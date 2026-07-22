;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop flow) — Concurrent ML style events (Reppy's "events",
;; guile-fibers' "operations") synchronized over the io_uring loop
;; from (letloop liburing low). Ported from the coop.scm design
;; sketch; see plans/v12/20260720-flow/README.md for the full design
;; and milestone plan. Implements FL-1 (base event algebra), FL-2
;; (choice), FL-3 (rendezvous channels), FL-4 (timeouts), and FL-5
;; (I/O events).
(library (letloop flow)

  (export make-flow flow? flow-wrap flow-guard flow-choice flow-perform

          make-flow-channel flow-channel? flow-put flow-get
          flow-put! flow-get!
          flow-same-channel-choice-condition?
          flow-same-channel-choice-channel

          flow-timeout flow-sleep

          flow-accept flow-read flow-write

          flow-spawn flow-run flow-stop

          ~check-flow-000/always-ready
          ~check-flow-000/wrap-order
          ~check-flow-000/guard
          ~check-flow-000/suspend-resume

          ~check-flow-001/choice-two-ready
          ~check-flow-001/choice-ready-or-never
          ~check-flow-001/nested-choice-flattens
          ~check-flow-001/block-fanout-race

          ~check-flow-002/ping-pong
          ~check-flow-003/n-producers-one-consumer
          ~check-flow-004/same-channel-choice-raises
          ~check-flow-004/compaction

          ~check-flow-005/get-or-timeout-put-first
          ~check-flow-005/get-or-timeout-timeout-first
          ~check-flow-005/losing-timeout-cancelled

          ~check-flow-006/echo-pair
          ~check-flow-006/read-or-timeout-leaves-fd-usable)

  (import (chezscheme)
          (letloop r999)
          (only (letloop cffi) bytevector-pointer)
          (letloop liburing low))

  ;; A <flow> is either:
  ;;
  ;;   type = 'base  — data unused; wrap/try/block are the event's own
  ;;                   post-synchronization transformer, non-blocking
  ;;                   poll, and blocking registration (§4.2).
  ;;   type = 'guard — data is a thunk that must produce a fresh event
  ;;                   on every synchronization attempt (§4.1); wrap/
  ;;                   try/block are unused, resolved via flow-flatten.
  ;;   type = 'choice — data is a vector of member events (possibly
  ;;                    themselves choices/guards); wrap/try/block are
  ;;                    unused, resolved via flow-flatten. flow-choice
  ;;                    is associative and does not eagerly flatten —
  ;;                    flow-flatten unwraps nesting at perform time.
  (define-record-type* <flow>
    (make-flow% type data wrap try block)
    flow?
    (type  flow-type)
    (data  flow-data)
    (wrap  flow-wrap-proc)
    (try   flow-try-proc)
    (block flow-block-proc))

  (define make-flow
    (lambda (wrap try block)
      (make-flow% 'base #f wrap try block)))

  (define flow-guard
    (lambda (thunk)
      (make-flow% 'guard thunk #f #f #f)))

  ;; Choice is associative; a single-event choice is left as a
  ;; 1-element choice rather than collapsed — flow-flatten treats it
  ;; identically to collapsing, so there is no observable difference
  ;; and no need to special-case it here.
  (define flow-choice
    (lambda events
      (make-flow% 'choice (list->vector events) #f #f #f)))

  (define flow-wrap
    (lambda (event proc)
      (case (flow-type event)
        ((base)
         (make-flow% 'base #f
                     (lambda (x) (proc ((flow-wrap-proc event) x)))
                     (flow-try-proc event)
                     (flow-block-proc event)))
        ((guard)
         (make-flow% 'guard
                     (lambda () (flow-wrap ((flow-data event)) proc))
                     #f #f #f))
        ((choice)
         (make-flow% 'choice
                     (vector-map (lambda (base) (flow-wrap base proc))
                                 (flow-data event))
                     #f #f #f))
        (else
         (error 'flow-wrap "unsupported flow type" (flow-type event))))))

  ;; Resolve EVENT down to the list of base events it synchronizes
  ;; over: a base is its own singleton flattening; a guard is resolved
  ;; by calling its thunk exactly once and flattening the result; a
  ;; choice recursively flattens its members (this is where nested
  ;; choices collapse, since choice is associative).
  (define flow-flatten
    (lambda (event)
      (case (flow-type event)
        ((base) (list event))
        ((guard) (flow-flatten ((flow-data event))))
        ((choice)
         (apply append (map flow-flatten (vector->list (flow-data event)))))
        (else
         (error 'flow-flatten "unsupported flow type" (flow-type event))))))

  (define flow-rotate
    (lambda (lst n)
      (if (or (null? lst) (fxzero? n))
          lst
          (append (list-tail lst n) (list-head lst n)))))

  ;; Sentinel distinguishing "no base was ready" from a legitimate #f
  ;; result value; opaque, compared with eq? only.
  (define %flow-not-ready (list 'not-ready))

  (define flow-poll
    (lambda (bases)
      (let ((n (length bases)))
        (let loop ((bs (flow-rotate bases (if (fxzero? n) 0 (random n)))))
          (if (null? bs)
              %flow-not-ready
              (let ((thunk ((flow-try-proc (car bs)))))
                (if thunk
                    ((flow-wrap-proc (car bs)) (thunk))
                    (loop (cdr bs)))))))))

  ;; Allocate one state box shared by every base, register (state
  ;; resume register-cancel!) with each base's block, and suspend the
  ;; current fiber. resume always defers through loop-spawn rather
  ;; than calling the parked continuation directly — the completing
  ;; side may itself be in the middle of a CQE drain (§4.3). box-cas!
  ;; guards against a base being resumed more than once (e.g. a losing
  ;; sibling whose completion arrives after the choice already
  ;; synched), and resume returns whether *this* call was the one that
  ;; won it — the state box is only ever transitioned here, never by a
  ;; block/try implementation directly, so a channel (say) can tell
  ;; whether the peer it just matched was still actually available.
  ;;
  ;; register-cancel! lets a block that submitted a real SQE (a
  ;; timeout, a read, ...) hand over a thunk that cancels it; the
  ;; instant any base wins, every registered cancel thunk fires —
  ;; including, harmlessly, the winner's own (§4.3 rule 3: cancelling
  ;; an already-completed op is a safe no-op at the kernel level, so
  ;; there is no need to track and exclude the winner specifically).
  ;;
  ;; Each base is handed its *own* resume — value flows through that
  ;; base's own wrap before reaching the shared inner resume, exactly
  ;; as flow-poll applies wrap on the ready path — so no block
  ;; implementation has to remember to wrap its own raw completion
  ;; value (a real io_uring res code, an object off a channel, ...).
  (define flow-block-and-wait
    (lambda (bases)
      (let ((state (box 'waiting))
            (cancels (box '())))
        (loop-abort
         (lambda (k)
           (define register-cancel!
             (lambda (thunk) (set-box! cancels (cons thunk (unbox cancels)))))
           (define resume
             (lambda (value)
               (and (box-cas! state 'waiting 'synched)
                    (begin
                      (for-each (lambda (thunk) (thunk)) (unbox cancels))
                      (loop-spawn (lambda () (k value)))
                      #t))))
           (for-each (lambda (base)
                       ((flow-block-proc base) state
                        (lambda (raw) (resume ((flow-wrap-proc base) raw)))
                        register-cancel!))
                     bases))))))

  (define flow-perform
    (lambda (event)
      (let ((bases (flow-flatten event)))
        (flow-check-same-channel-choice! bases)
        (let ((result (flow-poll bases)))
          (if (eq? result %flow-not-ready)
              (flow-block-and-wait bases)
              result)))))

  ;;------------------------------------------------------------
  ;; Channels (§4.4)
  ;;------------------------------------------------------------

  ;; A channel is two FIFOs of pending parties (waiting puts, waiting
  ;; pops) plus a counter driving periodic compaction. Rendezvous is
  ;; direct: a value only moves when a put and a get are both present
  ;; at the same time, there is no buffering.
  (define-record-type* <flow-channel>
    (make-flow-channel% puts pops gc-counter)
    flow-channel?
    (puts       flow-channel-puts  flow-channel-puts!)
    (pops       flow-channel-pops  flow-channel-pops!)
    (gc-counter flow-channel-gc-counter flow-channel-gc-counter!))

  (define make-flow-channel
    (lambda ()
      (make-flow-channel% '() '() 0)))

  ;; A pending party: the (possibly choice-shared) state box and
  ;; resume from flow-perform, plus — for puts only — the value being
  ;; offered. A party is dead once its state is no longer 'waiting;
  ;; dead parties are skipped by box-cas! failing and are eventually
  ;; dropped by compaction, not removed eagerly.
  (define-record-type* <flow-channel-entry>
    (make-flow-channel-entry state resume value)
    flow-channel-entry?
    (state  flow-channel-entry-state)
    (resume flow-channel-entry-resume)
    (value  flow-channel-entry-value))

  (define flow-channel-entry-waiting?
    (lambda (entry)
      (eq? (unbox (flow-channel-entry-state entry)) 'waiting)))

  (define %flow-channel-gc-threshold 1024)

  ;; Bump the shared gc-counter on every enqueue; once it reaches the
  ;; threshold, drop every entry from both FIFOs whose state is no
  ;; longer 'waiting and reset the counter (§4.4). Called after the
  ;; enqueue so a completed entry can be compacted the same round it
  ;; is finally observed as dead.
  (define flow-channel-bump-gc!
    (lambda (channel)
      (let ((n (fx+ 1 (flow-channel-gc-counter channel))))
        (if (fx>=? n %flow-channel-gc-threshold)
            (begin
              (flow-channel-puts! channel
                (filter flow-channel-entry-waiting? (flow-channel-puts channel)))
              (flow-channel-pops! channel
                (filter flow-channel-entry-waiting? (flow-channel-pops channel)))
              (flow-channel-gc-counter! channel 0))
            (flow-channel-gc-counter! channel n)))))

  ;; try and block never race each other within a single flow-perform
  ;; call — phase 1 is single-threaded and nothing yields between the
  ;; poll pass and the block pass, so the two-phase re-scan coop.scm
  ;; needed for its bare-thread arm is unnecessary here (§4.7); a
  ;; future multi-shard resume would need to reintroduce it.
  ;;
  ;; Claiming a peer means calling *its* resume, and resume itself
  ;; owns the state-box CAS (flow-block-and-wait) — try must not CAS
  ;; the peer's state box on its own first, or resume's own CAS would
  ;; find it already 'synched and silently refuse to wake the peer.
  ;; resume's #t/#f return is exactly "did I just win this peer".
  (define flow-put-try
    (lambda (channel obj)
      (lambda ()
        (let scan ((pops (flow-channel-pops channel)))
          (cond
           ((null? pops) #f)
           (((flow-channel-entry-resume (car pops)) obj)
            (lambda () (void)))
           (else (scan (cdr pops))))))))

  (define flow-put-block
    (lambda (channel obj)
      (lambda (state resume register-cancel!)
        (flow-channel-puts! channel
          (append (flow-channel-puts channel)
                  (list (make-flow-channel-entry state resume obj))))
        (flow-channel-bump-gc! channel))))

  (define flow-put
    (lambda (channel obj)
      (make-flow% 'base (cons 'flow-put channel)
                  (lambda (x) (void))
                  (flow-put-try channel obj)
                  (flow-put-block channel obj))))

  (define flow-get-try
    (lambda (channel)
      (lambda ()
        (let scan ((puts (flow-channel-puts channel)))
          (cond
           ((null? puts) #f)
           (((flow-channel-entry-resume (car puts)) (void))
            (let ((obj (flow-channel-entry-value (car puts))))
              (lambda () obj)))
           (else (scan (cdr puts))))))))

  (define flow-get-block
    (lambda (channel)
      (lambda (state resume register-cancel!)
        (flow-channel-pops! channel
          (append (flow-channel-pops channel)
                  (list (make-flow-channel-entry state resume #f))))
        (flow-channel-bump-gc! channel))))

  (define flow-get
    (lambda (channel)
      (make-flow% 'base (cons 'flow-get channel)
                  (lambda (x) x)
                  (flow-get-try channel)
                  (flow-get-block channel))))

  (define flow-put!
    (lambda (channel obj) (flow-perform (flow-put channel obj))))

  (define flow-get!
    (lambda (channel) (flow-perform (flow-get channel))))

  ;; A choice containing both a put and a get on the same channel can
  ;; never rendezvous with anything but itself and would deadlock;
  ;; reject it instead (§4.4). Only flow-put/flow-get tag their `data`
  ;; field this way, so the pair? check cannot misfire on a 'guard
  ;; event (data is a thunk) or a plain base (data is #f).
  (define-condition-type &flow-same-channel-choice &error
    make-flow-same-channel-choice-condition
    flow-same-channel-choice-condition?
    (channel flow-same-channel-choice-channel))

  (define flow-check-same-channel-choice!
    (lambda (bases)
      (let loop ((bases bases) (puts '()) (pops '()))
        (unless (null? bases)
          (let ((tag (flow-data (car bases))))
            (cond
             ((not (pair? tag)) (loop (cdr bases) puts pops))
             ((eq? (car tag) 'flow-put)
              (when (memq (cdr tag) pops)
                (raise (make-flow-same-channel-choice-condition (cdr tag))))
              (loop (cdr bases) (cons (cdr tag) puts) pops))
             ((eq? (car tag) 'flow-get)
              (when (memq (cdr tag) puts)
                (raise (make-flow-same-channel-choice-condition (cdr tag))))
              (loop (cdr bases) puts (cons (cdr tag) pops)))
             (else (loop (cdr bases) puts pops))))))))

  ;;------------------------------------------------------------
  ;; Timeouts (§4.5)
  ;;------------------------------------------------------------

  ;; try is always #f — a timeout is never already-elapsed at poll
  ;; time by construction. block preps IORING_OP_TIMEOUT directly
  ;; (mirroring loop-sleep's own prep, but parking the flow-perform
  ;; resume instead of a raw continuation) and registers a cancel
  ;; thunk that preps IORING_OP_TIMEOUT_REMOVE if this base loses.
  ;;
  ;; The removal's own completion needs no handler: whether the
  ;; timeout is cancelled or fires for real, the *original* op's CQE
  ;; still arrives exactly once (with -ECANCELED on a successful
  ;; removal), so the one handler registered below always runs
  ;; eventually and is the single place `ts` is freed — no separate
  ;; free-on-cancel path is needed.
  (define flow-timeout
    (lambda (seconds)
      (make-flow% 'base #f
                  (lambda (x) (void))
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (let* ((ring (loop-ring (loop-current)))
                           (id   (loop-alloc-id!))
                           (ns   (exact (round (* seconds 1000000000))))
                           (ts   (make-timespec (div ns 1000000000)
                                                 (mod ns 1000000000)))
                           (sqe  (io-uring-get-sqe ring)))
                      (io-uring-prep-timeout sqe (ftype-pointer-address ts) 0 0)
                      (io-uring-sqe-set-data64 sqe id)
                      (hashtable-set! (loop-handlers (loop-current)) id
                                      (lambda (res)
                                        (foreign-free (ftype-pointer-address ts))
                                        (resume res)))
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (io-uring-get-sqe ring)))
                           (io-uring-prep-timeout-remove csqe id 0)
                           (io-uring-sqe-set-data64 csqe (loop-alloc-id!))))))))))

  (define flow-sleep
    (lambda (seconds) (flow-perform (flow-timeout seconds))))

  ;;------------------------------------------------------------
  ;; I/O events (§4.5)
  ;;------------------------------------------------------------

  ;; A fresh, self-owned recv buffer per call rather than the loop's
  ;; shared provided-buffer ring: that ring's result lands in the
  ;; private %buf-data table inside (letloop liburing low), which
  ;; would need its own exported hook to reach from here, and a
  ;; plain io_uring_prep_recv into our own bytevector needs none —
  ;; the same tradeoff loop-write already makes for sends.
  (define %flow-read-buffer-size 65536)

  ;; try is always #f — nothing here can be polled without a real
  ;; completion. block preps a plain recv (no IOSQE_BUFFER_SELECT)
  ;; and registers a cancel thunk: an unstarted read has consumed
  ;; nothing, so losing a choice can cancel it outright (unlike
  ;; flow-write, see below).
  (define flow-read
    (lambda (fd)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (let* ((ring (loop-ring (loop-current)))
                           (id   (loop-alloc-id!))
                           (bv   (make-bytevector %flow-read-buffer-size))
                           (sqe  (io-uring-get-sqe ring)))
                      (lock-object bv)
                      (io-uring-prep-recv sqe fd (bytevector-pointer bv)
                                          (bytevector-length bv) 0)
                      (io-uring-sqe-set-data64 sqe id)
                      (hashtable-set! (loop-handlers (loop-current)) id
                                      (lambda (res)
                                        (unlock-object bv)
                                        (resume
                                         (cond
                                          ((fx<? res 0) #f)
                                          ((fxzero? res) #t)
                                          (else (subbytevector bv 0 res))))))
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (io-uring-get-sqe ring)))
                           (io-uring-prep-cancel64 csqe id 0)
                           (io-uring-sqe-set-data64 csqe (loop-alloc-id!))))))))))

  ;; No register-cancel! here, deliberately: once bytes have started
  ;; moving this event is committed (§4.5) — a losing choice must not
  ;; abandon a half-sent write, so the short-write retry loop keeps
  ;; running to completion in the background regardless of whether
  ;; this base already lost. resume's own box-cas! makes the eventual
  ;; final call a harmless no-op in that case, exactly like a losing
  ;; I/O base's late CQE (§4.3 rule 2).
  (define flow-write
    (lambda (fd bv)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (let ((ring (loop-ring (loop-current))))
                      (define submit!
                        (lambda (remaining)
                          (lock-object remaining)
                          (let ((id  (loop-alloc-id!))
                                (sqe (io-uring-get-sqe ring)))
                            (io-uring-prep-send sqe fd (bytevector-pointer remaining)
                                                (bytevector-length remaining) 0)
                            (io-uring-sqe-set-data64 sqe id)
                            (hashtable-set! (loop-handlers (loop-current)) id
                                            (lambda (res)
                                              (unlock-object remaining)
                                              (cond
                                               ((fx<=? res 0) (resume #f))
                                               ((fx=? res (bytevector-length remaining))
                                                (resume #t))
                                               (else (submit! (subbytevector remaining res)))))))))
                      (submit! bv))))))

  ;; try/block delegate directly to loop-accept-try/loop-accept-block
  ;; (§4.5's one hook into (letloop liburing low)). No register-cancel!
  ;; — the multishot is per-fd infrastructure, never torn down just
  ;; because one choice touching it loses; a client accepted after we
  ;; already lost is pushed back onto the accept backlog by
  ;; loop-accept-block itself rather than leaked. resume's return
  ;; value (#t on winning the CAS, #f otherwise) is exactly the
  ;; claim/decline signal loop-accept-block's handler expects.
  (define flow-accept
    (lambda (fd)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda ()
                    (let ((client (loop-accept-try fd)))
                      (and client (lambda () client))))
                  (lambda (state resume register-cancel!)
                    (loop-accept-block fd (lambda (client) (resume client)))))))

  (define flow-spawn loop-spawn)
  (define flow-run loop-run)
  (define flow-stop loop-stop)

  (include "letloop/flow.check.scm"))

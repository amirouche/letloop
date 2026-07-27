;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop flow) — Concurrent ML style events (Reppy's "events",
;; guile-fibers' "operations") synchronized over the io_uring loop
;; from (letloop liburing low). Ported from the coop.scm design
;; sketch; see plans/v12/20260720-flow/README.md for the full design
;; and milestone plan. Implements FL-1 (base event algebra), FL-2
;; (choice), FL-3 (rendezvous channels), FL-4 (timeouts), FL-5 (I/O
;; events), and FL-6 (a standalone consumer proof — see the check).
;; FL-7 (multi-shard: N OS threads, each its own ring, cross-shard
;; resume via IORING_OP_MSG_RING) was implemented and then dropped:
;; single-shard already saturates far beyond what any real handler
;; with actual per-request work needs, and no consumer in this tree
;; ever called flow-shard-spawn outside its own tests, while the
;; thread-parameter plumbing it required cost real throughput on the
;; single-shard path every other consumer actually runs (see the
;; commit that removed it). Scaling across cores is SO_REUSEPORT's
;; job now, not this library's.
(library (letloop flow)

  (export make-flow flow? flow-wrap flow-guard flow-choice flow-perform

          make-flow-channel flow-channel? flow-put flow-get
          flow-put! flow-get!
          flow-same-channel-choice-condition?
          flow-same-channel-choice-channel

          flow-timeout flow-sleep

          flow-accept flow-read flow-write

          flow-open flow-read-at flow-write-at flow-close
          O-RDONLY O-WRONLY O-RDWR O-CREAT O-TRUNC O-APPEND

          flow-spawn flow-run flow-stop

          flow-log flow-log-start! flow-log-stop! flow-log-drain!

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
          ~check-flow-006/read-or-timeout-leaves-fd-usable
          ~check-flow-006/request-loop-idle-timeout

          ~check-flow-009/file-write-read-roundtrip
          ~check-flow-009/chunked-read-until-eof
          ~check-flow-009/nonzero-offset
          ~check-flow-009/read-or-timeout-leaves-fd-usable
          ~check-flow-009/open-nonexistent-fails
          ~check-flow-009/open-loses-choice-no-fd-leak
          ~check-flow-009/close-under-choice-fd-actually-closed
          ~check-flow-009/close-while-read-in-flight

          ~check-flow-010/log-drain-roundtrip
          ~check-flow-010/timestamps-non-decreasing
          ~check-flow-010/start-reaches-destination
          ~check-flow-010/stop-flushes-remaining

          ~check-flow-011/sync-resume-runs-later-cancels)

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
  ;; Lock-free lists (coop.scm layer 1, with defect 1 fixed: the
  ;; original box-cons! CASed against a free variable `lst` instead of
  ;; a snapshot of (unbox box); this one snapshots first). Safe for
  ;; concurrent push from multiple OS threads at once, unlike a plain
  ;; mutable field — needed once a channel or a shard's cross-resume
  ;; mailbox (§4.7) can be touched from more than one shard.
  ;;------------------------------------------------------------

  (define flow-box-cons!
    (lambda (box item)
      (let ((lst (unbox box)))
        (unless (box-cas! box lst (cons item lst))
          (flow-box-cons! box item)))))

  ;; Atomically swap BOX's list for '(), returning whatever was there.
  (define flow-box-drain!
    (lambda (box)
      (let ((lst (unbox box)))
        (if (box-cas! box lst '())
            lst
            (flow-box-drain! box)))))

  (define flow-box-increment!
    (lambda (box)
      (let ((n (unbox box)))
        (if (box-cas! box n (fx+ n 1))
            (fx+ n 1)
            (flow-box-increment! box)))))

  ;;------------------------------------------------------------
  ;; Channels (§4.4)
  ;;------------------------------------------------------------

  ;; A channel is two lock-free lists of pending parties (waiting
  ;; puts, waiting pops) plus a counter driving periodic compaction.
  ;; Rendezvous is direct: a value only moves when a put and a get are
  ;; both present at the same time, there is no buffering. The lists
  ;; are box-cas!-protected rather than plain mutable fields so a
  ;; channel can safely be shared across shards (§4.7) — a fiber on
  ;; any shard may enqueue into or scan either list at any time.
  (define-record-type* <flow-channel>
    (make-flow-channel% puts pops gc-counter)
    flow-channel?
    (puts       flow-channel-puts)
    (pops       flow-channel-pops)
    (gc-counter flow-channel-gc-counter))

  (define make-flow-channel
    (lambda ()
      (make-flow-channel% (box '()) (box '()) (box 0))))

  ;; A pending party: the (possibly choice-shared) state box and
  ;; resume from flow-perform, plus — for puts only — the value being
  ;; offered — plus CLAIMED, a channel-local guard independent of
  ;; STATE (see flow-channel-entry-claim! below, and the lost-wakeup
  ;; fix in flow-put-block/flow-get-block). A party is dead once its
  ;; state is no longer 'waiting; dead parties are skipped by resume's
  ;; own CAS failing and are eventually dropped by compaction, not
  ;; removed eagerly.
  (define-record-type* <flow-channel-entry>
    (make-flow-channel-entry state resume value claimed)
    flow-channel-entry?
    (state   flow-channel-entry-state)
    (resume  flow-channel-entry-resume)
    (value   flow-channel-entry-value)
    (claimed flow-channel-entry-claimed))

  ;; Temporary diagnostic, enabled by LETLOOP_FLOW_TRACE=1: every
  ;; channel park/resume prints one line, tagging entries and channels
  ;; with small sequential ids, so a hang's final state shows exactly
  ;; which fibers are parked on which channels with no matching peer.
  (define %flow-trace? (and (getenv "LETLOOP_FLOW_TRACE") #t))
  (define %flow-trace-entry-counter (box 0))
  (define %flow-trace-channel-ids (make-weak-eq-hashtable))
  (define %flow-trace-channel-counter (box 0))

  (define %flow-trace-channel-id
    (lambda (channel)
      (or (hashtable-ref %flow-trace-channel-ids channel #f)
          (let ((id (flow-box-increment! %flow-trace-channel-counter)))
            (hashtable-set! %flow-trace-channel-ids channel id)
            id))))

  (define %flow-trace!
    (lambda parts
      (when %flow-trace?
        (for-each (lambda (p) (display p (current-error-port))) parts)
        (newline (current-error-port))
        (flush-output-port (current-error-port)))))

  (define %flow-trace-entry-ids (make-weak-eq-hashtable))

  (define %flow-trace-entry-id
    (lambda (entry)
      (or (hashtable-ref %flow-trace-entry-ids entry #f)
          (let ((id (flow-box-increment! %flow-trace-entry-counter)))
            (hashtable-set! %flow-trace-entry-ids entry id)
            id))))

  (define (make-flow-channel-entry* state resume value)
    (make-flow-channel-entry state resume value (box #f)))

  (define flow-channel-entry-waiting?
    (lambda (entry)
      (eq? (unbox (flow-channel-entry-state entry)) 'waiting)))

  ;; Exclusive right to attempt (entry-resume entry): every call site
  ;; that might call entry-resume — flow-put-try/flow-get-try's normal
  ;; discovery, and flow-put-block/flow-get-block's own post-register
  ;; rescan below — must win this CAS first. As long as that's
  ;; consistently true, a claim! win guarantees the entry's underlying
  ;; state is still 'waiting (nobody else has "permission" to have
  ;; resumed it), so the subsequent resume call can never spuriously
  ;; fail and strand the entry claimed-but-not-actually-resumed.
  (define flow-channel-entry-claim!
    (lambda (entry)
      (box-cas! (flow-channel-entry-claimed entry) #f #t)))

  (define %flow-channel-gc-threshold 1024)

  ;; Atomically filter dead entries out of BOX's list; retries against
  ;; a fresh snapshot if a concurrent push raced ahead of us, losing
  ;; only the wasted filter work, never an entry.
  (define flow-channel-compact!
    (lambda (box)
      (let ((lst (unbox box)))
        (unless (box-cas! box lst (filter flow-channel-entry-waiting? lst))
          (flow-channel-compact! box)))))

  ;; Bump the shared gc-counter on every enqueue; once it reaches the
  ;; threshold, drop every dead entry from both lists and reset the
  ;; counter (§4.4). If a concurrent bump also crossed the threshold
  ;; and reset first, this reset attempt just no-ops (box-cas! against
  ;; a now-stale N) rather than clobbering their progress — compaction
  ;; still ran, it just isn't perfectly deduplicated under concurrent
  ;; crossings, which is fine for a maintenance operation.
  (define flow-channel-bump-gc!
    (lambda (channel)
      (let ((n (flow-box-increment! (flow-channel-gc-counter channel))))
        (when (fx>=? n %flow-channel-gc-threshold)
          (flow-channel-compact! (flow-channel-puts channel))
          (flow-channel-compact! (flow-channel-pops channel))
          (box-cas! (flow-channel-gc-counter channel) n 0)))))

  ;; try and block never race each other within a single flow-perform
  ;; call on one shard — nothing yields between the poll pass and the
  ;; block pass — so the two-phase re-scan coop.scm needed for its
  ;; bare-thread arm is unnecessary here; a *different* shard's put or
  ;; get can still land in between, which is exactly why the lists
  ;; above are lock-free rather than plain mutable fields.
  ;;
  ;; Claiming a peer means winning flow-channel-entry-claim! on it,
  ;; THEN calling its resume — resume itself owns the state-box CAS
  ;; (flow-block-and-wait), but claim! is what makes that CAS race-free
  ;; against a second concurrent claimant (see the lost-wakeup fix in
  ;; flow-put-block/flow-get-block below): try must not skip claim! and
  ;; call resume directly, or two concurrent tries could both "win" the
  ;; same peer's resume call racing each other, and a block's own
  ;; post-register rescan could double-claim an entry that a normal
  ;; try is concurrently discovering. resume's own #t/#f return remains
  ;; "did I just win this peer" for the caller.
  (define flow-put-try
    (lambda (channel obj)
      (lambda ()
        (let scan ((pops (unbox (flow-channel-pops channel))))
          (cond
           ((null? pops) #f)
           ((and (flow-channel-entry-waiting? (car pops))
                 (flow-channel-entry-claim! (car pops))
                 ((flow-channel-entry-resume (car pops)) obj))
            (%flow-trace! "put-try hit e" (%flow-trace-entry-id (car pops))
                          " ch" (%flow-trace-channel-id channel))
            (lambda () (void)))
           (else (scan (cdr pops))))))))

  ;; Lost-wakeup fix: try-then-block (here and in flow-get-block) has a
  ;; gap — a concurrent peer's OWN try can run before this push and
  ;; therefore miss this entry, while THIS side's earlier try (in
  ;; flow-perform, before falling through to block) can equally have
  ;; missed an equally-fresh peer registration. Without a re-check,
  ;; both sides would register and wait forever with nothing left to
  ;; discover either one — no compaction or GC path ever revisits a
  ;; pair like that. So: after registering, claim! ourselves (so no
  ;; concurrent try can complete us out from under this rescan), then
  ;; scan the peer list once more; a match found here is claimed and
  ;; resumed exactly like a normal try would, and we complete our own
  ;; entry directly (same resume closure a peer's try would have
  ;; called). No match: release our own claim so a future normal try
  ;; can still discover and resume us — this rescan changes nothing
  ;; about our own entry's state if it comes up empty.
  (define flow-put-block
    (lambda (channel obj)
      (lambda (state resume register-cancel!)
        (let ((entry (make-flow-channel-entry* state resume obj)))
          (%flow-trace! "put-park e" (%flow-trace-entry-id entry)
                        " ch" (%flow-trace-channel-id channel))
          (flow-box-cons! (flow-channel-puts channel) entry)
          (flow-channel-bump-gc! channel)
          (when (flow-channel-entry-claim! entry)
            (let scan ((pops (unbox (flow-channel-pops channel))))
              (cond
               ((null? pops)
                (set-box! (flow-channel-entry-claimed entry) #f))
               ((and (flow-channel-entry-waiting? (car pops))
                     (flow-channel-entry-claim! (car pops))
                     ((flow-channel-entry-resume (car pops)) obj))
                (%flow-trace! "put-block rendezvous e"
                              (%flow-trace-entry-id entry)
                              " with e" (%flow-trace-entry-id (car pops)))
                ((flow-channel-entry-resume entry) (void)))
               (else (scan (cdr pops))))))))))

  (define flow-put
    (lambda (channel obj)
      (make-flow% 'base (cons 'flow-put channel)
                  (lambda (x) (void))
                  (flow-put-try channel obj)
                  (flow-put-block channel obj))))

  (define flow-get-try
    (lambda (channel)
      (lambda ()
        (let scan ((puts (unbox (flow-channel-puts channel))))
          (cond
           ((null? puts) #f)
           ((and (flow-channel-entry-waiting? (car puts))
                 (flow-channel-entry-claim! (car puts))
                 ((flow-channel-entry-resume (car puts)) (void)))
            (%flow-trace! "get-try hit e" (%flow-trace-entry-id (car puts))
                          " ch" (%flow-trace-channel-id channel))
            (let ((obj (flow-channel-entry-value (car puts))))
              (lambda () obj)))
           (else (scan (cdr puts))))))))

  ;; Mirror of flow-put-block's lost-wakeup fix; see its comment.
  (define flow-get-block
    (lambda (channel)
      (lambda (state resume register-cancel!)
        (let ((entry (make-flow-channel-entry* state resume #f)))
          (%flow-trace! "get-park e" (%flow-trace-entry-id entry)
                        " ch" (%flow-trace-channel-id channel))
          (flow-box-cons! (flow-channel-pops channel) entry)
          (flow-channel-bump-gc! channel)
          (when (flow-channel-entry-claim! entry)
            (let scan ((puts (unbox (flow-channel-puts channel))))
              (cond
               ((null? puts)
                (set-box! (flow-channel-entry-claimed entry) #f))
               ((and (flow-channel-entry-waiting? (car puts))
                     (flow-channel-entry-claim! (car puts))
                     ((flow-channel-entry-resume (car puts)) (void)))
                (%flow-trace! "get-block rendezvous e"
                              (%flow-trace-entry-id entry)
                              " with e" (%flow-trace-entry-id (car puts)))
                ((flow-channel-entry-resume entry)
                 (flow-channel-entry-value (car puts))))
               (else (scan (cdr puts))))))))))

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
                           (sqe  (loop-get-sqe ring)))
                      (io-uring-prep-timeout sqe (ftype-pointer-address ts) 0 0)
                      (io-uring-sqe-set-data64 sqe id)
                      (hashtable-set! (loop-handlers (loop-current)) id
                                      (lambda (res)
                                        (foreign-free (ftype-pointer-address ts))
                                        (resume res)))
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (loop-get-sqe ring)))
                           (io-uring-prep-timeout-remove csqe id 0)
                           (io-uring-sqe-set-data64 csqe (loop-alloc-id!))))))))))

  (define flow-sleep
    (lambda (seconds) (flow-perform (flow-timeout seconds))))

  ;;------------------------------------------------------------
  ;; I/O events (§4.5)
  ;;------------------------------------------------------------

  ;; Uses the loop's shared provided-buffer ring (the same one
  ;; loop-read draws from) instead of a fresh self-owned bytevector:
  ;; a plain per-call allocation + lock-object/unlock-object pin
  ;; measurably regressed http/server's hot path once every
  ;; keep-alive read started racing through flow-choice (each read
  ;; was already a second SQE alongside flow-timeout's; a private
  ;; 64KiB alloc+pin on top of that made it worse for no benefit —
  ;; typical requests fit easily in the ring's loop-buf-ring-buf-size
  ;; buffers). loop-run-once's CQE drain already copies the ring
  ;; buffer's bytes into a bytevector and stashes it, keyed by
  ;; completion id, whenever IORING_CQE_F_BUFFER is set, so the
  ;; handler below just collects it via loop-buf-data-take! instead
  ;; of a bv it manages itself.
  (define flow-read
    (lambda (fd)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (let* ((ring (loop-ring (loop-current)))
                           (id   (loop-alloc-id!))
                           (sqe  (loop-get-sqe ring)))
                      (io-uring-prep-recv sqe fd 0 (loop-buf-ring-buf-size) 0)
                      (io-uring-sqe-set-flags sqe IOSQE-BUFFER-SELECT)
                      (io-uring-sqe-set-buf-group sqe (loop-buf-ring-bgid))
                      (io-uring-sqe-set-data64 sqe id)
                      (hashtable-set! (loop-handlers (loop-current)) id
                                      (lambda (res)
                                        (resume
                                         (cond
                                          ((fx<? res 0) (loop-buf-data-take! id) #f)
                                          ((fxzero? res) (loop-buf-data-take! id) #t)
                                          (else (loop-buf-data-take! id))))))
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (loop-get-sqe ring)))
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
                                (sqe (loop-get-sqe ring)))
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

  ;;------------------------------------------------------------
  ;; File I/O events (§4.5, regular-file variant)
  ;;------------------------------------------------------------

  ;; flow-read/flow-write above wrap recv/send, which are socket-only
  ;; syscalls (ENOTSOCK on a regular file) with a fixed 64K internal
  ;; buffer. These four wrap openat/read/write/close instead: chunked,
  ;; with an explicit per-call size and an explicit per-call offset,
  ;; since a regular-file read needs a position and these primitives
  ;; deliberately keep no cursor state of their own — a caller doing
  ;; sequential chunked reads tracks and increments its own offset.
  ;;
  ;; Each is the same make-flow% skeleton as flow-read: try is always
  ;; #f (nothing here is pollable without a real completion), block
  ;; preps exactly one SQE, registers a completion handler in the
  ;; loop's handler table, and — where abandoning the op is safe —
  ;; registers a cancel thunk so a losing choice tears it down.
  ;;
  ;; fd is a plain integer throughout, like flow-accept's client and
  ;; loop-connect's result; there is no wrapper record, no guardian and
  ;; no dynamic-wind. Callers close explicitly, on both the normal and
  ;; the error path (the established idiom — see (letloop tls uring)
  ;; and (letloop postgresql base), where dynamic-wind is rejected
  ;; outright as unsafe for this suspend/resume model).
  ;;
  ;; Failures surface as #f rather than a raised condition, matching
  ;; flow-read/flow-write. That is not just convention: a completion
  ;; handler runs on whichever stack drained the CQE, never on the
  ;; parked fiber's, so a raise from here would unwind the wrong
  ;; context entirely. #f is unambiguous — every success value is a
  ;; non-negative fixnum, a bytevector, or 'eof.

  ;; open(2) flags, so callers need not hardcode the numeric values.
  ;; O-APPEND caveat: Linux pwrite(2) — and therefore flow-write-at —
  ;; ignores the offset on an O_APPEND fd and appends regardless.
  (define O-RDONLY 0)
  (define O-WRONLY 1)
  (define O-RDWR   2)
  (define O-CREAT  #o100)
  (define O-TRUNC  #o1000)
  (define O-APPEND #o2000)

  (define %flow-at-fdcwd -100)

  ;; A NUL-terminated copy of STR as a bytevector, so the path can be
  ;; locked and handed to the kernel by pointer; see flow-open.
  (define %flow-c-string
    (lambda (str)
      (let* ((bytes (string->utf8 str))
             (n     (bytevector-length bytes))
             (out   (make-bytevector (fx+ n 1) 0)))
        (bytevector-copy! bytes 0 out 0 n)
        out)))

  ;; Yields the new fd (a non-negative fixnum) or #f on failure —
  ;; ENOENT on a missing path without O-CREAT, EACCES, ... all land on
  ;; #f rather than hanging or yielding a negative "fd".
  ;;
  ;; The path is a locked bytevector passed to io-uring-prep-openat-
  ;; pointer rather than an FFI `string` argument: preparing an SQE
  ;; only records the path pointer, and the kernel dereferences it at
  ;; submit time — a later loop tick — by which point the C copy an
  ;; FFI `string` allocates has long been freed. lock-object also keeps
  ;; the collector from moving it in the meantime; the handler unlocks
  ;; it, on every outcome, exactly as flow-timeout frees its timespec.
  ;;
  ;; register-cancel! is safe here (an openat that never ran opened
  ;; nothing), but the cancel can still lose the race — so if this base
  ;; already lost the choice and the open succeeded anyway, close the
  ;; fd nobody now owns instead of leaking it. resume's #t/#f return is
  ;; the "did I win" signal, the same one loop-accept-block uses to
  ;; decide whether a client was claimed or must be pushed back.
  (define flow-open
    (lambda (path flags mode)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (let* ((ring  (loop-ring (loop-current)))
                           (id    (loop-alloc-id!))
                           (cpath (%flow-c-string path))
                           (sqe   (loop-get-sqe ring)))
                      (lock-object cpath)
                      (io-uring-prep-openat-pointer sqe %flow-at-fdcwd
                                                    (bytevector-pointer cpath)
                                                    flags mode)
                      (io-uring-sqe-set-data64 sqe id)
                      (hashtable-set! (loop-handlers (loop-current)) id
                                      (lambda (res)
                                        (unlock-object cpath)
                                        (let ((won (resume (and (fx>=? res 0) res))))
                                          (when (and (not won) (fx>=? res 0))
                                            ;; This runs inside the CQE drain, under
                                            ;; loop-apply's catch-all guard: if the
                                            ;; ring is so loaded that loop-get-sqe
                                            ;; raises even after its flush-retry, a
                                            ;; bare raise would be silently swallowed
                                            ;; and the orphan fd leaked. Retry next
                                            ;; tick instead — by then the tick's
                                            ;; submit has drained the queue.
                                            (let retry ()
                                              (guard (ex (else (loop-spawn retry)))
                                                (let ((csqe (loop-get-sqe ring)))
                                                  (io-uring-prep-close csqe res)
                                                  (io-uring-sqe-set-data64 csqe (loop-alloc-id!)))))))))
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (loop-get-sqe ring)))
                           (io-uring-prep-cancel64 csqe id 0)
                           (io-uring-sqe-set-data64 csqe (loop-alloc-id!))))))))))

  ;; Yields a bytevector of at most COUNT bytes, 'eof at end of file
  ;; (res = 0), or #f on error. 'eof rather than an empty bytevector so
  ;; a read-until-EOF loop can dispatch on it directly instead of
  ;; special-casing zero-length results.
  ;;
  ;; A short read (res < COUNT) is a legitimate result, not an error:
  ;; the last chunk of a file is normally short. Callers advance their
  ;; own offset by the length actually returned.
  ;;
  ;; COUNT must be >= 1: read(2) returns 0 for a zero-length buffer,
  ;; indistinguishable from end-of-file, so a count of 0 would yield a
  ;; spurious 'eof mid-file — rejected here, at event-construction
  ;; time on the caller's own stack, where the raise is loud (a raise
  ;; from inside block would be swallowed by the loop's guard and
  ;; strand the fiber).
  ;;
  ;; register-cancel! as in flow-read: an abandoned read has consumed
  ;; nothing — and for a regular file, positioned reads consume nothing
  ;; even when they do run, so a losing sibling leaves the fd exactly
  ;; where it was.
  (define flow-read-at
    (lambda (fd offset count)
      (unless (and (fixnum? count) (fx>=? count 1))
        (error 'flow-read-at "count must be a positive fixnum" count))
      (unless (and (fixnum? offset) (fx>=? offset 0))
        (error 'flow-read-at "offset must be a non-negative fixnum" offset))
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (let* ((ring (loop-ring (loop-current)))
                           (id   (loop-alloc-id!))
                           (bv   (make-bytevector count))
                           (sqe  (loop-get-sqe ring)))
                      (lock-object bv)
                      (io-uring-prep-read sqe fd (bytevector-pointer bv) count offset)
                      (io-uring-sqe-set-data64 sqe id)
                      (hashtable-set! (loop-handlers (loop-current)) id
                                      (lambda (res)
                                        (unlock-object bv)
                                        (resume
                                         (cond
                                          ((fx<? res 0) #f)
                                          ((fxzero? res) 'eof)
                                          ((fx=? res count) bv)
                                          (else (subbytevector bv 0 res))))))
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (loop-get-sqe ring)))
                           (io-uring-prep-cancel64 csqe id 0)
                           (io-uring-sqe-set-data64 csqe (loop-alloc-id!))))))))))

  ;; Yields the number of bytes written (a fixnum, possibly short of
  ;; (bytevector-length bv)) or #f on error. Unlike flow-write there is
  ;; no retry loop: with an explicit offset a short write is trivially
  ;; resumable by the caller, and reporting it is more useful than
  ;; silently looping.
  ;;
  ;; No register-cancel!, deliberately, for the same reason flow-write
  ;; has none: once bytes may have hit the file this event is
  ;; committed, and a losing choice must not abandon a half-written
  ;; chunk. resume's own box-cas! makes the eventual completion a
  ;; harmless no-op in that case.
  (define flow-write-at
    (lambda (fd offset bv)
      ;; Same construction-time validation as flow-read-at: a negative
      ;; offset would only blow up later, at prep time inside the
      ;; loop's swallow-all guard, stranding the fiber silently.
      (unless (and (fixnum? offset) (fx>=? offset 0))
        (error 'flow-write-at "offset must be a non-negative fixnum" offset))
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (let* ((ring (loop-ring (loop-current)))
                           (id   (loop-alloc-id!))
                           (sqe  (loop-get-sqe ring)))
                      (lock-object bv)
                      (io-uring-prep-write sqe fd (bytevector-pointer bv)
                                           (bytevector-length bv) offset)
                      (io-uring-sqe-set-data64 sqe id)
                      (hashtable-set! (loop-handlers (loop-current)) id
                                      (lambda (res)
                                        (unlock-object bv)
                                        (resume (and (fx>=? res 0) res)))))))))

  ;; Yields 0 on success, #f on error. Delegates to loop-close-block,
  ;; which is loop-close's bookkeeping (resume anything parked on this
  ;; fd with a synthetic cancellation, drop it from the loop's tracking
  ;; tables, cancel in-flight ops, then submit IORING_OP_CLOSE) with
  ;; the completion handler supplied rather than the caller's
  ;; continuation — none of which is socket-specific, so file fds need
  ;; no separate teardown. A fiber that is not composing close with
  ;; anything can equally well call loop-close directly.
  ;;
  ;; No register-cancel!: a close in flight must run to completion or
  ;; the fd leaks.
  ;;
  ;; Caveat under flow-choice — sharper than flow-write's analogous
  ;; committed-at-block semantics: the choice's result does NOT tell
  ;; you whether the close happened. If a sibling base is already
  ;; ready at poll time, block never runs and the fd is still open; if
  ;; the choice reaches the block phase, the close is committed right
  ;; there even when a sibling then wins, and the winning value is the
  ;; sibling's either way. So never "retry" flow-close after losing a
  ;; choice: the descriptor may already be closed and its number
  ;; reused, and the retry would close a stranger's fd. Only compose
  ;; flow-close into a choice when the caller treats fd as dead the
  ;; moment the choice is performed, whatever the outcome — otherwise
  ;; perform it alone (or call loop-close), where the result is
  ;; unambiguous.
  (define flow-close
    (lambda (fd)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (loop-close-block fd
                                      (lambda (res)
                                        (resume (and (fx>=? res 0) res))))))))

  (define flow-spawn loop-spawn)
  (define flow-run loop-run)
  (define flow-stop loop-stop)

  ;;------------------------------------------------------------
  ;; flow-log: structured runtime logging
  ;;------------------------------------------------------------
  ;;
  ;; Every entry is (cons timestamp sexp), TIMESTAMP coming from
  ;; loop-jiffy -- the event loop's per-tick cached jiffy (one real
  ;; clock syscall per tick, see low.scm), never a fresh jiffy-current
  ;; syscall per flow-log call.
  ;;
  ;; Accumulation reuses flow-box-cons!/flow-box-drain!, the same
  ;; lock-free primitive already backing channel put/get queues, so
  ;; concurrent logging from any number of OS threads never races.

  ;; Registry of every OS thread's own log box. A single process-wide
  ;; box -- not a thread-parameter, since every thread that logs pushes
  ;; ITS OWN box into this ONE shared box -- accumulated with
  ;; flow-box-cons!, so concurrent registration from any number of
  ;; threads never races and never drops a registration.
  (define flow-log-registry (box '()))

  ;; This OS thread's own log accumulator. A thread-parameter: a plain
  ;; global here would let two OS threads logging concurrently clobber
  ;; each other's entries.
  (define flow-log-box (make-thread-parameter #f))

  ;; Lazily create and register this thread's log box on first
  ;; flow-log call, so flow-log works from any OS thread with no
  ;; separate explicit setup step. Only this thread ever writes its
  ;; OWN flow-log-box parameter value, so the check-then-set here
  ;; needs no CAS of its own; flow-box-cons! below is what makes the
  ;; registry push itself safe against concurrent registration from
  ;; other threads.
  (define flow-log-ensure-box!
    (lambda ()
      (or (flow-log-box)
          (let ((b (box '())))
            (flow-log-box b)
            (flow-box-cons! flow-log-registry b)
            b))))

  ;; Accumulate SEXP into this thread's log box, timestamped with the
  ;; current tick's cached loop-jiffy.
  (define flow-log
    (lambda (sexp)
      (flow-box-cons! (flow-log-ensure-box!) (cons (loop-jiffy) sexp))))

  ;; Drain the registry and every registered box, returning every
  ;; pending entry: oldest-first within each shard's own box, boxes
  ;; concatenated in registry order (not globally timestamp-sorted --
  ;; a caller wanting strict cross-shard temporal order can sort the
  ;; result itself).
  ;;
  ;; flow-box-drain! on the registry is itself race-free against
  ;; concurrent registrations (a new shard registering mid-drain either
  ;; lands in the drained snapshot or is still there afterward -- see
  ;; flow-box-cons!/flow-box-drain!'s CAS retry above), but draining it
  ;; empties it as a side effect; since registration happens once per
  ;; thread for that thread's whole lifetime (not a one-shot queue),
  ;; every drained box is pushed straight back in below so it remains
  ;; discoverable by the next drain.
  (define flow-log-drain!
    (lambda ()
      (let ((boxes (flow-box-drain! flow-log-registry)))
        (for-each (lambda (b) (flow-box-cons! flow-log-registry b)) boxes)
        (apply append (map (lambda (b) (reverse (flow-box-drain! b))) boxes)))))

  ;; Always (current-error-port) -- read at flush time, not captured
  ;; once at flow-log-start! time, so a caller that reparameterizes
  ;; current-error-port (e.g. a test capturing it, or a supervisor
  ;; redirecting it) is honored on the next cycle. Plain synchronous
  ;; Chez port I/O rather than flow-open/flow-write-at: this thread is
  ;; not on the async event-loop's critical path -- it is not even
  ;; necessarily running a loop at all, since flow-log must work from
  ;; bare threads too -- so there is nothing to gain from routing a
  ;; periodic background flush through io_uring, and doing so would
  ;; force this thread to also loop-new/loop-run its own ring for no
  ;; benefit.
  (define flow-log-write-entries!
    (lambda (entries)
      (unless (null? entries)
        (let ((port (current-error-port)))
          (for-each (lambda (entry) (write entry port) (newline port))
                    entries)
          (flush-output-port port)))))

  ;; flow-log-start!/flow-log-stop! state: exactly one dedicated flush
  ;; thread, not one per shard (a per-shard flush thread would defeat
  ;; the point of a single drain-and-flush cadence). stopped? starts #t
  ;; ("no flush thread currently running") so a flow-log-stop! with no
  ;; matching flow-log-start! returns immediately instead of hanging.
  (define flow-log-stop-requested? (box #f))
  (define flow-log-stopped? (box #t))

  ;; Granularity at which the flush thread re-checks
  ;; flow-log-stop-requested?, independent of PERIOD-SECONDS -- so
  ;; flow-log-stop! is noticed promptly even when the flush period
  ;; itself is long, rather than only at the next whole period
  ;; boundary.
  (define %flow-log-poll-interval 0.01)

  ;; Spawn exactly one dedicated OS thread that, every PERIOD-SECONDS,
  ;; drains every registered shard's log box (via flow-log-drain!) and
  ;; flushes the merged result to (current-error-port). Calling this
  ;; again before flow-log-stop! spawns a second, competing flush
  ;; thread -- draining itself stays correct either way
  ;; (flow-box-drain! never double-delivers the same entry), but
  ;; running two at once is not a supported configuration.
  (define flow-log-start!
    (lambda (period-seconds)
      (set-box! flow-log-stop-requested? #f)
      (set-box! flow-log-stopped? #f)
      (let ((ticks (fxmax 1 (exact (round (/ period-seconds %flow-log-poll-interval))))))
        (fork-thread
         (lambda ()
           (let lp ()
             (let wait-ticks ((n 0))
               (unless (or (unbox flow-log-stop-requested?) (fx>=? n ticks))
                 (sleep (make-time 'time-duration
                                   (exact (round (* %flow-log-poll-interval 1000000000)))
                                   0))
                 (wait-ticks (fx+ n 1))))
             (flow-log-write-entries! (flow-log-drain!))
             (if (unbox flow-log-stop-requested?)
                 (set-box! flow-log-stopped? #t)
                 (lp))))))
      (void)))

  ;; Signal the flush thread to stop and block the CALLER until it has
  ;; performed one final drain-and-flush and actually exited its loop,
  ;; so nothing logged before the stop request is lost on shutdown.
  (define flow-log-stop!
    (lambda ()
      (set-box! flow-log-stop-requested? #t)
      (let wait ()
        (unless (unbox flow-log-stopped?)
          (sleep (make-time 'time-duration 10000000 0))
          (wait)))))

  (include "letloop/flow.check.scm"))

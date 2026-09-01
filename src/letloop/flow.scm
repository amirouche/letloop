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
          flow-put! flow-get! flow-put-try!
          ;; Diagnostic only: raw internal list lengths, to tell apart
          ;; "logically empty" (put-count = get-count) from "channel
          ;; has released its internal state" -- see the entries in
          ;; letloop TODO.md for the full diagnosis this was built for
          ;; (a downstream indexing pipeline's unbounded RSS growth on
          ;; a large corpus pass).
          flow-channel-puts-length flow-channel-pops-length
          flow-same-channel-choice-condition?
          flow-same-channel-choice-channel

          flow-timeout flow-sleep

          flow-accept flow-read flow-write

          flow-open flow-read-at flow-write-at flow-close
          O-RDONLY O-WRONLY O-RDWR O-CREAT O-TRUNC O-APPEND

          flow-spawn flow-run flow-stop

          flow-log flow-log-start! flow-log-stop! flow-log-drain!

          flow-worker-start! flow-worker-stop! flow-worker-call
          flow-worker-io flow-worker-current?
          ~check-flow-worker-runs-off-loop
          ~check-flow-worker-propagates-raise
          ~check-flow-worker-overlaps
          ~check-flow-worker-io-runs-on-loop
          ~check-flow-worker-ring-event-off-loop
          ~check-flow-worker-multiple-values
          ~check-flow-channel-crosses-threads

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
          ~check-flow-006/accept-cancel-leaves-listener-usable
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

          ~check-flow-011/sync-resume-runs-later-cancels
          ~check-flow-011/raising-cancel-does-not-lose-fiber
          ~check-flow-011/winner-own-cancel-not-fired
          ~check-flow-011/block-raise-reaches-the-caller
          ~check-flow-011/block-raise-does-not-strand-a-worker
          ~check-flow-011/lost-get-does-not-eat-a-value)

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
  ;; instant any base wins, every LOSER's cancel thunk fires. The
  ;; winner's own is skipped: cancelling an already-completed op is a
  ;; safe no-op at the kernel level (§4.3 rule 3), but it still costs
  ;; a wasted SQE plus its -ENOENT CQE on every operation completed
  ;; through this path, so each cancel is tagged with its
  ;; registration and the winning registration excludes itself. The
  ;; tag is per REGISTRATION, not per base object, so the same base
  ;; appearing twice in one choice still gets its losing twin's
  ;; cancel fired.
  ;;
  ;; Each base is handed its *own* resume — value flows through that
  ;; base's own wrap before reaching the shared inner resume, exactly
  ;; as flow-poll applies wrap on the ready path — so no block
  ;; implementation has to remember to wrap its own raw completion
  ;; value (a real io_uring res code, an object off a channel, ...).
  ;; Off-loop callers cannot loop-abort: a worker thread is not a
  ;; fiber, there is no prompt to abort to. It blocks on a condition
  ;; variable instead, and its resume fills a slot and broadcasts
  ;; rather than spawning a continuation. Everything else -- the state
  ;; box, the CAS that picks one winner, the cancel bookkeeping -- is
  ;; shared with the fiber path below, so a rendezvous between a worker
  ;; and a fiber works in either direction with one implementation of
  ;; the protocol.
  ;; A raise from a base's block procedure, on its way back to the
  ;; party that is waiting on this synchronization.
  ;;
  ;; Registration never runs in the waiter's own dynamic extent. On the
  ;; loop it runs inside loop-abort's thunk, on the SCHEDULER's stack
  ;; with the prompt already unwound; off the loop it is marshalled
  ;; onto the loop by %flow-spawn-safe and runs there. Either way a
  ;; raise reaches loop-apply's catch-all instead of the caller: the
  ;; fiber is killed with its continuation unrun, or — worse, off the
  ;; loop — the worker thread is never broadcast to and blocks on its
  ;; condition variable for the life of the process. Both present as a
  ;; lost wakeup, which is exactly what they are not.
  ;;
  ;; Not a hypothetical: loop-get-sqe raises "submission queue full"
  ;; once more than 256 operations are queued in a tick, and every
  ;; ring-touching block proc reaches it — flow-timeout, flow-read,
  ;; flow-write, flow-open, flow-read-at — as does loop-accept-block's
  ;; "concurrent accept on fd". The cancel path a few lines below has
  ;; been hardened against precisely this raise since the NULL-SQE fix;
  ;; the registration pass had not been.
  ;;
  ;; So carry the object out as a VALUE, through the same resume the
  ;; winning base would have used, and re-raise it in %flow-settle on
  ;; the waiting party's own stack, where its guards are.
  (define-record-type* <flow-raise>
    (%make-flow-raise object)
    %flow-raise?
    (object %flow-raise-object))

  (define (%flow-settle result)
    (if (%flow-raise? result)
        (raise (%flow-raise-object result))
        result))

  (define flow-block-and-wait-off-loop
    (lambda (bases)
      (let ((state (box 'waiting))
            (cancels (box '()))
            (mutex (make-mutex))
            (ready (make-condition))
            (slot #f)
            (done? #f))
        (define resume-from
          (lambda (tag value)
            (and (box-cas! state 'waiting 'synched)
                 (begin
                   ;; Cancels touch the ring, so they must run ON the
                   ;; loop even though we are not on it.
                   ;;
                   ;; Known residual, unlike the on-loop path below:
                   ;; the broadcast wakes this worker on ITS thread
                   ;; while the cancels are still only queued on the
                   ;; loop, so a worker that immediately re-performs
                   ;; can have its new registration marshalled ahead of
                   ;; the old cancel. Only matters for a cancel that
                   ;; frees something the next registration needs —
                   ;; today just flow-accept's handler slot — i.e. a
                   ;; worker losing an accept race and re-accepting the
                   ;; same fd at once. Ordering these across the thread
                   ;; boundary would mean blocking the worker on the
                   ;; loop, which is worse than the case it fixes.
                   (%flow-spawn-safe
                     (lambda ()
                       (for-each (lambda (pair)
                                   (unless (eq? (car pair) tag)
                                     ((cdr pair))))
                                 (unbox cancels))))
                   (with-mutex mutex
                     (set! slot value)
                     (set! done? #t)
                     (condition-broadcast ready))
                   #t))))
        ;; Registration runs ON THE LOOP, for exactly the reason the
        ;; cancels above do: a block-proc for anything other than a
        ;; channel operation preps an SQE and mutates
        ;; (loop-handlers (loop-current)) -- flow-timeout, flow-read,
        ;; flow-write, flow-accept, flow-open. Doing that from a worker
        ;; thread corrupts the ring, and it does not fail where it
        ;; happens: it surfaces later as a segfault somewhere unrelated.
        ;; A downstream server died with "nonrecoverable invalid memory
        ;; reference" under load this way, and hung for 25 minutes on
        ;; another occasion.
        ;;
        ;; Channel block-procs touch only CAS boxes and were always
        ;; safe here, which is why worker mode appeared to work: every
        ;; event a compute worker actually performed happened to be a
        ;; channel operation.
        ;;
        ;; Deferring registration is safe against the wait below. RESUME-FROM
        ;; elects a single winner with box-cas! on STATE regardless of which
        ;; thread it runs on, and the worker either finds DONE? already set
        ;; and never waits, or waits and is broadcast to. The mutex is held
        ;; only around the slot, and condition-wait releases it.
        (%flow-spawn-safe
          (lambda ()
            ;; This thunk runs on the LOOP while the worker sleeps on
            ;; the condition variable below, so a raise in a block proc
            ;; here would be swallowed by loop-apply and the worker
            ;; would never be broadcast to again. Hand it back as this
            ;; synchronization's winning value instead: ERROR-TAG
            ;; matches no base, so every already registered cancel
            ;; fires, and the worker wakes into %flow-settle.
            (let ((error-tag (cons #f #f)))
              (guard (ex (#t
                          (unless (resume-from error-tag (%make-flow-raise ex))
                            (display "flow: block registration raised after another base won: "
                                     (current-error-port))
                            (if (condition? ex)
                                (display-condition ex (current-error-port))
                                (display ex (current-error-port)))
                            (newline (current-error-port))
                            (flush-output-port (current-error-port)))))
                (for-each (lambda (base)
                            (let ((tag (cons #f #f)))
                              ((flow-block-proc base) state
                               (lambda (raw)
                                 (resume-from tag ((flow-wrap-proc base) raw)))
                               (lambda (thunk)
                                 (set-box! cancels
                                           (cons (cons tag thunk) (unbox cancels)))))))
                          bases)))))
        (with-mutex mutex
          (let wait ()
            (unless done?
              (condition-wait ready mutex)
              (wait))))
        slot)))

  (define flow-block-and-wait
    (lambda (bases)
      (if (%worker-current?)
        (flow-block-and-wait-off-loop bases)
        (flow-block-and-wait-on-loop bases))))

  (define flow-block-and-wait-on-loop
    (lambda (bases)
      (let ((state (box 'waiting))
            (cancels (box '())))
        (loop-abort
         (lambda (k)
           ;; The cancel list is unboxed inside a spawned thunk, not
           ;; at resume time: a base can win SYNCHRONOUSLY, during the
           ;; block-registration for-each below (flow-put-block/
           ;; flow-get-block's post-register rescan does exactly that),
           ;; and the bases after it in flatten order have not
           ;; registered their cancels yet. Snapshotting here would
           ;; fire an incomplete list and leave e.g. a losing
           ;; flow-read armed forever, eating and discarding the fd's
           ;; next bytes. Deferring through loop-spawn reads the list
           ;; only after the registration pass has finished.
           ;;
           ;; Cancels and k are spawned as SEPARATE thunks: a cancel
           ;; can raise (loop-get-sqe does, on a full submission
           ;; queue), and once state has CASed to 'synched nothing
           ;; else can ever resume this fiber — sharing one thunk
           ;; would let a loser's failed cancel destroy the winner's
           ;; continuation. Split, the raise is confined to the
           ;; cancel thunk (reported by loop-apply's guard) and k
           ;; still runs. Their relative order within the tick does
           ;; not matter: cancel SQEs target ids the resumed fiber
           ;; can no longer touch, and everything prepped this tick
           ;; is submitted together at the next boundary anyway.
           (define resume-from
             (lambda (tag value)
               (and (box-cas! state 'waiting 'synched)
                    (begin
                      ;; %flow-spawn-safe, not loop-spawn: the party
                      ;; completing this rendezvous may be a worker
                      ;; thread, and loop-spawn conses onto the loop's
                      ;; unsynchronized thunk list. On the loop thread
                      ;; it IS loop-spawn, so the common path is
                      ;; unchanged.
                      ;; k is spawned FIRST so that it runs LAST:
                      ;; loop-spawn conses, and loop-run-once walks the
                      ;; list front to back, so the thunk queued last
                      ;; runs first. The losers' cancels must land
                      ;; before the resumed fiber does anything, because
                      ;; a cancel can free a resource the fiber
                      ;; immediately reuses — flow-accept's cancel
                      ;; releases the multishot's single handler slot,
                      ;; and a fiber that re-accepts before it runs gets
                      ;; "concurrent accept on fd" instead. Still two
                      ;; separate thunks, so a raising cancel is
                      ;; confined by loop-apply's guard and k survives
                      ;; it either way.
                      (%flow-spawn-safe (lambda () (k value)))
                      (%flow-spawn-safe
                       (lambda ()
                         (for-each (lambda (pair)
                                     (unless (eq? (car pair) tag)
                                       ((cdr pair))))
                                   (unbox cancels))))
                      #t))))
           ;; Same hazard as the cancel split described above, on the
           ;; other pass: a block proc can raise, and here that would
           ;; take k with it and strand the fiber. ERROR-TAG matches no
           ;; base, so the losers' cancels all fire and the fiber
           ;; resumes into %flow-settle, which re-raises on its own
           ;; stack. Bases after the failing one never register — this
           ;; synchronization is over.
           (let ((error-tag (cons #f #f)))
             (guard (ex (#t
                         ;; A base may already have won synchronously
                         ;; during registration, in which case the
                         ;; fiber is committed to that value and the
                         ;; CAS fails. Report rather than swallow.
                         (unless (resume-from error-tag (%make-flow-raise ex))
                           (display "flow: block registration raised after another base won: "
                                    (current-error-port))
                           (if (condition? ex)
                               (display-condition ex (current-error-port))
                               (display ex (current-error-port)))
                           (newline (current-error-port))
                           (flush-output-port (current-error-port)))))
               (for-each (lambda (base)
                           ;; one fresh tag per registration — see the
                           ;; comment above on winner-cancel exclusion
                           (let ((tag (cons #f #f)))
                             ((flow-block-proc base) state
                              (lambda (raw)
                                (resume-from tag ((flow-wrap-proc base) raw)))
                              (lambda (thunk)
                                (set-box! cancels
                                          (cons (cons tag thunk)
                                                (unbox cancels)))))))
                         bases))))))))

  (define flow-perform
    (lambda (event)
      (let ((bases (flow-flatten event)))
        (flow-check-same-channel-choice! bases)
        (let ((result (flow-poll bases)))
          (if (eq? result %flow-not-ready)
              (%flow-settle (flow-block-and-wait bases))
              result)))))

  ;;------------------------------------------------------------
  ;; Lock-free lists (coop.scm layer 1, with defect 1 fixed: the
  ;; original box-cons! CASed against a free variable `lst` instead of
  ;; a snapshot of (unbox box); this one snapshots first). Safe for
  ;; concurrent push from multiple OS threads at once, unlike a plain
  ;; mutable field. Since FL-7's removal the event loop — and with it
  ;; channels — is single-OS-thread, so only flow-log still exercises
  ;; the cross-thread guarantee (any thread may log; the flush thread
  ;; drains); channels keep using these because the CAS costs nothing
  ;; on the uncontended single-thread path.
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
  ;; both present at the same time, there is no buffering.
  ;;
  ;; Contract since FL-7's removal: a channel may only be touched from
  ;; fibers of THE one event loop. The lists themselves are still
  ;; CAS-protected, but completing a rendezvous calls the parked
  ;; peer's resume, and resume preps cancel SQEs on the loop's ring
  ;; and conses onto its (unsynchronized) thunk list — from a foreign
  ;; OS thread that corrupts loop state, mailbox indirection that
  ;; used to make it safe is gone. Cross-thread hand-off is what
  ;; flow-log's CAS boxes (below) are for.
  (define-record-type* <flow-channel>
    (make-flow-channel% puts pops gc-counter)
    flow-channel?
    (puts       flow-channel-puts)
    (pops       flow-channel-pops)
    (gc-counter flow-channel-gc-counter))

  (define make-flow-channel
    (lambda ()
      (make-flow-channel% (box '()) (box '()) (box 0))))

  ;; Diagnostic only -- see the export comment above.
  (define flow-channel-puts-length
    (lambda (channel) (length (unbox (flow-channel-puts channel)))))
  (define flow-channel-pops-length
    (lambda (channel) (length (unbox (flow-channel-pops channel)))))

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

  ;; Atomically unlink ONE specific entry from BOX's list right at the
  ;; moment it is matched via the non-blocking try path (flow-put-try/
  ;; flow-get-try below), instead of leaving it for the next periodic
  ;; flow-channel-compact! sweep. remq compares by eq?, so this removes
  ;; exactly the matched cons cell and nothing else; retries against a
  ;; fresh snapshot on a concurrent racing push/removal, same shape as
  ;; flow-channel-compact! above.
  (define flow-channel-remove!
    (lambda (box entry)
      (let ((lst (unbox box)))
        (unless (box-cas! box lst (remq entry lst))
          (flow-channel-remove! box entry)))))

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
  ;; call — nothing yields between the poll pass and the block pass,
  ;; and since FL-7's removal nothing outside the one loop thread may
  ;; touch a channel (see the <flow-channel> contract above), so no
  ;; concurrent peer can land in between either. The claim!/rescan
  ;; discipline below is kept regardless: it is what made the
  ;; rendezvous safe when a peer COULD appear mid-gap, it costs one
  ;; CAS on the empty path, and dropping it would silently re-open
  ;; the lost-wakeup hole the moment concurrency ever returns.
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
            ;; Bug fix, 2026-08-14: the try path resolves a rendezvous
            ;; without ever removing the matched entry from POPS,
            ;; which previously only happened via the periodic batch
            ;; flow-channel-compact! sweep (triggered only from the
            ;; BLOCKING path's counter -- a channel whose traffic
            ;; mostly resolves via try, the common, healthy,
            ;; non-backlogged case, almost never triggered it). Every
            ;; matched-but-unremoved entry, and the payload its VALUE
            ;; field still references, piled up in the channel's
            ;; internal list for the channel's whole lifetime -- see
            ;; letloop TODO.md's top entry for the full diagnosis (a
            ;; downstream indexing pipeline leaking unbounded RSS on
            ;; a large corpus pass). This unlinks the ONE matched
            ;; entry immediately -- a small targeted CAS, not a
            ;; periodic whole-list rebuild.
            (flow-channel-remove! (flow-channel-pops channel) (car pops))
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
            ;; Bug fix, 2026-08-14: see the matching comment in
            ;; flow-put-try -- immediate targeted removal, not a
            ;; compaction-counter bump.
            (let ((obj (flow-channel-entry-value (car puts))))
              (flow-channel-remove! (flow-channel-puts channel) (car puts))
              (lambda () obj)))
           (else (scan (cdr puts))))))))

  ;; A rendezvous whose putter has already been resumed cannot be
  ;; called off: its flow-put! has returned, the handoff DID happen. So
  ;; when the getter's own resume then reports #f — this perform synched
  ;; on another base first — the value must land somewhere rather than
  ;; evaporate. Hand it to another waiting getter if there is one;
  ;; otherwise leave it on the puts list as an entry with no
  ;; continuation behind it, only a state box its resume CASes exactly
  ;; like a real party's does.
  ;;
  ;; That CAS is what makes the entry single-use: the first taker wins
  ;; and the entry stops being `waiting?`, so a second one skips it and
  ;; compaction drops it. Without it the entry would stay waiting
  ;; forever and hand the same value out repeatedly — a synthetic
  ;; putter that never dies is worse than the lost value it replaces.
  ;;
  ;; The entry satisfies flow-get-try's waiting?/claim!/resume test
  ;; unchanged, so no reader needs to know it is special.
  (define %flow-channel-redeposit!
    (lambda (channel obj)
      (let scan ((pops (unbox (flow-channel-pops channel))))
        (cond
         ((null? pops)
          (let* ((state (box 'waiting))
                 (entry (make-flow-channel-entry*
                         state
                         (lambda (ignored) (box-cas! state 'waiting 'synched))
                         obj)))
            (%flow-trace! "redeposit e" (%flow-trace-entry-id entry)
                          " ch" (%flow-trace-channel-id channel))
            (flow-box-cons! (flow-channel-puts channel) entry)))
         ((and (flow-channel-entry-waiting? (car pops))
               (flow-channel-entry-claim! (car pops)))
          (if ((flow-channel-entry-resume (car pops)) obj)
              (flow-channel-remove! (flow-channel-pops channel) (car pops))
              ;; Cannot happen under the claim! invariant, but a claim
              ;; left set on an entry we then walk away from would
              ;; strand that getter for good — release it rather than
              ;; rely on the invariant holding forever.
              (begin
                (set-box! (flow-channel-entry-claimed (car pops)) #f)
                (scan (cdr pops)))))
         (else (scan (cdr pops)))))))

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
                ;; The putter above is already committed, so this
                ;; resume's #f — an earlier base of this same perform
                ;; won during registration — must not drop the value on
                ;; the floor. See %flow-channel-redeposit!.
                (let ((obj (flow-channel-entry-value (car puts))))
                  (unless ((flow-channel-entry-resume entry) obj)
                    (%flow-channel-redeposit! channel obj))))
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

  ;; Attempt a PUT without ever suspending: if a waiting GET exists
  ;; right now, deliver OBJ to it and return #t; otherwise return #f
  ;; immediately instead of registering and blocking. For a producer
  ;; that would rather drop a value than park forever waiting for a
  ;; consumer that may never arrive (e.g. the request this value was
  ;; computed for has already been abandoned and nothing is calling
  ;; flow-get! on this channel anymore) -- the non-blocking counterpart
  ;; to flow-put!, added 2026-08-14 alongside the flow-put-try/
  ;; flow-get-try immediate-removal fix above, for exactly this use.
  ;; (flow-put-try channel obj) returns a THUNK to attempt one
  ;; non-blocking match, not the attempt itself -- this wraps that
  ;; shape into a plain #t/#f call.
  (define flow-put-try!
    (lambda (channel obj)
      (and ((flow-put-try channel obj)) #t)))

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
  ;; (§4.5's one hook into (letloop liburing low)). resume's return
  ;; value (#t on winning the CAS, #f otherwise) is exactly the
  ;; claim/decline signal loop-accept-block's handler expects, so a
  ;; client accepted after we already lost is pushed back onto the
  ;; accept backlog rather than leaked.
  ;;
  ;; This block DOES need a register-cancel!, which it long lacked. The
  ;; old reasoning — the multishot is per-fd infrastructure and must
  ;; not be torn down just because one choice touching it lost — is
  ;; right, and the cancel below does not tear it down. What it missed
  ;; is the HANDLER: loop-accept-block keys a single continuation slot
  ;; by the multishot's id and refuses a second waiter on it, so a
  ;; losing accept that left its handler behind poisons the listening
  ;; fd — every later flow-accept on it raises "concurrent accept on
  ;; fd", for as long as no client happens to arrive to clear the slot,
  ;; i.e. precisely while the server is idle. Deleting just the handler
  ;; costs nothing: a client the multishot accepts with none registered
  ;; lands on the backlog exactly as above.
  (define flow-accept
    (lambda (fd)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda ()
                    (let ((client (loop-accept-try fd)))
                      (and client (lambda () client))))
                  (lambda (state resume register-cancel!)
                    (let ((id (loop-accept-block
                               fd (lambda (client) (resume client)))))
                      (register-cancel!
                       (lambda ()
                         (hashtable-delete! (loop-handlers (loop-current))
                                            id))))))))

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

  ;; %flow-spawn-safe, not loop-spawn: on the loop thread this IS
  ;; loop-spawn, so nothing changes for existing callers, but it also
  ;; lets a compute worker fan work out onto the loop.
  ;;
  ;; That is what makes an ordinary concurrent-fetch helper -- spawn N
  ;; fibers, have each flow-put! its result, flow-get! them all -- work
  ;; unchanged when called from a worker: the spawns land on the loop,
  ;; the puts happen there, and the worker's gets block off-loop on a
  ;; condition variable. Without it a worker had to fall back to
  ;; fetching one object at a time, which measured 2x SLOWER than the
  ;; single-threaded server on cold, I/O-bound queries.
  (define flow-spawn
    (lambda (thunk) (%flow-spawn-safe thunk)))
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
  ;; current tick's cached loop-jiffy. Callable from any OS thread —
  ;; the one flow facility that still is — but only once loop-new has
  ;; run somewhere in the process: loop-jiffy reads the loop record
  ;; and raises on the #f it is before then.
  (define flow-log
    (lambda (sexp)
      (flow-box-cons! (flow-log-ensure-box!) (cons (loop-jiffy) sexp))))

  ;; Drain the registry and every registered box, returning every
  ;; pending entry: oldest-first within each thread's own box, boxes
  ;; concatenated in registry order (not globally timestamp-sorted --
  ;; a caller wanting strict cross-thread temporal order can sort the
  ;; result itself).
  ;;
  ;; flow-box-drain! on the registry is itself race-free against
  ;; concurrent registrations (a new thread registering mid-drain either
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
  ;; thread, not one per logging thread (that would defeat the point
  ;; of a single drain-and-flush cadence). stopped? starts #t
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
  ;; drains every registered thread's log box (via flow-log-drain!) and
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

  ;;------------------------------------------------------------
  ;; flow-worker: run CPU-bound work on OS threads
  ;;------------------------------------------------------------
  ;;
  ;; The loop is one OS thread, so a fiber doing sustained CPU work
  ;; blocks every other fiber for its whole duration -- cooperative
  ;; scheduling only overlaps I/O WAITS, never computation. This gives
  ;; a fiber a way to hand a pure-CPU thunk to a pool of OS threads and
  ;; park until it is done, so the loop keeps serving other connections
  ;; meanwhile.
  ;;
  ;; This is deliberately NOT FL-7. Workers never touch the ring, never
  ;; call loop-spawn/loop-read/loop-write, never see %loop; they compute
  ;; and push a result. Only the loop thread ever resumes a fiber. The
  ;; loop's unsynchronized state (its thunk list, its handler table)
  ;; therefore stays owned by exactly one thread, which is the invariant
  ;; FL-7's removal restored and this must not break.
  ;;
  ;; Two queues, each matched to its direction:
  ;;
  ;; - jobs (loop thread -> workers): a mutex and condition variable,
  ;;   because idle workers must BLOCK rather than spin, and that is
  ;;   what a condvar is for. FIFO, so a burst cannot starve its own
  ;;   oldest request.
  ;; - results (workers -> loop thread): flow-box-cons!/flow-box-drain!,
  ;;   the lock-free CAS list already used by flow-log, already
  ;;   documented safe for concurrent push from any number of threads.
  ;;
  ;; The wake-up is an eventfd. Without one, a result would still be
  ;; noticed on the loop's next tick, but that tick can be up to
  ;; %wait-timeout (100ms) away -- fine for correctness, useless for a
  ;; request whose whole budget is tens of milliseconds. A worker
  ;; writes 8 bytes; the collector fiber is parked on an io_uring read
  ;; of that fd and wakes through the ordinary completion path, so no
  ;; new scheduler machinery is involved.

  (define %worker-eventfd-create
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "eventfd" (unsigned-int int) int)))
      (lambda ()
        (call-with-values (lambda () (func 0 0))
          (lambda (fd errno)
            (when (fx<? fd 0)
              (error 'flow-worker-start! "eventfd failed" errno))
            fd)))))

  ;; Called from a WORKER thread, never the loop thread. An eventfd
  ;; write of 8 bytes cannot block short of the counter saturating at
  ;; 2^64-2, which no real run reaches, so this needs no async path.
  (define %worker-eventfd-signal!
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "write" (int void* size_t) integer-64)))
      (lambda (fd)
        (let ((ptr (foreign-alloc 8)))
          (foreign-set! 'unsigned-64 ptr 0 1)
          (call-with-values (lambda () (func fd ptr 8))
            (lambda (n errno)
              (foreign-free ptr)
              (>= n 0)))))))

  (define %worker-eventfd-close
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "close" (int) int)))
      (lambda (fd) (call-with-values (lambda () (func fd)) (lambda (r e) r)))))

  ;; Park the calling fiber on FD until a worker signals it, consuming
  ;; the counter. Structured exactly like loop-read: one SQE, register
  ;; the continuation under its id, loop-abort.
  (define %worker-eventfd-wait
    (lambda (fd)
      (let ((buffer (foreign-alloc 8)))
        (let* ((sqe (loop-get-sqe (loop-ring (loop-current))))
               (id (loop-alloc-id!)))
          (io-uring-prep-read sqe fd buffer 8 0)
          (io-uring-sqe-set-data64 sqe id)
          (let ((res (loop-abort
                       (lambda (k) (hashtable-set! (loop-handlers (loop-current)) id k)))))
            (foreign-free buffer)
            res)))))

  ;; #t only on threads forked by flow-worker-start!, so code shared by
  ;; both sides can ask which thread it is on. A thread parameter, so
  ;; the loop thread never observes another thread's value.
  (define %worker-current? (make-thread-parameter #f))

  (define (flow-worker-current?) (%worker-current?))

  ;; One I/O request marshalled from a worker to the loop thread. The
  ;; worker blocks on MUTEX/CONDITION -- blocking an OS thread that has
  ;; nothing else to do, never the loop.
  (define-record-type* <flow-io-request>
    (make-flow-io-request% thunk done? result mutex condition)
    flow-io-request?
    (thunk     flow-io-request-thunk)
    (done?     flow-io-request-done?     flow-io-request-done?-set!)
    (result    flow-io-request-result    flow-io-request-result-set!)
    (mutex     flow-io-request-mutex)
    (condition flow-io-request-condition))

  (define %io-requests (box '()))

  ;; Thunks a foreign OS thread wants run on the loop thread. This is
  ;; the "mailbox indirection" the channel contract above says FL-7's
  ;; removal deleted: with it, completing a rendezvous from another
  ;; thread is safe again, because the peer's resume is queued here and
  ;; performed BY the loop rather than conses onto the loop's
  ;; unsynchronized thunk list by whoever happened to complete it.
  (define %cross-thread-spawns (box '()))

  ;; loop-spawn from the loop thread (the hot path, untouched), queue +
  ;; wake from anywhere else. A worker completing a rendezvous with no
  ;; pool running has nothing to wake, which can only mean the pool was
  ;; stopped underneath it -- better to say so than to enqueue a thunk
  ;; nobody will ever run.
  (define %flow-spawn-safe
    (lambda (thunk)
      (if (%worker-current?)
        (begin
          (unless %worker-eventfd
            (error 'flow "cross-thread resume with no worker pool running"))
          (flow-box-cons! %cross-thread-spawns thunk)
          (%worker-eventfd-signal! %worker-eventfd))
        (loop-spawn thunk))))

  ;; Run THUNK on the loop thread and return its value, wherever the
  ;; caller happens to be.
  ;;
  ;; This is what lets compute workers do I/O without ever touching the
  ;; ring: a worker submits the thunk, the loop runs it in a fiber of
  ;; its own -- so several workers' I/O overlaps exactly as ordinary
  ;; fiber I/O does, over ONE connection pool -- and the worker blocks
  ;; until the reply. Called on the loop thread it simply runs the
  ;; thunk, so the same storage code path serves warm-up and queries.
  (define flow-worker-io
    (lambda (thunk)
      (if (not (%worker-current?))
        (thunk)
        (let ((request (make-flow-io-request% thunk #f #f
                                              (make-mutex) (make-condition))))
          (flow-box-cons! %io-requests request)
          (%worker-eventfd-signal! %worker-eventfd)
          (with-mutex (flow-io-request-mutex request)
            (let wait ()
              (unless (flow-io-request-done? request)
                (condition-wait (flow-io-request-condition request)
                                (flow-io-request-mutex request))
                (wait))))
          (let ((outcome (flow-io-request-result request)))
            (if (eq? (car outcome) 'value)
              ;; Multiple-value transparent: www-request returns five
              ;; values, and a marshalling layer that quietly kept only
              ;; the first turned every S3 read into garbage -- queries
              ;; still "worked", they just returned no results.
              (apply values (cdr outcome))
              (raise (cdr outcome))))))))

  (define %worker-mutex (make-mutex))
  (define %worker-available (make-condition))
  (define %worker-jobs-in '())          ;; pushed here (reversed)
  (define %worker-jobs-out '())         ;; popped here
  (define %worker-results (box '()))
  (define %worker-pending #f)           ;; id -> continuation, loop thread only
  (define %worker-eventfd #f)
  (define %worker-next-id (box 0))
  (define %worker-stop? #f)
  (define %worker-running? #f)

  (define %worker-job-pop!
    ;; Caller holds %worker-mutex. #f means "stop requested".
    (lambda ()
      (let wait ()
        (cond
          (%worker-stop? #f)
          ((pair? %worker-jobs-out)
           (let ((job (car %worker-jobs-out)))
             (set! %worker-jobs-out (cdr %worker-jobs-out))
             job))
          ((pair? %worker-jobs-in)
           (set! %worker-jobs-out (reverse %worker-jobs-in))
           (set! %worker-jobs-in '())
           (wait))
          (else (condition-wait %worker-available %worker-mutex) (wait))))))

  (define %worker-body
    (lambda ()
      (%worker-current? #t)
      (let loop ()
        (let ((job (with-mutex %worker-mutex (%worker-job-pop!))))
          (when job
            ;; A raising thunk must still produce a result, or the
            ;; fiber that submitted it parks forever and its connection
            ;; hangs until the idle reaper closes it.
            (let ((outcome (guard (exception (#t (cons 'raised exception)))
                             (cons 'value (call-with-values (cdr job) list)))))
              (flow-box-cons! %worker-results (cons (car job) outcome))
              (%worker-eventfd-signal! %worker-eventfd))
            (loop))))))

  ;; Drains finished results and resumes their fibers. Runs as one
  ;; fiber ON the loop thread -- which is what makes resuming safe.
  (define %worker-collector
    (lambda ()
      (let loop ()
        (when %worker-running?
          (%worker-eventfd-wait %worker-eventfd)
          ;; Resumes handed over by foreign threads: run them as the
          ;; loop's own thunks, which is the whole point of the queue.
          (for-each loop-spawn (flow-box-drain! %cross-thread-spawns))
          ;; I/O requests first: a worker is blocked on each one, and
          ;; every fiber spawned here can be in flight at the same
          ;; time, which is what keeps several workers' fetches
          ;; overlapping on the one ring.
          (for-each
            (lambda (request)
              (loop-spawn
                (lambda ()
                  (let ((outcome (guard (exception (#t (cons 'raised exception)))
                                   (cons 'value
                                         (call-with-values
                                           (flow-io-request-thunk request)
                                           list)))))
                    (with-mutex (flow-io-request-mutex request)
                      (flow-io-request-result-set! request outcome)
                      (flow-io-request-done?-set! request #t)
                      (condition-broadcast (flow-io-request-condition request)))))))
            (flow-box-drain! %io-requests))
          (for-each
            (lambda (entry)
              (let ((k (hashtable-ref %worker-pending (car entry) #f)))
                (when k
                  (hashtable-delete! %worker-pending (car entry))
                  (loop-spawn (lambda () (k (cdr entry)))))))
            (flow-box-drain! %worker-results))
          (loop)))))

  ;; Start COUNT worker threads. Must be called from inside a running
  ;; loop (it spawns the collector fiber).
  (define flow-worker-start!
    (lambda (count)
      (when %worker-running?
        (error 'flow-worker-start! "worker pool already running"))
      (set! %worker-stop? #f)
      (set! %worker-pending (make-eqv-hashtable))
      (set! %worker-eventfd (%worker-eventfd-create))
      (set! %worker-running? #t)
      (do ((i 0 (fx+ i 1))) ((fx=? i count))
        (fork-thread %worker-body))
      (loop-spawn %worker-collector)))

  (define flow-worker-stop!
    (lambda ()
      (when %worker-running?
        (set! %worker-running? #f)
        (with-mutex %worker-mutex
          (set! %worker-stop? #t)
          (condition-broadcast %worker-available))
        ;; Wake the collector so it observes %worker-running? and exits
        ;; instead of staying parked on a read nobody will satisfy.
        (%worker-eventfd-signal! %worker-eventfd))))

  ;; Run THUNK on a worker thread; park this fiber until it finishes.
  ;; Returns the thunk's value, or re-raises whatever it raised, so a
  ;; caller cannot tell the work happened on another thread except that
  ;; the loop kept running.
  ;;
  ;; No race between queueing and parking: both happen on the loop
  ;; thread, and the collector is itself a fiber on that same thread,
  ;; so it cannot observe the result until this fiber has parked and
  ;; registered its continuation below.
  (define flow-worker-call
    (lambda (thunk)
      (unless %worker-running?
        (error 'flow-worker-call "worker pool not running"))
      (let ((id (flow-box-increment! %worker-next-id)))
        (with-mutex %worker-mutex
          (set! %worker-jobs-in (cons (cons id thunk) %worker-jobs-in))
          (condition-signal %worker-available))
        (let ((outcome (loop-abort
                         (lambda (k) (hashtable-set! %worker-pending id k)))))
          (if (eq? (car outcome) 'value)
            (apply values (cdr outcome))
            (raise (cdr outcome)))))))

  (include "letloop/flow.check.scm"))

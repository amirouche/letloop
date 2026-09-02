;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop flow2) — fibers, channels, and nurseries over io_uring.
;; A fork of (letloop flow); see src/letloop/flow2/README.md for the
;; full design document. The two architectural changes from flow:
;;
;; - Only the main thread touches the ring. Compute threads have no
;;   I/O verbs; the only cross-thread primitive is the channel, and
;;   channels here are buffered mutex-protected queues rather than
;;   rendezvous, and bounded by default. A put parks when the channel
;;   is full — backpressure, not a rendezvous: it waits for room, never
;;   for a matching getter. put nonetheless stays a plain procedure and
;;   no put EVENT is exported, and that, not the absence of parking, is
;;   what keeps flow's same-channel-choice hazard inexpressible here.
;;
;; - Every fiber belongs to a scope (nursery). A scope join waits for
;;   all children; the first child error cancels the siblings' parked
;;   events and in-flight ring operations and re-raises at the join.
;;   flow-monitor is a nursery with a deadline. Cancellation reuses
;;   the choice machinery: each perform inside a cancellable scope
;;   carries one extra base event that the scope's cancellation
;;   resumes, so the losing bases' register-cancel! thunks — the same
;;   ones a losing flow-choice member fires — tear down the ring ops.
;;
;; Errors are plain <flow-error> records dispatched by symbol —
;; cancelled, timeout, overflow, compute, wrong-thread — not R6RS
;; conditions, so the same value can be raised at a suspension point
;; or sent over a response channel as a worker task's failure reply.
(library (letloop flow2)

  (export
   ;; errors
   make-flow-error flow-error? flow-error-symbol flow-error-message
   flow-error-irritants flow-error-cause
   flow-error-cancelled? flow-error-timeout? flow-error-overflow?
   flow-error-compute? flow-error-wrong-thread?

   ;; events (Concurrent ML core)
   make-flow flow? flow-wrap flow-guard flow-choice flow-perform

   ;; channels
   make-flow-channel flow-channel? flow-channel-name
   flow-channel-buffer-size!
   flow-put! flow-get flow-get! flow-get-try

   ;; timers
   flow-timeout flow-sleep

   ;; network and file I/O
   flow-accept flow-read flow-write flow-write-all!
   flow-open flow-read-at flow-write-at flow-close
   O-RDONLY O-WRONLY O-RDWR O-CREAT O-TRUNC O-APPEND

   ;; fibers and nurseries
   flow-spawn flow-nursery flow-scope? flow-scope-cancel!
   flow-monitor flow-cancelled?

   ;; lifecycle and compute threads
   flow-run flow-stop flow-submit!

   ;; diagnostics
   flow-log flow-log-drain! flow-log-start! flow-log-stop!
   ;; Raw internal lengths, the way (letloop flow) gained
   ;; flow-channel-puts-length / flow-channel-pops-length after its
   ;; 44GB incident: a structure holding entries nobody will resume
   ;; looks idle from outside, and every leak in this family is the gap
   ;; between the raw number and the logical one.
   flow-channel-queue-length flow-channel-getters-length
   flow-channel-space-length flow-channel-bound
   flow-scope-children-count flow-scope-waiters-length
   flow-scope-join-waiters-length

   ;; checks
   ~check-flow2-000/error-symbol-dispatch
   ~check-flow2-000/error-predicates
   ~check-flow2-001/always-ready
   ~check-flow2-001/wrap-order
   ~check-flow2-002/channel-buffered-fifo
   ~check-flow2-002/channel-get-parks-until-put
   ~check-flow2-002/channel-bound-overflow
   ~check-flow2-002/channel-bound-below-length
   ~check-flow2-002/channel-bound-zero-rejected
   ~check-flow2-002/raising-bound-wakes-parked-putters
   ~check-flow2-002/channel-get-try-default
   ~check-flow2-002/channel-get-or-timeout
   ~check-flow2-000/log-is-nonblocking-and-drains
   ~check-flow2-000/log-flush-thread-lifecycle
   ~check-flow2-002/channel-name
   ~check-flow2-002/diagnostics-see-what-leaks
   ~check-flow2-002/default-bound-is-finite
   ~check-flow2-002/put-parks-when-full
   ~check-flow2-002/put-parked-on-full-is-cancellable
   ~check-flow2-002/channel-full-warns-once
   ~check-flow2-002/losing-get-does-not-eat-a-value
   ~check-flow2-002/losing-get-leaves-no-getter
   ~check-flow2-003/nursery-join-waits-children
   ~check-flow2-003/nursery-child-raise-cancels-siblings
   ~check-flow2-003/nursery-scope-cancel
   ~check-flow2-003/nursery-perform-after-cancel-raises
   ~check-flow2-003/nursery-in-dead-scope-raises
   ~check-flow2-003/block-raise-reaches-the-scope
   ~check-flow2-003/waiter-on-dead-scope-is-woken
   ~check-flow2-004/monitor-in-time
   ~check-flow2-004/monitor-deadline
   ~check-flow2-004/monitor-interrupted-by-parent-drains-children
   ~check-flow2-005/shutdown-joins-the-worker-pool
   ~check-flow2-005/nursery-waits-for-its-compute-task
   ~check-flow2-003/cancel-is-visible-to-non-suspending-ops
   ~check-flow2-003/cancelled-parent-drains-grandchildren
   ~check-flow2-005/worker-task-replies
   ~check-flow2-005/worker-raise-becomes-compute-error
   ~check-flow2-005/worker-ring-event-raises-wrong-thread
   ~check-flow2-005/worker-cancelled-along-monitor
   ~check-flow2-005/worker-io-protocol-roundtrip
   ~check-flow2-005/worker-resume-runs-cancels-first

   ;; block-and-wait machinery, ported from (letloop flow)'s
   ;; ~check-flow-011 series, plus the branch finding 1's fix added
   ~check-flow2-011/sync-resume-runs-later-cancels
   ~check-flow2-011/raising-cancel-does-not-lose-fiber
   ~check-flow2-011/winner-own-cancel-not-fired
   ~check-flow2-011/raise-after-sync-win-keeps-winner

   ;; network and file I/O, ported from (letloop flow)'s ~check-flow-006
   ;; and ~check-flow-009 series -- the 11 fd- and ring-touching checks
   ;; the fork had dropped
   ~check-flow2-006/write-reports-its-count
   ~check-flow2-006/echo-pair
   ~check-flow2-006/accept-cancel-leaves-listener-usable
   ~check-flow2-006/read-or-timeout-leaves-fd-usable
   ~check-flow2-006/request-loop-idle-timeout
   ~check-flow2-009/file-write-read-roundtrip
   ~check-flow2-009/chunked-read-until-eof
   ~check-flow2-009/nonzero-offset
   ~check-flow2-009/read-or-timeout-leaves-fd-usable
   ~check-flow2-009/open-nonexistent-fails
   ~check-flow2-009/open-loses-choice-no-fd-leak
   ~check-flow2-009/close-under-choice-fd-actually-closed
   ~check-flow2-009/close-while-read-in-flight)

  (import (chezscheme)
          (letloop r999)
          (only (letloop cffi) bytevector-pointer)
          (letloop liburing low))

  ;;------------------------------------------------------------
  ;; Errors: one record type, dispatched by symbol
  ;;------------------------------------------------------------

  ;; The taxonomy: cancelled, timeout, overflow, compute,
  ;; wrong-thread. A <flow-error> travels two transports — raised at
  ;; a suspension point, or sent over a response channel as a worker
  ;; task's failure reply — and is the same object either way, which
  ;; is why this is a plain record rather than an R6RS condition.
  (define-record-type* <flow-error>
    (make-flow-error symbol message irritants cause)
    flow-error?
    (symbol    flow-error-symbol)
    (message   flow-error-message)
    (irritants flow-error-irritants)
    (cause     flow-error-cause))

  (define (flow-error-cancelled? obj)
    (and (flow-error? obj) (eq? (flow-error-symbol obj) 'cancelled)))
  (define (flow-error-timeout? obj)
    (and (flow-error? obj) (eq? (flow-error-symbol obj) 'timeout)))
  (define (flow-error-overflow? obj)
    (and (flow-error? obj) (eq? (flow-error-symbol obj) 'overflow)))
  (define (flow-error-compute? obj)
    (and (flow-error? obj) (eq? (flow-error-symbol obj) 'compute)))
  (define (flow-error-wrong-thread? obj)
    (and (flow-error? obj) (eq? (flow-error-symbol obj) 'wrong-thread)))

  (define (%flow-cancelled-error)
    (make-flow-error 'cancelled "flow2: scope cancelled" '() #f))

  (define (%flow-wrong-thread who)
    (raise (make-flow-error 'wrong-thread
                            "flow2: main-thread-only operation on a compute thread"
                            (list who) #f)))

  ;;------------------------------------------------------------
  ;; Lock-free box helpers (same as flow's)
  ;;------------------------------------------------------------

  (define flow-box-cons!
    (lambda (box item)
      (let ((lst (unbox box)))
        (unless (box-cas! box lst (cons item lst))
          (flow-box-cons! box item)))))

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
  ;; flow-log: diagnostics that block neither the loop nor a worker
  ;;------------------------------------------------------------
  ;;
  ;; The design is (letloop flow)'s, reimplemented here rather than
  ;; imported: flow2 must never depend on flow. What it buys is the one
  ;; property a library-internal diagnostic has to have — logging must
  ;; be safe on the loop thread, where any syscall costs every fiber,
  ;; and on a compute thread, where blocking wastes the core the pool
  ;; exists to use.
  ;;
  ;; So a flow-log call does exactly one thing: cons onto a box this
  ;; thread owns. No mutex, no port, no syscall, no allocation beyond
  ;; the entry. Per-thread boxes, not one shared box, because two
  ;; threads CASing the same box would spin against each other on
  ;; precisely the hot path this exists to stay off. Formatting and
  ;; writing happen on a separate flush thread that nothing waits for.
  (define %flow-log-registry (box '()))

  ;; A thread-parameter, not a global: two OS threads logging
  ;; concurrently would otherwise clobber each other's accumulator.
  (define %flow-log-box (make-thread-parameter #f))

  ;; Created and registered on first use, so logging needs no setup
  ;; step on any thread. Only this thread writes its own parameter, so
  ;; the check-then-set needs no CAS; flow-box-cons! is what makes the
  ;; registry push safe against concurrent registration.
  (define (%flow-log-ensure-box!)
    (or (%flow-log-box)
        (let ((b (box '())))
          (%flow-log-box b)
          (flow-box-cons! %flow-log-registry b)
          b)))

  ;; The loop's cached per-tick jiffy, or 0 before there is a loop. A
  ;; plain read of an already-computed field — no syscall on the
  ;; logging path — and the only loop state a compute thread ever
  ;; touches. It is never written from here, and a worker reading a
  ;; value up to one tick stale is exactly the resolution a log line
  ;; wants. Logging before flow-run must not raise: a library that
  ;; warns during startup would otherwise take the program down.
  (define (%flow-log-now)
    (if (loop-current) (loop-jiffy) 0))

  (define (flow-log sexp)
    (flow-box-cons! (%flow-log-ensure-box!) (cons (%flow-log-now) sexp)))

  ;; Every pending entry: oldest-first within each thread's own box,
  ;; boxes in registry order rather than globally sorted — a caller
  ;; wanting strict cross-thread order can sort on the timestamps.
  ;; Draining the registry empties it, so every box is pushed straight
  ;; back: registration is once per thread for that thread's life, not
  ;; a one-shot queue.
  (define (flow-log-drain!)
    (let ((boxes (flow-box-drain! %flow-log-registry)))
      (for-each (lambda (b) (flow-box-cons! %flow-log-registry b)) boxes)
      (apply append (map (lambda (b) (reverse (flow-box-drain! b))) boxes))))

  (define (%flow-log-write! entries)
    (unless (null? entries)
      (let ((port (current-error-port)))
        (for-each (lambda (entry) (write entry port) (newline port))
                  entries)
        (flush-output-port port))))

  ;; (current-error-port) is read at flush time rather than captured at
  ;; start, so a caller that reparameterizes it — a check capturing
  ;; output, a supervisor redirecting it — is honored on the next cycle.
  ;; Plain synchronous port I/O: this thread is not on the loop's
  ;; critical path and does not run a ring at all, so routing it
  ;; through io_uring would buy nothing and cost it a loop of its own.
  (define %flow-log-poll-interval 0.01)
  (define %flow-log-stop-requested? (box #f))
  (define %flow-log-stopped? (box #t))

  ;; Guarded against a second concurrent flush thread, which flow left
  ;; merely documented as unsupported. Draining stays correct either
  ;; way — flow-box-drain! never double-delivers — but two threads
  ;; interleaving writes to the same port produce shuffled output at
  ;; exactly the moment someone is reading it to diagnose something.
  (define (flow-log-start! period-seconds)
    (when (box-cas! %flow-log-stopped? #t #f)
      (set-box! %flow-log-stop-requested? #f)
      (let ((ticks (fxmax 1 (exact (round (/ period-seconds
                                             %flow-log-poll-interval))))))
        (fork-thread
         (lambda ()
           (let lp ()
             ;; Re-check the stop flag at the poll interval rather than
             ;; only at a period boundary, so flow-log-stop! is prompt
             ;; even when the period is long.
             (let wait ((n 0))
               (unless (or (unbox %flow-log-stop-requested?) (fx>=? n ticks))
                 (sleep (make-time 'time-duration
                                   (exact (round (* %flow-log-poll-interval
                                                    1000000000)))
                                   0))
                 (wait (fx+ n 1))))
             (%flow-log-write! (flow-log-drain!))
             (if (unbox %flow-log-stop-requested?)
                 (set-box! %flow-log-stopped? #t)
                 (lp)))))))
    (void))

  ;; Blocks the caller until the flush thread has done one final
  ;; drain-and-write and exited, so nothing logged before the stop
  ;; request is lost on shutdown.
  (define (flow-log-stop!)
    (set-box! %flow-log-stop-requested? #t)
    (let wait ()
      (unless (unbox %flow-log-stopped?)
        (sleep (make-time 'time-duration 10000000 0))
        (wait))))

  ;;------------------------------------------------------------
  ;; Events: the Concurrent ML core, unchanged from flow
  ;;------------------------------------------------------------

  (define-record-type* <flow2-event>
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

  (define flow-choice
    (lambda events
      (make-flow% 'choice (list->vector events) #f #f #f)))

  (define flow-wrap
    (lambda (event proc)
      (case (flow-type event)
        ((base)
         (make-flow% 'base (flow-data event)
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

  (define %flow-not-ready (list 'not-ready))

  ;; Distinguished value a scope's cancellation resumes parked fibers
  ;; with; flow-perform converts it into a raised cancelled
  ;; <flow-error> on the parked fiber's own stack — a raise from the
  ;; canceller's stack would unwind the wrong context entirely.
  (define %flow-cancel-sentinel (list 'cancelled))

  ;; A raise from a base's block procedure, on its way back to the
  ;; fiber. Same device as %flow-cancel-sentinel, for the same reason.
  ;;
  ;; block procs run inside loop-abort's thunk — on the SCHEDULER's
  ;; stack, after the prompt was already unwound — so the guard
  ;; %scope-spawn! installs around the fiber body is no longer in the
  ;; dynamic extent. A raise there used to reach loop-apply's catch-all
  ;; instead: the fiber died, %scope-fail! never ran,
  ;; %scope-child-done! never decremented the scope's child count, and
  ;; %scope-finish parked on the join forever. Not a synthetic worry —
  ;; loop-get-sqe raises "submission queue full" once more than 256 ops
  ;; are queued in a tick (flow-timeout, flow-read, flow-write,
  ;; flow-open, flow-read-at, flow-write-at all reach it) and
  ;; loop-accept-block raises "concurrent accept on fd".
  ;;
  ;; (letloop flow)'s flow-block-and-wait-on-loop has the same shape and
  ;; the same hole: its comment names loop-get-sqe as a raise source and
  ;; hardens the CANCEL thunk against it, leaving the registration loop
  ;; below exposed. The fix belongs there too.
  (define-record-type* <flow2-raise>
    (%make-flow-raise object)
    %flow-raise?
    (object %flow-raise-object))

  ;; What a parked fiber sees when it wakes: a block-proc raise and a
  ;; scope cancellation both come back as values and are converted into
  ;; raises HERE, on the fiber's own stack, where its guards are.
  (define (%flow-settle result)
    (cond
     ((%flow-raise? result) (raise (%flow-raise-object result)))
     ((eq? result %flow-cancel-sentinel) (raise (%flow-cancelled-error)))
     (else result)))

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

  ;;------------------------------------------------------------
  ;; Cross-thread spawn: the loop's mailbox
  ;;------------------------------------------------------------

  ;; #t only on threads forked by flow-run's compute pool.
  (define %worker-current? (make-thread-parameter #f))

  ;; The scope of the task currently running on THIS compute thread;
  ;; #f while the worker idles on its request channel.
  (define %task-scope (make-thread-parameter #f))

  ;; Thunks a compute thread wants run on the loop thread — resuming
  ;; a fiber whose channel get a worker's put just completed. Drained
  ;; by the collector fiber, woken through the eventfd.
  (define %cross-thread-spawns (box '()))
  (define %flow2-eventfd #f)
  (define %flow2-workers-running? #f)

  ;; One 8-byte buffer holding the value 1, allocated with the eventfd
  ;; and never written again, so every cross-thread wake-up is a bare
  ;; write(2) instead of a foreign-alloc / foreign-free pair on the
  ;; hottest path this pool has. Shared by every worker, which is safe
  ;; precisely because nobody mutates it after this.
  (define %flow2-eventfd-buffer #f)

  ;; Worker liveness, so shutdown can join rather than hope. The count
  ;; is guarded by the mutex rather than CAS'd because the waiter needs
  ;; a condition variable anyway.
  (define %flow2-workers-live 0)
  (define %flow2-workers-mutex (make-mutex))
  (define %flow2-workers-gone (make-condition))

  (define (%flow-worker-exited!)
    (with-mutex %flow2-workers-mutex
      (set! %flow2-workers-live (fx- %flow2-workers-live 1))
      (condition-broadcast %flow2-workers-gone)))

  (define %eventfd-create
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "eventfd" (unsigned-int int) int)))
      (lambda ()
        (call-with-values (lambda () (func 0 0))
          (lambda (fd errno)
            (when (fx<? fd 0)
              (error 'flow-run "eventfd failed" errno))
            fd)))))

  (define %eventfd-signal!
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "write" (int void* size_t) integer-64)))
      (lambda (fd)
        (call-with-values (lambda () (func fd %flow2-eventfd-buffer 8))
          (lambda (n errno) (>= n 0))))))

  (define %eventfd-close
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "close" (int) int)))
      (lambda (fd) (call-with-values (lambda () (func fd)) (lambda (r e) r)))))

  ;; Park the collector fiber on FD until a worker signals it.
  ;; Reads into a buffer owned by the pool rather than one allocated
  ;; per wait. The collector parks here and, at shutdown, is simply
  ;; never resumed -- the loop has stopped -- so a per-wait allocation
  ;; was freed on every path except the one that always happens, and
  ;; leaked eight bytes plus its header per flow-run.
  (define %eventfd-wait
    (lambda (fd)
      (let* ((sqe (loop-get-sqe (loop-ring (loop-current))))
             (id (loop-alloc-id!)))
        (io-uring-prep-read sqe fd %flow2-eventfd-buffer 8 0)
        (io-uring-sqe-set-data64 sqe id)
        (loop-abort
         (lambda (k)
           (hashtable-set! (loop-handlers (loop-current)) id k))))))

  ;; loop-spawn from the loop thread (the hot path, untouched); from
  ;; a compute thread, queue the thunk and wake the loop through the
  ;; eventfd. Only channel internals reach this from a worker — there
  ;; is deliberately no user-facing cross-thread spawn.
  (define %flow-spawn-safe
    (lambda (thunk)
      (if (%worker-current?)
          (begin
            (unless %flow2-eventfd
              (error 'flow2 "cross-thread resume with no compute pool running"))
            (flow-box-cons! %cross-thread-spawns thunk)
            (%eventfd-signal! %flow2-eventfd))
          (loop-spawn thunk))))

  ;; The reverse is load-bearing. flow-box-drain! yields newest-first,
  ;; and loop-spawn conses, so spawning the drained list as-is REVERSES
  ;; it a second time relative to loop-run-once's front-to-back walk:
  ;; two thunks a worker queued in order A, B would run B first. That
  ;; silently broke resume-from's cancels-before-k ordering for every
  ;; worker-completed rendezvous — the resumed fiber ran before the
  ;; losers' cancels, and a fiber that re-performed flow-accept right
  ;; after winning a worker's put against it raised "concurrent accept
  ;; on fd", the exact regression the on-loop spawn order fix closed.
  ;; Reversing restores cons order into loop-spawn's LIFO, so a
  ;; worker's spawn-safe calls behave like the same calls made on-loop.
  (define %collector
    (lambda ()
      (let loop ()
        (when %flow2-workers-running?
          (%eventfd-wait %flow2-eventfd)
          (for-each loop-spawn (reverse (flow-box-drain! %cross-thread-spawns)))
          (loop)))))

  ;;------------------------------------------------------------
  ;; Scopes (nurseries)
  ;;------------------------------------------------------------

  ;; state box holds 'open, or the reason the scope died:
  ;;   (failed . obj)  — a child (or the nursery body) raised OBJ
  ;;   cancelled       — flow-scope-cancel!
  ;;   timeout         — flow-monitor's deadline
  ;; The box-cas! from 'open is what makes "first error wins" and
  ;; idempotent cancellation fall out with no further bookkeeping.
  ;;
  ;; waiters is a CAS list — a compute-thread task parked on a
  ;; channel registers its scope waiter from its own thread — of
  ;; (state . resume) pairs. children is a CAS box for the same reason:
  ;; a scope owns the compute tasks submitted inside it, and a worker
  ;; finishing one has to decrement from its own thread. join-waiters
  ;; and subscopes stay loop-thread-only, which is why waking the
  ;; joiners is marshalled back onto the loop.
  (define-record-type* <flow2-scope>
    (make-flow-scope% parent state waiters waiter-count
                      children join-waiters subscopes)
    flow-scope?
    (parent       flow-scope-parent)
    (state        flow-scope-state)
    (waiters      flow-scope-waiters)
    (waiter-count flow-scope-waiter-count)
    (children     flow-scope-children     flow-scope-children!)
    (join-waiters flow-scope-join-waiters flow-scope-join-waiters!)
    (subscopes    flow-scope-subscopes    flow-scope-subscopes!))

  (define (%make-scope parent)
    (make-flow-scope% parent (box 'open) (box '()) (box 0) (box 0) '() '()))

  ;; The root scope: never cancelled, and the flag flow-perform tests
  ;; to keep the hot path — every fiber outside any nursery — free of
  ;; scope bookkeeping.
  (define %root-scope (%make-scope #f))

  ;; The current scope of the running fiber. A plain global, not a
  ;; parameter: it travels with the fiber by being reinstalled at
  ;; every entry point — flow-spawn's wrapper, and the resume path in
  ;; flow-block-and-wait-on-loop — rather than through dynamic-wind,
  ;; which this suspend/resume model rejects (see flow-open in flow).
  (define %scope-current %root-scope)

  (define (%scope-dead? scope)
    (not (eq? (unbox (flow-scope-state scope)) 'open)))

  (define (flow-cancelled?)
    (if (%worker-current?)
        (let ((scope (%task-scope)))
          (and scope (%scope-dead? scope)))
        (and (not (eq? %scope-current %root-scope))
             (%scope-dead? %scope-current))))

  ;; Every 64 registrations, drop the waiters whose perform already
  ;; synched on another base — their state box is no longer 'waiting.
  (define %scope-waiter-gc-threshold 64)

  (define (%scope-waiter-compact! scope)
    (let ((b (flow-scope-waiters scope)))
      (let ((lst (unbox b)))
        (unless (box-cas! b lst
                          (filter (lambda (entry)
                                    (eq? (unbox (car entry)) 'waiting))
                                  lst))
          (%scope-waiter-compact! scope)))))

  (define (%scope-add-waiter! scope state resume)
    (flow-box-cons! (flow-scope-waiters scope) (cons state resume))
    ;; Recheck AFTER publishing, and wake ourselves if the scope died
    ;; in between. %scope-fail! CASes the state and then drains this
    ;; list, so a registration that lands after that drain is attached
    ;; to a corpse and nothing will ever resume it. On the loop thread
    ;; the window does not exist — nothing yields between the caller's
    ;; liveness check and this cons — but a compute thread registers
    ;; its own waiter from its own thread (see the record comment
    ;; above), and losing that race parks the worker on its condition
    ;; variable forever: the pool shrinks by one, silently, while the
    ;; main program keeps working. Resuming twice is harmless because
    ;; resume CASes the shared state box, so the loser is a no-op.
    (when (%scope-dead? scope)
      (resume %flow-cancel-sentinel))
    (let ((n (let ((b (flow-scope-waiter-count scope)))
               (let bump ()
                 (let ((n (unbox b)))
                   (if (box-cas! b n (fx+ n 1)) (fx+ n 1) (bump)))))))
      (when (fx>=? n %scope-waiter-gc-threshold)
        (set-box! (flow-scope-waiter-count scope) 0)
        (%scope-waiter-compact! scope))))

  ;; Kill SCOPE with REASON — loop thread only. Idempotent: only the
  ;; first reason wins the CAS; a later child raise inside an
  ;; already-cancelled scope changes nothing. Resuming a waiter with
  ;; the sentinel is what fires the losing siblings' register-cancel!
  ;; thunks (flow-block-and-wait's resume-from), i.e. what cancels
  ;; the subtree's in-flight ring operations. Subscopes die
  ;; transitively, as 'cancelled.
  (define (%scope-fail! scope reason)
    (when (box-cas! (flow-scope-state scope) 'open reason)
      (for-each (lambda (entry)
                  ((cdr entry) %flow-cancel-sentinel))
                (flow-box-drain! (flow-scope-waiters scope)))
      (for-each (lambda (sub) (%scope-fail! sub 'cancelled))
                (flow-scope-subscopes scope))))

  (define (flow-scope-cancel! scope)
    (when (%worker-current?) (%flow-wrong-thread 'flow-scope-cancel!))
    (%scope-fail! scope 'cancelled))

  (define (%scope-children scope)
    (unbox (flow-scope-children scope)))

  ;; Both directions CAS, because flow-submit! may be called from a
  ;; worker and %worker-body always decrements from one.
  (define (%scope-child-add! scope)
    (let bump ()
      (let ((n (unbox (flow-scope-children scope))))
        (unless (box-cas! (flow-scope-children scope) n (fx+ n 1))
          (bump)))))

  ;; One child returned or raised; at zero, resume the join. The
  ;; decrement is safe from any thread; waking the joiners is not --
  ;; join-waiters is a plain loop-thread-only list -- so a worker
  ;; marshals that half back onto the loop.
  (define (%scope-child-done! scope)
    (let ((n (let drop ()
               (let ((n (unbox (flow-scope-children scope))))
                 (if (box-cas! (flow-scope-children scope) n (fx- n 1))
                     (fx- n 1)
                     (drop))))))
      (when (fxzero? n)
        (if (%worker-current?)
            (%flow-spawn-safe (lambda () (%scope-wake-joiners! scope)))
            (%scope-wake-joiners! scope)))))

  ;; Loop thread only. Rechecks the count rather than trusting the
  ;; caller's: a marshalled wake-up runs a tick later, by which time
  ;; another task may have been submitted into the same scope.
  (define (%scope-wake-joiners! scope)
    (when (fxzero? (%scope-children scope))
      (let ((waiters (flow-scope-join-waiters scope)))
        (flow-scope-join-waiters! scope '())
        (for-each (lambda (resume) (resume #t)) waiters))))

  ;; The scope's own cancellation, as a base event: the implicit
  ;; extra member flow-perform adds to every synchronization inside a
  ;; cancellable scope. try is ready exactly when the scope is dead;
  ;; block registers this perform's shared state/resume as a waiter.
  (define (%scope-cancel-base scope)
    (make-flow% 'base (cons 'flow2-scope scope)
                (lambda (x) x)
                (lambda ()
                  (and (%scope-dead? scope)
                       (lambda () %flow-cancel-sentinel)))
                (lambda (state resume register-cancel!)
                  (%scope-add-waiter! scope state resume))))

  ;; Ready when the scope has no live children. Internal — the
  ;; nursery join and flow-monitor's deadline race use it.
  (define (%scope-join-event scope)
    (make-flow% 'base (cons 'flow2-scope scope)
                (lambda (x) x)
                (lambda ()
                  (and (fxzero? (%scope-children scope))
                       (lambda () #t)))
                (lambda (state resume register-cancel!)
                  (flow-scope-join-waiters!
                   scope (cons resume (flow-scope-join-waiters scope))))))

  ;;------------------------------------------------------------
  ;; Synchronization: poll, then park
  ;;------------------------------------------------------------

  ;; SCOPE is the fiber's scope at perform time, reinstalled around
  ;; the parked continuation so the fiber wakes up where it went to
  ;; sleep. Everything else is flow's design unchanged: one shared
  ;; state box CAS-elects a single winner, each base gets its own
  ;; wrap-applying resume, the losers' register-cancel! thunks fire
  ;; the instant any base wins, and both the cancels and the
  ;; continuation defer through %flow-spawn-safe because the party
  ;; completing the rendezvous may be a compute thread.
  (define flow-block-and-wait-on-loop
    (lambda (bases scope)
      (let ((state (box 'waiting))
            (cancels (box '())))
        (loop-abort
         (lambda (k)
           (define resume-from
             (lambda (tag value)
               (and (box-cas! state 'waiting 'synched)
                    (begin
                      ;; k is spawned FIRST so that it runs LAST:
                      ;; loop-spawn conses and loop-run-once walks the
                      ;; list front to back, so the thunk queued last
                      ;; runs first. The losers' cancels must land
                      ;; before the resumed fiber does anything, because
                      ;; a cancel can free a resource the fiber
                      ;; immediately reuses — flow-accept's cancel
                      ;; releases the multishot's single handler slot,
                      ;; and a fiber that re-accepts before it runs gets
                      ;; "concurrent accept on fd" instead. Still two
                      ;; separate thunks, so a raising cancel is
                      ;; confined by loop-apply's guard and k survives.
                      (%flow-spawn-safe
                       (lambda ()
                         (set! %scope-current scope)
                         (k value)))
                      (%flow-spawn-safe
                       (lambda ()
                         (for-each (lambda (pair)
                                     (unless (eq? (car pair) tag)
                                       ((cdr pair))))
                                   (unbox cancels))))
                      #t))))
           ;; Registration runs on the scheduler's stack, so a raise
           ;; here cannot reach the fiber by unwinding — see
           ;; <flow2-raise>. Catch it and elect it this perform's
           ;; winner: ERROR-TAG matches no base, so every already
           ;; registered base's cancel fires, and the fiber resumes into
           ;; %flow-settle, which re-raises on its own stack. The bases
           ;; after the failing one never register, which is what we
           ;; want — this perform is over.
           (let ((error-tag (cons #f #f)))
             (guard (ex (#t
                         ;; A base may already have won synchronously
                         ;; during registration, in which case the
                         ;; fiber is committed to that value and the
                         ;; CAS fails. Report rather than swallow: a
                         ;; silently dropped raise here is exactly the
                         ;; undebuggable-hang shape loop-apply's own
                         ;; guard comment warns about.
                         (unless (resume-from error-tag (%make-flow-raise ex))
                           (display "flow2: block registration raised after another base won: "
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
                                          (cons (cons tag thunk)
                                                (unbox cancels)))))))
                         bases))))))))

  ;; A compute thread is not a fiber: it parks on a condition
  ;; variable, and its resume fills a slot and broadcasts. Only
  ;; channel and scope bases reach here — %flow-perform-off-loop
  ;; rejects ring events before registration — and their block procs
  ;; touch only mutex- or CAS-protected state, so registration runs
  ;; inline on this thread with no marshalling.
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
                   (let ((pending (unbox cancels)))
                     (when (pair? pending)
                       (%flow-spawn-safe
                        (lambda ()
                          (for-each (lambda (pair)
                                      (unless (eq? (car pair) tag)
                                        ((cdr pair))))
                                    pending)))))
                   (with-mutex mutex
                     (set! slot value)
                     (set! done? #t)
                     (condition-broadcast ready))
                   #t))))
        ;; Registration runs on this thread's own stack, so unlike the
        ;; on-loop case a raise here does propagate to the task's guard
        ;; by itself. What it would leave behind is the bases that DID
        ;; register — a channel getter entry, say — still live and
        ;; pointing at a perform nobody will ever complete. Mark this
        ;; perform synched so the next deliverer drops that entry, fire
        ;; whatever cancels were registered, then let the raise go.
        (guard (ex (#t
                    (box-cas! state 'waiting 'synched)
                    (let ((pending (unbox cancels)))
                      (when (pair? pending)
                        (%flow-spawn-safe
                         (lambda ()
                           (for-each (lambda (pair) ((cdr pair))) pending)))))
                    (raise ex)))
          (for-each (lambda (base)
                      (let ((tag (cons #f #f)))
                        ((flow-block-proc base) state
                         (lambda (raw)
                           (resume-from tag ((flow-wrap-proc base) raw)))
                         (lambda (thunk)
                           (set-box! cancels
                                     (cons (cons tag thunk)
                                           (unbox cancels)))))))
                    bases))
        (with-mutex mutex
          (let wait ()
            (unless done?
              (condition-wait ready mutex)
              (wait))))
        slot)))

  ;; A base is safe to synchronize on from a compute thread only when
  ;; its try/block touch nothing but mutex- or CAS-protected state:
  ;; channel gets and scope bases qualify, anything that preps an SQE
  ;; or reads loop tables does not.
  (define (%base-off-loop-safe? base)
    (let ((tag (flow-data base)))
      (and (pair? tag)
           (memq (car tag) '(flow2-get flow2-space flow2-scope))
           #t)))

  (define (%flow-perform-off-loop event)
    (let ((scope (%task-scope)))
      (when (and scope (%scope-dead? scope))
        (raise (%flow-cancelled-error)))
      (let ((bases (flow-flatten event)))
        (for-each (lambda (base)
                    (unless (%base-off-loop-safe? base)
                      (%flow-wrong-thread 'flow-perform)))
                  bases)
        (let ((bases (if (and scope (not (eq? scope %root-scope)))
                         (append bases (list (%scope-cancel-base scope)))
                         bases)))
          (let ((result (flow-poll bases)))
            (%flow-settle (if (eq? result %flow-not-ready)
                              (flow-block-and-wait-off-loop bases)
                              result)))))))

  (define flow-perform
    (lambda (event)
      (if (%worker-current?)
          (%flow-perform-off-loop event)
          (let ((scope %scope-current))
            (if (eq? scope %root-scope)
                ;; Hot path: no scope test, no extra base, exactly
                ;; flow's perform.
                (let ((bases (flow-flatten event)))
                  (let ((result (flow-poll bases)))
                    (if (eq? result %flow-not-ready)
                        ;; %flow-settle, not a bare return: the cancel
                        ;; sentinel cannot reach here (no scope base
                        ;; under the root scope) but a block-proc raise
                        ;; can, and a root-scope fiber must see it too.
                        (%flow-settle
                         (flow-block-and-wait-on-loop bases scope))
                        result)))
                (begin
                  (when (%scope-dead? scope)
                    (raise (%flow-cancelled-error)))
                  (let ((bases (append (flow-flatten event)
                                       (list (%scope-cancel-base scope)))))
                    (let ((result (flow-poll bases)))
                      (%flow-settle (if (eq? result %flow-not-ready)
                                        (flow-block-and-wait-on-loop bases scope)
                                        result))))))))))

  ;;------------------------------------------------------------
  ;; Channels: buffered, mutex-protected, cross-thread
  ;;------------------------------------------------------------

  ;; One channel type for every role — fiber↔fiber, worker request
  ;; channels, response channels. Unbounded by default; a bound turns
  ;; an over-capacity put into a raised overflow. The mutex guards
  ;; the value queue (two-stack FIFO), the parked getters and the
  ;; bound; it is held only for list surgery, never across a resume.
  (define-record-type* <flow2-channel>
    (make-flow-channel% name mutex in out length bound getters
                        space saturated?)
    flow-channel?
    (name    flow-channel-name)
    (mutex   flow-channel-mutex)
    (in      flow-channel-in      flow-channel-in!)
    (out     flow-channel-out     flow-channel-out!)
    (length  flow-channel-length  flow-channel-length!)
    (bound   flow-channel-bound   flow-channel-bound!)
    (getters flow-channel-getters flow-channel-getters!)
    ;; Putters parked because the channel is full, oldest first.
    (space   flow-channel-space   flow-channel-space!)
    ;; Edge-trigger for the saturation warning; see
    ;; %channel-warn-saturated!.
    (saturated? flow-channel-saturated? flow-channel-saturated?!))

  ;; Every channel carries a name, and one created without a name still
  ;; gets a process-unique integer rather than nothing. A diagnostic
  ;; that cannot say WHICH channel is in trouble is barely better than
  ;; no diagnostic: (letloop flow) learned that from a hang it could not
  ;; attribute, and bolted sequential ids onto channels through a weak
  ;; hashtable purely so its trace could name them. This is that, made
  ;; deliberate and always on.
  ;;
  ;; The auto name is the integer itself rather than a symbol built from
  ;; it. Chez interns symbols for the life of the process, so minting
  ;; one per channel would leak steadily in a program that creates
  ;; channels in a loop — which is exactly the kind of program whose
  ;; channel diagnostics you end up reading.
  (define %flow-channel-counter (box 0))

  ;; Bounded by default, because unbounded is not a capacity choice —
  ;; it is the decision to convert a rate mismatch into unbounded
  ;; memory growth and discover it as an OOM hours later. flow's own
  ;; history is the argument: a channel that accumulated entries for a
  ;; process lifetime cost 44GB before anyone could name the cause.
  ;;
  ;; The particular number matters far less than its being finite, and
  ;; a full put PARKS rather than raising, so a bound set too low costs
  ;; throughput and never correctness. Pass #f for a genuinely
  ;; unbounded channel, deliberately and visibly at the call site.
  (define %flow-channel-default-bound 43)

  (define make-flow-channel
    (case-lambda
      (() (make-flow-channel (flow-box-increment! %flow-channel-counter)))
      ((name) (make-flow-channel name %flow-channel-default-bound))
      ((name bound)
       (unless (or (not bound) (and (fixnum? bound) (fx>? bound 0)))
         (error 'make-flow-channel
                "bound must be a positive fixnum, or #f for unbounded"
                bound))
       (make-flow-channel% name (make-mutex) '() '() 0 bound '() '() #f))))

  ;; A parked getter: the perform's shared state box and this base's
  ;; own wrap-applying resume, plus the claimed box that gives one
  ;; deliverer exclusivity before it calls resume (the same
  ;; discipline flow's rendezvous used; scope cancellation may still
  ;; win the underlying state CAS, which is why %channel-deliver!
  ;; rechecks resume's own return value).
  (define-record-type* <flow2-getter>
    (make-flow-getter state resume claimed)
    flow-getter?
    (state   flow-getter-state)
    (resume  flow-getter-resume)
    (claimed flow-getter-claimed))

  ;; Caller holds the channel mutex. Pop the first claimable waiting
  ;; getter, dropping dead entries on the way.
  (define (%channel-pop-getter! channel)
    (let loop ((getters (flow-channel-getters channel)) (kept '()))
      (cond
       ((null? getters)
        (flow-channel-getters! channel (reverse kept))
        #f)
       ((and (eq? (unbox (flow-getter-state (car getters))) 'waiting)
             (box-cas! (flow-getter-claimed (car getters)) #f #t))
        (flow-channel-getters! channel
                               (append (reverse kept) (cdr getters)))
        (car getters))
       ((eq? (unbox (flow-getter-state (car getters))) 'waiting)
        ;; claimed by a concurrent deliverer, keep it
        (loop (cdr getters) (cons (car getters) kept)))
       (else (loop (cdr getters) kept)))))

  ;; Caller holds the channel mutex.
  (define (%channel-room? channel)
    (let ((bound (flow-channel-bound channel)))
      (or (not bound) (fx<? (flow-channel-length channel) bound))))

  ;; Caller holds the channel mutex. Callers that dequeue must call
  ;; %channel-wake-space! afterwards, OUTSIDE the mutex — a resume can
  ;; run arbitrary continuation code and must never do so under a lock
  ;; this library takes on both the loop thread and a worker.
  (define (%channel-dequeue! channel)
    (when (null? (flow-channel-out channel))
      (flow-channel-out! channel (reverse (flow-channel-in channel)))
      (flow-channel-in! channel '()))
    (let ((value (car (flow-channel-out channel))))
      (flow-channel-out! channel (cdr (flow-channel-out channel)))
      (flow-channel-length! channel (fx- (flow-channel-length channel) 1))
      ;; Re-arm the saturation warning only once the queue has drained
      ;; to half the bound, not on the first dequeue. Without the
      ;; hysteresis a channel sitting AT its bound with a brisk consumer
      ;; warns on every single item — a log flood at exactly the moment
      ;; the log is worth reading.
      (let ((bound (flow-channel-bound channel)))
        (when (and (flow-channel-saturated? channel)
                   bound
                   (fx<=? (flow-channel-length channel) (fxdiv bound 2)))
          (flow-channel-saturated?! channel #f)))
      value))

  ;; Wake putters parked on a full channel, now that there is room.
  ;; Called outside the mutex. A waiter whose resume reports #f synched
  ;; on another base — a scope cancellation, say — so move to the next;
  ;; nothing is lost either way, since a space waiter carries no value.
  (define (%channel-wake-space! channel)
    (let again ()
      (let ((waiter
             (with-mutex (flow-channel-mutex channel)
               (and (%channel-room? channel)
                    (let ((waiters (flow-channel-space channel)))
                      (and (pair? waiters)
                           (begin
                             (flow-channel-space! channel (cdr waiters))
                             (car waiters))))))))
        (when waiter
          (unless ((cdr waiter) #t)
            (again))))))

  (define (%channel-remove-space! channel waiter)
    (with-mutex (flow-channel-mutex channel)
      (flow-channel-space!
       channel
       (remq waiter (flow-channel-space channel)))))

  ;; One line per saturation episode, not per blocked put. The flag is
  ;; set here and cleared by %channel-dequeue! at the half-bound
  ;; watermark, so a channel that stays pinned at its bound produces one
  ;; warning, and a channel that recovers and saturates again produces a
  ;; second — which is the signal you actually want.
  (define (%channel-warn-saturated! channel)
    (let ((warn?
           (with-mutex (flow-channel-mutex channel)
             (and (not (flow-channel-saturated? channel))
                  (begin (flow-channel-saturated?! channel #t) #t)))))
      (when warn?
        (flow-log (list 'flow2 'channel-full
                        (flow-channel-name channel)
                        (flow-channel-bound channel))))))

  ;; Deliver OBJ to a parked getter, or enqueue it. FORCE? skips the
  ;; bound — the worker guard's error reply uses it, so always-a-reply
  ;; holds even on a full bounded channel. The resume call happens
  ;; outside the mutex; if it reports the getter already synched
  ;; elsewhere (a scope cancellation won the race), try the next one.
  (define (%channel-put! channel obj force?)
    (let try ()
      (let ((entry
             (with-mutex (flow-channel-mutex channel)
               (let ((getter (%channel-pop-getter! channel)))
                 (or getter
                     ;; Handing a value straight to a parked getter does
                     ;; not grow the queue, so the bound is only
                     ;; consulted once there is nobody waiting for it.
                     (if (and (not force?) (not (%channel-room? channel)))
                         'full
                         (begin
                           (flow-channel-in!
                            channel (cons obj (flow-channel-in channel)))
                           (flow-channel-length!
                            channel (fx+ (flow-channel-length channel) 1))
                           #f)))))))
        (cond
         ((eq? entry 'full)
          (%channel-await-space! channel)
          ;; Room existed when we were woken, but another putter may
          ;; have taken it in between, so this is a retry and not an
          ;; assumption.
          (try))
         (entry
          (unless ((flow-getter-resume entry) obj)
            (try)))
         (else (void))))))

  ;; Park until the channel has room. Parking needs a scheduler: a
  ;; worker parks on its condition variable, a fiber parks on the loop.
  ;; With neither — a bare flow-put! outside flow-run — there is nothing
  ;; to park on, and pretending otherwise would hang the caller with no
  ;; diagnosis, so that case keeps the old behaviour and raises.
  (define (%channel-await-space! channel)
    (%channel-warn-saturated! channel)
    (if (or (%worker-current?)
            (let ((loop (loop-current)))
              (and loop (loop-running? loop))))
        (flow-perform (%flow-space channel))
        (raise (make-flow-error
                'overflow
                "flow2: channel full and no scheduler to park on"
                (list (flow-channel-name channel)
                      (flow-channel-bound channel))
                #f))))

  ;; "There is room in this channel." Deliberately not exported and
  ;; never handed to a caller: flow-put! performs it internally, which
  ;; is what lets put block without becoming an event. That distinction
  ;; is the whole reason flow's same-channel-choice hazard stays
  ;; inexpressible here — the hazard needs a put EVENT to compose into a
  ;; choice, not a put that happens to suspend.
  (define (%flow-space channel)
    (make-flow% 'base (cons 'flow2-space channel)
                (lambda (x) x)
                (lambda ()
                  (with-mutex (flow-channel-mutex channel)
                    (and (%channel-room? channel)
                         (lambda () #t))))
                (lambda (state resume register-cancel!)
                  (let ((waiter (cons state resume)))
                    ;; Armed before the waiter is reachable, with the
                    ;; recheck below closing the rest of the window —
                    ;; same discipline as flow-get's getter entry, and
                    ;; for the same reason: off-loop, resume-from
                    ;; snapshots the cancel list at resume time.
                    (register-cancel!
                     (lambda () (%channel-remove-space! channel waiter)))
                    (let ((room?
                           (with-mutex (flow-channel-mutex channel)
                             (or (%channel-room? channel)
                                 (begin
                                   (flow-channel-space!
                                    channel
                                    (append (flow-channel-space channel)
                                            (list waiter)))
                                   #f)))))
                      (if room?
                          ;; No value rides on this resume, so a #f
                          ;; needs no recovery: the caller simply stays
                          ;; committed to whichever base did win.
                          (resume #t)
                          (unless (eq? (unbox state) 'waiting)
                            (%channel-remove-space! channel waiter))))))))

  ;; Return OBJ to CHANNEL after a getter that had already claimed and
  ;; dequeued it turned out to have synched on another base — the value
  ;; is out of the queue and its claimant will never receive it, so
  ;; without this it is simply gone. Hand it to another parked getter
  ;; if there is one, exactly as a put would; otherwise push it back at
  ;; the HEAD of the queue, because that is where it was taken from and
  ;; appending it would reorder a FIFO. The bound is not consulted: the
  ;; value was already inside it a moment ago, so re-admitting it
  ;; cannot violate it, and raising overflow here would destroy the
  ;; value this procedure exists to preserve.
  (define (%channel-unget! channel obj)
    (let try ()
      (let ((entry
             (with-mutex (flow-channel-mutex channel)
               (or (%channel-pop-getter! channel)
                   (begin
                     (flow-channel-out!
                      channel (cons obj (flow-channel-out channel)))
                     (flow-channel-length!
                      channel (fx+ (flow-channel-length channel) 1))
                     #f)))))
        (when entry
          (unless ((flow-getter-resume entry) obj)
            (try))))))

  ;; Drop ENTRY from CHANNEL's getters list. A concurrent deliverer may
  ;; already have popped it, in which case this is a no-op — that
  ;; deliverer's own resume returns #f and %channel-put! retries, so no
  ;; value rides on the race.
  (define (%channel-remove-getter! channel entry)
    (with-mutex (flow-channel-mutex channel)
      (flow-channel-getters!
       channel
       (remq entry (flow-channel-getters channel)))))

  ;; A cancelled sender's sends are dropped — the raise is how it
  ;; observes its own death at the next channel operation.
  ;;
  ;; flow-cancelled?, not a compute-thread test. This used to check only
  ;; when running on a worker, so the guarantee held on one side of the
  ;; thread boundary and not the other: a main-thread fiber in a
  ;; cancelled scope could keep putting indefinitely as long as it never
  ;; performed a suspending event, while the identical code on a worker
  ;; raised at once. The README's "channel operations check it
  ;; implicitly" reads as universal, and now is.
  (define (flow-put! channel obj)
    (when (flow-cancelled?)
      (raise (%flow-cancelled-error)))
    (%channel-put! channel obj #f))

  ;; try and block both hold the mutex, so there is no try/park gap
  ;; for a concurrent put to fall into: either the value is already
  ;; queued (try or block's own recheck takes it) or the getter is
  ;; registered before any later put can scan for it.
  (define (flow-get channel)
    (make-flow% 'base (cons 'flow2-get channel)
                (lambda (x) x)
                (lambda ()
                  (let ((value
                         (with-mutex (flow-channel-mutex channel)
                           (and (fx>? (flow-channel-length channel) 0)
                                (list (%channel-dequeue! channel))))))
                    (and value
                         (begin
                           ;; outside the mutex: a resume runs
                           ;; continuation code
                           (%channel-wake-space! channel)
                           (lambda () (car value))))))
                (lambda (state resume register-cancel!)
                  (let ((entry (make-flow-getter state resume (box #f))))
                    ;; Armed BEFORE the entry is reachable, and the
                    ;; recheck below closes the remaining window. Without
                    ;; a cancel at all, a get that loses a choice leaves
                    ;; its entry on the list forever: the only reaper is
                    ;; %channel-pop-getter!, which runs only from a put,
                    ;; so a channel that is polled and never written —
                    ;; (flow-choice (flow-get ch) (flow-timeout 0.1)),
                    ;; the ordinary idle shape — grows without bound, and
                    ;; each dead entry pins a whole captured continuation
                    ;; through its resume.
                    (register-cancel!
                     (lambda () (%channel-remove-getter! channel entry)))
                    (let ((immediate
                           (with-mutex (flow-channel-mutex channel)
                             (if (fx>? (flow-channel-length channel) 0)
                                 (and (box-cas! (flow-getter-claimed entry) #f #t)
                                      (cons #t (%channel-dequeue! channel)))
                                 (begin
                                   (flow-channel-getters!
                                    channel
                                    (append (flow-channel-getters channel)
                                            (list entry)))
                                   #f)))))
                      (when immediate (%channel-wake-space! channel))
                      (if immediate
                          ;; resume reports #f when an earlier base of
                          ;; this same perform already won — registration
                          ;; is a for-each with no early exit, so a base
                          ;; that resumed inline is followed by every
                          ;; later base's block. The value is already out
                          ;; of the queue at that point, so put it back
                          ;; rather than drop it. %channel-put! has made
                          ;; the same test since day one.
                          (unless (resume (cdr immediate))
                            (%channel-unget! channel (cdr immediate)))
                          ;; The entry only became reachable just now, so
                          ;; a winner that fired the cancels before this
                          ;; point missed it — off-loop, resume-from
                          ;; snapshots the cancel list at resume time.
                          ;; Same recheck-after-publish as
                          ;; %scope-add-waiter!.
                          (unless (eq? (unbox state) 'waiting)
                            (%channel-remove-getter! channel entry))))))))

  (define (flow-get! channel)
    (flow-perform (flow-get channel)))

  ;; Same symmetry as flow-put!: a non-suspending get is still a channel
  ;; operation, and a cancelled scope must be observable through it on
  ;; either thread. Without this a main-thread fiber could drain a
  ;; channel for as long as it liked after its scope died.
  (define (flow-get-try channel default)
    (when (flow-cancelled?)
      (raise (%flow-cancelled-error)))
    (let ((value
           (with-mutex (flow-channel-mutex channel)
             (and (fx>? (flow-channel-length channel) 0)
                  (list (%channel-dequeue! channel))))))
      (cond
       (value
        ;; outside the mutex: a resume runs continuation code
        (%channel-wake-space! channel)
        (car value))
       (else default))))

  ;;------------------------------------------------------------
  ;; Diagnostics: raw internal lengths
  ;;------------------------------------------------------------
  ;;
  ;; (letloop flow) gained flow-channel-puts-length /
  ;; flow-channel-pops-length after its 44GB incident, commented as
  ;; existing "to tell apart logically empty (put-count = get-count)
  ;; from channel has released its internal state". Per TODO.md that
  ;; instrumentation is what finally confirmed the leak after the
  ;; business logic had been exonerated by eight repeated-allocation
  ;; passes: the raw puts list held 62 entries at 70 cumulative puts
  ;; while logical pending stayed exactly 0.
  ;;
  ;; The whole point is that these are RAW list lengths, not logical
  ;; ones. A structure holding entries nobody will ever resume looks
  ;; identical from the outside to one that is genuinely idle, and
  ;; every leak in this family — flow's §1.1, flow2's finding 4 — is
  ;; the gap between the two. Without a way to read both numbers you
  ;; are reduced to guessing from RSS.
  ;;
  ;; flow2 has three such structures, so all three are readable:
  ;; a channel's parked getters, its parked putters, and a scope's
  ;; waiter lists — flow-scope-join-waiters in particular has neither
  ;; compaction nor removal, only the implicit filter of a resume
  ;; returning #f.

  ;; Values currently queued. The logical number: what a getter would
  ;; find.
  (define (flow-channel-queue-length channel)
    (with-mutex (flow-channel-mutex channel)
      (flow-channel-length channel)))

  ;; Entries on the getters list, dead ones included. Compare against
  ;; the number of fibers you believe are actually parked on this
  ;; channel; a gap that grows is finding 4's shape.
  (define (flow-channel-getters-length channel)
    (with-mutex (flow-channel-mutex channel)
      (length (flow-channel-getters channel))))

  ;; Putters parked waiting for room. Persistently non-zero means
  ;; sustained backpressure — pair it with the (flow2 channel-full ...)
  ;; warning, which fires once per saturation episode.
  (define (flow-channel-space-length channel)
    (with-mutex (flow-channel-mutex channel)
      (length (flow-channel-space channel))))

  ;; A scope's own bookkeeping: children still running, fibers parked
  ;; on its cancellation, and fibers parked on its join.
  (define (flow-scope-children-count scope)
    (%scope-children scope))

  (define (flow-scope-waiters-length scope)
    (length (unbox (flow-scope-waiters scope))))

  ;; A plain list field, unlike flow-scope-waiters, which is a CAS box:
  ;; the join list is only ever touched from the loop thread.
  (define (flow-scope-join-waiters-length scope)
    (length (flow-scope-join-waiters scope)))

  ;; Raises overflow right here when the channel already holds more
  ;; than N values: the bound is never observably violated, and the
  ;; queue-vs-bound mismatch surfaces at the call site that made it.
  ;; The domain is make-flow-channel's: a positive fixnum, or #f for
  ;; unbounded. Zero used to slip through here — the constructor
  ;; rejects it — and produced a channel that could never make progress
  ;; put-first: the put parks on space, space waiters are only woken by
  ;; a dequeue, and nothing can ever enter a zero-bound queue, so
  ;; put-then-get deadlocked while get-then-put happened to work (a put
  ;; hands its value straight to a parked getter, skipping the queue) —
  ;; an order-dependent hang, the worst kind. And #f was refused, so a
  ;; bounded channel could never be made unbounded even though the
  ;; constructor allows creating one.
  (define (flow-channel-buffer-size! channel n)
    (unless (or (not n) (and (fixnum? n) (fx>? n 0)))
      (error 'flow-channel-buffer-size!
             "bound must be a positive fixnum, or #f for unbounded" n))
    (let ((wake
           (with-mutex (flow-channel-mutex channel)
             (when (and n (fx>? (flow-channel-length channel) n))
               (raise (make-flow-error 'overflow
                                       "flow2: channel already over the requested bound"
                                       (list n (flow-channel-length channel)) #f)))
             (flow-channel-bound! channel n)
             ;; Slots the new bound just opened, each owed one parked
             ;; putter. %channel-wake-space! otherwise only runs after
             ;; a dequeue, so growing the bound would leave putters
             ;; parked despite the room until the next get — and a
             ;; consumer that stopped consuming is exactly when an
             ;; operator raises a bound to relieve the producers.
             (let ((waiting (length (flow-channel-space channel))))
               (if n
                   (fxmin waiting
                          (fxmax 0 (fx- n (flow-channel-length channel))))
                   waiting)))))
      ;; Outside the mutex, one wake per opened slot: each call resumes
      ;; at most one live waiter and rechecks the room itself, so a
      ;; woken putter racing a slot away turns a later wake into a
      ;; no-op rather than an over-admission.
      (do ((i 0 (fx+ i 1))) ((fx>=? i wake))
        (%channel-wake-space! channel))))

  ;;------------------------------------------------------------
  ;; Timers (identical to flow)
  ;;------------------------------------------------------------

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
  ;; Network and file I/O events (identical to flow)
  ;;------------------------------------------------------------

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

  ;; One send, reporting what the kernel actually took: a positive
  ;; fixnum, or #f on failure. START defaults to 0 and lets a caller
  ;; resume a partial write without copying anything.
  ;;
  ;; It deliberately does NOT loop internally. Resubmitting the
  ;; remainder from inside the completion handler runs on the
  ;; scheduler's stack with the fiber parked across every round trip,
  ;; and that one decision caused three separate problems:
  ;;
  ;; - Uncancellable. The chain belonged to no fiber, so a cancelled
  ;;   scope could not stop it: it kept issuing ring operations against
  ;;   an fd the cleanup path had very likely already closed, which on a
  ;;   recycled descriptor is a write into someone else's file.
  ;; - Unraceable. (flow-choice (flow-write ...) (flow-timeout ...))
  ;;   would elect the timeout and the write would carry on regardless.
  ;; - Quadratic. subbytevector copied the whole remainder on every
  ;;   partial write, which is worst exactly when partial writes happen
  ;;   -- a large buffer dribbling out through a slow socket.
  ;;
  ;; Looping in the CALLER makes each chunk its own perform and
  ;; therefore its own cancellation point, and costs no atomicity: each
  ;; resubmit was a separate SQE either way, so a competing send on the
  ;; same fd could always interleave. flow-write-all! below is the
  ;; loop, and flow-write-at has reported its count all along -- this
  ;; makes flow-write agree with it.
  (define flow-write
    (case-lambda
      ((fd bv) (flow-write fd bv 0))
      ((fd bv start)
       (unless (and (fixnum? start)
                    (fx>=? start 0)
                    (fx<=? start (bytevector-length bv)))
         (error 'flow-write "start must be an index into bv"
                (list start (bytevector-length bv))))
       (make-flow% 'base #f
                   (lambda (x) x)
                   (lambda () #f)
                   (lambda (state resume register-cancel!)
                     (let* ((ring (loop-ring (loop-current)))
                            (id   (loop-alloc-id!))
                            (sqe  (loop-get-sqe ring)))
                       (lock-object bv)
                       (io-uring-prep-send sqe fd
                                           (+ (bytevector-pointer bv) start)
                                           (fx- (bytevector-length bv) start)
                                           0)
                       (io-uring-sqe-set-data64 sqe id)
                       (hashtable-set! (loop-handlers (loop-current)) id
                                       (lambda (res)
                                         ;; Runs on cancellation too, with
                                         ;; res = -ECANCELED, so the pin is
                                         ;; always released.
                                         (unlock-object bv)
                                         (resume (and (fx>? res 0) res))))
                       ;; The same cancel flow-read registers. A write
                       ;; that loses a choice must not still be in the
                       ;; ring afterwards.
                       (register-cancel!
                        (lambda ()
                          (let ((csqe (loop-get-sqe ring)))
                            (io-uring-prep-cancel64 csqe id 0)
                            (io-uring-sqe-set-data64 csqe (loop-alloc-id!)))))))))))

  ;; Write all of BV, resuming after each partial write. A procedure
  ;; rather than an event, exactly as flow-put! is: every iteration
  ;; performs flow-write and is therefore a suspension point and a
  ;; cancellation point, which is the property the old internal loop
  ;; threw away. Returns #t once everything is written, #f if a write
  ;; failed -- ask flow-write directly if you need to know how far it
  ;; got. An empty bytevector costs no syscall.
  (define (flow-write-all! fd bv)
    (let ((size (bytevector-length bv)))
      (let loop ((start 0))
        (if (fx=? start size)
            #t
            (let ((n (flow-perform (flow-write fd bv start))))
              (and n (loop (fx+ start n))))))))

  ;; The cancel is not optional here, unlike the other events where it
  ;; only saves a wasted ring operation. loop-accept-block keys its
  ;; single continuation slot by the multishot's id and REFUSES a
  ;; second waiter on it; a cancelled accept that left its handler
  ;; behind therefore poisons the listening fd, and every later
  ;; flow-accept on it raises "concurrent accept on fd" for as long as
  ;; no client happens to arrive to clear the slot — i.e. exactly when
  ;; the server is idle. Any flow-accept under a flow-monitor or a
  ;; cancellable scope hit this on the first cancellation.
  ;;
  ;; Deleting the handler is the whole fix: a client the multishot
  ;; accepts afterwards lands on %accept-backlog and the next
  ;; flow-accept picks it up, so nothing is leaked and nothing is lost.
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

  (define O-RDONLY 0)
  (define O-WRONLY 1)
  (define O-RDWR   2)
  (define O-CREAT  #o100)
  (define O-TRUNC  #o1000)
  (define O-APPEND #o2000)

  (define %flow-at-fdcwd -100)

  (define %flow-c-string
    (lambda (str)
      (let* ((bytes (string->utf8 str))
             (n     (bytevector-length bytes))
             (out   (make-bytevector (fx+ n 1) 0)))
        (bytevector-copy! bytes 0 out 0 n)
        out)))

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

  (define flow-write-at
    (lambda (fd offset bv)
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
                                        ;; runs on cancellation too, with
                                        ;; res = -ECANCELED, so the pin is
                                        ;; always released
                                        (unlock-object bv)
                                        (resume (and (fx>=? res 0) res))))
                      ;; A cancelled scope must not leave a write in the
                      ;; ring: io_uring resolves the fd when it processes
                      ;; the SQE, so a write still queued after the
                      ;; cleanup path closed that fd can land on whatever
                      ;; reopened the number.
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (loop-get-sqe ring)))
                           (io-uring-prep-cancel64 csqe id 0)
                           (io-uring-sqe-set-data64 csqe (loop-alloc-id!))))))))))

  ;; The one ring event here that deliberately registers NO cancel, and
  ;; the reason is the opposite of the others': cancelling a close would
  ;; leak the fd, which is precisely what the cancelling scope is trying
  ;; to clean up. So the close is left to complete.
  ;;
  ;; Nothing waits for it. The scope's cancellation wins this perform,
  ;; the fiber unwinds, and the completion handler's resume then reports
  ;; #f and is discarded — the kernel has released the descriptor either
  ;; way. A close also always completes on its own, so unlike an accept
  ;; or a read it can never hold a cancelled parent in %scope-finish's
  ;; drain.
  (define flow-close
    (lambda (fd)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (loop-close-block fd
                                      (lambda (res)
                                        (resume (and (fx>=? res 0) res))))))))

  ;;------------------------------------------------------------
  ;; Fibers, nurseries, monitor
  ;;------------------------------------------------------------

  ;; Spawn THUNK under SCOPE. Inside a nursery the child is counted
  ;; and its raise fails the scope — first error wins — before the
  ;; count drops; under the root scope this is a bare loop-spawn plus
  ;; the scope reinstall, the hot path.
  (define (%scope-spawn! scope thunk)
    (if (eq? scope %root-scope)
        (loop-spawn (lambda ()
                      (set! %scope-current %root-scope)
                      (thunk)))
        (begin
          (%scope-child-add! scope)
          (loop-spawn
           (lambda ()
             (set! %scope-current scope)
             (guard (ex (#t (%scope-fail! scope (cons 'failed ex))))
               (thunk))
             (%scope-child-done! scope))))))

  (define (flow-spawn thunk)
    (when (%worker-current?) (%flow-wrong-thread 'flow-spawn))
    (%scope-spawn! %scope-current thunk))

  ;; Run BODY with SCOPE current, restoring PARENT on normal return
  ;; or raise. Suspensions inside BODY reinstall SCOPE through the
  ;; resume path, so no dynamic-wind is involved.
  (define (%call-with-scope scope parent body)
    (set! %scope-current scope)
    (let ((outcome (guard (ex (#t (cons 'raised ex)))
                     (cons 'ok (body)))))
      (set! %scope-current parent)
      outcome))

  ;; Wait until SCOPE's children are all done, then translate its
  ;; final state: the recorded first error re-raises; explicit
  ;; cancellation and the monitor's deadline raise their symbol; an
  ;; open scope yields OUTCOME.
  (define (%scope-finish scope parent outcome)
    ;; The join runs under the PARENT scope on purpose, so an enclosing
    ;; cancellation reaches it rather than being blocked by a child that
    ;; will not finish. But when it did reach it, this raised on the
    ;; spot with this scope's own children still running — they were
    ;; cancelled transitively by %scope-fail!, yet nobody waited for
    ;; them to finish unwinding, so fibers outlived the scope that owned
    ;; them and the parent's own join could complete while they were
    ;; still on their way out. That is the single thing a nursery exists
    ;; to prevent.
    ;;
    ;; So: catch the interruption, make sure this scope really is dead
    ;; so its children are told to stop, and drain them to zero with the
    ;; cancellation OFF before propagating. The second wait runs at the
    ;; root scope, where flow-perform adds no cancel base and therefore
    ;; nothing can abandon it a second time.
    ;;
    ;; The cost is honest and worth stating: a child parked in an
    ;; operation that cannot be cancelled will hold its parent here.
    ;; Cancellation is prompt for everything that registers a cancel
    ;; thunk; flow-write-at and flow-close still do not (see Issues).
    (let ((interrupted
           (and (not (fxzero? (%scope-children scope)))
                (guard (ex (#t ex))
                  (flow-perform (%scope-join-event scope))
                  #f))))
      (when interrupted
        ;; Idempotent: if the scope already died for a better reason —
        ;; a child's failure, a monitor's deadline — that reason wins
        ;; and this changes nothing.
        (%scope-fail! scope 'cancelled)
        (let ((saved %scope-current))
          (set! %scope-current %root-scope)
          (let drain ()
            (unless (fxzero? (%scope-children scope))
              (flow-perform (%scope-join-event scope))
              (drain)))
          (set! %scope-current saved)))
      ;; Unconditionally, on every path. The old code unlinked only
      ;; after a join that returned normally, so a parent whose
      ;; cancellation interrupted the join kept the dead subscope on its
      ;; list for the rest of its life — and %scope-fail! walks that
      ;; list on every later cancellation.
      (when (flow-scope? parent)
        (flow-scope-subscopes!
         parent (remq scope (flow-scope-subscopes parent))))
      (let ((reason (unbox (flow-scope-state scope))))
        (cond
         ((pair? reason) (raise (cdr reason)))
         ((eq? reason 'timeout)
          (raise (make-flow-error 'timeout "flow2: deadline expired" '() #f)))
         ;; Before the bare 'cancelled: when the join was cut short we
         ;; re-raise what actually cut it, which is normally the
         ;; parent's cancellation but must not mask a block-proc raise
         ;; behind a generic cancelled error.
         (interrupted (raise interrupted))
         ((eq? reason 'cancelled)
          (raise (%flow-cancelled-error)))
         ((eq? (car outcome) 'raised) (raise (cdr outcome)))
         (else (cdr outcome))))))

  ;; PROC runs on the calling fiber with the fresh scope current;
  ;; fibers it spawns are the scope's children. The join — waiting
  ;; for every child — happens under the PARENT scope, so an
  ;; enclosing nursery's cancellation still reaches a parent parked
  ;; here. PROC raising fails the scope exactly like a child raising:
  ;; siblings are cancelled, and the first recorded error re-raises
  ;; after the children have drained.
  (define (flow-nursery proc)
    (when (%worker-current?) (%flow-wrong-thread 'flow-nursery))
    ;; A dead scope must not open a live subscope. The link below lands
    ;; AFTER %scope-fail!'s subscope walk, and the walk is CAS-guarded
    ;; so it never reruns: a scope created past that point would be
    ;; invisible to the cancellation forever — its body runs SHIELDED
    ;; under a permanently-open scope, parks on whatever it likes, and
    ;; nothing can ever reach it. On the loop thread nothing yields
    ;; between this check and the link (and %scope-fail! is loop-only),
    ;; so checking at entry closes the hole completely; it also matches
    ;; flow-perform, which raises rather than starting work in a scope
    ;; that is already dead.
    (when (flow-cancelled?) (raise (%flow-cancelled-error)))
    (let* ((parent %scope-current)
           (scope (%make-scope parent)))
      (unless (eq? parent %root-scope)
        (flow-scope-subscopes! parent (cons scope (flow-scope-subscopes parent))))
      (let ((outcome (%call-with-scope scope parent
                                       (lambda () (proc scope)))))
        (when (eq? (car outcome) 'raised)
          (%scope-fail! scope (cons 'failed (cdr outcome))))
        (%scope-finish scope parent outcome))))

  ;; A nursery with a deadline. THUNK runs as a child fiber — not on
  ;; the calling fiber — so the deadline is armed before any of the
  ;; monitored work starts, and bounds the thunk itself, not only
  ;; what it spawns. The calling fiber races the scope's join against
  ;; a ring timeout under the PARENT scope; whichever loses is
  ;; cancelled by the ordinary choice machinery (a won join removes
  ;; the timeout from the ring). On deadline the whole subtree is
  ;; cancelled, drained, and a timeout <flow-error> raises.
  (define (flow-monitor seconds thunk)
    (when (%worker-current?) (%flow-wrong-thread 'flow-monitor))
    ;; Same entry check as flow-nursery, and with more at stake: the
    ;; child fiber is spawned BEFORE the join/deadline race, and the
    ;; race's perform raises on the dead parent before the deadline is
    ;; armed — the child would be orphaned under a scope nothing can
    ;; cancel, with no deadline and no join.
    (when (flow-cancelled?) (raise (%flow-cancelled-error)))
    (let* ((parent %scope-current)
           (scope (%make-scope parent))
           (result (box #f)))
      (unless (eq? parent %root-scope)
        (flow-scope-subscopes! parent (cons scope (flow-scope-subscopes parent))))
      (%scope-spawn! scope
                     (lambda ()
                       (set-box! result (cons 'ok (thunk)))))
      ;; The race runs under the PARENT scope so an enclosing
      ;; cancellation reaches it — the same reason the nursery's join
      ;; does. But when it did, the raise used to propagate straight
      ;; out of flow-monitor: no %scope-fail!, no %scope-finish, no
      ;; drain. The monitor's children were cancelled transitively
      ;; through the subscope link, yet nobody waited for them to
      ;; finish unwinding — they outlived the monitor call, which is
      ;; the single thing a scope exists to prevent, and the exact
      ;; invariant %scope-finish's interrupted path enforces for
      ;; flow-nursery. Catch the interruption, fail the scope with it
      ;; — idempotently, so a child failure or the deadline that
      ;; already killed the scope keeps its better reason — and let
      ;; %scope-finish drain and re-raise it like any first error.
      (let ((race (guard (ex (#t (cons 'interrupted ex)))
                    (flow-perform
                     (flow-choice
                      (flow-wrap (%scope-join-event scope)
                                 (lambda (_) 'joined))
                      (flow-wrap (flow-timeout seconds)
                                 (lambda (_) 'deadline)))))))
        (cond
         ((eq? race 'deadline) (%scope-fail! scope 'timeout))
         ((pair? race) (%scope-fail! scope (cons 'failed (cdr race)))))
        (%scope-finish scope parent
                       (or (unbox result) (cons 'ok (void)))))))

  ;;------------------------------------------------------------
  ;; Lifecycle and compute threads
  ;;------------------------------------------------------------

  ;; A task, as the framework sees it: the thunk, the response
  ;; channel the guard's error reply targets, and the scope current
  ;; at submission — what a nursery's cancellation flags.
  (define-record-type* <flow2-task>
    (make-flow-task thunk response scope)
    flow-task?
    (thunk    flow-task-thunk)
    (response flow-task-response)
    (scope    flow-task-scope))

  (define %flow-worker-stop (list 'stop))

  ;; The task is counted as a child of the submitting scope, so the
  ;; nursery's join waits for it. Tagging alone -- which is all this did
  ;; -- meant cancellation reached a task but ownership did not: a join
  ;; could return while a scope-tagged task was still running on a
  ;; worker, and that task could still put to a channel afterwards. The
  ;; README promised a scope owns "the compute tasks they submit"; only
  ;; the flagging half was implemented.
  ;;
  ;; The increment happens BEFORE the put and is undone if the put does
  ;; not complete. Since channels became bounded, a put to a full worker
  ;; channel parks and can therefore be cancelled, and a count bumped
  ;; for a task that was never submitted is a join that never finishes.
  ;; Doing it after the put instead would be worse: the worker can pick
  ;; the task up and decrement before the increment lands.
  (define (flow-submit! worker-channel thunk response-channel)
    (let ((scope (if (%worker-current?)
                     (or (%task-scope) %root-scope)
                     %scope-current)))
      (if (eq? scope %root-scope)
          (%channel-put! worker-channel
                         (make-flow-task thunk response-channel scope)
                         #f)
          (begin
            (%scope-child-add! scope)
            (guard (ex (#t (%scope-child-done! scope) (raise ex)))
              (%channel-put! worker-channel
                             (make-flow-task thunk response-channel scope)
                             #f))))))

  ;; The per-worker framework loop: dequeue, skip tasks whose scope
  ;; died in the queue, run under the guard that makes always-a-reply
  ;; unconditional. A cancelled raise out of a task whose scope is
  ;; dead is the task unwinding, not a failure — no reply, by design
  ;; (nobody in that scope is listening). Everything else, wrap and
  ;; force onto the response channel, past any bound.
  (define (%worker-body channel)
    (%worker-current? #t)
    (let loop ()
      (let ((task (flow-get! channel)))
        (unless (eq? task %flow-worker-stop)
          (let ((scope (flow-task-scope task)))
            ;; The decrement pairs with flow-submit!'s increment and has
            ;; to happen on EVERY path out, including the one where the
            ;; task is skipped because its scope died in the queue --
            ;; otherwise a cancelled scope's join waits for a task that
            ;; will never run.
            (dynamic-wind
              void
              (lambda ()
                (unless (%scope-dead? scope)
                  (%task-scope scope)
                  (guard (ex ((and (flow-error-cancelled? ex)
                                   (%scope-dead? scope))
                              (void))
                             (#t
                              (%channel-put! (flow-task-response task)
                                             (make-flow-error
                                              'compute "flow2: worker task raised"
                                              '() ex)
                                             #t)))
                    ((flow-task-thunk task)))
                  (%task-scope #f)))
              (lambda ()
                (unless (eq? scope %root-scope)
                  (%scope-child-done! scope)))))
          (loop)))))

  ;; Start the loop on the calling thread — the main thread — and
  ;; spawn PROC as fiber zero with the list of worker request
  ;; channels (empty when COMPUTE-COUNT is zero, the default). The
  ;; count is fixed for the run; flow-run returns when the loop
  ;; stops. Parked fibers are then simply never resumed — flow-stop
  ;; is a shutdown, not a cancellation; cancel your own top-level
  ;; nursery first when cleanup must run.
  (define flow-run
    (case-lambda
      ((proc) (flow-run proc 0))
      ((proc compute-count)
       (loop-new)
       (set! %scope-current %root-scope)
       (set! %cross-thread-spawns (box '()))
       (let ((channels
              (if (fxzero? compute-count)
                  '()
                  (begin
                    (set! %flow2-eventfd (%eventfd-create))
                    (set! %flow2-eventfd-buffer (foreign-alloc 8))
                    (foreign-set! 'unsigned-64 %flow2-eventfd-buffer 0 1)
                    (set! %flow2-workers-running? #t)
                    (set! %flow2-workers-live compute-count)
                    (loop-spawn %collector)
                    (let start ((i 0) (channels '()))
                      (if (fx=? i compute-count)
                          (reverse channels)
                          (let ((channel (make-flow-channel (cons 'worker i))))
                            (fork-thread
                             (lambda ()
                               (dynamic-wind
                                 void
                                 (lambda () (%worker-body channel))
                                 %flow-worker-exited!)))
                            (start (fx+ i 1) (cons channel channels)))))))))
         (loop-spawn (lambda ()
                       (set! %scope-current %root-scope)
                       (proc channels)))
         (loop-run)
         (unless (null? channels)
           (%flow-shutdown-pool! channels))
         (void)))))

  ;; Stop the pool and, crucially, WAIT before dismantling what the
  ;; workers are still using.
  ;;
  ;; The old order signalled the eventfd, closed it, and set it to #f
  ;; with workers possibly still inside a task. Two ways that goes
  ;; wrong, both silent: a worker reaching %flow-spawn-safe afterwards
  ;; finds the #f and raises "cross-thread resume with no compute pool
  ;; running" from inside its own guard, or it wins the race, holds the
  ;; old fd number, and writes eight bytes into whatever the next
  ;; loop-new or socket call has since been given that number.
  ;;
  ;; So the fd is closed only once every worker has provably exited.
  ;; Where that cannot be established -- a task parked on a channel
  ;; nobody will ever put to, which flow-stop does not cancel because it
  ;; is a shutdown and not a cancellation -- the eventfd is deliberately
  ;; LEAKED and the situation logged. Leaking one descriptor is strictly
  ;; better than handing a live writer a number the process is about to
  ;; reuse, and the log names how many workers were still out.
  (define %flow-shutdown-join-seconds 2.0)

  (define (%flow-shutdown-pool! channels)
    (set! %flow2-workers-running? #f)
    (for-each (lambda (channel)
                (%channel-put! channel %flow-worker-stop #t))
              channels)
    (%eventfd-signal! %flow2-eventfd)
    (let ((deadline (+ (real-time)
                       (exact (round (* 1000 %flow-shutdown-join-seconds))))))
      (let ((stragglers
             (with-mutex %flow2-workers-mutex
               (let wait ()
                 (cond
                  ((fxzero? %flow2-workers-live) 0)
                  ((>= (real-time) deadline) %flow2-workers-live)
                  (else
                   ;; Bounded, so a stuck worker cannot make flow-run
                   ;; itself hang.
                   (condition-wait %flow2-workers-gone %flow2-workers-mutex
                                   (make-time 'time-duration 50000000 0))
                   (wait)))))))
        (cond
         ((fxzero? stragglers)
          (%eventfd-close %flow2-eventfd)
          (foreign-free %flow2-eventfd-buffer)
          (set! %flow2-eventfd #f)
          (set! %flow2-eventfd-buffer #f))
         (else
          (flow-log (list 'flow2 'shutdown-workers-still-running stragglers))))))
    (void))

  (define (flow-stop)
    (when (%worker-current?) (%flow-wrong-thread 'flow-stop))
    (loop-stop))

  (include "letloop/flow2.check.scm"))

;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop flow2) — fibers and channels over io_uring.
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
;; - flow2 owns delivery and choice cleanup, and nothing about
;;   lifetimes. A fiber or a task runs until it returns. Fan-out
;;   policy — wait for all, for the first, for a quorum, or until a
;;   deadline, and what to do with the stragglers — is the program's,
;;   written with channels, flow-choice and flow-timeout. The only
;;   cancellation is a choice's: the losing members' register-cancel!
;;   thunks tear down their ring operations.
;;
;; Errors are plain <flow-error> records dispatched by symbol —
;; overflow, wrong-thread — not R6RS conditions.
;; An error nobody handles, in a fiber or a compute task, ends that
;; fiber or task and becomes a flow-log entry; what to do about it is
;; the program's business, not the library's.
(library (letloop flow2)

  (export
   ;; errors
   make-flow-error flow-error? flow-error-symbol flow-error-message
   flow-error-irritants flow-error-cause
   flow-error-overflow? flow-error-wrong-thread?

   ;; events (Concurrent ML core)
   make-flow flow? flow-wrap flow-guard flow-choice flow-perform

   ;; channels
   make-flow-channel flow-channel? flow-channel-name
   flow-channel-buffer-size!
   flow-put! flow-get flow-get! flow-get-try

   ;; latches: fire once, wake every waiter
   make-flow-latch flow-latch? flow-latch-fire! flow-latch-fired?
   flow-latch-wait flow-latch-wait!

   ;; timers
   flow-timeout flow-sleep

   ;; network and file I/O
   flow-accept flow-read flow-write flow-write-all!
   flow-open flow-read-at flow-write-at flow-close
   O-RDONLY O-WRONLY O-RDWR O-CREAT O-TRUNC O-APPEND

   ;; fibers
   flow-spawn

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

   ;; checks
   ~check-flow2-000/error-symbol-dispatch
   ~check-flow2-000/error-predicates
   ~check-flow2-001/always-ready
   ~check-flow2-001/wrap-order
   ~check-flow2-001/a-raising-cancel-does-not-skip-the-others
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
   ~check-flow2-002/channel-full-warns-once
   ~check-flow2-002/losing-get-does-not-eat-a-value
   ~check-flow2-002/losing-get-leaves-no-getter
   ~check-flow2-003/block-raise-reaches-the-fiber
   ~check-flow2-005/shutdown-joins-the-worker-pool
   ~check-flow2-005/straggler-does-not-corrupt-the-next-run
   ~check-flow2-005/worker-task-replies
   ~check-flow2-005/worker-ring-event-raises-wrong-thread
   ~check-flow2-005/worker-io-protocol-roundtrip
   ~check-flow2-005/worker-resume-runs-cancels-first
   ~check-flow2-005/a-thread-the-user-forked-is-refused
   ~check-flow2-005/every-entry-point-refuses-a-stray-thread
   ~check-flow2-009/a-closed-fd-does-not-hand-on-a-stash

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
   ~check-flow2-006/read-losing-a-same-tick-race-keeps-its-bytes
   ~check-flow2-009/file-write-read-roundtrip
   ~check-flow2-009/chunked-read-until-eof
   ~check-flow2-009/nonzero-offset
   ~check-flow2-009/read-or-timeout-leaves-fd-usable
   ~check-flow2-009/open-nonexistent-fails
   ~check-flow2-009/open-loses-choice-no-fd-leak
   ~check-flow2-009/close-under-choice-fd-actually-closed
   ~check-flow2-009/close-while-read-in-flight

   ;; fifth adverse pass, 2026-09-03
   ~check-flow2-001/wrap-runs-on-the-performer-after-commit
   ~check-flow2-005/wrap-runs-on-the-loop-when-a-worker-delivers
   ~check-flow2-005/coalesced-wakes-do-not-inflate-the-eventfd
   ~check-flow2-000/log-flush-writes-to-the-port-current-at-start
   ~check-flow2-000/a-failing-flush-stops-cleanly-and-keeps-its-batch
   ~check-flow2-000/log-sink-can-be-a-procedure
   ~check-flow2-005/compute-count-is-validated

   ;; sixth adverse pass
   ~check-flow2-005/flow-run-refuses-to-nest
   ~check-flow2-005/a-failed-start-releases-the-loop
   ~check-flow2-005/a-thread-forked-in-a-task-is-refused
   ~check-flow2-000/a-forked-thread-logs-to-its-own-box
   ~check-flow2-006/reads-after-a-lost-race-keep-stream-order
   ~check-flow2-002/a-losing-get-wakes-no-putter

   ;; uncaught errors are log entries
   ~check-flow2-012/uncaught-raise-in-a-fiber-is-logged
   ~check-flow2-012/uncaught-raise-in-a-task-is-logged
   ~check-flow2-012/fan-out-gather-until-a-deadline-then-hand-off

   ;; latches
   ~check-flow2-013/latch-wakes-every-waiter-once
   ~check-flow2-013/losing-latch-wait-leaves-no-waiter
   ~check-flow2-013/latch-crosses-threads
   ~check-flow2-013/latch-as-a-stop-event

   ;; the default printer
   ~check-flow2-000/log-prints-to-stderr-by-default)

  (import (chezscheme)
          (letloop r999)
          (only (letloop cffi) bytevector-pointer)
          (letloop liburing low))

  ;;------------------------------------------------------------
  ;; Errors: one record type, dispatched by symbol
  ;;------------------------------------------------------------

  ;; The taxonomy: overflow, wrong-thread. A plain
  ;; record rather than an R6RS condition, so a program can put one on
  ;; a channel as easily as raise it.
  (define-record-type* <flow-error>
    (make-flow-error symbol message irritants cause)
    flow-error?
    (symbol    flow-error-symbol)
    (message   flow-error-message)
    (irritants flow-error-irritants)
    (cause     flow-error-cause))

  (define (flow-error-overflow? obj)
    (and (flow-error? obj) (eq? (flow-error-symbol obj) 'overflow)))
  (define (flow-error-wrong-thread? obj)
    (and (flow-error? obj) (eq? (flow-error-symbol obj) 'wrong-thread)))

  ;; Two callers, one symbol: an operation the loop thread reserves
  ;; called on a compute thread, and any flow2 operation called on a
  ;; thread the USER forked. The message names neither, because it
  ;; cannot: what the caller needs to know is which thread was allowed,
  ;; and that is the same answer both times.
  (define (%flow-wrong-thread who)
    (raise (make-flow-error 'wrong-thread
                            "flow2: operation from a thread that does not own it"
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

  ;; A value that belongs to the thread that set it. Chez's fork-thread
  ;; copies the parent's thread parameters into the child, so a plain
  ;; thread parameter is inherited, and both per-thread identities here
  ;; were: a thread the user forked inside a compute task held the
  ;; worker's pool, passed every wrong-thread check as that worker, and
  ;; -- after the run had closed the eventfd and freed its buffer --
  ;; signalled the closed descriptor, writing eight bytes of freed heap
  ;; into whatever file had since been given that number. A forked
  ;; thread also shared its parent's log box, so its entries interleaved
  ;; with the parent's and two threads CASed one box -- the contention
  ;; the per-thread boxes exist to avoid.
  ;;
  ;; The cell records the owner's thread id, and a reader on any other
  ;; thread sees #f. The parent is alive when it forks, so the child's
  ;; id always differs from the one it inherited.
  (define (%make-thread-own) (make-thread-parameter #f))

  (define (%thread-own-ref param)
    (let ((cell (param)))
      (and cell (eqv? (car cell) (get-thread-id)) (cdr cell))))

  (define (%thread-own-set! param value)
    (param (cons (get-thread-id) value)))

  ;; Per thread, not a global: two OS threads logging concurrently would
  ;; otherwise clobber each other's accumulator.
  (define %flow-log-box (%make-thread-own))

  ;; Created and registered on first use, so logging needs no setup
  ;; step on any thread. Only this thread writes its own parameter, so
  ;; the check-then-set needs no CAS; flow-box-cons! is what makes the
  ;; registry push safe against concurrent registration.
  (define (%flow-log-ensure-box!)
    (or (%thread-own-ref %flow-log-box)
        (let ((b (box '())))
          (%thread-own-set! %flow-log-box b)
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

  ;; Who owns the log. 'auto until the program says anything about it:
  ;; the first flow-log then starts the default printer, which writes
  ;; to stderr. Any of flow-log-drain!, flow-log-start! or
  ;; flow-log-stop! makes it 'owned, and from then on the program alone
  ;; decides where entries go -- the default never restarts by itself.
  ;;
  ;; The default exists because the alternative was an unbounded queue
  ;; by omission: with no flusher started, entries -- uncaught errors
  ;; included -- accumulated in memory for the life of the process and
  ;; were written nowhere. That is the unbounded-mailbox failure the
  ;; channels are bounded to avoid, reached by NOT configuring
  ;; something, and the errors it hid were the ones most worth seeing.
  (define %flow-log-mode (box 'auto))

  ;; #t while the running flush thread is the default printer, so a
  ;; program that takes the log over can stop it.
  (define %flow-log-default-running? (box #f))

  (define %flow-log-default-period 0.1)

  (define (flow-log sexp)
    (flow-box-cons! (%flow-log-ensure-box!) (cons (%flow-log-now) sexp))
    ;; One unbox on the hot path; the CAS and the fork happen once per
    ;; process. The entry is consed first, so the printer's first drain
    ;; sees it.
    (when (and (eq? (unbox %flow-log-mode) 'auto)
               (box-cas! %flow-log-mode 'auto 'default))
      (%flow-log-start-thread! %flow-log-default-period
                               (current-error-port) #t)))

  ;; The program has said where its entries go, so stop the default
  ;; printer if it runs. Its stop does a final drain-and-write, so
  ;; entries logged before this were printed, not dropped.
  (define (%flow-log-take-over!)
    (set-box! %flow-log-mode 'owned)
    (when (unbox %flow-log-default-running?)
      (%flow-log-stop-thread!)))

  ;; Every pending entry: oldest-first within each thread's own box,
  ;; boxes in registration order rather than globally sorted — a caller
  ;; wanting strict cross-thread order can sort on the timestamps. The
  ;; registry is read, not drained: it is a cons list, newest first, so
  ;; reversing a snapshot IS registration order. It used to be drained
  ;; and re-consed, which flipped the order on every call and made the
  ;; documented order true only on alternate drains.
  ;;
  ;; A program that drains the log has taken it over, so this also
  ;; stops the default printer -- see %flow-log-mode.
  (define (flow-log-drain!)
    (%flow-log-take-over!)
    (%flow-log-drain-all!))

  ;; The drain itself, for the flush thread, which must not take the
  ;; log over from itself.
  (define (%flow-log-drain-all!)
    (let ((boxes (reverse (unbox %flow-log-registry))))
      (apply append (map (lambda (b) (reverse (flow-box-drain! b))) boxes))))

  (define (%flow-log-write! entries port)
    (unless (null? entries)
      (for-each (lambda (entry) (write entry port) (newline port))
                entries)
      (flush-output-port port)))

  ;; The port is captured on the CALLING thread when the flusher
  ;; starts, or passed explicitly. It used to be read at flush time on
  ;; the flush thread, documented as "reparameterizing it is honored on
  ;; the next cycle" -- but current-error-port is a thread parameter,
  ;; and a thread forked before a parameterize keeps the value it
  ;; inherited at fork time, so the documented shape (start the flusher
  ;; at program start, redirect stderr later) wrote to the old port
  ;; forever. Plain synchronous port I/O: this thread is not on the
  ;; loop's critical path and does not run a ring at all, so routing it
  ;; through io_uring would buy nothing and cost it a loop of its own.
  (define %flow-log-poll-interval 0.01)
  (define %flow-log-stop-requested? (box #f))
  (define %flow-log-stopped? (box #t))

  ;; Guarded against a second concurrent flush thread, which flow left
  ;; merely documented as unsupported. Draining stays correct either
  ;; way — flow-box-drain! never double-delivers — but two threads
  ;; interleaving writes to the same port produce shuffled output at
  ;; exactly the moment someone is reading it to diagnose something.
  ;;
  ;; SINK is a textual output port, written one entry per line, or a
  ;; procedure, called on the flush thread with each non-empty batch
  ;; of entries, oldest first per thread. The procedure is where a
  ;; program decides what the library's own events mean to it --
  ;; uncaught errors in particular: count them, forward them, filter
  ;; out the noise. It runs on the flush thread, not the loop, so it
  ;; cannot stop the run itself; it can fire a latch a fiber waits on.
  (define flow-log-start!
    (case-lambda
      ((period-seconds) (flow-log-start! period-seconds (current-error-port)))
      ((period-seconds sink)
       (unless (or (procedure? sink)
                   (and (output-port? sink) (textual-port? sink)))
         (error 'flow-log-start!
                "sink must be a textual output port or a procedure" sink))
       ;; An explicit start replaces the default printer rather than
       ;; being refused by it.
       (%flow-log-take-over!)
       (%flow-log-start-thread! period-seconds sink #f))))

  ;; DEFAULT? marks the default printer, which a take-over stops.
  (define (%flow-log-start-thread! period-seconds sink default?)
    (when (box-cas! %flow-log-stopped? #t #f)
      (set-box! %flow-log-stop-requested? #f)
      (set-box! %flow-log-default-running? default?)
      (let ((ticks (fxmax 1 (exact (round (/ period-seconds
                                             %flow-log-poll-interval))))))
        (fork-thread
         (lambda ()
           (let lp ()
             ;; Re-check the stop flag at the poll interval rather
             ;; than only at a period boundary, so flow-log-stop! is
             ;; prompt even when the period is long.
             (let wait ((n 0))
               (unless (or (unbox %flow-log-stop-requested?) (fx>=? n ticks))
                 (sleep (make-time 'time-duration
                                   (exact (round (* %flow-log-poll-interval
                                                    1000000000)))
                                   0))
                 (wait (fx+ n 1))))
             (if (and (%flow-log-flush!
                       (if (procedure? sink)
                           (lambda (entries)
                             (unless (null? entries) (sink entries)))
                           (lambda (entries)
                             (%flow-log-write! entries sink))))
                      (not (unbox %flow-log-stop-requested?)))
                 (lp)
                 (begin
                   (set-box! %flow-log-default-running? #f)
                   (set-box! %flow-log-stopped? #t))))))))
    (void))

  ;; One drain-and-write, #f when the write raised. A port that fails
  ;; (a full disk, a closed pipe) used to kill the flush thread before
  ;; it set %flow-log-stopped?, so flow-log-stop! spun forever and
  ;; flow-log-start! refused to start another. Now the thread marks
  ;; itself stopped and exits; the batch it could not write goes back
  ;; into the log, followed by a (flow2 log-flush-raised CONDITION)
  ;; entry, so a drain or the next flusher still sees all of it.
  (define (%flow-log-flush! write!)
    (let ((entries (%flow-log-drain-all!)))
      (guard (ex (#t (let ((b (%flow-log-ensure-box!)))
                       (for-each (lambda (entry) (flow-box-cons! b entry))
                                 entries)
                       (flow-log (list 'flow2 'log-flush-raised
                                       (%flow-condition-sexp ex))))
                     #f))
        (write! entries)
        #t)))

  ;; Blocks the caller until the flush thread has done one final
  ;; drain-and-write and exited, so nothing logged before the stop
  ;; request is lost on shutdown.
  ;;
  ;; After it the log is the program's: entries accumulate until it
  ;; drains them or starts a flusher -- see %flow-log-mode.
  (define (flow-log-stop!)
    (set-box! %flow-log-mode 'owned)
    (%flow-log-stop-thread!))

  (define (%flow-log-stop-thread!)
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

  ;; A raise from a base's block procedure, on its way back to the
  ;; fiber as a value, converted into a raise on the fiber's own stack.
  ;;
  ;; block procs run inside loop-abort's thunk — on the SCHEDULER's
  ;; stack, after the prompt was already unwound — so the fiber's own
  ;; guards are no longer in the dynamic extent. A raise there used to
  ;; reach loop-apply's catch-all instead: the fiber died without its
  ;; handlers ever seeing the error, and anything waiting on it waited
  ;; forever. Not a synthetic worry —
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

  ;; A base's raw completion value, with the base whose wrap still has
  ;; to be applied to it. The block path used to apply the wrap inside
  ;; the base's resume -- on the stack of whoever completed the
  ;; rendezvous, and BEFORE resume-from's CAS. That is the wrong stack
  ;; twice over: a wrap that raised did so in the fiber calling
  ;; flow-put! (or in a completion handler, where loop-apply's guard ate
  ;; it), the getter was never resumed, and the value was gone; and when
  ;; the deliverer was a compute thread the wrap RAN ON THE WORKER, so a
  ;; wrap that touched the loop -- a flow-spawn, a ring event -- either
  ;; raised wrong-thread into the worker's put or, if it touched loop
  ;; state without going through a guarded entry point, corrupted it.
  ;; The Rationale's "no API through which a compute thread can reach
  ;; the loop's state" was false by exactly this much. The try path
  ;; never had the problem: flow-poll applies the wrap on the
  ;; performer. Now so does the block path, in %flow-settle.
  (define-record-type* <flow2-deferred>
    (%make-flow-deferred base raw)
    %flow-deferred?
    (base %flow-deferred-base)
    (raw  %flow-deferred-raw))

  ;; What a parked fiber sees when it wakes: a block-proc raise comes
  ;; back as a value and is converted into a raise HERE, on the fiber's
  ;; own stack, where its guards are -- and
  ;; the winning base's wrap is applied here too, after the commit, for
  ;; the same reason.
  (define (%flow-settle result)
    (let ((result (if (%flow-deferred? result)
                      ((flow-wrap-proc (%flow-deferred-base result))
                       (%flow-deferred-raw result))
                      result)))
      (cond
       ((%flow-raise? result) (raise (%flow-raise-object result)))
       (else result))))

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

  ;; Everything one flow-run's compute pool shares — the eventfd, its
  ;; write/read buffer, the spawn mailbox, and the liveness bookkeeping
  ;; — lives in ONE record created by that flow-run, and every worker
  ;; holds its own run's record through %worker-current?. These used to
  ;; be globals, and a straggler worker that outlived its run's 2s
  ;; shutdown join then corrupted the NEXT run through them: its exit
  ;; decremented the new run's live count, so the new shutdown
  ;; undercounted and closed the eventfd with one of its own workers
  ;; still live — resurrecting exactly the close-while-a-writer-lives
  ;; bug the join exists to prevent — and its spawn-safe calls consed a
  ;; dead run's continuations into the new loop's mailbox. With the
  ;; record, a straggler can only ever touch the run that created it:
  ;; its signals land on its own leaked fd, its thunks in a mailbox
  ;; nobody drains (a dead run's resumes SHOULD be dropped), and its
  ;; exit wakes a join that has already given up on it.
  ;;
  ;; The buffer is TWO 8-byte cells, allocated with the eventfd. The
  ;; first holds the value 1 and is what every %eventfd-signal! writes,
  ;; so a cross-thread wake-up is a bare write(2) instead of a
  ;; foreign-alloc / foreign-free pair on the hottest path the pool has.
  ;; The second is the collector's read target. They used to be one
  ;; cell, on the theory that Scheme never wrote it again -- but an
  ;; eventfd READ stores the counter into its buffer, so after the first
  ;; wake the cell held whatever count that read returned, and every
  ;; later signal added THAT instead of 1. Whenever several wakes
  ;; coalesced inside one busy tick the cell was multiplied, it never
  ;; shrank, and it reached 2^64 in about twenty windows; past 2^63 the
  ;; kernel refuses a second addition per read cycle, and the fd is
  ;; blocking, so the worker sat in write(2) until the loop's next tick
  ;; -- one cross-thread wake per tick, every other worker stalled. The
  ;; live count is guarded by the mutex rather than CAS'd because the
  ;; shutdown join needs a condition variable anyway.
  (define-record-type* <flow2-pool>
    (make-flow-pool% eventfd buffer spawns mutex gone live running?)
    %flow-pool?
    (eventfd  %pool-eventfd)
    (buffer   %pool-buffer)
    (spawns   %pool-spawns)
    (mutex    %pool-mutex)
    (gone     %pool-gone)
    (live     %pool-live     %pool-live!)
    (running? %pool-running? %pool-running?!))

  ;; This run's pool on threads forked by flow-run's compute pool, #f
  ;; on the loop thread — so it doubles as the am-I-on-a-worker test.
  (define %worker-pool (%make-thread-own))

  (define (%worker-current?) (%thread-own-ref %worker-pool))

  (define (%flow-worker-exited! pool)
    (with-mutex (%pool-mutex pool)
      (%pool-live! pool (fx- (%pool-live pool) 1))
      (condition-broadcast (%pool-gone pool))))

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
      (lambda (pool)
        (call-with-values (lambda () (func (%pool-eventfd pool)
                                           (%pool-buffer pool) 8))
          (lambda (n errno) (>= n 0))))))

  (define %eventfd-close
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "close" (int) int)))
      (lambda (fd) (call-with-values (lambda () (func fd)) (lambda (r e) r)))))

  ;; Park the collector fiber on the pool's eventfd until a worker
  ;; signals it. Reads into the pool's SECOND cell rather than one
  ;; allocated per wait -- and not into the first, which is the value
  ;; the signal writes (see <flow2-pool>). The collector parks here and,
  ;; at shutdown, is simply never resumed -- the loop has stopped -- so
  ;; a per-wait allocation was freed on every path except the one that
  ;; always happens, and leaked eight bytes plus its header per
  ;; flow-run.
  (define %eventfd-wait
    (lambda (pool)
      (let* ((sqe (loop-get-sqe (loop-ring (loop-current))))
             (id (loop-alloc-id!)))
        (io-uring-prep-read sqe (%pool-eventfd pool)
                            (+ (%pool-buffer pool) 8) 8 0)
        (io-uring-sqe-set-data64 sqe id)
        (loop-abort
         (lambda (k)
           (hashtable-set! (loop-handlers (loop-current)) id k))))))

  ;; The thread flow-run is running the loop on, for the duration of
  ;; that run and #f outside one. "Any thread" here has only ever meant
  ;; the loop thread and this library's own compute threads: a thread
  ;; the USER forked holds no pool, so it takes the loop-spawn branch of
  ;; %flow-spawn-safe below and mutates loop-thunks with no
  ;; synchronization against loop-run-once's take-and-clear, and sends
  ;; no eventfd wake — a resume lost outright, or delayed by a whole
  ;; wait timeout. The entry points that advertise cross-thread use
  ;; check this and raise wrong-thread instead.
  (define %flow-loop-thread (box #f))

  ;; The pool of the run in progress, #f outside one. A worker is
  ;; recognised by holding THIS pool, not by holding any pool: a
  ;; straggler from a previous run still holds its own, and everything
  ;; it does with it lands on a dead run -- which is exactly right for
  ;; the straggler's own state and exactly wrong for an object it shares
  ;; with the live run. A straggler that put to a channel the next run's
  ;; fiber was parked on popped that getter, consed its continuation
  ;; into the dead mailbox, and returned normally: the fiber was
  ;; stranded past its own deadline (the dead resume had already won the
  ;; state CAS) and the value was gone. From the live run's point of
  ;; view a straggler is a thread flow2 does not own, so it is refused
  ;; like one.
  (define %flow-pool-current (box #f))

  ;; Outside a run there is no loop to corrupt and nothing to check:
  ;; flow-put! on a channel before flow-run is a legitimate way to
  ;; prime one, and it either queues or raises overflow on its own.
  (define (%flow-check-caller-thread! who)
    (let ((owner (unbox %flow-loop-thread))
          (pool (%worker-current?)))
      (when owner
        (if pool
            (unless (eq? pool (unbox %flow-pool-current))
              (%flow-wrong-thread who))
            (unless (eqv? owner (get-thread-id))
              (%flow-wrong-thread who))))))

  ;; loop-spawn from the loop thread (the hot path, untouched); from
  ;; a compute thread, queue the thunk on the worker's OWN run's pool
  ;; and wake that run's loop through its eventfd. Only channel
  ;; internals reach this from a worker — there is deliberately no
  ;; user-facing cross-thread spawn. A worker always holds its pool,
  ;; and a straggler's pool keeps its (leaked) fd, so there is no
  ;; no-pool case left to error on.
  ;;
  ;; No thread test here on purpose. This runs on resume paths, where a
  ;; raise would abandon a channel already mutated — a value dequeued
  ;; and delivered to nobody. The check belongs at the entry points,
  ;; before anything has been committed.
  (define %flow-spawn-safe
    (lambda (thunk)
      (let ((pool (%worker-current?)))
        (if pool
            (begin
              (flow-box-cons! (%pool-spawns pool) thunk)
              (%eventfd-signal! pool))
            (loop-spawn thunk)))))

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
  ;; The wait is guarded because %eventfd-wait preps an SQE, and
  ;; loop-get-sqe raises "submission queue full" when the kernel
  ;; refuses to take more — the same raise source the <flow2-raise>
  ;; comment below calls realistic. Unguarded, that raise killed the
  ;; collector through loop-apply's catch-all, and every later
  ;; worker→loop resume accumulated in a box nobody would ever drain:
  ;; total, silent loss of all cross-thread traffic, presenting as a
  ;; zero-CPU hang. The failure path drains what is already pending
  ;; (loop-spawn raises nothing) and retries on the next tick, by
  ;; which point loop-run-once's submit has freed SQ slots; the
  ;; eventfd counter keeps any signal sent meanwhile, so the re-armed
  ;; read completes immediately and nothing is lost.
  (define (%collector pool)
    (let loop ()
      (when (%pool-running? pool)
        (let ((armed? (guard (ex (#t (flow-log (list 'flow2 'collector-wait-raised))
                                     #f))
                        (%eventfd-wait pool)
                        #t)))
          (for-each loop-spawn
                    (reverse (flow-box-drain! (%pool-spawns pool))))
          (if armed?
              (loop)
              (loop-spawn (lambda () (%collector pool))))))))

  ;;------------------------------------------------------------
  ;; Synchronization: poll, then park
  ;;------------------------------------------------------------

  ;; Fire every registered cancel except the winner's. One thunk, so the
  ;; whole batch lands before the resumed fiber does — that ordering is
  ;; load-bearing — but one guard PER cancel, which is the part that was
  ;; missing: most of these thunks call loop-get-sqe, which raises
  ;; "submission queue full" when the kernel will not take more, and a
  ;; raise from one aborted the walk and skipped every cancel after it.
  ;; One transient SQ-full could therefore leave a read in the ring and
  ;; a timeout armed with its continuation pinned until it fires, on
  ;; bases that had nothing to do with the failure.
  ;;
  ;; TAG is the winner's; pass #f to fire all of them, since every real
  ;; tag is a fresh pair.
  ;; Both reduce an object to something a log line can hold. A base's
  ;; data is (TAG . RECORD) for channel bases, so writing it
  ;; raw would dump a whole channel -- queue included -- into the log;
  ;; a condition writes as #<condition> and says nothing at all.
  (define (%flow-base-name data)
    (cond ((not (pair? data)) data)          ; 'flow2-close, or #f for a ring event
          ((flow-channel? (cdr data)) (list (car data) (flow-channel-name (cdr data))))
          (else (car data))))

  (define (%flow-condition-sexp ex)
    (cond ((flow-error? ex)
           (list 'flow-error (flow-error-symbol ex) (flow-error-message ex)))
          ((condition? ex)
           (call-with-string-output-port
            (lambda (port) (display-condition ex port))))
          (else ex)))

  ;; A block proc raised after an earlier base of the same perform had
  ;; already won during registration: the fiber is committed to that
  ;; value, so the raise has nowhere to go but here. It used to be
  ;; written to stderr directly, the one library event that bypassed
  ;; the logger.
  (define (%flow-log-raise-after-win ex)
    (flow-log (list 'flow2 'block-raised-after-win (%flow-condition-sexp ex))))

  ;; An entry is (TAG DATA . THUNK). DATA is the base's own, carried
  ;; only so that a raise here can say which base it came from: a bare
  ;; (flow2 cancel-raised) is what an operator reaches after an
  ;; unexplained hang or fd leak, and it named neither the base nor the
  ;; condition -- the two things that would end the investigation.
  (define (%flow-run-cancels! pending tag)
    (for-each (lambda (entry)
                (unless (eq? (car entry) tag)
                  (guard (ex (#t (flow-log (list 'flow2 'cancel-raised
                                                 (%flow-base-name (cadr entry))
                                                 (%flow-condition-sexp ex)))))
                    ((cddr entry)))))
              pending))

  ;; flow's design unchanged: one shared
  ;; state box CAS-elects a single winner, each base gets its own
  ;; wrap-applying resume, the losers' register-cancel! thunks fire
  ;; the instant any base wins, and both the cancels and the
  ;; continuation defer through %flow-spawn-safe because the party
  ;; completing the rendezvous may be a compute thread.
  (define flow-block-and-wait-on-loop
    (lambda (bases)
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
                      (%flow-spawn-safe (lambda () (k value)))
                      (%flow-spawn-safe
                       (lambda () (%flow-run-cancels! (unbox cancels) tag)))
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
                           (%flow-log-raise-after-win ex))))
               (for-each (lambda (base)
                           (let ((tag (cons #f #f)))
                             ((flow-block-proc base) state
                              (lambda (raw)
                                (resume-from tag (%make-flow-deferred base raw)))
                              (lambda (thunk)
                                (set-box! cancels
                                          (cons (cons tag
                                                      (cons (flow-data base)
                                                            thunk))
                                                (unbox cancels)))))))
                         bases))))))))

  ;; A compute thread is not a fiber: it parks on a condition
  ;; variable, and its resume fills a slot and broadcasts. Only
  ;; channel and latch bases reach here — %flow-perform-off-loop
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
                        (lambda () (%flow-run-cancels! pending tag)))))
                   (with-mutex mutex
                     (set! slot value)
                     (set! done? #t)
                     (condition-broadcast ready))
                   #t))))
        ;; Registration runs on this thread's own stack, so unlike the
        ;; on-loop case a raise here can propagate to the task's guard
        ;; by itself. Whether it SHOULD depends on the same CAS the
        ;; on-loop path consults: if this perform is still unclaimed,
        ;; the raise wins it — fire whatever cancels were registered so
        ;; no getter entry outlives a perform nobody will complete, and
        ;; re-raise. But if an earlier base already won during
        ;; registration, the caller is committed to that value — a
        ;; channel get may already have DEQUEUED it — and re-raising
        ;; would destroy it, the lost-value shape finding 7 was about.
        ;; Report it exactly as the on-loop path does, and fall
        ;; through to the wait, which the winner has already (or is
        ;; about to) satisfy.
        (let ((raised
               (guard (ex (#t
                           (if (box-cas! state 'waiting 'synched)
                               (begin
                                 (let ((pending (unbox cancels)))
                                   (when (pair? pending)
                                     (%flow-spawn-safe
                                      (lambda ()
                                        (%flow-run-cancels! pending #f)))))
                                 (list ex))
                               (begin
                                 (%flow-log-raise-after-win ex)
                                 #f))))
                 (for-each (lambda (base)
                             (let ((tag (cons #f #f)))
                               ((flow-block-proc base) state
                                (lambda (raw)
                                  (resume-from tag (%make-flow-deferred base raw)))
                                (lambda (thunk)
                                  (set-box! cancels
                                            (cons (cons tag
                                                        (cons (flow-data base)
                                                              thunk))
                                                  (unbox cancels)))))))
                           bases)
                 #f)))
          (when raised (raise (car raised))))
        (with-mutex mutex
          (let wait ()
            (unless done?
              (condition-wait ready mutex)
              (wait))))
        slot)))

  ;; A base is safe to synchronize on from a compute thread only when
  ;; its try/block touch nothing but mutex- or CAS-protected state:
  ;; channel and latch bases qualify, anything that preps an SQE
  ;; or reads loop tables does not.
  (define (%base-off-loop-safe? base)
    (let ((tag (flow-data base)))
      (and (pair? tag)
           (memq (car tag) '(flow2-get flow2-space flow2-latch))
           #t)))

  (define (%flow-perform-off-loop event)
    (let ((bases (flow-flatten event)))
      (for-each (lambda (base)
                  (unless (%base-off-loop-safe? base)
                    (%flow-wrong-thread 'flow-perform)))
                bases)
      (let ((result (flow-poll bases)))
        (%flow-settle (if (eq? result %flow-not-ready)
                          (flow-block-and-wait-off-loop bases)
                          result)))))

  ;; The guard belongs HERE, not at the handful of entry points that
  ;; happened to be named when it was written. Every suspending
  ;; operation funnels through flow-perform, and on a user-forked
  ;; thread %worker-current? is #f, so the on-loop branch below is the
  ;; one taken: it dequeues under the channel mutex, resumes a parked
  ;; putter through
  ;; %flow-spawn-safe -> loop-spawn with no eventfd wake, and parks on
  ;; a loop-abort that is #f in that thread. flow-get! on a non-empty
  ;; channel therefore SUCCEEDED off-loop and stranded the putter,
  ;; while on an empty one it died with "attempt to apply
  ;; non-procedure #f" — a corruption and a nonsense error where
  ;; wrong-thread was documented.
  (define flow-perform
    (lambda (event)
      (%flow-check-caller-thread! 'flow-perform)
      (%flow-perform event)))

  ;; Without the caller check: %worker-body fetches its next task
  ;; through this, so a straggler -- refused everywhere else once the
  ;; next run starts -- can still dequeue the stop sentinel its own run
  ;; left it and exit, instead of dying on a raise in the framework
  ;; loop.
  (define %flow-perform
    (lambda (event)
      (if (%worker-current?)
          (%flow-perform-off-loop event)
          (let* ((bases (flow-flatten event))
                 (result (flow-poll bases)))
            (if (eq? result %flow-not-ready)
                ;; %flow-settle, not a bare return: a block-proc raise
                ;; comes back as a value and must raise on this stack.
                (%flow-settle (flow-block-and-wait-on-loop bases))
                result)))))

  ;;------------------------------------------------------------
  ;; Channels: buffered, mutex-protected, cross-thread
  ;;------------------------------------------------------------

  ;; One channel type for every role — fiber↔fiber, worker request
  ;; channels, the channels tasks reply on. Bounded by default (see
  ;; %flow-channel-default-bound); a put over the bound parks until
  ;; there is room, and raises overflow only with no scheduler to park
  ;; on. The mutex guards the value queue (two-stack FIFO), the parked
  ;; getters and putters and the bound; it is held only for list
  ;; surgery, never across a resume.
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
  ;; discipline flow's rendezvous used; another base of the same
  ;; perform may still win the underlying state CAS, which is why
  ;; %channel-put! rechecks resume's own return value).
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
  ;; Called outside the mutex. A waiter whose resume reports #f has
  ;; already synched, so move to the next; nothing is lost either way,
  ;; since a space waiter carries no value.
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
  ;; bound — the shutdown's stop sentinel uses it, so a worker channel
  ;; that is full still delivers it. The resume call happens
  ;; outside the mutex; if it reports the getter already synched
  ;; elsewhere (another base of its choice won the race), try the next
  ;; one.
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
  ;; value was already inside it a moment ago, and raising overflow here
  ;; would destroy the value this procedure exists to preserve. That
  ;; holds only because the dequeue that took it woke no putter -- see
  ;; flow-get, which wakes them after a successful resume and not
  ;; before.
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

  (define (flow-put! channel obj)
    (%flow-check-caller-thread! 'flow-put!)
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
                      (if immediate
                          ;; resume reports #f when an earlier base of
                          ;; this same perform already won — registration
                          ;; is a for-each with no early exit, so a base
                          ;; that resumed inline is followed by every
                          ;; later base's block. The value is already out
                          ;; of the queue at that point, so put it back
                          ;; rather than drop it. %channel-put! has made
                          ;; the same test since day one.
                          ;;
                          ;; Putters are woken only once the value is
                          ;; really taken. Waking them first, as this
                          ;; did, let a putter on another compute thread
                          ;; fill the slot before the unget, which then
                          ;; left the channel one past its bound --
                          ;; %channel-unget! does not consult it.
                          (if (resume (cdr immediate))
                              (%channel-wake-space! channel)
                              (%channel-unget! channel (cdr immediate)))
                          ;; The entry only became reachable just now, so
                          ;; a winner that fired the cancels before this
                          ;; point missed it — off-loop, resume-from
                          ;; snapshots the cancel list at resume time.
                          (unless (eq? (unbox state) 'waiting)
                            (%channel-remove-getter! channel entry))))))))

  (define (flow-get! channel)
    (flow-perform (flow-get channel)))

  (define (flow-get-try channel default)
    (%flow-check-caller-thread! 'flow-get-try)
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
  ;; Latches: fire once, wake every waiter
  ;;------------------------------------------------------------
  ;;
  ;; A channel hands each value to ONE getter, so it cannot tell
  ;; everyone who cares that something happened: a stop request to
  ;; every producer of a fan-out, or "the result for this key is
  ;; complete" to every query parked on it. A latch fires at most once,
  ;; with a value, and from then on every wait -- parked or later --
  ;; completes with that value. It is never reset; a new episode is a
  ;; new latch.
  ;;
  ;; The channel's locking discipline: the mutex guards the value and
  ;; the waiter list and is held only for list surgery, never across a
  ;; resume. Waiting is an event, so it composes: a producer that
  ;; should be stoppable puts (flow-latch-wait stop) in its own choices.
  (define %flow-latch-unfired (list 'unfired))

  (define-record-type* <flow2-latch>
    (make-flow-latch% mutex value waiters)
    flow-latch?
    (mutex   flow-latch-mutex)
    (value   flow-latch-value   flow-latch-value!)
    (waiters flow-latch-waiters flow-latch-waiters!))

  (define (make-flow-latch)
    (make-flow-latch% (make-mutex) %flow-latch-unfired '()))

  (define (flow-latch-fired? latch)
    (with-mutex (flow-latch-mutex latch)
      (not (eq? (flow-latch-value latch) %flow-latch-unfired))))

  ;; #t when this call fired LATCH, #f when it had already fired, in
  ;; which case the first value stays. Like flow-put!, callable from the
  ;; loop thread and from a compute thread.
  (define (flow-latch-fire! latch value)
    (%flow-check-caller-thread! 'flow-latch-fire!)
    (let ((waiters
           (with-mutex (flow-latch-mutex latch)
             (and (eq? (flow-latch-value latch) %flow-latch-unfired)
                  (let ((waiters (flow-latch-waiters latch)))
                    (flow-latch-value! latch value)
                    (flow-latch-waiters! latch '())
                    waiters)))))
      (and waiters
           (begin
             ;; Outside the mutex: a resume runs continuation code. A
             ;; resume that reports #f lost to another base of its own
             ;; choice, and since a latch wait consumes nothing there is
             ;; nothing to put back.
             (for-each (lambda (resume) (resume value)) waiters)
             #t))))

  (define (%latch-remove-waiter! latch resume)
    (with-mutex (flow-latch-mutex latch)
      (flow-latch-waiters! latch (remq resume (flow-latch-waiters latch)))))

  (define (flow-latch-wait latch)
    (make-flow% 'base (cons 'flow2-latch latch)
                (lambda (x) x)
                (lambda ()
                  (let ((value (with-mutex (flow-latch-mutex latch)
                                 (flow-latch-value latch))))
                    (and (not (eq? value %flow-latch-unfired))
                         (lambda () value))))
                (lambda (state resume register-cancel!)
                  ;; Armed before the waiter is reachable, with the
                  ;; recheck below closing the rest of the window --
                  ;; flow-get's discipline, for flow-get's reason: a
                  ;; wait that loses a choice must not stay on the list
                  ;; pinning its continuation until the latch fires,
                  ;; which for a stop latch may be never.
                  (register-cancel!
                   (lambda () (%latch-remove-waiter! latch resume)))
                  (let ((value
                         (with-mutex (flow-latch-mutex latch)
                           (let ((value (flow-latch-value latch)))
                             (when (eq? value %flow-latch-unfired)
                               (flow-latch-waiters!
                                latch
                                (append (flow-latch-waiters latch)
                                        (list resume))))
                             value))))
                    (if (eq? value %flow-latch-unfired)
                        (unless (eq? (unbox state) 'waiting)
                          (%latch-remove-waiter! latch resume))
                        (resume value))))))

  (define (flow-latch-wait! latch)
    (flow-perform (flow-latch-wait latch)))

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
  ;; flow2 has two such structures, so both are readable: a channel's
  ;; parked getters and its parked putters.

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
    ;; Growing a bound wakes the putters it admits, and a wake is a
    ;; resume -- on a stray thread, the unsynchronized loop-spawn the
    ;; guard exists to prevent. This was the one entry point that
    ;; reaches the scheduler and had no guard after the fourth pass
    ;; moved it to the choke point.
    (%flow-check-caller-thread! 'flow-channel-buffer-size!)
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
                    ;; The SQE is claimed BEFORE the timespec is
                    ;; foreign-alloc'd: loop-get-sqe raises when the
                    ;; ring is full, and an allocation made ahead of it
                    ;; had no owner to free it — 16 leaked bytes per
                    ;; raise, on exactly the overloaded tick that
                    ;; produces many of them. The other events allocate
                    ;; only GC-managed bytevectors ahead of their SQE.
                    (let* ((ring (loop-ring (loop-current)))
                           (id   (loop-alloc-id!))
                           (ns   (exact (round (* seconds 1000000000))))
                           (sqe  (loop-get-sqe ring))
                           (ts   (make-timespec (div ns 1000000000)
                                                (mod ns 1000000000))))
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

  ;; A read that LOSES its choice still has to account for the bytes.
  ;; The recv and the base that beat it — typically the deadline in the
  ;; idle-timeout idiom — complete in the same tick whenever the loop is
  ;; late draining, i.e. under load, i.e. exactly when idle timeouts
  ;; fire; the handlers then run in completion-queue order and the
  ;; loser's resume returns #f. The bytes are already off the socket at
  ;; that point, so discarding them is silent, unrecoverable data loss
  ;; for that connection — a request truncated with nothing logged. It
  ;; goes on the fd's recv backlog instead, and this event's try pops it
  ;; before preparing another recv, which is the shape flow-accept has
  ;; always had for a client it could not hand over.
  ;;
  ;; Only the data case needs it. A clean EOF and a failure are both
  ;; level-triggered: the next recv reports them again, so there is
  ;; nothing to preserve.
  ;;
  ;; A loser's recv is NOT cancelled: it is left in flight, ownerless,
  ;; and the next flow-read on the fd adopts it instead of preparing a
  ;; second one. Cancelling it reordered the stream. The cancel is
  ;; asynchronous, so the kernel could still complete the old recv with
  ;; data -- after the next flow-read had already found the backlog
  ;; empty and submitted a recv of its own. That second recv then took
  ;; the NEXT bytes, the late completion parked the earlier ones on the
  ;; backlog, and the read after returned them: (timeout "two" "one")
  ;; where the peer sent "one" then "two". With at most one recv in
  ;; flight per reader, bytes arrive in the order the kernel took them.
  ;;
  ;; An orphan nobody adopts completes into the backlog, or is torn
  ;; down by loop-close-prep! with everything else the fd owns.
  (define-record-type* <flow2-recv>
    (%make-flow-recv id owner)
    %flow-recv?
    (id    %flow-recv-id)
    (owner %flow-recv-owner %flow-recv-owner!))

  ;; fd -> the <flow2-recv> left in flight by a reader that lost.
  ;; Loop thread only, like every ring event.
  (define %flow-recv-orphans (make-eqv-hashtable))

  (define (%flow-recv-orphans-clear!)
    (hashtable-clear! %flow-recv-orphans))

  ;; Still in flight means its handler is still registered. A close
  ;; deletes the handler at once, before its synthetic completion runs
  ;; a tick later, and the kernel may reissue the number in between --
  ;; so an orphan whose handler is gone belongs to the old fd and must
  ;; not be handed to a reader of the new one.
  (define (%flow-recv-in-flight? r)
    (hashtable-contains? (loop-handlers (loop-current)) (%flow-recv-id r)))

  (define (%flow-recv-adopt! fd)
    (let ((r (hashtable-ref %flow-recv-orphans fd #f)))
      (and r
           (begin
             (hashtable-delete! %flow-recv-orphans fd)
             (and (%flow-recv-in-flight? r) r)))))

  ;; The losing reader's cancel. If its recv has already completed --
  ;; the same-tick race above -- the completion handled the bytes and
  ;; there is nothing left to hand over.
  (define (%flow-recv-orphan! fd r resume)
    (when (and (eq? (%flow-recv-owner r) resume)
               (%flow-recv-in-flight? r))
      (%flow-recv-owner! r #f)
      (hashtable-set! %flow-recv-orphans fd r)))

  (define (%flow-recv-complete! fd r res)
    (loop-fd-op-remove! fd (%flow-recv-id r))
    (when (eq? (hashtable-ref %flow-recv-orphans fd #f) r)
      (hashtable-delete! %flow-recv-orphans fd))
    (let ((owner (%flow-recv-owner r))
          (bv (loop-buf-data-take! (%flow-recv-id r))))
      (%flow-recv-owner! r #f)
      (cond
       ((fx<? res 0) (when owner (owner #f)))
       ((fxzero? res) (when owner (owner #t)))
       ((not (and owner (owner bv)))
        (loop-recv-backlog-put! fd bv)))))

  (define flow-read
    (lambda (fd)
      (make-flow% 'base #f
                  (lambda (x) x)
                  (lambda ()
                    (let ((bv (loop-recv-backlog-take! fd)))
                      (and bv (lambda () bv))))
                  (lambda (state resume register-cancel!)
                    (let ((r (or (%flow-recv-adopt! fd)
                                 (%flow-recv-submit! fd))))
                      (%flow-recv-owner! r resume)
                      (register-cancel!
                       (lambda () (%flow-recv-orphan! fd r resume))))))))

  (define (%flow-recv-submit! fd)
    (let* ((ring (loop-ring (loop-current)))
           (id   (loop-alloc-id!))
           (sqe  (loop-get-sqe ring))
           (r    (%make-flow-recv id #f)))
      (io-uring-prep-recv sqe fd 0 (loop-buf-ring-buf-size) 0)
      (io-uring-sqe-set-flags sqe IOSQE-BUFFER-SELECT)
      (io-uring-sqe-set-buf-group sqe (loop-buf-ring-bgid))
      (io-uring-sqe-set-data64 sqe id)
      ;; In the fd's operation index, not just in loop-handlers. Without
      ;; it loop-close-prep!'s teardown pass skipped this recv, so its
      ;; handler survived the close -- and a recv that completed with
      ;; data in the window between the cancel submit and the kernel
      ;; acting on it then ran the backlog put, re-creating a stash for
      ;; an fd whose stash had just been purged. After the kernel
      ;; reissued the number, the next connection's first flow-read was
      ;; served the previous connection's bytes. Registered, the handler
      ;; is deleted by the purge and the late CQE finds nothing (the
      ;; drain has already recycled its buffer and drops the orphan).
      ;; That matters more now that a losing recv stays in flight.
      ;;
      ;; flow-write deliberately does NOT register: its handler is what
      ;; unlocks the pinned bytevector, and running it from the
      ;; synthetic resume would unlock memory the kernel may not be done
      ;; reading. It has no stash to corrupt, and its real -ECANCELED
      ;; CQE releases the pin.
      (loop-fd-op-add! fd id)
      (hashtable-set! (loop-handlers (loop-current)) id
                      (lambda (res) (%flow-recv-complete! fd r res)))
      r))

  ;; One send, reporting what the kernel actually took: a positive
  ;; fixnum, or #f on failure. START defaults to 0 and lets a caller
  ;; resume a partial write without copying anything.
  ;;
  ;; It deliberately does NOT loop internally. Resubmitting the
  ;; remainder from inside the completion handler runs on the
  ;; scheduler's stack with the fiber parked across every round trip,
  ;; and that one decision caused three separate problems:
  ;;
  ;; - Uncancellable. The chain belonged to no fiber, so nothing could
  ;;   stop it: it kept issuing ring operations against
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
                   ;; A zero-byte remainder is ready with count 0, no
                   ;; syscall: START may legitimately equal the length
                   ;; (the validation above allows it, and a caller-side
                   ;; resume loop naturally produces it), and sending
                   ;; zero bytes returns res = 0, which the handler
                   ;; below must keep reading as failure for a real
                   ;; send. 0 is truthy in Scheme, so callers testing
                   ;; (and n ...) see success, as flow-write-all! does.
                   (lambda ()
                     (and (fx=? start (bytevector-length bv))
                          (lambda () 0)))
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
  ;; the server is idle. Any flow-accept that lost a choice to a
  ;; timeout hit this on the first loss.
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
                                          ;; #t, not 'eof: flow-read has
                                          ;; said #t for a clean end of
                                          ;; stream all along, and two
                                          ;; encodings for the same
                                          ;; condition across two read
                                          ;; verbs is a trap that only
                                          ;; ever costs a caller.
                                          ((fxzero? res) #t)
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
                      ;; A losing write must not stay in the ring:
                      ;; io_uring resolves the fd when it processes
                      ;; the SQE, so a write still queued after the
                      ;; cleanup path closed that fd can land on whatever
                      ;; reopened the number.
                      (register-cancel!
                       (lambda ()
                         (let ((csqe (loop-get-sqe ring)))
                           (io-uring-prep-cancel64 csqe id 0)
                           (io-uring-sqe-set-data64 csqe (loop-alloc-id!))))))))))

  ;; The one ring event here that deliberately registers NO cancel:
  ;; cancelling a close would leak the fd, so the close is left to
  ;; complete. Composed with other bases the perform is decided as a
  ;; whole; a close already in flight when another base wins still
  ;; completes, and this handler's resume then reports #f and is
  ;; discarded — the kernel released the descriptor either way.
  (define flow-close
    (lambda (fd)
      (make-flow% 'base 'flow2-close
                  (lambda (x) x)
                  (lambda () #f)
                  (lambda (state resume register-cancel!)
                    (loop-close-block fd
                                      (lambda (res)
                                        (resume (and (fx>=? res 0) res))))))))

  ;;------------------------------------------------------------
  ;; Fibers
  ;;------------------------------------------------------------

  ;; An error nobody handled ends the fiber and becomes a log entry,
  ;; (flow2 uncaught fiber CONDITION) -- what happens to it next is the
  ;; logger's business: flushed to a port, handed to a procedure, or
  ;; drained and asserted on by a test. It used to reach loop-apply's
  ;; catch-all, which writes straight to stderr, so the one event most
  ;; worth routing was the one flow-log never saw. The catch-all stays
  ;; as the last resort for a fiber started below flow2, through the
  ;; ring layer directly.
  (define (%fiber-run thunk)
    (guard (ex (#t (flow-log (list 'flow2 'uncaught 'fiber
                                   (%flow-condition-sexp ex)))))
      (thunk)))

  ;; Fire and forget: flow2 keeps no record of the fiber, so nothing
  ;; waits for it and nothing can stop it but its own code. A spawner
  ;; that wants to know how it ended says so in the thunk -- put a
  ;; result, or a failure, on a channel it reads.
  ;;
  ;; A worker is refused because there is deliberately no cross-thread
  ;; spawn; a thread the user forked is refused for the blunter reason
  ;; that loop-spawn is not synchronized against the loop's own
  ;; take-and-clear of that list.
  (define (flow-spawn thunk)
    (when (%worker-current?) (%flow-wrong-thread 'flow-spawn))
    (%flow-check-caller-thread! 'flow-spawn)
    (loop-spawn (lambda () (%fiber-run thunk))))

  ;;------------------------------------------------------------
  ;; Lifecycle and compute threads
  ;;------------------------------------------------------------

  (define %flow-worker-stop (list 'stop))

  ;; Queue THUNK on a worker's request channel. Like flow-spawn, fire
  ;; and forget: the task's results, and its failures if anyone needs
  ;; them, travel over channels the task itself writes to. A submit
  ;; parks when the request channel is full, which is the pool's
  ;; backpressure.
  (define (flow-submit! worker-channel thunk)
    ;; A submit reaches %channel-put! directly whenever the worker
    ;; channel has room, so it never touches flow-perform's guard and
    ;; needs its own.
    (%flow-check-caller-thread! 'flow-submit!)
    (%channel-put! worker-channel thunk #f))

  ;; The per-worker framework loop: dequeue, run. A raise the task did
  ;; not handle itself is logged as (flow2 uncaught task WORKER
  ;; CONDITION) and the worker takes its next task: the pool must not
  ;; shrink because one task failed.
  ;;
  ;; There used to be an always-a-reply rule here: the framework put a
  ;; compute <flow-error> on the task's response channel for it. That
  ;; made flow2 a party to every task's protocol -- it had to know the
  ;; reply channel, force past its bound, and stay out of a straggler's
  ;; way -- for a guarantee a task gets from one guard of its own.
  (define (%worker-body pool channel)
    (%thread-own-set! %worker-pool pool)
    (let loop ()
      (let ((task (%flow-perform (flow-get channel))))
        (unless (eq? task %flow-worker-stop)
          (guard (ex (#t
                      ;; Named by its request channel's (worker . i), so
                      ;; the entry says WHERE.
                      (flow-log (list 'flow2 'uncaught 'task
                                      (flow-channel-name channel)
                                      (%flow-condition-sexp ex)))))
            (task))
          (loop)))))

  ;; Start the loop on the calling thread — the main thread — and
  ;; spawn PROC as fiber zero with the list of worker request
  ;; channels (empty when COMPUTE-COUNT is zero, the default). The
  ;; count is fixed for the run; flow-run returns when the loop
  ;; stops. Parked fibers are then simply never resumed — flow-stop
  ;; is a shutdown, not a cancellation; tell your own fibers to finish
  ;; first when cleanup must run.
  (define flow-run
    (case-lambda
      ((proc) (flow-run proc 0))
      ((proc compute-count)
       ;; Before anything is touched. A negative count is not zero, so
       ;; a pool was created, and the forking loop below terminates on
       ;; (fx=? i compute-count) -- never, for i >= 0: it forked until
       ;; fork-thread failed with EAGAIN.
       (unless (and (fixnum? compute-count) (fx>=? compute-count 0))
         (error 'flow-run "compute-count must be a non-negative fixnum"
                compute-count))
       ;; A compute thread never runs a loop -- the Rationale's one
       ;; structural rule -- and there is one loop per process: loop-new
       ;; frees the ring that is running. Nested in a fiber, a second
       ;; flow-run tore down its caller's loop and the outer fiber died
       ;; with "attempt to apply non-procedure #f"; from a compute task it
       ;; did the same to the main thread's ring and two threads ran one
       ;; loop until the process hung. The claim is a CAS, so two threads
       ;; starting at once cannot both win it.
       (when (%worker-current?) (%flow-wrong-thread 'flow-run))
       (unless (box-cas! %flow-loop-thread #f (get-thread-id))
         (error 'flow-run "a flow-run is already in progress"))
       ;; Whoever claimed the loop owns it for this run; see
       ;; %flow-check-caller-thread!. Everything from here on releases
       ;; the claim on its way out, raise included. A start that failed
       ;; -- eventfd creation refused for want of descriptors, say --
       ;; used to leave it set, and every flow2 call from another thread
       ;; then raised wrong-thread against a run that did not exist.
       (let ((pool #f) (channels '()))
         (guard (ex (#t (%flow-run-release! pool channels) (raise ex)))
           (loop-new)
           ;; orphaned recvs belong to the previous ring
           (%flow-recv-orphans-clear!)
           ;; The pool is created per run and handed to the workers and
           ;; the collector as a closure, never through a global — a
           ;; straggler from a previous run therefore cannot touch this
           ;; run's eventfd, mailbox, or live count (see <flow2-pool>) --
           ;; and is refused at every entry point, because it does not
           ;; hold %flow-pool-current.
           (unless (fxzero? compute-count)
             ;; the eventfd first: it is the call that fails in practice,
             ;; and the buffer then never needs freeing on that path.
             ;; Two cells: the signal value, and the read target.
             (let* ((fd (%eventfd-create))
                    (buffer (foreign-alloc 16)))
               (foreign-set! 'unsigned-64 buffer 0 1)
               (foreign-set! 'unsigned-64 buffer 8 0)
               (set! pool (make-flow-pool% fd buffer (box '())
                                           (make-mutex) (make-condition)
                                           0 #t))))
           (when pool
             (set-box! %flow-pool-current pool)
             (loop-spawn (lambda () (%collector pool)))
             (let start ((i 0))
               (unless (fx=? i compute-count)
                 (let ((channel (make-flow-channel (cons 'worker i))))
                   ;; counted before the fork, so a shutdown that runs
                   ;; after a failed fork still joins every thread that
                   ;; did start
                   (with-mutex (%pool-mutex pool)
                     (%pool-live! pool (fx+ (%pool-live pool) 1)))
                   (set! channels (append channels (list channel)))
                   (guard (ex (#t (%flow-worker-exited! pool) (raise ex)))
                     (fork-thread
                      (lambda ()
                        (dynamic-wind
                          void
                          (lambda () (%worker-body pool channel))
                          (lambda () (%flow-worker-exited! pool))))))
                   (start (fx+ i 1))))))
           (let ((channels channels))
             (loop-spawn (lambda () (%fiber-run (lambda () (proc channels))))))
           (loop-run))
         (%flow-run-release! pool channels)
         (void)))))

  ;; The way out of a run, normal or not: join the pool, then give up
  ;; the claim. Cleared after the pool is joined, so a worker that puts
  ;; on its way out is still recognised as this run's rather than as a
  ;; stray thread. A straggler that outlives the join is recognised as
  ;; nobody's from the next run on.
  (define (%flow-run-release! pool channels)
    (when pool
      (%flow-shutdown-pool! pool channels))
    (set-box! %flow-pool-current #f)
    (set-box! %flow-loop-thread #f))

  ;; Stop the pool and, crucially, WAIT before dismantling what the
  ;; workers are still using.
  ;;
  ;; The fd is closed only once every worker has provably exited.
  ;; Where that cannot be established -- a task parked on a channel
  ;; nobody will ever put to, which flow-stop does not cancel because it
  ;; is a shutdown and not a cancellation -- the eventfd and its buffer
  ;; are deliberately LEAKED with the pool record and the situation
  ;; logged. Leaking one descriptor is strictly better than handing a
  ;; live writer a number the process is about to reuse, and the log
  ;; names how many workers were still out. Because the straggler keeps
  ;; its pool — and through it that same leaked fd — its later signals,
  ;; spawns, and its final exit all land on the dead run's record and
  ;; never on the next run's (see <flow2-pool>).
  (define %flow-shutdown-join-seconds 2.0)

  (define (%flow-shutdown-pool! pool channels)
    (%pool-running?! pool #f)
    (for-each (lambda (channel)
                (%channel-put! channel %flow-worker-stop #t))
              channels)
    (%eventfd-signal! pool)
    (let ((deadline (+ (real-time)
                       (exact (round (* 1000 %flow-shutdown-join-seconds))))))
      (let ((stragglers
             (with-mutex (%pool-mutex pool)
               (let wait ()
                 (cond
                  ((fxzero? (%pool-live pool)) 0)
                  ((>= (real-time) deadline) (%pool-live pool))
                  (else
                   ;; Bounded, so a stuck worker cannot make flow-run
                   ;; itself hang.
                   (condition-wait (%pool-gone pool) (%pool-mutex pool)
                                   (make-time 'time-duration 50000000 0))
                   (wait)))))))
        (cond
         ((fxzero? stragglers)
          (%eventfd-close (%pool-eventfd pool))
          (foreign-free (%pool-buffer pool)))
         (else
          (flow-log (list 'flow2 'shutdown-workers-still-running stragglers))))))
    (void))

  (define (flow-stop)
    (when (%worker-current?) (%flow-wrong-thread 'flow-stop))
    (%flow-check-caller-thread! 'flow-stop)
    (loop-stop))

  (include "letloop/flow2.check.scm"))

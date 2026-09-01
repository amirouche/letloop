;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop flow2) — fibers, channels, and nurseries over io_uring.
;; A fork of (letloop flow); see src/letloop/flow2/README.md for the
;; full design document. The two architectural changes from flow:
;;
;; - Only the main thread touches the ring. Compute threads have no
;;   I/O verbs; the only cross-thread primitive is the channel, and
;;   channels here are buffered mutex-protected queues rather than
;;   rendezvous — put never parks (a bounded channel raises overflow
;;   instead), so put is a plain procedure, not an event, and flow's
;;   same-channel-choice hazard is inexpressible.
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
   make-flow-channel flow-channel? flow-channel-buffer-size!
   flow-put! flow-get flow-get! flow-get-try

   ;; timers
   flow-timeout flow-sleep

   ;; network and file I/O
   flow-accept flow-read flow-write
   flow-open flow-read-at flow-write-at flow-close
   O-RDONLY O-WRONLY O-RDWR O-CREAT O-TRUNC O-APPEND

   ;; fibers and nurseries
   flow-spawn flow-nursery flow-scope? flow-scope-cancel!
   flow-monitor flow-cancelled?

   ;; lifecycle and compute threads
   flow-run flow-stop flow-submit!

   ;; checks
   ~check-flow2-000/error-symbol-dispatch
   ~check-flow2-000/error-predicates
   ~check-flow2-001/always-ready
   ~check-flow2-001/wrap-order
   ~check-flow2-002/channel-buffered-fifo
   ~check-flow2-002/channel-get-parks-until-put
   ~check-flow2-002/channel-bound-overflow
   ~check-flow2-002/channel-bound-below-length
   ~check-flow2-002/channel-get-try-default
   ~check-flow2-002/channel-get-or-timeout
   ~check-flow2-003/nursery-join-waits-children
   ~check-flow2-003/nursery-child-raise-cancels-siblings
   ~check-flow2-003/nursery-scope-cancel
   ~check-flow2-003/nursery-perform-after-cancel-raises
   ~check-flow2-003/block-raise-reaches-the-scope
   ~check-flow2-004/monitor-in-time
   ~check-flow2-004/monitor-deadline
   ~check-flow2-005/worker-task-replies
   ~check-flow2-005/worker-raise-becomes-compute-error
   ~check-flow2-005/worker-ring-event-raises-wrong-thread
   ~check-flow2-005/worker-cancelled-along-monitor
   ~check-flow2-005/worker-io-protocol-roundtrip

   ;; block-and-wait machinery, ported from (letloop flow)'s
   ;; ~check-flow-011 series
   ~check-flow2-011/sync-resume-runs-later-cancels
   ~check-flow2-011/raising-cancel-does-not-lose-fiber
   ~check-flow2-011/winner-own-cancel-not-fired
   ~check-flow2-011/raise-after-sync-win-keeps-winner

   ;; network and file I/O, ported from (letloop flow)'s ~check-flow-006
   ;; and ~check-flow-009 series -- the 11 fd- and ring-touching checks
   ;; the fork had dropped
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
        (let ((ptr (foreign-alloc 8)))
          (foreign-set! 'unsigned-64 ptr 0 1)
          (call-with-values (lambda () (func fd ptr 8))
            (lambda (n errno)
              (foreign-free ptr)
              (>= n 0)))))))

  (define %eventfd-close
    (let ((func (foreign-procedure __atomic __disable_interrupts __errno
                                   "close" (int) int)))
      (lambda (fd) (call-with-values (lambda () (func fd)) (lambda (r e) r)))))

  ;; Park the collector fiber on FD until a worker signals it.
  (define %eventfd-wait
    (lambda (fd)
      (let ((buffer (foreign-alloc 8)))
        (let* ((sqe (loop-get-sqe (loop-ring (loop-current))))
               (id (loop-alloc-id!)))
          (io-uring-prep-read sqe fd buffer 8 0)
          (io-uring-sqe-set-data64 sqe id)
          (let ((res (loop-abort
                      (lambda (k)
                        (hashtable-set! (loop-handlers (loop-current)) id k)))))
            (foreign-free buffer)
            res)))))

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

  (define %collector
    (lambda ()
      (let loop ()
        (when %flow2-workers-running?
          (%eventfd-wait %flow2-eventfd)
          (for-each loop-spawn (flow-box-drain! %cross-thread-spawns))
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
  ;; (state . resume) pairs; children, join-waiters and subscopes are
  ;; loop-thread-only.
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
    (make-flow-scope% parent (box 'open) (box '()) (box 0) 0 '() '()))

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

  ;; One child returned or raised; at zero, resume the join.
  (define (%scope-child-done! scope)
    (flow-scope-children! scope (fx- (flow-scope-children scope) 1))
    (when (fxzero? (flow-scope-children scope))
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
                  (and (fxzero? (flow-scope-children scope))
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
           (memq (car tag) '(flow2-get flow2-scope))
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
    (make-flow-channel% mutex in out length bound getters)
    flow-channel?
    (mutex   flow-channel-mutex)
    (in      flow-channel-in      flow-channel-in!)
    (out     flow-channel-out     flow-channel-out!)
    (length  flow-channel-length  flow-channel-length!)
    (bound   flow-channel-bound   flow-channel-bound!)
    (getters flow-channel-getters flow-channel-getters!))

  (define (make-flow-channel)
    (make-flow-channel% (make-mutex) '() '() 0 #f '()))

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
  (define (%channel-dequeue! channel)
    (when (null? (flow-channel-out channel))
      (flow-channel-out! channel (reverse (flow-channel-in channel)))
      (flow-channel-in! channel '()))
    (let ((value (car (flow-channel-out channel))))
      (flow-channel-out! channel (cdr (flow-channel-out channel)))
      (flow-channel-length! channel (fx- (flow-channel-length channel) 1))
      value))

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
                     (let ((bound (flow-channel-bound channel)))
                       (when (and bound (not force?)
                                  (fx>=? (flow-channel-length channel) bound))
                         (raise (make-flow-error
                                 'overflow "flow2: channel over its bound"
                                 (list bound) #f)))
                       (flow-channel-in!
                        channel (cons obj (flow-channel-in channel)))
                       (flow-channel-length!
                        channel (fx+ (flow-channel-length channel) 1))
                       #f))))))
        (when entry
          (unless ((flow-getter-resume entry) obj)
            (try))))))

  (define (flow-put! channel obj)
    (when (and (%worker-current?)
               (let ((scope (%task-scope)))
                 (and scope (%scope-dead? scope))))
      ;; A cancelled task's sends are dropped — the raise is how the
      ;; task observes its own death at the next channel operation.
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
                  (with-mutex (flow-channel-mutex channel)
                    (and (fx>? (flow-channel-length channel) 0)
                         (let ((value (%channel-dequeue! channel)))
                           (lambda () value)))))
                (lambda (state resume register-cancel!)
                  (let ((entry (make-flow-getter state resume (box #f))))
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
                      (when immediate
                        (resume (cdr immediate))))))))

  (define (flow-get! channel)
    (flow-perform (flow-get channel)))

  (define (flow-get-try channel default)
    (when (and (%worker-current?)
               (let ((scope (%task-scope)))
                 (and scope (%scope-dead? scope))))
      (raise (%flow-cancelled-error)))
    (with-mutex (flow-channel-mutex channel)
      (if (fx>? (flow-channel-length channel) 0)
          (%channel-dequeue! channel)
          default)))

  ;; Raises overflow right here when the channel already holds more
  ;; than N values: the bound is never observably violated, and the
  ;; queue-vs-bound mismatch surfaces at the call site that made it.
  (define (flow-channel-buffer-size! channel n)
    (unless (and (fixnum? n) (fx>=? n 0))
      (error 'flow-channel-buffer-size! "bound must be a non-negative fixnum" n))
    (with-mutex (flow-channel-mutex channel)
      (when (fx>? (flow-channel-length channel) n)
        (raise (make-flow-error 'overflow
                                "flow2: channel already over the requested bound"
                                (list n (flow-channel-length channel)) #f)))
      (flow-channel-bound! channel n)))

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
                                        (unlock-object bv)
                                        (resume (and (fx>=? res 0) res)))))))))

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
          (flow-scope-children! scope (fx+ (flow-scope-children scope) 1))
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
    (when (not (fxzero? (flow-scope-children scope)))
      (flow-perform (%scope-join-event scope)))
    (when (flow-scope? parent)
      (flow-scope-subscopes!
       parent (remq scope (flow-scope-subscopes parent))))
    (let ((reason (unbox (flow-scope-state scope))))
      (cond
       ((pair? reason) (raise (cdr reason)))
       ((eq? reason 'timeout)
        (raise (make-flow-error 'timeout "flow2: deadline expired" '() #f)))
       ((eq? reason 'cancelled)
        (raise (%flow-cancelled-error)))
       ((eq? (car outcome) 'raised) (raise (cdr outcome)))
       (else (cdr outcome)))))

  ;; PROC runs on the calling fiber with the fresh scope current;
  ;; fibers it spawns are the scope's children. The join — waiting
  ;; for every child — happens under the PARENT scope, so an
  ;; enclosing nursery's cancellation still reaches a parent parked
  ;; here. PROC raising fails the scope exactly like a child raising:
  ;; siblings are cancelled, and the first recorded error re-raises
  ;; after the children have drained.
  (define (flow-nursery proc)
    (when (%worker-current?) (%flow-wrong-thread 'flow-nursery))
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
    (let* ((parent %scope-current)
           (scope (%make-scope parent))
           (result (box #f)))
      (unless (eq? parent %root-scope)
        (flow-scope-subscopes! parent (cons scope (flow-scope-subscopes parent))))
      (%scope-spawn! scope
                     (lambda ()
                       (set-box! result (cons 'ok (thunk)))))
      (let ((race (flow-perform
                   (flow-choice
                    (flow-wrap (%scope-join-event scope)
                               (lambda (_) 'joined))
                    (flow-wrap (flow-timeout seconds)
                               (lambda (_) 'deadline))))))
        (when (eq? race 'deadline)
          (%scope-fail! scope 'timeout))
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

  (define (flow-submit! worker-channel thunk response-channel)
    (let ((scope (if (%worker-current?)
                     (or (%task-scope) %root-scope)
                     %scope-current)))
      (%channel-put! worker-channel
                     (make-flow-task thunk response-channel scope)
                     #f)))

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
          (unless (%scope-dead? (flow-task-scope task))
            (%task-scope (flow-task-scope task))
            (guard (ex ((and (flow-error-cancelled? ex)
                             (%scope-dead? (flow-task-scope task)))
                        (void))
                       (#t
                        (%channel-put! (flow-task-response task)
                                       (make-flow-error
                                        'compute "flow2: worker task raised"
                                        '() ex)
                                       #t)))
              ((flow-task-thunk task)))
            (%task-scope #f))
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
                    (set! %flow2-workers-running? #t)
                    (loop-spawn %collector)
                    (let start ((i 0) (channels '()))
                      (if (fx=? i compute-count)
                          (reverse channels)
                          (let ((channel (make-flow-channel)))
                            (fork-thread (lambda () (%worker-body channel)))
                            (start (fx+ i 1) (cons channel channels)))))))))
         (loop-spawn (lambda ()
                       (set! %scope-current %root-scope)
                       (proc channels)))
         (loop-run)
         (unless (null? channels)
           (set! %flow2-workers-running? #f)
           (for-each (lambda (channel)
                       (%channel-put! channel %flow-worker-stop #t))
                     channels)
           (%eventfd-signal! %flow2-eventfd)
           (%eventfd-close %flow2-eventfd)
           (set! %flow2-eventfd #f))
         (void)))))

  (define (flow-stop)
    (when (%worker-current?) (%flow-wrong-thread 'flow-stop))
    (loop-stop))

  (include "letloop/flow2.check.scm"))

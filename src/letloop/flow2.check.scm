;; Checks for (letloop flow2). Included at the tail of the library;
;; discovered by `make check` via the ~check- exports. Checks that
;; need the loop use the real entry point — flow-run with a fiber
;; zero that calls flow-stop — rather than driving loop-run-once by
;; hand, so the lifecycle (worker pool startup and teardown included)
;; is exercised on every run.

;;------------------------------------------------------------
;; Errors
;;------------------------------------------------------------

(define (~check-flow2-000/error-symbol-dispatch)
  (define err (make-flow-error 'timeout "deadline" '(0.25) #f))
  (assert (flow-error? err))
  (assert (eq? 'slow (case (flow-error-symbol err)
                       ((timeout) 'slow)
                       ((cancelled) 'gone)
                       (else 'other))))
  (assert (equal? "deadline" (flow-error-message err)))
  (assert (equal? '(0.25) (flow-error-irritants err)))
  (assert (not (flow-error-cause err)))
  #t)

(define (~check-flow2-000/error-predicates)
  (define cancelled (make-flow-error 'cancelled "" '() #f))
  (define compute (make-flow-error 'compute "" '() 'boom))
  (assert (flow-error-cancelled? cancelled))
  (assert (not (flow-error-timeout? cancelled)))
  (assert (not (flow-error-overflow? cancelled)))
  (assert (flow-error-compute? compute))
  (assert (eq? 'boom (flow-error-cause compute)))
  (assert (not (flow-error? 'compute)))
  (assert (not (flow-error-wrong-thread? 42)))
  #t)

;;------------------------------------------------------------
;; Event core
;;------------------------------------------------------------

(define (~check-flow2-001/always-ready)
  (define ev (make-flow (lambda (x) x)
                        (lambda () (lambda () 42))
                        (lambda (state resume register-cancel!)
                          (error 'block "should never block"))))
  (equal? (flow-perform ev) 42))

(define (~check-flow2-001/wrap-order)
  (define base (make-flow (lambda (x) x)
                          (lambda () (lambda () 1))
                          (lambda (state resume register-cancel!)
                            (error 'block "should never block"))))
  (define w1 (flow-wrap base (lambda (x) (* x 10))))
  (define w2 (flow-wrap w1 (lambda (x) (+ x 1))))
  (equal? (flow-perform w2) 11))

;;------------------------------------------------------------
;; Channels
;;------------------------------------------------------------

;; Buffered put needs no peer and no loop; get! drains FIFO.
(define (~check-flow2-002/channel-buffered-fifo)
  (define ch (make-flow-channel))
  (flow-put! ch 'a)
  (flow-put! ch 'b)
  (flow-put! ch 'c)
  (assert (eq? 'a (flow-get! ch)))
  (assert (eq? 'b (flow-get! ch)))
  (assert (eq? 'c (flow-get! ch)))
  #t)

(define (~check-flow2-002/channel-get-parks-until-put)
  (define ch (make-flow-channel))
  (define result #f)
  (flow-run
   (lambda (workers)
     (flow-spawn
      (lambda ()
        (flow-sleep 0.005)
        (flow-put! ch 'delivered)))
     (set! result (flow-get! ch))
     (flow-stop)))
  (eq? result 'delivered))

(define (~check-flow2-002/channel-bound-overflow)
  (define ch (make-flow-channel))
  (flow-channel-buffer-size! ch 2)
  (flow-put! ch 1)
  (flow-put! ch 2)
  (assert (guard (ex ((flow-error-overflow? ex) #t))
            (flow-put! ch 3)
            #f))
  ;; the failed put enqueued nothing
  (assert (eqv? 1 (flow-get! ch)))
  (assert (eqv? 2 (flow-get! ch)))
  (assert (eq? 'empty (flow-get-try ch 'empty)))
  #t)

;; Shrinking the bound below the current queue length raises at the
;; call site; the bound is never observably violated.
(define (~check-flow2-002/channel-bound-below-length)
  (define ch (make-flow-channel))
  (flow-put! ch 1)
  (flow-put! ch 2)
  (flow-put! ch 3)
  (guard (ex ((flow-error-overflow? ex)
              (equal? '(2 3) (flow-error-irritants ex))))
    (flow-channel-buffer-size! ch 2)
    #f))

(define (~check-flow2-002/channel-get-try-default)
  (define ch (make-flow-channel))
  (assert (eq? 'nope (flow-get-try ch 'nope)))
  (flow-put! ch 'yes)
  (assert (eq? 'yes (flow-get-try ch 'nope)))
  (assert (eq? 'nope (flow-get-try ch 'nope)))
  #t)

(define (~check-flow2-002/channel-get-or-timeout)
  (define ch (make-flow-channel))
  (define first #f)
  (define second #f)
  (flow-run
   (lambda (workers)
     ;; empty channel: the timeout wins
     (set! first (flow-perform
                  (flow-choice (flow-get ch)
                               (flow-wrap (flow-timeout 0.005)
                                          (lambda (_) 'late)))))
     ;; value arrives first: the get wins, the losing 5s timeout is
     ;; cancelled on the ring (flow-run would otherwise still return,
     ;; but the ring op must not linger)
     (flow-spawn (lambda () (flow-put! ch 'fast)))
     (set! second (flow-perform
                   (flow-choice (flow-get ch)
                                (flow-wrap (flow-timeout 5.0)
                                           (lambda (_) 'late)))))
     (flow-stop)))
  (and (eq? first 'late) (eq? second 'fast)))

;; Finding 7 of the 2026-08-17 review. flow-get's block proc, when it
;; finds the channel non-empty at registration time, claims its entry
;; and dequeues -- and then used to ignore resume's return value.
;; resume reports #f when an earlier base of the same perform already
;; won, and registration is a for-each with no early exit, so that is
;; reachable: the value is out of the channel, the fiber is committed
;; elsewhere, and nothing receives it. Silent, and the peer that was
;; waiting for it looks like the culprit.
;;
;; FILLER makes the interleaving deterministic instead of waiting for a
;; compute thread to produce it: never ready at poll, and its block does
;; both halves itself -- fills the channel, then wins -- so the flow-get
;; registering after it necessarily takes the immediate path with the
;; state box already synched. Standalone sweep in
;; checks/repro-flow2-get-immediate-drop.scm.
(define (~check-flow2-002/losing-get-does-not-eat-a-value)
  (define ch (make-flow-channel))
  (define result #f)
  (define filler (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (flow-put! ch 'the-value)
                              (resume 'winner))))
  (flow-run
   (lambda (workers)
     ;; filler first: flow-flatten preserves choice order, and the
     ;; registration for-each walks it in order.
     (set! result (flow-perform (flow-choice filler (flow-get ch))))
     (flow-stop)))
  (assert (eq? result 'winner))
  ;; The value the losing get dequeued must still be in the channel.
  (assert (eq? 'the-value (flow-get-try ch 'EMPTY)))
  #t)

;;------------------------------------------------------------
;; Nurseries
;;------------------------------------------------------------

(define (~check-flow2-003/nursery-join-waits-children)
  (define done '())
  (define after-nursery #f)
  (flow-run
   (lambda (workers)
     (flow-nursery
      (lambda (scope)
        (for-each (lambda (i)
                    (flow-spawn
                     (lambda ()
                       (flow-sleep 0.005)
                       (set! done (cons i done)))))
                  '(1 2 3))))
     ;; the join guarantees all three ran before the nursery returned
     (set! after-nursery (length done))
     (flow-stop)))
  (eqv? after-nursery 3))

(define (~check-flow2-003/nursery-child-raise-cancels-siblings)
  (define never (make-flow-channel))
  (define sibling-cancelled? #f)
  (define reraised #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((eq? ex 'boom) (set! reraised #t)))
       (flow-nursery
        (lambda (scope)
          ;; sibling parked forever on an empty channel: only the
          ;; scope's cancellation can resume it
          (flow-spawn
           (lambda ()
             (guard (ex ((flow-error-cancelled? ex)
                         (set! sibling-cancelled? #t)
                         (raise ex)))
               (flow-get! never))))
          (flow-spawn
           (lambda ()
             (flow-sleep 0.005)
             (raise 'boom))))))
     (flow-stop)))
  (and sibling-cancelled? reraised))

(define (~check-flow2-003/nursery-scope-cancel)
  (define never (make-flow-channel))
  (define outcome #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-cancelled? ex) (set! outcome 'cancelled)))
       (flow-nursery
        (lambda (scope)
          (flow-spawn (lambda () (flow-get! never)))
          (flow-spawn
           (lambda ()
             (flow-sleep 0.005)
             (flow-scope-cancel! scope))))))
     (flow-stop)))
  (eq? outcome 'cancelled))

;; Once the scope is dead, the next synchronization raises before
;; even polling — the fast-path check at flow-perform's entry.
(define (~check-flow2-003/nursery-perform-after-cancel-raises)
  (define ch (make-flow-channel))
  (define raised-inside? #f)
  (flow-run
   (lambda (workers)
     (flow-put! ch 'ready)  ;; even a ready value must not mask cancellation
     (guard (ex ((flow-error-cancelled? ex) (void)))
       (flow-nursery
        (lambda (scope)
          (flow-scope-cancel! scope)
          (guard (ex ((flow-error-cancelled? ex) (set! raised-inside? #t)))
            (flow-get! ch)))))
     (flow-stop)))
  raised-inside?)

;; A raise from a base event's BLOCK procedure must reach the fiber,
;; and through it the scope -- exactly as a raise from the fiber's body
;; does. Before the fix, block procs ran inside loop-abort's thunk, on
;; the scheduler's stack with the prompt already unwound, so the raise
;; escaped to loop-apply's catch-all: the fiber died without
;; %scope-child-done!, the scope's child count never reached zero, and
;; the nursery's join parked forever. Case B below HUNG.
;;
;; Not synthetic. loop-get-sqe raises "submission queue full" past 256
;; queued ops in one tick, reachable from flow-timeout / flow-read /
;; flow-write / flow-open / flow-read-at / flow-write-at; and
;; loop-accept-block raises "concurrent accept on fd". Standalone
;; reproducer: checks/repro-flow2-block-raise.scm.
(define (~check-flow2-003/block-raise-reaches-the-scope)
  ;; never ready, so flow-perform must call block -- and block raises
  (define (bad-event)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume register-cancel!)
                 (error 'bad-event "raised from block"))))
  (define root-saw #f)
  (define nursery-saw #f)
  (flow-run
   (lambda (workers)
     ;; A: root scope -- flow-perform raises on the performing fiber
     (guard (ex (#t (set! root-saw #t)))
       (flow-perform (bad-event)))
     ;; B: inside a nursery -- the child's raise fails the scope and
     ;; re-raises at the join, instead of hanging it
     (guard (ex (#t (set! nursery-saw #t)))
       (flow-nursery
        (lambda (scope)
          (flow-spawn (lambda () (flow-perform (bad-event)))))))
     (flow-stop)))
  (assert root-saw)
  (assert nursery-saw)
  #t)

;; A waiter registered on a scope that is ALREADY dead must be woken
;; by the registration itself. %scope-fail! CASes the state and then
;; drains the waiters list, so anything consed on after that drain is
;; attached to a corpse -- and on a compute thread, which registers its
;; own waiter from its own thread, losing that race parks the worker
;; forever and shrinks the pool by one with no other symptom.
;;
;; Asserted deterministically against the internals rather than by
;; racing: the real interleaving needs the loop thread's CAS to land
;; inside a ~1us window on the worker, which took a 6000-round deadline
;; sweep to hit even once (checks/repro-flow2-scope-waiter-race.scm
;; does exactly that, and is kept for the end-to-end proof). What
;; belongs in `make check` is the invariant the fix establishes, and
;; that is checkable in microseconds.
(define (~check-flow2-003/waiter-on-dead-scope-is-woken)
  (define scope (%make-scope %root-scope))
  (define woken 'not-woken)
  ;; kill it first: the waiters list has already been drained
  (%scope-fail! scope 'cancelled)
  (%scope-add-waiter! scope (box 'waiting)
                      (lambda (value) (set! woken value) #t))
  (assert (eq? woken %flow-cancel-sentinel))
  ;; and the ordinary order still works: register, then cancel
  (let ((live (%make-scope %root-scope))
        (seen 'not-woken))
    (%scope-add-waiter! live (box 'waiting)
                        (lambda (value) (set! seen value) #t))
    (assert (eq? seen 'not-woken))
    (%scope-fail! live 'cancelled)
    (assert (eq? seen %flow-cancel-sentinel)))
  #t)

;;------------------------------------------------------------
;; Monitor
;;------------------------------------------------------------

(define (~check-flow2-004/monitor-in-time)
  (define result #f)
  (flow-run
   (lambda (workers)
     (set! result (flow-monitor 5.0
                                (lambda ()
                                  (flow-sleep 0.005)
                                  'done)))
     (flow-stop)))
  (eq? result 'done))

(define (~check-flow2-004/monitor-deadline)
  (define never (make-flow-channel))
  (define outcome #f)
  (define child-cancelled? #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-timeout? ex) (set! outcome 'timeout)))
       (flow-monitor 0.01
                     (lambda ()
                       ;; a nested spawn, cancelled transitively
                       (flow-spawn
                        (lambda ()
                          (guard (ex ((flow-error-cancelled? ex)
                                      (set! child-cancelled? #t)
                                      (raise ex)))
                            (flow-get! never))))
                       (flow-get! never))))
     (flow-stop)))
  (and (eq? outcome 'timeout) child-cancelled?))

;;------------------------------------------------------------
;; Compute threads
;;------------------------------------------------------------

(define (~check-flow2-005/worker-task-replies)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda () (flow-put! response 'pong))
                     response)
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (eq? result 'pong))

;; The always-a-reply guarantee: a raising task cannot hang its
;; submitter — the guard wraps the raise as a compute <flow-error>
;; carrying the original in its cause.
(define (~check-flow2-005/worker-raise-becomes-compute-error)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda () (raise 'kaboom))
                     response)
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (and (flow-error-compute? result)
       (eq? 'kaboom (flow-error-cause result))))

;; Workers have no I/O verbs: performing a ring event raises
;; wrong-thread on the compute thread, catchable by the task.
(define (~check-flow2-005/worker-ring-event-raises-wrong-thread)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda ()
                       (guard (ex ((flow-error-wrong-thread? ex)
                                   (flow-put! response 'wrong-thread)))
                         (flow-sleep 0.01)
                         (flow-put! response 'slept)))
                     response)
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (eq? result 'wrong-thread))

;; A monitor's deadline reaches a task parked on a channel: the get
;; raises cancelled on the compute thread, the framework drops the
;; unwound task without a reply, and the worker survives to serve
;; the next submission.
(define (~check-flow2-005/worker-cancelled-along-monitor)
  (define timed-out? #f)
  (define alive #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-timeout? ex) (set! timed-out? #t)))
       (flow-monitor 0.01
                     (lambda ()
                       (let ((up (make-flow-channel))
                             (down (make-flow-channel)))
                         (flow-submit! (car workers)
                                       (lambda () (flow-get! down))
                                       up)
                         (flow-get! up)))))
     ;; same worker, fresh scope: still serving
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda () (flow-put! response 'alive))
                     response)
       (set! alive (flow-get! response)))
     (flow-stop))
   1)
  (and timed-out? (eq? alive 'alive)))

;; The verb-less I/O protocol from the design document, in miniature:
;; the task requests work over its response channel, the submitting
;; fiber serves each request in a fiber of its own, results return on
;; the task's downlink.
(define (~check-flow2-005/worker-io-protocol-roundtrip)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((up (make-flow-channel))
           (down (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda ()
                       (flow-put! up (list 'double 21))
                       (let ((doubled (flow-get! down)))
                         (flow-put! up (list 'done doubled))))
                     up)
       (let serve ()
         (let ((msg (flow-get! up)))
           (cond
            ((flow-error? msg) (set! result msg))
            ((eq? (car msg) 'double)
             (flow-spawn
              (lambda () (flow-put! down (* 2 (cadr msg)))))
             (serve))
            ((eq? (car msg) 'done)
             (set! result (cadr msg))))))
       (flow-stop)))
   1)
  (eqv? result 42))

;;------------------------------------------------------------
;; Block-and-wait machinery
;;------------------------------------------------------------
;;
;; Ported 2026-08-17 from (letloop flow)'s ~check-flow-011 series,
;; which the fork had also dropped. These cover flow-block-and-wait-on-
;; loop itself -- synchronous wins during registration, a raising cancel
;; thunk, and which cancels fire -- i.e. exactly the procedure finding 1
;; of the review lives in.
;;
;; They deliberately drive the loop with BOUNDED loop-run-once ticks
;; rather than flow-run, keeping flow's rationale verbatim: a buggy
;; build must FAIL these rather than hang `make check`. That also means
;; they run outside flow-run, which never gets to reset %scope-current
;; -- so each sets it explicitly, the way flow-run does, rather than
;; inheriting whatever scope the previous check happened to leave in
;; that global.

;; A base that resumes INLINE, during the registration for-each, wins
;; before the bases after it have registered their cancels. The cancel
;; list is therefore unboxed inside a spawned thunk rather than at
;; resume time; snapshotting it at resume would fire an incomplete list
;; and leave the later base armed forever.
(define (~check-flow2-011/sync-resume-runs-later-cancels)
  (define cancelled #f)
  (define result #f)
  (define sync (make-flow (lambda (x) x)
                          (lambda () #f)        ;; try: not ready
                          (lambda (state resume register-cancel!)
                            (resume 'sync))))   ;; resume inline, mid-registration
  (define parked (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (register-cancel!
                               (lambda () (set! cancelled #t))))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice sync parked)))))
  (let tick ((n 0))
    (when (fx<? n 4)
      (loop-run-once)
      (tick (fx+ n 1))))
  (and (eq? result 'sync) cancelled))

;; A cancel thunk that raises -- loop-get-sqe does exactly that on a
;; full submission queue -- must not take the winning continuation down
;; with it: the state box has already CASed to 'synched, so if k is lost
;; here no other base can ever resume the fiber and it is gone for good,
;; silently. The raise itself is reported by loop-apply's guard, which
;; is fine; what this pins down is that the fiber still gets its value.
(define (~check-flow2-011/raising-cancel-does-not-lose-fiber)
  (define result #f)
  (define winner (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (loop-spawn (lambda () (resume 'won))))))
  (define raising (make-flow (lambda (x) x)
                             (lambda () #f)
                             (lambda (state resume register-cancel!)
                               (register-cancel!
                                (lambda ()
                                  (error 'raising-cancel "boom"))))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice winner raising)))))
  (let tick ((n 0))
    (when (fx<? n 6)
      (loop-run-once)
      (tick (fx+ n 1))))
  (eq? result 'won))

;; The winner of a choice must not fire its OWN cancel: its operation
;; already completed, so the cancel SQE it would prep is a guaranteed
;; no-op the kernel answers with -ENOENT -- one wasted SQE + CQE round
;; trip per completed operation, on the hottest path this bookkeeping
;; has. Losers' cancels must of course still all fire.
(define (~check-flow2-011/winner-own-cancel-not-fired)
  (define winner-cancelled #f)
  (define loser-cancelled #f)
  (define result #f)
  (define winner (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (register-cancel!
                               (lambda () (set! winner-cancelled #t)))
                              (loop-spawn (lambda () (resume 'won))))))
  (define loser (make-flow (lambda (x) x)
                           (lambda () #f)
                           (lambda (state resume register-cancel!)
                             (register-cancel!
                              (lambda () (set! loser-cancelled #t))))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice winner loser)))))
  (let tick ((n 0))
    (when (fx<? n 6)
      (loop-run-once)
      (tick (fx+ n 1))))
  (and (eq? result 'won)
       loser-cancelled
       (not winner-cancelled)))

;; The two dropped checks above, composed -- and the branch finding 1's
;; fix introduced. An earlier base wins synchronously during
;; registration, and a LATER base's block proc then raises. The fiber is
;; already committed to the winner's value, so the raise has nowhere to
;; go: the fix reports it on stderr rather than swallowing it, and must
;; not disturb the winner. Asserted here: the fiber still gets 'sync,
;; the later base's own cancel still fires, and nothing hangs.
(define (~check-flow2-011/raise-after-sync-win-keeps-winner)
  (define cancelled #f)
  (define result 'not-set)
  (define sync (make-flow (lambda (x) x)
                          (lambda () #f)
                          (lambda (state resume register-cancel!)
                            (resume 'sync))))
  (define raising (make-flow (lambda (x) x)
                             (lambda () #f)
                             (lambda (state resume register-cancel!)
                               (register-cancel!
                                (lambda () (set! cancelled #t)))
                               (error 'raising-block "boom"))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice sync raising)))))
  (let tick ((n 0))
    (when (fx<? n 6)
      (loop-run-once)
      (tick (fx+ n 1))))
  (and (eq? result 'sync) cancelled))

;;------------------------------------------------------------
;; Network and file I/O
;;------------------------------------------------------------
;;
;; Ported 2026-08-17 from (letloop flow)'s ~check-flow-006/* and
;; ~check-flow-009/*, which the flow2 fork dropped along with the other
;; fd- and ring-touching checks (flow ships 40 checks, flow2 shipped
;; 21, and all 11 I/O ones were on the missing side). The numbering is
;; kept deliberately -- 006 for sockets, 009 for files -- so each check
;; here is traceable to the flow original it came from.
;;
;; Two adaptations, no semantic changes: they drive the loop through
;; flow-run / flow-spawn / flow-stop rather than loop-new / loop-spawn /
;; loop-run, per this file's header, and they use ports 1824x + 10 so a
;; single `make check` process running both suites never contends for a
;; listening address.

;; Under /tmp/letloop so `make clean` sweeps anything a crashed check
;; leaves behind; each check also deletes its own file on the way out.
(define %flow2-check-directory "/tmp/letloop")

(define (flow2-check-path name)
  (unless (file-exists? %flow2-check-directory)
    (mkdir %flow2-check-directory))
  (string-append %flow2-check-directory "/" name))

(define (flow2-check-remove! path)
  (when (file-exists? path)
    (delete-file path)))

;; Deterministic filler, so a mis-offset read is caught by content and
;; not merely by length.
(define (flow2-check-bytes size)
  (let ((bv (make-bytevector size)))
    (let loop ((i 0))
      (if (fx=? i size)
          bv
          (begin (bytevector-u8-set! bv i (fxmod (fx* i 7) 251))
                 (loop (fx+ i 1)))))))

(define (flow2-check-concatenate bvs)
  (let ((out (make-bytevector (apply + (map bytevector-length bvs)))))
    (let loop ((bvs bvs) (offset 0))
      (if (null? bvs)
          out
          (let ((n (bytevector-length (car bvs))))
            (bytevector-copy! (car bvs) 0 out offset n)
            (loop (cdr bvs) (fx+ offset n)))))))

;; flow-write-at reports what it actually wrote rather than looping, so
;; a caller that wants "all of it" writes the loop itself -- as here.
(define (flow2-check-write-all fd offset bv)
  (let loop ((offset offset) (bv bv))
    (let ((n (flow-perform (flow-write-at fd offset bv))))
      (cond
       ((not n) #f)
       ((fx=? n (bytevector-length bv)) #t)
       (else (loop (fx+ offset n) (subbytevector bv n)))))))

(define (flow2-check-create! path bv)
  (let ((fd (flow-perform
             (flow-open path (fxior O-WRONLY O-CREAT O-TRUNC) #o600))))
    (and fd
         (let ((ok (flow2-check-write-all fd 0 bv)))
           (flow-perform (flow-close fd))
           ok))))

;; Real loopback TCP: a listener accepts via flow-accept, echoes one
;; message back via flow-read/flow-write; the peer connects, sends, and
;; reads the echo back via flow-write/flow-read too, so both directions
;; of both events run over a real socket pair.
(define (~check-flow2-006/echo-pair)
  (define PORT 18244)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let* ((client (flow-perform (flow-accept listen-fd)))
                 (data   (flow-perform (flow-read client))))
            (flow-perform (flow-write client data))
            (loop-close client))))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                (flow-perform (flow-write fd (string->utf8 "hello")))
                (set! result (flow-perform (flow-read fd)))
                (loop-close fd))))
          (loop-close listen-fd)
          (flow-stop))))))
  (equal? result (string->utf8 "hello")))

;; A read racing a short timeout on a silent socket must resolve via
;; the timeout (not hang), and -- the actual point of this check -- the
;; fd must still be usable afterward: a fresh flow-read on the same fd
;; must see the client's message once it actually arrives, proving the
;; cancelled/lost read did not consume or corrupt the connection.
;;
;; This is the check whose accept-side analogue flow2 still lacks: see
;; checks/repro-flow2-accept-cancel.scm, where a cancelled flow-accept
;; leaves its handler registered and poisons the listening fd. flow-read
;; passes here because it calls register-cancel! and flow-accept does
;; not.
(define (~check-flow2-006/read-or-timeout-leaves-fd-usable)
  (define PORT 18245)
  (define timed-out #f)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let ((client (flow-perform (flow-accept listen-fd))))
            (set! timed-out
                  (eq? (flow-perform
                        (flow-choice (flow-read client) (flow-timeout 0.05)))
                       (void)))
            (set! result (flow-perform (flow-read client)))
            (loop-close client)
            (loop-close listen-fd)
            (flow-stop))))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                ;; stay silent well past the server's 50ms
                ;; read-or-timeout before finally sending
                (flow-sleep 0.2)
                (flow-perform (flow-write fd (string->utf8 "late")))
                (loop-close fd)))))))))
  (and timed-out
       (equal? result (string->utf8 "late"))))

;; The accept-side counterpart of read-or-timeout-leaves-fd-usable, and
;; the check flow never had either. A cancelled flow-accept used to
;; leave its handler registered against the multishot's id, so the next
;; flow-accept on that listener raised "concurrent accept on fd" --
;; permanently, for as long as no client arrived to clear the slot.
;; What is asserted is the part that matters: after the cancellation the
;; listener still ACCEPTS, and the client that connects afterwards is
;; delivered intact. Reproducer: checks/repro-flow2-accept-cancel.scm.
(define (~check-flow2-006/accept-cancel-leaves-listener-usable)
  (define PORT 18247)
  (define timed-out #f)
  (define accepted #f)
  (define received #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          ;; The whole body is guarded so a regression FAILS this check
          ;; rather than hanging the suite: an unguarded raise here
          ;; would kill the fiber before it reaches flow-stop, and
          ;; flow-run would never return.
          (guard (ex (#t (set! accepted 'raised)))
            ;; nothing is connecting yet, so the monitor's deadline
            ;; cancels this accept
            (set! timed-out
                  (guard (ex ((flow-error-timeout? ex) #t))
                    (flow-monitor 0.05
                                  (lambda ()
                                    (flow-perform (flow-accept listen-fd))))
                    #f))
            ;; the listener must still be usable
            (let ((client (flow-perform (flow-accept listen-fd))))
              (set! accepted (fixnum? client))
              (set! received (flow-perform (flow-read client)))
              (loop-close client)))
          (loop-close listen-fd)
          (flow-stop)))
       (flow-spawn
        (lambda ()
          ;; connect only after the first accept has been cancelled
          (flow-sleep 0.15)
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                (flow-perform (flow-write fd (string->utf8 "after-cancel")))
                (flow-sleep 0.05)
                (loop-close fd)))))))))
  (and timed-out
       (eq? accepted #t)
       (equal? received (string->utf8 "after-cancel"))))

;; A per-connection request/echo loop that races each read against an
;; idle timeout and closes gracefully once the peer goes silent -- the
;; realistic consumer shape, and the one http/server.body.scm's dispatch
;; race now uses on flow (see fbacb46).
(define (~check-flow2-006/request-loop-idle-timeout)
  (define PORT 18246)
  (define echoed '())
  (define closed-on-timeout #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let ((client (flow-perform (flow-accept listen-fd))))
            (let request-loop ()
              (let ((result (flow-perform
                             (flow-choice (flow-read client)
                                          (flow-timeout 0.1)))))
                (cond
                 ((eq? result (void))     ;; idle timeout won
                  (set! closed-on-timeout #t)
                  (loop-close client))
                 ((eq? result #t)         ;; peer EOF
                  (loop-close client))
                 (else
                  (set! echoed (cons result echoed))
                  (flow-perform (flow-write client result))
                  (request-loop)))))
            (loop-close listen-fd)
            (flow-stop))))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                (flow-perform (flow-write fd (string->utf8 "one")))
                (flow-perform (flow-read fd))
                (flow-perform (flow-write fd (string->utf8 "two")))
                (flow-perform (flow-read fd))
                ;; go silent well past the server's 100ms per-read idle
                ;; timeout before closing
                (flow-sleep 0.3)
                (loop-close fd)))))))))
  (and (equal? (reverse echoed)
               (list (string->utf8 "one") (string->utf8 "two")))
       closed-on-timeout))

;; Round trip through a real file: create + write + close, then reopen
;; read-only and read the whole thing back in one call.
(define (~check-flow2-009/file-write-read-roundtrip)
  (define path (flow2-check-path "flow2-009-roundtrip.bin"))
  (define payload (string->utf8 "the quick brown fox jumps over the lazy dog"))
  (define written #f)
  (define result #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (let ((fd (flow-perform
                (flow-open path (fxior O-WRONLY O-CREAT O-TRUNC) #o600))))
       (set! written (flow-perform (flow-write-at fd 0 payload)))
       (flow-perform (flow-close fd)))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (set! result (flow-perform (flow-read-at fd 0 65536)))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (and (eqv? written (bytevector-length payload))
       (equal? result payload)))

;; A file deliberately larger than the chunk size and not a multiple of
;; it: the loop must see two full chunks, one short chunk, and then
;; 'eof -- the caller tracking its own offset the whole way, since these
;; primitives keep no cursor.
(define (~check-flow2-009/chunked-read-until-eof)
  (define path (flow2-check-path "flow2-009-chunked.bin"))
  (define chunk 4096)
  (define payload (flow2-check-bytes 10000))
  (define created #f)
  (define pieces '())
  (define saw-eof #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (let read-loop ((offset 0))
         (let ((piece (flow-perform (flow-read-at fd offset chunk))))
           (cond
            ((eq? piece 'eof) (set! saw-eof #t))
            ((not piece) (void))     ;; error: fall through, check fails
            (else
             (set! pieces (cons piece pieces))
             (read-loop (fx+ offset (bytevector-length piece)))))))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (let ((pieces (reverse pieces)))
    (and created
         saw-eof
         (fx=? (length pieces) 3)                    ;; 4096 + 4096 + 1808
         (fx=? (bytevector-length (list-ref pieces 2)) 1808)
         (equal? (flow2-check-concatenate pieces) payload))))

;; Neither the write nor the read starts at 0: the marker must land at
;; exactly OFFSET (the head of the file untouched), and reading it back
;; from OFFSET must return it -- an offset silently ignored would fail
;; both halves.
(define (~check-flow2-009/nonzero-offset)
  (define path (flow2-check-path "flow2-009-offset.bin"))
  (define offset 4000)
  (define payload (flow2-check-bytes 8192))
  (define marker (string->utf8 "MARKER-AT-4000"))
  (define created #f)
  (define patched #f)
  (define read-back #f)
  (define head #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDWR 0))))
       (set! patched (flow-perform (flow-write-at fd offset marker)))
       (set! read-back (flow-perform
                        (flow-read-at fd offset (bytevector-length marker))))
       (set! head (flow-perform (flow-read-at fd 0 16)))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (and created
       (eqv? patched (bytevector-length marker))
       (equal? read-back marker)
       (equal? head (subbytevector payload 0 16))))

;; The file-fd counterpart of the socket check above. A regular-file
;; read cannot be made to hang the way a silent socket can, so which
;; base wins is genuinely racy here (a 0-second timeout against an
;; already-satisfiable read) and neither outcome is asserted; what is
;; asserted is the part that matters -- after the choice resolves,
;; whichever way it went, a plain flow-read-at on the same fd still
;; returns the right bytes, so a losing/cancelled read leaves neither
;; the fd nor the loop's handler table in a half-submitted state.
(define (~check-flow2-009/read-or-timeout-leaves-fd-usable)
  (define path (flow2-check-path "flow2-009-choice.bin"))
  (define payload (flow2-check-bytes 512))
  (define created #f)
  (define slow #f)
  (define racy #f)
  (define after #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       ;; a read that cannot lose: 1s is forever next to a 512-byte
       ;; read off the page cache
       (set! slow (flow-perform
                   (flow-choice (flow-read-at fd 0 512) (flow-timeout 1.0))))
       ;; a read that may well lose
       (set! racy (flow-perform
                   (flow-choice (flow-read-at fd 0 512) (flow-timeout 0.0))))
       (set! after (flow-perform (flow-read-at fd 0 512)))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (and created
       (equal? slow payload)
       (or (equal? racy payload) (eq? racy (void)))
       (equal? after payload)))

;; Opening a missing path without O-CREAT must yield #f -- the same
;; shape flow-read/flow-write use for failure -- rather than hanging or
;; handing back a negative "fd" that would then be used as one.
(define (~check-flow2-009/open-nonexistent-fails)
  (define path (flow2-check-path "flow2-009-does-not-exist.bin"))
  (define result 'not-set)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! result (flow-perform (flow-open path O-RDONLY 0)))
     (flow-stop)))
  (eq? result #f))

;; flow-open on the losing side of a choice: the loser-with-success
;; path in flow-open's completion handler must close the fd nobody now
;; owns (detected via resume's #f "did I win" return) rather than leak
;; it. Which base wins each round is genuinely racy (a 0-second timeout
;; against a page-cache openat), so run many rounds and assert the
;; invariant that holds either way: the process's open-fd count is back
;; at its baseline once the dust settles -- a leaked orphan would grow
;; it by one per round the timeout won.
;;
;; flow-open is the ONE place flow2 kept this careful resume-returns-#f
;; handling (flow2.scm:857); this is the check that keeps it honest.
(define (~check-flow2-009/open-loses-choice-no-fd-leak)
  (define path (flow2-check-path "flow2-009-open-choice.bin"))
  (define rounds 50)
  (define failures 0)
  (define baseline #f)
  (define final #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (flow2-check-create! path (flow2-check-bytes 64))
     (set! baseline (length (directory-list "/proc/self/fd")))
     (let round ((n 0))
       (unless (fx=? n rounds)
         (let ((r (flow-perform
                   (flow-choice (flow-open path O-RDONLY 0)
                                (flow-timeout 0.0)))))
           (cond
            ((fixnum? r) (flow-perform (flow-close r)))  ;; open won: ours to close
            ((eq? r (void)) (void))                      ;; timeout won: orphan path
            (else (set! failures (fx+ failures 1)))))
         (round (fx+ n 1))))
     ;; give straggler orphan-close CQEs from the last rounds a tick or
     ;; two to land before counting
     (flow-sleep 0.05)
     (set! final (length (directory-list "/proc/self/fd")))
     (flow-stop)))
  (flow2-check-remove! path)
  (and (fxzero? failures)
       (fixnum? baseline)
       (eqv? final baseline)))

;; flow-close composed under flow-choice: per its committed-at-block
;; caveat, once the choice reaches the block phase the close happens
;; whichever base wins -- so afterward the fd must actually be closed,
;; and a probe read on it must yield #f (EBADF), never data. Nothing
;; opens another fd between the close and the probe, so the descriptor
;; number cannot have been reused out from under the test.
(define (~check-flow2-009/close-under-choice-fd-actually-closed)
  (define path (flow2-check-path "flow2-009-close-choice.bin"))
  (define created #f)
  (define chosen 'not-set)
  (define after 'not-set)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path (flow2-check-bytes 64)))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (set! chosen (flow-perform
                     (flow-choice (flow-close fd) (flow-timeout 1.0))))
       ;; in the unlikely event the timeout won, the committed close's
       ;; CQE still needs a tick to land before the probe
       (flow-sleep 0.02)
       (set! after (flow-perform (flow-read-at fd 0 16))))
     (flow-stop)))
  (flow2-check-remove! path)
  (and created
       (or (eqv? chosen 0) (eq? chosen (void)))
       (eq? after #f)))

;; flow-close while another fiber's flow-read-at is parked on the same
;; fd, both submitted in the same tick: exercises loop-close-block's
;; IORING_OP_ASYNC_CANCEL(CANCEL_ALL) actually matching an in-flight
;; file op. The assertions are liveness and shape: the reader fiber
;; resumes (not stranded) with either the payload or #f, and the close
;; itself succeeds.
(define (~check-flow2-009/close-while-read-in-flight)
  (define path (flow2-check-path "flow2-009-close-inflight.bin"))
  (define payload (flow2-check-bytes 512))
  (define created #f)
  (define read-result 'not-set)
  (define read-done #f)
  (define close-result 'not-set)
  (define close-done #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       ;; spawn is LIFO within a tick: spawn the closer first so the
       ;; reader's block runs first next tick and its SQE is already
       ;; prepped (handler parked) when loop-close-block preps the
       ;; cancel + close right after it.
       (flow-spawn
        (lambda ()
          (set! close-result (flow-perform (flow-close fd)))
          (set! close-done #t)))
       (flow-spawn
        (lambda ()
          (set! read-result (flow-perform (flow-read-at fd 0 512)))
          (set! read-done #t)))
       (let wait ((n 0))
         (flow-sleep 0.01)
         (if (or (and read-done close-done) (fx>? n 500))
             (flow-stop)
             (wait (fx+ n 1)))))))
  (flow2-check-remove! path)
  (and created
       read-done
       close-done
       (eqv? close-result 0)
       (or (equal? read-result payload) (eq? read-result #f))))

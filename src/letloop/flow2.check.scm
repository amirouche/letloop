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

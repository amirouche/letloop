;; Scheduler-level checks for (letloop liburing low): the fiber
;; dispatch loop (loop-spawn / loop-run-once / loop-run) and the
;; continuation machinery underneath it (call-with-loop-prompt /
;; loop-abort). Included at the tail of the library; discovered by
;; `make check` via the ~check- exports.
;;
;; The 000/001 pair is a regression test for the "resumed fiber that
;; returns normally re-runs its siblings" bug: loop-abort's call/1cc
;; capture is undelimited, so a suspended fiber's continuation carries
;; the not-yet-run tail of loop-run-once's (for-each ... thunks) over
;; its siblings in the tick that suspended it. Before the fix in
;; call-with-loop-prompt, a fiber that returned normally after being
;; resumed fell into that stale tail and every sibling still pending
;; at suspend time ran a second time. See the comment above
;; loop-prompt-current in low.scm.

;; loop-spawn conses onto the pending list and loop-run-once
;; for-eaches it, so the LAST thunk spawned runs FIRST in the tick.
;; Every check below therefore spawns the sibling(s) first and the
;; suspending fiber last, so that the sibling is still pending — i.e.
;; sits in the tail of the continuation loop-abort captures — when the
;; fiber suspends.

(define (~check-low-000/resumed-return-does-not-rerun-sibling)
  (define sibling-runs 0)
  (define resumed #f)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! sibling-runs (fx+ sibling-runs 1))))
  (loop-spawn
   (lambda ()
     ;; suspends here: loop-abort captures an undelimited continuation
     ;; whose tail still contains the sibling above
     (loop-sleep 0.01)
     (set! resumed #t)
     (loop-stop)
     ;; ...and then returns normally, rather than suspending forever
     ;; or looping. This is the shape that used to re-run the sibling.
     (void)))
  (loop-run)
  (and resumed (eqv? sibling-runs 1)))

(define (~check-low-001/two-suspends-then-return)
  ;; Same thing across two suspensions: the second loop-abort must
  ;; capture against the prompt of the tick that resumed the fiber,
  ;; and the final normal return must land in the tick that resumed it
  ;; the second time.
  (define sibling-runs 0)
  (define resumes 0)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! sibling-runs (fx+ sibling-runs 1))))
  (loop-spawn
   (lambda ()
     (loop-sleep 0.005)
     (set! resumes (fx+ resumes 1))
     (loop-sleep 0.005)
     (set! resumes (fx+ resumes 1))
     (loop-stop)
     (void)))
  (loop-run)
  (and (eqv? resumes 2) (eqv? sibling-runs 1)))

(define (~check-low-002/non-suspending-fibers-run-once)
  ;; The fiber that never suspends must keep returning through the
  ;; plain-return path, exactly once each, in loop-spawn's LIFO order.
  (define log '())
  (loop-new)
  (loop-spawn (lambda () (set! log (cons 'a log))))
  (loop-spawn (lambda () (set! log (cons 'b log))))
  (loop-spawn (lambda () (set! log (cons 'c log)) (loop-stop)))
  (loop-run)
  (equal? (reverse log) '(c b a)))

(define (~check-low-003/resumed-return-does-not-rerun-late-spawn)
  ;; A sibling spawned from *inside* another fiber during the same
  ;; tick lands in the next tick's thunk list; check that a fiber
  ;; resumed and returning normally does not re-run those either.
  (define sibling-runs 0)
  (define done #f)
  (loop-new)
  (loop-spawn
   (lambda ()
     ;; runs first; queues two thunks for the following tick, then
     ;; suspends long enough that the fiber spawned below outlives it
     (loop-spawn (lambda () (set! sibling-runs (fx+ sibling-runs 1))))
     (loop-spawn
      (lambda ()
        (loop-sleep 0.01)
        (set! done #t)
        (loop-stop)
        (void)))
     (loop-sleep 0.5)
     (void)))
  (loop-run)
  (and done (eqv? sibling-runs 1)))

;; A CQE that carries IORING_CQE_F_BUFFER but finds no handler must
;; not leave its copied-out bytevector behind in %buf-data — nothing
;; would ever collect it. The handler-less shape is real:
;; loop-close-prep! deletes the parked handlers of a closing fd's
;; in-flight reads and resumes them with -ECANCELED, but when the
;; recv completed with data before the async cancel landed, its CQE
;; still arrives with F_BUFFER set; before the fix each such race
;; grew %buf-data by one entry, forever, under connection churn.
;; Reproduced here without the race: arm a buffer-select recv whose
;; completion id never gets a handler at all — the exact state the
;; close path leaves behind — send it bytes over loopback, and check
;; %buf-data is empty once the CQE has been drained. The 200ms grace
;; before stopping dwarfs loopback delivery latency.
(define (~check-low-004/handlerless-buffered-cqe-not-retained)
  (define PORT 18240)
  (define listen-fd (loop-socket-new AF-INET SOCK-STREAM 0))
  (define done #f)
  (loop-new)
  (loop-bind listen-fd "127.0.0.1" PORT)
  (loop-listen listen-fd 128)
  (loop-spawn
   (lambda ()
     (let ((client (loop-accept listen-fd)))
       ;; buffer-select recv prepped exactly like loop-read, minus
       ;; the handler registration
       (let* ((sqe (loop-get-sqe (loop-ring %loop)))
              (id  (loop-alloc-id!)))
         (io-uring-prep-recv sqe client 0 %buf-ring-buf-size 0)
         (io-uring-sqe-set-flags sqe IOSQE-BUFFER-SELECT)
         (io-uring-sqe-set-buf-group sqe %buf-ring-bgid)
         (io-uring-sqe-set-data64 sqe id)))))
  (loop-spawn
   (lambda ()
     (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
       (lambda (addr addrlen)
         (let ((fd (loop-connect addr addrlen)))
           (foreign-free addr)
           (loop-write fd (string->utf8 "orphan"))
           (loop-sleep 0.2)
           (set! done #t)
           (loop-stop))))))
  (loop-run)
  (and done (fxzero? (hashtable-size %buf-data))))

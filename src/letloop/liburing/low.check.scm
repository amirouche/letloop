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

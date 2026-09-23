;; Reproducer for finding 3 of the 2026-08-17 adverse review of
;; (letloop flow2): %scope-add-waiter! registers a scope waiter without
;; rechecking whether the scope is already dead, so a compute thread
;; racing %scope-fail!'s drain is never resumed and parks forever. The
;; pool silently shrinks; nothing in the main program reports it.
;;
;; Mechanism. %scope-fail! (flow2.scm:381) CASes the scope's state and
;; then drains its waiters list. %scope-add-waiter! (flow2.scm:364)
;; conses onto that same list with no recheck afterwards. A worker in
;; %flow-perform-off-loop that passes the liveness check, polls
;; not-ready, and reaches flow-box-cons! AFTER the drain has run
;; registers into a dead scope's list. Nothing will ever resume it, so
;; flow-block-and-wait-off-loop blocks on its condition variable for
;; the life of the process.
;;
;; The concurrency is by design -- flow2.scm:314 says so explicitly:
;; "a compute-thread task parked on a channel registers its scope
;; waiter from its own thread". Only the recheck is missing. On the
;; main thread the same code happens to be safe because nothing yields
;; between the check and the registration, but nothing enforces that.
;;
;; The fix is two lines, and resume already CASes the shared state box,
;; so a double resume is harmless:
;;
;;   (define (%scope-add-waiter! scope state resume)
;;     (flow-box-cons! (flow-scope-waiters scope) (cons state resume))
;;     (when (%scope-dead? scope) (resume %flow-cancel-sentinel))
;;     ...)
;;
;; Why this needs a purpose-built reproducer. The window is roughly a
;; microsecond wide, and it only opens when the monitor's deadline
;; fires while the worker is between its liveness check and its cons.
;; A task that parks immediately after submission is never in that
;; window for a millisecond-scale deadline -- which is why
;; ~check-flow2-005/worker-cancelled-along-monitor passes, and why 5000
;; rounds of the obvious shape (submit, park, time out) never
;; reproduced it. Here the task first burns a fixed ~20k-iteration spin
;; so the moment it reaches flow-get! is a controllable offset from
;; submission, and the deadline is swept finely across that offset.
;;
;; Measured 2026-08-17: 0/3 runs survived on dev, 3/3 survived with the
;; two-line recheck applied.
;;
;; Run (does NOT hang -- the final wait is itself bounded by a monitor):
;;
;;   timeout 400 ./venv $(pwd)/local/ local/bin/letloop compile \
;;     ./src/ ./checks/ checks/repro-flow2-scope-waiter-race.scm \
;;     repro-flow2-scope-waiter-race && ./a.out
;;
;; Buggy build (current dev): "WORKER LOST: no reply in 2s".
;; Fixed build: "(worker alive)".
(library (repro-flow2-scope-waiter-race)
  (export repro-flow2-scope-waiter-race)
  (import (chezscheme) (letloop flow2))

  (define %rounds 6000)

  ;; Pure compute, no allocation, no channel op: a fixed amount of
  ;; wall-clock on the worker thread before it parks, so the deadline
  ;; sweep below can land inside the registration window.
  (define (spin n)
    (let loop ((i 0) (acc 0))
      (if (fx=? i n) acc (loop (fx+ i 1) (fx+ acc i)))))

  (define (say . args)
    (for-each display args)
    (newline)
    (flush-output-port (current-output-port)))

  (define (repro-flow2-scope-waiter-race)
    (flow-run
     (lambda (workers)
       (let ((worker (car workers)))

         (let round ((i 0))
           (when (fx<? i %rounds)
             (when (fxzero? (fxmod i 1000))
               (say "round " i))
             ;; Sweep the deadline across the spin's duration in 0.5us
             ;; steps. Each round submits a task that will park on a
             ;; channel nobody ever puts to, so only the scope's
             ;; cancellation can ever resume it.
             (guard (ex ((flow-error? ex) (void)))
               (flow-monitor
                (* 0.0000005 (random 2000))
                (lambda ()
                  (let ((up (make-flow-channel))
                        (down (make-flow-channel)))
                    (flow-submit! worker
                                  (lambda ()
                                    (spin 20000)
                                    (flow-get! down))
                                  up)
                    (flow-get! up)))))
             (round (fx+ i 1))))

         (say "survived " %rounds " rounds")

         ;; The whole point: after all that cancellation, is the worker
         ;; still serving? A lost worker would hang here forever, so
         ;; bound the wait and report it instead.
         (let ((response (make-flow-channel)))
           (flow-submit! worker
                         (lambda () (flow-put! response 'alive))
                         response)
           (guard (ex ((flow-error-timeout? ex)
                       (say "WORKER LOST: no reply in 2s")))
             (flow-monitor 2.0
                           (lambda ()
                             (say "(worker " (flow-get! response) ")")))))

         (flow-stop)))
     1)))

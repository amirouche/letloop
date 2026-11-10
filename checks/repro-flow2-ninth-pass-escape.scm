;; Ninth adverse pass, 2026-11-10: a flow-run left by something other
;; than a return or a raise. On its own because a failure leaves the
;; process unable to start another run.
;;
;;   letloop check ./src/ ./checks/ ./checks/repro-flow2-ninth-pass-escape.scm
(library (repro-flow2-ninth-pass-escape)
  (export ~check-repro/a-run-left-by-a-continuation-releases-the-loop)
  (import (chezscheme)
          (letloop flow2))

  ;; flow-run releases its claim on the loop from a guard, which sees a
  ;; raise and nothing else. A continuation captured outside the run and
  ;; invoked from a fiber leaves without one -- as does a REPL interrupt
  ;; that resets to the top level -- and the claim stays: every later
  ;; flow-run raises "a flow-run is already in progress", and this run's
  ;; compute threads are never joined.
  (define ~check-repro/a-run-left-by-a-continuation-releases-the-loop
    (lambda ()
      (define first
        (call/cc
         (lambda (k)
           (flow-run (lambda (workers) (k 'escaped)))
           'returned)))
      (define second
        (guard (ex (#t (if (condition? ex)
                           (call-with-string-output-port
                            (lambda (port) (display-condition ex port)))
                           ex)))
          (flow-run (lambda (workers) (flow-stop)))
          'ran))
      (flow-log-drain!)
      (format #t "first run: ~s; the next flow-run: ~s~%" first second)
      (eq? second 'ran))))

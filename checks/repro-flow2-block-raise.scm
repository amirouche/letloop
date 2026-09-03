;; Reproducer for the top finding of the 2026-08-17 adverse review of
;; (letloop flow2): a raise inside a base event's BLOCK procedure
;; escapes the fiber's guard entirely, so the nursery never learns the
;; child died and its join parks forever.
;;
;; Mechanism. flow-perform calls loop-abort BEFORE running any base's
;; block proc, so the (lambda (k) ...) that registers the bases runs on
;; the SCHEDULER's stack, after the prompt has been unwound. The guard
;; %scope-spawn! installs around the fiber body (flow2.scm:940) is no
;; longer in the dynamic extent. A raise there lands in loop-apply's
;; catch-all: the fiber dies, %scope-fail! never runs,
;; %scope-child-done! never decrements the scope's child count, and
;; %scope-finish parks on %scope-join-event with nothing left to wake
;; it. This is the "peers park forever, looking exactly like a lost
;; wakeup" signature the nursery was introduced to abolish.
;;
;; Not synthetic: two block procs in this tree raise on ordinary
;; conditions -- loop-get-sqe ("submission queue full", >256 ops queued
;; in one tick, reachable from flow-timeout / flow-read / flow-write /
;; flow-open / flow-read-at / flow-write-at) and loop-accept-block
;; ("concurrent accept on fd", see repro-flow2-accept-cancel.scm).
;;
;; The same shape is INHERITED from (letloop flow): flow-block-and-wait
;; -on-loop (flow.scm:303-347) is identical, and its own comment names
;; loop-get-sqe as a raise source -- then hardens only the CANCEL path
;; against it ("Split, the raise is confined to the cancel thunk ...
;; and k still runs"), leaving the registration for-each below it
;; exposed. Any fix belongs in BOTH libraries.
;;
;; Run (case C hangs on a buggy build -- always use timeout):
;;
;;   timeout 25 ./venv $(pwd)/local/ local/bin/letloop compile \
;;     ./src/ ./checks/ checks/repro-flow2-block-raise.scm \
;;     repro-flow2-block-raise && ./a.out
;;
;; Buggy build (current dev): A passes; B prints "fiber died" on stderr
;; and is rescued only by the enclosing monitor's deadline, which then
;; misreports the failure as a `timeout`; C prints "fiber died" and
;; HANGS -- "C returned" is never reached and the timeout kills it.
;;
;; Fixed build: all three print "-> nursery re-raised" and the program
;; reaches "C returned" and exits 0. The raise from the block proc must
;; reach the scope, exactly as the raise from the fiber body in case A
;; does.
(library (repro-flow2-block-raise)
  (export repro-flow2-block-raise)
  (import (chezscheme) (letloop flow2))

  (define (say . args)
    (for-each display args)
    (newline)
    (flush-output-port (current-output-port)))

  ;; An event that can never be ready, so flow-perform must call block
  ;; -- and whose block raises, the way loop-get-sqe and
  ;; loop-accept-block do.
  (define (bad-event)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume register-cancel!)
                 (error 'bad-event "raised from block"))))

  (define (repro-flow2-block-raise)
    (flow-run
     (lambda (workers)

       ;; Control: a raise from the fiber BODY is inside the guard
       ;; %scope-spawn! installs, so the nursery sees it and re-raises
       ;; at the join. This is the behaviour the two cases below are
       ;; measured against.
       (say "A: a raise from a fiber body is caught by the nursery")
       (guard (ex (#t (say "   -> nursery re-raised: " (condition? ex))))
         (flow-nursery
          (lambda (scope)
            (flow-spawn (lambda () (error 'body "boom"))))))

       ;; The same raise, one layer down, from the block proc. The
       ;; enclosing monitor eventually rescues the program -- but the
       ;; error it reports is its own `timeout`, not 'bad-event, so the
       ;; real cause is lost.
       (say "B: the same raise from an event's block proc")
       (guard (ex (#t (say "   -> nursery re-raised")))
         (flow-monitor
          1.0
          (lambda ()
            (flow-nursery
             (lambda (scope)
               (flow-spawn (lambda () (flow-perform (bad-event)))))))))
       (say "B returned")

       ;; With no enclosing deadline there is nothing to rescue it: the
       ;; scope's child count stays at 1 forever and the join never
       ;; completes.
       (say "C: same, in a plain nursery with no enclosing deadline")
       (guard (ex (#t (say "   -> nursery re-raised")))
         (flow-nursery
          (lambda (scope)
            (flow-spawn (lambda () (flow-perform (bad-event)))))))
       (say "C returned")

       (flow-stop)))))

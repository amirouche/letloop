;; What does a nursery cost per operation?
;;
;; Finding 17 of the 2026-08-17 adverse review of (letloop flow2): the
;; design says "every fiber belongs to a scope", and every perform
;; inside a cancellable scope carries one extra base event
;; (%scope-cancel-base). That extra base is not free -- a record plus
;; three closures, then flow-flatten's append, then flow-rotate's
;; append / list-tail / list-head and a (random n) in flow-poll, and on
;; the park path a cons, a CAS counter bump, and a whole-list filter
;; every 64 registrations.
;;
;; The review's point was not that this is slow, but that nobody had
;; measured it, while the one directly comparable measurement in this
;; repository is discouraging: ec70498 added a per-connection
;; flow-choice read timeout to the HTTP server and 05ab523 reverted it,
;; TODO.md line 60 recording "cost ~19% throughput to CML bookkeeping
;; overhead". A second base per operation is the same shape of change.
;; The README's claim that the ROOT-scope path is free is true and
;; beside the point, since the design tells you not to write that.
;;
;; Three configurations, so the extra base is the only thing that
;; varies:
;;
;;   root     fibers at the root scope       -- one base per perform
;;   nursery  the same fibers in a nursery   -- two bases per perform
;;   monitor  the same, under a deadline     -- two bases, plus a live
;;                                              ring timeout for the run
;;
;; and two workloads, because the extra base costs differently on each
;; path:
;;
;;   ping-pong  every operation parks (block path: cons, CAS, filter)
;;   drain      the consumer mostly finds a value already queued
;;              (poll path: flatten, rotate, random)
;;
;; Run (~30s):
;;
;;   ./venv $(pwd)/local/ local/bin/letloop compile --optimize-level=3 \
;;     ./src/ ./benchmarks/ benchmarks/flow2-nursery-bench.scm \
;;     flow2-nursery-bench
(library (flow2-nursery-bench)
  (export flow2-nursery-bench)
  (import (chezscheme) (letloop flow2))

  ;; The park path is ~800ns an operation and the poll path ~65ns, so
  ;; they need different counts to clear real-time's millisecond
  ;; granularity: at 200k the drain finished in 13ms, where a single
  ;; millisecond of noise is 8% of the answer.
  (define %park-iterations 200000)
  (define %poll-iterations 2000000)
  (define %trials 5)

  (define (say . args)
    (for-each display args)
    (newline)
    (flush-output-port (current-output-port)))

  ;; Best of N rather than mean: the loop shares a machine with
  ;; whatever else is running, so noise is one-sided -- it can only make
  ;; a run slower. The fastest trial is the closest to the cost being
  ;; measured.
  ;; A benchmark that does not check it did the work measures nothing.
  ;; The first draft of this file reported the monitor configuration as
  ;; 10x FASTER than root on the drain workload, which is impossible --
  ;; it was completing a fraction of the operations.
  (define (best-of trials expected thunk)
    (let loop ((i 0) (best #f))
      (if (fx=? i trials)
          best
          (let* ((outcome (thunk))
                 (done (car outcome))
                 (elapsed (cdr outcome)))
            (unless (eqv? done expected)
              (error 'flow2-nursery-bench
                     "workload did not complete its operations"
                     (list 'expected expected 'done done)))
            (loop (fx+ i 1)
                  (if (or (not best) (< elapsed best)) elapsed best))))))

  ;; Run BODY under the configuration named by MODE, with the SAME
  ;; fiber topology in all three so the scope is the only variable.
  ;;
  ;; That matters more than it looks. flow-monitor runs its thunk in a
  ;; spawned fiber (%scope-spawn!), while flow-nursery runs proc inline
  ;; via %call-with-scope. A first draft of this file called them
  ;; directly and measured the resulting difference in fiber topology --
  ;; which changes how often the two sides park -- rather than the cost
  ;; of the extra base. It reported nursery at +77% and monitor at +18%
  ;; for a change that adds exactly one base to each, which is what gave
  ;; it away.
  (define (under mode body)
    (case mode
      ((root)
       (let ((done (make-flow-channel 'done 1)))
         (flow-spawn (lambda () (body) (flow-put! done 'ok)))
         (flow-get! done)))
      ((nursery)
       (flow-nursery (lambda (scope) (flow-spawn (lambda () (body))))))
      ((monitor) (flow-monitor 60.0 body))
      (else (error 'under "unknown mode" mode))))

  ;; Every operation parks: the channels hold one value, so each side
  ;; alternates between a full put and an empty get.
  (define (ping-pong n mode)
    (let ((done 0)
          (start #f)
          (elapsed 0))
      (flow-run
       (lambda (workers)
         (let ((a (make-flow-channel 'ping 1))
               (b (make-flow-channel 'pong 1)))
         (under
          mode
          (lambda ()
            (flow-spawn
             (lambda ()
               (let loop ((i 0))
                 (when (fx<? i n)
                   (flow-put! a i)
                   (flow-get! b)
                   (loop (fx+ i 1))))))
              (set! start (real-time))
              (let loop ((i 0))
                (when (fx<? i n)
                  (flow-get! a)
                  (flow-put! b i)
                  (set! done (fx+ done 1))
                  (loop (fx+ i 1))))
              (set! elapsed (- (real-time) start)))))
         (flow-stop)))
      (cons done elapsed)))

  ;; Pure poll path: the channel is filled BEFORE the loop starts and
  ;; nothing produces during the run, so not one get registers and not
  ;; one parks. Running a live producer alongside instead makes the
  ;; result depend on how often the two sides happen to park, which is
  ;; scheduling noise and swamped the signal in the first draft.
  (define (drain n mode)
    (let ((done 0)
          (start #f)
          (elapsed 0)
          (ch (make-flow-channel 'drain #f)))   ;; unbounded: pre-fill
      (let fill ((i 0))
        (when (fx<? i n)
          (flow-put! ch i)
          (fill (fx+ i 1))))
      ;; Collect before the clock starts, so a major collection provoked
      ;; by the 200k-value pre-fill cannot land inside the measured
      ;; region of whichever mode happens to run first.
      (collect (collect-maximum-generation))
      (flow-run
       (lambda (workers)
         (under
          mode
          (lambda ()
            (set! start (real-time))
            (let loop ((i 0))
              (when (fx<? i n)
                (flow-get! ch)
                (set! done (fx+ done 1))
                (loop (fx+ i 1))))
            (set! elapsed (- (real-time) start))))
         (flow-stop)))
      (cons done elapsed)))

  (define (report label n baseline ms)
    (let ((ops-per-second (if (zero? ms) 0 (exact (round (/ (* n 1000.0) ms))))))
      (say "  " label
           "  " ms " ms"
           "  " ops-per-second " ops/s"
           (if baseline
               (string-append
                "   "
                (let ((delta (* 100.0 (/ (- ms baseline) baseline))))
                  (string-append (if (>= delta 0) "+" "")
                                 (number->string
                                  (/ (round (* 10 delta)) 10.0))
                                 "%")))
               "   (baseline)"))
      ms))

  (define (run-workload name workload n)
    (say "")
    (say name " -- " n " operations, best of " %trials)
    (let ((baseline (report "root    " n #f
                            (best-of %trials n (lambda () (workload n 'root))))))
      (report "nursery " n baseline
              (best-of %trials n (lambda () (workload n 'nursery))))
      (report "monitor " n baseline
              (best-of %trials n (lambda () (workload n 'monitor))))
      (void)))

  (define (flow2-nursery-bench)
    (say "flow2 nursery overhead -- finding 17")
    (say "the comparable prior measurement in this repo: a per-connection")
    (say "flow-choice read timeout cost ~19% throughput (TODO.md:60)")
    ;; warm-up, so the first measured trial is not paying for the first
    ;; touch of every code path
    (ping-pong 2000 'root)
    (drain 2000 'root)
    (run-workload "ping-pong -- every operation parks (block path)"
                  ping-pong %park-iterations)
    (run-workload "drain -- pre-filled, nothing parks (poll path)"
                  drain %poll-iterations)
    (say "")))

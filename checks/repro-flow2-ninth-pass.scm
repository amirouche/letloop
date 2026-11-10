;; Ninth adverse pass, 2026-11-10. Each check passes only when flow2
;; behaves as documented, and prints what it saw. Every wait that could
;; hang is raced against a timeout, so a hang is a reported failure.
;; Run against the tree before 86fe9c4 to see them fail; every one
;; passes since 47a94f3.
;;
;;   letloop check ./src/ ./checks/ ./checks/repro-flow2-ninth-pass.scm
;;
;; The flow-run escape lives in repro-flow2-ninth-pass-escape.scm: it
;; leaves the process unable to start another run.
(library (repro-flow2-ninth-pass)
  (export ~check-repro/a-parked-putter-is-woken-when-there-is-room
          ~check-repro/readme-fan-out-gather-at-two-thousand-fibers
          ~check-repro/workers-putting-once-each-all-get-through
          ~check-repro/read-pending-on-a-compute-thread-is-refused
          ~check-repro/timeouts-fire-in-deadline-order-under-churn
          ~check-repro/a-timeout-that-never-fires-can-be-written)
  (import (chezscheme)
          (letloop flow2))

  (define get-or-hung
    (lambda (ch seconds)
      (flow-perform
       (flow-choice (flow-get ch)
                    (flow-wrap (flow-timeout seconds) (lambda (_) 'hung))))))

  ;; N values are owed on CH; count them out, stopping at the first
  ;; get that waits SECONDS for nothing.
  (define gather
    (lambda (ch n seconds)
      (let loop ((n n) (out '()))
        (if (zero? n)
            out
            (let ((v (get-or-hung ch seconds)))
              (if (eq? v 'hung)
                  out
                  (loop (- n 1) (cons v out))))))))

  ;; A channel bounded at 1, three producers that put one value each,
  ;; one consumer. The first put queues, the other two park for room.
  ;; The consumer's first get dequeues and wakes ONE putter, then gets
  ;; again before that putter has run and parks as a getter. The woken
  ;; putter hands its value straight to the parked getter -- no dequeue,
  ;; so nobody wakes the third putter: it stays parked for room on a
  ;; channel that is EMPTY, beside a getter parked for a value.
  (define ~check-repro/a-parked-putter-is-woken-when-there-is-room
    (lambda ()
      (define got '())
      (define queue #f)
      (define space #f)
      (define getters #f)
      (flow-log-drain!)
      (flow-run
       (lambda (workers)
         (let ((ch (make-flow-channel 'one 1)))
           (do ((i 0 (+ i 1))) ((= i 3))
             (flow-spawn (lambda () (flow-put! ch i))))
           (flow-sleep 0.01)
           (set! got (gather ch 3 0.5))
           (set! queue (flow-channel-queue-length ch))
           (set! space (flow-channel-space-length ch))
           (set! getters (flow-channel-getters-length ch))
           (flow-stop))))
      (flow-log-drain!)
      (format #t "got ~a of 3; left behind: ~a queued, ~a putters parked for room~%"
              (length got) queue space)
      (fx=? (length got) 3)))

  ;; The README's "Fan out and gather, every fiber reporting its end",
  ;; as printed, on the default bound: "the default bound is fine: a
  ;; fetch that outruns the gatherer parks until it catches up."
  (define ~check-repro/readme-fan-out-gather-at-two-thousand-fibers
    (lambda ()
      (define n 2000)
      (define got 0)
      (define space #f)
      (define queue #f)
      (flow-log-drain!)
      (flow-run
       (lambda (workers)
         (let ((replies (make-flow-channel 'replies)))
           (do ((i 0 (+ i 1))) ((= i n))
             (flow-spawn
              (lambda ()
                (flow-put! replies
                           (guard (ex (#t (cons 'failed ex)))
                             (cons 'done i))))))
           (set! got (length (gather replies n 1.0)))
           (set! queue (flow-channel-queue-length replies))
           (set! space (flow-channel-space-length replies))
           (flow-stop))))
      (flow-log-drain!)
      (format #t "~a of ~a replies; left behind: ~a queued, ~a fibers parked in flow-put!~%"
              got n queue space)
      (fx=? got n)))

  ;; The same, with the puts coming from compute threads: each task puts
  ;; one value on a channel bounded at 1.
  (define ~check-repro/workers-putting-once-each-all-get-through
    (lambda ()
      (define rounds 200)
      (define count 4)
      (define short 0)
      (flow-log-drain!)
      (flow-run
       (lambda (workers)
         (let loop ((round 0))
           (when (fx<? round rounds)
             (let ((ch (make-flow-channel 'one 1)))
               (for-each (lambda (w) (flow-submit! w (lambda () (flow-put! ch round))))
                         workers)
               (flow-sleep 0.001)
               (unless (fx=? count (length (gather ch count 0.2)))
                 (set! short (fx+ short 1)))
               ;; unpark whoever is stuck, so the worker can take its next task
               (flow-channel-buffer-size! ch #f))
             (loop (fx+ round 1))))
         (flow-stop))
       count)
      (flow-log-drain!)
      (format #t "~a of ~a rounds came up short of ~a values~%" short rounds count)
      (fxzero? short)))

  ;; "Loop thread only" (flow-read-pending?), and "every flow2 operation
  ;; raises wrong-thread" from a thread that does not own it.
  (define ~check-repro/read-pending-on-a-compute-thread-is-refused
    (lambda ()
      (define saw #f)
      (flow-log-drain!)
      (flow-run
       (lambda (workers)
         (let ((out (make-flow-channel 'out)))
           (flow-submit! (car workers)
                         (lambda ()
                           (flow-put! out
                                      (guard (ex ((flow-error-wrong-thread? ex) 'wrong-thread)
                                                 (#t (list 'raised ex)))
                                        (list 'returned (flow-read-pending? 0))))))
           (set! saw (get-or-hung out 1.0))
           (flow-stop)))
       1)
      (flow-log-drain!)
      (format #t "flow-read-pending? on a compute thread: ~s~%" saw)
      (eq? saw 'wrong-thread)))

  (define now-ns
    (lambda ()
      (let ((t (current-time 'time-monotonic)))
        (+ (* (time-second t) 1000000000) (time-nanosecond t)))))

  ;; The heap, through the only door it has: many fibers, each racing
  ;; two timeouts so every perform is one fire and one removal from the
  ;; middle of the heap. No fiber may wake before its deadline, and
  ;; fibers must wake in deadline order (deadlines within 1 ms of each
  ;; other are not compared: one tick fires them together, and the
  ;; order fibers run in within a tick is unspecified).
  (define ~check-repro/timeouts-fire-in-deadline-order-under-churn
    (lambda ()
      (define fibers 300)
      (define woke '())                     ; (deadline . woke-at), newest first
      (define early 0)
      (define misordered 0)
      (flow-log-drain!)
      (flow-run
       (lambda (workers)
         (let ((done (make-flow-channel 'done #f)))
           (do ((i 0 (+ i 1))) ((= i fibers))
             (flow-spawn
              (lambda ()
                (let* ((a (/ (random 300) 1000.0))
                       (b (/ (random 300) 1000.0))
                       (armed (now-ns)))
                  (flow-perform (flow-choice (flow-timeout a) (flow-timeout b)))
                  (set! woke (cons (cons (+ armed (exact (round (* (min a b) 1e9))))
                                         (now-ns))
                                   woke))
                  (flow-put! done #t)))))
           (do ((i 0 (+ i 1))) ((= i fibers))
             (get-or-hung done 2.0))
           (flow-stop))))
      (flow-log-drain!)
      (let loop ((entries (reverse woke)) (latest 0))
        (unless (null? entries)
          (let ((deadline (caar entries)) (at (cdar entries)))
            (when (< at deadline) (set! early (+ early 1)))
            (when (< (+ deadline 3000000) latest) (set! misordered (+ misordered 1)))
            (loop (cdr entries) (max latest deadline)))))
      (format #t "~a of ~a fibers woke; ~a early, ~a out of deadline order~%"
              (length woke) fibers early misordered)
      (and (= (length woke) fibers) (zero? early) (zero? misordered))))

  ;; "SECONDS (a real number)". +inf.0 is a real, and the natural way to
  ;; say "no deadline" where a deadline is optional.
  (define ~check-repro/a-timeout-that-never-fires-can-be-written
    (lambda ()
      (define saw #f)
      (flow-log-drain!)
      (flow-run
       (lambda (workers)
         (let ((ch (make-flow-channel 'ch)))
           (flow-spawn (lambda () (flow-sleep 0.01) (flow-put! ch 'value)))
           (set! saw
             (guard (ex (#t (list 'raised
                                  (if (condition? ex)
                                      (call-with-string-output-port
                                       (lambda (port) (display-condition ex port)))
                                      ex))))
               (flow-perform (flow-choice (flow-get ch) (flow-timeout +inf.0)))))
           (flow-stop))))
      (flow-log-drain!)
      (format #t "(flow-choice (flow-get ch) (flow-timeout +inf.0)) => ~s~%" saw)
      (eq? saw 'value))))

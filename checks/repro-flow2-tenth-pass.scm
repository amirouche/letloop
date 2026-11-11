;; Tenth adverse pass, 2026-11-11. Each check passes only when flow2
;; behaves as documented, and prints what it saw. Every wait that could
;; hang is raced against a timeout, so a hang is a reported failure.
;; Three of the four failed on 990c10b; every one passes since a4b197d.
;; The first wants 8400 file descriptors (ulimit -n).
;;
;;   letloop check ./src/ ./checks/ ./checks/repro-flow2-tenth-pass.scm
(library (repro-flow2-tenth-pass)
  (export ~check-repro/more-readers-than-ring-buffers-all-get-their-bytes
          ~check-repro/a-full-put-after-flow-stop-does-not-raise
          ~check-repro/values-crossing-threads-arrive-exactly-once
          ~check-repro/a-perform-outside-a-run-says-so)
  (import (chezscheme)
          (letloop flow2))

  (define socketpair
    (foreign-procedure "socketpair" (int int int u8*) int))

  (define c-write
    (foreign-procedure "write" (int u8* size_t) ssize_t))

  (define c-close
    (foreign-procedure "close" (int) int))

  ;; (A . B), a connected AF_UNIX stream pair.
  (define make-pair
    (lambda ()
      (let ((fds (make-bytevector 8 0)))
        (unless (zero? (socketpair 1 1 0 fds))
          (error 'make-pair "socketpair failed"))
        (cons (bytevector-s32-native-ref fds 0)
              (bytevector-s32-native-ref fds 4)))))

  (define get-or-hung
    (lambda (ch seconds)
      (flow-perform
       (flow-choice (flow-get ch)
                    (flow-wrap (flow-timeout seconds) (lambda (_) 'hung))))))

  ;; N fibers each park in flow-read on a socket of their own, and one
  ;; byte then arrives on every socket before the loop next drains its
  ;; completions -- what a tick that ran long looks like to a server
  ;; holding N connections. Every reader is owed its byte. The ring
  ;; lends recv 4096 buffers, so past that many the kernel answers
  ;; -ENOBUFS, and flow-read reports it as a failed connection.
  (define ~check-repro/more-readers-than-ring-buffers-all-get-their-bytes
    (lambda ()
      (let ((n 4200) (bytes 0) (failed 0) (eof 0) (hung 0))
        (flow-run
         (lambda (_)
           (let ((results (make-flow-channel 'results #f))
                 (pairs (let loop ((i 0) (out '()))
                          (if (fx=? i n)
                              out
                              (loop (fx+ i 1) (cons (make-pair) out))))))
             (for-each
              (lambda (pair)
                (flow-spawn
                 (lambda ()
                   (flow-put! results (flow-perform (flow-read (car pair)))))))
              pairs)
             ;; every recv is in the ring
             (flow-sleep 0.5)
             ;; plain syscalls, so no tick runs between the first byte
             ;; and the last
             (for-each (lambda (pair) (c-write (cdr pair) (bytevector 120) 1))
                       pairs)
             (let loop ((i 0))
               (when (fx<? i n)
                 (let ((v (get-or-hung results 5)))
                   (cond
                    ((bytevector? v) (set! bytes (fx+ bytes 1)) (loop (fx+ i 1)))
                    ((eq? v #f) (set! failed (fx+ failed 1)) (loop (fx+ i 1)))
                    ((eq? v #t) (set! eof (fx+ eof 1)) (loop (fx+ i 1)))
                    (else (set! hung (fx- n i)))))))
             (for-each (lambda (pair) (c-close (car pair)) (c-close (cdr pair)))
                       pairs)
             (flow-stop))))
        (format #t "   readers ~a: bytes ~a, failed ~a, eof ~a, hung ~a\n"
                n bytes failed eof hung)
        (assert (fx=? bytes n))
        #t)))

  ;; Two fibers runnable in the same tick: one stops the run, the other
  ;; puts on a full channel. The put is inside a run and on the loop
  ;; thread; the README gives overflow to a put OUTSIDE a run only, so
  ;; this one parks and is never resumed.
  (define ~check-repro/a-full-put-after-flow-stop-does-not-raise
    (lambda ()
      (let ((seen 'nothing))
        (flow-run
         (lambda (_)
           (let ((ch (make-flow-channel 'full 1)))
             (flow-put! ch 'a)
             ;; spawned first, so it runs second
             (flow-spawn
              (lambda ()
                (guard (ex (#t (set! seen (if (flow-error? ex)
                                              (flow-error-symbol ex)
                                              ex))))
                  (flow-put! ch 'b)
                  (set! seen 'returned))))
             (flow-spawn (lambda () (flow-stop))))))
        (format #t "   the put after flow-stop: ~s\n" seen)
        (assert (eq? seen 'nothing))
        #t)))

  ;; N values go fibers -> IN -> two compute threads -> MID -> two
  ;; compute threads -> OUT -> fibers, over channels bounded at 1, 2
  ;; and 3, with the consuming fibers racing every get against a
  ;; timeout short enough to lose often. Each value is owed to exactly
  ;; one consumer.
  (define ~check-repro/values-crossing-threads-arrive-exactly-once
    (lambda ()
      (let* ((n 40000)
             (seen (make-vector n 0))
             (count 0)
             (timeouts 0)
             (outcome 'unfinished))
        (flow-run
         (lambda (workers)
           (let ((in (make-flow-channel 'in 1))
                 (mid (make-flow-channel 'mid 2))
                 (out (make-flow-channel 'out 3)))
             (define forward
               (lambda (from to)
                 (lambda ()
                   (let loop ()
                     (let ((v (flow-get! from)))
                       (flow-put! to v)
                       (unless (eq? v 'end) (loop)))))))
             (flow-submit! (list-ref workers 0) (forward in mid))
             (flow-submit! (list-ref workers 1) (forward in mid))
             (flow-submit! (list-ref workers 2) (forward mid out))
             (flow-submit! (list-ref workers 3) (forward mid out))
             (do ((p 0 (fx+ p 1))) ((fx=? p 4))
               (flow-spawn
                (lambda ()
                  (do ((i p (fx+ i 4))) ((fx>=? i n))
                    (flow-put! in i)))))
             (do ((c 0 (fx+ c 1))) ((fx=? c 3))
               (flow-spawn
                (lambda ()
                  (let loop ()
                    (when (fx<? count n)
                      (let ((v (flow-perform
                                (flow-choice
                                 (flow-get out)
                                 (flow-wrap
                                  (flow-timeout (vector-ref '#(0 0.00001 0.0002)
                                                            (random 3)))
                                  (lambda (_) 'timeout))))))
                        (cond
                         ((eq? v 'timeout) (set! timeouts (fx+ timeouts 1)))
                         ((fixnum? v)
                          (vector-set! seen v (fx+ 1 (vector-ref seen v)))
                          (set! count (fx+ count 1))
                          (when (fx=? count n)
                            (set! outcome 'complete)
                            ;; let the compute threads leave their tasks
                            (flow-put! in 'end)
                            (flow-put! in 'end)
                            (flow-spawn
                             (lambda ()
                               (get-or-hung out 2)
                               (get-or-hung out 2)
                               (flow-stop)))))))
                      (loop))))))
             (flow-spawn
              (lambda ()
                (flow-sleep 60)
                (set! outcome 'hung)
                (flow-stop)))))
         4)
        (let ((missing 0) (twice 0))
          (vector-for-each
           (lambda (k)
             (cond ((fxzero? k) (set! missing (fx+ missing 1)))
                   ((fx>? k 1) (set! twice (fx+ twice 1)))))
           seen)
          (format #t "   ~a: ~a of ~a, missing ~a, twice ~a, lost gets ~a\n"
                  outcome count n missing twice timeouts)
          (assert (eq? outcome 'complete))
          (assert (fxzero? missing))
          (assert (fxzero? twice)))
        #t)))

  ;; A get on an empty channel with no run in progress has nothing to
  ;; park on. A put in the same position raises overflow and says why;
  ;; this prints what the get does, and what it leaves on the channel.
  (define ~check-repro/a-perform-outside-a-run-says-so
    (lambda ()
      (let* ((ch (make-flow-channel 'outside))
             (said (guard (ex (#t (cond
                                   ((flow-error? ex) (flow-error-message ex))
                                   ((condition? ex)
                                    (call-with-string-output-port
                                     (lambda (port) (display-condition ex port))))
                                   (else ex))))
                     (flow-get! ch)
                     'returned)))
        (format #t "   a get outside a run: ~s, getters left ~a\n"
                said (flow-channel-getters-length ch))
        (assert (and (string? said)
                     (not (string=? said "Exception: attempt to apply non-procedure #f"))))
        (assert (fxzero? (flow-channel-getters-length ch)))
        #t))))

;; Reproducers for the 2026-08-24 adverse review of (letloop flow2),
;; the third pass, run against dev @ ad661dc. Written as a library of
;; ~check- procedures so they can be run with
;;
;;   letloop check ./src/ ./checks/ ./checks/repro-flow2-third-pass.scm
;;
;; and each one PASSES only when the library behaves as documented --
;; so a run against the unfixed tree is a list of the findings.
;;
;; Finding 1 (close in a dead scope leaks the fd) is fixed; its
;; regression check now lives in flow2.check.scm as
;; ~check-flow2-009/close-in-a-dead-scope-still-closes, and the version
;; here is kept as the original standalone reproduction. Findings 2
;; (the README fan-out pattern hangs past the default bound) and 3 (a
;; flow-read that loses a same-tick race drops received bytes) are
;; still open.
(library (repro flow2)
  (export ~check-repro/close-in-dead-scope-leaks-fd
          ~check-repro/fan-out-pattern-hangs-past-bound
          ~check-repro/fan-out-pattern-ok-under-bound
          ~check-repro/read-losing-same-tick-drops-bytes)
  (import (chezscheme)
          (letloop flow2)
          (letloop liburing low))

  (define %fcntl (foreign-procedure "fcntl" (int int) int))
  (define (fd-open? fd) (fx>=? (%fcntl fd 1) 0)) ; F_GETFD

  ;; 1. A child parked on a timeout is cancelled by a sibling's raise;
  ;;    its explicit cleanup performs flow-close inside the now-dead
  ;;    scope. README: "callers close fds explicitly on ... the error
  ;;    path, and cancellation arriving as a raised cancelled error ...
  ;;    is what makes that explicit cleanup reachable."
  (define (~check-repro/close-in-dead-scope-leaks-fd)
    (define path "/tmp/letloop/repro-close-dead-scope.bin")
    (define fd #f)
    (define close-outcome 'never-ran)
    (define still-open 'unknown)
    (flow-run
     (lambda (workers)
       (guard (ex (#t (void)))
         (flow-nursery
          (lambda (scope)
            (flow-spawn
             (lambda ()
               (set! fd (flow-perform (flow-open path (fxior O-WRONLY O-CREAT O-TRUNC) #o600)))
               (guard (ex ((flow-error-cancelled? ex)
                           ;; the cleanup the README says is reachable
                           (set! close-outcome
                             (guard (ex2 (#t (list 'close-raised (and (flow-error? ex2) (flow-error-symbol ex2)))))
                               (flow-perform (flow-close fd))))
                           (raise ex)))
                 (flow-sleep 10))))
            (flow-spawn (lambda () (flow-sleep 0.05) (raise 'boom))))))
       ;; give a close, had one been issued, a few ticks to land
       (flow-sleep 0.1)
       (set! still-open (fd-open? fd))
       (flow-stop)))
    (when (file-exists? path) (delete-file path))
    (display (list 'close-outcome close-outcome 'fd-still-open still-open)) (newline)
    ;; passes only if the fd was actually released
    (not still-open))

  ;; 2. The README's "Fan out, gather, and never hang" pattern, verbatim
  ;;    shape, with more items than the default bound of 43. The gather
  ;;    loop runs AFTER the join; the 44th put parks on space; the join
  ;;    waits for that fiber. Wrapped in a monitor so the check terminates.
  (define (query-ngrams ngrams)
    (define replies (make-flow-channel))
    (flow-nursery
     (lambda (scope)
       (for-each (lambda (ngram)
                   (flow-spawn
                    (lambda ()
                      (flow-put! replies ngram))))
                 ngrams)))
    (let loop ((out '()))
      (let ((r (flow-get-try replies #f)))
        (if r (loop (cons r out)) out))))

  (define (run-fan-out n)
    (define outcome #f)
    (flow-run
     (lambda (workers)
       (set! outcome
         (guard (ex ((flow-error? ex) (list 'error (flow-error-symbol ex))))
           (list 'ok (length (flow-monitor 1.0 (lambda () (query-ngrams (iota n))))))))
       (flow-stop)))
    (display (list 'fan-out n outcome)) (newline)
    outcome)

  (define (~check-repro/fan-out-pattern-ok-under-bound)
    (equal? (run-fan-out 40) '(ok 40)))

  (define (~check-repro/fan-out-pattern-hangs-past-bound)
    (equal? (run-fan-out 50) '(ok 50)))

  ;; 3. Server parks on (choice (read client) (timeout 0.05)). The client
  ;;    fiber never yields between t=0 and t=100ms; at t=70ms it pushes
  ;;    bytes with a blocking write(2), so the kernel completes the recv
  ;;    AFTER the timeout but before the loop drains. Drain order is CQ
  ;;    order: the timeout's handler wins the CAS, the recv's handler
  ;;    takes the buffer and resume returns #f. Then a fresh read on the
  ;;    same fd, raced against a generous timeout, should see the bytes.
  (define %write2 (foreign-procedure "write" (int u8* size_t) ssize_t))
  (define (spin-until ms)
    (let spin () (when (< (real-time) ms) (spin))))

  (define (~check-repro/read-losing-same-tick-drops-bytes)
    (define PORT 18299)
    (define first-race #f)
    (define second-read #f)
    (define payload (string->utf8 "payload"))
    (flow-run
     (lambda (workers)
       (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
         (loop-bind listen-fd "127.0.0.1" PORT)
         (loop-listen listen-fd 128)
         (flow-spawn
          (lambda ()
            (let ((client (flow-perform (flow-accept listen-fd))))
              (set! first-race
                (flow-perform (flow-choice
                               (flow-wrap (flow-read client) (lambda (x) (list 'read x)))
                               (flow-wrap (flow-timeout 0.05) (lambda (_) 'timeout)))))
              (set! second-read
                (flow-perform (flow-choice
                               (flow-wrap (flow-read client) (lambda (x) (list 'read x)))
                               (flow-wrap (flow-timeout 0.5) (lambda (_) 'timeout)))))
              (loop-close client)
              (loop-close listen-fd)
              (flow-stop))))
         (flow-spawn
          (lambda ()
            (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
              (lambda (addr addrlen)
                (let ((fd (loop-connect addr addrlen)))
                  (foreign-free addr)
                  ;; let the server park on its choice first
                  (flow-sleep 0.01)
                  (let ((t0 (real-time)))
                    (spin-until (+ t0 70))
                    (%write2 fd payload (bytevector-length payload))
                    (spin-until (+ t0 100)))
                  ;; keep the socket alive until the server is done
                  (flow-sleep 1.0)
                  (loop-close fd)))))))))
    (display (list 'first first-race 'second second-read)) (newline)
    ;; expected by the README's fd-stays-usable story: the second read
    ;; delivers the payload
    (equal? second-read (list 'read payload))))

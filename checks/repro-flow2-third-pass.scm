;; Reproducers for the 2026-08-24 adverse review of (letloop flow2),
;; the third pass, run against dev @ ad661dc. Written as a library of
;; ~check- procedures so they can be run with
;;
;;   letloop check ./src/ ./checks/ ./checks/repro-flow2-third-pass.scm
;;
;; and each one PASSES only when the library behaves as documented --
;; so a run against the tree as it was on 2026-08-24 is a list of the
;; findings.
;;
;; ALL THREE ARE NOW FIXED, and each has a regression check in
;; flow2.check.scm -- ~check-flow2-009/close-in-a-dead-scope-still-
;; closes, ~check-flow2-003/gather-after-join-scales-past-the-default-
;; bound, and ~check-flow2-006/read-losing-a-same-tick-race-keeps-its-
;; bytes. What is kept here is the original reproduction of each, in the
;; shape it was first written, because the shape is the argument.
;;
;; Findings 1 and 2 -- a close in a dead scope, and the fan-out
;; pattern's gather after a nursery's join -- were about nurseries, and
;; their reproducers went with them; only finding 3 is kept.
(library (repro-flow2-third-pass)
  (export ~check-repro/read-losing-same-tick-drops-bytes)
  (import (chezscheme)
          (letloop flow2)
          (letloop liburing low))

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

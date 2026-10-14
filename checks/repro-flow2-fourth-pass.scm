;; Reproducers for the 2026-08-27 adverse review of (letloop flow2),
;; the fourth pass, run against dev @ 097d6a1. Written as a library of
;; ~check- procedures so they can be run with
;;
;;   letloop check ./src/ ./checks/ ./checks/repro-flow2-fourth-pass.scm
;;
;; and each one PASSES only when the library behaves as documented --
;; so a run against the tree as it was on 2026-08-27 is a list of the
;; findings.
;;
;; ALL ARE NOW FIXED. Findings 1 and 2 have regression checks in
;; flow2.check.scm (~check-flow2-005/every-entry-point-refuses-a-stray-
;; thread and ~check-flow2-009/a-closed-fd-does-not-hand-on-a-stash);
;; finding 5 extended ~check-flow2-001/a-raising-cancel-does-not-skip-
;; the-others. What is kept here is the original reproduction of each,
;; in the shape it was first written, because the shape is the
;; argument.
;;
;; Findings 3 and 4 were README examples that contradicted their own
;; reference sections, and the two checks for them are the point the
;; third pass already made and this pass had to make again: an example
;; that is not executed somewhere is a claim, not a specification. Both
;; run the page's code as the page now prints it.
(library (repro-flow2-fourth-pass)
  (export ~check-repro/get-from-a-stray-thread-succeeds
          ~check-repro/closed-fd-hands-on-a-stash
          ~check-repro/readme-index-file-example-terminates
          ~check-repro/readme-gather-keeps-a-false-reply
          ~check-repro/cancel-log-names-nothing)
  (import (chezscheme)
          (letloop flow2)
          (letloop liburing low))

  ;; 1. The third pass's own fix, applied at three call sites instead
  ;;    of at the choke point they pass through. README: "flow-put!,
  ;;    flow-get-try and flow-spawn therefore raise wrong-thread when
  ;;    called from one" -- an enumeration, and flow-perform was not on
  ;;    it, so flow-get! from a thread the user forked took the ON-loop
  ;;    branch. On a NON-EMPTY channel it did not raise at all: it
  ;;    dequeued off-loop and "resumed" the parked putter through a
  ;;    loop-spawn with no eventfd wake. The putter was still parked
  ;;    1.5s later.
  (define (~check-repro/get-from-a-stray-thread-succeeds)
    (define channel (make-flow-channel 'stocked 1))
    (define outcome 'not-set)
    (define putter 'parked)
    (define done (box #f))
    (flow-run
     (lambda (workers)
       ;; fill it, then park a second put behind the bound
       (flow-put! channel 'first)
       (flow-spawn
        (lambda ()
          (flow-put! channel 'second)
          (set! putter 'resumed)))
       (flow-spawn
        (lambda ()
          (flow-sleep 0.05)
          (fork-thread
           (lambda ()
             (set! outcome
                   (guard (ex (#t (if (flow-error? ex)
                                      (flow-error-symbol ex)
                                      'not-a-flow-error)))
                     (list 'got (flow-get! channel))))
             (set-box! done #t)))
          (let wait ((n 0))
            (flow-sleep 0.01)
            (if (or (unbox done) (fx>? n 150))
                (flow-stop)
                (wait (fx+ n 1))))))))
    ;; the finding: `(got first)` and putter still 'parked
    (assert (eq? 'wrong-thread outcome))
    (assert (eq? 'parked putter))
    #t)

  ;; 2. loop-close-prep! purges the fd's recv stash because "leaving
  ;;    them keyed by a number the kernel is about to reissue is how a
  ;;    stash becomes a cross-connection data leak". flow2's recv was
  ;;    not in the per-fd operation index, so the close could not tear
  ;;    its handler down, and a recv that completed with data after the
  ;;    purge put the payload back -- under a dead fd number.
  ;;
  ;;    The write is aimed at the window between the cancel submit and
  ;;    the kernel acting on it, not guaranteed to land in it, so this
  ;;    reproduces sometimes and never fails spuriously.
  (define %write2
    (foreign-procedure "write" (int u8* size_t) ssize_t))

  (define (spin-until ms)
    (let loop () (when (< (real-time) ms) (loop))))

  (define (~check-repro/closed-fd-hands-on-a-stash)
    (define PORT 18261)
    (define payload (string->utf8 "previous-connection"))
    (define stash 'not-set)
    (flow-run
     (lambda (workers)
       (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
         (loop-bind listen-fd "127.0.0.1" PORT)
         (loop-listen listen-fd 128)
         (flow-spawn
          (lambda ()
            (let ((client (flow-perform (flow-accept listen-fd))))
              (flow-perform
               (flow-choice
                (flow-wrap (flow-read client) (lambda (x) (list 'read x)))
                (flow-wrap (flow-timeout 0.05) (lambda (x) 'timeout))))
              (loop-close client)
              (flow-sleep 0.3)
              (set! stash (loop-recv-backlog-take! client)))
            (loop-close listen-fd)
            (flow-stop)))
         (flow-spawn
          (lambda ()
            (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
              (lambda (addr addrlen)
                (let ((fd (loop-connect addr addrlen)))
                  (foreign-free addr)
                  (flow-sleep 0.01)
                  (let ((t0 (real-time)))
                    (spin-until (+ t0 52))
                    (%write2 fd payload (bytevector-length payload)))
                  (flow-sleep 1.0)
                  (loop-close fd)))))))))
    ;; the finding: the previous connection's bytes, waiting for
    ;; whoever gets that fd number next
    (assert (not stash))
    #t)

  ;; 3. The README's "Do I/O from a compute thread" example, run. Its
  ;;    `(if chunk ...)` predated the 'eof -> #t change for
  ;;    flow-read-at, so a clean EOF was truthy: the task looped
  ;;    forever feeding #t to index-chunk and never sent `done`.
  ;;    Executed here with the monitor that turns that into something
  ;;    visible.
  (define (~check-repro/readme-index-file-example-terminates)
    (define path "/tmp/letloop/repro-flow2-fourth-index.bin")
    (define size 200000)
    (define bytes (make-bytevector size 7))
    (define result 'not-set)
    (let ((port (open-file-output-port path (file-options no-fail))))
      (put-bytevector port bytes)
      (close-port port))
    (flow-run
     (lambda (workers)
       (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
         (set! result
               (guard (ex ((flow-error-timeout? ex) 'never-terminated))
                 (flow-monitor 5.0
                   (lambda ()
                     (let ((up (make-flow-channel 'up))
                           (down (make-flow-channel 'down)))
                       (flow-submit!
                        (car workers)
                        (lambda ()
                          ;; the page's compute side, verbatim in shape
                          (let loop ((offset 0) (total 0))
                            (flow-put! up (list 'read-at offset 65536))
                            (let ((chunk (flow-get! down)))
                              (cond
                               ((bytevector? chunk)
                                (loop (+ offset 65536)
                                      (+ total (bytevector-length chunk))))
                               ((eq? chunk #t) (flow-put! up (list 'done total)))
                               (else (flow-put! up (list 'failed offset)))))))
                        up)
                       ;; the page's main side
                       (let serve ()
                         (let ((msg (flow-get! up)))
                           (cond
                            ((flow-error? msg) (raise msg))
                            (else
                             (case (car msg)
                               ((read-at)
                                (flow-spawn
                                 (lambda ()
                                   (flow-put! down
                                              (flow-perform
                                               (flow-read-at fd
                                                             (cadr msg)
                                                             (caddr msg))))))
                                (serve))
                               ((done) (cadr msg))
                               ((failed)
                                (list 'failed (cadr msg))))))))))))) 
         (flow-perform (flow-close fd))
         (flow-stop)))
     1)
    (delete-file path)
    ;; the finding: 'never-terminated
    (assert (eqv? size result))
    #t)

  ;; 4. The README's fan-out gather, run with a fetch that legitimately
  ;;    returns #f. The gather used #f as both the empty sentinel and a
  ;;    legal value, so it stopped at the first false reply and dropped
  ;;    every reply queued behind it.
  (define (~check-repro/readme-gather-keeps-a-false-reply)
    (define ngrams '(a b c d e f g h))
    (define out 'not-set)
    ;; the third of eight has no result, and says so with #f
    (define (fetch-ngram ngram) (if (eq? ngram 'c) #f ngram))
    (flow-run
     (lambda (workers)
       (let ((replies (make-flow-channel 'replies (length ngrams))))
         (flow-nursery
          (lambda (scope)
            (for-each (lambda (ngram)
                        (flow-spawn
                         (lambda () (flow-put! replies (fetch-ngram ngram)))))
                      ngrams)))
         (set! out
               (let loop ((n (length ngrams)) (acc '()))
                 (if (zero? n)
                     acc
                     (loop (- n 1) (cons (flow-get-try replies #f) acc)))))
         (flow-stop))))
    ;; the finding: fewer than eight, whatever happened to be queued
    ;; ahead of the #f
    (assert (eqv? (length ngrams) (length out)))
    (assert (memq 'h out))
    #t)

  ;; 5. A losing base's cancel that raises is invisible by design --
  ;;    the rest of the batch still runs -- so the log line is the only
  ;;    trace, and the README sends operators to it after an
  ;;    unexplained hang or fd leak. It said (flow2 cancel-raised) and
  ;;    nothing else.
  (define (~check-repro/cancel-log-names-nothing)
    (define (never-ready-with-cancel thunk)
      (make-flow (lambda (x) x)
                 (lambda () #f)
                 (lambda (state resume register-cancel!)
                   (register-cancel! thunk))))
    (define entries '())
    (flow-run
     (lambda (workers)
       (flow-perform
        (flow-choice
         (never-ready-with-cancel
          (lambda () (error 'repro-flow2-fourth "the cancel raised")))
         (flow-wrap (flow-timeout 0.02) (lambda (x) 'timeout))))
       (flow-sleep 0.05)
       (set! entries (flow-log-drain!))
       (flow-stop)))
    ;; the finding: (TIMESTAMP flow2 cancel-raised), length 3
    (let ((line (let find ((entries entries))
                  (cond
                   ((null? entries) #f)
                   ((eq? 'cancel-raised (caddr (car entries))) (car entries))
                   (else (find (cdr entries)))))))
      (assert line)
      (assert (fx>? (length line) 3))
      (assert (string? (list-ref line 4))))
    #t))

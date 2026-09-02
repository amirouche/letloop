;; Checks for (letloop tea loop), driving the module through its exported
;; API the way a caller would.  Included at the tail of the library;
;; discovered by `make check` via the ~check- exports.


  ;; ----- pipe-pair helper -------------------------------------------------
  ;;
  ;; We don't have a real tty, so the loop is exercised over a pipe.  The
  ;; reader side is fed by a separate write(2) call from the test driver.

  ;; Best-effort, and it matters more here than it looks: this file is
  ;; `include`d into (letloop tea loop), so its body runs whenever that
  ;; library is instantiated -- not only when a check runs. Unguarded,
  ;; it takes down anything reaching tea on a statically linked build,
  ;; where there is no loader to service the dlopen. `letloop review`
  ;; died on exactly this. pipe2 is registered by letloop-main.c there,
  ;; so the foreign-procedure below resolves without it.
  (define libc (guard (ex (#t #f)) (load-shared-object "libc.so.6")))
  (define c-pipe2 (foreign-procedure "pipe2" (void* int) int))

  (define (make-pipe)
    (let ((fds (foreign-alloc 8)))
      (let ((r (c-pipe2 fds 0)))
        (when (fx<? r 0) (error 'make-pipe "pipe2 failed")))
      (let ((rd (foreign-ref 'int fds 0))
            (wr (foreign-ref 'int fds 4)))
        (foreign-free fds)
        (values rd wr))))

  (define (write-bytes fd byte-list)
    (let* ((n   (length byte-list))
           (buf (foreign-alloc n)))
      (let loop ((i 0) (bs byte-list))
        (cond
         ((null? bs) #t)
         (else
          (foreign-set! 'unsigned-8 buf i (car bs))
          (loop (fx+ i 1) (cdr bs)))))
      (write-fd fd buf n)
      (foreign-free buf)))

  ;; Drive the loop until at least one event is queued (or one round elapses
  ;; without producing one — we cap iterations to avoid wedging the test).
  (define (drive-until-event! l)
    (let loop ((rounds 0))
      (let ((e (tea-loop-pop-event! l)))
        (cond
         (e e)
         ((fx>? rounds 20) #f)
         (else
          (tea-loop-run-once! l 200)
          (loop (fx+ rounds 1)))))))

  (define (~check-loop-pipe-arrow-key)
    (check-skip-unless liburing-ffi "io_uring_queue_init"
    (let-values (((rd wr) (make-pipe)))
      (let* ((parser (make-input-parser xterm-caps))
             (l      (make-tea-loop rd parser)))
        (write-bytes wr (bytevector->u8-list (string->utf8 "\x1b;[A")))
        (let ((e (drive-until-event! l)))
          (close-fd wr)
          (tea-loop-shutdown! l)
          (close-fd rd)
          (and (key-event? e)
               (eq? (key-event-key e) 'arrow-up)))))))

  (define (~check-loop-pipe-multibyte-utf8)
    (check-skip-unless liburing-ffi "io_uring_queue_init"
    (let-values (((rd wr) (make-pipe)))
      (let* ((parser (make-input-parser xterm-caps))
             (l      (make-tea-loop rd parser)))
        ;; Send two bytes of "é" (U+00E9 = 0xC3 0xA9) in two separate
        ;; writes — proves the parser holds state across iouring read
        ;; boundaries.
        (write-bytes wr '(#xC3))
        (tea-loop-run-once! l 200)
        (write-bytes wr '(#xA9))
        (let ((e (drive-until-event! l)))
          (close-fd wr)
          (tea-loop-shutdown! l)
          (close-fd rd)
          (and (key-event? e)
               (= (key-event-ch e) #xE9)))))))

  (define (~check-loop-pipe-esc-flush)
    ;; Send a lone ESC; the loop's 50ms timer should fire and yield esc.
    (check-skip-unless liburing-ffi "io_uring_queue_init"
    (let-values (((rd wr) (make-pipe)))
      (let* ((parser (make-input-parser xterm-caps))
             (l      (make-tea-loop rd parser)))
        (write-bytes wr '(#x1B))
        ;; Drive for up to 5 rounds — the timeout is 50ms, so 5x200ms is
        ;; plenty.
        (let ((e (drive-until-event! l)))
          (close-fd wr)
          (tea-loop-shutdown! l)
          (close-fd rd)
          (and (key-event? e)
               (eq? (key-event-key e) 'esc)))))))

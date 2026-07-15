#!chezscheme
;; (letloop tea loop) — io_uring-driven event source for a tea instance.
;;
;; Owns an io_uring ring, a read buffer, multishot poll SQEs on the tty fd
;; and the signalfd, and an ESC-flush timeout SQE.  Drains CQEs and pushes
;; events into a FIFO that the public tea-poll/tea-events surface drains.
;;
;; Tag scheme: each SQE's user_data is (op | (gen << 8)) — operation in the
;; low 8 bits, monotonic generation counter in the high bits, so we can
;; cancel a specific in-flight timeout by remembering its full 64-bit tag.
;;
;; Stage 3 deliberately keeps the API simple: callers see tea-poll /
;; tea-events / tea-on-event in tea.scm; this module only exposes the
;; primitives that surface needs.
(library (letloop tea loop)
  (export
   make-tea-loop
   tea-loop?
   tea-loop-shutdown!
   tea-loop-pop-event!
   tea-loop-run-once!
   ;; resize signalling — the public renderer hooks into this so it can
   ;; cellbuf-resize! when the kernel says the geometry changed
   tea-loop-resize-pending?
   tea-loop-clear-resize-pending!

   ~check-loop-pipe-arrow-key
   ~check-loop-pipe-multibyte-utf8
   ~check-loop-pipe-esc-flush)
  (import (chezscheme)
          ;; strerror, POLLIN, O-NONBLOCK also come from (letloop tea
          ;; syscall); keep the tea bindings.
          (except (letloop liburing low) strerror POLLIN O-NONBLOCK)
          (letloop tea syscall)
          (letloop tea input)
          ;; xterm-caps, for the pipe-driven checks
          (letloop tea caps))

  (define-ftype <ts>
    (struct (sec long-long) (nsec long-long)))

  ;; ----- tags --------------------------------------------------------------

  (define OP-TTY-POLL    1)
  (define OP-SIGFD-POLL  2)
  (define OP-TTY-READ    3)
  (define OP-SIGFD-READ  4)
  (define OP-ESC-TIMEOUT 5)

  (define (op-of tag) (fxand tag #xFF))

  ;; ----- read buffer + signalfd siginfo -----------------------------------

  (define READ-BUFFER-SIZE 4096)
  (define SIGFD-INFO-SIZE  128)

  ;; ----- record ------------------------------------------------------------

  (define-record-type tea-loop
    (fields ring
            cqe-ptr
            tty-fd
            sigfd
            read-buf            ; foreign pointer
            sigfd-buf           ; foreign pointer
            (mutable parser)
            (mutable events)    ; list, head = next event to pop
            (mutable events-tail)
            (mutable next-gen)
            (mutable esc-timeout-tag)  ; full user_data of the in-flight timeout, or #f
            (mutable resize-pending?)
            (mutable timeout-ts))      ; foreign-allocated kernel-timespec
    (protocol
     (lambda (new)
       (lambda (tty-fd parser)
         (let* ((ring  (make-io-uring))
                (rc    (io-uring-queue-init 64 ring 0))
                (cqep  (make-cqe-pointer))
                (sfd   (sigwinch-fd-open))
                (buf   (foreign-alloc READ-BUFFER-SIZE))
                (sbuf  (foreign-alloc SIGFD-INFO-SIZE))
                (ts    (foreign-alloc (ftype-sizeof <ts>)))
                (instance
                 (new ring cqep tty-fd sfd buf sbuf parser
                      '() '() 1 #f #f ts)))
           (unless (fx=? rc 0)
             (error 'make-tea-loop "io_uring_queue_init failed" rc))
           (submit-tty-poll! instance)
           (submit-sigfd-poll! instance)
           instance)))))

  ;; ----- tag management ---------------------------------------------------

  (define (next-tag! l op)
    (let* ((g (tea-loop-next-gen l))
           (tag (fxior op (fxsll g 8))))
      (tea-loop-next-gen-set! l (fx+ g 1))
      tag))

  ;; ----- SQE submission ---------------------------------------------------

  (define (submit-tty-poll! l)
    (let ((sqe (io-uring-get-sqe (tea-loop-ring l)))
          (tag (next-tag! l OP-TTY-POLL)))
      (io-uring-prep-poll-multishot sqe (tea-loop-tty-fd l) POLLIN)
      (io-uring-sqe-set-data64 sqe tag)
      (io-uring-submit (tea-loop-ring l))))

  (define (submit-sigfd-poll! l)
    (let ((sqe (io-uring-get-sqe (tea-loop-ring l)))
          (tag (next-tag! l OP-SIGFD-POLL)))
      (io-uring-prep-poll-multishot sqe (tea-loop-sigfd l) POLLIN)
      (io-uring-sqe-set-data64 sqe tag)
      (io-uring-submit (tea-loop-ring l))))

  (define (submit-tty-read! l)
    (let ((sqe (io-uring-get-sqe (tea-loop-ring l)))
          (tag (next-tag! l OP-TTY-READ)))
      (io-uring-prep-read sqe (tea-loop-tty-fd l)
                          (tea-loop-read-buf l) READ-BUFFER-SIZE 0)
      (io-uring-sqe-set-data64 sqe tag)
      (io-uring-submit (tea-loop-ring l))))

  (define (submit-sigfd-read! l)
    (let ((sqe (io-uring-get-sqe (tea-loop-ring l)))
          (tag (next-tag! l OP-SIGFD-READ)))
      (io-uring-prep-read sqe (tea-loop-sigfd l)
                          (tea-loop-sigfd-buf l) SIGFD-INFO-SIZE 0)
      (io-uring-sqe-set-data64 sqe tag)
      (io-uring-submit (tea-loop-ring l))))

  (define ESC-FLUSH-MS 50)

  (define (submit-esc-timeout! l)
    ;; Schedule a 50ms one-shot timeout.  If a continuation byte arrives
    ;; before it fires, cancel-esc-timeout! kills it.
    (let* ((ring (tea-loop-ring l))
           (sqe  (io-uring-get-sqe ring))
           (tag  (next-tag! l OP-ESC-TIMEOUT))
           (raw  (tea-loop-timeout-ts l))
           (ts   (make-ftype-pointer <ts> raw)))
      (ftype-set! <ts> (sec)  ts 0)
      (ftype-set! <ts> (nsec) ts (fx* ESC-FLUSH-MS 1000000))
      (io-uring-prep-timeout sqe raw 0 0)
      (io-uring-sqe-set-data64 sqe tag)
      (tea-loop-esc-timeout-tag-set! l tag)
      (io-uring-submit ring)))

  (define (cancel-esc-timeout! l)
    (let ((tag (tea-loop-esc-timeout-tag l)))
      (when tag
        (let ((sqe (io-uring-get-sqe (tea-loop-ring l))))
          (io-uring-prep-cancel64 sqe tag 0)
          ;; cancel SQE doesn't need its own user_data; use 0
          (io-uring-sqe-set-data64 sqe 0)
          (io-uring-submit (tea-loop-ring l))
          (tea-loop-esc-timeout-tag-set! l #f)))))

  ;; ----- event queue ------------------------------------------------------

  (define (push-event! l e)
    (let ((cell (cons e '())))
      (cond
       ((null? (tea-loop-events l))
        (tea-loop-events-set! l cell)
        (tea-loop-events-tail-set! l cell))
       (else
        (set-cdr! (tea-loop-events-tail l) cell)
        (tea-loop-events-tail-set! l cell)))))

  (define (tea-loop-pop-event! l)
    (cond
     ((null? (tea-loop-events l)) #f)
     (else
      (let ((e (car (tea-loop-events l))))
        (tea-loop-events-set! l (cdr (tea-loop-events l)))
        (when (null? (tea-loop-events l))
          (tea-loop-events-tail-set! l '()))
        e))))

  ;; ----- read buffer drain ------------------------------------------------

  (define (drain-read! l n)
    ;; Feed n bytes from read-buf through the parser; queue any events.
    (let ((parser (tea-loop-parser l))
          (buf    (tea-loop-read-buf l)))
      (let loop ((i 0))
        (when (fx<? i n)
          (let* ((b (foreign-ref 'unsigned-8 buf i))
                 (e (input-parser-feed! parser b)))
            (when e (push-event! l e)))
          (loop (fx+ i 1))))))

  ;; ----- CQE dispatch -----------------------------------------------------

  (define (dispatch-cqe! l cqe)
    (let* ((tag (io-uring-cqe-get-data64 cqe))
           (op  (op-of tag))
           (res (io-uring-cqe-get-res cqe))
           (parser (tea-loop-parser l)))
      (cond
       ((fx=? op OP-TTY-POLL)
        ;; tty has data ready; submit a read.  Multishot keeps polling.
        (when (fx>=? res 0) (submit-tty-read! l)))
       ((fx=? op OP-SIGFD-POLL)
        (when (fx>=? res 0) (submit-sigfd-read! l)))
       ((fx=? op OP-TTY-READ)
        (cond
         ((fx>? res 0)
          ;; Bytes arrived — first cancel any pending ESC-flush timer.
          (cancel-esc-timeout! l)
          (drain-read! l res)
          ;; If parser is still in 'esc state with no continuation in this
          ;; chunk, schedule a fresh timeout.
          (when (eq? (input-parser-state parser) 'esc)
            (submit-esc-timeout! l)))
         ;; res <= 0 → EOF or error; don't resubmit, the multishot poll
         ;; will fire again on the next event if the fd becomes ready.
         ))
       ((fx=? op OP-SIGFD-READ)
        (when (fx>? res 0)
          (tea-loop-resize-pending?-set! l #t)
          ;; queue a synthetic resize-event marker so tea-poll wakes up
          (push-event! l 'resize-event)))
       ((fx=? op OP-ESC-TIMEOUT)
        ;; Result is -ETIME on natural fire, -ECANCELED if we cancelled it.
        (let ((current (tea-loop-esc-timeout-tag l)))
          (cond
           ((fx=? tag (if current current -1))
            ;; this is the in-flight timeout — flush ESC
            (tea-loop-esc-timeout-tag-set! l #f)
            (let ((e (input-parser-flush! parser)))
              (when e (push-event! l e))))
           ;; else: stale timeout (already cancelled) — ignore
           )))
       (else
        ;; unknown tag — ignore
        #f))))

  ;; ----- public driver ----------------------------------------------------

  (define (tea-loop-run-once! l timeout-ms)
    ;; Wait for at least one CQE, then drain everything available.  Returns
    ;; the number of events produced by this round.
    (let ((ring    (tea-loop-ring l))
          (cqe-ptr (tea-loop-cqe-ptr l))
          (start-len (length (tea-loop-events l))))
      (cond
       (timeout-ms
        (let* ((raw (foreign-alloc (ftype-sizeof <ts>)))
               (ts  (make-ftype-pointer <ts> raw)))
          (ftype-set! <ts> (sec)  ts (fxdiv timeout-ms 1000))
          (ftype-set! <ts> (nsec) ts (fx* (fxmod timeout-ms 1000) 1000000))
          ;; the wrapper takes the ftype pointer, not the raw address
          (io-uring-wait-cqe-timeout ring cqe-ptr ts)
          (foreign-free raw)))
       (else
        (io-uring-wait-cqe ring cqe-ptr)))
      ;; drain everything available without blocking
      (let drain ()
        (when (fxzero? (io-uring-peek-cqe ring cqe-ptr))
          (let ((cqe (foreign-ref 'void* cqe-ptr 0)))
            (dispatch-cqe! l cqe)
            (io-uring-cqe-seen ring cqe)
            (drain))))
      (fx- (length (tea-loop-events l)) start-len)))

  ;; ----- resize plumbing --------------------------------------------------
  ;; tea.scm checks resize-pending? after each run-once! and calls tea-resize
  ;; if set, then clears the flag.

  (define (tea-loop-clear-resize-pending! l)
    (tea-loop-resize-pending?-set! l #f))

  ;; ----- shutdown ---------------------------------------------------------

  (define (tea-loop-shutdown! l)
    (io-uring-queue-exit (tea-loop-ring l))
    (foreign-free (tea-loop-ring     l))
    (foreign-free (tea-loop-cqe-ptr  l))
    (foreign-free (tea-loop-read-buf l))
    (foreign-free (tea-loop-sigfd-buf l))
    (foreign-free (tea-loop-timeout-ts l))
    (close-fd (tea-loop-sigfd l)))
  

  (include "letloop/tea/loop.check.scm")
  )

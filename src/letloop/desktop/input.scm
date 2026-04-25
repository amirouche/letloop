;; M2.3 chunk E-3: keyboard event pump.
;;
;; The render loop calls pump-keyboard-events! once per frame. It
;; drains every pending struct input_event off the (non-blocking)
;; evdev fd and dispatches each EV_KEY to the supplied callback as
;;
;;   (callback key-code value)
;;
;; where key-code is one of the KEY_* constants from
;; (letloop desktop evdev) and value is one of
;; KEY_VALUE_PRESS / KEY_VALUE_REPEAT / KEY_VALUE_RELEASE.
;;
;; Non-EV_KEY events (EV_SYN frame markers, EV_LED echoes from the
;; kernel) are read off the fd but ignored.
;;
;; PLAN.md targets an io_uring multishot read for this hot path. We
;; ship the simpler libc-read variant first because:
;;   - one frame's worth of keyboard events fits in a handful of
;;     read() syscalls at most
;;   - the sandbox has no /dev/input/, so the io_uring path can't be
;;     verified here either; a perf-driven io_uring rewrite belongs
;;     in a follow-up that's actually run on hardware.
(library (letloop desktop input)
  (export
   open-keyboard
   close-keyboard
   pump-keyboard-events!
   process-input-bytevector!
   ;; io_uring variant — same handler contract, lower per-event syscall
   ;; cost. Same /dev/input fd shape, so callers swap one for the other
   ;; without changing the rest of the line-editor wiring.
   uring-keyboard?
   open-keyboard-uring
   close-keyboard-uring!
   pump-keyboard-events-uring!)
  (import
   (chezscheme)
   (letloop desktop evdev)
   (letloop liburing low))

  (define (open-keyboard path) (open-evdev path))
  (define (close-keyboard fd)  (close-evdev fd))

  ;; Read every pending event off `fd` and dispatch the EV_KEY ones.
  ;; Non-blocking semantics inherit from open-evdev's O_NONBLOCK flag,
  ;; so the loop terminates as soon as the kernel's queue is empty
  ;; (read returns a negative value, parsed as #f by read-input-event).
  (define (pump-keyboard-events! fd handler)
    (let loop ()
      (let ((ev (read-input-event fd)))
        (cond
         ((not ev) (void))
         (else
          (when (= (input-event-type ev) EV_KEY)
            (handler (input-event-code ev)
                     (input-event-value ev)))
          (loop))))))

  ;; Sandbox-testable variant: parse a bytevector of N consecutive
  ;; struct input_event records and dispatch the EV_KEY ones via the
  ;; same handler signature. The byte length must be a multiple of
  ;; input-event-size.
  (define (process-input-bytevector! bv handler)
    (let ((len (bytevector-length bv)))
      (unless (zero? (remainder len input-event-size))
        (error 'process-input-bytevector!
               "byte length not a multiple of input-event-size"
               len input-event-size))
      (let loop ((off 0))
        (when (< off len)
          (let ((ev (parse-input-event bv off)))
            (when (= (input-event-type ev) EV_KEY)
              (handler (input-event-code ev)
                       (input-event-value ev))))
          (loop (+ off input-event-size))))))

  ;; ----------------------------------------------------------------
  ;; io_uring variant
  ;; ----------------------------------------------------------------
  ;;
  ;; Submits a single 24-byte read on the evdev fd and uses
  ;; io_uring_peek_cqe to drain whatever's ready each frame, then
  ;; re-submits. On a typical typing rate this still issues one
  ;; submission queue entry per event — the win over libc-read is
  ;; the absence of EAGAIN syscalls when the queue is empty (peek-cqe
  ;; is a userspace memory load).
  ;;
  ;; PLAN.md mentions multishot reads (kernel ≥6.0) — that needs
  ;; io_uring_prep_read_multishot, not exported by (letloop liburing
  ;; low). Adding that binding is straightforward but unverifiable
  ;; from the sandbox; we ship the single-shot variant first.

  (define-record-type uring-keyboard
    (fields fd ring buf cqe-out (mutable submitted?)))

  (define (open-keyboard-uring path)
    (let* ((fd      (open-evdev path))
           (ring    (foreign-alloc/zero (io-uring-size)))
           (buf     (foreign-alloc input-event-size))
           (cqe-out (foreign-alloc 8))
           (rc      (io-uring-queue-init 8 ring 0)))
      (when (negative? rc)
        (foreign-free cqe-out)
        (foreign-free buf)
        (foreign-free ring)
        (close-evdev fd)
        (error 'open-keyboard-uring "io_uring_queue_init failed" rc))
      (let ((rk (make-uring-keyboard fd ring buf cqe-out #f)))
        (submit-read! rk)
        rk)))

  (define (foreign-alloc/zero n)
    (let ((p (foreign-alloc n)))
      (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i 0))
      p))

  (define (submit-read! rk)
    (let ((sqe (io-uring-get-sqe (uring-keyboard-ring rk))))
      (cond
       ((zero? sqe)
        ;; Submission queue full — drop. Next pump will retry after
        ;; consuming the existing CQE.
        (uring-keyboard-submitted?-set! rk #f))
       (else
        (io-uring-prep-read sqe
                            (uring-keyboard-fd rk)
                            (uring-keyboard-buf rk)
                            input-event-size 0)
        (io-uring-submit (uring-keyboard-ring rk))
        (uring-keyboard-submitted?-set! rk #t)))))

  (define (close-keyboard-uring! rk)
    (io-uring-queue-exit (uring-keyboard-ring rk))
    (foreign-free (uring-keyboard-cqe-out rk))
    (foreign-free (uring-keyboard-buf rk))
    (foreign-free (uring-keyboard-ring rk))
    (close-evdev (uring-keyboard-fd rk)))

  (define (pump-keyboard-events-uring! rk handler)
    (unless (uring-keyboard-submitted? rk) (submit-read! rk))
    (let loop ()
      (let ((rc (io-uring-peek-cqe (uring-keyboard-ring rk)
                                   (uring-keyboard-cqe-out rk))))
        (cond
         ((not (zero? rc)) (void))      ; nothing ready
         (else
          (let* ((cqe (foreign-ref 'uptr (uring-keyboard-cqe-out rk) 0))
                 (res (io-uring-cqe-get-res cqe)))
            (when (= res input-event-size)
              ;; Parse the single input_event out of buf.
              (let ((bv (make-bytevector input-event-size)))
                (do ((i 0 (+ i 1))) ((= i input-event-size))
                  (bytevector-u8-set!
                   bv i (foreign-ref 'unsigned-8
                                     (uring-keyboard-buf rk) i)))
                (let ((ev (parse-input-event bv 0)))
                  (when (= (input-event-type ev) EV_KEY)
                    (handler (input-event-code ev)
                             (input-event-value ev))))))
            (io-uring-cqe-seen (uring-keyboard-ring rk) cqe)
            (uring-keyboard-submitted?-set! rk #f)
            (submit-read! rk)
            (loop))))))))

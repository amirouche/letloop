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
   process-input-bytevector!)
  (import
   (chezscheme)
   (letloop desktop evdev))

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
          (loop (+ off input-event-size)))))))

#!chezscheme
;; M2.3 chunk E-1: evdev parser + low-level open/read.
;;
;; The Linux input subsystem hands out one struct input_event at a
;; time on /dev/input/event* file descriptors. On 64-bit Linux ≥5.6
;; the layout is:
;;
;;   struct input_event {
;;     struct timeval time;   // tv_sec : long (8B), tv_usec : long (8B)
;;     __u16 type;            // 2 bytes
;;     __u16 code;            // 2 bytes
;;     __s32 value;           // 4 bytes
;;   };  // 24 bytes total on x86_64
;;
;; This module covers parsing one such record out of a bytevector +
;; a thin synchronous read wrapper over the libc syscall. The
;; io_uring multishot loop lives in (letloop desktop input).
(library (letloop desktop evdev)
  (export
   ;; sizes / offsets
   input-event-size

   ;; bytevector parsing
   parse-input-event
   input-event-time-sec
   input-event-time-usec
   input-event-type
   input-event-code
   input-event-value

   ;; event type constants
   EV_SYN
   EV_KEY
   EV_REL
   EV_ABS
   EV_MSC
   EV_LED
   EV_REP

   ;; key-event values
   KEY_VALUE_RELEASE
   KEY_VALUE_PRESS
   KEY_VALUE_REPEAT

   ;; selected key codes (US QWERTY common)
   KEY_ESC KEY_1 KEY_2 KEY_3 KEY_4 KEY_5 KEY_6 KEY_7 KEY_8 KEY_9 KEY_0
   KEY_MINUS KEY_EQUAL KEY_BACKSPACE KEY_TAB
   KEY_Q KEY_W KEY_E KEY_R KEY_T KEY_Y KEY_U KEY_I KEY_O KEY_P
   KEY_LEFTBRACE KEY_RIGHTBRACE KEY_ENTER
   KEY_LEFTCTRL KEY_RIGHTCTRL
   KEY_A KEY_S KEY_D KEY_F KEY_G KEY_H KEY_J KEY_K KEY_L
   KEY_SEMICOLON KEY_APOSTROPHE KEY_GRAVE KEY_LEFTSHIFT KEY_RIGHTSHIFT
   KEY_BACKSLASH KEY_Z KEY_X KEY_C KEY_V KEY_B KEY_N KEY_M
   KEY_COMMA KEY_DOT KEY_SLASH
   KEY_LEFTALT KEY_RIGHTALT KEY_SPACE KEY_CAPSLOCK
   KEY_F1 KEY_F2 KEY_F3 KEY_F4 KEY_F5 KEY_F6 KEY_F7 KEY_F8 KEY_F9 KEY_F10
   KEY_F11 KEY_F12

   ;; syscall wrappers
   open-evdev
   close-evdev
   read-input-event)
  (import (chezscheme))

  ;; ----------------------------------------------------------------
  ;; Constants
  ;; ----------------------------------------------------------------

  (define input-event-size 24)

  (define EV_SYN 0)
  (define EV_KEY 1)
  (define EV_REL 2)
  (define EV_ABS 3)
  (define EV_MSC 4)
  (define EV_LED #x11)
  (define EV_REP #x14)

  (define KEY_VALUE_RELEASE 0)
  (define KEY_VALUE_PRESS   1)
  (define KEY_VALUE_REPEAT  2)

  ;; Subset of <linux/input-event-codes.h> — enough for an ASCII REPL.
  (define KEY_ESC 1)
  (define KEY_1 2)
  (define KEY_2 3)
  (define KEY_3 4)
  (define KEY_4 5)
  (define KEY_5 6)
  (define KEY_6 7)
  (define KEY_7 8)
  (define KEY_8 9)
  (define KEY_9 10)
  (define KEY_0 11)
  (define KEY_MINUS 12)
  (define KEY_EQUAL 13)
  (define KEY_BACKSPACE 14)
  (define KEY_TAB 15)
  (define KEY_Q 16)
  (define KEY_W 17)
  (define KEY_E 18)
  (define KEY_R 19)
  (define KEY_T 20)
  (define KEY_Y 21)
  (define KEY_U 22)
  (define KEY_I 23)
  (define KEY_O 24)
  (define KEY_P 25)
  (define KEY_LEFTBRACE 26)
  (define KEY_RIGHTBRACE 27)
  (define KEY_ENTER 28)
  (define KEY_LEFTCTRL 29)
  (define KEY_A 30)
  (define KEY_S 31)
  (define KEY_D 32)
  (define KEY_F 33)
  (define KEY_G 34)
  (define KEY_H 35)
  (define KEY_J 36)
  (define KEY_K 37)
  (define KEY_L 38)
  (define KEY_SEMICOLON 39)
  (define KEY_APOSTROPHE 40)
  (define KEY_GRAVE 41)
  (define KEY_LEFTSHIFT 42)
  (define KEY_BACKSLASH 43)
  (define KEY_Z 44)
  (define KEY_X 45)
  (define KEY_C 46)
  (define KEY_V 47)
  (define KEY_B 48)
  (define KEY_N 49)
  (define KEY_M 50)
  (define KEY_COMMA 51)
  (define KEY_DOT 52)
  (define KEY_SLASH 53)
  (define KEY_RIGHTSHIFT 54)
  (define KEY_LEFTALT 56)
  (define KEY_SPACE 57)
  (define KEY_CAPSLOCK 58)
  (define KEY_F1 59)
  (define KEY_F2 60)
  (define KEY_F3 61)
  (define KEY_F4 62)
  (define KEY_F5 63)
  (define KEY_F6 64)
  (define KEY_F7 65)
  (define KEY_F8 66)
  (define KEY_F9 67)
  (define KEY_F10 68)
  (define KEY_RIGHTCTRL 97)
  (define KEY_RIGHTALT 100)
  (define KEY_F11 87)
  (define KEY_F12 88)

  ;; ----------------------------------------------------------------
  ;; Bytevector parsing — pure, sandbox-testable.
  ;; ----------------------------------------------------------------

  (define (u16-le bv off)
    (bitwise-ior
     (bytevector-u8-ref bv off)
     (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 1)) 8)))

  (define (s32-le bv off)
    (let ((u (bitwise-ior
              (bytevector-u8-ref bv off)
              (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 1))  8)
              (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 2)) 16)
              (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 3)) 24))))
      (if (>= u #x80000000) (- u #x100000000) u)))

  (define (s64-le bv off)
    (let ((u (let loop ((i 0) (acc 0))
               (if (= i 8)
                   acc
                   (loop (+ i 1)
                         (bitwise-ior
                          acc
                          (bitwise-arithmetic-shift-left
                           (bytevector-u8-ref bv (+ off i))
                           (* i 8))))))))
      (if (>= u #x8000000000000000) (- u #x10000000000000000) u)))

  ;; Returns a list of 5 elements: (sec usec type code value).
  ;; Errors if the bytevector slice is shorter than input-event-size.
  (define (parse-input-event bv offset)
    (when (< (bytevector-length bv) (+ offset input-event-size))
      (error 'parse-input-event
             "bytevector slice too short for one input_event"
             (bytevector-length bv) offset))
    (list
     (s64-le bv offset)
     (s64-le bv (+ offset 8))
     (u16-le bv (+ offset 16))
     (u16-le bv (+ offset 18))
     (s32-le bv (+ offset 20))))

  (define (input-event-time-sec  ev) (list-ref ev 0))
  (define (input-event-time-usec ev) (list-ref ev 1))
  (define (input-event-type      ev) (list-ref ev 2))
  (define (input-event-code      ev) (list-ref ev 3))
  (define (input-event-value     ev) (list-ref ev 4))

  ;; ----------------------------------------------------------------
  ;; Synchronous syscall wrappers
  ;; ----------------------------------------------------------------
  ;;
  ;; We use the libc `open` / `close` / `read` so we can short-circuit
  ;; the io_uring path when we just want to grab a few events
  ;; (debugging, fallback when liburing is unavailable). The hot path
  ;; in (letloop desktop input) uses io_uring instead.

  (define O_RDONLY   #o000)
  (define O_NONBLOCK #o4000)
  (define O_CLOEXEC  #o2000000)

  (define stdlib (load-shared-object #f))

  (define libc-open
    (foreign-procedure "open" (string int int) int))
  (define libc-close
    (foreign-procedure "close" (int) int))
  (define libc-read
    (foreign-procedure "read" (int uptr unsigned-long) ssize_t))

  (define (open-evdev path)
    (let ((fd (libc-open path
                         (bitwise-ior O_RDONLY O_NONBLOCK O_CLOEXEC) 0)))
      (when (negative? fd)
        (error 'open-evdev "failed to open" path))
      fd))

  (define (close-evdev fd)
    (libc-close fd))

  ;; Read up to one event, returning either a parsed event or #f if
  ;; the FD is non-blocking and no data is available. Errors raise.
  (define (read-input-event fd)
    (let* ((buf (foreign-alloc input-event-size))
           (out (foreign-alloc input-event-size)))
      (dynamic-wind
       void
       (lambda ()
         (let ((n (libc-read fd buf input-event-size)))
           (cond
            ((= n input-event-size)
             (let ((bv (make-bytevector input-event-size)))
               (do ((i 0 (+ i 1))) ((= i input-event-size))
                 (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 buf i)))
               (parse-input-event bv 0)))
            ((negative? n) #f)         ; EAGAIN on non-blocking FD
            (else
             (error 'read-input-event "short read" n)))))
       (lambda ()
         (foreign-free out)
         (foreign-free buf))))))

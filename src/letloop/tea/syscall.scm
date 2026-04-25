#!chezscheme
;; (letloop tea syscall) — minimal libc bindings used by the Scheme port of
;; termbox2.  Linux x86_64 only.  All other tea modules avoid foreign-procedure
;; and route through this layer so the FFI surface stays auditable.
(library (letloop tea syscall)
  (export
   ;; tty
   isatty?
   open-tty
   close-fd
   read-fd
   write-fd
   ;; termios / raw mode
   make-termios
   tcgetattr
   tcsetattr
   cfmakeraw!
   ;; window size
   make-winsize  winsize-rows  winsize-cols
   ioctl-winsize
   ;; signalfd-based SIGWINCH delivery
   sigwinch-fd-open
   sigwinch-fd-drain
   ;; constants
   O-RDWR  O-NOCTTY  O-CLOEXEC  O-NONBLOCK
   TCSAFLUSH
   POLLIN
   ;; errno
   errno strerror)
  (import (chezscheme))

  ;; ----- shared object -----------------------------------------------------

  (define libc (load-shared-object "libc.so.6"))

  ;; ----- constants (linux x86_64) ------------------------------------------

  (define O-RDWR       2)
  (define O-NOCTTY     #o400)        ; 256
  (define O-CLOEXEC    #o2000000)    ; 524288
  (define O-NONBLOCK   #o4000)       ; 2048
  (define TCSAFLUSH    2)
  (define TIOCGWINSZ   #x5413)
  (define SIGWINCH     28)
  (define SIG-BLOCK    0)
  (define SFD-CLOEXEC  O-CLOEXEC)
  (define SFD-NONBLOCK O-NONBLOCK)
  (define POLLIN       1)
  (define NCCS         32)
  (define SIGSET-SIZE  128)          ; sizeof(sigset_t) under glibc

  ;; ----- errno -------------------------------------------------------------

  (define (errno) (#%$errno))

  (define strerror
    (let ((f (foreign-procedure "strerror" (int) string)))
      (lambda (e) (f e))))

  (define-syntax check
    (syntax-rules ()
      ((_ who expr)
       (let ((r expr))
         (if (fx<? r 0)
             (error 'who (strerror (errno)))
             r)))))

  ;; ----- tty open/close/io -------------------------------------------------

  (define c-isatty (foreign-procedure "isatty" (int) int))
  (define c-open   (foreign-procedure "open"   (string int) int))
  (define c-close  (foreign-procedure "close"  (int) int))
  (define c-read   (foreign-procedure "read"   (int void* size_t) ssize_t))
  (define c-write  (foreign-procedure "write"  (int void* size_t) ssize_t))

  (define (isatty? fd) (fx=? (c-isatty fd) 1))

  (define (open-tty path)
    ;; O_NOCTTY so we don't accidentally claim a controlling terminal.
    (let ((fd (c-open path (fxior O-RDWR O-NOCTTY O-CLOEXEC))))
      (if (fx<? fd 0)
          (error 'open-tty (strerror (errno)))
          fd)))

  (define (close-fd fd) (check close-fd (c-close fd)))

  (define (read-fd fd ptr n)
    ;; Returns bytes read (>=0) or -errno.  Caller decides what to do with
    ;; EINTR / EAGAIN.
    (let ((r (c-read fd ptr n)))
      (if (< r 0) (- 0 (errno)) r)))

  (define (write-fd fd ptr n)
    (let ((r (c-write fd ptr n)))
      (if (< r 0) (- 0 (errno)) r)))

  ;; ----- termios -----------------------------------------------------------
  ;;
  ;; struct termios layout under glibc:
  ;;   tcflag_t c_iflag, c_oflag, c_cflag, c_lflag;  (4 x 4 bytes)
  ;;   cc_t     c_line;                              (1 byte)
  ;;   cc_t     c_cc[NCCS=32];                       (32 bytes)
  ;;   speed_t  c_ispeed, c_ospeed;                  (2 x 4 bytes, padded)
  ;; total ~60 bytes; we over-allocate to 128 for safety across libc revs.

  (define TERMIOS-SIZE 128)

  (define c-tcgetattr (foreign-procedure "tcgetattr" (int void*)      int))
  (define c-tcsetattr (foreign-procedure "tcsetattr" (int int  void*) int))
  (define c-cfmakeraw (foreign-procedure "cfmakeraw" (void*)          void))

  (define (make-termios) (foreign-alloc TERMIOS-SIZE))

  (define (tcgetattr fd t) (check tcgetattr (c-tcgetattr fd t)))
  (define (tcsetattr fd actions t) (check tcsetattr (c-tcsetattr fd actions t)))
  (define (cfmakeraw! t) (c-cfmakeraw t))

  ;; ----- ioctl(TIOCGWINSZ) -------------------------------------------------

  (define-ftype <winsize>
    (struct
     (rows   unsigned-16)
     (cols   unsigned-16)
     (xpixel unsigned-16)
     (ypixel unsigned-16)))

  (define (make-winsize)
    (make-ftype-pointer <winsize>
                        (foreign-alloc (ftype-sizeof <winsize>))))

  (define (winsize-rows ws) (ftype-ref <winsize> (rows) ws))
  (define (winsize-cols ws) (ftype-ref <winsize> (cols) ws))

  ;; ioctl is variadic; we declare a 3-arg form taking a void*.
  (define c-ioctl
    (foreign-procedure "ioctl" (int unsigned-long void*) int))

  (define (ioctl-winsize fd ws)
    (check ioctl-winsize
           (c-ioctl fd TIOCGWINSZ (ftype-pointer-address ws))))

  ;; ----- signalfd(SIGWINCH) ------------------------------------------------
  ;;
  ;; We mask SIGWINCH process-wide and consume it via a signalfd, which is
  ;; just a regular fd ready for io_uring polling.  No C trampoline, no
  ;; signal-handler async-safety concerns.

  (define c-sigemptyset (foreign-procedure "sigemptyset" (void*)         int))
  (define c-sigaddset   (foreign-procedure "sigaddset"   (void* int)     int))
  (define c-sigprocmask (foreign-procedure "sigprocmask" (int void* void*) int))
  (define c-signalfd    (foreign-procedure "signalfd"    (int void* int) int))

  (define (sigwinch-fd-open)
    (let ((mask (foreign-alloc SIGSET-SIZE)))
      (check sigwinch-fd-open (c-sigemptyset mask))
      (check sigwinch-fd-open (c-sigaddset   mask SIGWINCH))
      (check sigwinch-fd-open (c-sigprocmask SIG-BLOCK mask 0))
      (let ((fd (c-signalfd -1 mask (fxior SFD-CLOEXEC SFD-NONBLOCK))))
        (foreign-free mask)
        (if (fx<? fd 0)
            (error 'sigwinch-fd-open (strerror (errno)))
            fd))))

  (define SIGFD-SIGINFO-SIZE 128) ; struct signalfd_siginfo

  (define (sigwinch-fd-drain fd)
    ;; Read and discard pending siginfo records; returns count consumed.
    (let ((buf (foreign-alloc SIGFD-SIGINFO-SIZE)))
      (let loop ((n 0))
        (let ((r (c-read fd buf SIGFD-SIGINFO-SIZE)))
          (cond
           ((fx<? r 0)
            (foreign-free buf)
            n)
           ((fx=? r 0)
            (foreign-free buf)
            n)
           (else (loop (fx+ n 1))))))))
  )

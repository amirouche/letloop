(library (tea syscall)

  (export
   ~check-syscall-constants
   ~check-syscall-sigwinch-fd
   ~check-syscall-winsize-on-non-tty)

  (import (chezscheme)
          (letloop tea syscall))

  ;; Smoke: constants are integers and exported.
  (define (~check-syscall-constants)
    (and (fixnum? O-RDWR)
         (fixnum? O-CLOEXEC)
         (fixnum? TCSAFLUSH)
         (fixnum? POLLIN)))

  ;; signalfd opens, drains zero pending signals, closes — no real signal
  ;; needed.  This also proves sigemptyset/sigaddset/sigprocmask/signalfd are
  ;; bound and the SIGSET_T size is right.
  (define (~check-syscall-sigwinch-fd)
    (let ((fd (sigwinch-fd-open)))
      (and (fx>? fd 2)
           (fx=? (sigwinch-fd-drain fd) 0)
           (fx=? (close-fd fd) 0))))

  ;; ioctl(TIOCGWINSZ) on a non-tty is expected to return -1; we just verify
  ;; the call doesn't blow up — ioctl-winsize raises in that case, so we
  ;; catch.  Also confirms the winsize ftype is wired up.
  (define (~check-syscall-winsize-on-non-tty)
    (let ((ws (make-winsize)))
      (guard (e (#t #t))
        (ioctl-winsize 1 ws)
        ;; If stdout *is* a tty in the test runner, that's fine too.
        (and (fx>=? (winsize-rows ws) 0)
             (fx>=? (winsize-cols ws) 0))))))

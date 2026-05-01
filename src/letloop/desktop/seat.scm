#!chezscheme
;; Seat acquisition — the low-level contract that lets Chez Scheme paint the
;; display directly.
;;
;; A "seat" bundles three kernel resources: a dedicated virtual terminal
;; (switched into KD_GRAPHICS so the kernel stops drawing a text console),
;; a DRM master handle on the graphics card (so mode sets are ours), and
;; the ambient state needed to restore everything cleanly.
;;
;; Acquisition sequence (mirrors kmscon/src/uterm/uterm_vt_linux.c and
;; wlroots/backend/session/direct-ipc.c, minus the Wayland plumbing):
;;
;;   1. open /dev/tty0         — controlling terminal device
;;   2. VT_GETSTATE            — remember the VT we started on
;;   3. VT_OPENQRY             — ask the kernel for a free VT number
;;   4. open /dev/ttyN         — the free VT itself
;;   5. VT_ACTIVATE + WAITACTIVE — switch to it; caller is now on screen
;;   6. KDGETMODE              — remember the text/graphics state
;;   7. KDSETMODE KD_GRAPHICS  — stop the kernel console driver
;;   8. open /dev/dri/card0    — the GPU
;;   9. DRM_IOCTL_SET_MASTER   — become the single DRM master
;;  10. install SIGINT trap so Ctrl-C drops us back to text cleanly
;;
;; seat-release reverses steps 9..6 and switches back to the original VT.
;; DRM master is also released implicitly by the kernel when drm-fd closes,
;; and KD_GRAPHICS leaks if the process dies between steps 7 and the
;; release — that's the one remaining foot-gun and why signal handling is
;; mandatory here.
;;
;; Not handled in M2.0: VT_PROCESS mode and the VT_RELDISP dance. A user
;; who presses Alt-F1 during a desktop session will kick the kernel into
;; confused territory; we'll revisit in M2.3 alongside input.
(library (letloop desktop seat)
  (export
   seat?
   seat-vt-number
   seat-tty0-fd
   seat-tty-vt-fd
   seat-drm-fd
   seat-original-kd-mode
   seat-original-vt
   seat-released?

   seat-take
   seat-release
   call-with-seat)
  (import
   (chezscheme)
   (letloop desktop ioctl))

  (define (pk . args)
    (when (getenv "LETLOOP_DEBUG")
      (display ";; " (current-error-port))
      (write args (current-error-port))
      (newline (current-error-port))
      (flush-output-port (current-error-port)))
    (if (null? args) (void) (car (reverse args))))

  ;; Linux VT ioctls (linux/vt.h) — legacy magic constants, not _IOC encoded.
  (define VT_OPENQRY    #x5600)
  (define VT_GETMODE    #x5601)
  (define VT_SETMODE    #x5602)
  (define VT_GETSTATE   #x5603)
  (define VT_RELDISP    #x5605)
  (define VT_ACTIVATE   #x5606)
  (define VT_WAITACTIVE #x5607)

  (define VT_AUTO    0)   ; kernel handles VT switches
  (define VT_PROCESS 1)   ; we handle VT switches ourselves

  ;; POSIX signal numbers on Linux/x86_64.
  (define SIGTERM 15)
  (define SIGSEGV 11)
  ;; SIGUSR1 — convention kmscon and wlroots use for VT release.
  (define SIGUSR1 10)

  ;; Linux KD ioctls (linux/kd.h) — also legacy magic.
  (define KDGETMODE #x4B3B)
  (define KDSETMODE #x4B3A)
  (define KD_TEXT     0)
  (define KD_GRAPHICS 1)

  ;; DRM ioctls (include/uapi/drm/drm.h). Type 'd' = #x64.
  (define DRM_IOCTL_SET_MASTER  (_IO #x64 #x1E))
  (define DRM_IOCTL_DROP_MASTER (_IO #x64 #x1F))

  (define-record-type seat
    (fields
     (mutable   released?)
     (immutable vt-number)
     (immutable tty0-fd)
     (immutable tty-vt-fd)
     (immutable drm-fd)
     (immutable original-kd-mode)
     (immutable original-vt))
    (protocol
     (lambda (new)
       (lambda (vt-number tty0-fd tty-vt-fd drm-fd kd-mode orig-vt)
         (new #f vt-number tty0-fd tty-vt-fd drm-fd kd-mode orig-vt)))))

  ;; ----------------------------------------------------------------
  ;; VT_SETMODE — declare ourselves the VT-switch handler so Alt+Fn
  ;; sends us SIGUSR1 instead of the kernel ripping the screen out
  ;; from under us. We refuse all switches (VT_RELDISP 0) while in
  ;; KD_GRAPHICS — letloop desktop is meant to be the exclusive
  ;; consumer of its seat, like an embedded kiosk. Polite-multitenant
  ;; behaviour (drop master, allow switch, reacquire on SIGUSR2)
  ;; would require a swapchain rebuild on every chvt and is out of
  ;; scope for M2.x.
  ;;
  ;; struct vt_mode (linux/vt.h):
  ;;   char  mode;     // VT_AUTO or VT_PROCESS
  ;;   char  waitv;    // unused
  ;;   short relsig;   // signal sent on VT release request
  ;;   short acqsig;   // signal sent on VT acquired
  ;;   short frsig;    // unused
  ;;
  ;; sizeof = 8 bytes (1 + 1 + 2 + 2 + 2).
  ;; ----------------------------------------------------------------

  (define (vt-set-mode! who fd mode-byte relsig acqsig)
    (let ((p (foreign-alloc 8)))
      (dynamic-wind
       void
       (lambda ()
         (foreign-set! 'unsigned-8  p 0 mode-byte)
         (foreign-set! 'unsigned-8  p 1 0)
         (foreign-set! 'unsigned-16 p 2 relsig)
         (foreign-set! 'unsigned-16 p 4 acqsig)
         (foreign-set! 'unsigned-16 p 6 0)
         (let-values (((ret errno) (sys-ioctl-ptr fd VT_SETMODE p)))
           (errno-check who ret errno)))
       (lambda () (foreign-free p)))))

  ;; A single mutable holds the tty-vt-fd that the SIGUSR1 handler
  ;; needs to call VT_RELDISP on. set! at seat-take time, cleared at
  ;; seat-release. The handler uses this rather than a parameter
  ;; because Chez's deferred signal dispatch may run on a thread that
  ;; doesn't share the parameterize binding.
  (define vt-process-tty-fd #f)

  ;; The currently-live seat, exposed to global signal handlers
  ;; (SIGTERM / SIGSEGV) so they can drop KD_GRAPHICS before _exit.
  ;; SIGKILL is uncatchable — there's no software fix for `kill -9`.
  (define active-seat #f)

  (define (fatal-signal-handler signum)
    ;; Best-effort cleanup. Chez's register-signal-handler runs us
    ;; deferred at the next safe point; if the runtime is too far
    ;; gone (typical SEGV) this never fires, but worst case the
    ;; user's next chvt resets the console anyway. Ordering here is
    ;; the same as seat-release: drop master, KD_TEXT, restore VT.
    (when active-seat
      (guard (_ [#t #f])
        (seat-release active-seat)))
    (exit (+ 128 signum)))

  (define (vt-refuse-switch!)
    ;; Called from the SIGUSR1 handler — tells the kernel "no, we
    ;; aren't releasing this VT". The user stays on our screen.
    (when vt-process-tty-fd
      (guard (_ [#t #f])
        (sys-ioctl-int vt-process-tty-fd VT_RELDISP 0))))

  ;; ---------- ioctl helpers that allocate, call, free ----------

  (define (ioctl-out-u32 who fd request)
    ;; For ioctls that write a single u32 through a pointer (VT_OPENQRY,
    ;; KDGETMODE). Returns the value.
    (let ((p (foreign-alloc 4)))
      (dynamic-wind
       void
       (lambda ()
         (foreign-set! 'unsigned-32 p 0 0)
         (let-values (((ret errno) (sys-ioctl-ptr fd request p)))
           (errno-check who ret errno)
           (foreign-ref 'unsigned-32 p 0)))
       (lambda () (foreign-free p)))))

  (define (ioctl-vt-getstate who fd)
    ;; struct vt_stat { u16 v_active; u16 v_signal; u16 v_state; }
    (let ((p (foreign-alloc 6)))
      (dynamic-wind
       void
       (lambda ()
         (foreign-set! 'unsigned-16 p 0 0)
         (foreign-set! 'unsigned-16 p 2 0)
         (foreign-set! 'unsigned-16 p 4 0)
         (let-values (((ret errno) (sys-ioctl-ptr fd VT_GETSTATE p)))
           (errno-check who ret errno)
           (foreign-ref 'unsigned-16 p 0)))
       (lambda () (foreign-free p)))))

  ;; ---------- seat-take ----------

  (define (open-or-die who path flags)
    (let-values (((fd errno) (sys-open path flags)))
      (when (negative? fd)
        (errno-raise who errno))
      fd))

  (define (ioctl-int-or-die who fd request arg)
    (let-values (((ret errno) (sys-ioctl-int fd request arg)))
      (errno-check who ret errno)))

  (define (safe-close fd)
    (when fd
      (let-values (((r _) (sys-close fd))) r)))

  (define (seat-take)
    ;; Partial-construction state held in mutable locals so an error mid-way
    ;; can roll back whatever was already claimed.
    (define tty0-fd      #f)
    (define orig-vt      #f)
    (define vt-num       #f)
    (define tty-vt-fd    #f)
    (define orig-kd-mode #f)
    (define kd-set?      #f)
    (define drm-fd       #f)
    (define master?      #f)
    (define vt-process-set? #f)

    (define (rollback!)
      (pk 'seat-take 'rollback!)
      (when master?   (ioctl-int-or-die 'seat-take/rollback drm-fd DRM_IOCTL_DROP_MASTER 0))
      (safe-close drm-fd)
      (when vt-process-set?
        (guard (_ [#t #f])
          (vt-set-mode! 'seat-take/rollback tty-vt-fd VT_AUTO 0 0))
        (set! vt-process-tty-fd #f))
      (when kd-set?   (ioctl-int-or-die 'seat-take/rollback tty-vt-fd KDSETMODE orig-kd-mode))
      (when (and tty0-fd orig-vt)
        (ioctl-int-or-die 'seat-take/rollback tty0-fd VT_ACTIVATE   orig-vt)
        (ioctl-int-or-die 'seat-take/rollback tty0-fd VT_WAITACTIVE orig-vt))
      (safe-close tty-vt-fd)
      (safe-close tty0-fd))

    (guard (e [#t
               (guard (_ [#t #f]) (rollback!))
               (raise e)])

      (set! tty0-fd (open-or-die 'seat-take/tty0 "/dev/tty0"
                                 (bitwise-ior O_RDWR O_CLOEXEC)))
      (pk 'seat-take 'tty0-fd tty0-fd)

      (set! orig-vt (ioctl-vt-getstate 'seat-take/vt-getstate tty0-fd))
      (pk 'seat-take 'original-vt orig-vt)

      (set! vt-num (ioctl-out-u32 'seat-take/vt-openqry tty0-fd VT_OPENQRY))
      (pk 'seat-take 'free-vt vt-num)

      (set! tty-vt-fd
        (open-or-die 'seat-take/ttyN
                     (format #f "/dev/tty~a" vt-num)
                     (bitwise-ior O_RDWR O_CLOEXEC)))
      (pk 'seat-take 'tty-vt-fd tty-vt-fd)

      (ioctl-int-or-die 'seat-take/activate   tty0-fd VT_ACTIVATE   vt-num)
      (ioctl-int-or-die 'seat-take/waitactive tty0-fd VT_WAITACTIVE vt-num)

      (set! orig-kd-mode (ioctl-out-u32 'seat-take/kdgetmode tty-vt-fd KDGETMODE))
      (pk 'seat-take 'original-kd-mode orig-kd-mode)

      (ioctl-int-or-die 'seat-take/kdsetmode tty-vt-fd KDSETMODE KD_GRAPHICS)
      (set! kd-set? #t)

      ;; Take over VT-switch handling. The kernel will now send us
      ;; SIGUSR1 when someone presses Alt+Fn, and we'll refuse the
      ;; switch via VT_RELDISP 0 — keeps our display intact.
      (set! vt-process-tty-fd tty-vt-fd)
      (register-signal-handler SIGUSR1 (lambda (_signum) (vt-refuse-switch!)))
      (vt-set-mode! 'seat-take/vt-setmode tty-vt-fd VT_PROCESS SIGUSR1 SIGUSR1)
      (set! vt-process-set? #t)
      (pk 'seat-take 'vt-process-mode 'on)

      (set! drm-fd (open-or-die 'seat-take/card0 "/dev/dri/card0"
                                (bitwise-ior O_RDWR O_CLOEXEC)))
      (pk 'seat-take 'drm-fd drm-fd)

      (ioctl-int-or-die 'seat-take/setmaster drm-fd DRM_IOCTL_SET_MASTER 0)
      (set! master? #t)

      (let ((s (make-seat vt-num tty0-fd tty-vt-fd drm-fd orig-kd-mode orig-vt)))
        ;; Stash the seat where SIGTERM / SIGSEGV handlers can find it.
        (set! active-seat s)
        (register-signal-handler SIGTERM fatal-signal-handler)
        (register-signal-handler SIGSEGV fatal-signal-handler)
        s)))

  ;; ---------- seat-release ----------

  (define (seat-release seat)
    (unless (seat-released? seat)
      (seat-released?-set! seat #t)
      (pk 'seat-release seat)
      ;; Best-effort: each step may fail on its own (e.g. already-dropped master)
      ;; but we push through so later steps still run. Order matters — drop
      ;; master before closing drm-fd, restore KD mode before closing tty-vt.
      (guard (_ [#t #f])
        (sys-ioctl-int (seat-drm-fd seat) DRM_IOCTL_DROP_MASTER 0))
      (safe-close (seat-drm-fd seat))
      ;; Hand VT-switch handling back to the kernel before flipping
      ;; the console out of KD_GRAPHICS — otherwise we'd get a
      ;; transient window where the kernel thinks we own switches
      ;; but the screen is text again.
      (guard (_ [#t #f])
        (vt-set-mode! 'seat-release (seat-tty-vt-fd seat) VT_AUTO 0 0))
      (set! vt-process-tty-fd #f)
      (guard (_ [#t #f])
        (sys-ioctl-int (seat-tty-vt-fd seat) KDSETMODE
                       (seat-original-kd-mode seat)))
      (guard (_ [#t #f])
        (sys-ioctl-int (seat-tty0-fd seat) VT_ACTIVATE (seat-original-vt seat))
        (sys-ioctl-int (seat-tty0-fd seat) VT_WAITACTIVE (seat-original-vt seat)))
      (safe-close (seat-tty-vt-fd seat))
      (safe-close (seat-tty0-fd seat))
      (set! active-seat #f)))

  ;; ---------- call-with-seat ----------
  ;;
  ;; Runs PROC with a live seat. seat-take installs three signal traps:
  ;; SIGINT (Ctrl-C, via keyboard-interrupt-handler), SIGTERM (kill),
  ;; SIGSEGV (best-effort — Chez's deferred dispatch may not survive a
  ;; corrupt heap). Each fires fatal-signal-handler → seat-release →
  ;; exit. SIGKILL (kill -9) remains uncatchable; the kernel releases
  ;; DRM master on fd close, and KD_GRAPHICS mode leaks until the next
  ;; chvt. There is no software fix for that path.
  (define (call-with-seat proc)
    (let ((seat (seat-take)))
      (dynamic-wind
       void
       (lambda ()
         (parameterize
          ((keyboard-interrupt-handler
            (lambda ()
              (seat-release seat)
              (exit 0))))
          (proc seat)))
       (lambda () (seat-release seat))))))

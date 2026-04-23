(library (letloop desktop)
  (export letloop-desktop)
  (import
   (chezscheme)
   (letloop cli base)
   (letloop desktop seat)
   (letloop desktop drm)
   (letloop desktop vulkan))

  (define (pk . args)
    (when (getenv "LETLOOP_DEBUG")
      (display ";; " (current-error-port))
      (write args (current-error-port))
      (newline (current-error-port))
      (flush-output-port (current-error-port)))
    (if (null? args) (void) (car (reverse args))))

  ;; M2.0 deliverable: take the seat, print connector info, park here until
  ;; Ctrl-C. The SIGINT handler installed by call-with-seat does the
  ;; release, then exit(0) — at which point the kernel console driver
  ;; reclaims the TTY and the user sees their shell again.
  ;;
  ;; A naive (read (current-input-port)) on /dev/stdin would work, but
  ;; stdin was attached to the old VT and we've switched away from it. So
  ;; we just block in pause(2), relying on SIGINT to wake us.
  (define letloop-desktop
    (lambda (args)
      (call-with-values (lambda () (cli-read args))
        (lambda (keywords positional extra)
          (cond
           ((and (null? positional)
                 (null? extra))
            (desktop-run))
           (else
            (format (current-error-port)
                    "letloop desktop: no arguments expected in M2.0\n")
            (exit 1)))))))

  (define (desktop-run)
    (format (current-error-port)
            "letloop desktop: taking the seat...\n")
    (call-with-seat
     (lambda (seat)
       (format (current-error-port)
               "seat acquired: vt=~a drm-fd=~a (Ctrl-C to release)\n"
               (seat-vt-number seat)
               (seat-drm-fd seat))
       (drm-describe-connectors (seat-drm-fd seat) (current-error-port))
       (vulkan-describe          (current-error-port))
       (flush-output-port (current-error-port))
       (park-forever))))

  (define park-forever
    (let ((pause (foreign-procedure "pause" () int)))
      (lambda ()
        (let loop ()
          (pause)
          (loop))))))

(library (letloop desktop)
  (export letloop-desktop)
  (import
   (chezscheme)
   (letloop cli base)
   (letloop desktop seat)
   (letloop desktop drm)
   (letloop desktop vulkan)
   (letloop desktop window))

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
       (call-with-vulkan-instance "letloop-desktop"
         (lambda (instance)
           (call-with-window instance
             (lambda (w)
               (let ((rgba (parse-clear-color (getenv "LETLOOP_DESKTOP_COLOR"))))
                 (window-clear-color! w
                                      (car rgba) (cadr rgba)
                                      (caddr rgba) (cadddr rgba)))
               (window-fg-color! w 1.0 1.0 1.0 1.0)
               (window-draw-text! w "letloop desktop" 40 40)
               (window-draw-text! w "press Ctrl-C to exit" 40 80)
               (window-run! w))))))))

  ;; Parse "R G B" or "R G B A" as floats from LETLOOP_DESKTOP_COLOR.
  ;; Default is opaque magenta — visible against any boot console.
  (define (parse-clear-color s)
    (define default '(1.0 0.0 1.0 1.0))
    (cond
     ((or (not s) (zero? (string-length s)))
      default)
     (else
      (guard (e (#t default))
        (let* ((normalized
                (list->string
                 (map (lambda (c) (if (char=? c #\,) #\space c))
                      (string->list s))))
               (parts (filter (lambda (p) (not (zero? (string-length p))))
                              (split-on-space normalized))))
          (let ((vals (map (lambda (p) (exact->inexact (string->number p)))
                           parts)))
            (cond
             ((= (length vals) 3) (append vals (list 1.0)))
             ((= (length vals) 4) vals)
             (else default))))))))

  (define (split-on-space s)
    (let loop ((chars (string->list s)) (acc '()) (out '()))
      (cond
       ((null? chars)
        (reverse (if (null? acc) out (cons (list->string (reverse acc)) out))))
       ((char=? (car chars) #\space)
        (loop (cdr chars) '()
              (if (null? acc) out (cons (list->string (reverse acc)) out))))
       (else
        (loop (cdr chars) (cons (car chars) acc) out))))))

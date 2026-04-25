#!chezscheme
;; (letloop tea) — public API of the Scheme termbox2 port.
;;
;; A tea instance is opaque; pass it as the first argument to every
;; non-constructor procedure.  Output is double-buffered (cellbuf-diff!
;; produces minimal escape sequences); input is parsed by a state machine
;; fed bytes from an io_uring-driven event loop, with SIGWINCH delivered
;; via signalfd as just another fd to poll.
(library (letloop tea)
  (export
   ;; lifecycle
   tea-open
   tea-close
   ;; geometry
   tea-width
   tea-height
   tea-resize
   ;; drawing
   tea-clear
   tea-set-cell
   tea-print
   tea-present
   ;; cursor (cosmetic — the in-buffer cursor is just where the program
   ;; rendered; these toggle the actual blinking terminal cursor)
   tea-hide-cursor
   tea-show-cursor
   tea-set-cursor
   ;; output mode (live switch — forces a full repaint on next present)
   tea-set-output-mode
   ;; events
   tea-poll
   tea-events
   tea-on-event
   ;; introspection
   tea-output-mode
   tea-fd
   ;; re-exports for callers (so they don't have to import (letloop tea cell))
   attr-mask)
  (import (chezscheme)
          (letloop tea syscall)
          (letloop tea sgr)
          (letloop tea cell)
          (letloop tea caps)
          (letloop tea terminfo)
          (letloop tea input)
          (letloop tea loop))

  (define-record-type tea
    (fields fd
            (mutable saved-termios)
            caps
            (mutable output-mode)
            (mutable back)
            (mutable front)
            (mutable cursor-x)
            (mutable cursor-y)
            (mutable cursor-visible?)
            (mutable parser)
            (mutable loop)
            (mutable on-event-cb)))   ; #f or proc(event)

  ;; ----- lifecycle ---------------------------------------------------------

  (define (write-string-fd fd str)
    (let* ((bv (string->utf8 str))
           (n  (bytevector-length bv)))
      (cond
       ((fx=? n 0) 0)
       (else
        (let ((ptr (foreign-alloc n)))
          (let loop ((i 0))
            (when (fx<? i n)
              (foreign-set! 'unsigned-8 ptr i (bytevector-u8-ref bv i))
              (loop (fx+ i 1))))
          (let ((r (write-fd fd ptr n)))
            (foreign-free ptr)
            r))))))

  (define (read-winsize fd)
    (let ((ws (make-winsize)))
      (ioctl-winsize fd ws)
      (let ((rows (winsize-rows ws)) (cols (winsize-cols ws)))
        (foreign-free (ftype-pointer-address ws))
        (values cols rows))))

  (define tea-open
    (case-lambda
     (()
      (tea-open '()))
     ((opts)
      (let* ((tty-path     (or (and (assq 'tty opts) (cdr (assq 'tty opts)))
                               "/dev/tty"))
             (output-mode  (or (and (assq 'output-mode opts)
                                    (cdr (assq 'output-mode opts)))
                               'normal))
             (alt-screen?  (let ((p (assq 'alt-screen? opts)))
                             (if p (cdr p) #t)))
             (hide-cursor? (let ((p (assq 'hide-cursor? opts)))
                             (if p (cdr p) #t)))
             (term         (getenv "TERM"))
             ;; Three-tier cap lookup: built-in match first, then the
             ;; binary terminfo database, then xterm as a final fallback.
             (caps         (or (caps-for-term/strict term)
                               (terminfo-cap-set    term)
                               (caps-for-term       term)))
             (fd           (open-tty tty-path)))
        (unless (isatty? fd)
          (close-fd fd)
          (error 'tea-open "not a tty" tty-path))
        (let ((saved (make-termios))
              (raw   (make-termios)))
          (tcgetattr fd saved)
          (tcgetattr fd raw)
          (cfmakeraw! raw)
          (tcsetattr fd TCSAFLUSH raw)
          (let-values (((w h) (read-winsize fd)))
            (let* ((w* (if (fx=? w 0) 80 w))
                   (h* (if (fx=? h 0) 24 h))
                   (back   (make-cellbuf w* h*))
                   (front  (make-cellbuf w* h*))
                   (parser (make-input-parser caps))
                   (loop   (make-tea-loop fd parser))
                   (instance (make-tea fd saved caps output-mode
                                       back front 0 0 (not hide-cursor?)
                                       parser loop #f)))
              ;; init: alt screen, hide cursor, clear, keypad on
              (when alt-screen?
                (write-string-fd fd (cap-set-init-string caps)))
              (write-string-fd fd (cap-set-keypad-on caps))
              instance)))))))

  (define (tea-close tea)
    (let ((fd   (tea-fd tea))
          (caps (tea-caps tea))
          (saved (tea-saved-termios tea))
          (loop (tea-loop tea)))
      ;; cosmetic: leave keypad mode, send shutdown
      (write-string-fd fd (cap-set-keypad-off caps))
      (write-string-fd fd (cap-set-shutdown-string caps))
      ;; tear down the iouring loop (frees ring, sigfd, buffers)
      (when loop (tea-loop-shutdown! loop))
      ;; restore termios
      (tcsetattr fd TCSAFLUSH saved)
      (foreign-free saved)
      (close-fd fd)))

  ;; ----- geometry ----------------------------------------------------------

  (define (tea-width  tea) (cellbuf-w (tea-back tea)))
  (define (tea-height tea) (cellbuf-h (tea-back tea)))

  (define (tea-resize tea)
    ;; Re-read the window size and reallocate buffers.  Caller fires this
    ;; after a SIGWINCH (via signalfd in the iouring loop) or whenever the
    ;; outer program decides the geometry might have changed.
    (let-values (((w h) (read-winsize (tea-fd tea))))
      (let ((w* (if (fx=? w 0) 80 w))
            (h* (if (fx=? h 0) 24 h)))
        (cellbuf-resize! (tea-back  tea) w* h*)
        (cellbuf-resize! (tea-front tea) w* h*)
        (values w* h*))))

  ;; ----- drawing -----------------------------------------------------------

  (define (tea-clear tea) (cellbuf-clear! (tea-back tea)))

  (define tea-set-cell
    (case-lambda
     ((tea x y ch fg bg)         (tea-set-cell tea x y ch fg bg 0))
     ((tea x y ch fg bg attr)
      (let ((mask (if (fixnum? attr) attr (list->attr-mask attr))))
        (cellbuf-set! (tea-back tea) x y
                      (if (char? ch) (char->integer ch) ch)
                      fg bg mask)))))

  (define tea-print
    (case-lambda
     ((tea x y fg bg str)        (tea-print tea x y fg bg str 0))
     ((tea x y fg bg str attr)
      (let ((mask (if (fixnum? attr) attr (list->attr-mask attr))))
        (cellbuf-set-string! (tea-back tea) x y str fg bg mask)))))

  (define (tea-present tea)
    (let-values (((p get) (open-string-output-port)))
      ;; Hide the cursor while we redraw to avoid flicker, then move it back
      ;; to the program's logical cursor position and (maybe) show it.
      (sgr-hide-cursor! p)
      (cellbuf-diff! p (tea-back tea) (tea-front tea) (tea-output-mode tea))
      (sgr-cursor! p (tea-cursor-x tea) (tea-cursor-y tea))
      (when (tea-cursor-visible? tea)
        (sgr-show-cursor! p))
      (write-string-fd (tea-fd tea) (get))))

  ;; ----- cursor ------------------------------------------------------------

  (define (tea-set-cursor tea x y)
    (tea-cursor-x-set! tea x)
    (tea-cursor-y-set! tea y))

  (define (tea-hide-cursor tea) (tea-cursor-visible?-set! tea #f))
  (define (tea-show-cursor tea) (tea-cursor-visible?-set! tea #t))

  ;; ----- output mode -------------------------------------------------------

  (define (tea-set-output-mode tea mode)
    (tea-output-mode-set! tea mode)
    ;; Force a full repaint by clearing the front buffer.
    (cellbuf-clear! (tea-front tea)))

  ;; ----- events -----------------------------------------------------------

  (define (handle-resize-marker! tea)
    ;; The loop puts 'resize-event in the queue when SIGWINCH arrives.  We
    ;; translate it to a real resize record and update both buffers.
    (let-values (((w h) (tea-resize tea)))
      (tea-loop-clear-resize-pending! (tea-loop tea))
      (cons 'resize (cons w h))))

  (define (next-event! tea)
    (let* ((loop (tea-loop tea))
           (e    (tea-loop-pop-event! loop)))
      (cond
       ((eq? e 'resize-event) (handle-resize-marker! tea))
       (else                  e))))

  (define tea-poll
    (case-lambda
     ((tea)         (tea-poll tea #f))
     ((tea timeout-ms)
      (let ((loop (tea-loop tea)))
        (let drive ()
          (let ((e (next-event! tea)))
            (cond
             (e e)
             (else
              (let ((produced (tea-loop-run-once! loop timeout-ms)))
                (cond
                 ((fx>? produced 0) (drive))
                 (timeout-ms        #f)
                 (else              (drive))))))))))))

  (define (tea-events tea)
    ;; Pull-style stream: returns a thunk that yields the next event each
    ;; call, blocking the io_uring loop until one arrives.  This composes
    ;; with (letloop generator) — wrapping it with make-iterator gives a
    ;; proper generator if the caller wants one.
    (lambda () (tea-poll tea)))

  (define (tea-on-event tea proc)
    ;; Push-style: register a single callback.  Each iteration of the
    ;; internal loop fires it with every event drained that round.
    (tea-on-event-cb-set! tea proc)
    ;; Drive the loop forever, dispatching every event to proc.  Returns
    ;; only if proc throws.
    (let drive ()
      (let ((loop (tea-loop tea)))
        (tea-loop-run-once! loop #f)
        (let drain ()
          (let ((e (next-event! tea)))
            (when e
              (proc e)
              (drain))))
        (drive))))
  )

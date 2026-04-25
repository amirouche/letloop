(library (tea base)

  (export
   ~check-base-cellbuf-render-pipeline
   ~check-base-attr-mask-export
   ~check-base-output-mode-switch-repaints)

  (import (chezscheme)
          (letloop tea sgr)
          (letloop tea cell)
          (letloop tea))

  ;; The renderer pipeline used by tea-present, exercised without a tty.
  ;; This is the core composition: write into back via tea-print/tea-set-cell
  ;; equivalents, then cellbuf-diff! into a port, then check the bytes.

  (define (~check-base-cellbuf-render-pipeline)
    (let* ((back  (make-cellbuf 5 1))
           (front (make-cellbuf 5 1))
           (mask  (attr-mask bold)))
      (cellbuf-set-string! back 0 0 "hi" 1 #f mask)
      (let-values (((p get) (open-string-output-port)))
        (cellbuf-diff! p back front 'normal)
        ;; cursor home, then SGR(reset, bold, fg=red, bg=default), then "hi"
        (string=? (get)
                  "\x1b;[1;1H\x1b;[0;1;31;49mhi"))))

  (define (~check-base-attr-mask-export)
    ;; (letloop tea) re-exports attr-mask so callers don't need to import
    ;; (letloop tea cell) just to write decorated strings.
    (fx=? (attr-mask bold underline)
          (fxior 1 8)))

  ;; ----- output mode switch -----------------------------------------------

  (define (~check-base-output-mode-switch-repaints)
    ;; After a mode switch, every cell of front is "blank/default", so the
    ;; next diff must repaint the full back buffer in the new mode's SGR.
    (let* ((back  (make-cellbuf 3 1))
           (front (make-cellbuf 3 1)))
      (cellbuf-set! back 0 0 (char->integer #\R) #xff0000 #f 0)
      ;; First render in truecolor — front is empty so the whole row paints.
      (let-values (((p get) (open-string-output-port)))
        (cellbuf-diff! p back front 'truecolor)
        (let ((s (get)))
          (and (> (string-length s) 10)
               (let-values (((p2 get2) (open-string-output-port)))
                 ;; Second render after mode switch + front cleared:
                 ;; should still emit the cell — proving cellbuf-clear!
                 ;; on front is the right "force repaint" mechanism.
                 (cellbuf-clear! front)
                 (cellbuf-diff! p2 back front 'normal)
                 (> (string-length (get2)) 0))))))))

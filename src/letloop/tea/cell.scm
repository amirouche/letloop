#!chezscheme
;; (letloop tea cell) — cell grid + double-buffered diff.
;;
;; A cellbuf is a w*h grid where each cell holds (char, fg, bg, attr-mask).
;;   char     — Unicode codepoint (fixnum), default = space (32)
;;   fg, bg   — color value in the active output mode, or #f for default
;;   attr     — attribute bitmask (see attr-mask->list / list->attr-mask)
;;
;; Two cellbufs are kept: `back` (what the program drew this frame) and
;; `front` (what is currently on screen).  cellbuf-diff! walks both, emits
;; only the cursor moves, SGR changes, and characters needed to make front
;; match back, then atomically copies back into front.
;;
;; All output is written to a textual port; UTF-8 byte conversion happens
;; later, when the port's string is flushed via write(2).
(library (letloop tea cell)
  (export
   make-cellbuf
   cellbuf-w  cellbuf-h
   cellbuf-resize!
   cellbuf-clear!
   cellbuf-set!
   cellbuf-set-string!
   cellbuf-ref
   cellbuf-diff!
   ;; attribute helpers
   attr-mask attr-mask->list list->attr-mask
   ATTR-BOLD ATTR-DIM ATTR-ITALIC ATTR-UNDERLINE ATTR-BLINK
   ATTR-REVERSE ATTR-INVISIBLE ATTR-STRIKEOUT ATTR-UNDERLINE-2 ATTR-OVERLINE

   ~check-cell-make-clear
   ~check-cell-set-ref
   ~check-cell-set-string
   ~check-cell-resize-shrink
   ~check-cell-resize-grow
   ~check-cell-attr-mask-roundtrip
   ~check-cell-diff-empty
   ~check-cell-diff-single
   ~check-cell-diff-multi
   ~check-cell-diff-state-tracking)
  (import (chezscheme)
          (letloop tea sgr)
          (only (letloop tea width) codepoint-width))

  ;; ----- attribute mask ----------------------------------------------------

  (define ATTR-BOLD        1)
  (define ATTR-DIM         2)
  (define ATTR-ITALIC      4)
  (define ATTR-UNDERLINE   8)
  (define ATTR-BLINK       16)
  (define ATTR-REVERSE     32)
  (define ATTR-INVISIBLE   64)
  (define ATTR-STRIKEOUT   128)
  (define ATTR-UNDERLINE-2 256)
  (define ATTR-OVERLINE    512)

  (define (attr-symbol->bit s)
    (case s
      ((bold)        ATTR-BOLD)
      ((dim)         ATTR-DIM)
      ((italic)      ATTR-ITALIC)
      ((underline)   ATTR-UNDERLINE)
      ((blink)       ATTR-BLINK)
      ((reverse)     ATTR-REVERSE)
      ((invisible)   ATTR-INVISIBLE)
      ((strikeout)   ATTR-STRIKEOUT)
      ((underline-2) ATTR-UNDERLINE-2)
      ((overline)    ATTR-OVERLINE)
      (else (error 'attr-symbol->bit "unknown attribute" s))))

  (define attr-bits
    (vector
     (cons ATTR-BOLD        'bold)
     (cons ATTR-DIM         'dim)
     (cons ATTR-ITALIC      'italic)
     (cons ATTR-UNDERLINE   'underline)
     (cons ATTR-BLINK       'blink)
     (cons ATTR-REVERSE     'reverse)
     (cons ATTR-INVISIBLE   'invisible)
     (cons ATTR-STRIKEOUT   'strikeout)
     (cons ATTR-UNDERLINE-2 'underline-2)
     (cons ATTR-OVERLINE    'overline)))

  (define (attr-mask->list m)
    (let loop ((i 0) (acc '()))
      (cond
       ((fx=? i (vector-length attr-bits)) (reverse acc))
       (else
        (let* ((p (vector-ref attr-bits i))
               (bit (car p)) (sym (cdr p)))
          (loop (fx+ i 1)
                (if (fx=? (fxand m bit) 0) acc (cons sym acc))))))))

  (define (list->attr-mask attrs)
    (let loop ((a attrs) (m 0))
      (if (null? a) m (loop (cdr a) (fxior m (attr-symbol->bit (car a)))))))

  (define-syntax attr-mask
    (syntax-rules ()
      ((_ sym ...) (fxior (attr-symbol->bit 'sym) ...))
      ((_) 0)))

  ;; ----- cellbuf record ----------------------------------------------------

  (define-record-type cellbuf
    (fields (mutable w)
            (mutable h)
            (mutable chs)    ; fxvector
            (mutable fgs)    ; vector
            (mutable bgs)    ; vector
            (mutable attrs)) ; fxvector
    (protocol
     (lambda (new)
       (lambda (w h)
         (let ((n (fx* w h)))
           (new w h
                (make-fxvector n 32)         ; space
                (make-vector n #f)           ; default fg
                (make-vector n #f)           ; default bg
                (make-fxvector n 0)))))))    ; no attrs

  (define-syntax cb-idx
    (syntax-rules ()
      ((_ buf x y) (fx+ x (fx* y (cellbuf-w buf))))))

  (define (cellbuf-clear! buf)
    (let* ((n (fx* (cellbuf-w buf) (cellbuf-h buf)))
           (chs (cellbuf-chs buf))
           (fgs (cellbuf-fgs buf))
           (bgs (cellbuf-bgs buf))
           (atr (cellbuf-attrs buf)))
      (let loop ((i 0))
        (when (fx<? i n)
          (fxvector-set! chs i 32)
          (vector-set!  fgs i #f)
          (vector-set!  bgs i #f)
          (fxvector-set! atr i 0)
          (loop (fx+ i 1))))))

  (define (cellbuf-set! buf x y ch fg bg attr-mask-val)
    (let ((w (cellbuf-w buf)) (h (cellbuf-h buf)))
      (when (and (fx>=? x 0) (fx<? x w) (fx>=? y 0) (fx<? y h))
        (let ((i (fx+ x (fx* y w))))
          (fxvector-set! (cellbuf-chs   buf) i ch)
          (vector-set!   (cellbuf-fgs   buf) i fg)
          (vector-set!   (cellbuf-bgs   buf) i bg)
          (fxvector-set! (cellbuf-attrs buf) i attr-mask-val)))))

  (define (cellbuf-set-string! buf x y str fg bg attr-mask-val)
    ;; ASCII fast path; non-ASCII still works (one cell per codepoint),
    ;; but wide characters are not yet handled — that lives in width.scm.
    (let* ((n (string-length str))
           (w (cellbuf-w buf))
           (h (cellbuf-h buf)))
      (let loop ((i 0) (xi x))
        (cond
         ((fx>=? i n) xi)
         ((fx>=? xi w) xi)
         (else
          (cellbuf-set! buf xi y (char->integer (string-ref str i))
                        fg bg attr-mask-val)
          (loop (fx+ i 1) (fx+ xi 1)))))))

  (define (cellbuf-ref buf x y)
    (let ((i (cb-idx buf x y)))
      (values (fxvector-ref (cellbuf-chs   buf) i)
              (vector-ref   (cellbuf-fgs   buf) i)
              (vector-ref   (cellbuf-bgs   buf) i)
              (fxvector-ref (cellbuf-attrs buf) i))))

  ;; ----- resize -----------------------------------------------------------

  (define (cellbuf-resize! buf new-w new-h)
    (let* ((old-w (cellbuf-w buf)) (old-h (cellbuf-h buf))
           (n (fx* new-w new-h))
           (new-chs (make-fxvector n 32))
           (new-fgs (make-vector  n #f))
           (new-bgs (make-vector  n #f))
           (new-atr (make-fxvector n 0))
           (copy-w  (fxmin old-w new-w))
           (copy-h  (fxmin old-h new-h)))
      (let row-loop ((y 0))
        (when (fx<? y copy-h)
          (let col-loop ((x 0))
            (when (fx<? x copy-w)
              (let ((src (fx+ x (fx* y old-w)))
                    (dst (fx+ x (fx* y new-w))))
                (fxvector-set! new-chs dst (fxvector-ref (cellbuf-chs buf) src))
                (vector-set!   new-fgs dst (vector-ref   (cellbuf-fgs buf) src))
                (vector-set!   new-bgs dst (vector-ref   (cellbuf-bgs buf) src))
                (fxvector-set! new-atr dst (fxvector-ref (cellbuf-attrs buf) src))
                (col-loop (fx+ x 1)))))
          (row-loop (fx+ y 1))))
      (cellbuf-w-set!     buf new-w)
      (cellbuf-h-set!     buf new-h)
      (cellbuf-chs-set!   buf new-chs)
      (cellbuf-fgs-set!   buf new-fgs)
      (cellbuf-bgs-set!   buf new-bgs)
      (cellbuf-attrs-set! buf new-atr)))

  ;; ----- diff --------------------------------------------------------------
  ;;
  ;; Single-pass row-major scan.  Tracks the cursor's current screen position
  ;; and the SGR state (fg, bg, attr-mask) currently in effect so we only
  ;; emit changes.  After the scan, front is overwritten with back.

  (define (color=? a b) (eqv? a b))   ; both fixnums or both #f

  (define (cellbuf-diff! port back front mode)
    (unless (and (fx=? (cellbuf-w back) (cellbuf-w front))
                 (fx=? (cellbuf-h back) (cellbuf-h front)))
      (error 'cellbuf-diff! "back/front size mismatch"))
    (let* ((w (cellbuf-w back))
           (h (cellbuf-h back))
           (back-chs   (cellbuf-chs   back))
           (back-fgs   (cellbuf-fgs   back))
           (back-bgs   (cellbuf-bgs   back))
           (back-attrs (cellbuf-attrs back))
           (front-chs   (cellbuf-chs   front))
           (front-fgs   (cellbuf-fgs   front))
           (front-bgs   (cellbuf-bgs   front))
           (front-attrs (cellbuf-attrs front))
           (cur-x  -1) (cur-y -1)
           (st-fg  'unset) (st-bg 'unset) (st-attr -1))
      (let row-loop ((y 0))
        (when (fx<? y h)
          (let col-loop ((x 0))
            (when (fx<? x w)
              (let* ((i  (fx+ x (fx* y w)))
                     (ch (fxvector-ref back-chs   i))
                     (fg (vector-ref   back-fgs   i))
                     (bg (vector-ref   back-bgs   i))
                     (a  (fxvector-ref back-attrs i)))
                (unless (and (fx=? ch (fxvector-ref front-chs   i))
                             (color=? fg (vector-ref front-fgs   i))
                             (color=? bg (vector-ref front-bgs   i))
                             (fx=? a  (fxvector-ref front-attrs i)))
                  ;; cursor positioning
                  (unless (and (fx=? cur-x x) (fx=? cur-y y))
                    (sgr-cursor! port x y))
                  ;; SGR state change
                  (unless (and (color=? fg st-fg)
                               (color=? bg st-bg)
                               (fx=? a st-attr))
                    (sgr-set-color! port mode fg bg (attr-mask->list a))
                    (set! st-fg fg) (set! st-bg bg) (set! st-attr a))
                  ;; emit char — track where the terminal cursor really
                  ;; lands: wide glyphs advance two columns, combining
                  ;; marks none; assuming one desynchronizes the tracker
                  ;; from the screen for every following cell.
                  (write-char (integer->char ch) port)
                  (let ((w (codepoint-width ch)))
                    ;; wide → 2, combining → 0, everything else
                    ;; (incl. control, width -1) → 1
                    (set! cur-x (fx+ x (if (fx<? w 0) 1 w))))
                  (set! cur-y y)
                  ;; sync front <- back
                  (fxvector-set! front-chs   i ch)
                  (vector-set!   front-fgs   i fg)
                  (vector-set!   front-bgs   i bg)
                  (fxvector-set! front-attrs i a)))
              (col-loop (fx+ x 1))))
          (row-loop (fx+ y 1))))))
  

  (include "letloop/tea/cell.check.scm")
  )

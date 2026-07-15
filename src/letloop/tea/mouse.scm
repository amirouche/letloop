#!chezscheme
;; (letloop tea mouse) — decoders for the three terminal mouse encodings.
;;
;; X10 legacy:    \e[M  followed by three raw bytes (button+33, x+33, y+33)
;;                — coordinates capped at 223; safe to ignore at >222.
;; SGR 1006:      \e[<button;x;yM  (press / motion)
;;                \e[<button;x;ym  (release)
;;                — coordinates 1-indexed; we emit 0-indexed.
;; urxvt 1015:    \e[button+32;x;yM
;;
;; All three encode the button id with optional modifier bits OR'd in:
;;   bit 0..1   : button low bits  (0=L  1=M  2=R, 3=release in X10)
;;   bit 2  ( 4): shift held
;;   bit 3  ( 8): meta/alt held
;;   bit 4 (16): ctrl held
;;   bit 5 (32): motion (mouse moved while a button is held)
;;   bit 6 (64): high bit — together with low bits 0/1: wheel-up / wheel-down
;;
;; This module exports decode functions only; routing the three prefixes
;; through the input parser belongs in input.scm.
(library (letloop tea mouse)
  (export
   make-mouse-event
   mouse-event?
   mouse-event-button
   mouse-event-x
   mouse-event-y
   mouse-event-pressed?
   mouse-event-motion?
   mouse-event-mods
   decode-mouse-x10
   decode-mouse-sgr
   decode-mouse-urxvt

   ~check-mouse-x10-left-press
   ~check-mouse-x10-release
   ~check-mouse-x10-with-mods
   ~check-mouse-x10-motion
   ~check-mouse-sgr-left-press
   ~check-mouse-sgr-release
   ~check-mouse-sgr-wheel-up
   ~check-mouse-sgr-with-mods
   ~check-mouse-urxvt-middle-press
   ~check-mouse-zero-indexed-coords)
  (import (chezscheme))

  (define-record-type mouse-event
    (fields button       ; symbol: left|middle|right|wheel-up|wheel-down|release|motion
            x y          ; 0-indexed
            pressed?     ; #t for press, #f for release / motion-only
            motion?      ; #t if the motion bit is set
            mods))       ; list of symbols: shift, meta, ctrl

  ;; ----- decode helpers ---------------------------------------------------

  (define (decode-button-bits b)
    ;; Returns (values button-symbol pressed?)
    (let* ((wheel? (not (fx=? (fxand b 64) 0)))
           (low    (fxand b 3)))
      (cond
       (wheel?
        (case low
          ((0) (values 'wheel-up   #t))
          ((1) (values 'wheel-down #t))
          ((2) (values 'wheel-left #t))
          ((3) (values 'wheel-right #t))))
       (else
        (case low
          ((0) (values 'left   #t))
          ((1) (values 'middle #t))
          ((2) (values 'right  #t))
          ((3) (values 'release #f)))))))

  (define (decode-mods b)
    (let loop ((bits '((4 . shift) (8 . meta) (16 . ctrl)))
               (acc '()))
      (cond
       ((null? bits) (reverse acc))
       ((fx=? (fxand b (car (car bits))) 0)
        (loop (cdr bits) acc))
       (else
        (loop (cdr bits) (cons (cdr (car bits)) acc))))))

  (define (motion-bit? b) (not (fx=? (fxand b 32) 0)))

  ;; ----- X10 legacy --------------------------------------------------------
  ;;
  ;; The three bytes after \e[M are button+33, x+33, y+33.  No release info
  ;; per-button — the "release" state is encoded as button-low=3.

  (define (decode-mouse-x10 b1 b2 b3)
    (let* ((b   (fx- b1 32))
           (x   (fxmax 0 (fx- (fx- b2 32) 1)))
           (y   (fxmax 0 (fx- (fx- b3 32) 1))))
      (let-values (((sym pressed?) (decode-button-bits b)))
        (let ((mods   (decode-mods b))
              (motion (motion-bit? b)))
          (make-mouse-event
           (if motion 'motion sym)
           x y
           pressed?
           motion
           mods)))))

  ;; ----- SGR 1006 ----------------------------------------------------------

  (define (decode-mouse-sgr params trailing-char)
    ;; params: list of three positive ints (button x y)
    ;; trailing-char: #\M for press/motion, #\m for release
    (let* ((b (car params))
           (x (fxmax 0 (fx- (cadr params) 1)))
           (y (fxmax 0 (fx- (caddr params) 1)))
           (release? (char=? trailing-char #\m)))
      (let-values (((sym _press?) (decode-button-bits b)))
        (let* ((mods   (decode-mods b))
               (motion (motion-bit? b))
               (sym2   (cond
                        (release? 'release)
                        (motion   'motion)
                        (else     sym))))
          (make-mouse-event sym2 x y (not release?) motion mods)))))

  ;; ----- urxvt 1015 --------------------------------------------------------

  (define (decode-mouse-urxvt params)
    ;; params: list of three positive ints (button+32 x y)
    (let* ((b (fx- (car params) 32))
           (x (fxmax 0 (fx- (cadr params) 1)))
           (y (fxmax 0 (fx- (caddr params) 1))))
      (let-values (((sym pressed?) (decode-button-bits b)))
        (let ((mods   (decode-mods b))
              (motion (motion-bit? b)))
          (make-mouse-event
           (if motion 'motion sym)
           x y
           pressed?
           motion
           mods)))))
  

  (include "letloop/tea/mouse.check.scm")
  )

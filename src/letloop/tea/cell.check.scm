;; Checks for (letloop tea cell), driving the module through its exported
;; API the way a caller would.  Included at the tail of the library;
;; discovered by `make check` via the ~check- exports.


  (define (build f . args)
    (let-values (((p get) (open-string-output-port)))
      (apply f p args)
      (get)))

  (define-syntax expect
    (syntax-rules ()
      ((_ a b)
       (let ((a* a) (b* b))
         (or (equal? a* b*)
             (begin (display (list 'expected b* 'got a*)) (newline) #f))))))

  (define (~check-cell-make-clear)
    (let ((b (make-cellbuf 4 3)))
      (and (fx=? (cellbuf-w b) 4) (fx=? (cellbuf-h b) 3)
           (let-values (((c f g a) (cellbuf-ref b 0 0)))
             (and (fx=? c 32) (not f) (not g) (fx=? a 0))))))

  (define (~check-cell-set-ref)
    (let ((b (make-cellbuf 4 3)))
      (cellbuf-set! b 1 1 (char->integer #\X) 1 4 (attr-mask bold underline))
      (let-values (((c f g a) (cellbuf-ref b 1 1)))
        (and (fx=? c (char->integer #\X)) (eqv? f 1) (eqv? g 4)
             (fx=? a (fxior ATTR-BOLD ATTR-UNDERLINE))))))

  (define (~check-cell-set-string)
    (let ((b (make-cellbuf 6 1)))
      (cellbuf-set-string! b 1 0 "abc" 2 #f 0)
      (let-values (((c1 _f1 _g1 _a1) (cellbuf-ref b 1 0))
                   ((c2 _f2 _g2 _a2) (cellbuf-ref b 2 0))
                   ((c3 _f3 _g3 _a3) (cellbuf-ref b 3 0))
                   ((c4 _f4 _g4 _a4) (cellbuf-ref b 4 0)))
        (and (fx=? c1 97) (fx=? c2 98) (fx=? c3 99) (fx=? c4 32)))))

  (define (~check-cell-resize-shrink)
    (let ((b (make-cellbuf 4 4)))
      (cellbuf-set! b 0 0 65 #f #f 0)
      (cellbuf-set! b 3 3 90 #f #f 0)  ; outside the new bounds
      (cellbuf-resize! b 2 2)
      (let-values (((c _f _g _a) (cellbuf-ref b 0 0)))
        (and (fx=? (cellbuf-w b) 2)
             (fx=? c 65)))))

  (define (~check-cell-resize-grow)
    (let ((b (make-cellbuf 2 2)))
      (cellbuf-set! b 1 1 88 #f #f 0)
      (cellbuf-resize! b 4 4)
      (let-values (((c1 _f1 _g1 _a1) (cellbuf-ref b 1 1))
                   ((c2 _f2 _g2 _a2) (cellbuf-ref b 3 3)))
        (and (fx=? c1 88) (fx=? c2 32)))))

  (define (~check-cell-attr-mask-roundtrip)
    (let* ((m (list->attr-mask '(bold italic overline)))
           (l (attr-mask->list m)))
      ;; order is canonical (bold, dim, italic, ..., overline)
      (equal? l '(bold italic overline))))

  ;; ----- diff --------------------------------------------------------------

  (define (~check-cell-diff-empty)
    ;; back == front => no output
    (let ((back  (make-cellbuf 4 2))
          (front (make-cellbuf 4 2)))
      (string=? (build cellbuf-diff! back front 'normal) "")))

  (define (~check-cell-diff-single)
    ;; one cell changes -> cursor move + sgr + char
    (let ((back  (make-cellbuf 4 1))
          (front (make-cellbuf 4 1)))
      (cellbuf-set! back 2 0 (char->integer #\X) 1 #f 0)
      (let ((s (build cellbuf-diff! back front 'normal)))
        ;; CSI 1;3H ; CSI 0;31;49m ; X
        (expect s "\x1b;[1;3H\x1b;[0;31;49mX"))))

  (define (~check-cell-diff-multi)
    ;; two adjacent cells change with same colors -> single SGR, then both chars
    (let ((back  (make-cellbuf 4 1))
          (front (make-cellbuf 4 1)))
      (cellbuf-set! back 0 0 (char->integer #\a) 2 #f 0)
      (cellbuf-set! back 1 0 (char->integer #\b) 2 #f 0)
      (let ((s (build cellbuf-diff! back front 'normal)))
        ;; cursor only emitted once because b is at the cursor position after a
        (expect s "\x1b;[1;1H\x1b;[0;32;49mab"))))

  (define (~check-cell-diff-state-tracking)
    ;; non-adjacent cells force two cursor moves; identical color suppresses
    ;; the second SGR.
    (let ((back  (make-cellbuf 5 1))
          (front (make-cellbuf 5 1)))
      (cellbuf-set! back 0 0 (char->integer #\a) 1 #f 0)
      (cellbuf-set! back 3 0 (char->integer #\b) 1 #f 0)
      (let ((s (build cellbuf-diff! back front 'normal)))
        (expect s "\x1b;[1;1H\x1b;[0;31;49ma\x1b;[1;4Hb"))))

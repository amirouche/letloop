;; Checks for (letloop tea width), driving the module through its exported
;; API the way a caller would.  Included at the tail of the library;
;; discovered by `make check` via the ~check- exports.


  (define (~check-width-ascii)
    (and (= (codepoint-width 65) 1)        ; A
         (= (codepoint-width 32) 1)        ; space
         (= (codepoint-width 126) 1)))     ; ~

  (define (~check-width-control)
    (and (= (codepoint-width 0) -1)
         (= (codepoint-width #x1B) -1)     ; ESC
         (= (codepoint-width #x7F) -1)     ; DEL
         (= (codepoint-width #x9F) -1)))   ; last C1 control

  (define (~check-width-combining)
    (and (= (codepoint-width #x0300) 0)    ; combining grave
         (= (codepoint-width #x036F) 0)    ; last in first range
         (= (codepoint-width #x0483) 0)    ; combining cyrillic titlo
         (= (codepoint-width #x200B) 0)))  ; zero-width space

  (define (~check-width-cjk)
    (and (= (codepoint-width #x4E2D) 2)    ; 中
         (= (codepoint-width #x6587) 2)    ; 文
         (= (codepoint-width #x9FFF) 2)))

  (define (~check-width-hangul)
    (and (= (codepoint-width #xAC00) 2)    ; 가
         (= (codepoint-width #xD7A3) 2)
         (= (codepoint-width #x1100) 2)))

  (define (~check-width-fullwidth)
    (and (= (codepoint-width #xFF21) 2)    ; FULLWIDTH A
         (= (codepoint-width #xFF60) 2)))

  (define (~check-width-emoji)
    (and (= (codepoint-width #x1F389) 2)   ; 🎉
         (= (codepoint-width #x1F600) 2)   ; 😀
         (= (codepoint-width #x1F9E0) 2))) ; 🧠

  (define (~check-width-narrow-edges)
    ;; Just above U+036F (combining range end+1) is U+0370 = Greek capital
    ;; heta — narrow.  Just below U+1100 is U+10FF — narrow.
    (and (= (codepoint-width #x0370) 1)
         (= (codepoint-width #x10FF) 1)
         (= (codepoint-width #xA4D0) 1)))

  ;; Random spot-check: width should be one of {-1, 0, 1, 2} for every
  ;; codepoint we ask about, even ones that miss every range.
  (define (~check-width-monotone-binary-search)
    (let loop ((cps '(33 #x4E00 #x4DBF #x4DC0 #xFE10 #xFE30 #xFE4F #xFE50)))
      (or (null? cps)
          (let ((w (codepoint-width (car cps))))
            (and (memv w '(-1 0 1 2))
                 (loop (cdr cps)))))))

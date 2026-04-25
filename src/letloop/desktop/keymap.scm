;; M2.3 chunk E-2: scancode → character lookup for a US-QWERTY layout.
;;
;; The line editor in (letloop desktop window) consumes
;; keymap-printable to translate evdev key codes into characters that
;; show up in the line buffer. Non-printable keys (Enter, Backspace,
;; Tab, modifiers, function keys) return #f from keymap-printable;
;; the caller pattern-matches on the raw key code instead.
;;
;; This is the smallest layout that makes the M2.4 REPL usable. A
;; future M2.x can add Tifinagh / Arabic / Cyrillic entry — XKB-style
;; layout switching is out of scope here.
(library (letloop desktop keymap)
  (export
   keymap-printable)
  (import
   (chezscheme)
   (letloop desktop evdev))

  (define (or-default x default)
    (if x x default))

  ;; Returns the printable character produced by `key` with `shift?`
  ;; modifier state, or #f if the key has no printable mapping.
  ;;
  ;; Layout: US QWERTY, no AltGr / dead keys. Modifier layering for
  ;; Ctrl/Alt is the caller's job — we only handle Shift here.
  (define (keymap-printable key shift?)
    (cond
     ;; Letters
     ((= key KEY_A) (if shift? #\A #\a))
     ((= key KEY_B) (if shift? #\B #\b))
     ((= key KEY_C) (if shift? #\C #\c))
     ((= key KEY_D) (if shift? #\D #\d))
     ((= key KEY_E) (if shift? #\E #\e))
     ((= key KEY_F) (if shift? #\F #\f))
     ((= key KEY_G) (if shift? #\G #\g))
     ((= key KEY_H) (if shift? #\H #\h))
     ((= key KEY_I) (if shift? #\I #\i))
     ((= key KEY_J) (if shift? #\J #\j))
     ((= key KEY_K) (if shift? #\K #\k))
     ((= key KEY_L) (if shift? #\L #\l))
     ((= key KEY_M) (if shift? #\M #\m))
     ((= key KEY_N) (if shift? #\N #\n))
     ((= key KEY_O) (if shift? #\O #\o))
     ((= key KEY_P) (if shift? #\P #\p))
     ((= key KEY_Q) (if shift? #\Q #\q))
     ((= key KEY_R) (if shift? #\R #\r))
     ((= key KEY_S) (if shift? #\S #\s))
     ((= key KEY_T) (if shift? #\T #\t))
     ((= key KEY_U) (if shift? #\U #\u))
     ((= key KEY_V) (if shift? #\V #\v))
     ((= key KEY_W) (if shift? #\W #\w))
     ((= key KEY_X) (if shift? #\X #\x))
     ((= key KEY_Y) (if shift? #\Y #\y))
     ((= key KEY_Z) (if shift? #\Z #\z))
     ;; Digits + their shifted symbols
     ((= key KEY_1) (if shift? #\! #\1))
     ((= key KEY_2) (if shift? #\@ #\2))
     ((= key KEY_3) (if shift? #\# #\3))
     ((= key KEY_4) (if shift? #\$ #\4))
     ((= key KEY_5) (if shift? #\% #\5))
     ((= key KEY_6) (if shift? #\^ #\6))
     ((= key KEY_7) (if shift? #\& #\7))
     ((= key KEY_8) (if shift? #\* #\8))
     ((= key KEY_9) (if shift? #\( #\9))
     ((= key KEY_0) (if shift? #\) #\0))
     ;; Punctuation
     ((= key KEY_MINUS)      (if shift? #\_ #\-))
     ((= key KEY_EQUAL)      (if shift? #\+ #\=))
     ((= key KEY_LEFTBRACE)  (if shift? #\{ #\[))
     ((= key KEY_RIGHTBRACE) (if shift? #\} #\]))
     ((= key KEY_BACKSLASH)  (if shift? #\| #\\))
     ((= key KEY_SEMICOLON)  (if shift? #\: #\;))
     ((= key KEY_APOSTROPHE) (if shift? #\" #\'))
     ((= key KEY_GRAVE)      (if shift? #\~ #\`))
     ((= key KEY_COMMA)      (if shift? #\< #\,))
     ((= key KEY_DOT)        (if shift? #\> #\.))
     ((= key KEY_SLASH)      (if shift? #\? #\/))
     ;; Whitespace
     ((= key KEY_SPACE) #\space)
     (else #f))))

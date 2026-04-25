(library (tea caps)

  (export
   ~check-caps-xterm-shape
   ~check-caps-xterm-init-clears
   ~check-caps-xterm-shutdown-restores
   ~check-caps-xterm-input-keys-cover-arrows
   ~check-caps-for-term-exact
   ~check-caps-for-term-prefix
   ~check-caps-for-term-fallback
   ~check-caps-for-term-empty)

  (import (chezscheme)
          (letloop tea caps))

  (define (~check-caps-xterm-shape)
    (and (cap-set? xterm-caps)
         (string=? (cap-set-name xterm-caps) "xterm")
         (string? (cap-set-init-string xterm-caps))
         (string? (cap-set-shutdown-string xterm-caps))
         (list? (cap-set-input-keys xterm-caps))))

  (define (~check-caps-xterm-init-clears)
    ;; init must turn on alt screen, hide the cursor, and clear
    (let ((s (cap-set-init-string xterm-caps)))
      (and (string-contains s "\x1b;[?1049h")
           (string-contains s "\x1b;[?25l")
           (string-contains s "\x1b;[2J"))))

  (define (~check-caps-xterm-shutdown-restores)
    (let ((s (cap-set-shutdown-string xterm-caps)))
      (and (string-contains s "\x1b;[?25h")
           (string-contains s "\x1b;[?1049l"))))

  (define (~check-caps-xterm-input-keys-cover-arrows)
    (let ((keys (cap-set-input-keys xterm-caps)))
      (and (assoc "\x1b;[A" keys)
           (assoc "\x1b;OA" keys)   ; app-keypad form
           (assoc "\x1b;[5~" keys))))

  (define (~check-caps-for-term-exact)
    (eq? (caps-for-term "xterm") xterm-caps))

  (define (~check-caps-for-term-prefix)
    (eq? (caps-for-term "xterm-256color") xterm-caps))

  (define (~check-caps-for-term-fallback)
    ;; unknown TERM still returns something usable
    (eq? (caps-for-term "weird-terminal-xyz") xterm-caps))

  (define (~check-caps-for-term-empty)
    (eq? (caps-for-term #f) xterm-caps))

  ;; ----- helper: substring search -----------------------------------------

  (define (string-contains hay needle)
    (let* ((hl (string-length hay)) (nl (string-length needle)))
      (let loop ((i 0))
        (cond
         ((fx>? (fx+ i nl) hl) #f)
         ((string=? (substring hay i (fx+ i nl)) needle) i)
         (else (loop (fx+ i 1))))))))

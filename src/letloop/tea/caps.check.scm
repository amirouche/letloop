;; Checks for (letloop tea caps), driving the module through its exported
;; API the way a caller would.  Included at the tail of the library;
;; discovered by `make check` via the ~check- exports.


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

  (define (~check-caps-linux-no-altscreen)
    ;; linux console doesn't support \e[?1049h — verify init doesn't include it
    (let ((s (cap-set-init-string linux-caps)))
      (not (string-contains s "\x1b;[?1049h"))))

  (define (~check-caps-tmux-aliased)
    ;; tmux* TERM values pick up the tmux table (which mirrors screen)
    (and (eq? (caps-for-term "tmux") tmux-caps)
         (eq? (caps-for-term "tmux-256color") tmux-caps)))

  (define (~check-caps-rxvt-fkeys)
    ;; rxvt's F1 is \e[11~, not the xterm \eOP
    (let ((keys (cap-set-input-keys rxvt-unicode-caps)))
      (and (assoc "\x1b;[11~" keys)
           (not (assoc "\x1b;OP" keys)))))

  (define (~check-caps-mod-keys-shape)
    ;; Each entry is (escape-string . (key-symbol . mod-list))
    (let ((entry (assoc "\x1b;[1;5A" xterm-mod-keys)))
      (and entry
           (eq?    (cadr entry) 'arrow-up)
           (equal? (cddr entry) '(ctrl)))))

  ;; ----- helper: substring search -----------------------------------------

  (define (string-contains hay needle)
    (let* ((hl (string-length hay)) (nl (string-length needle)))
      (let loop ((i 0))
        (cond
         ((fx>? (fx+ i nl) hl) #f)
         ((string=? (substring hay i (fx+ i nl)) needle) i)
         (else (loop (fx+ i 1)))))))

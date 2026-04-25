(library (tea terminfo)

  (export
   ~check-terminfo-paths-include-system
   ~check-terminfo-load-xterm
   ~check-terminfo-load-missing
   ~check-terminfo-xterm-has-altscreen
   ~check-terminfo-xterm-input-keys
   ~check-terminfo-as-fallback)

  (import (chezscheme)
          (letloop tea caps)
          (letloop tea terminfo))

  (define (~check-terminfo-paths-include-system)
    (let ((ps (terminfo-paths)))
      (or (member "/usr/share/terminfo" ps)
          (member "/lib/terminfo" ps))))

  (define (~check-terminfo-load-xterm)
    (let ((cs (load-terminfo "xterm")))
      (and cs
           (cap-set? cs)
           (string=? (cap-set-name cs) "xterm"))))

  (define (~check-terminfo-load-missing)
    (not (load-terminfo "definitely-not-a-real-terminal-name-xyz")))

  (define (~check-terminfo-xterm-has-altscreen)
    (let* ((cs (load-terminfo "xterm"))
           (s  (cap-set-init-string cs)))
      ;; \e[?1049h appears in xterm's smcup
      (let loop ((i 0))
        (cond
         ((fx>? (fx+ i 7) (string-length s)) #f)
         ((string=? (substring s i (fx+ i 7)) "[?1049h") i)
         (else (loop (fx+ i 1)))))))

  (define (~check-terminfo-xterm-input-keys)
    (let* ((cs   (load-terminfo "xterm"))
           (keys (cap-set-input-keys cs)))
      ;; Should have at least one arrow key
      (or (assoc "\x1b;OA" keys)
          (assoc "\x1b;[A" keys))))

  (define (~check-terminfo-as-fallback)
    ;; The orchestration in tea.scm prefers strict built-in lookup;
    ;; terminfo only fires for unknown TERM values.  Verify that
    ;; terminfo can still resolve an xterm-derived term that's *not*
    ;; in our built-in list, like "vt220".
    (let ((cs (load-terminfo "vt220")))
      (or (and cs (cap-set? cs))
          ;; vt220 may not be installed everywhere — accept #f on systems
          ;; that don't ship it.
          (not (file-exists? "/usr/share/terminfo/v/vt220"))))))

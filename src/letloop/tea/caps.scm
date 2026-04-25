#!chezscheme
;; (letloop tea caps) — terminal capability tables.
;;
;; A `cap-set` describes one terminal type:
;;   name           — string, matched against $TERM (exact, then prefix)
;;   init-string    — bytes to write on tea-open (alt screen + cursor hide etc)
;;   shutdown-string— bytes to write on tea-close (undo init)
;;   keypad-on      — \e[?1h\e=  (xterm app-mode keypad)
;;   keypad-off     — \e[?1l\e>
;;   input-keys     — alist of (escape-sequence . key-symbol)
;;
;; Stage 1 ships only xterm.  The other six built-ins (screen, tmux, linux,
;; rxvt-256color, rxvt-unicode, eterm) and the binary terminfo parser arrive
;; in stage 5; the lookup function falls back to xterm in the meantime, which
;; covers the overwhelming majority of real terminals (and matches termbox2's
;; preferred fallback ordering).
(library (letloop tea caps)
  (export
   make-cap-set
   cap-set?
   cap-set-name
   cap-set-init-string
   cap-set-shutdown-string
   cap-set-keypad-on
   cap-set-keypad-off
   cap-set-input-keys
   ;; built-ins
   xterm-caps
   ;; lookup
   caps-for-term)
  (import (chezscheme))

  (define-record-type cap-set
    (fields name
            init-string
            shutdown-string
            keypad-on
            keypad-off
            input-keys))

  ;; ----- xterm -------------------------------------------------------------
  ;;
  ;; Init: enter alt screen with title save (\e[22t), hide cursor, clear.
  ;; Shutdown: show cursor, exit alt screen (with title restore).
  ;;
  ;; The two extra escape pairs around alt-screen-on/off save and restore
  ;; the xterm window title — termbox2 emits them so the user's title isn't
  ;; clobbered when the program exits.

  (define xterm-init-string
    (string-append
     "\x1b;[?1049h"     ; enter alternate screen buffer
     "\x1b;[22;0;0t"    ; xterm: save window+icon titles
     "\x1b;[?25l"       ; hide cursor
     "\x1b;[H\x1b;[2J"  ; home + clear
     ))

  (define xterm-shutdown-string
    (string-append
     "\x1b;[m"          ; reset SGR
     "\x1b;[?12l"       ; stop blinking cursor (xterm)
     "\x1b;[?25h"       ; show cursor
     "\x1b;[?1049l"     ; leave alternate screen
     "\x1b;[23;0;0t"    ; xterm: restore window+icon titles
     ))

  (define xterm-keypad-on  "\x1b;[?1h\x1b;=")
  (define xterm-keypad-off "\x1b;[?1l\x1b;>")

  ;; Input key table.  The escape sequences are exactly what xterm emits in
  ;; default mode (with app-keypad off — when on, arrows become \eOA etc, so
  ;; both forms are listed).  Function keys F1..F4 use \eO followed by P,Q,R,S
  ;; as that's how xterm encodes them (modern xterm uses \e[1;2P style with
  ;; modifiers, parsed separately by the modifier-trie).

  (define xterm-input-keys
    '(;; arrows (CSI form)
      ("\x1b;[A" . arrow-up)
      ("\x1b;[B" . arrow-down)
      ("\x1b;[C" . arrow-right)
      ("\x1b;[D" . arrow-left)
      ;; arrows (SS3 form, app-keypad)
      ("\x1b;OA" . arrow-up)
      ("\x1b;OB" . arrow-down)
      ("\x1b;OC" . arrow-right)
      ("\x1b;OD" . arrow-left)
      ;; navigation
      ("\x1b;[H" . home)
      ("\x1b;[F" . end)
      ("\x1b;OH" . home)
      ("\x1b;OF" . end)
      ("\x1b;[1~" . home)
      ("\x1b;[4~" . end)
      ("\x1b;[2~" . insert)
      ("\x1b;[3~" . delete)
      ("\x1b;[5~" . pg-up)
      ("\x1b;[6~" . pg-down)
      ("\x1b;[Z"  . back-tab)
      ;; function keys (SS3 form for F1..F4)
      ("\x1b;OP" . f1)
      ("\x1b;OQ" . f2)
      ("\x1b;OR" . f3)
      ("\x1b;OS" . f4)
      ;; function keys (CSI tilde form for F5..F12)
      ("\x1b;[15~" . f5)
      ("\x1b;[17~" . f6)
      ("\x1b;[18~" . f7)
      ("\x1b;[19~" . f8)
      ("\x1b;[20~" . f9)
      ("\x1b;[21~" . f10)
      ("\x1b;[23~" . f11)
      ("\x1b;[24~" . f12)))

  (define xterm-caps
    (make-cap-set "xterm"
                  xterm-init-string
                  xterm-shutdown-string
                  xterm-keypad-on
                  xterm-keypad-off
                  xterm-input-keys))

  ;; ----- lookup ------------------------------------------------------------
  ;;
  ;; Match $TERM exactly first, then by prefix; fall back to xterm.  More
  ;; tables (and the binary terminfo parser) plug in here in stage 5.

  (define all-cap-sets (list xterm-caps))

  (define (caps-for-term term)
    (or (and term
             (let exact ((cs all-cap-sets))
               (cond
                ((null? cs) #f)
                ((string=? term (cap-set-name (car cs))) (car cs))
                (else (exact (cdr cs))))))
        (and term
             (let prefix ((cs all-cap-sets))
               (cond
                ((null? cs) #f)
                ((let ((n (cap-set-name (car cs))))
                   (and (fx>=? (string-length term) (string-length n))
                        (string=? n (substring term 0 (string-length n)))))
                 (car cs))
                (else (prefix (cdr cs))))))
        xterm-caps))
  )

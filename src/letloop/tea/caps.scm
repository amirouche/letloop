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
   linux-caps
   screen-caps
   tmux-caps
   rxvt-unicode-caps
   rxvt-256color-caps
   eterm-caps
   ;; xterm-style modifier-key sequences (Ctrl/Shift/Alt + arrow etc)
   xterm-mod-keys
   ;; lookup
   caps-for-term
   caps-for-term/strict
   all-cap-sets

   ~check-caps-xterm-shape
   ~check-caps-xterm-init-clears
   ~check-caps-xterm-shutdown-restores
   ~check-caps-xterm-input-keys-cover-arrows
   ~check-caps-for-term-exact
   ~check-caps-for-term-prefix
   ~check-caps-for-term-fallback
   ~check-caps-for-term-empty
   ~check-caps-linux-no-altscreen
   ~check-caps-tmux-aliased
   ~check-caps-rxvt-fkeys
   ~check-caps-mod-keys-shape)
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

  ;; ----- xterm modifier-key sequences -------------------------------------
  ;;
  ;; \e[1;Nx where N is the modifier code (2=shift, 3=alt, 5=ctrl, 6=ctrl+shift,
  ;; 7=ctrl+alt, 8=ctrl+alt+shift) and x is A/B/C/D/H/F for arrows/home/end,
  ;; or P/Q/R/S for F1..F4.  We only encode arrow + home/end here; F1..F4
  ;; with modifiers are rare and follow the same pattern callers can derive.
  ;;
  ;; The values are pairs (key-symbol . mod-list) that the parser merges
  ;; into a key-event with mods set.  Stored separately from input-keys so
  ;; consumers that don't care about modifiers can skip this table.

  (define xterm-mod-keys
    `(("\x1b;[1;2A" . (arrow-up    . (shift)))
      ("\x1b;[1;2B" . (arrow-down  . (shift)))
      ("\x1b;[1;2C" . (arrow-right . (shift)))
      ("\x1b;[1;2D" . (arrow-left  . (shift)))
      ("\x1b;[1;3A" . (arrow-up    . (meta)))
      ("\x1b;[1;3B" . (arrow-down  . (meta)))
      ("\x1b;[1;3C" . (arrow-right . (meta)))
      ("\x1b;[1;3D" . (arrow-left  . (meta)))
      ("\x1b;[1;5A" . (arrow-up    . (ctrl)))
      ("\x1b;[1;5B" . (arrow-down  . (ctrl)))
      ("\x1b;[1;5C" . (arrow-right . (ctrl)))
      ("\x1b;[1;5D" . (arrow-left  . (ctrl)))
      ("\x1b;[1;6A" . (arrow-up    . (ctrl shift)))
      ("\x1b;[1;6B" . (arrow-down  . (ctrl shift)))
      ("\x1b;[1;6C" . (arrow-right . (ctrl shift)))
      ("\x1b;[1;6D" . (arrow-left  . (ctrl shift)))
      ("\x1b;[1;7A" . (arrow-up    . (ctrl meta)))
      ("\x1b;[1;7B" . (arrow-down  . (ctrl meta)))
      ("\x1b;[1;7C" . (arrow-right . (ctrl meta)))
      ("\x1b;[1;7D" . (arrow-left  . (ctrl meta)))
      ("\x1b;[1;2H" . (home . (shift)))
      ("\x1b;[1;2F" . (end  . (shift)))
      ("\x1b;[1;5H" . (home . (ctrl)))
      ("\x1b;[1;5F" . (end  . (ctrl)))))

  (define xterm-caps
    (make-cap-set "xterm"
                  xterm-init-string
                  xterm-shutdown-string
                  xterm-keypad-on
                  xterm-keypad-off
                  xterm-input-keys))

  ;; ----- linux console ----------------------------------------------------
  ;;
  ;; The kernel's built-in console.  Init/shutdown are simpler — there is
  ;; no alt-screen support and no xterm window-title escapes.

  (define linux-init-string
    (string-append
     "\x1b;[?25l"      ; hide cursor
     "\x1b;[H\x1b;[J")) ; home + clear (note \e[J not \e[2J)

  (define linux-shutdown-string
    (string-append
     "\x1b;[m"
     "\x1b;[?25h"))

  (define linux-input-keys
    '(;; arrows — same as xterm CSI form
      ("\x1b;[A" . arrow-up)
      ("\x1b;[B" . arrow-down)
      ("\x1b;[C" . arrow-right)
      ("\x1b;[D" . arrow-left)
      ;; navigation
      ("\x1b;[1~" . home)
      ("\x1b;[4~" . end)
      ("\x1b;[2~" . insert)
      ("\x1b;[3~" . delete)
      ("\x1b;[5~" . pg-up)
      ("\x1b;[6~" . pg-down)
      ;; function keys — linux uses \e[[A..\e[[E for F1..F5, then tilde form
      ("\x1b;[[A" . f1)
      ("\x1b;[[B" . f2)
      ("\x1b;[[C" . f3)
      ("\x1b;[[D" . f4)
      ("\x1b;[[E" . f5)
      ("\x1b;[17~" . f6)
      ("\x1b;[18~" . f7)
      ("\x1b;[19~" . f8)
      ("\x1b;[20~" . f9)
      ("\x1b;[21~" . f10)
      ("\x1b;[23~" . f11)
      ("\x1b;[24~" . f12)))

  (define linux-caps
    (make-cap-set "linux"
                  linux-init-string
                  linux-shutdown-string
                  ""              ; no keypad mode on linux console
                  ""
                  linux-input-keys))

  ;; ----- screen / tmux ----------------------------------------------------
  ;;
  ;; screen and tmux pass most xterm escapes through but use \eO… for some
  ;; arrow forms.  The init/shutdown match xterm without title save/restore
  ;; (which screen swallows anyway).

  (define screen-init-string
    (string-append
     "\x1b;[?1049h"
     "\x1b;[?25l"
     "\x1b;[H\x1b;[2J"))

  (define screen-shutdown-string
    (string-append
     "\x1b;[m"
     "\x1b;[?25h"
     "\x1b;[?1049l"))

  (define screen-keypad-on  "\x1b;[?1h\x1b;=")
  (define screen-keypad-off "\x1b;[?1l\x1b;>")

  (define screen-input-keys
    '(("\x1b;[A"   . arrow-up)
      ("\x1b;[B"   . arrow-down)
      ("\x1b;[C"   . arrow-right)
      ("\x1b;[D"   . arrow-left)
      ("\x1b;OA"   . arrow-up)
      ("\x1b;OB"   . arrow-down)
      ("\x1b;OC"   . arrow-right)
      ("\x1b;OD"   . arrow-left)
      ("\x1b;[1~"  . home)
      ("\x1b;[4~"  . end)
      ("\x1b;[2~"  . insert)
      ("\x1b;[3~"  . delete)
      ("\x1b;[5~"  . pg-up)
      ("\x1b;[6~"  . pg-down)
      ("\x1b;OP"   . f1)
      ("\x1b;OQ"   . f2)
      ("\x1b;OR"   . f3)
      ("\x1b;OS"   . f4)
      ("\x1b;[15~" . f5)
      ("\x1b;[17~" . f6)
      ("\x1b;[18~" . f7)
      ("\x1b;[19~" . f8)
      ("\x1b;[20~" . f9)
      ("\x1b;[21~" . f10)
      ("\x1b;[23~" . f11)
      ("\x1b;[24~" . f12)))

  (define screen-caps
    (make-cap-set "screen"
                  screen-init-string
                  screen-shutdown-string
                  screen-keypad-on
                  screen-keypad-off
                  screen-input-keys))

  ;; tmux is a strict subset of screen for our purposes; reuse the table
  ;; under a different name so caps-for-term "tmux*" picks it up.
  (define tmux-caps
    (make-cap-set "tmux"
                  screen-init-string
                  screen-shutdown-string
                  screen-keypad-on
                  screen-keypad-off
                  screen-input-keys))

  ;; ----- rxvt-unicode (urxvt) ---------------------------------------------
  ;;
  ;; urxvt uses tilde-style for arrows when in app-keypad mode (\e[a / \e[b
  ;; for shift-arrow-up etc).  Function keys use \e[11~ … \e[24~.

  (define rxvt-unicode-input-keys
    '(("\x1b;[A"  . arrow-up)
      ("\x1b;[B"  . arrow-down)
      ("\x1b;[C"  . arrow-right)
      ("\x1b;[D"  . arrow-left)
      ("\x1b;OA"  . arrow-up)
      ("\x1b;OB"  . arrow-down)
      ("\x1b;OC"  . arrow-right)
      ("\x1b;OD"  . arrow-left)
      ("\x1b;[7~" . home)
      ("\x1b;[8~" . end)
      ("\x1b;[2~" . insert)
      ("\x1b;[3~" . delete)
      ("\x1b;[5~" . pg-up)
      ("\x1b;[6~" . pg-down)
      ;; function keys
      ("\x1b;[11~" . f1)
      ("\x1b;[12~" . f2)
      ("\x1b;[13~" . f3)
      ("\x1b;[14~" . f4)
      ("\x1b;[15~" . f5)
      ("\x1b;[17~" . f6)
      ("\x1b;[18~" . f7)
      ("\x1b;[19~" . f8)
      ("\x1b;[20~" . f9)
      ("\x1b;[21~" . f10)
      ("\x1b;[23~" . f11)
      ("\x1b;[24~" . f12)))

  (define rxvt-unicode-caps
    (make-cap-set "rxvt-unicode"
                  xterm-init-string         ; alt-screen + cursor-hide work
                  xterm-shutdown-string
                  xterm-keypad-on
                  xterm-keypad-off
                  rxvt-unicode-input-keys))

  (define rxvt-256color-caps
    (make-cap-set "rxvt-256color"
                  xterm-init-string
                  xterm-shutdown-string
                  xterm-keypad-on
                  xterm-keypad-off
                  rxvt-unicode-input-keys))

  ;; ----- Eterm -------------------------------------------------------------
  ;;
  ;; Eterm follows xterm closely; the small differences (function keys
  ;; mostly) are picked up here.

  (define eterm-input-keys
    `(,@(map (lambda (p) p) xterm-input-keys)
      ;; Eterm extra: F11/F12 use [11~ tilde form like rxvt
      ("\x1b;[11~" . f1)
      ("\x1b;[12~" . f2)))

  (define eterm-caps
    (make-cap-set "Eterm"
                  xterm-init-string
                  xterm-shutdown-string
                  xterm-keypad-on
                  xterm-keypad-off
                  eterm-input-keys))

  ;; ----- lookup ------------------------------------------------------------
  ;;
  ;; Match $TERM exactly first, then by prefix; fall back to xterm.  Order
  ;; matters: more specific names ("rxvt-256color") must come before less
  ;; specific ones ("rxvt-unicode" → "rxvt-uni…").

  (define all-cap-sets
    (list rxvt-256color-caps
          rxvt-unicode-caps
          tmux-caps
          screen-caps
          linux-caps
          eterm-caps
          xterm-caps))

  (define (caps-for-term term)
    ;; Returns the matching built-in cap-set, or xterm-caps as a final
    ;; fallback so callers always get a usable instance.  A separate
    ;; strict form is exposed for layered lookups (e.g., terminfo first).
    (or (caps-for-term/strict term) xterm-caps))

  (define (caps-for-term/strict term)
    (and term
         (or (let exact ((cs all-cap-sets))
               (cond
                ((null? cs) #f)
                ((string=? term (cap-set-name (car cs))) (car cs))
                (else (exact (cdr cs)))))
             (let prefix ((cs all-cap-sets))
               (cond
                ((null? cs) #f)
                ((let ((n (cap-set-name (car cs))))
                   (and (fx>=? (string-length term) (string-length n))
                        (string=? n (substring term 0 (string-length n)))))
                 (car cs))
                (else (prefix (cdr cs))))))))
  

  (include "letloop/tea/caps.check.scm")
  )

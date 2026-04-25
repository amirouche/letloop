#!chezscheme
;; (letloop tea sgr) — build VT/ANSI control sequences.
;;
;; All output is written to a textual port the caller supplies (typically a
;; string-output-port acting as bytebuf).  No I/O happens in this module.
;;
;; Output modes:
;;   normal      8 ANSI colors,  \e[3Nm / \e[4Nm  (bright via attr or N>=8)
;;   256/216/gs  256-palette,    \e[38;5;Nm / \e[48;5;Nm
;;   truecolor   24-bit RGB,     \e[38;2;R;G;Bm / \e[48;2;R;G;Bm
;;
;; Color value conventions (see (letloop tea base) — exposed there as helpers):
;;   normal:    integer 0..7 (or 'default for terminal default = #f here)
;;   256/216:   integer 0..255
;;   grayscale: integer 0..23
;;   truecolor: integer 0..#xFFFFFF (R<<16 | G<<8 | B)
;;
;; A color value of #f means "use terminal default" — emitted as 39/49.
;; Attributes are a list of symbols; output by build-attr-codes.
(library (letloop tea sgr)
  (export
   ;; primitives — write to a port
   sgr-reset!
   sgr-cursor!         ; move cursor (1-indexed terminal coords)
   sgr-clear!          ; clear screen + home cursor
   sgr-set-color!      ; fg + bg + attr list, dispatched on output-mode
   ;; toggles
   sgr-alt-screen-on!     sgr-alt-screen-off!
   sgr-hide-cursor!       sgr-show-cursor!
   sgr-bracketed-paste-on!  sgr-bracketed-paste-off!
   sgr-focus-events-on!     sgr-focus-events-off!
   sgr-mouse-on!            sgr-mouse-off!
   ;; attribute codes
   attr-symbol->code
   ;; helpers
   write-csi)
  (import (chezscheme))

  (define ESC #\x1b)

  (define (write-esc port) (write-char ESC port))

  (define (write-csi port)
    (write-char ESC port)
    (write-char #\[ port))

  (define (write-int port n) (display n port))

  ;; ----- attribute table ---------------------------------------------------

  (define (attr-symbol->code sym)
    (case sym
      ((bold)        1)
      ((dim)         2)
      ((italic)      3)
      ((underline)   4)
      ((blink)       5)
      ((reverse)     7)
      ((invisible)   8)
      ((strikeout)   9)
      ((underline-2) 21)
      ((overline)    53)
      (else
       (error 'attr-symbol->code "unknown attribute" sym))))

  ;; ----- primitives --------------------------------------------------------

  (define (sgr-reset! port)
    (write-csi port) (write-char #\m port))

  (define (sgr-cursor! port x y)
    ;; x,y are 0-indexed; ANSI is 1-indexed.
    (write-csi port)
    (write-int port (fx+ y 1))
    (write-char #\; port)
    (write-int port (fx+ x 1))
    (write-char #\H port))

  (define (sgr-clear! port)
    (write-csi port) (write-char #\H port)
    (write-csi port) (write-char #\2 port) (write-char #\J port))

  ;; ----- color emission ----------------------------------------------------

  (define (write-attr-codes! port attrs)
    (for-each
     (lambda (a)
       (write-char #\; port)
       (write-int port (attr-symbol->code a)))
     attrs))

  (define (write-fg-normal! port c)
    (cond
     ((not c)         (write-int port 39))
     ((fx<? c 8)      (write-int port (fx+ 30 c)))
     (else            (write-int port (fx+ 90 (fx- c 8))))))

  (define (write-bg-normal! port c)
    (cond
     ((not c)         (write-int port 49))
     ((fx<? c 8)      (write-int port (fx+ 40 c)))
     (else            (write-int port (fx+ 100 (fx- c 8))))))

  (define (write-fg-256! port c)
    (cond
     ((not c) (write-int port 39))
     (else    (write-int port 38) (write-char #\; port)
              (write-int port 5)  (write-char #\; port)
              (write-int port c))))

  (define (write-bg-256! port c)
    (cond
     ((not c) (write-int port 49))
     (else    (write-int port 48) (write-char #\; port)
              (write-int port 5)  (write-char #\; port)
              (write-int port c))))

  (define (write-fg-truecolor! port c)
    (cond
     ((not c) (write-int port 39))
     (else
      (let ((r (fxand (fxsrl c 16) #xff))
            (g (fxand (fxsrl c 8)  #xff))
            (b (fxand c            #xff)))
        (write-int port 38) (write-char #\; port)
        (write-int port 2)  (write-char #\; port)
        (write-int port r)  (write-char #\; port)
        (write-int port g)  (write-char #\; port)
        (write-int port b)))))

  (define (write-bg-truecolor! port c)
    (cond
     ((not c) (write-int port 49))
     (else
      (let ((r (fxand (fxsrl c 16) #xff))
            (g (fxand (fxsrl c 8)  #xff))
            (b (fxand c            #xff)))
        (write-int port 48) (write-char #\; port)
        (write-int port 2)  (write-char #\; port)
        (write-int port r)  (write-char #\; port)
        (write-int port g)  (write-char #\; port)
        (write-int port b)))))

  (define (sgr-set-color! port mode fg bg attrs)
    ;; Emits one CSI ... m sequence with attrs first, then fg, then bg.
    ;; Reset is emitted when both fg and bg are #f and attrs is empty.
    (cond
     ((and (not fg) (not bg) (null? attrs))
      (sgr-reset! port))
     (else
      (write-csi port)
      ;; lead with 0 so we shed any prior state
      (write-int port 0)
      (write-attr-codes! port attrs)
      (write-char #\; port)
      (case mode
        ((normal)
         (write-fg-normal! port fg)
         (write-char #\; port)
         (write-bg-normal! port bg))
        ((256 216 grayscale)
         (let ((fg* (and fg (case mode
                              ((216)       (fx+ 16 fg))
                              ((grayscale) (fx+ 232 fg))
                              (else        fg))))
               (bg* (and bg (case mode
                              ((216)       (fx+ 16 bg))
                              ((grayscale) (fx+ 232 bg))
                              (else        bg)))))
           (write-fg-256! port fg*)
           (write-char #\; port)
           (write-bg-256! port bg*)))
        ((truecolor)
         (write-fg-truecolor! port fg)
         (write-char #\; port)
         (write-bg-truecolor! port bg))
        (else
         (error 'sgr-set-color! "unknown output mode" mode)))
      (write-char #\m port))))

  ;; ----- toggles -----------------------------------------------------------

  (define (write-decset! port n)
    (write-csi port) (write-char #\? port) (write-int port n) (write-char #\h port))

  (define (write-decreset! port n)
    (write-csi port) (write-char #\? port) (write-int port n) (write-char #\l port))

  (define (sgr-alt-screen-on!       port) (write-decset!   port 1049))
  (define (sgr-alt-screen-off!      port) (write-decreset! port 1049))
  (define (sgr-hide-cursor!         port) (write-decreset! port 25))
  (define (sgr-show-cursor!         port) (write-decset!   port 25))
  (define (sgr-bracketed-paste-on!  port) (write-decset!   port 2004))
  (define (sgr-bracketed-paste-off! port) (write-decreset! port 2004))
  (define (sgr-focus-events-on!     port) (write-decset!   port 1004))
  (define (sgr-focus-events-off!    port) (write-decreset! port 1004))

  ;; Mouse: enable X10 (1000) + button-event tracking (1002) + any-event
  ;; (1003) + SGR encoding (1006) — termbox2's chosen set.
  (define (sgr-mouse-on! port)
    (write-decset! port 1000)
    (write-decset! port 1002)
    (write-decset! port 1003)
    (write-decset! port 1006))

  (define (sgr-mouse-off! port)
    (write-decreset! port 1006)
    (write-decreset! port 1003)
    (write-decreset! port 1002)
    (write-decreset! port 1000))
  )

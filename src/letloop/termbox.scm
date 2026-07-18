#!chezscheme
;; (letloop termbox) — compatibility shim over (letloop tea).
;;
;; Preserves the bit-for-bit surface of the previous libtermbox2 binding so
;; existing consumers (notably `(letloop review)`) keep working without any
;; edits.  Internally:
;;
;;   - one hidden tea instance, opened on tb-init;
;;   - the shim turns each tea event into the legacy ev-* fields the C
;;     binding exposed (ev-type / ev-key / ev-ch / ev-mod / ev-w / ev-h);
;;   - colors map 1..8 onto the named ANSI palette (TB-RED=2 etc) and the
;;     active tea output mode is 'normal so those numbers pass through
;;     unchanged.
;;
;; New code should import (letloop tea) directly — the record-based
;; instance API is more idiomatic and exposes mouse, focus, paste, and
;; live output-mode switching that this shim doesn't surface.
(library (letloop termbox)
  (export tb-init tb-shutdown tb-width tb-height
          tb-clear tb-present tb-print tb-set-cell
          tb-poll tb-ev-type tb-ev-mod tb-ev-key tb-ev-ch
          tb-ev-w tb-ev-h
          TB-EVENT-KEY TB-EVENT-RESIZE
          TB-KEY-ESC TB-KEY-ENTER TB-KEY-BACKSPACE TB-KEY-BACKSPACE2 TB-KEY-TAB
          TB-KEY-ARROW-UP TB-KEY-ARROW-DOWN TB-KEY-ARROW-LEFT TB-KEY-ARROW-RIGHT
          TB-KEY-PGUP TB-KEY-PGDN
          TB-DEFAULT TB-BLACK TB-RED TB-GREEN TB-YELLOW TB-BLUE TB-MAGENTA TB-CYAN TB-WHITE)
  (import (chezscheme)
          (letloop tea)
          (letloop tea input))

  ;; ----- legacy constants --------------------------------------------------

  (define TB-EVENT-KEY    1)
  (define TB-EVENT-RESIZE 2)

  (define TB-KEY-ESC         27)
  (define TB-KEY-ENTER       13)
  (define TB-KEY-BACKSPACE   127)
  (define TB-KEY-BACKSPACE2  8)
  (define TB-KEY-TAB         9)
  (define TB-KEY-ARROW-UP    65517)
  (define TB-KEY-ARROW-DOWN  65516)
  (define TB-KEY-ARROW-LEFT  65515)
  (define TB-KEY-ARROW-RIGHT 65514)
  (define TB-KEY-PGUP        65519)
  (define TB-KEY-PGDN        65518)

  (define TB-DEFAULT  0)
  (define TB-BLACK    1)
  (define TB-RED      2)
  (define TB-GREEN    3)
  (define TB-YELLOW   4)
  (define TB-BLUE     5)
  (define TB-MAGENTA  6)
  (define TB-CYAN     7)
  (define TB-WHITE    8)

  ;; ----- hidden global state ----------------------------------------------

  (define *tb*       #f)
  (define *ev-type*  0)
  (define *ev-key*   0)
  (define *ev-ch*    0)
  (define *ev-mod*   0)
  (define *ev-w*     0)
  (define *ev-h*     0)

  ;; ----- color translation -------------------------------------------------
  ;; legacy uses 1..8 for black..white plus 0 = default; tea in 'normal mode
  ;; uses 1..8 for the same 8 colors plus 0 = default — pass through.

  (define (tb-color->tea c)
    (cond ((fx=? c 0) #f)
          (else (fx- c 1))))   ; 1->0 (black), 2->1 (red) … per ANSI 30+i

  ;; ----- key symbol → legacy code -----------------------------------------

  (define (key-symbol->code sym)
    (case sym
      ((esc)         TB-KEY-ESC)
      ((enter)       TB-KEY-ENTER)
      ((backspace)   TB-KEY-BACKSPACE)
      ((tab)         TB-KEY-TAB)
      ((arrow-up)    TB-KEY-ARROW-UP)
      ((arrow-down)  TB-KEY-ARROW-DOWN)
      ((arrow-left)  TB-KEY-ARROW-LEFT)
      ((arrow-right) TB-KEY-ARROW-RIGHT)
      ((pg-up)       TB-KEY-PGUP)
      ((pg-down)     TB-KEY-PGDN)
      ;; termbox2 function/navigation codes count down from 0xFFFF
      ((f1) 65535) ((f2) 65534) ((f3)  65533) ((f4)  65532)
      ((f5) 65531) ((f6) 65530) ((f7)  65529) ((f8)  65528)
      ((f9) 65527) ((f10) 65526) ((f11) 65525) ((f12) 65524)
      ((insert) 65523)
      ((delete) 65522)
      ((home)   65521)
      ((end)    65520)
      ;; control keys carry their ASCII code, as in the C binding
      ((ctrl-space)         0)
      ((ctrl-backslash)     28)
      ((ctrl-bracket-right) 29)
      ((ctrl-caret)         30)
      ((ctrl-underscore)    31)
      (else (or (ctrl-letter->code sym) 0))))

  (define (ctrl-letter->code sym)
    ;; ctrl-a .. ctrl-z → 1 .. 26
    (let ((s (symbol->string sym)))
      (and (fx=? (string-length s) 6)
           (string=? (substring s 0 5) "ctrl-")
           (let ((c (char->integer (string-ref s 5))))
             (and (fx>=? c 97) (fx<=? c 122) (fx- c 96))))))

  ;; legacy modifier bits: TB_MOD_ALT=1 TB_MOD_CTRL=2 TB_MOD_SHIFT=4;
  ;; tea spells alt 'meta.
  (define (mods->tb mods)
    (fold-left (lambda (acc m)
                 (fxior acc (case m
                              ((meta alt) 1)
                              ((ctrl)     2)
                              ((shift)    4)
                              (else       0))))
               0 (or mods '())))

  ;; ----- lifecycle ---------------------------------------------------------

  (define (tb-init)
    (set! *tb* (tea-open '((output-mode . normal))))
    0)

  (define (tb-shutdown)
    (when *tb*
      (tea-close *tb*)
      (set! *tb* #f))
    0)

  (define (tb-width)  (if *tb* (tea-width  *tb*) 0))
  (define (tb-height) (if *tb* (tea-height *tb*) 0))
  (define (tb-clear)
    (when *tb* (tea-clear *tb*))
    0)
  (define (tb-present)
    (when *tb* (tea-present *tb*))
    0)

  ;; tea-print expects (tea x y fg bg str); legacy is (x y fg bg str).
  (define (tb-print x y fg bg s)
    (when *tb*
      (tea-print *tb* x y (tb-color->tea fg) (tb-color->tea bg) s))
    0)

  (define (tb-set-cell x y ch fg bg)
    (when *tb*
      (tea-set-cell *tb* x y ch
                    (tb-color->tea fg) (tb-color->tea bg)))
    0)

  ;; ----- event loop --------------------------------------------------------
  ;;
  ;; tb-poll blocks until exactly one event lands, fills the *ev-* slots,
  ;; and returns 0.  We translate tea event records back to the legacy
  ;; layout.

  (define (tb-poll)
    (let ((e (and *tb* (tea-poll *tb*))))
      (set! *ev-type* 0)
      (set! *ev-key*  0)
      (set! *ev-ch*   0)
      (set! *ev-mod*  0)
      (set! *ev-w*    0)
      (set! *ev-h*    0)
      (cond
       ((not e) 0)
       ((key-event? e)
        (set! *ev-type* TB-EVENT-KEY)
        (set! *ev-mod* (mods->tb (key-event-mods e)))
        (let ((sym (key-event-key e))
              (ch  (key-event-ch  e)))
          (cond
           (sym (set! *ev-key* (key-symbol->code sym)))
           (ch  (set! *ev-ch*  ch))))
        0)
       ((and (pair? e) (eq? (car e) 'resize))
        (set! *ev-type* TB-EVENT-RESIZE)
        (set! *ev-w* (cadr e))
        (set! *ev-h* (cddr e))
        0)
       (else 0))))

  (define (tb-ev-type) *ev-type*)
  (define (tb-ev-key)  *ev-key*)
  (define (tb-ev-ch)   *ev-ch*)
  (define (tb-ev-mod)  *ev-mod*)
  (define (tb-ev-w)    *ev-w*)
  (define (tb-ev-h)    *ev-h*)
  )

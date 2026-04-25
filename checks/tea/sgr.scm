(library (tea sgr)

  (export
   ~check-sgr-cursor
   ~check-sgr-clear
   ~check-sgr-reset
   ~check-sgr-color-normal
   ~check-sgr-color-bright
   ~check-sgr-color-default
   ~check-sgr-color-256
   ~check-sgr-color-216
   ~check-sgr-color-grayscale
   ~check-sgr-color-truecolor
   ~check-sgr-attrs
   ~check-sgr-toggles
   ~check-sgr-mouse-on)

  (import (chezscheme)
          (letloop tea sgr))

  (define (build f . args)
    (let-values (((p get) (open-string-output-port)))
      (apply f p args)
      (get)))

  (define-syntax expect
    (syntax-rules ()
      ((_ a b)
       (let ((a* a) (b* b))
         (or (string=? a* b*)
             (begin (display (list 'expected b* 'got a*)) (newline) #f))))))

  (define (~check-sgr-cursor)
    ;; 0,0 -> CSI 1;1H
    (expect (build sgr-cursor! 0 0) "\x1b;[1;1H"))

  (define (~check-sgr-clear)
    (expect (build sgr-clear!) "\x1b;[H\x1b;[2J"))

  (define (~check-sgr-reset)
    (expect (build sgr-reset!) "\x1b;[m"))

  (define (~check-sgr-color-normal)
    ;; fg=red(1), bg=blue(4), no attrs, normal mode
    (expect (build sgr-set-color! 'normal 1 4 '())
            "\x1b;[0;31;44m"))

  (define (~check-sgr-color-bright)
    ;; fg=11 (bright yellow) -> 90+(11-8)=93
    (expect (build sgr-set-color! 'normal 11 #f '())
            "\x1b;[0;93;49m"))

  (define (~check-sgr-color-default)
    ;; both default + no attrs collapses to plain reset
    (expect (build sgr-set-color! 'normal #f #f '())
            "\x1b;[m"))

  (define (~check-sgr-color-256)
    (expect (build sgr-set-color! '256 166 17 '())
            "\x1b;[0;38;5;166;48;5;17m"))

  (define (~check-sgr-color-216)
    ;; 216 mode adds offset 16
    (expect (build sgr-set-color! '216 0 5 '())
            "\x1b;[0;38;5;16;48;5;21m"))

  (define (~check-sgr-color-grayscale)
    ;; grayscale adds offset 232
    (expect (build sgr-set-color! 'grayscale 0 23 '())
            "\x1b;[0;38;5;232;48;5;255m"))

  (define (~check-sgr-color-truecolor)
    ;; #xd75f00 dark orange fg, default bg
    (expect (build sgr-set-color! 'truecolor #xd75f00 #f '())
            "\x1b;[0;38;2;215;95;0;49m"))

  (define (~check-sgr-attrs)
    ;; bold + underline, fg red, default bg
    (expect (build sgr-set-color! 'normal 1 #f '(bold underline))
            "\x1b;[0;1;4;31;49m"))

  (define (~check-sgr-toggles)
    (and
     (string=? (build sgr-alt-screen-on!)        "\x1b;[?1049h")
     (string=? (build sgr-alt-screen-off!)       "\x1b;[?1049l")
     (string=? (build sgr-hide-cursor!)          "\x1b;[?25l")
     (string=? (build sgr-show-cursor!)          "\x1b;[?25h")
     (string=? (build sgr-bracketed-paste-on!)   "\x1b;[?2004h")
     (string=? (build sgr-bracketed-paste-off!)  "\x1b;[?2004l")
     (string=? (build sgr-focus-events-on!)      "\x1b;[?1004h")
     (string=? (build sgr-focus-events-off!)     "\x1b;[?1004l")))

  (define (~check-sgr-mouse-on)
    ;; X10 + button-event + any-event + SGR encoding, in that order
    (expect (build sgr-mouse-on!)
            "\x1b;[?1000h\x1b;[?1002h\x1b;[?1003h\x1b;[?1006h")))

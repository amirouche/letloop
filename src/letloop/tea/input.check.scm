;; Checks for (letloop tea input), driving the module through its exported
;; API the way a caller would.  Included at the tail of the library;
;; discovered by `make check` via the ~check- exports.


  (define (feed-bytes p byte-list)
    (let loop ((bs byte-list) (events '()))
      (cond
       ((null? bs) (reverse events))
       (else
        (let ((e (input-parser-feed! p (car bs))))
          (loop (cdr bs)
                (if e (cons e events) events)))))))

  (define (feed-str p str)
    (feed-bytes p (bytevector->u8-list (string->utf8 str))))

  (define (~check-input-printable-ascii)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-bytes p '(65))))
      (and (= (length es) 1)
           (key-event? (car es))
           (= (key-event-ch (car es)) 65)
           (not (key-event-key (car es))))))

  (define (~check-input-control-tab-enter)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-bytes p '(9 13))))
      (and (= (length es) 2)
           (eq? (key-event-key (car es)) 'tab)
           (eq? (key-event-key (cadr es)) 'enter))))

  (define (~check-input-ctrl-letter)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-bytes p '(3))))   ; ctrl-c
      (eq? (key-event-key (car es)) 'ctrl-c)))

  (define (~check-input-arrow-key)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[A")))
      (and (= (length es) 1)
           (eq? (key-event-key (car es)) 'arrow-up))))

  (define (~check-input-pg-up)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[5~")))
      (eq? (key-event-key (car es)) 'pg-up)))

  (define (~check-input-utf8-multibyte)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "é")))
      (and (= (length es) 1)
           (= (key-event-ch (car es)) #xE9))))

  (define (~check-input-lone-esc-flush)
    ;; After a single ESC byte with no continuation, flush emits 'esc.
    (let ((p (make-input-parser xterm-caps)))
      (and (not (input-parser-feed! p #x1B))
           (let ((e (input-parser-flush! p)))
             (and e (eq? (key-event-key e) 'esc))))))

  (define (~check-input-alt-letter)
    ;; ESC + 'a' (no other prefix matches \ea) -> alt-a
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-bytes p '(#x1B 97))))
      (and (= (length es) 1)
           (= (key-event-ch (car es)) 97)
           (equal? (key-event-mods (car es)) '(meta)))))

  (define (~check-input-mouse-sgr-press)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[<0;5;7M")))
      (and (= (length es) 1)
           (let ((e (car es)))
             (and (not (key-event? e))
                  (not (paste-event? e))
                  (not (focus-event? e)))))))

  (define (~check-input-mouse-x10)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-bytes p
                 (list #x1B (char->integer #\[) (char->integer #\M)
                       32 33 33))))
      (= (length es) 1)))

  (define (~check-input-focus-in)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[I")))
      (and (= (length es) 1)
           (focus-event? (car es))
           (focus-event-in? (car es)))))

  (define (~check-input-paste-end-roundtrip)
    ;; Bracketed paste of "Hi": \e[200~Hi\e[201~
    ;; Expect 2 events: paste-start, paste-end with data="Hi".
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[200~Hi\x1b;[201~")))
      (and (= (length es) 2)
           (paste-event? (car es))
           (not (paste-event-data (car es)))
           (not (paste-event-end? (car es)))
           (paste-event? (cadr es))
           (paste-event-end? (cadr es))
           (string=? (paste-event-data (cadr es)) "Hi"))))

  (define (~check-input-paste-with-stray-esc)
    ;; Pasted content that contains ESC + non-sentinel bytes must round-trip
    ;; verbatim — this is the case the byte-by-byte parser had to get
    ;; right when the inline sentinel scan partially matched.
    (let* ((p (make-input-parser xterm-caps))
           ;; \e[200~  X \e Y  \e[201~ — content is "X\eY"
           (es (feed-bytes p
                 (append
                  (bytevector->u8-list (string->utf8 "\x1b;[200~"))
                  '(88 #x1B 89)   ; "X\eY"
                  (bytevector->u8-list (string->utf8 "\x1b;[201~"))))))
      (and (= (length es) 2)
           (string=? (paste-event-data (cadr es)) "X\x1b;Y"))))

  (define (~check-input-paste-utf8)
    ;; Pasted multibyte text returns as a proper UTF-8 string.
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[200~héllo\x1b;[201~")))
      (and (= (length es) 2)
           (string=? (paste-event-data (cadr es)) "héllo"))))

  (define (~check-input-ctrl-arrow-up)
    ;; Modifier-key sequence \e[1;5A = ctrl + arrow-up
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[1;5A")))
      (and (= (length es) 1)
           (eq? (key-event-key (car es)) 'arrow-up)
           (equal? (key-event-mods (car es)) '(ctrl)))))

  (define (~check-input-shift-home)
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[1;2H")))
      (and (= (length es) 1)
           (eq? (key-event-key (car es)) 'home)
           (equal? (key-event-mods (car es)) '(shift)))))

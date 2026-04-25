(library (tea input)

  (export
   ~check-input-printable-ascii
   ~check-input-control-tab-enter
   ~check-input-ctrl-letter
   ~check-input-arrow-key
   ~check-input-pg-up
   ~check-input-utf8-multibyte
   ~check-input-lone-esc-flush
   ~check-input-alt-letter
   ~check-input-mouse-sgr-press
   ~check-input-mouse-x10
   ~check-input-focus-in
   ~check-input-paste-end-roundtrip)

  (import (chezscheme)
          (letloop tea input)
          (letloop tea caps))

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
    (let* ((p (make-input-parser xterm-caps))
           (es (feed-str p "\x1b;[200~Hi\x1b;[201~")))
      ;; Expect: data H, data i, paste-end.
      (and (= (length es) 3)
           (paste-event? (car es))
           (= (paste-event-data (car es)) 72)
           (paste-event? (caddr es))
           (paste-event-end? (caddr es))))))

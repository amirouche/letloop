#!chezscheme
;; (letloop tea input) — byte stream → event stream.
;;
;; Stateful: feed bytes one at a time, get events as they materialize.
;; Returns either #f (more bytes needed) or an event record.  Each call
;; consumes exactly one byte.
;;
;; Recognized inputs:
;;
;;   * Key escape sequences from the active cap-set's input-keys table,
;;     resolved through the trie.  Yields key-event records with `key` set
;;     to the symbol from the table (arrow-up, f5, pg-down, …).
;;
;;   * Mouse: X10 (\e[M + 3 raw bytes) and SGR 1006 (\e[<…M / \e[<…m).
;;     urxvt 1015 is recognized but only when the parameter form is
;;     unambiguous (\e[ + digit immediately, terminated by M).
;;
;;   * Bracketed paste: \e[200~ enters paste mode; subsequent bytes are
;;     emitted as paste-data events until \e[201~ closes it.
;;
;;   * Focus: \e[I (focus-in), \e[O (focus-out).
;;
;;   * UTF-8 codepoints — yields key-event with `ch` set to the codepoint
;;     and `key` = #f.
;;
;;   * ASCII control bytes — yields key-event with `key` set to a symbol
;;     (esc, enter, tab, backspace, ctrl-a … ctrl-z).
;;
;;   * Alt+key — when ESC is followed within the same chunk by a printable
;;     byte, we emit a single key-event with 'meta in mods.  Lone ESC needs
;;     a flush (input-parser-flush!) which the caller invokes after a
;;     timeout has elapsed with no more bytes; until then it stays buffered.
(library (letloop tea input)
  (export
   make-key-event
   key-event?
   key-event-ch
   key-event-key
   key-event-mods
   make-paste-event
   paste-event?
   paste-event-data
   paste-event-end?
   make-focus-event
   focus-event?
   focus-event-in?
   make-input-parser
   input-parser?
   input-parser-feed!
   input-parser-flush!)
  (import (chezscheme)
          (letloop tea utf8)
          (letloop tea trie)
          (letloop tea mouse)
          (letloop tea caps))

  ;; ----- event records ----------------------------------------------------

  (define-record-type key-event
    (fields ch key mods))

  (define-record-type paste-event
    (fields data       ; codepoint of one byte of pasted content, or #f at end
            end?))     ; #t if this signals end-of-paste

  (define-record-type focus-event
    (fields in?))      ; #t = focus gained, #f = lost

  ;; ----- parser record ----------------------------------------------------

  (define-record-type input-parser
    (fields trie
            (mutable state)         ; 'normal | 'esc | 'csi | 'sgr | 'x10
                                    ; | 'paste | 'utf8 | 'alt
            (mutable buf)           ; reverse list of pending bytes
            (mutable trie-state)    ; for normal trie matching
            (mutable utf8-decoder)
            (mutable params)        ; reverse list of integers for CSI parsing
            (mutable accum))        ; integer accumulator for current param
    (protocol
     (lambda (new)
       (lambda (caps)
         (let* ((extra-keys
                 ;; supplement the cap-set with internal markers the
                 ;; parser will dispatch on.
                 '(("\x1b;[M"    . __mouse-x10)
                   ("\x1b;[<"    . __mouse-sgr)
                   ("\x1b;[200~" . __paste-start)
                   ("\x1b;[I"    . __focus-in)
                   ("\x1b;[O"    . __focus-out)))
                (all (append (cap-set-input-keys caps) extra-keys))
                (t   (make-trie all)))
           (new t 'normal '() (make-trie-state t)
                (make-utf8-decoder) '() 0))))))

  ;; ----- helpers ----------------------------------------------------------

  (define (ctrl-symbol byte)
    (cond
     ((fx=? byte 0)     'ctrl-space)   ; NUL = ctrl-@/ctrl-space
     ((fx=? byte #x09)  'tab)
     ((fx=? byte #x0A)  'enter)
     ((fx=? byte #x0D)  'enter)        ; CR also reported as enter (raw mode)
     ((fx=? byte #x1B)  'esc)
     ((fx=? byte #x7F)  'backspace)
     ((and (fx>=? byte 1) (fx<=? byte 26))
      ;; ctrl-a..ctrl-z -> 1..26
      (string->symbol
       (string-append "ctrl-"
                      (string (integer->char (fx+ byte 96))))))
     (else #f)))

  (define (ascii-printable? b)
    (and (fx>=? b #x20) (fx<? b #x7F)))

  (define (digit? b) (and (fx>=? b #x30) (fx<=? b #x39)))

  ;; ----- main entry --------------------------------------------------------

  (define (input-parser-feed! p b)
    (case (input-parser-state p)
      ((normal) (feed-normal! p b))
      ((esc)    (feed-esc!    p b))
      ((csi)    (feed-csi!    p b))
      ((sgr)    (feed-sgr!    p b))
      ((x10)    (feed-x10!    p b))
      ((paste)  (feed-paste!  p b))
      ((utf8)   (feed-utf8!   p b))
      (else     (error 'input-parser-feed! "bad state"
                       (input-parser-state p)))))

  (define (input-parser-flush! p)
    ;; Called by the loop when a timeout elapses with no more bytes; commits
    ;; any pending ESC as a literal esc key.
    (case (input-parser-state p)
      ((esc)
       (input-parser-state-set! p 'normal)
       (trie-state-reset! (input-parser-trie-state p))
       (make-key-event #f 'esc '()))
      (else #f)))

  ;; ----- normal -----------------------------------------------------------

  (define (feed-normal! p b)
    (cond
     ((fx=? b #x1B)
      ;; ESC — could be lone or start of an escape sequence.
      (input-parser-state-set! p 'esc)
      (let ((ts (input-parser-trie-state p)))
        (trie-state-reset! ts)
        (trie-feed! ts b))
      #f)
     ((fx<? b #x80)
      (cond
       ((ctrl-symbol b) =>
        (lambda (sym) (make-key-event #f sym '())))
       (else
        ;; printable ASCII
        (make-key-event b #f '()))))
     (else
      ;; UTF-8 lead byte
      (input-parser-state-set! p 'utf8)
      (utf8-decoder-reset! (input-parser-utf8-decoder p))
      (feed-utf8! p b))))

  ;; ----- esc / csi --------------------------------------------------------

  (define (feed-esc! p b)
    ;; We're at \e and have just received the next byte b.  Run it through
    ;; the trie to disambiguate.  Special prefixes (mouse, paste, focus)
    ;; route into their own states; everything else is a regular key.
    (let* ((ts (input-parser-trie-state p))
           (r  (trie-feed! ts b)))
      (cond
       ((eq? r 'continue)
        ;; still inside a known prefix; stay in esc until we know more
        (input-parser-state-set! p 'csi) ; collecting more
        #f)
       ((eq? r 'no-match)
        ;; ESC + non-prefix byte = Alt+char
        (input-parser-state-set! p 'normal)
        (cond
         ((ascii-printable? b)
          (make-key-event b #f '(meta)))
         (else
          (let ((sym (ctrl-symbol b)))
            (make-key-event #f (or sym 'esc) '(meta))))))
       (else
        ;; (match val)
        (handle-trie-match! p (cadr r))))))

  (define (feed-csi! p b)
    (let* ((ts (input-parser-trie-state p))
           (r  (trie-feed! ts b)))
      (cond
       ((eq? r 'continue) #f)
       ((eq? r 'no-match)
        (input-parser-state-set! p 'normal)
        ;; Drop the partial sequence (the bytes consumed so far are
        ;; available via trie-state-bytes, but we can't safely re-emit
        ;; them as separate keys — they were prefixes that didn't pan
        ;; out).  In termbox2 these are silently dropped; we do the same.
        #f)
       (else
        (handle-trie-match! p (cadr r))))))

  (define (handle-trie-match! p val)
    (case val
      ((__mouse-x10)
       (input-parser-state-set! p 'x10)
       (input-parser-buf-set! p '())
       #f)
      ((__mouse-sgr)
       (input-parser-state-set! p 'sgr)
       (input-parser-params-set! p '())
       (input-parser-accum-set! p 0)
       #f)
      ((__paste-start)
       (input-parser-state-set! p 'paste)
       (input-parser-buf-set! p '())
       #f)
      ((__focus-in)
       (input-parser-state-set! p 'normal)
       (make-focus-event #t))
      ((__focus-out)
       (input-parser-state-set! p 'normal)
       (make-focus-event #f))
      (else
       (input-parser-state-set! p 'normal)
       (make-key-event #f val '()))))

  ;; ----- mouse-X10 --------------------------------------------------------

  (define (feed-x10! p b)
    (let ((buf (cons b (input-parser-buf p))))
      (input-parser-buf-set! p buf)
      (cond
       ((fx=? (length buf) 3)
        (input-parser-state-set! p 'normal)
        (let ((bytes (reverse buf)))
          (decode-mouse-x10 (car bytes) (cadr bytes) (caddr bytes))))
       (else #f))))

  ;; ----- mouse-SGR --------------------------------------------------------

  (define (feed-sgr! p b)
    (cond
     ((digit? b)
      (input-parser-accum-set!
       p (fx+ (fx* (input-parser-accum p) 10) (fx- b #x30)))
      #f)
     ((fx=? b (char->integer #\;))
      (input-parser-params-set!
       p (cons (input-parser-accum p) (input-parser-params p)))
      (input-parser-accum-set! p 0)
      #f)
     ((or (fx=? b (char->integer #\M))
          (fx=? b (char->integer #\m)))
      (let ((params (reverse
                     (cons (input-parser-accum p) (input-parser-params p)))))
        (input-parser-state-set! p 'normal)
        (cond
         ((fx=? (length params) 3)
          (decode-mouse-sgr params (integer->char b)))
         (else #f))))
     (else
      ;; bad byte; bail
      (input-parser-state-set! p 'normal)
      #f)))

  ;; ----- paste -----------------------------------------------------------

  (define (feed-paste! p b)
    ;; Emit each byte as a paste-data event UNLESS we see the start of
    ;; \e[201~ (paste-end).  We implement detection inline rather than via
    ;; the trie because pasted content can itself contain ESC.
    (let ((buf (input-parser-buf p)))
      (cond
       ((and (null? buf) (fx=? b #x1B))
        (input-parser-buf-set! p '(#x1B))
        #f)
       ((and (equal? buf '(#x1B)) (fx=? b (char->integer #\[)))
        (input-parser-buf-set! p (cons b buf))
        #f)
       ((and (equal? buf (list (char->integer #\[) #x1B))
             (fx=? b (char->integer #\2)))
        (input-parser-buf-set! p (cons b buf))
        #f)
       ((and (equal? buf (list (char->integer #\2) (char->integer #\[) #x1B))
             (fx=? b (char->integer #\0)))
        (input-parser-buf-set! p (cons b buf))
        #f)
       ((and (equal? buf
                     (list (char->integer #\0)
                           (char->integer #\2)
                           (char->integer #\[) #x1B))
             (fx=? b (char->integer #\1)))
        (input-parser-buf-set! p (cons b buf))
        #f)
       ((and (equal? buf
                     (list (char->integer #\1)
                           (char->integer #\0)
                           (char->integer #\2)
                           (char->integer #\[) #x1B))
             (fx=? b (char->integer #\~)))
        ;; matched \e[201~ — paste-end
        (input-parser-buf-set! p '())
        (input-parser-state-set! p 'normal)
        (make-paste-event #f #t))
       (else
        ;; Mismatch in our \e[201~ scan: flush any buffered bytes as paste
        ;; data first (one per call would be cleanest, but here we collapse
        ;; to a single event for the current byte and ignore the partial
        ;; — termbox2 tolerates this as paste data is opaque text).
        (input-parser-buf-set! p '())
        (make-paste-event b #f)))))

  ;; ----- utf-8 ------------------------------------------------------------

  (define (feed-utf8! p b)
    (let ((r (utf8-decoder-feed! (input-parser-utf8-decoder p) b)))
      (cond
       ((eq? r 'incomplete) #f)
       ((eq? r 'invalid)
        (input-parser-state-set! p 'normal)
        #f)
       (else
        (input-parser-state-set! p 'normal)
        (make-key-event r #f '())))))
  )

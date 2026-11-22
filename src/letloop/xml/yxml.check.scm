;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Included at the tail of the library; discovered by `make check` via
;; the ~check- exports.

;; -------------------------------------------------------------------
;; Layer 1 tests -- hand-verified cases from the spec
;; -------------------------------------------------------------------

(define drive-string
  (lambda (p text)
    ;; Feed an ASCII test string byte by byte, collecting (kind . payload).
    (let loop ((i 0) (out '()))
      (if (fx=? i (string-length text))
        (reverse out)
        (let-values (((kind payload) (yxml-step! p (char->integer (string-ref text i)))))
          (loop (fx+ i 1) (cons (cons kind payload) out)))))))

(define non-ok
  (lambda (events)
    (filter (lambda (e) (not (eq? (car e) 'ok))) events)))

(define error-kinds '(esyn eref eclose estack eeof))

(define until-first-error
  (lambda (events)
    ;; yxml_parse's behavior past the first error is unspecified (the
    ;; real harness, test.c, exits immediately on one) -- truncate a
    ;; driven event list the same way before asserting on it.
    (let loop ((events events) (out '()))
      (cond
       ((null? events) (reverse out))
       ((memq (caar events) error-kinds) (reverse (cons (car events) out)))
       (else (loop (cdr events) (cons (car events) out)))))))

(define ~check-yxml-elem-minimal
  (lambda ()
    (let ((p (yxml-parser-make)))
      (assert (equal? (non-ok (drive-string p "<a/>"))
                       '((elem-start . "a") (elem-end . #f))))
      (assert (yxml-eof? p)))))

(define ~check-yxml-elem-nesting-content
  (lambda ()
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<a><b>x</b></a>"))))
      (assert (equal? (map car events) '(elem-start elem-start content elem-end elem-end)))
      (assert (bytevector=? (cdr (list-ref events 2)) (bytevector (char->integer #\x))))
      (assert (yxml-eof? p)))))

(define ~check-yxml-elem-mismatched-close
  (lambda ()
    (let ((p (yxml-parser-make)))
      (assert (equal? (until-first-error (non-ok (drive-string p "<a></b>")))
                       '((elem-start . "a") (eclose . #f)))))))

(define ~check-yxml-attr
  (lambda ()
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<a b=\"c\"/>"))))
      (assert (equal? (map car events) '(elem-start attr-start attr-val attr-end elem-end)))
      (assert (bytevector=? (cdr (list-ref events 2)) (bytevector (char->integer #\c)))))))

(define ~check-yxml-numeric-ref-multibyte
  (lambda ()
    (let* ((p (yxml-parser-make))
           (content-events (filter (lambda (e) (eq? (car e) 'content)) (drive-string p "<a>&#8364;</a>"))))
      ;; euro sign U+20AC, 3-byte UTF-8, produced as one content event.
      (assert (fx=? 1 (length content-events)))
      (assert (string=? (utf8->string (cdr (car content-events))) "\x20ac;")))))

(define ~check-yxml-cdata-bracket-lookahead
  (lambda ()
    (let* ((p (yxml-parser-make))
           (events (drive-string p "<a><![CDATA[x]]y]]></a>"))
           (content-events (filter (lambda (e) (eq? (car e) 'content)) events))
           (assembled (utf8->string (bytevector-append-list (map cdr content-events)))))
      (assert (string=? assembled "x]]y")))))

(define ~check-yxml-comment-no-token
  (lambda ()
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<a><!-- hi --></a>"))))
      (assert (equal? events '((elem-start . "a") (elem-end . #f)))))))

(define ~check-yxml-xmldecl-no-pi-token
  (lambda ()
    (let* ((p (yxml-parser-make))
           (events (drive-string p "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")))
      (assert (not (memq 'pi-start (map car events))))
      (assert (equal? (map car (filter (lambda (e) (memq (car e) '(elem-start elem-end))) events))
                       '(elem-start elem-end))))))

(define ~check-yxml-real-pi
  (lambda ()
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<?target data?><a/>")))
           (pi-content-events (filter (lambda (e) (eq? (car e) 'pi-content)) events)))
      (assert (equal? (map car events)
                       '(pi-start pi-content pi-content pi-content pi-content pi-end elem-start elem-end)))
      (assert (string=? (cdr (car events)) "target"))
      (assert (string=? (utf8->string (bytevector-append-list (map cdr pi-content-events))) "data")))))

(define ~check-yxml-eof-incomplete
  (lambda ()
    (let ((p (yxml-parser-make)))
      (drive-string p "<a><b>x</b>")
      (assert (not (yxml-eof? p))))))

(define ~check-yxml-eof-complete
  (lambda ()
    (let ((p (yxml-parser-make)))
      (drive-string p "<a></a>")
      (assert (yxml-eof? p)))))

;; -------------------------------------------------------------------
;; Layer 2 tests
;; -------------------------------------------------------------------

(define ~check-xml->sxml-minimal
  (lambda ()
    (assert (equal? (xml->sxml (string->utf8 "<a/>")) '(a)))))

(define ~check-xml->sxml-nested-mixed-content
  (lambda ()
    (assert (equal? (xml->sxml (string->utf8 "<a>t1<b>x</b>t2</a>"))
                     '(a "t1" (b "x") "t2")))))

(define ~check-xml->sxml-numeric-ref-assembled
  (lambda ()
    (assert (equal? (xml->sxml (string->utf8 "<a>&#8364;</a>"))
                     (list 'a "\x20ac;")))))

(define ~check-xml->sxml-pi-alongside-content
  (lambda ()
    (assert (equal? (xml->sxml (string->utf8 "<a><?target data?>x</a>"))
                     '(a (*PI* target "data") "x")))))

;; Regression: a PI before the root element (e.g. a real-world
;; <?xml-stylesheet?>, common in OAI-PMH responses) must not become
;; what xml->sxml returns as "top" -- it has to be skipped in favor of
;; the actual root element that follows it. Found via a real Persee
;; OAI-PMH fixture during incorporated.scm's development: the old
;; implementation returned (*PI* xml-stylesheet "...") itself as top,
;; so every subsequent sxpath query against it silently matched
;; nothing instead of erroring.
(define ~check-xml->sxml-leading-pi-before-root
  (lambda ()
    (assert (equal? (xml->sxml (string->utf8 "<?xml-stylesheet type=\"text/xsl\" href=\"x.xsl\"?><a>x</a>"))
                     '(a "x")))
    ;; Whitespace between the PI and the root element must also not
    ;; become a spurious extra "child" that confuses root-finding.
    (assert (equal? (xml->sxml (string->utf8 "<?xml-stylesheet type=\"text/xsl\" href=\"x.xsl\"?>\n<a>x</a>"))
                     '(a "x")))))

;; -------------------------------------------------------------------
;; Official yxml test corpus (submodules/yxml/test/*.xml + *.out)
;; -------------------------------------------------------------------
;;
;; Reproduces test.c's y_printres formatting exactly (line-per-event,
;; adjacent data chunks concatenated on one line, control bytes < 0x20
;; and 0x7F hex-escaped, everything else -- including raw UTF-8 lead/
;; continuation bytes >= 0x80 -- passed through verbatim), then
;; compares byte-for-byte against the real *.out files. One
;; aggregating check, not one per fixture, since letloop's export
;; list is static; a failure names the specific fixture and shows
;; expected vs. actual.

(define read-file-bytes
  (lambda (path)
    (call-with-port (open-file-input-port path)
      (lambda (port) (get-bytevector-all port)))))

(define byte-escape-push!
  (lambda (out b)
    ;; printf("\\x%02x", c) -- literal backslash, "x", two lowercase hex digits.
    (if (or (fx=? b #x7f) (fx<? b #x20))
      (let ((hex "0123456789abcdef"))
        (set! out (cons (char->integer (string-ref hex (fxand (fxsrl b 4) #xf)))
                         (cons (char->integer #\x)
                               (cons (char->integer #\\) out))))
        (cons (char->integer (string-ref hex (fxand b #xf))) out))
      (cons b out))))

(define string-bytes-escape-push!
  (lambda (out s)
    (fold-left byte-escape-push! out (bytevector->u8-list (string->utf8 s)))))

(define bytevector-escape-push!
  (lambda (out bv)
    (fold-left byte-escape-push! out (bytevector->u8-list bv))))

(define ascii-push!
  (lambda (out s)
    (fold-left (lambda (out c) (cons (char->integer c) out)) out (string->list s))))

(define fixture-render
  (lambda (bytes)
    (let ((p (yxml-parser-make))
          (size (bytevector-length bytes))
          (out '())
          (indata #f)
          (errored? #f))
      (define newline!
        (lambda () (set! out (cons (char->integer #\newline) out))))
      (let loop ((i 0))
        (if (or errored? (fx=? i size))
          (void)
          (let-values (((kind payload) (yxml-step! p (bytevector-u8-ref bytes i))))
            (case kind
              ((ok) (void))
              ((elem-start) (newline!) (set! out (ascii-push! out "elemstart ")) (set! out (string-bytes-escape-push! out payload)) (set! indata #f))
              ((elem-end) (newline!) (set! out (ascii-push! out "elemend")) (set! indata #f))
              ((attr-start) (newline!) (set! out (ascii-push! out "attrstart ")) (set! out (string-bytes-escape-push! out payload)) (set! indata #f))
              ((attr-end) (newline!) (set! out (ascii-push! out "attrend")) (set! indata #f))
              ((pi-start) (newline!) (set! out (ascii-push! out "pistart ")) (set! out (string-bytes-escape-push! out payload)) (set! indata #f))
              ((pi-end) (newline!) (set! out (ascii-push! out "piend")) (set! indata #f))
              ((content) (unless indata (newline!) (set! out (ascii-push! out "content "))) (set! out (bytevector-escape-push! out payload)) (set! indata #t))
              ((attr-val) (unless indata (newline!) (set! out (ascii-push! out "attrval "))) (set! out (bytevector-escape-push! out payload)) (set! indata #t))
              ((pi-content) (unless indata (newline!) (set! out (ascii-push! out "picontent "))) (set! out (bytevector-escape-push! out payload)) (set! indata #t))
              (else (newline!) (set! out (ascii-push! out "error\n")) (set! errored? #t)))
            (loop (fx+ i 1)))))
      (unless errored?
        (newline!)
        (set! out (ascii-push! out (if (yxml-eof? p) "ok\n" "error\n"))))
      (let* ((rev (reverse out)) (bv (make-bytevector (length rev))))
        (let fill ((i 0) (rest rev))
          (if (null? rest) bv (begin (bytevector-u8-set! bv i (car rest)) (fill (fx+ i 1) (cdr rest)))))))))

(define ~check-yxml-official-fixtures
  (lambda ()
    (let* ((directory "submodules/yxml/test")
           ;; The corpus is a git submodule, and the path is relative to
           ;; the repository root, where `make check` runs. Without it
           ;; there is nothing to compare against.
           (entries (if (file-directory? directory)
                      (directory-list directory)
                      (begin
                        (format #t "** SKIP: no yxml test corpus at ~a (git submodule update --init)\n"
                                directory)
                        '())))
           (xml-files (filter (lambda (name) (string-suffix? ".xml" name)) entries)))
      (for-each
       (lambda (xml-name)
         (let* ((base (substring xml-name 0 (fx- (string-length xml-name) 4)))
                (out-name (string-append base ".out"))
                (xml-path (string-append directory "/" xml-name))
                (out-path (string-append directory "/" out-name)))
           (when (file-exists? out-path)
             (let* ((input (read-file-bytes xml-path))
                    (expected (read-file-bytes out-path))
                    (actual (fixture-render input)))
               (unless (bytevector=? actual expected)
                 (error '~check-yxml-official-fixtures
                        "fixture mismatch"
                        xml-name
                        (utf8->string actual)
                        (utf8->string expected)))))))
       xml-files)
      ;; letloop check treats a void/falsy return as FAILED regardless
      ;; of whether an assertion inside actually failed -- for-each
      ;; returns void, so this needs an explicit truthy tail.
      #t)))

(define string-suffix?
  (lambda (suffix string)
    (let ((sl (string-length suffix)) (l (string-length string)))
      (and (fx>=? l sl) (string=? suffix (substring string (fx- l sl) l))))))

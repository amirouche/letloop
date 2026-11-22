(library (letloop www)
  (export www-request www-host-read www-uri-read www-query-read
          www-request-line-uri-split
          www-form-urlencoded-read
          (rename (url-parse www-url-read)
                  (percent-decode www-percent-decode))
          ~check-www-000 ~check-www-001 ~check-www-002 ~check-www-002-bis
          ~check-www-003 ~check-www-004
          ~check-www-url-read-000 ~check-www-url-read-001)
  (import (chezscheme) (letloop http) (letloop tls base) (letloop match))

  (define pk
    (lambda args
      (display ";; ")
      (write args)
      (newline)
      (flush-output-port)
      (car (reverse args))))

  (define www-request
    (lambda (method url headers body)
      (guard (ex (else (error 'www-request
                              (if (condition? ex)
                                  (condition-message ex)
                                  (format #f "~a" ex))
                              (if (condition? ex)
                                  (condition-irritants ex)
                                  '()))))
        (call-with-values (lambda () (https-request method url headers body))
          (lambda (version code reason headers body)
            (values code headers body))))))

  (define ~check-www-url-read-000
    (lambda ()
      (call-with-values (lambda () (url-parse "https://example.com:8443/a/b?q=1"))
        (lambda (scheme host port target)
          (and (string=? scheme "https")
               (string=? host "example.com")
               (= port 8443)
               (string=? target "/a/b?q=1"))))))

  (define ~check-www-url-read-001
    (lambda ()
      ;; No port, no path: port is #f, target defaults to /.
      (call-with-values (lambda () (url-parse "http://example.com"))
        (lambda (scheme host port target)
          (and (string=? scheme "http")
               (string=? host "example.com")
               (not port)
               (string=? target "/"))))))

  ;; Needs the network, like ~check-tls-request-000 and
  ;; ~check-tls-uring-000 (base.check.scm, tls/uring.scm). example.com
  ;; over httpbin.org: this only ever checks the status code, never
  ;; httpbin's echo body, and example.com is IANA-run infrastructure
  ;; rather than a small hobby service that goes down.
  (define ~check-www-000
    (lambda ()
      (call-with-values (lambda () (www-request 'GET "https://example.com/" '() (bytevector)))
        (lambda (code headers body)
          (= code 200)))))

  (define ~check-www-001
    (lambda ()
      ;; The extra header exercises the request-header-writing path;
      ;; example.com ignores it rather than echoing it back, but this
      ;; check only ever asserted the status code, never the echo.
      (call-with-values (lambda () (www-request 'GET "https://example.com/" '((x-letloop . "yes")) (bytevector)))
        (lambda (code headers body)
          (= code 200)))))

  (define string->list*
    (lambda (x)
      (if x (string->list x) '())))
  
  (define percent-decode
    ;; Optional PLUS? (default #t) decodes #\+ to space, the
    ;; form/query semantics; pass #f for RFC 3986 path segments where
    ;; + is a literal character. Invalid %XX escapes are copied
    ;; through literally instead of raising.
    ;;
    ;; %XX yields a BYTE (0-255), not a Unicode codepoint -- a
    ;; non-ASCII character is UTF-8 encoded before percent-encoding
    ;; (e.g. "é" as %C3%A9), so the two escapes must be collected as
    ;; raw bytes and UTF-8-decoded TOGETHER at the end. Turning each
    ;; escape into a character via (integer->char n) treats every
    ;; byte as its own Latin-1 codepoint instead, which took %C3%A9
    ;; and produced "Ã©" (U+00C3 U+00A9) instead of "é" (U+00E9) --
    ;; found live via a mojibake'd "notre territoire mathématiques"
    ;; query.
    ;;
    ;; Literal characters go into the same byte stream as their UTF-8
    ;; bytes. They used to go in as CHAR->INTEGER on the theory that a
    ;; URL's literal characters are ASCII by construction -- but the
    ;; server builds its strings with utf8->string over the raw request
    ;; bytes, and a client may send raw UTF-8 (GET /日本). Above 255,
    ;; u8-list->bytevector raised, which the server's guard turned into
    ;; a dropped connection; from 128 to 255, "café" decoded as
    ;; "caf\xFFFD;".
    ;;
    ;; An escape is two HEX DIGITS. string->number also accepts a sign,
    ;; so "%+1" decoded to U+0001 and "%-0" to NUL.
    (lambda (string . plus)
      (let ((plus? (if (pair? plus) (car plus) #t)))
        (let loop ((chars (string->list* string))
                   (out '()))
          (match chars
            (() (utf8->string (u8-list->bytevector (reverse out))))
            ((#\+ ,rest ...)
             (loop rest (cons (char->integer (if plus? #\space #\+)) out)))
            ((#\% ,a ,b ,rest ...)
             (let ((n (and (hex-digit? a) (hex-digit? b)
                           (string->number (list->string (list a b)) 16))))
               (if n
                   (loop rest (cons n out))
                   ;; invalid escape: keep it as literal text
                   (loop rest (char-bytes-cons b (char-bytes-cons a
                                                  (cons (char->integer #\%) out)))))))
            ((,char . ,rest) (loop rest (char-bytes-cons char out))))))))

  (define (hex-digit? char)
    (or (char<=? #\0 char #\9)
        (char<=? #\a char #\f)
        (char<=? #\A char #\F)))

  ;; CHAR's UTF-8 bytes, consed onto the reversed byte list OUT.
  (define (char-bytes-cons char out)
    (if (char<? char #\x80)
        (cons (char->integer char) out)
        (append (reverse (bytevector->u8-list (string->utf8 (string char))))
                out)))

  (define www-form-urlencoded-read
    ;; content-type: application/x-www-form-urlencoded
    (lambda (string)

      (define form-item-split
        (lambda (string)
          (let loop ((chars (string->list* string))
                     (out '()))
            (match chars
              (() (list (string->symbol (list->string (reverse out)))))
              ((#\= . ,rest) (cons (string->symbol (percent-decode (list->string (reverse out))))
                                   (percent-decode (list->string rest))))
              ((,char . ,rest) (loop rest (cons char out)))))))

      (let loop ((chars (string->list* string))
                 (out '(())))
        (match chars
          (() (reverse (cons (form-item-split (list->string (reverse (car out)))) (cdr out))))
          ((#\& . ,rest) (loop (cdr chars)
                               (cons* (list)
                                      (form-item-split (list->string (reverse (car out))))
                                      (cdr out))))
          ;; very rare case, TODO: spec ref.
          ((#\; . ,rest) (loop (cdr chars)
                               (cons* (list)
                                      (form-item-split (list->string (reverse (car out))))
                                      (cdr out))))
          ((,char . ,rest) (loop (cdr chars) (cons (cons char (car out)) (cdr out))))))))

  (define www-request-line-uri-split
    (lambda (string)
      (let loop ((chars (string->list* string))
                 (out '()))
        (match chars
          (() (reverse out))
          ((#\/ . ,rest) (loop rest (cons* (list)
                                           (percent-decode
                                            (list->string
                                             (reverse (car out))))
                                           (cdr out))))
          ((,char . ,rest) (loop rest (cons (cons char (car out))
                                            (cdr out))))))))

  (define www-query-read www-form-urlencoded-read)

  (define string-find
    (lambda (string char)
      (let loop ((chars (string->list* string))
                 (index 0))
        (if (null? chars)
            #f
            (if (char=? char (car chars))
                index
                (loop (cdr chars) (fx+ index 1)))))))

  (define www-uri-read
    (lambda (string)

      (define path-split
        (lambda (string)
          (when (and (not (string=? string "")) (char=? #\/ (string-ref string 0)))
            (set! string (substring string 1 (string-length string))))

          (when (and (not (string=? string "")) (char=? #\/ (string-ref string (fx- (string-length string) 1))))
            (set! string (substring string 0 (fx- (string-length string) 1))))

          (if (string=? "" string)
              '()
              (let loop ((chars (string->list* string))
                         (out '(())))
                (match chars
                  (() (reverse (cons (percent-decode (list->string (reverse (car out))))
                                     (cdr out))))
                  ((#\/ . ,rest) (loop rest (cons* '()
                                                   (percent-decode (list->string (reverse (car out))))
                                                   (cdr out))))
                  ((,char . ,rest) (loop rest (cons (cons char (car out))
                                                    (cdr out)))))))))

      (define path #f)
      (define query #f)
      (define fragment #f)

      (let ((index (string-find string #\#)))
        (when index
          (set! fragment (substring string (fx+ index 1) (string-length string)))
          (set! string (substring string 0 index))))

      (let ((index (string-find string #\?)))
        (when index
          (set! query (substring string (fx+ index 1) (string-length string)))
          (set! string (substring string 0 index))))

      (set! path string)

      (values (and path (path-split path)) (and query (www-query-read query)) fragment)))

  (define www-host-read
    (lambda (string)
      (define port #f)
      
      (define index (string-find string #\:))

      (when (and index (not (= index (string-length string))))
        (set! port (string->number
                    (substring string (+ index 1)
                               (string-length string)))))
      
      (when index
        (set! string (substring string 0 index)))
      
      (let loop ((chars (string->list* string))
                 (out '(())))
        (match chars
          (()  (cons (reverse (cons (list->string
                                     (reverse (car out)))
                                    (cdr out)))
                     port))
          ((#\. . ,rest) (loop rest
                               (cons* '()
                                      (list->string (reverse (car out)))
                                      (cdr out))))
          ((,char . ,rest) (loop rest (cons (cons char (car out))
                                            (cdr out))))))))

  (define ~check-www-002
    (lambda ()
      (call-with-values (lambda ()
                          (www-uri-read
                           "/foo/b%33r/baz/?q=world+peace&s=1&now#README"))
        (lambda uri
          (assert (equal? uri  '(("foo" "b3r" "baz")
                                 ((q . "world peace")
                                  (s . "1")
                                  (now))
                                 "README")))))))

  (define ~check-www-002-bis
    (lambda ()
      (call-with-values (lambda ()
                          (www-uri-read
                           ""))
        (lambda uri
          (assert (equal? uri  '(()
                                 #f
                                 #f)))))))
  
  ;; Raw UTF-8 in a request reaches percent-decode as characters above
  ;; 127: it raised above 255 and mangled 128-255. A signed "escape" is
  ;; not one.
  (define ~check-www-004
    (lambda ()
      (assert (equal? (percent-decode "日本") "日本"))
      (assert (equal? (percent-decode "café") "café"))
      (assert (equal? (percent-decode "caf%C3%A9/日") "café/日"))
      (assert (equal? (percent-decode "%+1%-0") "%+1%-0"))
      (assert (equal? (percent-decode "a+b") "a b"))
      (assert (equal? (percent-decode "a+b" #f) "a+b"))
      (assert (equal? (percent-decode "%zz%4") "%zz%4"))
      (call-with-values (lambda () (www-uri-read "/日本?q=日"))
        (lambda (path query fragment)
          (assert (equal? path '("日本")))
          (assert (equal? query '((q . "日"))))))
      #t))

  (define ~check-www-003
    (lambda ()
      (assert (equal? (cons '("foo" "bar" "baz" "qux" "example") 9999)
                      (www-host-read "foo.bar.baz.qux.example:9999")))))
  

  )

(library (letloop www)
  (export www-request www-host-read www-uri-read www-query-read
          www-request-line-uri-split
          www-form-urlencoded-read
          (rename (url-parse www-url-read)
                  (percent-decode www-percent-decode))
          ~check-www-000 ~check-www-001 ~check-www-002 ~check-www-002-bis
          ~check-www-003 ~check-www-url-read-000 ~check-www-url-read-001)
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

  (define ~check-www-000
    (lambda ()
      (call-with-values (lambda () (www-request 'GET "https://httpbin.org/anything" '() (bytevector)))
        (lambda (code headers body)
          (= code 200)))))

  (define ~check-www-001
    (lambda ()
      (call-with-values (lambda () (www-request 'GET "https://httpbin.org/anything" '((x-letloop . "yes")) (bytevector)))
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
    (lambda (string . plus)
      (let ((plus? (if (pair? plus) (car plus) #t)))
        (let loop ((chars (string->list* string))
                   (out '()))
          (match chars
            (() (list->string (reverse out)))
            ((#\+ ,rest ...)
             (loop rest (cons (if plus? #\space #\+) out)))
            ((#\% ,a ,b ,rest ...)
             (let ((n (string->number (list->string (list a b)) 16)))
               (if (and n (fixnum? n) (fx<=? 0 n 255))
                   (loop rest (cons (integer->char n) out))
                   ;; invalid escape: keep it as literal text
                   (loop rest (cons* b a #\% out)))))
            ((,char . ,rest) (loop rest (cons char out))))))))

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
  
  (define ~check-www-003
    (lambda ()
      (assert (equal? (cons '("foo" "bar" "baz" "qux" "example") 9999)
                      (www-host-read "foo.bar.baz.qux.example:9999")))))
  

  )

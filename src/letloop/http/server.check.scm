;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Network-free checks; the live server path is exercised by
;; checks/check-transparenturing.sh and the stress harness.

(define ~check-http-server-000
  (lambda ()
    (check #t (and (string=? "Not Found" (status-code->reason 404))
                   (string=? "Internal Server Error" (status-code->reason 500))
                   (string=? "OK" (status-code->reason 299))))))

(define ~check-http-server-001
  (lambda ()
    ;; Response helpers pair body bytes with a content type.
    (let ((j (json '((hello . "world"))))
          (h (html '(p "hi")))
          (x (xml '(a "b")))
          (t (response 'text "plain")))
      (check #t (and (string=? (cdr j) "application/json")
                     (string=? (utf8->string (car j)) "{\"hello\":\"world\"}")
                     (string=? (cdr h) "text/html")
                     (string=? (utf8->string (car h)) "<p>hi</p>")
                     (string=? (cdr x) "application/xml")
                     (string=? (utf8->string (car x)) "<a>b</a>")
                     (string=? (cdr t) "text/plain"))))))

(define ~check-http-server-002
  (lambda ()
    ;; In-place URI parsing: path segments percent-decoded (single
    ;; byte escapes; percent-decode is not UTF-8 aware), query split,
    ;; fragment dropped. + stays literal in path segments (RFC 3986)
    ;; but decodes to space in the query string; invalid %XX escapes
    ;; pass through as literal text.
    (let ((buf (string->utf8 "/a%20b/c+d/e%zg?x=1&y=deux+trois#frag")))
      (call-with-values (lambda () (uri-parse/range buf 0 (bytevector-length buf)))
        (lambda (path query)
          (check #t (and (equal? path '("a b" "c+d" "e%zg"))
                         (equal? query '((x . "1") (y . "deux trois"))))))))))

(define ~check-http-server-003
  (lambda ()
    ;; try-parse-http-request: incomplete head, then head+body with a
    ;; pipelined remainder.
    (let ((out (make-phr-out)))
      (let-values (((req remainder)
                    (try-parse-http-request (string->utf8 "POST / HTTP/1.1\r\nContent-") out)))
        (check #t (not req)))
      (let-values (((req remainder)
                    (try-parse-http-request
                     (string->utf8 "POST / HTTP/1.1\r\nContent-Length: 2\r\n\r\nhiGET")
                     out)))
        (let ((ok (and req
                       (eq? (phr-request-method-symbol req) 'POST)
                       (string=? (utf8->string remainder) "GET"))))
          (unlock-object out)
          (check #t ok))))))

(define ~check-http-server-005
  (lambda ()
    ;; try-parse-http-request: a definite parse error yields
    ;; 'bad-request rather than 'need more bytes', both for garbage
    ;; bytes and for an unparsable (fixnum-overflowing)
    ;; content-length.
    (let ((out (make-phr-out)))
      (let-values (((req remainder)
                    (try-parse-http-request (string->utf8 "\x0;garbage\r\n\r\n") out)))
        (let-values (((req* remainder*)
                      (try-parse-http-request
                       (string->utf8 "POST / HTTP/1.1\r\nContent-Length: 99999999999999999999\r\n\r\n")
                       out)))
          (unlock-object out)
          (check #t (and (eq? req 'bad-request)
                         (eq? req* 'bad-request))))))))

(define ~check-http-server-004
  (lambda ()
    ;; http-response-write* renders a full response with the body and
    ;; a computed content-length.
    (let ((chunks '()))
      (http-response-write*
       (lambda (bv) (set! chunks (cons bv chunks)) #t)
       200 "OK" '((content-type . "text/plain")) (string->utf8 "hello"))
      (let ((text (utf8->string (apply bytevector-append (reverse chunks)))))
        (check #t (and (string=? "HTTP/1.1 200 OK\r\n" (substring text 0 17))
                       (let ((len (string-length text)))
                         (string=? "hello" (substring text (- len 5) len)))))))))

;; A six-argument DISPATCH, written to the contract as documented before
;; the request context existed, is called without it; a seven-argument
;; one gets it; anything else is refused at startup, not per request.
;; The procedures are built by eval: inlined, %dispatch-adapt's branch
;; for the arity a procedure does NOT have draws Chez's argument-count
;; warning, and a warning fails the library's load.
(define ~check-http-server-006
  (lambda ()
    (define (opaque sexp) (eval sexp (environment '(chezscheme))))
    (let ((six (%dispatch-adapt
                (opaque '(lambda (app state method path params req)
                           (list app state method path params req)))))
          (seven (%dispatch-adapt
                  (opaque '(lambda (app state method path params req rctx)
                             rctx)))))
      (assert (equal? (six 1 2 3 4 5 6 'rctx) '(1 2 3 4 5 6)))
      (assert (eq? (seven 1 2 3 4 5 6 'rctx) 'rctx))
      (assert (guard (ex (#t #t))
                (%dispatch-adapt (opaque '(lambda (a b c) a)))
                #f))
      #t)))

;; A request whose body length can be read two ways is refused, not
;; resolved: chunked, which is not implemented; Content-Length with
;; Transfer-Encoding; and two Content-Lengths. One Content-Length still
;; parses.
(define ~check-http-server-007
  (lambda ()
    (define parse
      (lambda (text)
        (let ((out (make-phr-out)))
          (let-values (((req remainder)
                        (try-parse-http-request (string->utf8 text) out)))
            (unlock-object out)
            req))))
    (assert (eq? 'bad-request
                 (parse "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n")))
    (assert (eq? 'bad-request
                 (parse "POST / HTTP/1.1\r\nContent-Length: 4\r\ntransfer-encoding: chunked\r\n\r\n0\r\n\r\n")))
    (assert (eq? 'bad-request
                 (parse "POST / HTTP/1.1\r\nContent-Length: 0\r\ncontent-length: 5\r\n\r\nhello")))
    (assert (eq? 'bad-request
                 (parse "POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello")))
    (assert (not (symbol? (parse "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"))))
    (assert (not (symbol? (parse "GET / HTTP/1.1\r\nHost: x\r\n\r\n"))))
    #t))

;; A request whose head is in and whose body is not says how long it
;; will be, so the server can read that much and parse once; before
;; the head is in there is nothing to say. Given exactly that many
;; bytes, it parses.
(define ~check-http-server-008
  (lambda ()
    (define head "POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n")
    (define parse
      (lambda (text)
        (let ((out (make-phr-out)))
          (let-values (((req remainder need)
                        (%try-parse-http-request (string->utf8 text) out #f)))
            (unlock-object out)
            (list (and req #t) need)))))
    (assert (equal? '(#f #f) (parse "POST / HTTP/1.1\r\nContent-Le")))
    (assert (equal? (list #f (+ (string-length head) 10))
                    (parse (string-append head "0123"))))
    (assert (equal? '(#t #f) (parse (string-append head "0123456789"))))
    (assert (equal? (string->utf8 "abcdef")
                    (bytevector-concatenate
                     (map string->utf8 '("ab" "" "cde" "f")) 6)))
    #t))

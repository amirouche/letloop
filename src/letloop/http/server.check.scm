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
    ;; fragment dropped.
    (let ((buf (string->utf8 "/a%20b/c?x=1&y=deux#frag")))
      (call-with-values (lambda () (uri-parse/range buf 0 (bytevector-length buf)))
        (lambda (path query)
          (check #t (and (equal? path '("a b" "c"))
                         (equal? query '((x . "1") (y . "deux"))))))))))

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

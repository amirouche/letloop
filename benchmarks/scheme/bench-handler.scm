#!chezscheme
;; The benchmark's request handler.
;;
;; Deliberately builds the response body by plain string
;; interpolation rather than through (letloop http server)'s
;; s-expression helpers, because that is what every other
;; implementation in this suite does:
;;
;;   bun/server.ts    `<html>...${count}...`   template literal
;;   rust/src/main.rs format!("...{}...", c)   format macro
;;   go/main.go       fmt.Fprintf(...)         format
;;
;; Using (html `(html (body ...))) here instead would have letloop
;; walking an s-expression tree and HTML-escaping every text node and
;; attribute value while the others merely concatenate strings —
;; strictly more work for the same bytes. Measured on this suite that
;; handicap is worth about 22% (196k vs 252k req/s), which is enough
;; to change how letloop ranks against Bun. The s-expression API is
;; the idiomatic one and is what examples/my-web-library.scm shows;
;; it is just not what this benchmark is trying to measure.
;;
;; The footer mirrors the one bun/server.ts and rust/src/main.rs
;; emit, so the three responses are of comparable size.
(library (bench-handler)

  (export application context dispatch)

  (import (chezscheme)
          (letloop match)
          (letloop http server)
          (only (letloop liburing low) loop-sleep))

  (define (application) (box 0))

  (define (context application client req) client)

  ;; Encoded once, at load time, exactly as Rust's format! copies its
  ;; constant parts out of a static &str: only the interpolated value
  ;; is built per request. This matters more in Scheme than it looks —
  ;; a Chez string is 32 bits per character, so going through
  ;; (string->utf8 (string-append ...)) allocates ~4x the page in
  ;; string storage and then walks it again to re-encode. Measured at
  ;; 669 ns/request for this page versus 146 ns to parse the request
  ;; that asked for it.
  (define %page-head (string->utf8 "<html><body>\n<h1>Count: "))

  (define %page-tail
    (string->utf8
     (string-append
      "</h1>\n<p>Press Ctrl-C for graceful shutdown</p>\n"
      "<form method=\"POST\" action=\"/increment\">\n"
      "<button type=\"submit\">Increment</button>\n</form>\n"
      "<footer><small>Scheme | letloop | (letloop http server) | io_uring | "
      "coroutines | letloop compile --optimize-level=3</small></footer>\n"
      "</body></html>")))

  ;; Small unsigned integer straight to its ASCII bytes, skipping the
  ;; intermediate Scheme string entirely.
  (define count->utf8
    (lambda (n)
      (if (fxzero? n)
          (bytevector 48)
          (let loop ((n n) (digits '()))
            (if (fxzero? n)
                (u8-list->bytevector digits)
                (loop (fxdiv n 10)
                      (cons (fx+ 48 (fxmod n 10)) digits)))))))

  (define bytevector-append*
    (lambda bvs
      (let* ((total (apply fx+ (map bytevector-length bvs)))
             (out (make-bytevector total)))
        (let loop ((bvs bvs) (offset 0))
          (if (null? bvs)
              out
              (let ((bv (car bvs)))
                (bytevector-copy! bv 0 out offset (bytevector-length bv))
                (loop (cdr bvs) (fx+ offset (bytevector-length bv)))))))))

  (define (dispatch application request-state method path params req)
    (match (cons method path)
      ((GET)
       (values 200
               (cons (bytevector-append* %page-head
                                         (count->utf8 (unbox application))
                                         %page-tail)
                     "text/html")
               '()))
      ((POST "increment")
       (set-box! application (+ (unbox application) 1))
       (values 302 (cons (bytevector) "text/plain") '((location . "/"))))
      ((GET "sleep")
       ;; io_uring timeout op: parks only this connection's
       ;; coroutine, the loop keeps serving — the same genuinely
       ;; non-blocking ~1s wait every other implementation does
       ;; (tokio::time::sleep, setTimeout, green-thread sleep).
       (loop-sleep 1)
       (values 200 (cons (string->utf8 "<html><body><h1>Slept 1 second (via loop-sleep)</h1></body></html>")
                         "text/html")
               '()))
      (,_
       (values 404 (cons (string->utf8 "<html><body><h1>Not Found</h1></body></html>")
                         "text/html")
               '())))))

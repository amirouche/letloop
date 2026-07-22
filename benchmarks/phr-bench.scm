;; Compare the C picohttpparser (FFI, via (letloop picohttpparser)) with the
;; pure-Scheme port (letloop phr).
;;
;; First runs a differential test over valid, malformed, and truncated
;; inputs, then benchmarks both implementations.
;;
;; Usage:
;;
;;   LD_LIBRARY_PATH=local/lib ./local/bin/scheme --libdirs ./src \
;;       --script benchmarks/phr-bench.scm [ITERATIONS] [--no-gc]
;;
(import (chezscheme)
        (prefix (letloop picohttpparser) c:)
        (prefix (letloop phr) s:))

(define iterations
  (let ((args (command-line-arguments)))
    (if (or (null? args) (not (string->number (car args))))
        200000
        (string->number (car args)))))

(when (member "--no-gc" (command-line-arguments))
  ;; disable automatic collection for the whole run
  (collect-request-handler void)
  (display "garbage collector: disabled\n"))

;; picohttpparser's own bench.c request
(define big-request
  (string->utf8
   (string-append
    "GET /wp-content/uploads/2010/03/hello-kitty-darth-vader-pink.jpg HTTP/1.1\r\n"
    "Host: www.kittyhell.com\r\n"
    "User-Agent: Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; ja-JP-mac; rv:1.9.2.3) "
    "Gecko/20100401 Firefox/3.6.3 Pathtraq/0.9\r\n"
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n"
    "Accept-Language: ja,en-us;q=0.7,en;q=0.3\r\n"
    "Accept-Encoding: gzip,deflate\r\n"
    "Accept-Charset: Shift_JIS,utf-8;q=0.7,*;q=0.7\r\n"
    "Keep-Alive: 115\r\n"
    "Connection: keep-alive\r\n"
    "Cookie: wp_ozh_wsa_visits=2; wp_ozh_wsa_visit_lasttime=xxxxxxxxxx; "
    "__utma=xxxxxxxxxxxxxxxxxxxxxxxxxxxx; "
    "__utmz=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\n"
    "\r\n")))

(define small-request
  (string->utf8 "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"))

(define response
  (string->utf8
   (string-append
    "HTTP/1.1 200 OK\r\n"
    "Date: Tue, 22 Jul 2026 12:00:00 GMT\r\n"
    "Content-Type: text/html; charset=utf-8\r\n"
    "Transfer-Encoding: chunked\r\n"
    "Connection: keep-alive\r\n"
    "Vary: Accept-Encoding\r\n"
    "Cache-Control: private, max-age=0\r\n"
    "Server: gws\r\n"
    "\r\n")))

;; ---- differential test ----

(define request-summary
  (lambda (req request? bytes-consumed method path minor count name value)
    (cond
     ((eq? req 'incomplete) 'incomplete)
     ((not req) #f)
     (else
      (list (bytes-consumed req)
            (method req)
            (path req)
            (minor req)
            (count req)
            (let loop ((i 0) (out '()))
              (if (fx>=? i (count req))
                  (reverse out)
                  (loop (fx+ i 1)
                        (cons (cons (name req i) (value req i)) out)))))))))

(define c-request-summary
  (lambda (buf)
    (request-summary (c:phr-parse-request buf)
                     c:phr-request? c:phr-request-bytes-consumed
                     c:phr-request-method c:phr-request-path
                     c:phr-request-minor-version c:phr-request-header-count
                     c:phr-request-header-name c:phr-request-header-value)))

(define s-request-summary
  (lambda (buf)
    (request-summary (s:phr-parse-request buf)
                     s:phr-request? s:phr-request-bytes-consumed
                     s:phr-request-method s:phr-request-path
                     s:phr-request-minor-version s:phr-request-header-count
                     s:phr-request-header-name s:phr-request-header-value)))

(define response-summary
  (lambda (resp bytes-consumed status minor message count name value)
    (cond
     ((eq? resp 'incomplete) 'incomplete)
     ((not resp) #f)
     (else
      (list (bytes-consumed resp)
            (status resp)
            (minor resp)
            (message resp)
            (count resp)
            (let loop ((i 0) (out '()))
              (if (fx>=? i (count resp))
                  (reverse out)
                  (loop (fx+ i 1)
                        (cons (cons (name resp i) (value resp i)) out)))))))))

(define c-response-summary
  (lambda (buf)
    (response-summary (c:phr-parse-response buf)
                      c:phr-response-bytes-consumed c:phr-response-status
                      c:phr-response-minor-version c:phr-response-message
                      c:phr-response-header-count c:phr-response-header-name
                      c:phr-response-header-value)))

(define s-response-summary
  (lambda (buf)
    (response-summary (s:phr-parse-response buf)
                      s:phr-response-bytes-consumed s:phr-response-status
                      s:phr-response-minor-version s:phr-response-message
                      s:phr-response-header-count s:phr-response-header-name
                      s:phr-response-header-value)))

(define subbytevector
  (lambda (bv start end)
    (let ((out (make-bytevector (fx- end start))))
      (bytevector-copy! bv start out 0 (fx- end start))
      out)))

(define request-cases
  (append
   (list small-request
         big-request
         (string->utf8 "\r\nGET / HTTP/1.1\r\n\r\n")
         (string->utf8 "GET /lf HTTP/1.1\nHost: a\n\n")
         (string->utf8 "POST /x HTTP/1.0\r\nA:b\r\n  folded \r\nC:  d  \r\n\r\n")
         (string->utf8 "GET   /spaces   HTTP/1.1\r\n\r\n")
         (string->utf8 "GET / HTTP/2.0\r\n\r\n")
         (string->utf8 "GET / FTP/1.1\r\n\r\n")
         (string->utf8 " / HTTP/1.1\r\n\r\n")
         (string->utf8 "GET  HTTP/1.1\r\n\r\n")
         (string->utf8 "GET / HTTP/1.1\r\nBad header: x\r\n\r\n")
         (string->utf8 "GET / HTTP/1.1\r\n: novalue\r\n\r\n")
         (string->utf8 "GET / HTTP/1.1\r\nX: a\rb\r\n\r\n")
         (string->utf8 "G\x7f;T / HTTP/1.1\r\n\r\n"))
   ;; every prefix of the small request must yield the same verdict
   (let loop ((i 0) (out '()))
     (if (fx>? i (bytevector-length small-request))
         (reverse out)
         (loop (fx+ i 1) (cons (subbytevector small-request 0 i) out))))))

(define response-cases
  (list response
        (string->utf8 "HTTP/1.1 200 OK\r\n\r\n")
        (string->utf8 "HTTP/1.1 200\r\n\r\n")
        (string->utf8 "HTTP/1.1 200 \r\n\r\n")
        (string->utf8 "HTTP/1.1 200   spaced message\r\n\r\n")
        (string->utf8 "HTTP/1.1 200X\r\n\r\n")
        (string->utf8 "HTTP/1.1 abc OK\r\n\r\n")
        (string->utf8 "HTTP/1.1 999 Wat\r\n\r\n")
        (string->utf8 "HTTP/1.1 20")
        (string->utf8 "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n")))

(define failures 0)

(define compare!
  (lambda (kind buf c s)
    (unless (equal? c s)
      (set! failures (fx+ failures 1))
      (format #t "MISMATCH ~a on ~s\n  C:      ~s\n  Scheme: ~s\n"
              kind (utf8->string buf) c s))))

(for-each (lambda (buf)
            (compare! 'request buf (c-request-summary buf) (s-request-summary buf)))
          request-cases)
(for-each (lambda (buf)
            (compare! 'response buf (c-response-summary buf) (s-response-summary buf)))
          response-cases)

(if (fxzero? failures)
    (format #t "differential test: ~a cases, all identical\n"
            (+ (length request-cases) (length response-cases)))
    (begin
      (format #t "differential test: ~a MISMATCHES\n" failures)
      (exit 1)))

;; ---- benchmark ----

(define now-ns
  (lambda ()
    (let ((t (current-time 'time-monotonic)))
      (+ (* (time-second t) 1000000000) (time-nanosecond t)))))

(define bench
  (lambda (name thunk)
    ;; warmup
    (let loop ((i 0)) (when (fx<? i 10000) (thunk) (loop (fx+ i 1))))
    (collect)
    (let ((start (now-ns)))
      (let loop ((i 0)) (when (fx<? i iterations) (thunk) (loop (fx+ i 1))))
      (let ((elapsed (- (now-ns) start)))
        (format #t "~a: ~a ns/op (~a ops in ~a ms)\n"
                name
                (div elapsed iterations)
                iterations
                (div elapsed 1000000))
        (div elapsed iterations)))))

(format #t "\niterations: ~a\n\n" iterations)

(define report
  (lambda (label c-ns s-ns)
    (format #t "~a: scheme/C ratio ~,2f\n\n" label (/ (inexact s-ns) (inexact c-ns)))))

(let ((c (bench "C      small request " (lambda () (c:phr-parse-request small-request))))
      (s (bench "Scheme small request " (lambda () (s:phr-parse-request small-request)))))
  (report "small request" c s))

(let ((c (bench "C      big request   " (lambda () (c:phr-parse-request big-request))))
      (s (bench "Scheme big request   " (lambda () (s:phr-parse-request big-request)))))
  (report "big request" c s))

(let ((c (bench "C      response      " (lambda () (c:phr-parse-response response))))
      (s (bench "Scheme response      " (lambda () (s:phr-parse-response response)))))
  (report "response" c s))

;; parse + typical header lookup, closer to what a server does per request
(let ((c (bench "C      parse+lookup  "
                (lambda ()
                  (let ((req (c:phr-parse-request big-request)))
                    (c:phr-request-header-ref req "connection")))))
      (s (bench "Scheme parse+lookup  "
                (lambda ()
                  (let ((req (s:phr-parse-request big-request)))
                    (s:phr-request-header-ref req "connection"))))))
  (report "parse+lookup" c s))

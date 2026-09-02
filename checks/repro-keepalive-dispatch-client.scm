;; Client half of the keep-alive dispatch-duplication reproducer.
;; Pure letloop -- no downstream-application dependency -- drives a running
;; repro-keepalive-dispatch-lib.scm server (started separately, see
;; that file's header) with two populations:
;;
;;   KEEPALIVE_CONNS connections, each issuing
;;   KEEPALIVE_REQUESTS_PER_CONN sequential requests over ONE socket
;;   (Connection: keep-alive) -- real HTTP/1.1 keep-alive, matching a
;;   browser or reverse-proxy upstream pool.
;;
;;   FRESH_REQUESTS separate connections, each issuing exactly one
;;   request then closing (Connection: close).
;;
;; After every request completes it fetches GET /dump and checks
;; whether any request token was dispatched more than once -- direct,
;; live evidence of the fixed call-with-loop-prompt bug (or an
;; equivalent regression) firing under real concurrent HTTP traffic,
;; not just the synthetic fiber tests in
;; src/letloop/liburing/low.check.scm.
;;
;; It also reports client-observed latency broken out by a keep-alive
;; connection's request POSITION (1..N), to check whether the "gets
;; slower the longer a connection stays open" signature a downstream
;; application's own bench-server tracking notes reported against its
;; search-serving endpoint reproduces here, with a handler that does
;; zero real work (no scoring, no storage fetch) -- isolating whether
;; the effect lives in letloop's server layer itself or is specific
;; to that heavier per-request path.
;;
;; Run (server already running on PORT, see the lib file's header):
;;
;;   cd submodules/letloop
;;   PORT=18080 KEEPALIVE_CONNS=20 KEEPALIVE_REQUESTS_PER_CONN=20 \
;;   FRESH_REQUESTS=400 LD_LIBRARY_PATH=$PWD/local/lib \
;;     local/bin/letloop compile src checks \
;;       checks/repro-keepalive-dispatch-client.scm main
(library (repro-keepalive-dispatch-client)
  (export main)
  (import (chezscheme)
          (letloop liburing low))

  (define (environment-or name default)
    (let ((value (getenv name)))
      (if (and value (not (string=? value ""))) value default)))

  (define port (string->number (environment-or "PORT" "18080")))
  (define keepalive-conns (string->number (environment-or "KEEPALIVE_CONNS" "20")))
  (define keepalive-requests (string->number (environment-or "KEEPALIVE_REQUESTS_PER_CONN" "20")))
  (define fresh-requests (string->number (environment-or "FRESH_REQUESTS" "400")))

  (define (seconds t) (+ (time-second t) (/ (time-nanosecond t) 1e9)))
  (define (now) (seconds (current-time)))

  ;; ---- byte/string helpers (local, no dependency on http/server's
  ;; own unexported bytevector-append or on picohttpparser) ----

  (define (bytevector-append . bvs)
    (let* ((total (apply fx+ (map bytevector-length bvs)))
           (out (make-bytevector total)))
      (let loop ((bvs bvs) (offset 0))
        (if (null? bvs)
          out
          (let ((bv (car bvs)))
            (bytevector-copy! bv 0 out offset (bytevector-length bv))
            (loop (cdr bvs) (fx+ offset (bytevector-length bv))))))))

  (define (bv-index-of hay needle start)
    (let ((hlen (bytevector-length hay)) (nlen (bytevector-length needle)))
      (let loop ((i start))
        (cond
          ((fx> (fx+ i nlen) hlen) #f)
          ((let inner ((j 0))
             (cond ((fx= j nlen) #t)
                   ((fx= (bytevector-u8-ref hay (fx+ i j)) (bytevector-u8-ref needle j))
                    (inner (fx+ j 1)))
                   (else #f)))
           i)
          (else (loop (fx+ i 1)))))))

  (define crlfcrlf (bytevector 13 10 13 10))

  (define (string-index-of haystack needle)
    (let ((hlen (string-length haystack)) (nlen (string-length needle)))
      (let loop ((i 0))
        (cond
          ((fx> (fx+ i nlen) hlen) #f)
          ((string=? (substring haystack i (fx+ i nlen)) needle) i)
          (else (loop (fx+ i 1)))))))

  (define (header-content-length header-text-lowercase)
    (let ((idx (string-index-of header-text-lowercase "content-length:")))
      (and idx
           (let scan ((i (fx+ idx 15)) (value 0) (any? #f))
             (if (and (fx< i (string-length header-text-lowercase))
                      (char<=? #\0 (string-ref header-text-lowercase i) #\9))
               (scan (fx+ i 1)
                     (+ (* value 10)
                        (- (char->integer (string-ref header-text-lowercase i))
                           (char->integer #\0)))
                     #t)
               (and any? value))))))

  ;; Send REQUEST-BYTES on FD, read a full HTTP response (headers +
  ;; declared Content-Length body). Returns (values elapsed-seconds
  ;; eof?) -- this reproducer sends one request at a time per
  ;; connection and waits for its full response before sending the
  ;; next, no pipelining, so there is never leftover to carry over.
  (define (request-response fd request-bytes)
    (let ((started (now)))
      (loop-write fd request-bytes)
      (let read-loop ((buf (bytevector)))
        (let ((chunk (loop-read fd)))
          (cond
            ((eq? chunk #t) (values (- (now) started) #t))
            ((not chunk) (values (- (now) started) #t))
            (else
             (let ((buf (bytevector-append buf chunk)))
               (let ((header-end (bv-index-of buf crlfcrlf 0)))
                 (if (not header-end)
                   (read-loop buf)
                   (let* ((header-text (string-downcase (utf8->string (subbytevector buf 0 header-end))))
                          (content-length (or (header-content-length header-text) 0))
                          (needed (fx+ header-end 4 content-length)))
                     (if (fx>= (bytevector-length buf) needed)
                       (values (- (now) started) #f)
                       (read-loop buf))))))))))))

  (define (request-bytes token keep-alive?)
    (string->utf8
      (string-append "GET /echo/" token " HTTP/1.1\r\n"
                      "Host: 127.0.0.1\r\n"
                      "Connection: " (if keep-alive? "keep-alive" "close") "\r\n"
                      "\r\n")))

  (define (connect!)
    (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 port))
      (lambda (addr addrlen)
        (let ((fd (loop-connect addr addrlen)))
          (foreign-free addr)
          fd))))

  ;; ---- results (single OS thread, cooperative fibers only
  ;; interleave at suspension points -- plain set!/cons is safe) ----

  (define results '())    ;; list of (kind position elapsed)
  (define pending 0)

  (define (record! kind position elapsed)
    (set! results (cons (list kind position elapsed) results)))

  (define (done-one!) (set! pending (fx- pending 1)))

  (define (run-keepalive-connection connection-index)
    (let ((fd (connect!)))
      (let loop ((n 1))
        (if (fx> n keepalive-requests)
          (begin (loop-close fd) (done-one!))
          (let ((token (string-append (number->string connection-index) "-" (number->string n))))
            (let-values (((elapsed eof?) (request-response fd (request-bytes token #t))))
              (record! 'keepalive n elapsed)
              (if eof?
                (begin (loop-close fd) (done-one!))
                (loop (fx+ n 1)))))))))

  (define (run-fresh-request request-index)
    (let ((fd (connect!))
          (token (string-append "fresh-" (number->string request-index))))
      (let-values (((elapsed eof?) (request-response fd (request-bytes token #f))))
        (record! 'fresh 1 elapsed)
        (loop-close fd)
        (done-one!))))

  (define (fetch-dump)
    (let ((fd (connect!)))
      (loop-write fd (string->utf8 "GET /dump HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"))
      (let read-loop ((buf (bytevector)))
        (let ((chunk (loop-read fd)))
          (cond
            ((or (eq? chunk #t) (not chunk))
             (loop-close fd)
             (let ((header-end (bv-index-of buf crlfcrlf 0)))
               (if header-end
                 (utf8->string (subbytevector buf (fx+ header-end 4) (bytevector-length buf)))
                 "")))
            (else (read-loop (bytevector-append buf chunk))))))))

  (define (string-split-lines text)
    (let ((len (string-length text)))
      (let loop ((start 0) (i 0) (acc '()))
        (cond
          ((fx= i len) (reverse (if (fx> i start) (cons (substring text start i) acc) acc)))
          ((char=? (string-ref text i) #\newline)
           (loop (fx+ i 1) (fx+ i 1) (if (fx> i start) (cons (substring text start i) acc) acc)))
          (else (loop start (fx+ i 1) acc))))))

  (define (median xs)
    (if (null? xs)
      #f
      (list-ref (sort < xs) (quotient (length xs) 2))))

  (define (ms x) (if x (exact->inexact (* 1000 x)) "-"))

  (define (report!)
    (let* ((dump-text (fetch-dump))
           (tokens (string-split-lines dump-text))
           (counts (make-hashtable string-hash string=?)))
      (for-each
        (lambda (token) (hashtable-set! counts token (fx+ 1 (hashtable-ref counts token 0))))
        tokens)
      (let ((duplicates
              (fold-left (lambda (acc token)
                           (if (and (fx> (hashtable-ref counts token 0) 1)
                                    (not (member token acc)))
                             (cons token acc)
                             acc))
                         '() tokens)))
        (format #t "\n=== dispatch-duplication check ===\n")
        (format #t "requests sent: ~a, server-recorded: ~a, distinct tokens: ~a\n"
                (+ (* keepalive-conns keepalive-requests) fresh-requests)
                (length tokens) (hashtable-size counts))
        (if (null? duplicates)
          (format #t "RESULT: no token was ever dispatched twice\n")
          (format #t "RESULT: ~a token(s) dispatched more than once: ~a\n"
                  (length duplicates) duplicates)))
      (let ((by-position (make-eqv-hashtable)))
        (for-each
          (lambda (entry)
            (when (eq? (car entry) 'keepalive)
              (let ((position (cadr entry)) (elapsed (caddr entry)))
                (hashtable-set! by-position position
                                 (cons elapsed (hashtable-ref by-position position '()))))))
          results)
        (format #t "\n=== keep-alive latency by connection position (ms, median) ===\n")
        (let loop ((n 1))
          (when (fx<= n keepalive-requests)
            (let ((xs (hashtable-ref by-position n '())))
              (format #t "  position ~a: n=~a median=~a\n" n (length xs) (ms (median xs))))
            (loop (fx+ n 1)))))
      (let ((fresh (map caddr (filter (lambda (entry) (eq? (car entry) 'fresh)) results))))
        (format #t "\n=== fresh-connection latency ===\n")
        (format #t "n=~a median=~a ms\n" (length fresh) (ms (median fresh))))))

  (define (main)
    (loop-new)
    (set! pending (+ keepalive-conns fresh-requests))
    (let loop ((i 1))
      (when (fx<= i keepalive-conns)
        (loop-spawn (lambda () (run-keepalive-connection i)))
        (loop (fx+ i 1))))
    (let loop ((i 1))
      (when (fx<= i fresh-requests)
        (loop-spawn (lambda () (run-fresh-request i)))
        (loop (fx+ i 1))))
    (loop-spawn
      (lambda ()
        (let wait ()
          (if (fx> pending 0)
            (begin (loop-sleep 0.02) (wait))
            (begin (report!) (loop-stop))))))
    (loop-run)))

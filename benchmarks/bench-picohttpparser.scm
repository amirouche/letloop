#!chezscheme
;; Benchmark: profile picohttpparser hot path with (time ...)
;; Compares old (allocating) vs new (zero-allocation) approaches.
;;
;; Usage: scheme --script benchmarks/bench-picohttpparser.scm

(import (chezscheme))

(define libpicohttpparser (load-shared-object "libpicohttpparser.so"))

(define %phr-max-headers 100)
(define %request-out-size (fx+ 48 (fx* %phr-max-headers 32)))
(define %native (native-endianness))

(define %phr-parse-request-wrapper
  (let ((func (foreign-procedure "phr_parse_request_wrapper"
                                 (void* size_t void* size_t size_t) int)))
    (lambda (buf-ptr buf-len out-ptr max-headers last-len)
      (func buf-ptr buf-len out-ptr max-headers last-len))))

(define (bytevector-pointer bv)
  (#%$object-address bv (+ (foreign-sizeof 'void*) 1)))

(define subbytevector
  (case-lambda
   ((bv start end)
    (if (and (fxzero? start) (fx=? end (bytevector-length bv)))
        bv
        (let ((ret (make-bytevector (fx- end start))))
          (bytevector-copy! bv start ret 0 (fx- end start))
          ret)))
   ((bv start)
    (subbytevector bv start (bytevector-length bv)))))

;; --- OLD (allocating) versions ---

(define phr-parse-request/old
  (lambda (buf out)
    (lock-object buf)
    (let ((ret (%phr-parse-request-wrapper
                (bytevector-pointer buf) (bytevector-length buf)
                (bytevector-pointer out) %phr-max-headers 0)))
      (unlock-object buf)
      (cond
       ((fx>? ret 0) (vector 'phr-request buf out ret))
       ((fx=? ret -2) 'incomplete)
       (else #f)))))

(define %phr-buf (lambda (req) (vector-ref req 1)))
(define %phr-out (lambda (req) (vector-ref req 2)))

(define phr-request-method/old
  (lambda (req)
    (let ((out (%phr-out req)) (buf (%phr-buf req)))
      (let ((offset (bytevector-u64-ref out 0 %native))
            (len (bytevector-u64-ref out 8 %native)))
        (utf8->string (subbytevector buf offset (fx+ offset len)))))))

(define phr-request-header-count
  (lambda (req) (bytevector-u64-ref (%phr-out req) 40 %native)))

(define phr-request-header-name/old
  (lambda (req index)
    (let ((out (%phr-out req)) (buf (%phr-buf req)))
      (let ((base (fx+ 48 (fx* index 32))))
        (let ((offset (bytevector-u64-ref out base %native))
              (len (bytevector-u64-ref out (fx+ base 8) %native)))
          (if (fxzero? len) #f
              (utf8->string (subbytevector buf offset (fx+ offset len)))))))))

(define phr-request-header-value/old
  (lambda (req index)
    (let ((out (%phr-out req)) (buf (%phr-buf req)))
      (let ((base (fx+ 48 (fx* index 32))))
        (let ((offset (bytevector-u64-ref out (fx+ base 16) %native))
              (len (bytevector-u64-ref out (fx+ base 24) %native)))
          (utf8->string (subbytevector buf offset (fx+ offset len))))))))

(define phr-request-header-ref/old
  (lambda (req name)
    (let ((count (phr-request-header-count req))
          (target (string-downcase name)))
      (let loop ((i 0))
        (if (fx>=? i count) #f
            (let ((hdr-name (phr-request-header-name/old req i)))
              (if (and hdr-name (string-ci=? hdr-name target))
                  (phr-request-header-value/old req i)
                  (loop (fx+ i 1)))))))))

;; --- NEW (zero-allocation) versions ---

(define %hdr-connection (string->utf8 "connection"))
(define %hdr-content-length (string->utf8 "content-length"))
(define %hdr-authorization (string->utf8 "authorization"))
(define %hdr-x-missing (string->utf8 "x-missing"))
(define %hdr-host (string->utf8 "host"))
(define %val-close (string->utf8 "close"))

(define %method-GET (string->utf8 "GET"))
(define %method-POST (string->utf8 "POST"))
(define %method-PUT (string->utf8 "PUT"))
(define %method-DELETE (string->utf8 "DELETE"))
(define %method-HEAD (string->utf8 "HEAD"))
(define %method-OPTIONS (string->utf8 "OPTIONS"))
(define %method-PATCH (string->utf8 "PATCH"))

(define bytevector-range-ci=?
  (lambda (key buf offset len)
    (and (fx=? (bytevector-length key) len)
         (let loop ((i 0))
           (or (fx=? i len)
               (let* ((b (bytevector-u8-ref buf (fx+ offset i)))
                      (b* (if (and (fx>=? b 65) (fx<=? b 90))
                              (fxlogior b 32) b))
                      (a (bytevector-u8-ref key i)))
                 (and (fx=? a b*) (loop (fx+ i 1)))))))))

(define bytevector-range=?
  (lambda (key buf offset len)
    (and (fx=? (bytevector-length key) len)
         (let loop ((i 0))
           (or (fx=? i len)
               (and (fx=? (bytevector-u8-ref key i)
                          (bytevector-u8-ref buf (fx+ offset i)))
                    (loop (fx+ i 1))))))))

(define phr-request-header-ref/bv
  (lambda (req key-bv)
    (let ((out (%phr-out req)) (buf (%phr-buf req))
          (count (phr-request-header-count req)))
      (let loop ((i 0))
        (if (fx>=? i count) #f
            (let* ((base (fx+ 48 (fx* i 32)))
                   (name-offset (bytevector-u64-ref out base %native))
                   (name-len (bytevector-u64-ref out (fx+ base 8) %native)))
              (if (and (not (fxzero? name-len))
                       (bytevector-range-ci=? key-bv buf name-offset name-len))
                  (let ((val-offset (bytevector-u64-ref out (fx+ base 16) %native))
                        (val-len (bytevector-u64-ref out (fx+ base 24) %native)))
                    (utf8->string (subbytevector buf val-offset (fx+ val-offset val-len))))
                  (loop (fx+ i 1)))))))))

(define phr-request-header-ref-as-integer
  (lambda (req key-bv)
    (let ((out (%phr-out req)) (buf (%phr-buf req))
          (count (phr-request-header-count req)))
      (let loop ((i 0))
        (if (fx>=? i count) #f
            (let* ((base (fx+ 48 (fx* i 32)))
                   (name-offset (bytevector-u64-ref out base %native))
                   (name-len (bytevector-u64-ref out (fx+ base 8) %native)))
              (if (and (not (fxzero? name-len))
                       (bytevector-range-ci=? key-bv buf name-offset name-len))
                  (let ((val-offset (bytevector-u64-ref out (fx+ base 16) %native))
                        (val-len (bytevector-u64-ref out (fx+ base 24) %native)))
                    (let iloop ((j 0) (n 0))
                      (if (fx>=? j val-len) n
                          (let ((d (fx- (bytevector-u8-ref buf (fx+ val-offset j)) 48)))
                            (if (and (fx>=? d 0) (fx<? d 10))
                                (iloop (fx+ j 1) (fx+ (fx* n 10) d))
                                #f)))))
                  (loop (fx+ i 1)))))))))

(define phr-request-header-value-ci=?
  (lambda (req key-bv val-bv)
    (let ((out (%phr-out req)) (buf (%phr-buf req))
          (count (phr-request-header-count req)))
      (let loop ((i 0))
        (if (fx>=? i count) #f
            (let* ((base (fx+ 48 (fx* i 32)))
                   (name-offset (bytevector-u64-ref out base %native))
                   (name-len (bytevector-u64-ref out (fx+ base 8) %native)))
              (if (and (not (fxzero? name-len))
                       (bytevector-range-ci=? key-bv buf name-offset name-len))
                  (let ((val-offset (bytevector-u64-ref out (fx+ base 16) %native))
                        (val-len (bytevector-u64-ref out (fx+ base 24) %native)))
                    (bytevector-range-ci=? val-bv buf val-offset val-len))
                  (loop (fx+ i 1)))))))))

(define phr-request-method-symbol
  (lambda (req)
    (let* ((out (%phr-out req)) (buf (%phr-buf req))
           (offset (bytevector-u64-ref out 0 %native))
           (len (bytevector-u64-ref out 8 %native)))
      (cond
        ((bytevector-range=? %method-GET buf offset len) 'GET)
        ((bytevector-range=? %method-POST buf offset len) 'POST)
        ((bytevector-range=? %method-PUT buf offset len) 'PUT)
        ((bytevector-range=? %method-DELETE buf offset len) 'DELETE)
        ((bytevector-range=? %method-HEAD buf offset len) 'HEAD)
        ((bytevector-range=? %method-OPTIONS buf offset len) 'OPTIONS)
        ((bytevector-range=? %method-PATCH buf offset len) 'PATCH)
        (else (string->symbol (phr-request-method/old req)))))))

(define phr-parse-request/new
  (lambda (buf out req-vec)
    (lock-object buf)
    (let ((ret (%phr-parse-request-wrapper
                (bytevector-pointer buf) (bytevector-length buf)
                (bytevector-pointer out) %phr-max-headers 0)))
      (unlock-object buf)
      (cond
       ((fx>? ret 0)
        (vector-set! req-vec 1 buf)
        (vector-set! req-vec 2 out)
        (vector-set! req-vec 3 ret)
        req-vec)
       ((fx=? ret -2) 'incomplete)
       (else #f)))))

;; ---- Test data ----

(define %test-request
  (string->utf8
   (string-append
    "GET /api/users/42?format=json&verbose=true HTTP/1.1\r\n"
    "Host: example.com\r\n"
    "User-Agent: benchmark/1.0\r\n"
    "Accept: application/json\r\n"
    "Accept-Encoding: gzip, deflate\r\n"
    "Connection: keep-alive\r\n"
    "X-Request-ID: abc123\r\n"
    "Authorization: Bearer token123\r\n"
    "\r\n")))

(define %iterations 1000000)

(define %out
  (let ((out (make-bytevector %request-out-size 0)))
    (lock-object out) out))

;; Verify correctness of new functions
(let ((req (phr-parse-request/old %test-request %out)))
  (format #t "=== Verification ===\n")
  (format #t "method-symbol: ~a\n" (phr-request-method-symbol req))
  (format #t "header-ref/bv Host: ~a\n" (phr-request-header-ref/bv req %hdr-host))
  (format #t "header-ref/bv Authorization: ~a\n" (phr-request-header-ref/bv req %hdr-authorization))
  (format #t "header-ref/bv X-Missing: ~a\n" (phr-request-header-ref/bv req %hdr-x-missing))
  (format #t "header-ref-as-integer Content-Length: ~a\n"
          (phr-request-header-ref-as-integer req %hdr-content-length))
  (format #t "header-value-ci=? Connection=close: ~a\n"
          (phr-request-header-value-ci=? req %hdr-connection %val-close))
  (format #t "header-value-ci=? Connection=keep-alive: ~a (expect keep-alive != close)\n"
          (phr-request-header-value-ci=? req %hdr-connection (string->utf8 "keep-alive")))
  (newline))

(format #t "=== Benchmarks (~a iterations each) ===\n\n" %iterations)

;; --- Header lookup comparisons ---

(format #t "--- OLD: header-ref 'Authorization' (7th, string alloc) ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (phr-request-header-ref/old req "Authorization")
        (loop (fx- i 1))))))
(newline)

(format #t "--- NEW: header-ref/bv 'Authorization' (7th, bytevector range) ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (phr-request-header-ref/bv req %hdr-authorization)
        (loop (fx- i 1))))))
(newline)

(format #t "--- OLD: header-ref 'X-Missing' (miss, string alloc) ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (phr-request-header-ref/old req "X-Missing")
        (loop (fx- i 1))))))
(newline)

(format #t "--- NEW: header-ref/bv 'X-Missing' (miss, bytevector range) ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (phr-request-header-ref/bv req %hdr-x-missing)
        (loop (fx- i 1))))))
(newline)

;; --- Content-Length as integer ---

(format #t "--- OLD: header-ref 'Content-Length' + string->number ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (let ((cl (phr-request-header-ref/old req "Content-Length")))
          (if cl (string->number cl) 0))
        (loop (fx- i 1))))))
(newline)

(format #t "--- NEW: header-ref-as-integer 'Content-Length' ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (or (phr-request-header-ref-as-integer req %hdr-content-length) 0)
        (loop (fx- i 1))))))
(newline)

;; --- Connection: close check ---

(format #t "--- OLD: header-ref 'Connection' + string-ci=? ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (let ((conn (phr-request-header-ref/old req "connection")))
          (and conn (string-ci=? conn "close")))
        (loop (fx- i 1))))))
(newline)

(format #t "--- NEW: header-value-ci=? Connection=close ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (phr-request-header-value-ci=? req %hdr-connection %val-close)
        (loop (fx- i 1))))))
(newline)

;; --- Method to symbol ---

(format #t "--- OLD: string->symbol (phr-request-method) ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (string->symbol (phr-request-method/old req))
        (loop (fx- i 1))))))
(newline)

(format #t "--- NEW: phr-request-method-symbol ---\n")
(let ((req (phr-parse-request/old %test-request %out)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (phr-request-method-symbol req)
        (loop (fx- i 1))))))
(newline)

;; --- Parse with reusable vector ---

(format #t "--- OLD: phr-parse-request (allocates vector) ---\n")
(time
  (let loop ((i %iterations))
    (unless (fxzero? i)
      (phr-parse-request/old %test-request %out)
      (loop (fx- i 1)))))
(newline)

(format #t "--- NEW: phr-parse-request (reuses vector) ---\n")
(let ((req-vec (vector 'phr-request #f #f 0)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (phr-parse-request/new %test-request %out req-vec)
        (loop (fx- i 1))))))
(newline)

;; --- Full hot path comparison ---

(format #t "--- OLD: Full hot path (parse + method + path + 2 header-refs) ---\n")
(time
  (let loop ((i %iterations))
    (unless (fxzero? i)
      (let ((req (phr-parse-request/old %test-request %out)))
        (string->symbol (phr-request-method/old req))
        (let ((cl (phr-request-header-ref/old req "Content-Length")))
          (if cl (string->number cl) 0))
        (let ((conn (phr-request-header-ref/old req "connection")))
          (and conn (string-ci=? conn "close"))))
      (loop (fx- i 1)))))
(newline)

(format #t "--- NEW: Full hot path (parse + method-symbol + integer-ref + value-ci=?) ---\n")
(let ((req-vec (vector 'phr-request #f #f 0)))
  (time
    (let loop ((i %iterations))
      (unless (fxzero? i)
        (let ((req (phr-parse-request/new %test-request %out req-vec)))
          (phr-request-method-symbol req)
          (or (phr-request-header-ref-as-integer req %hdr-content-length) 0)
          (phr-request-header-value-ci=? req %hdr-connection %val-close))
        (loop (fx- i 1))))))
(newline)

(format #t "=== Done ===\n")

#!chezscheme
(library (letloop picohttpparser)
  (export phr-parse-request
          make-phr-out
          phr-request?
          phr-request-bytes-consumed
          phr-request-method
          phr-request-method-symbol
          phr-request-path
          phr-request-minor-version
          phr-request-header-count
          phr-request-header-name
          phr-request-header-value
          phr-request-header-ref
          phr-request-header-ref/bv
          phr-request-header-ref-as-integer
          phr-request-header-value-ci=?
          phr-request-body
          bytevector-range=?
          bytevector-range-ci=?
          phr-parse-response
          phr-response?
          phr-response-bytes-consumed
          phr-response-status
          phr-response-minor-version
          phr-response-message
          phr-response-header-count
          phr-response-header-name
          phr-response-header-value
          phr-response-header-ref
          ~check-phr-000
          ~check-phr-001
          ~check-phr-002
          ~check-phr-003
          ~check-phr-004
          ~check-phr-005
          ~check-phr-006
          ~check-phr-007)

  (import (chezscheme)
          (letloop cffi))

  (define libpicohttpparser (load-shared-object "libpicohttpparser.so"))

  (define-syntax define-syntax-rule
    (syntax-rules ()
      ((define-syntax-rule (keyword args ...) body)
       (define-syntax keyword
         (syntax-rules ()
           ((keyword args ...) body))))))

  (define-syntax-rule (foreign-procedure* return ptr args ...)
    (foreign-procedure ptr (args ...) return))

  ;; Maximum headers per request/response
  (define %phr-max-headers 100)

  ;; Output buffer size: 48 bytes header + 32 bytes per header slot
  (define %request-out-size (fx+ 48 (fx* %phr-max-headers 32)))

  ;; Response output buffer: 32 bytes header + 32 bytes per header slot
  (define %response-out-size (fx+ 32 (fx* %phr-max-headers 32)))

  (define %native (native-endianness))

  ;; R6RS bytevector-copy takes a single argument; slice explicitly.
  (define subbytevector
    (lambda (bv start end)
      (let ((ret (make-bytevector (fx- end start))))
        (bytevector-copy! bv start ret 0 (fx- end start))
        ret)))

  ;; ---- Request parsing ----

  ;; phr-request is a vector: #(phr-request buf out bytes-consumed)
  ;; buf: the original input bytevector (kept alive to prevent GC)
  ;; out: bytevector of offsets/lengths written by the C wrapper
  ;; bytes-consumed: how many bytes of buf were consumed

  (define %phr-parse-request-wrapper
    (let ((func (foreign-procedure* int "phr_parse_request_wrapper"
                                    void* size_t void* size_t size_t)))
      (lambda (buf-ptr buf-len out-ptr max-headers last-len)
        (func buf-ptr buf-len out-ptr max-headers last-len))))

  ;; Allocate a reusable, pinned out buffer: pass it as the second
  ;; argument of phr-parse-request to avoid one allocation per parse
  ;; (one per connection is enough).
  (define make-phr-out
    (lambda ()
      (let ((out (make-bytevector %request-out-size 0)))
        (lock-object out)
        out)))

  ;; Reusable-out variant: OUT comes from make-phr-out (already
  ;; pinned); REST may carry a last-len fixnum and/or a req vector to
  ;; mutate in place instead of allocating a fresh one.
  (define %phr-parse-request/out
    (lambda (buf out rest)
      (let ((last-len (cond
                       ((and (pair? rest) (fixnum? (car rest))) (car rest))
                       (else 0)))
            (req-vec (cond
                      ((and (pair? rest) (vector? (car rest))) (car rest))
                      ((and (pair? rest) (pair? (cdr rest)) (vector? (cadr rest))) (cadr rest))
                      (else #f))))
        (lock-object buf)
        (let ((ret (%phr-parse-request-wrapper
                    (bytevector-pointer buf)
                    (bytevector-length buf)
                    (bytevector-pointer out)
                    %phr-max-headers
                    last-len)))
          (unlock-object buf)
          (cond
           ((fx>? ret 0)
            (if req-vec
                (begin
                  (vector-set! req-vec 1 buf)
                  (vector-set! req-vec 2 out)
                  (vector-set! req-vec 3 ret)
                  req-vec)
                (vector 'phr-request buf out ret)))
           ((fx=? ret -2) 'incomplete)
           (else #f))))))

  (define phr-parse-request
    (lambda (buf . rest)
      (if (and (pair? rest) (bytevector? (car rest)))
          (%phr-parse-request/out buf (car rest) (cdr rest))
          (let ((max-headers (if (and (pair? rest) (pair? (cdr rest)))
                                 (cadr rest)
                                 %phr-max-headers))
                (last-len (if (pair? rest) (car rest) 0)))
            (let ((out (make-bytevector %request-out-size 0)))
              (with-lock (list buf out)
                (let ((ret (%phr-parse-request-wrapper
                            (bytevector-pointer buf)
                            (bytevector-length buf)
                            (bytevector-pointer out)
                            max-headers
                            last-len)))
                  (cond
                   ((fx>? ret 0) (vector 'phr-request buf out ret))
                   ((fx=? ret -2) 'incomplete)
                   (else #f)))))))))

  (define phr-request?
    (lambda (x)
      (and (vector? x)
           (fx=? (vector-length x) 4)
           (eq? (vector-ref x 0) 'phr-request))))

  (define %phr-buf (lambda (req) (vector-ref req 1)))
  (define %phr-out (lambda (req) (vector-ref req 2)))

  (define phr-request-bytes-consumed
    (lambda (req)
      (vector-ref req 3)))

  ;; Lazy accessor: extracts method string from buffer only when called
  (define phr-request-method
    (lambda (req)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((offset (bytevector-u64-ref out 0 %native))
              (len (bytevector-u64-ref out 8 %native)))
          (utf8->string (subbytevector buf offset (fx+ offset len)))))))

  ;; Lazy accessor: extracts path string from buffer only when called
  (define phr-request-path
    (lambda (req)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((offset (bytevector-u64-ref out 16 %native))
              (len (bytevector-u64-ref out 24 %native)))
          (utf8->string (subbytevector buf offset (fx+ offset len)))))))

  (define phr-request-minor-version
    (lambda (req)
      (bytevector-s32-ref (%phr-out req) 32 %native)))

  (define phr-request-header-count
    (lambda (req)
      (bytevector-u64-ref (%phr-out req) 40 %native)))

  ;; Lazy accessor: extracts a single header name by index
  (define phr-request-header-name
    (lambda (req index)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((base (fx+ 48 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out base %native))
                (len (bytevector-u64-ref out (fx+ base 8) %native)))
            (if (fxzero? len)
                #f
                (utf8->string (subbytevector buf offset (fx+ offset len)))))))))

  ;; Lazy accessor: extracts a single header value by index
  (define phr-request-header-value
    (lambda (req index)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((base (fx+ 48 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out (fx+ base 16) %native))
                (len (bytevector-u64-ref out (fx+ base 24) %native)))
            (utf8->string (subbytevector buf offset (fx+ offset len))))))))

  ;; Lazy lookup: find header value by name (case-insensitive)
  ;; Only converts headers one at a time until a match is found
  (define phr-request-header-ref
    (lambda (req name)
      (let ((count (phr-request-header-count req))
            (target (string-downcase name)))
        (let loop ((i 0))
          (if (fx>=? i count)
              #f
              (let ((hdr-name (phr-request-header-name req i)))
                (if (and hdr-name (string-ci=? hdr-name target))
                    (phr-request-header-value req i)
                    (loop (fx+ i 1)))))))))

  ;; Body slice per content-length; empty bytevector when absent,
  ;; unparsable, or not fully received yet.
  (define phr-request-body
    (lambda (req)
      (let ((cl (phr-request-header-ref req "content-length")))
        (if (not cl)
            (bytevector)
            (let* ((len (string->number cl))
                   (consumed (phr-request-bytes-consumed req))
                   (buf (%phr-buf req)))
              (if (or (not len) (fxzero? len)
                      (fx<? (bytevector-length buf) (fx+ consumed len)))
                  (bytevector)
                  (subbytevector buf consumed (fx+ consumed len))))))))

  ;; ---- Zero-allocation header/method primitives ----

  ;; Compare pre-lowercased bytevector KEY against BUF[offset, offset+len)
  ;; case-insensitively. HTTP header names are ASCII, so fold A-Z to a-z.
  (define bytevector-range-ci=?
    (lambda (key buf offset len)
      (and (fx=? (bytevector-length key) len)
           (let loop ((i 0))
             (or (fx=? i len)
                 (let* ((b (bytevector-u8-ref buf (fx+ offset i)))
                        (b* (if (and (fx>=? b 65) (fx<=? b 90))
                                (fxlogior b 32)
                                b))
                        (a (bytevector-u8-ref key i)))
                   (and (fx=? a b*)
                        (loop (fx+ i 1)))))))))

  ;; Same, case-sensitive.
  (define bytevector-range=?
    (lambda (key buf offset len)
      (and (fx=? (bytevector-length key) len)
           (let loop ((i 0))
             (or (fx=? i len)
                 (and (fx=? (bytevector-u8-ref key i)
                            (bytevector-u8-ref buf (fx+ offset i)))
                      (loop (fx+ i 1))))))))

  ;; Header lookup keyed by a pre-computed lowercase bytevector; only
  ;; the matched value is extracted.
  (define phr-request-header-ref/bv
    (lambda (req key-bv)
      (let ((out (%phr-out req))
            (buf (%phr-buf req))
            (count (phr-request-header-count req)))
        (let loop ((i 0))
          (if (fx>=? i count)
              #f
              (let* ((base (fx+ 48 (fx* i 32)))
                     (name-offset (bytevector-u64-ref out base %native))
                     (name-len (bytevector-u64-ref out (fx+ base 8) %native)))
                (if (and (not (fxzero? name-len))
                         (bytevector-range-ci=? key-bv buf name-offset name-len))
                    (let ((val-offset (bytevector-u64-ref out (fx+ base 16) %native))
                          (val-len (bytevector-u64-ref out (fx+ base 24) %native)))
                      (utf8->string (subbytevector buf val-offset (fx+ val-offset val-len))))
                    (loop (fx+ i 1)))))))))

  ;; Header lookup parsing the value as a decimal integer straight
  ;; from the bytes; #f on missing header or non-digit.
  (define phr-request-header-ref-as-integer
    (lambda (req key-bv)
      (let ((out (%phr-out req))
            (buf (%phr-buf req))
            (count (phr-request-header-count req)))
        (let loop ((i 0))
          (if (fx>=? i count)
              #f
              (let* ((base (fx+ 48 (fx* i 32)))
                     (name-offset (bytevector-u64-ref out base %native))
                     (name-len (bytevector-u64-ref out (fx+ base 8) %native)))
                (if (and (not (fxzero? name-len))
                         (bytevector-range-ci=? key-bv buf name-offset name-len))
                    (let ((val-offset (bytevector-u64-ref out (fx+ base 16) %native))
                          (val-len (bytevector-u64-ref out (fx+ base 24) %native)))
                      (let iloop ((j 0) (n 0))
                        (if (fx>=? j val-len)
                            n
                            (let ((d (fx- (bytevector-u8-ref buf (fx+ val-offset j)) 48)))
                              (if (and (fx>=? d 0) (fx<? d 10))
                                  (iloop (fx+ j 1) (fx+ (fx* n 10) d))
                                  #f)))))
                    (loop (fx+ i 1)))))))))

  ;; Does the header's value equal VAL-BV, without extracting it?
  (define phr-request-header-value-ci=?
    (lambda (req key-bv val-bv)
      (let ((out (%phr-out req))
            (buf (%phr-buf req))
            (count (phr-request-header-count req)))
        (let loop ((i 0))
          (if (fx>=? i count)
              #f
              (let* ((base (fx+ 48 (fx* i 32)))
                     (name-offset (bytevector-u64-ref out base %native))
                     (name-len (bytevector-u64-ref out (fx+ base 8) %native)))
                (if (and (not (fxzero? name-len))
                         (bytevector-range-ci=? key-bv buf name-offset name-len))
                    (let ((val-offset (bytevector-u64-ref out (fx+ base 16) %native))
                          (val-len (bytevector-u64-ref out (fx+ base 24) %native)))
                      (bytevector-range-ci=? val-bv buf val-offset val-len))
                    (loop (fx+ i 1)))))))))

  (define %method-GET     (string->utf8 "GET"))
  (define %method-POST    (string->utf8 "POST"))
  (define %method-PUT     (string->utf8 "PUT"))
  (define %method-DELETE  (string->utf8 "DELETE"))
  (define %method-HEAD    (string->utf8 "HEAD"))
  (define %method-OPTIONS (string->utf8 "OPTIONS"))
  (define %method-PATCH   (string->utf8 "PATCH"))

  ;; Method as a symbol, no string allocation for the common methods.
  (define phr-request-method-symbol
    (lambda (req)
      (let* ((out (%phr-out req))
             (buf (%phr-buf req))
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
          (else (string->symbol (phr-request-method req)))))))

  ;; ---- Response parsing ----

  ;; phr-response is a vector: #(phr-response buf out bytes-consumed)

  (define %phr-parse-response-wrapper
    (let ((func (foreign-procedure* int "phr_parse_response_wrapper"
                                    void* size_t void* size_t size_t)))
      (lambda (buf-ptr buf-len out-ptr max-headers last-len)
        (func buf-ptr buf-len out-ptr max-headers last-len))))

  (define phr-parse-response
    (lambda (buf . rest)
      (let ((max-headers (if (and (pair? rest) (pair? (cdr rest)))
                             (cadr rest)
                             %phr-max-headers))
            (last-len (if (pair? rest) (car rest) 0)))
        (let ((out (make-bytevector %response-out-size 0)))
          (with-lock (list buf out)
            (let ((ret (%phr-parse-response-wrapper
                        (bytevector-pointer buf)
                        (bytevector-length buf)
                        (bytevector-pointer out)
                        max-headers
                        last-len)))
              (cond
               ((fx>? ret 0) (vector 'phr-response buf out ret))
               ((fx=? ret -2) 'incomplete)
               (else #f))))))))

  (define phr-response?
    (lambda (x)
      (and (vector? x)
           (fx=? (vector-length x) 4)
           (eq? (vector-ref x 0) 'phr-response))))

  (define phr-response-bytes-consumed
    (lambda (resp)
      (vector-ref resp 3)))

  (define phr-response-status
    (lambda (resp)
      (bytevector-s32-ref (%phr-out resp) 0 %native)))

  (define phr-response-minor-version
    (lambda (resp)
      (bytevector-s32-ref (%phr-out resp) 4 %native)))

  ;; Lazy accessor: extracts response message from buffer only when called
  (define phr-response-message
    (lambda (resp)
      (let ((out (%phr-out resp))
            (buf (%phr-buf resp)))
        (let ((offset (bytevector-u64-ref out 8 %native))
              (len (bytevector-u64-ref out 16 %native)))
          (if (fxzero? len)
              ""
              (utf8->string (subbytevector buf offset (fx+ offset len))))))))

  (define phr-response-header-count
    (lambda (resp)
      (bytevector-u64-ref (%phr-out resp) 24 %native)))

  ;; Lazy accessor: extracts a single header name by index
  (define phr-response-header-name
    (lambda (resp index)
      (let ((out (%phr-out resp))
            (buf (%phr-buf resp)))
        (let ((base (fx+ 32 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out base %native))
                (len (bytevector-u64-ref out (fx+ base 8) %native)))
            (if (fxzero? len)
                #f
                (utf8->string (subbytevector buf offset (fx+ offset len)))))))))

  ;; Lazy accessor: extracts a single header value by index
  (define phr-response-header-value
    (lambda (resp index)
      (let ((out (%phr-out resp))
            (buf (%phr-buf resp)))
        (let ((base (fx+ 32 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out (fx+ base 16) %native))
                (len (bytevector-u64-ref out (fx+ base 24) %native)))
            (utf8->string (subbytevector buf offset (fx+ offset len))))))))

  ;; Lazy lookup: find header value by name (case-insensitive)
  (define phr-response-header-ref
    (lambda (resp name)
      (let ((count (phr-response-header-count resp))
            (target (string-downcase name)))
        (let loop ((i 0))
          (if (fx>=? i count)
              #f
              (let ((hdr-name (phr-response-header-name resp i)))
                (if (and hdr-name (string-ci=? hdr-name target))
                    (phr-response-header-value resp i)
                    (loop (fx+ i 1)))))))))

  ;; ---- Tests ----

  ;; Basic GET request parsing
  (define ~check-phr-000
    (lambda ()
      (let* ((raw "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-method req) "GET"))
        (assert (string=? (phr-request-path req) "/"))
        (assert (fx=? (phr-request-minor-version req) 1))
        (assert (fx=? (phr-request-header-count req) 1))
        (assert (string-ci=? (phr-request-header-name req 0) "Host"))
        (assert (string=? (phr-request-header-value req 0) "example.com")))))

  ;; Multiple headers, lazy individual access
  (define ~check-phr-001
    (lambda ()
      (let* ((raw (string-append
                   "POST /api/data HTTP/1.1\r\n"
                   "Host: example.com\r\n"
                   "Content-Type: application/json\r\n"
                   "Content-Length: 13\r\n"
                   "X-Custom: hello\r\n"
                   "\r\n"))
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-method req) "POST"))
        (assert (string=? (phr-request-path req) "/api/data"))
        (assert (fx=? (phr-request-header-count req) 4))
        ;; Lazy lookup by name — only inspects headers until match
        (assert (string=? (phr-request-header-ref req "Content-Type") "application/json"))
        (assert (string=? (phr-request-header-ref req "x-custom") "hello"))
        (assert (not (phr-request-header-ref req "nonexistent"))))))

  ;; Incomplete request returns 'incomplete
  (define ~check-phr-002
    (lambda ()
      (let* ((raw "GET / HTTP/1.1\r\nHost: ex")
             (buf (string->utf8 raw)))
        (assert (eq? (phr-parse-request buf) 'incomplete)))))

  ;; Bytes consumed is correct
  (define ~check-phr-003
    (lambda ()
      (let* ((raw "GET /hello HTTP/1.0\r\n\r\nextra body data")
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-path req) "/hello"))
        (assert (fx=? (phr-request-minor-version req) 0))
        ;; bytes consumed should be the header portion only
        (assert (fx=? (phr-request-bytes-consumed req)
                      (string-length "GET /hello HTTP/1.0\r\n\r\n"))))))

  ;; Response parsing
  (define ~check-phr-004
    (lambda ()
      (let* ((raw (string-append
                   "HTTP/1.1 200 OK\r\n"
                   "Content-Type: text/html\r\n"
                   "Content-Length: 5\r\n"
                   "\r\n"))
             (buf (string->utf8 raw))
             (resp (phr-parse-response buf)))
        (assert (phr-response? resp))
        (assert (fx=? (phr-response-status resp) 200))
        (assert (fx=? (phr-response-minor-version resp) 1))
        (assert (string=? (phr-response-message resp) "OK"))
        (assert (fx=? (phr-response-header-count resp) 2))
        (assert (string=? (phr-response-header-ref resp "Content-Type") "text/html"))
        (assert (string=? (phr-response-header-ref resp "content-length") "5")))))

  ;; Reusable out buffer + in-place req vector (the server hot path)
  (define ~check-phr-005
    (lambda ()
      (let ((out (make-phr-out))
            (req-vec (vector 'phr-request #f #f 0)))
        (let ((req (phr-parse-request
                    (string->utf8 "GET /a HTTP/1.1\r\nHost: x\r\n\r\n")
                    out req-vec)))
          (assert (eq? req req-vec))
          (assert (string=? (phr-request-path req) "/a")))
        ;; Second parse reuses both without allocation
        (let ((req (phr-parse-request
                    (string->utf8 "POST /b HTTP/1.1\r\nHost: y\r\n\r\n")
                    out req-vec)))
          (assert (eq? req req-vec))
          (assert (string=? (phr-request-path req) "/b"))
          (assert (string=? (phr-request-header-ref req "host") "y")))
        (unlock-object out)
        #t)))

  ;; Zero-allocation primitives
  (define ~check-phr-006
    (lambda ()
      (let* ((raw (string-append
                   "POST /api HTTP/1.1\r\n"
                   "Connection: Close\r\n"
                   "Content-Length: 5\r\n"
                   "\r\n"))
             (req (phr-parse-request (string->utf8 raw))))
        (assert (eq? (phr-request-method-symbol req) 'POST))
        (assert (string=? (phr-request-header-ref/bv req (string->utf8 "connection")) "Close"))
        (assert (fx=? (phr-request-header-ref-as-integer req (string->utf8 "content-length")) 5))
        (assert (phr-request-header-value-ci=? req (string->utf8 "connection") (string->utf8 "close")))
        (assert (not (phr-request-header-ref/bv req (string->utf8 "x-missing"))))
        (assert (not (phr-request-header-ref-as-integer req (string->utf8 "connection"))))
        #t)))

  ;; Body extraction per content-length
  (define ~check-phr-007
    (lambda ()
      (let* ((raw "POST /api HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
             (req (phr-parse-request (string->utf8 raw))))
        (assert (equal? (phr-request-body req) (string->utf8 "hello")))
        ;; Truncated body yields the empty bytevector
        (let ((req (phr-parse-request (string->utf8 "POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhi"))))
          (assert (equal? (phr-request-body req) (bytevector))))
        #t)))

  )

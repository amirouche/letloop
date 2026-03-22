#!chezscheme
(library (letloop picohttpparser)
  (export phr-parse-request
          phr-request?
          phr-request-bytes-consumed
          phr-request-method
          phr-request-path
          phr-request-minor-version
          phr-request-header-count
          phr-request-header-name
          phr-request-header-value
          phr-request-header-ref
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
          ~check-phr-004)

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

  (define phr-parse-request
    (lambda (buf . rest)
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
               (else #f))))))))

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
          (utf8->string (bytevector-copy buf offset (fx+ offset len)))))))

  ;; Lazy accessor: extracts path string from buffer only when called
  (define phr-request-path
    (lambda (req)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((offset (bytevector-u64-ref out 16 %native))
              (len (bytevector-u64-ref out 24 %native)))
          (utf8->string (bytevector-copy buf offset (fx+ offset len)))))))

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
                (utf8->string (bytevector-copy buf offset (fx+ offset len)))))))))

  ;; Lazy accessor: extracts a single header value by index
  (define phr-request-header-value
    (lambda (req index)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((base (fx+ 48 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out (fx+ base 16) %native))
                (len (bytevector-u64-ref out (fx+ base 24) %native)))
            (utf8->string (bytevector-copy buf offset (fx+ offset len))))))))

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
              (utf8->string (bytevector-copy buf offset (fx+ offset len))))))))

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
                (utf8->string (bytevector-copy buf offset (fx+ offset len)))))))))

  ;; Lazy accessor: extracts a single header value by index
  (define phr-response-header-value
    (lambda (resp index)
      (let ((out (%phr-out resp))
            (buf (%phr-buf resp)))
        (let ((base (fx+ 32 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out (fx+ base 16) %native))
                (len (bytevector-u64-ref out (fx+ base 24) %native)))
            (utf8->string (bytevector-copy buf offset (fx+ offset len))))))))

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

  )

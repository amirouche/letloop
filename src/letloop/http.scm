(library (letloop http)

  (export http-error?
          http-error-message
          http-error-payload
          http-request-read
          http-request-write
          http-response-read
          http-response-write

          ;; XXX: Disable tests
          #;~check-letloop-http
          )

  (import (chezscheme)
          (letloop r999))

  (define pk
    (lambda args
      (write args)(newline)
      (flush-output-port)
      (car (reverse args))))

  ;; <http-error>

  (define-record-type* <http-error>
    (make-http-error message payload)
    http-error?
    (message http-error-message)
    (payload http-error-payload))

  ;; helpers

  (define raise-unexpected-end-of-file
    (lambda ()
      (raise (make-http-error "Unexpected end of file" (list 'unexpected-end-of-file)))))

  (define raise-invalid
    (lambda (uid)
      (raise (make-http-error "Invalid" (list 'invalid uid)))))

  (define byte-space 32)
  (define byte-carriage-return 13)
  (define byte-linefeed 10) ;; aka. newline

  (define generator->list
    (lambda (generator)
      (let loop ((out '()))
        (let ((object (generator)))
          (if (eof-object? object)
              (reverse out)
              (loop (cons object out)))))))

  (define every
    (lambda (predicate? objects)
      (if (null? objects)
          #t
          (if (predicate? (car objects))
              (every predicate? (cdr objects))
              #f))))

  (define (bytevector-append . bvs)
    (assert (every bytevector? bvs))
    (let* ((total (apply fx+ (map bytevector-length bvs)))
           (out (make-bytevector total)))
      (let loop ((bvs bvs)
                 (index 0))
        (unless (null? bvs)
          (bytevector-copy! (car bvs) 0 out index (bytevector-length (car bvs)))
          (loop (cdr bvs) (fx+ index (bytevector-length (car bvs))))))
      out))

  ;; Buffer abstraction: wraps a chunk-reader thunk (lambda () -> bytevector | eof-object)
  ;; Returns two closures: read-byte! and read-bytes!

  (define make-reader
    (lambda (read)
      (let ((buf (bytevector))
            (idx 0)
            (len 0))

        (define refill!
          (lambda ()
            (let ((chunk (read)))
              (if (eof-object? chunk)
                  #f
                  (begin
                    (set! buf chunk)
                    (set! idx 0)
                    (set! len (bytevector-length chunk))
                    #t)))))

        (define read-byte!
          (lambda ()
            (if (fx<? idx len)
                (let ((b (bytevector-u8-ref buf idx)))
                  (set! idx (fx+ idx 1))
                  b)
                (if (refill!)
                    (read-byte!)
                    (eof-object)))))

        (define read-bytes!
          (lambda (n)
            (let ((out (make-bytevector n)))
              (let loop ((written 0))
                (if (fx=? written n)
                    out
                    (let ((avail (fx- len idx)))
                      (if (fxzero? avail)
                          (if (refill!)
                              (loop written)
                              (raise-unexpected-end-of-file))
                          (let ((to-copy (fxmin avail (fx- n written))))
                            (bytevector-copy! buf idx out written to-copy)
                            (set! idx (fx+ idx to-copy))
                            (loop (fx+ written to-copy))))))))))

        (values read-byte! read-bytes!))))

  (define http-line-read
    (lambda (read-byte!)
      (let loopx ((out '()))
        (let ((byte (read-byte!)))
          (cond
           ((eof-object? byte)
            (if (null? out)
                (raise-unexpected-end-of-file)
                (raise-unexpected-end-of-file)))
           ((and (fx=? byte byte-linefeed) (not (null? out)) (fx=? (car out) byte-carriage-return))
            (u8-list->bytevector (reverse (cdr out))))
           ;; linefeed may not appear in the middle of request-line,
           ;; response-line, or header line.
           ((and (fx=? byte byte-linefeed) (or (null? out) (not (fx=? (car out) byte-carriage-return))))
            (raise-invalid 1))
           (else (loopx (cons byte out))))))))


  (define http-headers-read
    (lambda (read-byte!)

      (define massage*
        (lambda (chars)
          (let loop ((chars chars))
            (if (null? chars)
                '()
                (if (char=? (car chars) #\space)
                    (loop (cdr chars))
                    chars)))))

      (define massage
        (lambda (string)
          (let loopx ((chars (reverse (massage* (reverse (massage* (string->list string))))))
                      (key '()))
            (if (null? chars)
                (raise-invalid 5)
                (let ((char (car chars)))
                  (if (char=? char #\:)
                      (cons (string->symbol (string-downcase (list->string (reverse (massage* key)))))
                            (string-downcase (list->string (massage* (reverse (massage* (reverse (cdr chars))))))))
                      (loopx (cdr chars) (cons (car chars) key))))))))

      (let loopy ((out '()))
        (let ((line-bv (http-line-read read-byte!)))
          (if (fxzero? (bytevector-length line-bv))
              (reverse (map (lambda (x) (massage (utf8->string x))) out))
              (loopy (cons line-bv out)))))))

  (define http-chunked-read
    (lambda (read-byte! read-bytes!)
      (let loop ((chunks '()))
        (let ((chunk-size (string->number (utf8->string (http-line-read read-byte!)) 16)))
          (unless chunk-size
            (raise-invalid 11))
          (if (fxzero? chunk-size)
              (apply bytevector-append (reverse chunks))
              (let ((chunk-data (read-bytes! chunk-size)))
                (http-line-read read-byte!) ;; consume trailing CRLF
                (loop (cons chunk-data chunks))))))))

  (define http-body-read
    (lambda (read-byte! read-bytes! headers)
      (let ((content-length (let ((value (assq 'content-length headers)))
                              (if value
                                  (string->number (cdr value))
                                  #f))))
        (if content-length
            (if (fxzero? content-length)
                (bytevector)
                (read-bytes! content-length))
            (let ((chunked? (let ((value (assq 'transfer-encoding headers)))
                              (and value (string=? (cdr value) "chunked")))))
              (if chunked?
                  (http-chunked-read read-byte! read-bytes!)
                  (bytevector)))))))

  ;; http-request-read

  (define http-request-read
    (lambda (read)
      ;; READ is (lambda () -> bytevector | eof-object)

      (define request-line-read
        (lambda (read-byte!)

          (define massage
            (lambda (line-bv)
              (let loop ((bytes (bytevector->u8-list line-bv))
                         (chunk '())
                         (out '()))
                (if (null? bytes)
                    (if (null? chunk)
                        (raise-invalid 3)
                        (reverse (cons (utf8->string (u8-list->bytevector (reverse chunk))) out)))
                    (let ((byte (car bytes)))
                      (if (and (fx=? byte byte-space) (not (null? chunk)))
                          (loop (cdr bytes) '() (cons (utf8->string (u8-list->bytevector (reverse chunk))) out))
                          (loop (cdr bytes) (cons byte chunk) out)))))))

          (let ((strings (massage (http-line-read read-byte!))))
            (unless (fx=? (length strings) 3)
              (raise-invalid 2))
            (values (string->symbol (car strings)) (cadr strings) (string->symbol (caddr strings))))))

      (guard (ex (else (values #f #f #f #f #f)))
        (let-values (((read-byte! read-bytes!) (make-reader read)))
          (call-with-values (lambda () (request-line-read read-byte!))
            (lambda (method uri version)
              (let ((headers (http-headers-read read-byte!)))
                (values method uri version headers (http-body-read read-byte! read-bytes! headers)))))))))

  ;; http-request-write

  (define http-request-write
    (lambda (accumulator method target version headers body)
      ;; body is (lambda () -> bytevector | eof-object)
      ;; Consume body to compute content-length, then write headers + body
      (let ((chunks (generator->list body)))
        (let ((content-length (apply fx+ (map bytevector-length chunks))))
          (let* ((headers* (massage-headers-content-length headers content-length))
                 (request-line (format #f "~a ~a ~a\r\n" method target version))
                 (header-str (apply string-append (map (lambda (x) (format #f "~a: ~a\r\n" (car x) (cdr x))) headers*))))
            (accumulator (string->utf8 (string-append request-line header-str "\r\n")))
            (for-each accumulator chunks))))))

  ;; shared helper for content-length insertion

  (define transfer-encoding-chunked?
    (lambda (pair)
      (and (eq? (car pair) 'transfer-encoding)
           (string=? (cdr pair) "chunked"))))

  (define massage-headers-content-length
    (lambda (headers content-length)
      (cond
       ((null? headers) (list (cons 'content-length content-length)))
       ((transfer-encoding-chunked? (car headers)) (cons (cons 'content-length content-length) (cdr headers)))
       (else (cons (car headers) (massage-headers-content-length (cdr headers) content-length))))))

  ;; http-response-read

  (define http-response-read
    (lambda (read)
      ;; READ is (lambda () -> bytevector | eof-object)

      (define response-line-read
        (lambda (read-byte!)

          (define massage
            (lambda (line-bv)
              (let loop ((bytes (bytevector->u8-list line-bv))
                         (chunk '())
                         (out '()))
                (if (null? bytes)
                    (if (null? chunk)
                        (raise-invalid 7)
                        (reverse (cons (utf8->string (u8-list->bytevector (reverse chunk))) out)))
                    (let ((byte (car bytes)))
                      (if (and (fx=? byte byte-space) (not (null? chunk)))
                          (loop (cdr bytes) '() (cons (utf8->string (u8-list->bytevector (reverse chunk))) out))
                          (loop (cdr bytes) (cons byte chunk) out)))))))

          (let ((strings (massage (http-line-read read-byte!))))
            (values (string->symbol (car strings)) (string->number (cadr strings)) #f))))

      (let-values (((read-byte! read-bytes!) (make-reader read)))
        (call-with-values (lambda () (response-line-read read-byte!))
          (lambda (version code reason)
            (let ((headers (http-headers-read read-byte!)))
              (values version code reason headers (http-body-read read-byte! read-bytes! headers))))))))

  ;; http-response-write

  (define http-response-write
    (lambda (accumulator version code reason headers body)
      ;; body is (lambda () -> bytevector | eof-object)
      ;; Consume body to compute content-length, write headers in one call, then stream body chunks
      (assert (or (pair? headers) (null? headers)))

      (let ((chunks (generator->list body)))
        (let ((content-length (apply fx+ (map bytevector-length chunks))))
          (let* ((headers* (massage-headers-content-length headers content-length))
                 (response-line (format #f "~a ~a ~a\r\n" version code reason))
                 (header-str (apply string-append (map (lambda (x) (format #f "~a: ~a\r\n" (car x) (cdr x))) headers*))))
            (accumulator (string->utf8 (string-append response-line header-str "\r\n")))
            (for-each accumulator chunks))))))

  ;; there is simpler way to do the following, but I will need it later

  (define ~check-letloop-http
    (lambda ()

      (define call-with-binary-input-file
        (lambda (string proc)
          (let ((port (open-file-input-port string)))
            (call-with-values (lambda () (proc port))
              (lambda args
                (close-port port)
                (apply values args))))))


      (define read-bytevector
        (lambda (port)
          (let loop ((out '()))
            (let ((byte (get-u8 port)))
              (if (eof-object? byte)
                  (apply bytevector (reverse out))
                  (loop (cons byte out)))))))

      (define call-with-input-string
        (lambda (string proc)
          (let ((port (open-input-string string)))
            (call-with-values (lambda () (proc port))
              (lambda args
                (close-port port)
                (apply values args))))))

      ;;

      (define (list->generator objects)
        (lambda ()
          (if (null? objects)
              (eof-object)
              (let ((object (car objects)))
                (set! objects (cdr objects))
                object))))

      (define (make-bytevector-accumulator)
        (let ((out '()))
          (lambda (bytevector)
            (if (eof-object? bytevector)
                (apply bytevector-append (reverse out))
                (set! out (cons bytevector out))))))

      (define (bytevector->chunk-reader bv)
        (let ((done #f))
          (lambda ()
            (if done
                (eof-object)
                (begin (set! done #t) bv)))))

      ;;

      (define request-string->scheme
        (lambda (string)
          (call-with-values (lambda () (http-request-read (bytevector->chunk-reader (string->utf8 string))))
            (lambda (method uri version headers body)
              (list method uri version headers (utf8->string body))))))


      (define request-scheme->string
        (lambda (method uri version headers body)
          (let ((accumulator (make-bytevector-accumulator)))
            (http-request-write accumulator method uri version headers (list->generator (list (string->utf8 body))))
            (let ((bytevector (accumulator (eof-object))))
              (utf8->string bytevector)))))

      (define (request-massage string)
        (request-string->scheme (apply request-scheme->string (request-string->scheme string))))



      (define response-string->scheme
        (lambda (string)
          (call-with-values (lambda () (http-response-read (bytevector->chunk-reader (string->utf8 string))))
            (lambda (version code reason headers body)
              (list version code reason headers (utf8->string body))))))

      (define response-scheme->string
        (lambda (version code reason headers body)
          (let ((accumulator (make-bytevector-accumulator)))
            (http-response-write accumulator version code reason headers (list->generator (list (string->utf8 body))))
            (let ((bytevector (accumulator (eof-object))))
              (utf8->string bytevector)))))

      (define (response-massage string)
        (response-string->scheme (apply response-scheme->string (response-string->scheme string))))

      ;;

      (define (massage* port)
        (format #f "\"~a\"" (apply string-append
                                   (map (lambda (c) (if (char=? c #\") "\\\"" (list->string (list c))))
                                        (string->list (utf8->string (read-bytevector port)))))))

      (define error-display
        (lambda (e)
          (if (condition? e)
              (display-condition e)
              (display e))
          (newline)))

      (define check-one-request
        (lambda (filepath)
          (call-with-binary-input-file
           filepath
           (lambda (port)
             (call-with-input-string (massage* port)
                                     (lambda (port)
                                       (guard (e (else (error-display e) #f))
                                              (request-massage (read port)))))))))


      (define check-one-response
        (lambda (filepath)
          (call-with-binary-input-file
           filepath
           (lambda (port)
             (call-with-input-string (massage* port)
                                     (lambda (port)
                                       (guard (e (else (error-display e) #f))
                                              (response-massage (read port)))))))))

      (define LETLOOP_ROOT (let ((LETLOOP_ROOT (getenv "LETLOOP_ROOT")))
                             (unless LETLOOP_ROOT
                               (format #t "You need to enter the loop!")
                               (exit 42))
                             LETLOOP_ROOT))

      (define http-test-suite (string-append LETLOOP_ROOT "/data/http11-test-suite/"))

      (define (check-request case fail)
        (let ((input (format #f "~a/requests/~a/input.txt" http-test-suite case)))
          (format #t "** Checking ~a\n" input)
          (let ((actual (check-one-request input)))
            (if actual
                (let ((expected (call-with-input-file (format #f "~a/requests/~a/output.scm" http-test-suite case) read)))
                  (when (not (equal? actual expected))
                    (pretty-print actual)
                    (format #t "failed with: ~a !\n" input)
                    (flush-output-port)
                    (fail #f)))
                (unless (file-regular? (format "~a/requests/~a/error" http-test-suite case))
                  (format #t "error with: ~a !\n" input)
                  (flush-output-port)
                  (fail #f))))
          #t))

      (define request
        (call/cc (lambda (fail)
                   (length (map
                            (lambda (case)
                              (check-request case fail))
                            (directory-list
                             (string-append http-test-suite
                                            "/requests")))))))

      (define (check-response case fail)
        (let ((input (format #f "~a/responses/~a/input.txt" http-test-suite case)))
          (format #t "** Checking ~a\n" input)
          (let ((actual (check-one-response input)))
            (if actual
                (let ((expected (call-with-input-file (format #f "~a/responses/~a/output.scm" http-test-suite case) read)))
                  (when (not (equal? actual expected))
                    (pretty-print actual)
                    (format #t "failed with: ~a !\n" input)
                    (flush-output-port)
                    (fail #f)))
                (unless (file-regular?
                         (format "~a/responses/~a/error"
                                 http-test-suite case))
                  (format #t "error with: ~a !\n" input)
                  (flush-output-port)
                  (fail #f)))))
        #t)

      (define response
        (call/cc (lambda (fail)
                   (length
                    (map
                     (lambda (case) (check-response case fail))
                     (directory-list
                      (string-append http-test-suite
                                     "/responses")))))))

      (assert (and request response)))))

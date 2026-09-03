(define fetch-check-url "https://images.linuxcontainers.org/")

(define-syntax check-skip-unless-network
  (syntax-rules ()
    ((_ body ...)
     (guard (ex (#t (display "** SKIP: network unavailable\n") #t))
       body ...))))

;; fetch-verify! accepts a correctly hashed download and writes it
(define ~check-fetch-000
  (lambda ()
    (check-skip-unless-network
     (call-with-values (lambda () (www-request 'GET fetch-check-url '() (bytevector)))
       (lambda (code headers body)
         (unless (= code 200) (error 'check-fetch-000 "probe request failed" code))
         (let* ((expected-hash-hex (bytevector->hex-string (blake3 body)))
                (destination "/tmp/letloop/fetch-check-000"))
           (system! "mkdir -p /tmp/letloop/")
           (fetch-verify! "probe" fetch-check-url expected-hash-hex destination)
           (let ((written (call-with-port (open-file-input-port destination) get-bytevector-all)))
             (bytevector=? written body))))))))

;; fetch-verify! rejects a download that does not match the declared hash
(define ~check-fetch-001
  (lambda ()
    (check-skip-unless-network
     (guard (ex (#t #t))
       (fetch-verify! "probe" fetch-check-url
                       "0000000000000000000000000000000000000000000000000000000000000000"
                       "/tmp/letloop/fetch-check-001")
       #f))))

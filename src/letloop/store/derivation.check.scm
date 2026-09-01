(define (derivation-check-write path sexp)
  (system "mkdir -p /tmp/letloop/")
  (when (file-exists? path) (delete-file path))
  (call-with-output-file path (lambda (port) (write sexp port))))

(define ~check-derivation-000
  (lambda ()
    (define path "/tmp/letloop/derivation-check-000.scm")
    (derivation-check-write
     path
     '(derivation
       (name "hello-c")
       (build-environment (root (distribution "alpine") (version "3.20") (machine "amd64")))
       (inputs ("/store/aaa-input"))
       (fetch (hello-src (url "https://example.org/hello.tar.gz")
                          (hash (blake3 "ab12"))))
       (script "set -e\n" "echo hi\n")
       (output "out")
       (expected-output-hash (blake3 "cd34"))))
    (let* ((d (derivation-read path))
           (build-environment (derivation-build-environment d))
           (fetch (car (derivation-fetches d))))
      (and (derivation? d)
           (string=? (derivation-name d) "hello-c")
           (build-environment-rootfs? build-environment)
           (string=? (build-environment-distribution build-environment) "alpine")
           (string=? (build-environment-version build-environment) "3.20")
           (string=? (build-environment-machine build-environment) "amd64")
           (equal? (derivation-inputs d) '("/store/aaa-input"))
           (= (length (derivation-fetches d)) 1)
           (string=? (fetch-name fetch) "hello-src")
           (string=? (fetch-url fetch) "https://example.org/hello.tar.gz")
           (eq? (fetch-hash-algorithm fetch) 'blake3)
           (string=? (fetch-hash-hex fetch) "ab12")
           (string=? (derivation-script d) "set -e\necho hi\n")
           (string=? (derivation-output d) "out")
           (equal? (derivation-expected-output-hash d) (cons 'blake3 "cd34"))))))

(define ~check-derivation-001
  (lambda ()
    (define path "/tmp/letloop/derivation-check-001.scm")
    (derivation-check-write
     path
     '(derivation
       (name "bad name!")
       (build-environment (root (directory "/tmp")))
       (script "true\n")
       (output "out")))
    (guard (ex (#t #t))
      (derivation-read path)
      #f)))

(define ~check-derivation-002
  (lambda ()
    (define path "/tmp/letloop/derivation-check-002.scm")
    (derivation-check-write
     path
     '(derivation
       (name "minimal")
       (build-environment (root (directory "/some/rootfs")))
       (script "true\n")
       (output "out")))
    (let* ((d (derivation-read path))
           (build-environment (derivation-build-environment d)))
      (and (build-environment-directory? build-environment)
           (string=? (build-environment-directory build-environment) "/some/rootfs")
           (null? (derivation-inputs d))
           (null? (derivation-fetches d))
           (not (derivation-expected-output-hash d))))))

(define ~check-derivation-003
  (lambda ()
    (define path "/tmp/letloop/derivation-check-003.scm")
    (derivation-check-write
     path
     '(derivation
       (name "missing-output")
       (build-environment (root (directory "/tmp")))
       (script "true\n")))
    (guard (ex (#t #t))
      (derivation-read path)
      #f)))

(define ~check-derivation-004/fetch-only
  (lambda ()
    (define path "/tmp/letloop/derivation-check-004.scm")
    (derivation-check-write
     path
     '(derivation
       (name "toolchain-tarball")
       (fetch (toolchain (url "https://example.org/toolchain.tgz")
                          (hash (blake3 "ab12"))))
       (output "out")))
    (let ((d (derivation-read path)))
      (and (derivation? d)
           (not (derivation-build-environment d))
           (not (derivation-script d))
           (= (length (derivation-fetches d)) 1)
           (string=? (derivation-output d) "out")))))

(define ~check-derivation-005/script-without-build-environment
  (lambda ()
    (define path "/tmp/letloop/derivation-check-005.scm")
    (derivation-check-write
     path
     '(derivation
       (name "orphan-script")
       (script "true\n")
       (output "out")))
    (guard (ex (#t #t))
      (derivation-read path)
      #f)))

(define ~check-derivation-006/build-environment-without-script
  (lambda ()
    (define path "/tmp/letloop/derivation-check-006.scm")
    (derivation-check-write
     path
     '(derivation
       (name "orphan-build-environment")
       (build-environment (root (directory "/tmp")))
       (output "out")))
    (guard (ex (#t #t))
      (derivation-read path)
      #f)))

(define ~check-derivation-007/fetch-only-needs-a-fetch
  (lambda ()
    (define path "/tmp/letloop/derivation-check-007.scm")
    (derivation-check-write
     path
     '(derivation
       (name "empty")
       (output "out")))
    (guard (ex (#t #t))
      (derivation-read path)
      #f)))

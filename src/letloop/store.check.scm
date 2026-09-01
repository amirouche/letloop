;; End-to-end exercise of store-build (derivation read, sandboxed
;; build, content-hash, store placement, dedup, .drv sidecar) using a
;; symlink-based fixture rootfs (see (letloop store sandbox)'s own
;; check) so it needs neither network nor a cached distribution image.
(define (store-check-fixture-rootfs! rootfs)
  (for-each
   (lambda (name)
     (when (file-exists? (string-append "/" name))
       (system! (format #f "ln -s ~a ~a"
                         (shell-single-quote (string-append "/" name))
                         (shell-single-quote (string-append rootfs "/" name))))))
   '("usr" "bin" "sbin" "lib" "lib64" "etc")))

(define ~check-store-000
  (lambda ()
    (if (not (bwrap-available?))
        (begin (display "** SKIP: /usr/bin/bwrap not found\n") #t)
        (guard (ex (#t (display "** SKIP: bwrap sandbox unavailable in this environment\n") #t))
          (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
          (system! "mkdir -p /tmp/letloop/")
          (let* ((rootfs (mkdtemp "/tmp/letloop/store-check-rootfs-XXXXXX"))
                 (derivation-path "/tmp/letloop/store-check-000.scm"))
            (store-check-fixture-rootfs! rootfs)
            (system! "rm -rf /tmp/letloop/store-check-store")
            (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-store")
            (when (file-exists? derivation-path) (delete-file derivation-path))
            (call-with-output-file derivation-path
              (lambda (port)
                (write `(derivation
                          (name "store-check")
                          (build-environment (root (directory ,rootfs)))
                          (script "mkdir -p out\n" "echo hello > out/hello\n")
                          (output "out"))
                       port)))
            (let* ((first (store-build derivation-path))
                   (second (store-build derivation-path)))
              (and (string=? first second)
                   (file-exists? (string-append first "/hello"))
                   (file-exists? (string-append first ".drv")))))))))

;; A fetch-only derivation -- no build-environment, no script, no
;; sandbox -- lands its fetches straight in the store. Needs the
;; network but no bwrap and no rootfs at all, which is the whole point
;; of the shape: it is what the first link of a bootstrap chain uses.
(define ~check-store-001/fetch-only
  (lambda ()
    (guard (ex (#t (display "** SKIP: network unavailable\n") #t))
      (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
      (system! "mkdir -p /tmp/letloop/")
      (call-with-values (lambda () (www-request 'GET "https://images.linuxcontainers.org/" '() (bytevector)))
        (lambda (code headers body)
          (unless (= code 200) (error 'check-store-001 "probe request failed" code))
          (let ((expected-hash-hex (bytevector->hex-string (blake3 body)))
                (derivation-path "/tmp/letloop/store-check-001.scm"))
            (system! "rm -rf /tmp/letloop/store-check-001-store")
            (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-001-store")
            (when (file-exists? derivation-path) (delete-file derivation-path))
            (call-with-output-file derivation-path
              (lambda (port)
                (write `(derivation
                          (name "fetch-only-check")
                          (fetch (probe (url "https://images.linuxcontainers.org/")
                                         (hash (blake3 ,expected-hash-hex))))
                          (output "out"))
                       port)))
            (let ((destination (store-build derivation-path)))
              (and (file-exists? (string-append destination "/probe"))
                   (file-exists? (string-append destination ".drv"))
                   (bytevector=?
                    (call-with-port (open-file-input-port (string-append destination "/probe"))
                      get-bytevector-all)
                    body)))))))))

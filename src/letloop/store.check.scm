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

(define (store-check-write-derivation! path sexp)
  (when (file-exists? path) (delete-file path))
  (call-with-output-file path (lambda (port) (write sexp port))))

;; A derivation naming another as an input -- (derivation "sibling.scm")
;; in place of a literal store path -- gets that one built first and its
;; store output bind-mounted, so the referring build can read it. The
;; reference is a bare filename, resolved relative to the referring
;; derivation's own directory rather than the invoker's cwd.
(define ~check-store-002/derivation-input
  (lambda ()
    (if (not (bwrap-available?))
        (begin (display "** SKIP: /usr/bin/bwrap not found\n") #t)
        (guard (ex (#t (display "** SKIP: bwrap sandbox unavailable in this environment\n") #t))
          (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
          (system! "mkdir -p /tmp/letloop/")
          (let* ((rootfs (mkdtemp "/tmp/letloop/store-check-002-rootfs-XXXXXX"))
                 (directory (mkdtemp "/tmp/letloop/store-check-002-XXXXXX"))
                 (dependency-path (string-append directory "/dependency.scm"))
                 (referrer-path (string-append directory "/referrer.scm")))
            (store-check-fixture-rootfs! rootfs)
            (system! "rm -rf /tmp/letloop/store-check-002-store")
            (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-002-store")
            (store-check-write-derivation!
             dependency-path
             `(derivation
                (name "dependency")
                (build-environment (root (directory ,rootfs)))
                (script "mkdir -p out\n" "echo dependency-content > out/marker\n")
                (output "out")))
            (store-check-write-derivation!
             referrer-path
             `(derivation
                (name "referrer")
                (build-environment (root (directory ,rootfs)))
                (inputs ((derivation "dependency.scm")))
                ;; every input is bind-mounted at its own absolute store
                ;; path, so the script finds it by globbing the store
                (script "set -e\n"
                        "mkdir -p out\n"
                        "cat /tmp/letloop/store-check-002-store/*-dependency/marker > out/copied\n")
                (output "out")))
            (let ((destination (store-build referrer-path)))
              (and (file-exists? (string-append destination "/copied"))
                   (string=?
                    "dependency-content"
                    (let ((line (call-with-input-file (string-append destination "/copied")
                                   get-line)))
                      line)))))))))

;; A derivation whose build-environment root is another derivation's
;; output: the rootfs itself is built first. This is the shape the
;; bootstrap chain needs -- everything after bootstrap-rootfs names it
;; as its root rather than a hand-written host path.
(define ~check-store-003/derivation-root
  (lambda ()
    (if (not (bwrap-available?))
        (begin (display "** SKIP: /usr/bin/bwrap not found\n") #t)
        (guard (ex (#t (display "** SKIP: bwrap sandbox unavailable in this environment\n") #t))
          (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
          (system! "mkdir -p /tmp/letloop/")
          (let* ((rootfs (mkdtemp "/tmp/letloop/store-check-003-rootfs-XXXXXX"))
                 (directory (mkdtemp "/tmp/letloop/store-check-003-XXXXXX"))
                 (rootfs-path (string-append directory "/rootfs.scm"))
                 (user-path (string-append directory "/user.scm")))
            (store-check-fixture-rootfs! rootfs)
            (system! "rm -rf /tmp/letloop/store-check-003-store")
            (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-003-store")
            ;; produces a rootfs-shaped output: the same symlink set the
            ;; fixture uses, so the derivation built against it can run
            (store-check-write-derivation!
             rootfs-path
             `(derivation
                (name "assembled-rootfs")
                (build-environment (root (directory ,rootfs)))
                (script "set -e\n"
                        "mkdir -p out\n"
                        "for name in usr bin sbin lib lib64 etc; do\n"
                        "  if [ -e \"/$name\" ]; then ln -s \"/$name\" \"out/$name\"; fi\n"
                        "done\n")
                (output "out")))
            (store-check-write-derivation!
             user-path
             `(derivation
                (name "built-against-assembled")
                (build-environment (root (derivation "rootfs.scm")))
                (script "mkdir -p out\n" "echo built > out/marker\n")
                (output "out")))
            (let ((destination (store-build user-path)))
              (file-exists? (string-append destination "/marker"))))))))

;; A reference cycle raises a clear error instead of recursing forever.
;; Needs no sandbox: resolution fails before any build starts.
(define ~check-store-004/cyclic-reference
  (lambda ()
    (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
    (system! "mkdir -p /tmp/letloop/")
    (let* ((directory (mkdtemp "/tmp/letloop/store-check-004-XXXXXX"))
           (a-path (string-append directory "/a.scm"))
           (b-path (string-append directory "/b.scm")))
      (system! "rm -rf /tmp/letloop/store-check-004-store")
      (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-004-store")
      (store-check-write-derivation!
       a-path
       '(derivation
          (name "a")
          (build-environment (root (derivation "b.scm")))
          (script "true\n")
          (output "out")))
      (store-check-write-derivation!
       b-path
       '(derivation
          (name "b")
          (build-environment (root (derivation "a.scm")))
          (script "true\n")
          (output "out")))
      (guard (ex (#t #t))
        (store-build a-path)
        #f))))

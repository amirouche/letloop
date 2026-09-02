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
                ;; /build/inputs/<name> is how a script names an input
                ;; whose real store path it cannot know in advance
                (script "set -e\n"
                        "mkdir -p out\n"
                        "cat /build/inputs/dependency/marker > out/copied\n")
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

;; The build cache skips the build itself on a second call, not just
;; the final move that content addressing already dedups. The script
;; sleeps, so the two calls are told apart by how long they take: a
;; second call that returns in a fraction of the sleep cannot have run
;; it. Sabotaging the build between the calls would not work as a test
;; -- everything it depends on is part of the cache key, so breaking
;; any of it invalidates the entry rather than proving it was used.
(define ~check-store-005/build-cache-skips-the-build
  (lambda ()
    (if (not (bwrap-available?))
        (begin (display "** SKIP: /usr/bin/bwrap not found\n") #t)
        (guard (ex (#t (display "** SKIP: bwrap sandbox unavailable in this environment\n") #t))
          (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
          (system! "mkdir -p /tmp/letloop/")
          (let* ((rootfs (mkdtemp "/tmp/letloop/store-check-005-rootfs-XXXXXX"))
                 (directory (mkdtemp "/tmp/letloop/store-check-005-XXXXXX"))
                 (derivation-path (string-append directory "/cached.scm")))
            (store-check-fixture-rootfs! rootfs)
            (system! "rm -rf /tmp/letloop/store-check-005-store")
            (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-005-store")
            (store-check-write-derivation!
             derivation-path
             `(derivation
                (name "cached")
                (build-environment (root (directory ,rootfs)))
                (script "set -e\n" "sleep 3\n" "mkdir -p out\n" "echo done > out/marker\n")
                (output "out")))
            (let* ((started (real-time))
                   (first (store-build derivation-path))
                   (first-elapsed (- (real-time) started))
                   (resumed (real-time))
                   (second (store-build derivation-path))
                   (second-elapsed (- (real-time) resumed)))
              (and (string=? first second)
                   (file-exists? (string-append second "/marker"))
                   (>= first-elapsed 3000)
                   (< second-elapsed 1500))))))))

;; ... but it must not skip a build whose literal input changed. A
;; literal input is named by a path, not by content, so keying on the
;; path alone would hand back an output built from the old contents --
;; the one kind of wrong answer a cache must never give.
(define ~check-store-006/build-cache-sees-changed-inputs
  (lambda ()
    (if (not (bwrap-available?))
        (begin (display "** SKIP: /usr/bin/bwrap not found\n") #t)
        (guard (ex (#t (display "** SKIP: bwrap sandbox unavailable in this environment\n") #t))
          (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
          (system! "mkdir -p /tmp/letloop/")
          (let* ((rootfs (mkdtemp "/tmp/letloop/store-check-006-rootfs-XXXXXX"))
                 (directory (mkdtemp "/tmp/letloop/store-check-006-XXXXXX"))
                 (source (string-append directory "/source"))
                 (derivation-path (string-append directory "/uses-source.scm")))
            (store-check-fixture-rootfs! rootfs)
            (system! "rm -rf /tmp/letloop/store-check-006-store")
            (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-006-store")
            (system! (format #f "mkdir -p ~a" (shell-single-quote source)))
            (system! (format #f "echo before > ~a/content" (shell-single-quote source)))
            (store-check-write-derivation!
             derivation-path
             `(derivation
                (name "uses-source")
                (build-environment (root (directory ,rootfs)))
                (inputs (,source))
                (script "set -e\n"
                        "mkdir -p out\n"
                        "cp " ,source "/content out/content\n")
                (output "out")))
            (let ((first (store-build derivation-path)))
              (system! (format #f "echo after > ~a/content" (shell-single-quote source)))
              (let ((second (store-build derivation-path)))
                (and (not (string=? first second))
                     (string=? "after"
                               (call-with-input-file (string-append second "/content")
                                 get-line))))))))))

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

;; letloop-store's own CLI: a directory argument extends the library
;; path exactly like `letloop check`/`letloop compile`, and every
;; trailing name-component argument becomes one segment of a
;; (package ...) library name -- `letloop store build libgegl v1.2.3
;; pre` resolves (package libgegl v1.2.3 pre), matching a directory-
;; per-component library layout. Exercises both a plain and a
;; versioned project package, driven through letloop-store itself
;; rather than store-build, so a regression in argument parsing shows
;; up here rather than only in resolve-package-reference.
(define ~check-store-007/cli-project-package
  (lambda ()
    (if (not (bwrap-available?))
        (begin (display "** SKIP: /usr/bin/bwrap not found\n") #t)
        (guard (ex (#t (display "** SKIP: bwrap sandbox unavailable in this environment\n") #t))
          (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
          (define (write-package! path library-name output-name rootfs)
            (call-with-output-file path
              (lambda (port)
                (write `(library ,library-name
                          (export package)
                          (import (chezscheme))
                          (define package
                            '(derivation
                              (name ,output-name)
                              (build-environment (root (directory ,rootfs)))
                              (script "mkdir -p out\n" "echo hello > out/hello\n")
                              (output "out"))))
                       port))))
          (system! "mkdir -p /tmp/letloop/")
          (let* ((rootfs (mkdtemp "/tmp/letloop/store-check-007-rootfs-XXXXXX"))
                 (root (mkdtemp "/tmp/letloop/store-check-007-root-XXXXXX")))
            (store-check-fixture-rootfs! rootfs)
            (system! "rm -rf /tmp/letloop/store-check-007-store")
            (putenv "LETLOOP_STORE" "/tmp/letloop/store-check-007-store")
            ;; (package NAME ...) resolves against ROOT the same way
            ;; (letloop package NAME) resolves against letloop's own
            ;; installed src: through the literal "package" directory.
            (system! (format #f "mkdir -p ~a"
                              (shell-single-quote (string-append root "/package"))))
            (write-package! (string-append root "/package/store-cli-hello.scm")
                             '(package store-cli-hello) "store-cli-hello" rootfs)
            (system! (format #f "mkdir -p ~a"
                              (shell-single-quote (string-append root "/package/store-cli-versioned"))))
            (write-package! (string-append root "/package/store-cli-versioned/v1.scm")
                             '(package store-cli-versioned v1) "store-cli-versioned" rootfs)
            (with-output-to-string
              (lambda () (letloop-store (list "build" root "store-cli-hello"))))
            (with-output-to-string
              (lambda () (letloop-store (list "build" root "store-cli-versioned" "v1"))))
            (and (file-exists? (string-append (store-build '(package store-cli-hello)) "/hello"))
                 (file-exists? (string-append (store-build '(package store-cli-versioned v1)) "/hello"))))))))

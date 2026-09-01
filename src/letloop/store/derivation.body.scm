;; A derivation is read straight from a plain S-expression file, e.g.:
;;
;;   (derivation
;;     (name "hello-c")
;;     (build-environment (root (derivation "toolchain.derivation.scm")))
;;     (inputs ("/store/aaa-some-input"))
;;     (fetch (hello-src (url "https://example.org/hello-1.0.0.tar.gz")
;;                        (hash (blake3 "..."))))
;;     (script "set -e\n" "mkdir -p out\n" "musl-gcc -static -o out/hello hello.c\n")
;;     (output "out")
;;     (expected-output-hash (blake3 "...")))
;;
;; build-environment's root is either a (directory ...) pointing at an
;; already-provisioned rootfs, or (derivation "path.scm"), another
;; derivation whose own output is the rootfs, built first. That second
;; form -- also accepted in place of any literal store path in
;; `inputs` -- is what makes a chain of derivations possible at all,
;; e.g. a toolchain fetch feeding a rootfs assembly feeding everything
;; built against it.
;;
;; There used to be a third form, (distribution ...) (version ...)
;; (machine ...), which downloaded a distribution image through
;; `letloop root create`. Both it and `letloop root` are gone: the
;; store builds its own environments now, and a chain that starts from
;; a hash-pinned toolchain is the point of the exercise -- see
;; checks/letloop/bootstrap*.derivation.scm.
;;
;; build-environment and script are both optional, but only together: a
;; derivation with neither is fetch-only -- its declared fetches are
;; placed directly into the output directory, verified by hash, with no
;; sandbox and no unpacking. This exists so the very first links in a
;; bootstrap chain (a prebuilt toolchain tarball, a static busybox
;; binary) never need a rootfs with a shell to fetch themselves into the
;; store -- unpacking becomes the job of whatever later, ordinary
;; sandboxed derivation consumes them as an input and has a real `tar`
;; to do it with. A derivation with only one of the two is rejected: a
;; script with nothing to run it in, or a rootfs with nothing to run,
;; are both mistakes worth catching at read time.

(define-record-type* <derivation>
  (make-derivation name build-environment inputs fetches script output expected-output-hash)
  derivation?
  (name derivation-name)
  (build-environment derivation-build-environment)
  (inputs derivation-inputs)
  (fetches derivation-fetches)
  (script derivation-script)
  (output derivation-output)
  (expected-output-hash derivation-expected-output-hash))

;; Both kinds carry a path in the same slot -- either kind ends up
;; being "a host directory to bind as the rootfs", they differ only in
;; whether store-build has to produce it first.
(define-record-type* <build-environment>
  (make-build-environment kind directory)
  build-environment?
  (kind build-environment-kind)
  (directory build-environment-directory))

(define (build-environment-directory? environment)
  (eq? (build-environment-kind environment) 'directory))

;; (root (derivation "path.scm")) -- the build environment is another
;; derivation's own output, built first.
(define (build-environment-derivation? environment)
  (eq? (build-environment-kind environment) 'derivation))

(define-record-type* <fetch>
  (make-fetch name url hash-algorithm hash-hex)
  fetch?
  (name fetch-name)
  (url fetch-url)
  (hash-algorithm fetch-hash-algorithm)
  (hash-hex fetch-hash-hex))

(define store-name-valid?
  (lambda (name)
    (and (string? name)
         (fx> (string-length name) 0)
         (for-all (lambda (char)
                    (or (char-alphabetic? char)
                        (char-numeric? char)
                        (memv char '(#\_ #\. #\-))))
                  (string->list name)))))

(define (find-clause clauses tag)
  (find (lambda (c) (and (pair? c) (eq? (car c) tag))) clauses))

(define (required-clause clauses tag context)
  (or (find-clause clauses tag)
      (error 'derivation-read (format #f "missing required ~a clause" tag) context)))

(define (parse-hash-clause hash-clause context)
  ;; (hash (blake3 "hex")) -> (values 'blake3 "hex")
  (let ((algorithm+hex (cadr hash-clause)))
    (unless (and (pair? algorithm+hex) (eq? (car algorithm+hex) 'blake3))
      (error 'derivation-read "only the blake3 hash algorithm is supported" context))
    (values (car algorithm+hex) (cadr algorithm+hex))))

(define (parse-name clauses)
  (let ((name (cadr (required-clause clauses 'name "derivation"))))
    (unless (store-name-valid? name)
      (error 'derivation-read "invalid derivation name, expected [a-zA-Z0-9_.-]+" name))
    name))

(define (parse-build-environment clauses)
  (let ((build-environment (find-clause clauses 'build-environment)))
    (and build-environment
         (let* ((root (required-clause (cdr build-environment) 'root build-environment))
                (directory (find-clause (cdr root) 'directory))
                (derivation (find-clause (cdr root) 'derivation)))
           (cond
            (directory (make-build-environment 'directory (cadr directory)))
            (derivation (make-build-environment 'derivation (cadr derivation)))
            (else
             (error 'derivation-read
                    "root must be (directory ...) or (derivation ...)"
                    root)))))))

;; An input is either a literal store path -- a string, bind-mounted at
;; the same absolute path inside the sandbox as outside -- or
;; (derivation "path/to/other.derivation.scm"), which store-build
;; resolves by building that derivation first and bind-mounting its
;; resulting store path. The reader keeps the reference as-is; nothing
;; here reads the filesystem or builds anything, so parsing stays pure.
;;
;; A (derivation ...) input is additionally reachable inside the build
;; at /build/inputs/<that derivation's name>, since its real store path
;; is content-addressed and so unknowable to whoever writes the script.
(define (parse-input entry)
  (cond
   ((string? entry) entry)
   ((and (pair? entry) (eq? (car entry) 'derivation) (pair? (cdr entry))
         (string? (cadr entry)))
    entry)
   (else
    (error 'derivation-read
           "an input must be a store path string or (derivation \"path.scm\")"
           entry))))

(define (parse-inputs clauses)
  (let ((inputs (find-clause clauses 'inputs)))
    (if inputs (map parse-input (cadr inputs)) '())))

(define (input-derivation-reference? input)
  (and (pair? input) (eq? (car input) 'derivation)))

(define (input-derivation-path input)
  (cadr input))

(define (parse-fetch-entry entry)
  (unless (and (pair? entry) (symbol? (car entry)))
    (error 'derivation-read "invalid fetch entry" entry))
  (let ((url (required-clause (cdr entry) 'url entry))
        (hash (required-clause (cdr entry) 'hash entry)))
    (call-with-values (lambda () (parse-hash-clause hash entry))
      (lambda (algorithm hex)
        (make-fetch (symbol->string (car entry)) (cadr url) algorithm hex)))))

(define (parse-fetches clauses)
  (let ((fetch (find-clause clauses 'fetch)))
    (if fetch (map parse-fetch-entry (cdr fetch)) '())))

(define (parse-script clauses)
  (let ((script (find-clause clauses 'script)))
    (and script (apply string-append (cdr script)))))

(define (parse-output clauses)
  (cadr (required-clause clauses 'output "derivation")))

(define (parse-expected-output-hash clauses)
  (let ((expected-output-hash (find-clause clauses 'expected-output-hash)))
    (and expected-output-hash
         (call-with-values (lambda () (parse-hash-clause expected-output-hash expected-output-hash))
           cons))))

(define (parse-derivation sexp path)
  (unless (and (pair? sexp) (eq? (car sexp) 'derivation))
    (error 'derivation-read "expected a top-level (derivation ...) form" path))
  (let* ((clauses (cdr sexp))
         (build-environment (parse-build-environment clauses))
         (script (parse-script clauses))
         (fetches (parse-fetches clauses)))
    (cond
     ((and (not build-environment) script)
      (error 'derivation-read "a script needs a build-environment to run in" path))
     ((and build-environment (not script))
      (error 'derivation-read "a build-environment needs a script to run" path))
     ((and (not build-environment) (null? fetches))
      (error 'derivation-read
             "a derivation with no build-environment must declare at least one fetch"
             path)))
    (make-derivation (parse-name clauses)
                      build-environment
                      (parse-inputs clauses)
                      fetches
                      script
                      (parse-output clauses)
                      (parse-expected-output-hash clauses))))

(define (derivation-read path)
  (parse-derivation (call-with-input-file path read) path))

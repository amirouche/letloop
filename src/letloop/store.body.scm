;; letloop store build DERIVATION.scm
;;
;; Reads a single derivation, resolves its build-environment rootfs
;; (fetching and caching it via the existing, unmodified `letloop
;; root create` if it names a distribution rather than an already-
;; provisioned directory), runs any fixed-output fetches, then the
;; build script itself inside a network-off bwrap sandbox, hashes the
;; declared output with BLAKE3, and places it in the store at
;; <hash>-<name>, deduping against an existing path with the same
;; content hash.

(define (store-directory)
  (or (getenv "LETLOOP_STORE")
      (string-append (getenv "HOME") "/.letloop/store")))

(define (store-roots-directory)
  (string-append (store-directory) "/.roots"))

(define (store-tmp-directory)
  (string-append (store-directory) "/.tmp"))

(define (store-path hash name)
  (string-append (store-directory) "/" hash "-" name))

;; -> a host directory holding the build-environment's toolchain
;; rootfs, downloading and caching it under .roots/ first if the
;; derivation named a distribution rather than an already-provisioned
;; directory.
(define (resolve-build-environment-rootfs build-environment)
  (if (build-environment-directory? build-environment)
      (build-environment-directory build-environment)
      (let* ((distribution (build-environment-distribution build-environment))
             (version (build-environment-version build-environment))
             (machine (build-environment-machine build-environment))
             (cache-directory (string-append (store-roots-directory) "/"
                                              distribution "-" version "-" machine)))
        (unless (file-exists? cache-directory)
          (system! (format #f "mkdir -p ~a" (shell-single-quote cache-directory)))
          (root-create distribution version machine cache-directory))
        cache-directory)))

(define (run-fetches! fetches scratch-directory)
  (let ((fetch-directory (string-append scratch-directory "/fetch")))
    (unless (null? fetches)
      (system! (format #f "mkdir -p ~a" (shell-single-quote fetch-directory))))
    (for-each
     (lambda (f)
       (fetch-verify! (fetch-name f) (fetch-url f) (fetch-hash-hex f)
                       (string-append fetch-directory "/" (fetch-name f))))
     fetches)))

(define (write-build-script! scratch-directory script)
  (call-with-output-file (string-append scratch-directory "/build.sh")
    (lambda (port) (display script port))))

(define (verify-expected-output-hash! expected actual derivation-path)
  (when expected
    (unless (string-ci=? (cdr expected) actual)
      (error 'store-build "output hash mismatch" derivation-path
             (list 'expected (cdr expected) 'actual actual)))))

;; Moves OUTPUT-DIRECTORY into the store at <HASH>-<NAME>, or drops it
;; if a path with that content hash is already there -- an emergent
;; dedup/cache from content addressing, not its own code path.
(define (store-place! output-directory hash name)
  (let ((destination (store-path hash name)))
    (unless (file-exists? destination)
      (system! (format #f "mkdir -p ~a" (shell-single-quote (store-directory))))
      (system! (format #f "mv ~a ~a"
                        (shell-single-quote output-directory)
                        (shell-single-quote destination))))
    destination))

(define (store-write-drv! destination derivation-path)
  (system! (format #f "cp ~a ~a.drv"
                    (shell-single-quote derivation-path)
                    (shell-single-quote destination))))

;; -> the resulting store path.
(define (store-build derivation-path)
  (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
  (let* ((d (derivation-read derivation-path))
         (rootfs-directory (resolve-build-environment-rootfs (derivation-build-environment d)))
         (ignore-0 (system! (format #f "mkdir -p ~a" (shell-single-quote (store-tmp-directory)))))
         (scratch-directory (mkdtemp (string-append (store-tmp-directory) "/build-XXXXXX")))
         (ignore-1 (run-fetches! (derivation-fetches d) scratch-directory))
         (ignore-2 (write-build-script! scratch-directory (derivation-script d)))
         (ignore-3 (sandbox-build! rootfs-directory scratch-directory (derivation-inputs d)))
         (output-directory (string-append scratch-directory "/" (derivation-output d))))
    (unless (file-exists? output-directory)
      (error 'store-build "declared output not produced by the build" (derivation-output d)))
    (let ((hash (store-hash-directory output-directory)))
      (verify-expected-output-hash! (derivation-expected-output-hash d) hash derivation-path)
      (let ((destination (store-place! output-directory hash (derivation-name d))))
        (store-write-drv! destination derivation-path)
        destination))))

(define (letloop-store args)
  (if (null? args)
      (begin
        (display "Choose: build.\nAs of yet, only: letloop store build DERIVATION.scm\n")
        (exit 1))
      (case (string->symbol (car args))
        ((build) (display (store-build (cadr args))) (newline))
        (else (display "A typo? try: letloop store build DERIVATION.scm\n") (exit 1)))))

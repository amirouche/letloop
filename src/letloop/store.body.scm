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
;;
;; A derivation with no script takes a second, shorter path: its
;; fetches land straight in the output directory, hash-verified, with
;; no rootfs and no sandbox involved at all. Everything after that --
;; hashing, expected-hash verification, placement, the .drv sidecar --
;; is identical either way.

;; Where the store lives, most specific first:
;;
;;   $LETLOOP_STORE            the store directory outright
;;   $LETLOOP_PROJECT_PATH     a project's letloop directory; the store
;;                             is `store` inside it
;;   ~/.local/letloop/store    otherwise
;;
;; The middle one is what keeps a checkout's builds out of the user's
;; own store: ./venv points it at $LETLOOP_PREFIX/letloop, so working
;; on letloop fills local/letloop/store rather than the store a user
;; has been accumulating packages in. Same reason a language runtime
;; grows a per-project directory -- one machine, several worlds, and
;; nothing shared between them by accident.
;;
;; $LETLOOP_STORE stays because a caller sometimes wants to name a
;; store directly, and because every check here does.
(define (store-directory)
  (cond
   ((getenv "LETLOOP_STORE"))
   ((getenv "LETLOOP_PROJECT_PATH")
    => (lambda (project) (string-append project "/store")))
   (else (string-append (getenv "HOME") "/.local/letloop/store"))))

(define (store-tmp-directory)
  (string-append (store-directory) "/.tmp"))

;; <name>-<hash>, not Nix's <hash>-<name>. Nix puts the hash first
;; because it scans built outputs for store paths and rewrites them in
;; place, which a fixed-width leading field makes tractable. letloop
;; does none of that, so the reason does not carry over -- and putting
;; the name first is what makes `ls` sort usefully, keeps every version
;; of a package adjacent, and lets a name be tab-completed at all.
(define (store-path hash name)
  (string-append (store-directory) "/" name "-" hash))

;; -> a host directory to bind as the build's rootfs: either one that
;; already exists, or the output of the derivation that builds it,
;; produced first through RESOLVE-DERIVATION.
(define (store-scaffold-directory)
  (string-append (store-directory) "/.scaffold"))

;; The rootfs for a (root (host)) build: a directory of symlinks into
;; the host's own top-level directories, read-only once bound.
;;
;; Provisioned here rather than by whoever runs letloop, so that
;; building into an empty store bootstraps itself instead of failing
;; on a path someone was supposed to have created. Symlinks rather
;; than copies because nothing reads them except the one assembly
;; script, which uses the host's sh and tar to unpack bytes it never
;; inspects -- nothing of the host reaches the output.
(define (provision-host-scaffold!)
  (let ((scaffold (store-scaffold-directory)))
    (system! (format #f "rm -rf ~a" (shell-single-quote scaffold)))
    (system! (format #f "mkdir -p ~a" (shell-single-quote scaffold)))
    (for-each
     (lambda (name)
       (let ((source (string-append "/" name)))
         (when (file-exists? source)
           (system! (format #f "ln -s ~a ~a"
                             (shell-single-quote source)
                             (shell-single-quote (string-append scaffold "/" name)))))))
     '("usr" "bin" "sbin" "lib" "lib64" "etc"))
    scaffold))

(define (resolve-build-environment-rootfs build-environment resolve-reference)
  (cond
   ((build-environment-host? build-environment) (provision-host-scaffold!))
   ((or (build-environment-derivation? build-environment)
        (build-environment-package? build-environment))
    (resolve-reference (build-environment-directory build-environment)))
   (else (build-environment-directory build-environment))))

;; A reference is what one derivation names another by: either a path
;; to a file, or the name of a library that carries the derivation as a
;; value. Paths only work between derivations sitting in one checkout;
;; a library name resolves wherever letloop's own libraries do, which
;; is what lets a package set ship inside a release.
(define (package-reference? reference) (pair? reference))

(define (reference-derivation reference)
  (if (package-reference? reference)
      (derivation-parse (eval 'package (environment reference)) reference)
      (derivation-read reference)))

;; What identifies a derivation for the build cache and the session
;; key. The printed form rather than a file's bytes, so the two kinds
;; of reference are treated alike -- and so that editing a comment
;; does not invalidate a build, which hashing the file did.
(define (reference-identity reference)
  (format #f "~s" (if (package-reference? reference)
                      (eval 'package (environment reference))
                      (call-with-input-file reference read))))

;; The library a package name resolves to: `letloop store build blake3`
;; means (letloop package blake3). Deliberately not (letloop store
;; blake3) -- that namespace already holds the store's own modules, so
;; a package named hash or fetch would collide with one of them.
(define (package-library-name name)
  (list 'letloop 'package (string->symbol name)))

;; A (derivation "...") reference resolves relative to the directory of
;; the derivation file that names it, not the invoker's cwd -- so a
;; chain of derivations sitting next to each other can reference
;; siblings by bare filename and keep working wherever it is built from.
(define (derivation-reference-path referrer-path reference)
  (if (or (package-reference? reference)
          (not (string? referrer-path))
          (char=? (string-ref reference 0) #\/))
      reference
      (let loop ((index (fx- (string-length referrer-path) 1)))
        (cond
         ((fx<? index 0) reference)
         ((char=? (string-ref referrer-path index) #\/)
          (string-append (substring referrer-path 0 (fx+ index 1)) reference))
         (else (loop (fx- index 1)))))))

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

(define (store-write-drv! destination reference)
  ;; A package carries its derivation in a library, so there is no file
  ;; to copy; the sidecar is only for the file form.
  (unless (package-reference? reference)
    (system! (format #f "cp ~a ~a.drv"
                      (shell-single-quote reference)
                      (shell-single-quote destination)))))

;; A derivation with no script (and so no build-environment) is
;; fetch-only: each declared fetch lands directly in the output
;; directory under its own name, hash-verified by fetch-verify! exactly
;; as it would be for a sandboxed build's inputs. Nothing is unpacked
;; and no sandbox runs -- see derivation.body.scm's header for why the
;; bootstrap chain needs a shape that requires no rootfs at all.
(define (run-fetch-only-build! fetches output-directory)
  (system! (format #f "mkdir -p ~a" (shell-single-quote output-directory)))
  (for-each
   (lambda (f)
     (fetch-verify! (fetch-name f) (fetch-url f) (fetch-hash-hex f)
                     (string-append output-directory "/" (fetch-name f))))
   fetches))

;; A store path is content-addressed, so a build script cannot name its
;; own inputs: their hashes are not known until they are built, and by
;; then the script is already written. Nix solves this by substituting
;; the resolved paths into the build environment; the equivalent here
;; is a symlink per input under <scratch>/inputs/<name>, which the
;; script sees as /build/inputs/<name> -- a stable name it can be
;; written against. The link points at the input's real store path,
;; which is separately bind-mounted at that same absolute path inside
;; the sandbox, so following it works.
;;
;; Only (derivation "...") inputs get one: a literal store path in
;; `inputs` was already something the author typed out and can type
;; again.
(define (link-derivation-inputs! scratch-directory named-inputs)
  (unless (null? named-inputs)
    (let ((inputs-directory (string-append scratch-directory "/inputs")))
      (system! (format #f "mkdir -p ~a" (shell-single-quote inputs-directory)))
      (for-each
       (lambda (named)
         (system! (format #f "ln -s ~a ~a"
                           (shell-single-quote (cdr named))
                           (shell-single-quote (string-append inputs-directory "/" (car named))))))
       named-inputs))))

;; Everything a sandboxed build depends on from outside its own
;; derivation file: the rootfs it runs in, its inputs as absolute
;; paths, and those of them that carry a name to be reachable under
;; /build/inputs. Resolved up front, before the build, so it can also
;; be folded into the build's cache key.
(define-record-type* <resolved>
  (make-resolved rootfs inputs named-inputs)
  resolved?
  (rootfs resolved-rootfs)
  (inputs resolved-inputs)
  (named-inputs resolved-named-inputs))

(define (input-reference? input)
  (or (input-derivation-reference? input)
      (input-package-reference? input)))

;; What an input names another derivation by: a sibling file for
;; (derivation "..."), a library name for (package ...).
(define (input-reference input)
  (if (input-package-reference? input)
      (input-package-name input)
      (input-derivation-path input)))

(define (resolve-dependencies d derivation-path resolve-derivation)
  (if (not (derivation-script d))
      (make-resolved #f '() '())
      (make-resolved
       (resolve-build-environment-rootfs (derivation-build-environment d) resolve-derivation)
       (map (lambda (input)
              (if (input-reference? input)
                  (resolve-derivation (input-reference input))
                  input))
            (derivation-inputs d))
       (map (lambda (input)
              (let* ((reference (input-reference input))
                     (resolved (derivation-reference-path derivation-path reference)))
                (cons (derivation-name (reference-derivation resolved))
                      (resolve-derivation reference))))
            (filter input-reference? (derivation-inputs d))))))

;; The build's own cache key doubles as its session key: it already
;; hashes the derivation and everything resolved into it, which is
;; exactly "the identity of the source and any source dependencies"
;; that a stable gensym key has to be derived from. Two builds of the
;; same thing then produce the same bytes, and two builds of different
;; things cannot collide.
(define (run-sandboxed-build! d scratch-directory resolved key)
  (run-fetches! (derivation-fetches d) scratch-directory)
  (link-derivation-inputs! scratch-directory (resolved-named-inputs resolved))
  (write-build-script! scratch-directory (derivation-script d))
  (sandbox-build! (resolved-rootfs resolved) scratch-directory (resolved-inputs resolved) key))

;; The store is addressed by what a build produced, which is only
;; knowable after running it -- so on its own it can dedup an output
;; but never skip the work that made it. For a chain a few derivations
;; deep that is the difference between rebuilding ChezScheme every time
;; something downstream changes and not.
;;
;; This keys a build on everything that determines it: the derivation
;; file's own bytes, the rootfs it runs in, and its resolved inputs.
;; Those are exactly the things that, changed, could change the output,
;; and all of them are known before the build starts. Same key, same
;; output -- under the determinism the store already assumes when it
;; treats two identical outputs as interchangeable.
;;
;; It is a cache, not a source of truth: every entry points at a store
;; path that was hashed from real content, and an entry whose target
;; has since been removed is ignored rather than trusted.
(define (store-cache-directory)
  (string-append (store-directory) "/.cache"))

;; What a path contributes to a cache key. A store path already has its
;; content hash in its own name, so the name is enough and there is no
;; reason to re-hash a 300 MB toolchain on every build. Anything else
;; -- a fixture rootfs, a working tree bind-mounted as a literal input
;; -- is named by a path whose contents can change underneath us, so it
;; has to be hashed. Keying those by path alone would hand back a stale
;; output the moment the tree behind it changed, which is exactly the
;; sort of wrong answer a cache must not give.
(define (path-cache-identity path)
  (let ((store (string-append (store-directory) "/")))
    (if (and (fx>= (string-length path) (string-length store))
             (string=? (substring path 0 (string-length store)) store))
        path
        (string-append path ":" (store-hash-directory path)))))

(define (build-cache-key derivation-path resolved)
  (define hasher (make-blake3))
  (blake3-update! hasher (string->utf8 (reference-identity derivation-path)))
  (blake3-update! hasher
                  (string->utf8
                   (format #f "\nrootfs ~a\n"
                           (let ((rootfs (resolved-rootfs resolved)))
                             (if rootfs (path-cache-identity rootfs) "none")))))
  (for-each (lambda (input)
              (blake3-update! hasher
                              (string->utf8 (format #f "input ~a\n" (path-cache-identity input)))))
            (resolved-inputs resolved))
  (let ((digest (blake3-finalize hasher 32)))
    (blake3-close! hasher)
    (bytevector->hex-string digest)))

(define (build-cache-ref key)
  (let ((entry (string-append (store-cache-directory) "/" key)))
    (and (file-exists? entry)
         (let ((destination (call-with-input-file entry get-line)))
           (and (string? destination)
                (file-exists? destination)
                destination)))))

(define (build-cache-set! key destination)
  (system! (format #f "mkdir -p ~a" (shell-single-quote (store-cache-directory))))
  (call-with-output-file (string-append (store-cache-directory) "/" key)
    (lambda (port) (display destination port) (newline port))))

;; Builds DERIVATION-PATH, first building anything it references
;; through (derivation "...") -- as its build-environment root, as an
;; input, or transitively through either.
;;
;; BUILDING is the list of paths on the current resolution stack, so a
;; reference cycle raises rather than looping forever. BUILT memoizes
;; path -> store path for this call, so a diamond -- two inputs naming
;; the same nested derivation -- resolves it once; the on-disk cache
;; above then carries the same saving across calls. Resolution itself
;; stays plain depth-first, one derivation at a time: still not a
;; scheduler.
(define (store-build/resolving derivation-path building built)
  (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
  (when (member derivation-path building)
    (error 'store-build "cyclic derivation reference" derivation-path building))
  (let ((memoized (assoc derivation-path (unbox built))))
    (if memoized
        (cdr memoized)
        (let* ((d (reference-derivation derivation-path))
               (resolve-derivation
                (lambda (reference)
                  (store-build/resolving
                   (derivation-reference-path derivation-path reference)
                   (cons derivation-path building)
                   built)))
               (resolved (resolve-dependencies d derivation-path resolve-derivation))
               (key (build-cache-key derivation-path resolved))
               (cached (build-cache-ref key)))
          (define (remember destination)
            (set-box! built (cons (cons derivation-path destination) (unbox built)))
            destination)
          (if cached
              (remember cached)
              (let* ((ignore-0 (system! (format #f "mkdir -p ~a"
                                                 (shell-single-quote (store-tmp-directory)))))
                     (scratch-directory (mkdtemp (string-append (store-tmp-directory)
                                                                 "/build-XXXXXX")))
                     (output-directory (string-append scratch-directory "/" (derivation-output d))))
                (if (derivation-script d)
                    (run-sandboxed-build! d scratch-directory resolved key)
                    (run-fetch-only-build! (derivation-fetches d) output-directory))
                (unless (file-exists? output-directory)
                  (error 'store-build "declared output not produced by the build"
                         (derivation-output d)))
                (let ((hash (store-hash-directory output-directory)))
                  (verify-expected-output-hash! (derivation-expected-output-hash d)
                                                 hash derivation-path)
                  (let ((destination (store-place! output-directory hash (derivation-name d))))
                    (store-write-drv! destination derivation-path)
                    (build-cache-set! key destination)
                    (remember destination)))))))))

;; -> the resulting store path.
(define (store-build derivation-path)
  (store-build/resolving derivation-path '() (box '())))

(define (letloop-store args)
  (if (null? args)
      (begin
        (display "Choose: build.\nAs of yet, only: letloop store build DERIVATION.scm\n")
        (exit 1))
      (case (string->symbol (car args))
        ((build)
         ;; A path if it names a file, otherwise a package: `letloop
         ;; store build blake3` builds what (letloop package blake3)
         ;; defines.
         (let ((argument (cadr args)))
           (display (store-build (if (file-exists? argument)
                                     argument
                                     (package-library-name argument))))
           (newline)))
        (else (display "A typo? try: letloop store build DERIVATION.scm\n") (exit 1)))))

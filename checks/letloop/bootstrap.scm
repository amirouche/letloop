#!chezscheme
;; The bootstrap chain, from an empty store to a statically linked,
;; relocatable letloop, and every gate that proves each step did what
;; it is for. Run it with upstream Chez, from anywhere:
;;
;;   scheme --script checks/letloop/bootstrap.scm
;;
;; No letloop is needed to run it, on purpose. It used to be a shell
;; script driving `letloop store build`, which tied producing the
;; first static letloop to already having a letloop -- the dynamic,
;; glibc-linked one `make letloop` builds with the host compiler. That
;; is the binary this chain exists to make unnecessary. (letloop store)
;; is an ordinary library and runs under a stock scheme, so this
;; program imports it from ./src and calls store-build directly; the
;; one thing a plain scheme cannot do on its own is HTTPS, and for
;; that the fetcher shells out to curl (fetch-with-curl), the single
;; network tool the seed host has to provide. Every fetched byte is
;; still hash-checked by fetch-verify!, so curl is trusted for
;; transport, never for content.
;;
;; Every step is gated, and gated on what it is actually for: fetches
;; on their contents, rootfs assemblies on the tools they must
;; provide, compilers on a program that compiles and runs, liburing on
;; symbols that link *and* run, the letloop it produces on compiling
;; and running programs from a copy outside the store.
;;
;; The chain trusts exactly two prebuilt binaries, both pinned by
;; BLAKE3 (see each package library's own header for the provenance
;; and the reasoning): musl.cc's toolchain and one BusyBox. The
;; from-source BusyBox retires the second: after it, that binary is
;; load-bearing only for the first rootfs assembly, and its bytes
;; appear in nothing the chain produces. The compiler cannot be
;; retired the same way without a full source bootstrap, which this
;; chain deliberately does not attempt.
;;
;; The first rootfs assembly is the one step that needs a rootfs it
;; cannot have built -- see (letloop package rootfs)'s header. It asks
;; for (root (host)), and the store provisions symlinks into the
;; host's own /usr and /bin for it, so building into an empty store
;; bootstraps itself rather than needing anything staged first.
;;
;; Opt-in, NOT run by `make check`: fetches ~95 MB, compiles make,
;; BusyBox, LibreSSL and Chez from source, and needs bwrap to build
;; with, curl to fetch with, and file, readelf, nm, cmp and sha256sum
;; to check what it built. Those are the gates' own tools, not the
;; chain's -- nothing they inspect ends up depending on them. A
;; missing one fails at the gate that needs it, by name.

(import (chezscheme))

;; ---- where we are ----------------------------------------------------

(define root
  ;; The checkout, found from this script's own path rather than from
  ;; the caller's cwd, so the command above works from anywhere.
  (let* ((script (car (command-line)))
         (up (lambda (path) (let ((parent (path-parent path)))
                              (if (string=? parent "") "." parent))))
         (relative (up (up (up script)))))
    (parameterize ((current-directory relative))
      (current-directory))))

(define src (string-append root "/src"))
(define workdir "/tmp/letloop-bootstrap")
(define store (string-append workdir "/store"))

(library-directories (list src))
(source-directories (list src))

;; dlopen(NULL): how a stock, dynamically linked scheme reaches libc
;; for the foreign-procedures the store makes -- readlink in (letloop
;; store hash), mkdtemp in store-build. A compiled letloop needs none
;; of this, its host registers those symbols in C before any Scheme
;; runs, and its libraries assume as much: Chez invokes a library body
;; on first use, not at import, so whichever of them runs first is the
;; one that would fail here, by name, with `no entry for "readlink"`.
;; Done once, up front, by the one program that runs them under an
;; upstream scheme.
(load-shared-object #f)

(import (letloop store)
        (letloop store fetch)
        (letloop store hash))

(putenv "LETLOOP_STORE" store)
(fetch-downloader fetch-with-curl)

;; ---- helpers ----------------------------------------------------------

(define (say . parts)
  (for-each display parts)
  (newline)
  (flush-output-port (current-output-port)))

(define (fail . parts)
  (apply say "FAIL: " parts)
  (exit 1))

(define (output command)
  ;; Captured stdout, the way the gates want it: a `grep -q` that exits
  ;; early kills its producer with SIGPIPE, and a status check on that
  ;; pipeline then reports a failure for a symbol it did find, or a
  ;; success for one it did not.
  (call-with-values (lambda () (open-process-ports command 'block (native-transcoder)))
    (lambda (stdin stdout stderr pid)
      (close-port stdin)
      (let ((text (get-string-all stdout)))
        (close-port stdout)
        (close-port stderr)
        (if (eof-object? text) "" text)))))

(define (output* command)
  (let ((text (output command)))
    (if (and (positive? (string-length text))
             (char=? (string-ref text (- (string-length text) 1)) #\newline))
        (substring text 0 (- (string-length text) 1))
        text)))

(define (contains? haystack needle)
  (let ((n (string-length needle)) (h (string-length haystack)))
    (let loop ((index 0))
      (cond
       ((> (+ index n) h) #f)
       ((string=? (substring haystack index (+ index n)) needle) #t)
       (else (loop (+ index 1)))))))

(define (contains-ci? haystack needle)
  (contains? (string-downcase haystack) (string-downcase needle)))

(define (mkdtemp template)
  ((foreign-procedure "mkdtemp" (string) string) template))

(define (temporary-directory)
  (mkdtemp "/tmp/letloop-bootstrap-XXXXXX"))

(define (q path) (shell-single-quote path))

(define (file-size path)
  (call-with-port (open-file-input-port path) port-length))

(define (needs-dynamic-loader? path)
  ;; "static-pie linked" and "statically linked" are both fully
  ;; static; what matters is that there is no INTERP segment.
  (contains? (output (format #f "readelf -l ~a" (q path))) "interpreter"))

(define (build name)
  ;; One package by name, the way `letloop store build NAME` resolves
  ;; it: (letloop package NAME), from ./src.
  (let ((destination (store-build (list 'letloop 'package name))))
    (say name ": " destination)
    destination))

(define (require-file path what)
  (unless (file-exists? path)
    (fail what ": " path)))

;; The relocated letloop runs with nothing of this checkout's
;; environment: ./venv exports LETLOOP_PREFIX and SCHEME, and both
;; would let a copy find this tree's sources or boot files instead of
;; its own, turning a relocation gate into a gate on the checkout.
;; LETLOOP_STORE stays: the copy carries no store, and compiling a
;; program that links tls has to find the archives somewhere.
(define clean-env "env -u LETLOOP_PREFIX -u SCHEME -u LD_LIBRARY_PATH")

;; ---- the two fetched artifacts -----------------------------------------
;;
;; Gated on their own before anything is built from them: a fetch that
;; quietly produced the wrong thing would otherwise surface as a
;; confusing failure several derivations later.

(system! (format #f "mkdir -p ~a" (q store)))

(define toolchain (build 'toolchain))
(let ((tarball (string-append toolchain "/x86_64-linux-musl-native.tgz")))
  (unless (and (file-exists? tarball) (positive? (file-size tarball)))
    (fail "the toolchain tarball is missing or empty")))

(define shell (build 'shell))
(unless (contains-ci? (output (format #f "file ~a" (q (string-append shell "/busybox"))))
                      "statically linked")
  (fail "the fetched busybox is not statically linked"))

;; ---- rootfs, from those, then from source ------------------------------

;; Building the rootfs pulls in both fetch-only derivations through its
;; own (package ...) input references -- store-build resolves them
;; depth-first, so this one call runs the whole chain.
(define rootfs (build 'rootfs))
(require-file (string-append rootfs "/bin/gcc") "no gcc in the assembled rootfs")
(require-file (string-append rootfs "/bin/sh") "no sh in the assembled rootfs")

;; The from-source rootfs: same shape, but assembled out of components
;; this chain compiled rather than fetched. Pulls in make and BusyBox
;; through its own (package ...) inputs.
(define rootfs-final (build 'rootfs-final))
(for-each (lambda (tool)
            (require-file (string-append rootfs-final "/bin/" tool)
                          (string-append "no " tool " in the final rootfs")))
          '("gcc" "make" "busybox" "sh"))

;; The prebuilt BusyBox must not have survived into it.
(when (zero? (system (format #f "cmp -s ~a ~a"
                             (q (string-append rootfs-final "/bin/busybox"))
                             (q (string-append shell "/busybox")))))
  (fail "final rootfs still carries the prebuilt busybox"))

;; make is linked static like everything else here, so it runs from a
;; store path directly rather than only from inside the rootfs.
(unless (contains? (output (format #f "~a --version" (q (string-append rootfs-final "/bin/make"))))
                   "GNU Make")
  (fail "the from-source make does not run standalone"))

;; ---- C, inside the rootfs the chain assembled --------------------------

;; The real milestone: a derivation whose build-environment is the
;; assembled rootfs itself, compiling C with nothing from Alpine or
;; from the host in its sandbox.
(define hello (build 'hello))
(when (needs-dynamic-loader? (string-append hello "/hello"))
  (fail hello "/hello needs a dynamic loader"))

;; Relocatability: run it outside the store and outside any sandbox.
(define elsewhere (temporary-directory))
(system! (format #f "cp ~a ~a" (q (string-append hello "/hello")) (q (string-append elsewhere "/hello"))))
(let ((text (output* (q (string-append elsewhere "/hello")))))
  (unless (string=? text "hello from the bootstrap toolchain")
    (fail "unexpected output: " text)))

;; ---- ChezScheme and letloop itself, with Alpine nowhere in sight -------

;; The source tree is staged fresh each run rather than bind-mounted
;; from the working directory: the build needs a writable copy, and a
;; stale snapshot silently builds the wrong thing. Only tracked files,
;; so local/ and other build output stay out of it -- which does mean
;; a new file has to be `git add`ed before it is visible here, and
;; shows up as "library not found" from inside the sandbox if it is
;; not. The path is a contract: (letloop package letloop) and (letloop
;; package flow2) copy /tmp/letloop-bootstrap/letloop-src by name.
(let ((staged (string-append workdir "/letloop-src")))
  (system! (format #f "rm -rf ~a && mkdir -p ~a" (q staged) (q staged)))
  (system! (format #f "cd ~a && git ls-files -z | tar --null -T - -cf - | tar -xf - -C ~a"
                   (q root) (q staged))))

;; liburing, gated on the archive letloop actually links against. The
;; makefile's probe for it is silent when it fails, producing a letloop
;; with no io_uring symbols that looks healthy until something reaches
;; flow, flow2 or review.
(require-file (string-append (build 'liburing) "/lib/liburing-ffi.a")
              "no liburing-ffi.a, so letloop would link without io_uring")
(require-file (string-append (build 'blake3) "/lib/libblake3.a")
              "no libblake3.a, so letloop could not hash a store output")

;; The rest of letloop's FFI libraries, as static archives -- not
;; linked into the bootstrap letloop itself the way liburing and
;; blake3 are, but built and gated here so a `letloop compile`
;; consumer has something proven to link against, and so a change to
;; any of these derivations is caught before it reaches a user. oprf
;; and opaque exercise (package ...) inputs that are themselves
;; (package ...) derivations, the first place in this chain two
;; application-level packages depend on each other.
(for-each
 (lambda (pair)
   (let ((name (car pair)) (archive (cdr pair)))
     (require-file (string-append (build name) "/lib/" archive)
                   (string-append "no " archive))))
 '((argon2 . "libargon2.a")
   (sodium . "libsodium.a")
   (picohttpparser . "libpicohttpparser.a")
   (oprf . "liboprf.a")
   (opaque . "libopaque.a")))

;; The largest build in this chain: real LibreSSL, not Debian/Ubuntu's
;; libretls shim -- see (letloop package tls)'s own header for why that
;; distinction matters here specifically.
(let ((tls (build 'tls)))
  (for-each (lambda (archive)
              (require-file (string-append tls "/lib/" archive)
                            (string-append "no " archive)))
            '("libtls.a" "libssl.a" "libcrypto.a")))

(define letloop (build 'letloop))
(define letloop-binary (string-append letloop "/bin/letloop"))

(let ((symbols (output (format #f "nm ~a" (q letloop-binary)))))
  (for-each (lambda (pair)
              (unless (contains? symbols (car pair))
                (fail "the bootstrap letloop carries no " (cdr pair) " symbols")))
            '(("io_uring_queue_init" . "io_uring")
              ("blake3_hasher_init" . "blake3")
              ("tls_connect" . "tls"))))
(when (needs-dynamic-loader? letloop-binary)
  (fail letloop-binary " needs a dynamic loader"))

;; ---- that letloop, relocated -----------------------------------------
;;
;; It has to be a working letloop, not just one that prints a version:
;; run it from a copy outside the store, on this host's own libc, with
;; this checkout's environment scrubbed (see clean-env).

(define elsewhere2 (temporary-directory))
(system! (format #f "cp -a ~a ~a" (q (string-append letloop "/.")) (q (string-append elsewhere2 "/"))))
(define relocated (string-append elsewhere2 "/bin/letloop"))
(define work (string-append elsewhere2 "/work"))
(system! (format #f "mkdir -p ~a" (q work)))

(define (relocated-run command)
  ;; COMMAND, with the relocated letloop's environment scrubbed.
  (format #f "~a ~a" clean-env command))

(unless (contains? (output (relocated-run (format #f "~a version" (q relocated))))
                   "Chez Scheme Version")
  (fail "bootstrap letloop cannot report its version"))

(define (write-file! path text)
  (call-with-output-file path (lambda (port) (display text port)) 'truncate))

(define (relocated-compile! library)
  ;; Compiled rather than exec'd: `letloop exec` is gone, so a program
  ;; is built and then run. Compiling is the path this letloop has to
  ;; support on a foreign host, and it re-executes itself as the
  ;; compiler child to do it.
  (let ((log (string-append work "/compile.log")))
    (unless (zero? (system (format #f "cd ~a && ~a > ~a 2>&1"
                                   (q work)
                                   (relocated-run (format #f "~a compile . ~a main" (q relocated) library))
                                   (q log))))
      (fail "relocated bootstrap letloop cannot compile " library ":\n"
            (output (format #f "cat ~a" (q log)))))))

(write-file! (string-append work "/hi.scm")
             "(library (hi)
  (export main)
  (import (chezscheme))
  (define (main . args) (display \"bootstrap letloop works\\n\")))
")
(relocated-compile! "hi.scm")
(let ((text (output* (relocated-run (q (string-append work "/a.out"))))))
  (unless (string=? text "bootstrap letloop works")
    (fail "bootstrap letloop cannot run a program: " text)))

;; The actual proof static tls linking closes a real gap, not just
;; that it compiles: a genuine HTTPS request, from the relocated copy,
;; with no host libtls.so and no host CA store -- both would have to
;; come from inside the copy for this to work at all. Network-
;; dependent, like the other live-host gates here.
(write-file! (string-append work "/https-probe.scm")
             "(library (https-probe)
  (export main)
  (import (chezscheme) (letloop www))
  (define (main . args)
    (call-with-values (lambda () (www-request 'GET \"https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/\" '() (bytevector)))
      (lambda (code headers body)
        (display code) (newline)))))
")
(relocated-compile! "https-probe.scm")
(let ((text (output (relocated-run (format #f "~a 2>&1" (q (string-append work "/a.out")))))))
  (unless (contains? text "200")
    (fail "relocated bootstrap letloop cannot make an HTTPS request: " text)))

;; The same program, alone. Beside the copy above it finds
;; lib/letloop/cert.pem by walking up from itself, which proves the
;; file rung of (letloop tls base)'s resolve-ca-actions and nothing
;; else. Copied to an empty directory, with SSL_CERT_FILE, SSL_CERT_DIR
;; and every LETLOOP_* variable unset, the only CA source left is the
;; bundle `letloop compile` embedded in it -- and that is the case the
;; store is for: ./a.out alone is the deliverable.
(define bare (temporary-directory))
(system! (format #f "cp ~a ~a" (q (string-append work "/a.out")) (q (string-append bare "/probe"))))
(let ((text (output (format #f "cd ~a && env -u LETLOOP_PREFIX -u LETLOOP_STORE -u SCHEME -u SSL_CERT_FILE -u SSL_CERT_DIR ./probe 2>&1"
                            (q bare)))))
  (unless (contains? text "200")
    (fail "a compiled program alone, with no CA store beside it, cannot make an HTTPS request: " text)))

;; ---- self-hosting: the letloop the store built, running the store -----
;;
;; The point of all of it. Exercises blake3 statically -- without it
;; this fails at the first hash with "cannot dlopen shared object", so
;; a letloop that could compile programs but not drive the store.

(define selfhost (temporary-directory))
(define selfhost-store (string-append selfhost "/store"))

;; First, a fetch: the relocated letloop downloading over HTTPS with
;; its own static tls and its own lib/letloop/cert.pem, into an empty
;; store, and hash-checking what it got. This is the cold-start
;; question -- can a static letloop be the fetcher for its own chain
;; -- asked directly, on the smallest fetch-only package there is.
(let ((text (output* (format #f "LETLOOP_STORE=~a ~a 2>&1 | tail -1"
                             (q selfhost-store)
                             (relocated-run (format #f "~a store build shell" (q relocated)))))))
  (unless (and (file-exists? (string-append text "/busybox"))
               (positive? (file-size (string-append text "/busybox"))))
    (fail "the bootstrap letloop cannot fetch into its own store: " text)))

;; Then a sandboxed build, driven by it.
(write-file! (string-append selfhost "/self.derivation.scm")
             (format #f "(derivation
 (name \"self-hosted\")
 (build-environment (root (directory ~s)))
 (script \"set -e\\n\" \"mkdir -p out\\n\" \"echo self-hosted > out/marker\\n\")
 (output \"out\"))
" rootfs-final))
(let ((text (output* (format #f "LETLOOP_STORE=~a ~a 2>&1 | tail -1"
                             (q selfhost-store)
                             (relocated-run (format #f "~a store build ~a"
                                                    (q relocated)
                                                    (q (string-append selfhost "/self.derivation.scm"))))))))
  (unless (string=? (output* (format #f "cat ~a" (q (string-append text "/marker")))) "self-hosted")
    (fail "the bootstrap letloop cannot run its own store: " text))
  (say "self-hosted build: " text))

;; And its own package manager runs -- the subsystem that produced it.
(unless (contains? (output (relocated-run (format #f "~a store 2>&1" (q relocated))))
                   "letloop store build")
  (fail "bootstrap letloop's store subcommand does not run"))

;; ---- what it can build ------------------------------------------------

;; The io_uring machinery actually running, not merely linked: checks
;; of ring setup, submit, wait, cancel, socket and file I/O.
(let* ((flow2 (build 'flow2))
       (passed (string->number
                (output* (format #f "grep -c '\\*\\* SUCCESS' ~a" (q (string-append flow2 "/result")))))))
  (unless (and passed (>= passed 50))
    (fail "only " passed " flow2 checks ran; expected the full suite")))

;; The core promise on its own: a Scheme program in, a standalone
;; static binary out. bootstrap-hello above compiles C and so proves
;; the toolchain; this proves what the store is actually for. No
;; archive, so `letloop compile` takes its ordinary path and invokes
;; no C compiler.
(define scheme-hello (build 'scheme-hello))
(when (needs-dynamic-loader? (string-append scheme-hello "/hello"))
  (fail "the compiled Scheme program needs a dynamic loader"))
(system! (format #f "cp ~a ~a" (q (string-append scheme-hello "/hello")) (q (string-append elsewhere "/scheme-hello"))))
(let ((text (output* (q (string-append elsewhere "/scheme-hello")))))
  (unless (string=? text "hello from a scheme program the store built")
    (fail "the compiled Scheme program does not run relocated: " text)))

;; Reproducibility: the same derivation, built twice, byte for byte.
;; Chez names gensyms from a per-process random session key and writes
;; those names into every fasl, so without pinning it two builds of
;; identical sources differ -- they stay $fasl-file-equal?, but the
;; bytes move, and a store cannot be addressed by something that
;; moves. store-build pins it from the build's own cache key, which is
;; exactly "the identity of the source and its dependencies".
;;
;; Forced by dropping the cache entry and the output: otherwise the
;; second call is a cache hit and proves nothing, which it silently
;; did the first time this was written.
(let* ((sha256 (lambda (path) (substring (output* (format #f "sha256sum ~a" (q path))) 0 64)))
       (first (sha256 (string-append scheme-hello "/hello")))
       (key (output* (format #f "grep -rl ~a ~a 2>/dev/null | head -1"
                             (q (path-last scheme-hello))
                             (q (string-append store "/.cache/"))))))
  (unless (string=? key "")
    (system! (format #f "rm -f ~a" (q key))))
  (system! (format #f "rm -rf ~a ~a" (q scheme-hello) (q (string-append scheme-hello ".drv"))))
  (let* ((again (build 'scheme-hello))
         (second (sha256 (string-append again "/hello"))))
    (unless (string=? first second)
      (fail "two builds of the same derivation differ\n  " first "\n  " second))
    (unless (string=? again scheme-hello)
      (fail "reproducible output landed at a different store path"))
    (say "reproducible: rebuilt byte-identical")))

;; The widest compile in the repo: review pulls in tea/*, liburing/low,
;; sq and heap, all amalgamated into one program. Compile-only -- it
;; is an interactive TUI, and its io_uring machinery is covered above
;; by actually running rings rather than drawing a screen.
(let ((review (build 'review)))
  (unless (and (file-exists? (string-append review "/letloop-review"))
               (positive? (file-size (string-append review "/letloop-review"))))
    (fail "letloop review did not compile")))

;; The loop closes: that letloop compiling against a C static library,
;; with the toolchain this chain built.
(define static-lib (build 'static-lib))
(when (needs-dynamic-loader? (string-append static-lib "/demo"))
  (fail static-lib "/demo needs a dynamic loader"))
(system! (format #f "cp ~a ~a" (q (string-append static-lib "/demo")) (q (string-append elsewhere "/demo"))))
(let ((text (output* (format #f "~a | tail -1" (q (string-append elsewhere "/demo"))))))
  (unless (string=? text "42")
    (fail "the static-library demo does not run relocated: " text)))

(for-each (lambda (directory) (system! (format #f "rm -rf ~a" (q directory))))
          (list elsewhere elsewhere2 bare selfhost))

(say "=== All tests passed ===")

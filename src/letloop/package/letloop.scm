#!chezscheme
(library (letloop package letloop)
  (export package)
  (import (chezscheme))

  ;; letloop itself, built in the bootstrap rootfs against the
  ;; bootstrap-built ChezScheme. This is the point Alpine is gone: the
  ;; sandbox here holds a musl toolchain, a from-source BusyBox and make,
  ;; a from-source ChezScheme, and letloop's own sources -- and nothing
  ;; from any distribution.
  ;;
  ;; The source tree arrives as a literal input path rather than a
  ;; (derivation ...) reference: it is the working tree being built, not
  ;; something the store produced, and bootstrap.sh stages a clean copy
  ;; of it at that path first. Literal inputs are bind-mounted at the
  ;; same absolute path inside the sandbox as outside, so the script
  ;; finds it exactly where the derivation names it.
  ;;
  ;; The tree is copied into /build before building because `make
  ;; letloop` writes .so and .wpo files next to each source file, and
  ;; inputs are mounted read-only.
  ;;
  ;; Two things this build needs that the store cannot provide as
  ;; inputs, and which the makefile was taught to live without rather
  ;; than have them installed: bash (SHELL is /bin/sh now; every recipe
  ;; was already POSIX) and GNU coreutils' `ln -sr` (the relative
  ;; install symlink is computed by hand now, since BusyBox's ln has no
  ;; -r). Both changes are in the makefile, not worked around here.
  (define package
    '(derivation
     (name "bootstrap-letloop")
     (build-environment (root (package (letloop package rootfs-final))))
     (inputs ("/tmp/letloop-bootstrap/letloop-src"
              (package (letloop package chezscheme))
              (package (letloop package liburing))
              (package (letloop package blake3))
              (package (letloop package tls))
              (package (letloop package picohttpparser))
              (package (letloop package sodium))
              (package (letloop package opaque))
              (package (letloop package oprf))
              (package (letloop package ca-certificates))))
     (script
      "set -e\n"
      "cp -a /tmp/letloop-bootstrap/letloop-src /build/src\n"
      ;; ChezScheme has to be copied out of the store before use, not used
      ;; in place: `make letloop` assembles the binary into the directory
      ;; holding the boot files, which it finds from $SCHEME's own resolved
      ;; location. Pointed at the input directly that is a read-only bind,
      ;; and the writes fail -- silently, since the recipe chains with `;`
      ;; rather than `&&`, leaving a dangling bin/letloop symlink as the
      ;; only evidence.
      ;; ChezScheme is copied *into the prefix being built*, not used
      ;; beside it. `make letloop` assembles the binary next to the boot
      ;; files, which it locates from $SCHEME's own resolved path, and then
      ;; links PREFIX/bin/letloop to it relatively -- so Chez has to live
      ;; under PREFIX for that link to resolve. This is the same layout a
      ;; normal ./venv install has.
      ;;
      ;; The trailing /. copies contents rather than the directory:
      ;; /build/inputs/<name> is itself a symlink into the store, and a
      ;; plain `cp -a` of it would just reproduce that symlink, leaving the
      ;; tree read-only.
      "mkdir -p /build/out\n"
      "cp -a /build/inputs/bootstrap-chezscheme/. /build/out/\n"
      "chmod -R u+w /build/out\n"
      "cd /build/src\n"
      "export SCHEME=/build/out/bin/scheme\n"
      "\"$SCHEME\" --version\n"
      ;; So the makefile's own probes for -luring-ffi/-lblake3/-ltls find
      ;; them and define LETLOOP_LIBURING_STATIC/LETLOOP_BLAKE3_STATIC/
      ;; LETLOOP_TLS_STATIC. Without these the probes simply fail and the
      ;; build proceeds *silently* without the symbols, leaving a letloop
      ;; that cannot run flow, flow2 or review (no io_uring), cannot
      ;; hash faster than the Scheme floor (no blake3), or cannot fetch
      ;; anything over HTTPS (no tls) -- which is exactly what happened
      ;; the first time this derivation was written, for the first two.
      ;; gcc reads all three of these itself; no makefile change beyond
      ;; the probes themselves is needed.
      "export LIBRARY_PATH=/build/inputs/bootstrap-liburing/lib:/build/inputs/bootstrap-blake3/lib:/build/inputs/bootstrap-tls/lib:/build/inputs/bootstrap-picohttpparser/lib:/build/inputs/bootstrap-sodium/lib:/build/inputs/bootstrap-opaque/lib:/build/inputs/bootstrap-oprf/lib\n"
      "export C_INCLUDE_PATH=/build/inputs/bootstrap-liburing/include:/build/inputs/bootstrap-blake3/include:/build/inputs/bootstrap-tls/include:/build/inputs/bootstrap-picohttpparser/include:/build/inputs/bootstrap-sodium/include:/build/inputs/bootstrap-opaque/include\n"
      "make letloop SCHEME=\"$SCHEME\" PREFIX=/build/out\n"
      ;; letloop-libraries (a `make letloop` prerequisite) does
      ;; `rm -rf $(PREFIX)/lib/letloop` before repopulating it, so this
      ;; has to land after `make letloop` finishes, not before -- a
      ;; copy placed earlier would just be wiped. (letloop tls base)'s
      ;; bundled-ca-file looks for exactly this path.
      "cp /build/inputs/bootstrap-ca-certificates/cert.pem /build/out/lib/letloop/cert.pem\n"
      ;; all three probes are silent either way, so check the symbols
      ;; really landed rather than discovering it at run time -- blake3
      ;; and tls in particular fail only once something reaches a hash
      ;; or a fetch
      "nm /build/out/bin/letloop > /build/symbols\n"
      "grep -q io_uring_queue_init /build/symbols\n"
      "grep -q blake3_hasher_init /build/symbols\n"
      "grep -q tls_init /build/symbols\n"
      ;; The ones with no Scheme fallback at all: under static musl
      ;; dlopen does not work, so an unregistered one is not slower,
      ;; it is absent -- (letloop http) loses its parser, and sodium
      ;; and opaque fail on first call.
      ;;
      ;; argon2 is deliberately not among them, and not an oversight:
      ;; libsodium vendors its own argon2 and defines three of the
      ;; four symbols (letloop argon2) resolves, so linking both
      ;; archives fails with "multiple definition". See the makefile,
      ;; which will not even probe for argon2 once sodium is linked.
      "grep -q phr_parse_request_wrapper /build/symbols\n"
      "grep -q sodium_init /build/symbols\n"
      "grep -q opaque_Register /build/symbols\n"
      ;; prove the letloop just built actually runs, here, rather than
      ;; leaving it to whoever picks the artifact up
      "/build/out/bin/letloop version\n")
     (output "out"))))

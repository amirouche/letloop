#!chezscheme
(library (letloop package argon2)
  (export package)
  (import (chezscheme))

  ;; libargon2, built from source against the bootstrap toolchain, as a
  ;; static archive -- for (letloop argon2), which dlopen's
  ;; libargon2.so.1 at runtime and has no fallback the way blake3 does.
  ;;
  ;; The upstream Makefile has an `install` target, but it branches on
  ;; `uname -s`/`uname -m` and, on Linux-x86_64, installs the library
  ;; under lib/x86_64-linux-gnu -- a Debian/Ubuntu-specific path that
  ;; would leave nothing at the flat out/lib every other package in this
  ;; chain uses. Building the archive directly (`make libargon2.a`) and
  ;; copying it, the header and the man page by hand sidesteps that
  ;; branch entirely, rather than fighting it with an override.
  ;;
  ;; No .so is built: nothing here consumes it, and the shared object
  ;; needs -fPIC and its own OS-specific SONAME handling this chain has
  ;; no use for.
  ;;
  ;; Source tarball fetched 2026-08-24 from the 20190702 tag, 1,505,307
  ;; bytes -- the same version the repo's own makefile builds.
  (define package
    '(derivation
     (name "bootstrap-argon2")
     (build-environment (root (package (letloop package rootfs-final))))
     (fetch (argon2.tar.gz
             (url "https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/20190702.tar.gz")
             (hash (blake3 "19acf613160b1f9a2b7782f14b8a6f1df670695b78b79f77a50a3af5086994b7"))))
     (script
      "set -e\n"
      "mkdir -p /build/out/lib /build/out/include /build/out/share/man/man1\n"
      "tar xzf fetch/argon2.tar.gz --no-same-owner\n"
      "cd phc-winner-argon2-20190702\n"
      "make libargon2.a\n"
      "cp libargon2.a /build/out/lib/\n"
      "cp include/argon2.h /build/out/include/\n"
      "cp man/argon2.1 /build/out/share/man/man1/\n"
      ;; the entry points (letloop argon2) resolves must be there, or
      ;; letloop links fine and fails at its first call
      "nm /build/out/lib/libargon2.a > /build/symbols\n"
      "grep -q ' T argon2_hash' /build/symbols\n"
      "grep -q ' T argon2id_hash_raw' /build/symbols\n")
     (output "out"))))

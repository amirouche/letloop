#!chezscheme
(library (letloop package blake3)
  (export package)
  (import (chezscheme))

  ;; BLAKE3, built from source against the bootstrap toolchain, as a
  ;; static archive -- for speed, not for correctness.
  ;;
  ;; (letloop blake3) falls back to (letloop blake3 scheme), which needs
  ;; no shared object at all, so the store hashes with or without this --
  ;; and (letloop store) itself imports (letloop blake3 scheme) directly,
  ;; not through that fallback, so this archive is for speeding up other
  ;; compiled programs, not for the store's own operation. What this
  ;; buys, where it is used, is about 128x: roughly 2.5 GB/s against
  ;; 20 MB/s, which on a 300 MB rootfs is the difference between an
  ;; instant and a quarter of a minute, paid on every build.
  ;;
  ;; It was briefly load-bearing: before the fallback existed, a
  ;; statically linked letloop had no loader to service the dlopen and
  ;; failed with "cannot dlopen shared object" the moment a build wanted
  ;; a hash -- a letloop the store built that could not drive the store.
  ;; Hashing is the store's own primitive, so making it depend on a
  ;; package the store must first build was the wrong shape.
  ;;
  ;; No build system to speak of: BLAKE3's C implementation is a fixed
  ;; list of sources plus per-architecture assembly, compiled directly.
  ;; This mirrors the repo's own `make blake3` target, which does the
  ;; same thing for the shared object, and is x86_64-only for the same
  ;; reason the rest of this chain is.
  ;;
  ;; Source tarball fetched 2026-08-23 from the 1.8.3 tag, 266,132 bytes
  ;; -- the same version the makefile pins.
  (define package
    '(derivation
     (name "bootstrap-blake3")
     (build-environment (root (package (letloop package rootfs-final))))
     (fetch (blake3.tar.gz
             (url "https://github.com/BLAKE3-team/BLAKE3/archive/refs/tags/1.8.3.tar.gz")
             (hash (blake3 "85f499fb88172eab22773a61fd6fd33a025f01e003c3ea2c53e1d080860ede2a"))))
     (script
      "set -e\n"
      "mkdir -p /build/out/lib /build/out/include\n"
      "tar xzf fetch/blake3.tar.gz --no-same-owner\n"
      "cd BLAKE3-1.8.3/c\n"
      "gcc -c -O3 blake3.c blake3_dispatch.c blake3_portable.c \\\n"
      "    blake3_sse2_x86-64_unix.S blake3_sse41_x86-64_unix.S \\\n"
      "    blake3_avx2_x86-64_unix.S blake3_avx512_x86-64_unix.S\n"
      "ar rcs libblake3.a blake3.o blake3_dispatch.o blake3_portable.o \\\n"
      "    blake3_sse2_x86-64_unix.o blake3_sse41_x86-64_unix.o \\\n"
      "    blake3_avx2_x86-64_unix.o blake3_avx512_x86-64_unix.o\n"
      "cp libblake3.a /build/out/lib/\n"
      "cp blake3.h /build/out/include/\n"
      ;; the three entry points (letloop blake3) resolves must be there, or
      ;; letloop links fine and fails at its first hash
      "nm /build/out/lib/libblake3.a > /build/symbols\n"
      "grep -q ' T blake3_hasher_init' /build/symbols\n"
      "grep -q ' T blake3_hasher_update' /build/symbols\n"
      "grep -q ' T blake3_hasher_finalize' /build/symbols\n")
     (output "out"))))

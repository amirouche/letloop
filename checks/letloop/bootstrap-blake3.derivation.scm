;; BLAKE3, built from source against the bootstrap toolchain, as a
;; static archive.
;;
;; Without this the bootstrap letloop cannot run `letloop store build`
;; at all: the store hashes every output with BLAKE3, (letloop blake3)
;; reaches it through define-shared-object, and a statically linked
;; musl binary has no dynamic loader to service the dlopen. It fails
;; with "cannot dlopen shared object, tried libblake3.so,
;; libblake3.so.1" the moment a build finishes and wants a hash -- so a
;; letloop built by the store could not itself drive the store.
;;
;; No build system to speak of: BLAKE3's C implementation is a fixed
;; list of sources plus per-architecture assembly, compiled directly.
;; This mirrors the repo's own `make blake3` target, which does the
;; same thing for the shared object, and is x86_64-only for the same
;; reason the rest of this chain is.
;;
;; Source tarball fetched 2026-08-23 from the 1.8.3 tag, 266,132 bytes
;; -- the same version the makefile pins.
(derivation
 (name "bootstrap-blake3")
 (build-environment (root (derivation "bootstrap-rootfs-final.derivation.scm")))
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
 (output "out"))

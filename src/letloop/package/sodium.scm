#!chezscheme
(library (letloop package sodium)
  (export package)
  (import (chezscheme))

  ;; libsodium, built from source against the bootstrap toolchain, as a
  ;; static archive -- for (letloop sodium), which dlopen's
  ;; libsodium.so at runtime, and for (letloop package oprf) and
  ;; (letloop package opaque), which link against it directly.
  ;;
  ;; --disable-shared: nothing in this chain consumes libsodium.so, and
  ;; building it costs a -fPIC pass and its own SONAME handling for no
  ;; reader. --enable-static keeps the archive libtool would otherwise
  ;; drop once shared is off.
  ;;
  ;; Standard autotools, same shape as (letloop package liburing): a
  ;; configure and a make install into /build/out.
  ;;
  ;; Source tarball fetched 2026-08-24 from the 1.0.22-RELEASE tag,
  ;; 2,269,468 bytes -- the same version the repo's own makefile builds.
  (define package
    '(derivation
     (name "bootstrap-sodium")
     (build-environment (root (package (letloop package rootfs-final))))
     (fetch (sodium.tar.gz
             (url "https://github.com/jedisct1/libsodium/archive/refs/tags/1.0.22-RELEASE.tar.gz")
             (hash (blake3 "631b1d8f5afdd59606026efe78a7825aa89e3b047a441afc5217fc161f484860"))))
     (script
      "set -e\n"
      "mkdir -p /build/out\n"
      "tar xzf fetch/sodium.tar.gz --no-same-owner\n"
      "cd libsodium-1.0.22-RELEASE\n"
      "./configure --prefix=/build/out --disable-shared --enable-static\n"
      "make -j\"$(nproc)\"\n"
      "make install\n"
      ;; the entry points (letloop sodium) resolves must be there, or
      ;; letloop links fine and fails at its first call
      "test -e /build/out/lib/libsodium.a\n"
      "test -e /build/out/include/sodium.h\n"
      "nm /build/out/lib/libsodium.a > /build/symbols\n"
      "grep -q ' T sodium_init' /build/symbols\n"
      "grep -q ' T crypto_hash_sha256' /build/symbols\n"
      "grep -q ' T crypto_aead_xchacha20poly1305_ietf_encrypt' /build/symbols\n")
     (output "out"))))

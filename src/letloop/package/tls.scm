#!chezscheme
(library (letloop package tls)
  (export package)
  (import (chezscheme))

  ;; LibreSSL, built from source against the bootstrap toolchain, as
  ;; static archives -- for (letloop tls low), which dlopen's
  ;; libtls.so.28 at runtime.
  ;;
  ;; The largest build in this chain by a wide margin: LibreSSL is
  ;; libcrypto (the bulk of it), libssl and libtls together, not one
  ;; small library. Named here after the Chez-facing library
  ;; ((letloop tls), not (letloop libressl)) since that is what a
  ;; caller is actually asking to link against.
  ;;
  ;; Real LibreSSL, not Debian/Ubuntu's "libretls" (the libtls28t64
  ;; package this very host has installed) -- libretls is a thin
  ;; libtls-API shim over the system's own OpenSSL, which exists only
  ;; because a from-scratch LibreSSL's libssl/libcrypto collide by name
  ;; with OpenSSL's, an ABI conflict Debian's package set cannot carry.
  ;; That reason does not apply to a static archive built and consumed
  ;; entirely inside this chain: nothing here already links OpenSSL, so
  ;; building real LibreSSL directly needs no OpenSSL at all, static or
  ;; otherwise -- one source tree produces all three archives with no
  ;; external crypto dependency, matching how the rest of this chain
  ;; trusts as few external artifacts as possible.
  ;;
  ;; Fetched from ftp.openbsd.org, not GitHub: the portable release
  ;; tarball needs a pre-generated `configure` and pre-generated
  ;; per-architecture assembly (60-odd .S files) that autoreconf and
  ;; perl would otherwise have to regenerate, and neither is in this
  ;; toolchain. GitHub's own release page for this project ships no
  ;; such tarball -- only an auto-generated source snapshot of the bare
  ;; git tree, which is missing exactly those generated files. OpenBSD
  ;; is upstream's own canonical distribution point for the portable
  ;; releases, verified by content hash regardless.
  ;;
  ;; --disable-shared: this chain has no dynamic loader to serve a
  ;; .so, and building one would need its own SONAME handling for no
  ;; reader. --disable-tests skips a real test suite that would
  ;; otherwise add significant build time for no gate this store
  ;; doesn't already have a cheaper way to check (nm on the archives).
  ;;
  ;; Source tarball fetched 2026-08-24 from the 4.3.2 release,
  ;; 9,302,254 bytes.
  (define package
    '(derivation
     (name "bootstrap-tls")
     (build-environment (root (package (letloop package rootfs-final))))
     (fetch (libressl.tar.gz
             (url "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-4.3.2.tar.gz")
             (hash (blake3 "6364b58f037dd3ed4e0df5548ab28d7b93c11656e6eaa7c430db172dec12b69e"))))
     (script
      "set -e\n"
      "mkdir -p /build/out\n"
      "tar xzf fetch/libressl.tar.gz --no-same-owner\n"
      "cd libressl-4.3.2\n"
      "./configure --prefix=/build/out --disable-shared --enable-static --disable-tests\n"
      "make -j\"$(nproc)\"\n"
      "make install\n"
      ;; the entry points (letloop tls low) resolves must be there, or
      ;; letloop links fine and fails at its first handshake
      "test -e /build/out/lib/libtls.a\n"
      "test -e /build/out/lib/libssl.a\n"
      "test -e /build/out/lib/libcrypto.a\n"
      "test -e /build/out/include/tls.h\n"
      "nm /build/out/lib/libtls.a > /build/symbols-tls\n"
      "grep -q ' T tls_init' /build/symbols-tls\n"
      "grep -q ' T tls_connect' /build/symbols-tls\n"
      "grep -q ' T tls_read' /build/symbols-tls\n"
      "grep -q ' T tls_write' /build/symbols-tls\n"
      "grep -q ' T tls_close' /build/symbols-tls\n")
     (output "out"))))

#!chezscheme
(library (letloop package opaque)
  (export package)
  (import (chezscheme))

  ;; libopaque, built from source against the bootstrap toolchain, as a
  ;; static archive -- for (letloop opaque), which dlopen's
  ;; libopaque.so at runtime.
  ;;
  ;; Build-time and runtime (link-time) dependencies: (letloop package
  ;; sodium) and (letloop package oprf), bound to /build/inputs/
  ;; bootstrap-sodium and /build/inputs/bootstrap-oprf here. A consumer
  ;; linking libopaque.a needs libsodium.a, liboprf.a and
  ;; liboprf-noiseXK.a alongside it -- none of those symbols are folded
  ;; in, matching the same link-order warning (letloop package oprf)
  ;; already records.
  ;;
  ;; SODIUM_NEWER_THAN_1_0_18=0 sidesteps the upstream makefile's own
  ;; `pkgconf --atleast-version=1.0.19 libsodium` probe, which this
  ;; rootfs has no pkgconf to answer -- an unanswerable probe would
  ;; silently take the wrong branch rather than fail loudly. This
  ;; mirrors the repo's own makefile, which passes the same override
  ;; for the same reason.
  ;;
  ;; Only libopaque.a is built -- not the .so, the CLI utility, the
  ;; test binaries, or the man page (the last needs pandoc, which is
  ;; its own large dependency this chain does not carry; its source is
  ;; copied as share/doc/opaque.md instead of being silently dropped).
  ;; Building only the archive also means never linking anything here,
  ;; so libsodium/liboprf never need to actually resolve at this step.
  ;;
  ;; Source tarball fetched 2026-08-24 from commit 98f6a6e (the same
  ;; commit the repo's own makefile checks out), 138,145 bytes.
  (define package
    '(derivation
     (name "bootstrap-opaque")
     (build-environment (root (package (letloop package rootfs-final))))
     (inputs ((package (letloop package sodium))
              (package (letloop package oprf))))
     (fetch (opaque.tar.gz
             (url "https://github.com/stef/libopaque/archive/98f6a6ec01f8d22ca28a25d0fa970a2141701bd3.tar.gz")
             (hash (blake3 "903afbdcb357a8c762aebfcdaf3db3e3ff341c802d1e0f33179b2fa162065aae"))))
     (script
      "set -e\n"
      "mkdir -p /build/out/lib /build/out/include /build/out/share/doc\n"
      "tar xzf fetch/opaque.tar.gz --no-same-owner\n"
      "cd libopaque-98f6a6ec01f8d22ca28a25d0fa970a2141701bd3/src\n"
      "make libopaque.a \\\n"
      "  SODIUM_NEWER_THAN_1_0_18=0 \\\n"
      "  OPRFINCDIR=/build/inputs/bootstrap-oprf/include \\\n"
      "  CFLAGS=\"-Wall -O2 -g -fpic -I/build/inputs/bootstrap-sodium/include -DHAVE_SODIUM_HKDF=1\"\n"
      "cp libopaque.a /build/out/lib/\n"
      "cp opaque.h /build/out/include/\n"
      "cp utils/man/opaque.md /build/out/share/doc/\n"
      ;; a few of the entry points (letloop opaque) resolves must be
      ;; there, or letloop links fine and fails at its first call
      "nm /build/out/lib/libopaque.a > /build/symbols\n"
      "grep -q ' T opaque_Register' /build/symbols\n"
      "grep -q ' T opaque_CreateRegistrationRequest' /build/symbols\n"
      "grep -q ' T opaque_UserAuth' /build/symbols\n")
     (output "out"))))

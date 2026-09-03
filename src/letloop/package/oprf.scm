#!chezscheme
(library (letloop package oprf)
  (export package)
  (import (chezscheme))

  ;; liboprf, built from source against the bootstrap toolchain, as a
  ;; static archive. Not itself one of the libraries letloop dlopen's --
  ;; it exists here only because (letloop package opaque) needs it at
  ;; link time, the same way the repo's own makefile builds it as a
  ;; prerequisite of `opaque` rather than standalone.
  ;;
  ;; Build-time dependency: (letloop package sodium), bound to
  ;; /build/inputs/bootstrap-sodium here. Runtime (link-time) dependency
  ;; for anything that links liboprf.a: libsodium.a and
  ;; liboprf-noiseXK.a both -- neither is folded in, so a consumer links
  ;; all three, in that order, the same warning
  ;; src/letloop/store/README.md already records about static archives
  ;; being link-order-sensitive.
  ;;
  ;; Only the static archives are built, never the .so upstream's
  ;; makefiles also produce: this chain has no dynamic loader to serve
  ;; one, and skipping the shared-object link step also skips its
  ;; strict -Wl,-z,defs symbol resolution, which would otherwise need
  ;; -lsodium wired through at exactly this step for no reason -- an .a
  ;; only needs to compile, not link.
  ;;
  ;; The CFLAGS below are the repo's own makefile's override of
  ;; noise_xk's much larger default set (stack-protector, cf-protection,
  ;; -Werror=..., several -Wl,... linker flags) -- some of those are
  ;; glibc/gcc-specific and untested against this musl cross toolchain,
  ;; so this keeps to what is already proven rather than adopting them.
  ;;
  ;; Source tarball fetched 2026-08-24 from the v0.9.4 tag, 248,914
  ;; bytes -- the same version the repo's own makefile builds.
  (define package
    '(derivation
     (name "bootstrap-oprf")
     (build-environment (root (package (letloop package rootfs-final))))
     (inputs ((package (letloop package sodium))))
     (fetch (oprf.tar.gz
             (url "https://github.com/stef/liboprf/archive/refs/tags/v0.9.4.tar.gz")
             (hash (blake3 "8e4450b4c9037e62711105958a40feadc27698592484f168d4d77dfd89f629cd"))))
     (script
      "set -e\n"
      "mkdir -p /build/out/lib /build/out/include/oprf\n"
      "tar xzf fetch/oprf.tar.gz --no-same-owner\n"
      "cd liboprf-0.9.4/src\n"
      "make -C noise_xk liboprf-noiseXK.a \\\n"
      "  CFLAGS=\"-Wall -O2 -g -fpic -I/build/inputs/bootstrap-sodium/include\"\n"
      "cc -Wall -O2 -g -fpic -DHAVE_SODIUM_HKDF=1 \\\n"
      "   -I/build/inputs/bootstrap-sodium/include \\\n"
      "   -Inoise_xk/include -Inoise_xk/include/karmel -Inoise_xk/include/karmel/minimal \\\n"
      "   -c oprf.c toprf.c dkg.c dkg-vss.c utils.c tp-dkg.c mpmult.c stp-dkg.c toprf-update.c\n"
      "ar rcs liboprf.a oprf.o toprf.o dkg.o dkg-vss.o utils.o tp-dkg.o mpmult.o stp-dkg.o toprf-update.o\n"
      "cp liboprf.a /build/out/lib/\n"
      "cp noise_xk/liboprf-noiseXK.a /build/out/lib/\n"
      "cp oprf.h toprf.h toprf-update.h dkg.h dkg-vss.h tp-dkg.h stp-dkg.h utils.h mpmult.h /build/out/include/oprf/\n"
      "nm /build/out/lib/liboprf.a > /build/symbols\n"
      "grep -q ' T oprf_Finalize' /build/symbols\n")
     (output "out"))))

;; liburing, built from source against the bootstrap toolchain,
;; specifically for its "-ffi" variant.
;;
;; Without this the bootstrap letloop links with no io_uring symbols at
;; all -- the makefile probes for -luring-ffi, does not find it, and
;; quietly leaves LETLOOP_LIBURING_STATIC undefined -- so anything
;; reaching (letloop liburing low) fails at run time: flow, flow2,
;; review, the HTTP server. The rootfs carries the kernel's own
;; linux/io_uring.h from the toolchain's bundled headers, which is not
;; the same thing and is not enough.
;;
;; The "-ffi" build exists because most of liburing.h is `static
;; inline`, including the ring bookkeeping that calls the memory
;; barrier primitives in liburing/barrier.h, and inline functions have
;; no linkable symbol for a non-C consumer to reach. liburing compiles
;; a dedicated ffi.c with IOURINGINLINE defined empty to give them real
;; ones. See src/letloop/store/README.md's liburing section for what
;; went wrong when letloop tried to materialise its own copies instead.
;;
;; Both the plain and -ffi archives are installed: letloop-main.c links
;; -luring-ffi, which is a strict superset, but a program compiled with
;; `letloop compile ... liburing.a` may want either.
;;
;; Source tarball fetched 2026-08-23 from the liburing-2.14 tag,
;; 487,718 bytes -- the same version the repo's own makefile builds.
(derivation
 (name "bootstrap-liburing")
 (build-environment (root (derivation "bootstrap-rootfs-final.derivation.scm")))
 (inputs ((derivation "bootstrap-make.derivation.scm")))
 (fetch (liburing.tar.gz
         (url "https://github.com/axboe/liburing/archive/refs/tags/liburing-2.14.tar.gz")
         (hash (blake3 "178adf6ec1815ecab177194fabce29509ce3fe4b81ac65d690364f06f1e46db8"))))
 (script
  "set -e\n"
  "export PATH=/build/inputs/bootstrap-make/bin:$PATH\n"
  "mkdir -p /build/out\n"
  "tar xzf fetch/liburing.tar.gz --no-same-owner\n"
  "cd liburing-liburing-2.14\n"
  ;; configure normalises --prefix with `realpath -s`, and -s is a GNU
  ;; extension BusyBox does not have. It only means "do not resolve
  ;; symlinks", which for an absolute path with none in it is what
  ;; plain realpath does anyway.
  "sed -i 's/realpath -s /realpath /' configure\n"
  "./configure --prefix=/build/out\n"
  "make -j\"$(nproc)\"\n"
  "make install\n"
  ;; the archive letloop actually links against has to be there, or the
  ;; makefile's probe will silently skip io_uring again
  "test -e /build/out/lib/liburing-ffi.a\n"
  "test -e /build/out/include/liburing.h\n")
 (output "out"))

;; GNU make, built from source against the bootstrap toolchain.
;;
;; Neither of the two fetched artifacts provides `make`: the musl.cc
;; toolchain ships a compiler and binutils but no build driver, and
;; BusyBox has no make applet. Since every from-source package after
;; this one is driven by a makefile, nothing further can be built until
;; make exists -- including the from-source BusyBox that retires the
;; prebuilt one.
;;
;; This does not need a third trusted binary. GNU make ships build.sh
;; for exactly this situation -- bootstrapping make on a system that
;; has a compiler and a shell but no make yet -- so configure runs,
;; then build.sh compiles the sources it emitted. The trust set stays
;; at the two artifacts named in bootstrap-toolchain and
;; bootstrap-shell.
;;
;; --disable-dependency-tracking avoids configure probing for a
;; dependency-style helper it cannot use without make, and
;; --without-guile keeps the build to the toolchain and libc already
;; present rather than reaching for an optional extension.
;;
;; Fetched from mirrors.kernel.org rather than ftp.gnu.org: the latter
;; answers 403 without a User-Agent and then refuses connections
;; outright for a while after a few requests, which makes it unusable
;; for automated builds. Which mirror serves the bytes does not matter
;; -- the tarball is pinned by content hash, and this mirror's copy was
;; verified byte-identical to ftp.gnu.org's on 2026-08-23 (2,348,200
;; bytes). A substituted file fails the hash check; an untrusted mirror
;; is exactly what content addressing is for.
(derivation
 (name "bootstrap-make")
 (build-environment (root (derivation "bootstrap-rootfs.derivation.scm")))
 (fetch (make.tar.gz
         (url "https://mirrors.kernel.org/gnu/make/make-4.4.1.tar.gz")
         (hash (blake3 "a7d8aee97b7e9a525ef561afa84eea0d929f246e3aafa420231c0602151cf9eb"))))
 (script
  "set -e\n"
  "mkdir -p out/bin\n"
  "tar xzf fetch/make.tar.gz --no-same-owner\n"
  "cd make-4.4.1\n"
  ;; LDFLAGS=-static so make, like everything else this chain produces,
  ;; needs no loader -- it runs from a store path copied anywhere, not
  ;; only from inside a rootfs that happens to carry musl's ld.so
  "./configure --disable-dependency-tracking --without-guile LDFLAGS=-static\n"
  ;; build.sh is make's own no-make bootstrap path
  "sh ./build.sh\n"
  "./make --version\n"
  "cp make ../out/bin/make\n")
 (output "out"))

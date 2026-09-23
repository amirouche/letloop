#!chezscheme
(library (letloop package shell)
  (export package)
  (import (chezscheme))

  ;; The second and last prebuilt binary this bootstrap chain trusts: a
  ;; statically linked BusyBox, providing `sh` and the ~400 other applets
  ;; a build script expects (cp, mkdir, tar, sed, ...). Published by
  ;; busybox.net itself, built against musl.
  ;;
  ;; It exists to break the same chicken-and-egg the toolchain fetch
  ;; does, from the other side. sandbox-build! always runs
  ;; `sh -e /build/build.sh` inside the rootfs it is given, so a rootfs
  ;; with no shell can host no build at all -- and a toolchain tarball,
  ;; on its own, has no shell. One of these two artifacts has to arrive
  ;; without being built, and a 1 MB BusyBox is the smaller thing to
  ;; audit.
  ;;
  ;; Pure scaffolding, with a defined end: it is used exactly once, by
  ;; bootstrap-rootfs.derivation.scm's assembly step.
  ;; bootstrap-busybox.derivation.scm then rebuilds BusyBox from source
  ;; against the bootstrap toolchain, and that from-source build is what
  ;; the rootfs ships. After that point nothing in the chain depends on
  ;; this binary any more.
  ;;
  ;; Fetched 2026-08-23 from busybox.net's own 1.35.0-x86_64-linux-musl
  ;; binaries directory; 1,131,168 bytes, `file` reports "ELF 64-bit LSB
  ;; executable, x86-64, statically linked, stripped".
  (define package
    '(derivation
     (name "bootstrap-shell")
     (fetch (busybox
             (url "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox")
             (hash (blake3 "41eee14fead1f5f637e613b5bb865caab4fd3624f6bf5ebbe5280de5a8a6abac"))))
     (output "out"))))

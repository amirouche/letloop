#!chezscheme
(library (letloop package busybox)
  (export package)
  (import (chezscheme))

  ;; BusyBox, built from source against the bootstrap toolchain, to
  ;; replace the prebuilt binary bootstrap-shell fetched.
  ;;
  ;; This is what retires the second of the two trusted prebuilt
  ;; artifacts. After this derivation, the prebuilt BusyBox is used for
  ;; exactly one thing -- running the assembly script in
  ;; bootstrap-rootfs, before any from-source build is possible -- and
  ;; nothing downstream contains its bytes. The compiler tarball cannot
  ;; be retired the same way without a full source bootstrap, which this
  ;; chain deliberately does not attempt; see bootstrap-toolchain's
  ;; header.
  ;;
  ;; defconfig, then the settings this rootfs actually requires:
  ;; CONFIG_STATIC so the result needs no loader, and no
  ;; CONFIG_PREFIX/install step because bootstrap-rootfs-final does its
  ;; own applet linking (it has to skip names the toolchain claims).
  ;; Several defconfig applets need Linux headers or libraries this
  ;; minimal rootfs has no reason to carry -- they are switched off
  ;; rather than dragged in, since nothing in this chain builds a
  ;; bootloader, mounts NFS, or speaks SELinux.
  ;;
  ;; Source tarball fetched 2026-08-23 from busybox.net, 2,525,473 bytes.
  (define package
    '(derivation
     (name "bootstrap-busybox")
     (build-environment (root (package (letloop package rootfs))))
     (inputs ((package (letloop package make))))
     (fetch (busybox.tar.bz2
             (url "https://busybox.net/downloads/busybox-1.36.1.tar.bz2")
             (hash (blake3 "dfdfc1b9aa41d5134e087d904c0a5f6958825f0e94db1d2cb5ea93088247c886"))))
     (script
      "set -e\n"
      "export PATH=/build/inputs/bootstrap-make/bin:$PATH\n"
      "mkdir -p out/bin\n"
      "tar xjf fetch/busybox.tar.bz2 --no-same-owner\n"
      "cd busybox-1.36.1\n"
      "make defconfig\n"
      ;; static, so the result has no loader dependency at all
      "sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config\n"
      ;; applets needing headers or libraries a bare toolchain rootfs
      ;; has no reason to ship
      "for symbol in CONFIG_SELINUX CONFIG_PAM CONFIG_FEATURE_MOUNT_NFS \\\n"
      "              CONFIG_BOOTCHARTD CONFIG_TC CONFIG_FEATURE_WTMP \\\n"
      "              CONFIG_FEATURE_UTMP CONFIG_USE_BB_PWD_GRP; do\n"
      "  sed -i \"s/^$symbol=y/# $symbol is not set/\" .config\n"
      "done\n"
      "yes '' | make oldconfig >/dev/null\n"
      "make -j\"$(nproc)\"\n"
      "./busybox --help >/dev/null\n"
      "cp busybox ../out/bin/busybox\n")
     (output "out"))))

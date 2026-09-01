;; The build environment everything downstream of the bootstrap chain
;; should actually use: the toolchain, plus BusyBox and GNU make as
;; this chain built them from source, with no prebuilt BusyBox in it.
;;
;; bootstrap-rootfs is the scaffolding version -- it has to embed the
;; fetched BusyBox binary, because at that point nothing has been
;; compiled yet and there is no other shell to run a build with. This
;; one is assembled *by* a build running in that scaffold rootfs, so it
;; can use from-source components throughout. The prebuilt BusyBox is
;; therefore load-bearing exactly twice (assembling bootstrap-rootfs,
;; and hosting the builds of make and BusyBox itself) and appears in
;; nothing this produces.
;;
;; Same layout rules as bootstrap-rootfs, and for the same reasons: the
;; toolchain's own prefix contents at the rootfs root so gcc finds its
;; libexec and headers relative to /bin/gcc, a real /usr directory
;; rather than a top-level symlink, and BusyBox applets installed only
;; where the toolchain has not already claimed the name.
(derivation
 (name "bootstrap-rootfs-final")
 (build-environment (root (derivation "bootstrap-rootfs.derivation.scm")))
 (inputs ((derivation "bootstrap-toolchain.derivation.scm")
          (derivation "bootstrap-busybox.derivation.scm")
          (derivation "bootstrap-make.derivation.scm")))
 (script
  "set -e\n"
  "mkdir -p out\n"
  "tar xzf /build/inputs/bootstrap-toolchain/x86_64-linux-musl-native.tgz -C /build --no-same-owner\n"
  "cp -a /build/x86_64-linux-musl-native/. out/\n"
  "rm -f out/usr\n"
  "mkdir -p out/usr\n"
  "ln -s ../bin out/usr/bin\n"
  "ln -s ../lib out/usr/lib\n"
  "ln -s ../include out/usr/include\n"
  ;; from-source busybox and make, not the fetched binary
  "cp /build/inputs/bootstrap-busybox/bin/busybox out/bin/busybox\n"
  "cp /build/inputs/bootstrap-make/bin/make out/bin/make\n"
  "chmod +x out/bin/busybox out/bin/make\n"
  "for applet in $(out/bin/busybox --list); do\n"
  "  if [ ! -e \"out/bin/$applet\" ]; then ln -s busybox \"out/bin/$applet\"; fi\n"
  "done\n"
  "ln -s bin out/sbin\n"
  ;; prove the assembled environment can drive a real make-based build
  ;; before anything downstream depends on it
  "mkdir -p /build/probe\n"
  "printf 'int main(void){return 0;}\\n' > /build/probe/probe.c\n"
  "printf 'all:\\n\\tgcc -static -o probe probe.c\\n' > /build/probe/Makefile\n"
  "cd /build/probe && PATH=/build/out/bin make && ./probe\n")
 (output "out"))

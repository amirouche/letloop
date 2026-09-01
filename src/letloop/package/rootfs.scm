#!chezscheme
(library (letloop package rootfs)
  (export package)
  (import (chezscheme))

  ;; Assembles the two fetched bootstrap artifacts into a rootfs that
  ;; sandbox-build! can actually run a build in -- the thing every later
  ;; derivation names as its build-environment root, replacing Alpine.
  ;;
  ;; This is the one derivation in the chain that still needs a
  ;; pre-existing rootfs to build *in*, and the reason is structural, not
  ;; an oversight: sandbox-build! runs `sh -e /build/build.sh` inside
  ;; whatever rootfs it is given, so the build that produces the first
  ;; rootfs-with-a-shell cannot itself run in one. Something has to break
  ;; the loop from outside. bootstrap.sh supplies a rootfs of symlinks
  ;; into the host's own /usr, /bin, /lib (the same fixture trick
  ;; store.check.scm uses), so the host's shell and tar act as
  ;; scaffolding for this one step.
  ;;
  ;; That scaffolding does not leak into the output: this script only
  ;; unpacks and symlinks bytes that came from the two hash-pinned
  ;; inputs. Nothing is compiled here, so no host header, library or
  ;; compiler can end up in what it produces. Everything downstream is
  ;; built by the toolchain assembled here, in a sandbox containing
  ;; nothing but this rootfs.
  ;;
  ;; Layout: the toolchain tarball unpacks with its own prefix laid out
  ;; at the top level (bin/, lib/, include/, libexec/, x86_64-linux-musl/),
  ;; which is exactly where gcc expects to find its own libexec and
  ;; headers relative to /bin/gcc -- so its contents become the rootfs
  ;; root directly rather than being nested under a prefix directory. The
  ;; tarball's own `usr -> .` symlink is replaced with a real directory
  ;; of symlinks: a top-level symlink is an untested edge case for
  ;; bwrap's per-entry --ro-bind, and one directory deep is not.
  ;;
  ;; BusyBox supplies sh and the other ~400 applets a build script
  ;; expects, installed as symlinks only where the toolchain has not
  ;; already provided that name -- so the real ar, nm, strip and ranlib
  ;; win over BusyBox's reduced ones.
  (define package
    '(derivation
     (name "bootstrap-rootfs")
     (build-environment (root (host)))
     (inputs ((package (letloop package toolchain))
              (package (letloop package shell))))
     (script
      "set -e\n"
      "mkdir -p out\n"
      ;; --no-same-owner: the tarball records uid/gid 1000, but the sandbox
      ;; maps only uid 0, so restoring ownership fails outright. Nothing is
      ;; lost by dropping it -- store-hash-directory hashes content and the
      ;; owner-execute bit, never uid or gid.
      "tar xzf /build/inputs/bootstrap-toolchain/x86_64-linux-musl-native.tgz -C /build --no-same-owner\n"
      "cp -a /build/x86_64-linux-musl-native/. out/\n"
      ;; a real /usr, rather than the tarball's top-level `usr -> .`
      "rm -f out/usr\n"
      "mkdir -p out/usr\n"
      "ln -s ../bin out/usr/bin\n"
      "ln -s ../lib out/usr/lib\n"
      "ln -s ../include out/usr/include\n"
      ;; busybox, then one applet symlink per name the toolchain did not
      ;; already claim
      "cp /build/inputs/bootstrap-shell/busybox out/bin/busybox\n"
      "chmod +x out/bin/busybox\n"
      "for applet in $(out/bin/busybox --list); do\n"
      "  if [ ! -e \"out/bin/$applet\" ]; then ln -s busybox \"out/bin/$applet\"; fi\n"
      "done\n"
      ;; the sandbox's PATH names /sbin too
      "ln -s bin out/sbin\n"
      ;; `cc` is the POSIX name for the C compiler and what most build
      ;; systems reach for -- this repo's own makefile included. The
      ;; tarball ships gcc and x86_64-linux-musl-cc but no plain cc.
      "ln -s gcc out/bin/cc\n"
      ;; prove the assembled toolchain works, here, rather than finding out
      ;; in whatever derivation first tries to use it
      "printf 'int main(void){return 0;}\\n' > /build/probe.c\n"
      "out/bin/gcc -static -o /build/probe /build/probe.c\n"
      "/build/probe\n")
     (output "out"))))

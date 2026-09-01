;; ChezScheme, built from source against the bootstrap toolchain --
;; the last thing letloop needs before it can be built without Alpine.
;;
;; Uses the release tarball rather than a git clone. The repo carries
;; zuo, nanopass, zlib and lz4 as submodules, which a bare git archive
;; would omit, and a sandboxed build has no network to fetch them with
;; anyway (--unshare-net). The release tarball bundles all four, so one
;; hash-pinned fetch brings everything the build needs. It is also a
;; fixed point: the repo's makefile tracks CHEZ_REF=main, which is not
;; reproducible from one day to the next.
;;
;; --disable-x11 --disable-curses because this rootfs has neither, and
;; ChezScheme only wants them for its own expression editor.
;; --kernelobj because `make letloop` links against kernel.o rather
;; than the shared library.
;;
;; Release tarball fetched 2026-08-23 from the v10.4.1 release,
;; 9,584,694 bytes. That is a real release rather than the pre-release
;; the repo's own makefile tracks, so this is also the first pinned,
;; reproducible ChezScheme in the project.
(derivation
 (name "bootstrap-chezscheme")
 (build-environment (root (derivation "bootstrap-rootfs-final.derivation.scm")))
 (fetch (chezscheme.tar.gz
         (url "https://github.com/cisco/ChezScheme/releases/download/v10.4.1/csv10.4.1.tar.gz")
         (hash (blake3 "21155a09d465145d29eba64438864b61bbb1aafd8693021f20252c6952fb0a16"))))
 (script
  "set -e\n"
  "mkdir -p /build/out\n"
  "tar xzf fetch/chezscheme.tar.gz --no-same-owner\n"
  "cd csv10.4.1\n"
  "./configure --threads --disable-x11 --disable-curses --kernelobj \\\n"
  "            --installprefix=/build/out\n"
  "make -j\"$(nproc)\"\n"
  "make install\n"
  "/build/out/bin/scheme --version\n")
 (output "out"))

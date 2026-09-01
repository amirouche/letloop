;; The first of exactly two prebuilt binaries this bootstrap chain
;; trusts, and the reason it can exist at all: a complete, statically
;; linked, native x86_64-linux-musl toolchain -- gcc 11.2.1, binutils,
;; musl libc and its headers -- published by musl.cc (Zach van Rijn's
;; builds of musl-cross-make, the same source Alpine's own toolchain
;; work descends from).
;;
;; Trusting a prebuilt compiler is a deliberate choice, not an
;; oversight. Building a C compiler requires a C compiler; the only
;; ways out are to trust a prebuilt one (what Nix does, via its
;; per-platform bootstrap-tools tarball) or to bootstrap from a few
;; hundred bytes of hex through a chain of ever-larger compilers (what
;; Guix does, via hex0/stage0/mes -- years of work, and it still
;; bottoms out in trusting a small seed binary). This takes Nix's
;; bargain: two artifacts, pinned by content hash, named here with
;; their provenance so the trust decision stays auditable instead of
;; being buried in a hex string.
;;
;; Fetch-only: no build-environment, no script, no sandbox. That shape
;; exists precisely for this derivation. Every sandboxed build runs
;; `sh` inside the rootfs it is given, so the toolchain that will
;; *become* that rootfs cannot itself be fetched by one -- there would
;; be no shell to run the fetch in yet.
;;
;; Nothing is unpacked here; the tarball lands in the store as-is.
;; bootstrap-rootfs.derivation.scm untars it, having a real `tar` to do
;; it with.
;;
;; Risk worth naming: musl.cc is one maintainer's site with a history
;; of intermittent downtime, and offers no signed releases beyond the
;; tarball itself. The hash below pins exactly what was fetched on
;; 2026-08-23 (89,080,066 bytes, Last-Modified 2021-11-23), so a
;; substituted file fails loudly rather than silently -- but a
;; disappeared file fails too. Mirroring this exact tarball somewhere
;; durable is the obvious follow-up.
(derivation
 (name "bootstrap-toolchain")
 (fetch (x86_64-linux-musl-native.tgz
         (url "https://musl.cc/x86_64-linux-musl-native.tgz")
         (hash (blake3 "a77bdfcf09a27aacf21aba8cd4282e7adefc83f91769e0742864b77d0dd46fb2"))))
 (output "out"))

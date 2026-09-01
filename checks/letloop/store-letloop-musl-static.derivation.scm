;; Builds letloop itself -- ChezScheme already provisioned out-of-band
;; at /root/letloop-src (see store-static-hello.sh's provisioning),
;; this derivation only re-runs `make letloop` -- through
;; `letloop store build`, producing a self-hosting, statically linked,
;; relocatable distribution: the letloop-musl-static binary plus its
;; sibling library tree, laid out exactly like a real install
;; (bin/letloop-musl-static, lib/letloop/{src,obj}), so it is directly
;; usable for `compile`/`exec`/`check`/`store` too, not just `version`.
;;
;; The source tree lives inside the build-environment rootfs itself
;; (read-only, at /root/letloop-src) rather than as a derivation
;; `input` or `fetch`: v1 has no multi-derivation graph to have first
;; produced it as a separate store path, and `make letloop` needs a
;; writable copy anyway (it writes .so/.wpo files next to each source
;; file), so it is copied into the scratch /build area first.
(derivation
 (name "letloop-musl-static")
 (build-environment (root (directory "/tmp/letloop-store-check/alpine-buildenv")))
 (script
  "set -e\n"
  "cp -a /root/letloop-src /build/src\n"
  "cd /build/src\n"
  "export PATH=\"$(pwd)/local/bin:$PATH\"\n"
  "export SCHEME=\"$(pwd)/local/bin/scheme\"\n"
  "make letloop\n"
  "mkdir -p /build/out/bin /build/out/lib\n"
  "cp -L local/bin/letloop /build/out/bin/letloop-musl-static\n"
  "cp -a local/lib/letloop /build/out/lib/letloop\n")
 (output "out"))

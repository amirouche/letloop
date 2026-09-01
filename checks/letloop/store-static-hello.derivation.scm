;; End-to-end smoke test for `letloop store build`: statically compile
;; a tiny letloop/Scheme program via `letloop compile`, running inside
;; a network-off sandbox whose rootfs was provisioned (out-of-band, by
;; store-static-hello.sh) with a musl-linked `letloop` + ChezScheme
;; built from source. The program's source is inlined into the build
;; script itself (a heredoc) rather than referenced as a derivation
;; `input`, since v1 has no multi-derivation dependency graph to have
;; first produced it as a separate store path.
(derivation
 (name "static-hello")
 (build-environment (root (directory "/tmp/letloop-store-check/alpine-buildenv")))
 (script
  "set -e\n"
  "cat > hello.scm <<'SCHEMEEOF'\n"
  "(library (hello)\n"
  "  (export main)\n"
  "  (import (chezscheme))\n"
  "  (define (main . args)\n"
  "    (display \"hello, letloop store\")\n"
  "    (newline)))\n"
  "SCHEMEEOF\n"
  "letloop compile hello.scm main\n"
  "mkdir -p out\n"
  "cp a.out out/hello\n")
 (output "out"))

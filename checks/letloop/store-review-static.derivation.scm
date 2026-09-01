;; Compiles `letloop review` -- the largest real subsystem this repo
;; has (a fiber/event-loop-backed TUI, transitively importing
;; (letloop liburing low)) -- through the static musl toolchain via
;; `letloop store build`. Proves the *compile* step works statically
;; for something well beyond the trivial hello.scm example, including
;; every liburing symbol registration in letloop-main.c.
;;
;; Deliberately compile-only: the resulting binary is NOT run as part
;; of this derivation (or its smoke-test assertions). Actually driving
;; review's event loop hits the open, tracked gap in
;; src/letloop/store/README.md's "(letloop liburing low) under static
;; linking" section -- a real crash, not yet root-caused. Compiling it
;; is still real, useful evidence: it proves the whole dependency
;; chain (tea/*, liburing/low, r999) links and produces a valid static
;; ELF, which is the harder part to get wrong.
(derivation
 (name "review-static")
 (build-environment (root (directory "/tmp/letloop-store-check/alpine-buildenv")))
 (script
  "set -e\n"
  "letloop compile /usr/local/lib/letloop/src/letloop/review.scm letloop-review\n"
  "mkdir -p out\n"
  "cp a.out out/letloop-review\n")
 (output "out"))

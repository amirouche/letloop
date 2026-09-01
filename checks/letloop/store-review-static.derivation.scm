;; Compiles `letloop review` -- the largest real subsystem this repo
;; has (a fiber/event-loop-backed TUI, transitively importing
;; (letloop liburing low)) -- through the static musl toolchain via
;; `letloop store build`. Proves the *compile* step works statically
;; for something well beyond the trivial hello.scm example, including
;; every liburing symbol registration in letloop-main.c.
;;
;; Deliberately compile-only: the resulting binary is not run as part
;; of this derivation (or its smoke-test assertions) -- review itself
;; is an interactive TUI and needs a real terminal. Actually exercising
;; (letloop liburing low)'s runtime behavior statically -- ring setup,
;; submit, wait, cancel, socket/file io_uring ops -- is covered
;; separately and thoroughly by `letloop check src/ src/letloop/flow2.scm`
;; (58 checks, all real io_uring traffic) run against the
;; letloop-musl-static build below; see src/letloop/store/README.md's
;; liburing section for how that runtime crash (unrelated to symbol
;; registration -- an unguarded (load-shared-object #f) inside
;; low.scm's own body, plus several eagerly-resolved libc symbols
;; missing from letloop-main.c's table) was found and fixed. Compiling
;; review here is still useful evidence on its own: it proves the
;; whole dependency chain (tea/*, liburing/low, r999) links and
;; produces a valid static ELF, which is the harder part to get wrong.
(derivation
 (name "review-static")
 (build-environment (root (directory "/tmp/letloop-store-check/alpine-buildenv")))
 (script
  "set -e\n"
  "letloop compile /usr/local/lib/letloop/src/letloop/review.scm letloop-review\n"
  "mkdir -p out\n"
  "cp a.out out/letloop-review\n")
 (output "out"))

;; Actually *runs* (letloop liburing low)'s io_uring-backed checks
;; statically -- ring setup, submit, wait, cancel, socket and file
;; io_uring ops, cancellation races -- via flow2.scm's own 58
;; ~check-flow2-* procedures. Where store-review-static.derivation.scm
;; only proves the dependency chain *compiles* statically (review is
;; an interactive TUI, not runnable headlessly here), this derivation
;; is what actually exercises low.scm's runtime behavior under the
;; static musl build -- the thing that used to crash immediately on
;; any reference into low.scm, root-caused and fixed per
;; src/letloop/store/README.md's liburing section. `letloop check`
;; itself reports failures without a nonzero exit in all cases, so
;; grep its own "FAILED"/"Exception" markers rather than trusting
;; exit status alone.
(derivation
 (name "flow2-static-check")
 (build-environment (root (directory "/tmp/letloop-store-check/alpine-buildenv")))
 (script
  "set -e\n"
  "cd /root/letloop-src\n"
  "letloop check ./src/ src/letloop/flow2.scm 2>&1 | tee /tmp/flow2-check.log\n"
  ;; Some checks deliberately raise and catch synthetic errors
  ;; ("Exception in raising-cancel: boom") as part of testing error
  ;; paths -- only a bare, uncaught top-level "Exception:" (what the
  ;; static dlopen crash actually looked like) or an explicit "**
  ;; FAILED" marks a real failure here.
  "! grep -qE '^Exception:|\\*\\* FAILED' /tmp/flow2-check.log\n"
  "mkdir -p /build/out\n"
  "cp /tmp/flow2-check.log /build/out/result\n")
 (output "out"))

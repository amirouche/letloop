#!chezscheme
(library (letloop package flow2)
  (export package)
  (import (chezscheme))

  ;; Runs (letloop liburing low)'s io_uring machinery for real, on the
  ;; bootstrap letloop: ring setup, submit, wait, cancel, socket and file
  ;; operations, across flow2.scm's 58 checks.
  ;;
  ;; This is the gate that matters for the liburing work. Linking
  ;; -luring-ffi is silent when it fails -- the makefile probes, finds
  ;; nothing, and builds a letloop with no io_uring symbols at all --
  ;; and the resulting binary looks perfectly healthy until something
  ;; actually reaches flow, flow2 or review. bootstrap-letloop checks the
  ;; symbols are present; this checks they work.
  ;;
  ;; It mirrors store-flow2-static.derivation.scm, which holds the
  ;; Alpine-built letloop to the same bar.
  ;;
  ;; `letloop check` reports failures without a nonzero exit in every
  ;; case, so its own markers are what decide. Some checks deliberately
  ;; raise and catch synthetic errors ("Exception in raising-cancel:
  ;; boom") while testing error paths, so only a bare, uncaught
  ;; top-level "Exception:" or an explicit "** FAILED" counts.
  (define package
    '(derivation
     (name "bootstrap-flow2-check")
     (build-environment (root (package (letloop package rootfs-final))))
     (inputs ("/tmp/letloop-bootstrap/letloop-src"
              (package (letloop package letloop))))
     (script
      "set -e\n"
      "cp -a /tmp/letloop-bootstrap/letloop-src /build/src\n"
      "cd /build/src\n"
      "/build/inputs/bootstrap-letloop/bin/letloop check ./src/ src/letloop/flow2.scm 2>&1 \\\n"
      "  | tee /build/flow2.log\n"
      "! grep -qE '^Exception:|\\*\\* FAILED' /build/flow2.log\n"
      ;; a smoke test that passes because nothing ran would be worse than
      ;; one that fails, so require the checks to actually have happened
      "grep -c '\\*\\* SUCCESS' /build/flow2.log | grep -qvw 0\n"
      "mkdir -p /build/out\n"
      "cp /build/flow2.log /build/out/result\n")
     (output "out"))))

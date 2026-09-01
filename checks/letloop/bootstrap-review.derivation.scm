;; Compiles `letloop review` -- the largest real subsystem in the repo,
;; a fiber/event-loop-backed TUI reaching (letloop tea *) and
;; (letloop liburing low) -- with the bootstrap letloop, in the
;; bootstrap rootfs.
;;
;; This is the coverage the Alpine-based store-review-static
;; derivation used to provide, now with no distribution involved. It
;; exercises a much wider dependency chain than the other compile
;; checks here: tea/*, liburing/low, r999, sq, heap, all folded into
;; one amalgamated program.
;;
;; Compile-only, deliberately: review is an interactive TUI and wants a
;; real terminal, so there is nothing to usefully run in a sandbox.
;; That its io_uring machinery *works* is covered separately, and
;; better, by bootstrap-flow2.derivation.scm -- 61 checks driving real
;; rings rather than one program drawing a screen.
(derivation
 (name "bootstrap-review")
 (build-environment (root (derivation "bootstrap-rootfs-final.derivation.scm")))
 (inputs ((derivation "bootstrap-letloop.derivation.scm")))
 (script
  "set -e\n"
  "mkdir -p /build/out\n"
  "cd /build\n"
  "/build/inputs/bootstrap-letloop/bin/letloop compile \\\n"
  "    /build/inputs/bootstrap-letloop/lib/letloop/src/letloop/review.scm letloop-review\n"
  "cp a.out /build/out/letloop-review\n"
  ;; the point of the whole chain: what it produces needs no loader
  "! readelf -l /build/out/letloop-review | grep -qi interpreter\n")
 (output "out"))

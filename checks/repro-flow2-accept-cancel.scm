;; Reproducer for finding 2 of the 2026-08-17 adverse review of
;; (letloop flow2): cancelling a fiber parked in flow-accept poisons
;; the listening fd, so the NEXT flow-accept on it raises instead of
;; accepting.
;;
;; Mechanism. flow-accept (flow2.scm:812) never calls register-cancel!.
;; When the scope dies the fiber unwinds, but the handler it installed
;; stays registered against the multishot's active-id in
;; (loop-handlers (loop-current)). loop-accept-block guards against a
;; second waiter on the same id -- "A single continuation slot is keyed
;; by active-id; a second concurrent waiter would silently overwrite
;; the first one" -- so the next flow-accept on that fd raises
;; 'loop-accept-block "concurrent accept on fd".
;;
;; The slot is only cleared when a completion actually arrives (
;; loop-run-once deletes the handler before calling it), so the fd
;; stays poisoned for exactly as long as no client connects -- i.e. the
;; realistic case, since "accept under a deadline" is what a server
;; does when it is idle. Any server that puts flow-accept inside a
;; flow-monitor or any cancellable scope loses its listening socket on
;; the first cancellation, permanently.
;;
;; Only 4 of flow2's 11 block procs call register-cancel! (flow-timeout,
;; flow-read, flow-open, flow-read-at). flow-accept, flow-write,
;; flow-write-at, flow-close, flow-get and both scope bases do not --
;; see finding 4 of the review for the write-side consequences.
;;
;; (letloop flow) shipped ~check-flow-006/read-or-timeout-leaves-fd-
;; usable, whose stated point is precisely that a CANCELLED I/O op
;; leaves the fd usable, plus ~check-flow-009/open-loses-choice-no-fd-
;; leak. flow2 dropped both, along with the other nine fd- and
;; ring-touching checks (flow has 40 checks, flow2 has 21). Porting
;; them back is the cheapest guard against this whole class.
;;
;; Run (HANGS on a buggy build via repro-flow2-block-raise's finding --
;; the raise below kills the fiber outside the scope guard, so the
;; monitor's join never completes; always use timeout):
;;
;;   timeout 25 ./venv $(pwd)/local/ local/bin/letloop compile \
;;     ./src/ ./checks/ checks/repro-flow2-accept-cancel.scm \
;;     repro-flow2-accept-cancel && ./a.out
;;
;; Buggy build (current dev):
;;
;;   first accept under a 50ms monitor
;;     -> timed out, as expected
;;   second accept under a 50ms monitor
;;   loop-apply: fiber died: Exception in loop-accept-block:
;;     concurrent accept on fd with irritant 4
;;   <hang>
;;
;; Fixed build: both accepts print "-> timed out, as expected" and the
;; program exits 0. Nothing should ever connect to port 18099 during
;; the run; both monitors are supposed to expire.
(library (repro-flow2-accept-cancel)
  (export repro-flow2-accept-cancel)
  (import (chezscheme) (letloop flow2)
          (only (letloop liburing low)
                loop-socket-new loop-bind loop-listen
                AF-INET SOCK-STREAM))

  (define %port 18099)

  (define (say . args)
    (for-each display args)
    (newline)
    (flush-output-port (current-output-port)))

  ;; Park on accept until the monitor's deadline cancels us. On the
  ;; current dev build the second call's raise never reaches this guard
  ;; at all -- it escapes the fiber via loop-apply (see
  ;; repro-flow2-block-raise.scm), so stdout simply stops after the
  ;; label and the diagnosis is on stderr. The (#t ...) clause is what
  ;; discriminates a build where finding 1 is fixed and finding 2 is
  ;; not: there the raise reaches the scope and re-raises at the join,
  ;; and this prints "-> RAISED: ... concurrent accept on fd".
  (define (accept-under-deadline fd label)
    (say label)
    (guard (ex ((flow-error-timeout? ex)
                (say "  -> timed out, as expected"))
               (#t
                (display "  -> RAISED: ")
                (if (condition? ex) (display-condition ex) (display ex))
                (newline)
                (flush-output-port (current-output-port))))
      (flow-monitor 0.05 (lambda () (flow-perform (flow-accept fd))))))

  (define (repro-flow2-accept-cancel)
    (flow-run
     (lambda (workers)
       (let ((fd (loop-socket-new AF-INET SOCK-STREAM 0)))
         ;; loop-bind sets SO_REUSEADDR / SO_REUSEPORT itself.
         (loop-bind fd "127.0.0.1" %port)
         (loop-listen fd 128)
         (accept-under-deadline fd "first accept under a 50ms monitor")
         (accept-under-deadline fd "second accept under a 50ms monitor")
         (flow-stop))))))

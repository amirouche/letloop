;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop flow) — Concurrent ML style events (Reppy's "events",
;; guile-fibers' "operations") synchronized over the io_uring loop
;; from (letloop liburing low). Ported from the coop.scm design
;; sketch; see plans/v12/20260720-flow/README.md for the full design
;; and milestone plan. Implements FL-1 (base event algebra) and FL-2
;; (choice) — no channels, no I/O events yet.
(library (letloop flow)

  (export make-flow flow? flow-wrap flow-guard flow-choice flow-perform

          flow-spawn flow-run flow-stop

          ~check-flow-000/always-ready
          ~check-flow-000/wrap-order
          ~check-flow-000/guard
          ~check-flow-000/suspend-resume

          ~check-flow-001/choice-two-ready
          ~check-flow-001/choice-ready-or-never
          ~check-flow-001/nested-choice-flattens
          ~check-flow-001/block-fanout-race)

  (import (chezscheme)
          (letloop r999)
          (letloop liburing low))

  ;; A <flow> is either:
  ;;
  ;;   type = 'base  — data unused; wrap/try/block are the event's own
  ;;                   post-synchronization transformer, non-blocking
  ;;                   poll, and blocking registration (§4.2).
  ;;   type = 'guard — data is a thunk that must produce a fresh event
  ;;                   on every synchronization attempt (§4.1); wrap/
  ;;                   try/block are unused, resolved via flow-flatten.
  ;;   type = 'choice — data is a vector of member events (possibly
  ;;                    themselves choices/guards); wrap/try/block are
  ;;                    unused, resolved via flow-flatten. flow-choice
  ;;                    is associative and does not eagerly flatten —
  ;;                    flow-flatten unwraps nesting at perform time.
  (define-record-type* <flow>
    (make-flow% type data wrap try block)
    flow?
    (type  flow-type)
    (data  flow-data)
    (wrap  flow-wrap-proc)
    (try   flow-try-proc)
    (block flow-block-proc))

  (define make-flow
    (lambda (wrap try block)
      (make-flow% 'base #f wrap try block)))

  (define flow-guard
    (lambda (thunk)
      (make-flow% 'guard thunk #f #f #f)))

  ;; Choice is associative; a single-event choice is left as a
  ;; 1-element choice rather than collapsed — flow-flatten treats it
  ;; identically to collapsing, so there is no observable difference
  ;; and no need to special-case it here.
  (define flow-choice
    (lambda events
      (make-flow% 'choice (list->vector events) #f #f #f)))

  (define flow-wrap
    (lambda (event proc)
      (case (flow-type event)
        ((base)
         (make-flow% 'base #f
                     (lambda (x) (proc ((flow-wrap-proc event) x)))
                     (flow-try-proc event)
                     (flow-block-proc event)))
        ((guard)
         (make-flow% 'guard
                     (lambda () (flow-wrap ((flow-data event)) proc))
                     #f #f #f))
        ((choice)
         (make-flow% 'choice
                     (vector-map (lambda (base) (flow-wrap base proc))
                                 (flow-data event))
                     #f #f #f))
        (else
         (error 'flow-wrap "unsupported flow type" (flow-type event))))))

  ;; Resolve EVENT down to the list of base events it synchronizes
  ;; over: a base is its own singleton flattening; a guard is resolved
  ;; by calling its thunk exactly once and flattening the result; a
  ;; choice recursively flattens its members (this is where nested
  ;; choices collapse, since choice is associative).
  (define flow-flatten
    (lambda (event)
      (case (flow-type event)
        ((base) (list event))
        ((guard) (flow-flatten ((flow-data event))))
        ((choice)
         (apply append (map flow-flatten (vector->list (flow-data event)))))
        (else
         (error 'flow-flatten "unsupported flow type" (flow-type event))))))

  (define flow-rotate
    (lambda (lst n)
      (if (or (null? lst) (fxzero? n))
          lst
          (append (list-tail lst n) (list-head lst n)))))

  ;; Sentinel distinguishing "no base was ready" from a legitimate #f
  ;; result value; opaque, compared with eq? only.
  (define %flow-not-ready (list 'not-ready))

  (define flow-poll
    (lambda (bases)
      (let ((n (length bases)))
        (let loop ((bs (flow-rotate bases (if (fxzero? n) 0 (random n)))))
          (if (null? bs)
              %flow-not-ready
              (let ((thunk ((flow-try-proc (car bs)))))
                (if thunk
                    ((flow-wrap-proc (car bs)) (thunk))
                    (loop (cdr bs)))))))))

  ;; Allocate one state box shared by every base, register (state
  ;; resume) with each base's block, and suspend the current fiber.
  ;; resume always defers through loop-spawn rather than calling the
  ;; parked continuation directly — the completing side may itself be
  ;; in the middle of a CQE drain (§4.3). box-cas! guards against a
  ;; base being resumed more than once (e.g. a losing sibling whose
  ;; completion arrives after the choice already synched).
  (define flow-block-and-wait
    (lambda (bases)
      (let ((state (box 'waiting)))
        (loop-abort
         (lambda (k)
           (define resume
             (lambda (value)
               (when (box-cas! state 'waiting 'synched)
                 (loop-spawn (lambda () (k value))))))
           (for-each (lambda (base) ((flow-block-proc base) state resume))
                     bases))))))

  (define flow-perform
    (lambda (event)
      (let* ((bases  (flow-flatten event))
             (result (flow-poll bases)))
        (if (eq? result %flow-not-ready)
            (flow-block-and-wait bases)
            result))))

  (define flow-spawn loop-spawn)
  (define flow-run loop-run)
  (define flow-stop loop-stop)

  (include "letloop/flow.check.scm"))

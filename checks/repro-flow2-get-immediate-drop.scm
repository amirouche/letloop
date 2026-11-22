;; Reproducer for finding 7 of the 2026-08-17 adverse review of
;; (letloop flow2): flow-get's immediate path discards resume's return
;; value, so a value that was already dequeued from the channel is
;; delivered to nobody and is simply gone.
;;
;; Mechanism. flow-get's block proc (flow2.scm:806-820) takes the
;; channel mutex and, if the channel turns out to be non-empty by the
;; time it registers, claims its own entry and dequeues:
;;
;;   (when immediate
;;     (resume (cdr immediate)))
;;
;; resume returns #f when the perform's shared state box has already
;; CASed to 'synched -- i.e. some other base of the same choice won
;; first. The value is out of the channel and the fiber is committed to
;; the other base's result, so nothing ever receives it. %channel-put!
;; gets the identical situation right twenty lines earlier, at :782:
;;
;;   (unless ((flow-getter-resume entry) obj)
;;     (try))
;;
;; When it happens. Registration is a plain for-each over the flattened
;; bases with no early exit, so a base that resumes INLINE (during
;; registration) is followed by the registration of every later base --
;; including a flow-get whose channel became non-empty in between. On a
;; compute thread that window is wide and ordinary: registration runs
;; inline on the worker's own stack, so another thread completing a
;; sibling get between two block calls is all it takes. This reproducer
;; makes the same interleaving deterministic and single-threaded, with
;; a filler base that does both halves itself -- puts to the channel,
;; then wins -- rather than relying on a race to schedule.
;;
;; This is the class of flow's most expensive incident (legacy report
;; §2.1, cross-check §B3): the value does not error, does not warn, and
;; does not appear anywhere. The peer that was going to receive it just
;; waits, and the diagnosis points at the waiter.
;;
;; Run (does NOT hang):
;;
;;   timeout 25 ./venv $(pwd)/local/ local/bin/letloop exec \
;;     ./src/ ./checks/ checks/repro-flow2-get-immediate-drop.scm \
;;     repro-flow2-get-immediate-drop
;;
;; Buggy build (dev @ 89bb403):
;;
;;   perform returned: winner        (correct -- the filler did win)
;;   channel afterwards: EMPTY       <- the value was dropped
;;   FAIL: flow-get dequeued 'the-value and delivered it to nobody
;;
;; Fixed build: "channel afterwards: the-value" and "PASS".
(library (repro-flow2-get-immediate-drop)
  (export repro-flow2-get-immediate-drop)
  (import (chezscheme) (letloop flow2))

  (define (say . args)
    (for-each display args)
    (newline)
    (flush-output-port (current-output-port)))

  ;; Never ready at poll time, so the perform is forced to block and
  ;; the registration for-each runs. Its block proc then does, in this
  ;; order, the two things that open the window: it fills the channel
  ;; (so the flow-get registering after it takes the immediate path),
  ;; and it wins the perform (so that base's resume returns #f).
  (define (filler channel value)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume register-cancel!)
                 (flow-put! channel value)
                 (resume 'winner))))

  (define (repro-flow2-get-immediate-drop)
    (flow-run
     (lambda (workers)
       (let ((channel (make-flow-channel)))
         ;; The filler is FIRST, so it registers first: flow-flatten
         ;; preserves choice order and registration walks it in order.
         (let ((result (flow-perform
                        (flow-choice (filler channel 'the-value)
                                     (flow-get channel)))))
           (say "perform returned: " result)
           (let ((left (flow-get-try channel 'EMPTY)))
             (say "channel afterwards: " left)
             (if (eq? left 'the-value)
                 (say "PASS")
                 (say "FAIL: flow-get dequeued 'the-value"
                      " and delivered it to nobody"))))
         (flow-stop))))))

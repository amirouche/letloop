;; Reproducer for the getter-growth half of finding 4 of the
;; 2026-08-17 adverse review of (letloop flow2): flow-get never calls
;; register-cancel!, so a get that LOSES a choice leaves its entry on
;; the channel's getters list forever.
;;
;; Mechanism. flow-get's block proc (flow2.scm:806-820) conses an entry
;; onto (flow-channel-getters channel) and registers no cancel thunk.
;; When another base of the same choice wins -- a timeout, a scope
;; cancellation -- the fiber unwinds, but the entry stays. The only
;; reaper is %channel-pop-getter! (:733), which drops dead entries as
;; it scans, and it runs ONLY from %channel-put!. So on a channel that
;; is polled and rarely (or never) written, nothing ever reaps:
;;
;;   (flow-choice (flow-get ch) (flow-timeout 0.1))
;;
;; grows the list by one entry per poll, unboundedly. That shape is not
;; exotic -- it is how you write "wait for work, but wake up to do
;; housekeeping", and it is the idle path, so it runs most often
;; exactly when the system has least else to do.
;;
;; Why the growth is much worse than one cons per round. The retained
;; entry holds the base's `resume`, which closes over resume-from,
;; which closes over `k` -- the parked fiber's captured continuation.
;; Every abandoned getter therefore pins a whole continuation, not a
;; record header. This is structurally the leak behind flow's 44GB
;; incident (legacy report §1.1), and flow's regression check for the
;; class, ~check-flow-004/compaction, is one of the checks the fork
;; dropped.
;;
;; What this measures. Retained bytes after a full collection, at two
;; round counts, so the per-round retention is a slope rather than an
;; absolute number -- the same baseline-and-compare shape
;; ~check-flow2-009/open-loses-choice-no-fd-leak uses for fds. The
;; getters list is library-internal, so from out here bytes is the
;; honest observable; the in-library regression check
;; (~check-flow2-002/losing-get-leaves-no-getter) asserts on the list
;; length directly.
;;
;; Run (takes ~10s, does NOT hang):
;;
;;   timeout 60 ./venv $(pwd)/local/ local/bin/letloop exec \
;;     ./src/ ./checks/ checks/repro-flow2-getter-leak.scm \
;;     repro-flow2-getter-leak
;;
;; Buggy build (dev @ 89bb403): retention grows linearly with rounds
;; and the per-round slope is hundreds of bytes; prints "LEAK".
;; Fixed build: the two measurements are flat to within noise and the
;; slope is ~0; prints "PASS".
(library (repro-flow2-getter-leak)
  (export repro-flow2-getter-leak)
  (import (chezscheme) (letloop flow2))

  ;; Short enough to keep the run tolerable, long enough that the
  ;; timeout genuinely parks rather than completing during poll.
  (define %tick 0.0005)

  (define (say . args)
    (for-each display args)
    (newline)
    (flush-output-port (current-output-port)))

  (define (retained)
    (collect (collect-maximum-generation))
    (bytes-allocated))

  ;; Poll CHANNEL n times, letting the timeout win every time -- nobody
  ;; ever puts to it.
  (define (poll-rounds channel n)
    (let round ((i 0))
      (when (fx<? i n)
        (flow-perform (flow-choice (flow-get channel)
                                   (flow-wrap (flow-timeout %tick)
                                              (lambda (_) 'late))))
        (round (fx+ i 1)))))

  ;; Both checkpoints inside ONE flow-run on ONE channel. Measuring two
  ;; separate runs instead makes the slope a difference of two
  ;; independent baselines -- loop tables, boot-time garbage the first
  ;; full collection happens to reap -- which on a fixed build is pure
  ;; noise and swamps the signal in both directions.
  (define %small 200)
  (define %large 2000)

  (define (repro-flow2-getter-leak)
    (let ((a #f) (b #f))
      (flow-run
       (lambda (workers)
         (let ((channel (make-flow-channel)))
           (poll-rounds channel %small)
           (set! a (retained))
           (poll-rounds channel (- %large %small))
           (set! b (retained))
           ;; Touch the channel last so it cannot have been collected as
           ;; dead before either measurement.
           (flow-get-try channel 'none)
           (flow-stop))))
      (say "retained at " %small " rounds:  " a " bytes")
      (say "retained at " %large " rounds: " b " bytes")
      (let ((slope (/ (- b a) (- %large %small))))
        (say "per-round retention: " (exact->inexact slope) " bytes")
        ;; A fixed build still retains a little -- the loop's own tables
        ;; grow a bit -- so compare against a threshold well under one
        ;; retained continuation per round rather than against zero.
        (if (> slope 32)
            (say "LEAK: every losing flow-get left its entry"
                 " on the channel")
            (say "PASS"))))))

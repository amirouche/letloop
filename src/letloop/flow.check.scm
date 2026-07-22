;; Checks for (letloop flow), milestones FL-1 (base event algebra) and
;; FL-2 (choice). Included at the tail of the library; discovered by
;; `make check` via the ~check- exports.

(define (~check-flow-000/always-ready)
  (define ev (make-flow (lambda (x) x)
                         (lambda () (lambda () 42))
                         (lambda (state resume)
                           (error 'block "should never block"))))
  (equal? (flow-perform ev) 42))

(define (~check-flow-000/wrap-order)
  (define base (make-flow (lambda (x) x)
                           (lambda () (lambda () 1))
                           (lambda (state resume)
                             (error 'block "should never block"))))
  ;; w2 wraps w1 wraps base: value flows base -> w1 -> w2, i.e. the
  ;; outermost (most recently applied) flow-wrap runs last.
  (define w1 (flow-wrap base (lambda (x) (* x 10))))
  (define w2 (flow-wrap w1 (lambda (x) (+ x 1))))
  (equal? (flow-perform w2) 11))

(define (~check-flow-000/guard)
  (define counter 0)
  (define ev
    (flow-guard
     (lambda ()
       (set! counter (+ counter 1))
       (make-flow (lambda (x) x)
                  (lambda () (lambda () counter))
                  (lambda (state resume)
                    (error 'block "should never block"))))))
  ;; the thunk must re-run on every synchronization attempt, not be
  ;; memoized after the first flow-perform.
  (and (equal? (flow-perform ev) 1)
       (equal? (flow-perform ev) 2)))

(define (~check-flow-000/suspend-resume)
  (define result #f)
  (define ev
    (make-flow (lambda (x) x)
               (lambda () #f)                   ;; try: never ready
               (lambda (state resume)
                 ;; complete on a later tick, exercising the real
                 ;; loop-abort / box-cas! / loop-spawn suspend path
                 (loop-spawn (lambda () (resume 'resumed))))))
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform ev))
     (loop-stop)))
  (loop-run)
  (eq? result 'resumed))

(define (~check-flow-001/choice-two-ready)
  (define a (make-flow (lambda (x) x)
                        (lambda () (lambda () 'a))
                        (lambda (state resume)
                          (error 'block "should never block"))))
  (define b (make-flow (lambda (x) x)
                        (lambda () (lambda () 'b))
                        (lambda (state resume)
                          (error 'block "should never block"))))
  (define result (flow-perform (flow-choice a b)))
  (or (eq? result 'a) (eq? result 'b)))

(define (~check-flow-001/choice-ready-or-never)
  (define ready (make-flow (lambda (x) x)
                            (lambda () (lambda () 'ready))
                            (lambda (state resume)
                              (error 'block "should never block"))))
  ;; try never succeeds and block must never be reached: the poll
  ;; phase finds `ready` in the same pass regardless of rotation.
  (define never (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume)
                              (error 'block "ready sibling exists, should not block"))))
  (and (eq? (flow-perform (flow-choice never ready)) 'ready)
       (eq? (flow-perform (flow-choice ready never)) 'ready)))

(define (~check-flow-001/nested-choice-flattens)
  (define (never)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume)
                 (error 'block "ready sibling exists, should not block"))))
  (define ready (make-flow (lambda (x) x)
                            (lambda () (lambda () 'c))
                            (lambda (state resume)
                              (error 'block "should never block"))))
  (eq? (flow-perform (flow-choice (flow-choice (never) (never)) ready))
       'c))

;; The double-completion race the design calls out as the invariant
;; that matters: two bases share one state box; `a` resumes one tick
;; before `b`. box-cas! must let `a` win and turn `b`'s later resume
;; into a no-op — not a second (invalid) invocation of the parked
;; one-shot continuation.
(define (~check-flow-001/block-fanout-race)
  (define winner #f)
  (define a (make-flow (lambda (x) x)
                        (lambda () #f)
                        (lambda (state resume)
                          (loop-spawn (lambda () (resume 'a))))))
  (define b (make-flow (lambda (x) x)
                        (lambda () #f)
                        (lambda (state resume)
                          (loop-spawn
                           (lambda () (loop-spawn (lambda () (resume 'b))))))))
  (loop-new)
  (loop-spawn (lambda () (set! winner (flow-perform (flow-choice a b)))))
  (let tick ((n 0))
    (when (fx<? n 4)
      (loop-run-once)
      (tick (fx+ n 1))))
  (eq? winner 'a))

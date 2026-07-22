;; Checks for (letloop flow), milestone FL-1: base event algebra only.
;; Included at the tail of the library; discovered by `make check` via
;; the ~check- exports.

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

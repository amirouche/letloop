;; Checks for (letloop flow), milestones FL-1 (base event algebra) and
;; FL-2 (choice). Included at the tail of the library; discovered by
;; `make check` via the ~check- exports.

(define (~check-flow-000/always-ready)
  (define ev (make-flow (lambda (x) x)
                         (lambda () (lambda () 42))
                         (lambda (state resume register-cancel!)
                           (error 'block "should never block"))))
  (equal? (flow-perform ev) 42))

(define (~check-flow-000/wrap-order)
  (define base (make-flow (lambda (x) x)
                           (lambda () (lambda () 1))
                           (lambda (state resume register-cancel!)
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
                  (lambda (state resume register-cancel!)
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
               (lambda (state resume register-cancel!)
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
                        (lambda (state resume register-cancel!)
                          (error 'block "should never block"))))
  (define b (make-flow (lambda (x) x)
                        (lambda () (lambda () 'b))
                        (lambda (state resume register-cancel!)
                          (error 'block "should never block"))))
  (define result (flow-perform (flow-choice a b)))
  (or (eq? result 'a) (eq? result 'b)))

(define (~check-flow-001/choice-ready-or-never)
  (define ready (make-flow (lambda (x) x)
                            (lambda () (lambda () 'ready))
                            (lambda (state resume register-cancel!)
                              (error 'block "should never block"))))
  ;; try never succeeds and block must never be reached: the poll
  ;; phase finds `ready` in the same pass regardless of rotation.
  (define never (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (error 'block "ready sibling exists, should not block"))))
  (and (eq? (flow-perform (flow-choice never ready)) 'ready)
       (eq? (flow-perform (flow-choice ready never)) 'ready)))

(define (~check-flow-001/nested-choice-flattens)
  (define (never)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume register-cancel!)
                 (error 'block "ready sibling exists, should not block"))))
  (define ready (make-flow (lambda (x) x)
                            (lambda () (lambda () 'c))
                            (lambda (state resume register-cancel!)
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
                        (lambda (state resume register-cancel!)
                          (loop-spawn (lambda () (resume 'a))))))
  (define b (make-flow (lambda (x) x)
                        (lambda () #f)
                        (lambda (state resume register-cancel!)
                          (loop-spawn
                           (lambda () (loop-spawn (lambda () (resume 'b))))))))
  (loop-new)
  (loop-spawn (lambda () (set! winner (flow-perform (flow-choice a b)))))
  (let tick ((n 0))
    (when (fx<? n 4)
      (loop-run-once)
      (tick (fx+ n 1))))
  (eq? winner 'a))

(define (~check-flow-002/ping-pong)
  (define ch (make-flow-channel))
  (define log '())
  (loop-new)
  (loop-spawn (lambda ()
                (flow-put! ch 1)
                (flow-put! ch 2)
                (flow-put! ch 3)))
  (loop-spawn (lambda ()
                (set! log (cons (flow-get! ch) log))
                (set! log (cons (flow-get! ch) log))
                (set! log (cons (flow-get! ch) log))
                (loop-stop)))
  (loop-run)
  (equal? (reverse log) (list 1 2 3)))

(define (~check-flow-003/n-producers-one-consumer)
  (define ch (make-flow-channel))
  (define ids (list 0 1 2 3 4))
  (define received '())
  (loop-new)
  (for-each (lambda (i) (loop-spawn (lambda () (flow-put! ch i)))) ids)
  (loop-spawn (lambda ()
                (let loop ((n 0))
                  (when (fx<? n (length ids))
                    (set! received (cons (flow-get! ch) received))
                    (loop (fx+ n 1))))
                (loop-stop)))
  (loop-run)
  (equal? (sort < received) (sort < ids)))

(define (~check-flow-004/same-channel-choice-raises)
  (define ch (make-flow-channel))
  (guard (ex ((flow-same-channel-choice-condition? ex)
              (eq? (flow-same-channel-choice-channel ex) ch)))
    (flow-perform (flow-choice (flow-put ch 'x) (flow-get ch)))
    #f))

;; Drives the compaction mechanism directly against the FIFO/counter
;; rather than through %flow-channel-gc-threshold real rendezvous:
;; each real put/get costs a full io_uring idle-wait tick (~100ms,
;; since nothing pins an actual completion), so reaching the default
;; threshold of 1024 that way would take minutes for no added
;; coverage — flow-channel-bump-gc! itself doesn't touch the loop.
(define (~check-flow-004/compaction)
  (define ch (make-flow-channel))
  (define (dead-entry i)
    (let ((state (box 'waiting)))
      (box-cas! state 'waiting 'synched)
      (make-flow-channel-entry state (lambda (v) #f) i)))
  (define (build-list n f)
    (let loop ((i 0) (acc '()))
      (if (fx=? i n) acc (loop (fx+ i 1) (cons (f i) acc)))))
  (flow-channel-puts! ch (build-list 5 dead-entry))
  (let loop ((i 0))
    (when (fx<? i %flow-channel-gc-threshold)
      (flow-channel-bump-gc! ch)
      (loop (fx+ i 1))))
  (null? (flow-channel-puts ch)))

;; Producer is spawned second, so it runs first (loop-spawn prepends,
;; loop-run-once processes the thunk list front-to-back): it blocks on
;; an empty channel first, then the consumer's try matches it in the
;; same tick, so the choice resolves on the get without ever calling
;; the timeout base's block — no real timeout SQE is armed at all.
(define (~check-flow-005/get-or-timeout-put-first)
  (define ch (make-flow-channel))
  (define result #f)
  (loop-new)
  (loop-spawn (lambda ()
                (set! result (flow-perform (flow-choice (flow-get ch) (flow-timeout 2.0))))
                (loop-stop)))
  (loop-spawn (lambda () (flow-put! ch 'value)))
  (loop-run)
  (eq? result 'value))

;; No producer at all: the timeout is the only base that can ever
;; complete, so a short one proves flow-timeout/flow-choice actually
;; deliver a real IORING_OP_TIMEOUT completion rather than hanging.
(define (~check-flow-005/get-or-timeout-timeout-first)
  (define ch (make-flow-channel))
  (define result 'not-set)
  (loop-new)
  (loop-spawn (lambda ()
                (set! result (flow-perform (flow-choice (flow-get ch) (flow-timeout 0.02))))
                (loop-stop)))
  (loop-run)
  (eq? result (void)))

;; Consumer is spawned second (runs first): its get and its 2s timeout
;; both fail to poll ready, so it genuinely blocks and arms a real
;; timeout SQE. Producer (runs second) flow-sleeps 50ms — a real
;; timeout of its own — before putting, so the match against the
;; consumer's already-armed choice happens strictly on a later tick,
;; genuinely exercising register-cancel! rather than the "never even
;; blocked" path above. flow-perform's return isn't gated on the
;; cancel SQE completing (§4.3: cancellation is fire-and-forget), so
;; this can't observe the kernel op being removed directly; what it
;; does prove is the behavioral guarantee that matters — resolving via
;; the put, promptly, rather than being stuck until the 2s timer.
(define (~check-flow-005/losing-timeout-cancelled)
  (define ch (make-flow-channel))
  (define result #f)
  (define start #f)
  (define elapsed #f)
  (loop-new)
  (loop-spawn (lambda ()
                (set! start (real-time))
                (set! result (flow-perform (flow-choice (flow-get ch) (flow-timeout 2.0))))
                (set! elapsed (- (real-time) start))
                (loop-stop)))
  (loop-spawn (lambda ()
                (flow-sleep 0.05)
                (flow-put! ch 'value)))
  (loop-run)
  (and (eq? result 'value)
       (fx<? elapsed 1000)))

;; Real loopback TCP: a listener accepts via flow-accept, echoes one
;; message back via flow-read/flow-write; the peer connects, sends,
;; and reads the echo back via flow-write/flow-read too, so both
;; directions of both events run over a real socket pair.
(define (~check-flow-006/echo-pair)
  (define PORT 18234)
  (define listen-fd (loop-socket-new AF-INET SOCK-STREAM 0))
  (define result #f)
  (loop-new)
  (loop-bind listen-fd "127.0.0.1" PORT)
  (loop-listen listen-fd 128)
  (loop-spawn (lambda ()
                (let* ((client (flow-perform (flow-accept listen-fd)))
                       (data   (flow-perform (flow-read client))))
                  (flow-perform (flow-write client data))
                  (loop-close client))))
  (loop-spawn (lambda ()
                (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
                  (lambda (addr addrlen)
                    (let ((fd (loop-connect addr addrlen)))
                      (foreign-free addr)
                      (flow-perform (flow-write fd (string->utf8 "hello")))
                      (set! result (flow-perform (flow-read fd)))
                      (loop-close fd))))
                (loop-close listen-fd)
                (loop-stop)))
  (loop-run)
  (equal? result (string->utf8 "hello")))

;; A read racing a short timeout on a silent socket must resolve via
;; the timeout (not hang), and — the actual point of this check — the
;; fd must still be usable afterward: a fresh flow-read on the same
;; fd must see the client's message once it actually arrives, proving
;; the cancelled/lost read didn't consume or corrupt the connection.
(define (~check-flow-006/read-or-timeout-leaves-fd-usable)
  (define PORT 18235)
  (define listen-fd (loop-socket-new AF-INET SOCK-STREAM 0))
  (define timed-out #f)
  (define result #f)
  (loop-new)
  (loop-bind listen-fd "127.0.0.1" PORT)
  (loop-listen listen-fd 128)
  (loop-spawn (lambda ()
                (let ((client (flow-perform (flow-accept listen-fd))))
                  (set! timed-out
                    (eq? (flow-perform (flow-choice (flow-read client) (flow-timeout 0.05)))
                         (void)))
                  (set! result (flow-perform (flow-read client)))
                  (loop-close client)
                  (loop-close listen-fd)
                  (loop-stop))))
  (loop-spawn (lambda ()
                (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
                  (lambda (addr addrlen)
                    (let ((fd (loop-connect addr addrlen)))
                      (foreign-free addr)
                      ;; stay silent well past the server's 50ms
                      ;; read-or-timeout before finally sending
                      (flow-sleep 0.2)
                      (flow-perform (flow-write fd (string->utf8 "late")))
                      (loop-close fd))))))
  (loop-run)
  (and timed-out
       (equal? result (string->utf8 "late"))))

;; FL-6: a standalone proof that flow composes for a realistic
;; consumer pattern — a per-connection request/echo loop that races
;; each read against an idle timeout and closes gracefully once the
;; peer goes silent, the same shape http/server.body.scm's read path
;; would take if ported onto flow. Deliberately left as a standalone
;; check rather than actually replacing that file's own idle handling
;; (a periodic sweep over all connections, not a per-read race) — see
;; plans/v12/20260720-flow/README.md's FL-6 milestone note.
(define (~check-flow-006/request-loop-idle-timeout)
  (define PORT 18236)
  (define listen-fd (loop-socket-new AF-INET SOCK-STREAM 0))
  (define echoed '())
  (define closed-on-timeout #f)
  (loop-new)
  (loop-bind listen-fd "127.0.0.1" PORT)
  (loop-listen listen-fd 128)
  (loop-spawn (lambda ()
                (let ((client (flow-perform (flow-accept listen-fd))))
                  (let request-loop ()
                    (let ((result (flow-perform
                                   (flow-choice (flow-read client) (flow-timeout 0.1)))))
                      (cond
                       ((eq? result (void))   ;; idle timeout won
                        (set! closed-on-timeout #t)
                        (loop-close client))
                       ((eq? result #t)       ;; peer EOF
                        (loop-close client))
                       (else
                        (set! echoed (cons result echoed))
                        (flow-perform (flow-write client result))
                        (request-loop)))))
                  (loop-close listen-fd)
                  (loop-stop))))
  (loop-spawn (lambda ()
                (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
                  (lambda (addr addrlen)
                    (let ((fd (loop-connect addr addrlen)))
                      (foreign-free addr)
                      (flow-perform (flow-write fd (string->utf8 "one")))
                      (flow-perform (flow-read fd))
                      (flow-perform (flow-write fd (string->utf8 "two")))
                      (flow-perform (flow-read fd))
                      ;; go silent well past the server's 100ms
                      ;; per-read idle timeout before closing
                      (flow-sleep 0.3)
                      (loop-close fd))))))
  (loop-run)
  (and (equal? (reverse echoed) (list (string->utf8 "one") (string->utf8 "two")))
       closed-on-timeout))

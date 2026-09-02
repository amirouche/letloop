;; Checks for (letloop flow2). Included at the tail of the library;
;; discovered by `make check` via the ~check- exports. Checks that
;; need the loop use the real entry point — flow-run with a fiber
;; zero that calls flow-stop — rather than driving loop-run-once by
;; hand, so the lifecycle (worker pool startup and teardown included)
;; is exercised on every run.

;;------------------------------------------------------------
;; Errors
;;------------------------------------------------------------

(define (~check-flow2-000/error-symbol-dispatch)
  (define err (make-flow-error 'timeout "deadline" '(0.25) #f))
  (assert (flow-error? err))
  (assert (eq? 'slow (case (flow-error-symbol err)
                       ((timeout) 'slow)
                       ((cancelled) 'gone)
                       (else 'other))))
  (assert (equal? "deadline" (flow-error-message err)))
  (assert (equal? '(0.25) (flow-error-irritants err)))
  (assert (not (flow-error-cause err)))
  #t)

(define (~check-flow2-000/error-predicates)
  (define cancelled (make-flow-error 'cancelled "" '() #f))
  (define compute (make-flow-error 'compute "" '() 'boom))
  (assert (flow-error-cancelled? cancelled))
  (assert (not (flow-error-timeout? cancelled)))
  (assert (not (flow-error-overflow? cancelled)))
  (assert (flow-error-compute? compute))
  (assert (eq? 'boom (flow-error-cause compute)))
  (assert (not (flow-error? 'compute)))
  (assert (not (flow-error-wrong-thread? 42)))
  #t)

;; flow-log must be safe to call from the loop thread and from a
;; compute thread, so it does exactly one thing: cons onto a box the
;; calling thread owns. Nothing here starts the flush thread -- draining
;; by hand is what a check wants, and it also pins the ordering
;; contract: oldest-first within a thread's own box.
(define (~check-flow2-000/log-is-nonblocking-and-drains)
  ;; drain whatever earlier checks left behind, so this one sees only
  ;; its own entries
  (flow-log-drain!)
  (flow-log '(alpha))
  (flow-log '(beta 2))
  (let ((entries (flow-log-drain!)))
    (assert (= 2 (length entries)))
    ;; every entry is (timestamp . sexp), oldest first
    (assert (equal? '(alpha) (cdr (car entries))))
    (assert (equal? '(beta 2) (cdr (cadr entries))))
    ;; a log call before any loop exists must not raise -- a library
    ;; that warns during startup would otherwise take the program down
    (assert (fixnum? (car (car entries)))))
  ;; drained means drained
  (assert (null? (flow-log-drain!)))
  ;; and it works from a compute thread too, which is the half that
  ;; must never block
  (let ((done (box #f)))
    (fork-thread (lambda () (flow-log '(from-a-thread)) (set-box! done #t)))
    (let wait ((n 0))
      (when (and (not (unbox done)) (fx<? n 1000))
        (sleep (make-time 'time-duration 1000000 0))
        (wait (fx+ n 1))))
    (assert (unbox done)))
  (let ((entries (flow-log-drain!)))
    (assert (= 1 (length entries)))
    (assert (equal? '(from-a-thread) (cdr (car entries)))))
  #t)

;; The flush thread's lifecycle, exercised with nothing pending so the
;; check writes nothing to stderr. What matters here is that
;; flow-log-stop! returns rather than hanging -- it blocks the caller
;; until the thread has done its final drain and exited -- and that a
;; second flow-log-start! does not fork a competing flush thread. Two
;; threads interleaving writes to the same port produce shuffled output
;; at exactly the moment someone is reading it to diagnose something.
(define (~check-flow2-000/log-flush-thread-lifecycle)
  (flow-log-drain!)
  (flow-log-start! 0.02)
  (flow-log-start! 0.02)          ;; must be a no-op, not a second thread
  (flow-log-stop!)
  ;; stopped, so a fresh cycle must still be startable
  (flow-log-start! 0.02)
  (flow-log-stop!)
  #t)

;;------------------------------------------------------------
;; Event core
;;------------------------------------------------------------

(define (~check-flow2-001/always-ready)
  (define ev (make-flow (lambda (x) x)
                        (lambda () (lambda () 42))
                        (lambda (state resume register-cancel!)
                          (error 'block "should never block"))))
  (equal? (flow-perform ev) 42))

(define (~check-flow2-001/wrap-order)
  (define base (make-flow (lambda (x) x)
                          (lambda () (lambda () 1))
                          (lambda (state resume register-cancel!)
                            (error 'block "should never block"))))
  (define w1 (flow-wrap base (lambda (x) (* x 10))))
  (define w2 (flow-wrap w1 (lambda (x) (+ x 1))))
  (equal? (flow-perform w2) 11))

;;------------------------------------------------------------
;; Channels
;;------------------------------------------------------------

;; Buffered put needs no peer and no loop; get! drains FIFO.
(define (~check-flow2-002/channel-buffered-fifo)
  (define ch (make-flow-channel))
  (flow-put! ch 'a)
  (flow-put! ch 'b)
  (flow-put! ch 'c)
  (assert (eq? 'a (flow-get! ch)))
  (assert (eq? 'b (flow-get! ch)))
  (assert (eq? 'c (flow-get! ch)))
  #t)

(define (~check-flow2-002/channel-get-parks-until-put)
  (define ch (make-flow-channel))
  (define result #f)
  (flow-run
   (lambda (workers)
     (flow-spawn
      (lambda ()
        (flow-sleep 0.005)
        (flow-put! ch 'delivered)))
     (set! result (flow-get! ch))
     (flow-stop)))
  (eq? result 'delivered))

(define (~check-flow2-002/channel-bound-overflow)
  (define ch (make-flow-channel))
  (flow-channel-buffer-size! ch 2)
  (flow-put! ch 1)
  (flow-put! ch 2)
  (assert (guard (ex ((flow-error-overflow? ex) #t))
            (flow-put! ch 3)
            #f))
  ;; the failed put enqueued nothing
  (assert (eqv? 1 (flow-get! ch)))
  (assert (eqv? 2 (flow-get! ch)))
  (assert (eq? 'empty (flow-get-try ch 'empty)))
  #t)

;; Shrinking the bound below the current queue length raises at the
;; call site; the bound is never observably violated.
(define (~check-flow2-002/channel-bound-below-length)
  (define ch (make-flow-channel))
  (flow-put! ch 1)
  (flow-put! ch 2)
  (flow-put! ch 3)
  (guard (ex ((flow-error-overflow? ex)
              (equal? '(2 3) (flow-error-irritants ex))))
    (flow-channel-buffer-size! ch 2)
    #f))

;; The setter's domain is the constructor's: a positive fixnum or #f.
;; Zero used to slip through and made a channel that deadlocked
;; put-first — space waiters are only woken by a dequeue, and nothing
;; can ever enter a zero-bound queue — while get-first happened to
;; work, since a put hands its value straight to a parked getter.
;; Reproducer: repro-flow2-second-pass.scm, bound-zero scenario.
(define (~check-flow2-002/channel-bound-zero-rejected)
  (define ch (make-flow-channel 'validated 2))
  (assert (guard (ex (#t #t)) (make-flow-channel 'zero 0) #f))
  (assert (guard (ex (#t #t)) (flow-channel-buffer-size! ch 0) #f))
  ;; the rejected bound left the old one in place
  (assert (eqv? 2 (flow-channel-bound ch)))
  ;; #f un-bounds, matching the constructor's domain
  (flow-channel-buffer-size! ch #f)
  (assert (not (flow-channel-bound ch)))
  ;; an unbounded channel accepts puts past the old bound even with no
  ;; scheduler to park on
  (flow-put! ch 1)
  (flow-put! ch 2)
  (flow-put! ch 3)
  (assert (= 3 (flow-channel-queue-length ch)))
  #t)

;; Growing the bound is itself a source of room, so it must wake the
;; putters parked on the old bound — %channel-wake-space! otherwise
;; only runs after a dequeue, and a consumer that stopped consuming is
;; exactly when an operator raises a bound to relieve the producers.
(define (~check-flow2-002/raising-bound-wakes-parked-putters)
  (define ch (make-flow-channel 'growing 1))
  (define done '())
  (flow-run
   (lambda (workers)
     (flow-put! ch 1)                     ;; at the bound
     (flow-spawn (lambda () (flow-put! ch 2) (set! done (cons 2 done))))
     (flow-spawn (lambda () (flow-put! ch 3) (set! done (cons 3 done))))
     (flow-sleep 0.01)                    ;; both park
     (assert (null? done))
     (flow-channel-buffer-size! ch 4)     ;; room for both, no get involved
     (flow-sleep 0.01)
     (assert (= 2 (length done)))
     (flow-stop)))
  (assert (= 3 (flow-channel-queue-length ch)))
  ;; nothing left parked behind
  (assert (= 0 (flow-channel-space-length ch)))
  #t)

(define (~check-flow2-002/channel-get-try-default)
  (define ch (make-flow-channel))
  (assert (eq? 'nope (flow-get-try ch 'nope)))
  (flow-put! ch 'yes)
  (assert (eq? 'yes (flow-get-try ch 'nope)))
  (assert (eq? 'nope (flow-get-try ch 'nope)))
  #t)

(define (~check-flow2-002/channel-get-or-timeout)
  (define ch (make-flow-channel))
  (define first #f)
  (define second #f)
  (flow-run
   (lambda (workers)
     ;; empty channel: the timeout wins
     (set! first (flow-perform
                  (flow-choice (flow-get ch)
                               (flow-wrap (flow-timeout 0.005)
                                          (lambda (_) 'late)))))
     ;; value arrives first: the get wins, the losing 5s timeout is
     ;; cancelled on the ring (flow-run would otherwise still return,
     ;; but the ring op must not linger)
     (flow-spawn (lambda () (flow-put! ch 'fast)))
     (set! second (flow-perform
                   (flow-choice (flow-get ch)
                                (flow-wrap (flow-timeout 5.0)
                                           (lambda (_) 'late)))))
     (flow-stop)))
  (and (eq? first 'late) (eq? second 'fast)))

;; Every channel is identifiable, whether or not the caller named it --
;; a saturation warning that cannot say WHICH channel filled is barely
;; a warning. The auto name is deliberately a fixnum and not a symbol
;; built from one: Chez interns symbols for the life of the process, so
;; a program creating channels in a loop would leak one per channel.
(define (~check-flow2-002/channel-name)
  (define a (make-flow-channel))
  (define b (make-flow-channel))
  (define named (make-flow-channel 'sstable-writes))
  (assert (fixnum? (flow-channel-name a)))
  (assert (fixnum? (flow-channel-name b)))
  (assert (not (eqv? (flow-channel-name a) (flow-channel-name b))))
  (assert (eq? 'sstable-writes (flow-channel-name named)))
  #t)

;; Finding 7 of the 2026-08-17 review. flow-get's block proc, when it
;; finds the channel non-empty at registration time, claims its entry
;; and dequeues -- and then used to ignore resume's return value.
;; resume reports #f when an earlier base of the same perform already
;; won, and registration is a for-each with no early exit, so that is
;; reachable: the value is out of the channel, the fiber is committed
;; elsewhere, and nothing receives it. Silent, and the peer that was
;; waiting for it looks like the culprit.
;;
;; FILLER makes the interleaving deterministic instead of waiting for a
;; compute thread to produce it: never ready at poll, and its block does
;; both halves itself -- fills the channel, then wins -- so the flow-get
;; registering after it necessarily takes the immediate path with the
;; state box already synched. Standalone sweep in
;; checks/repro-flow2-get-immediate-drop.scm.
(define (~check-flow2-002/losing-get-does-not-eat-a-value)
  (define ch (make-flow-channel))
  (define result #f)
  (define filler (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (flow-put! ch 'the-value)
                              (resume 'winner))))
  (flow-run
   (lambda (workers)
     ;; filler first: flow-flatten preserves choice order, and the
     ;; registration for-each walks it in order.
     (set! result (flow-perform (flow-choice filler (flow-get ch))))
     (flow-stop)))
  (assert (eq? result 'winner))
  ;; The value the losing get dequeued must still be in the channel.
  (assert (eq? 'the-value (flow-get-try ch 'EMPTY)))
  #t)

;; The getter-growth half of finding 4. flow-get registered no cancel
;; thunk, so a get that LOSES a choice left its entry on the channel's
;; getters list, and the only reaper -- %channel-pop-getter! -- runs
;; only from a put. A channel that is polled and never written therefore
;; grew by one entry per poll forever, each pinning a captured
;; continuation through its resume: structurally flow's 44GB leak, whose
;; regression check the fork had dropped.
;;
;; Asserted on the list itself rather than on retained bytes, which is
;; what the checks can see from inside the library and is exact. The
;; bytes-per-round version, which is what an outside caller can observe,
;; is checks/repro-flow2-getter-leak.scm: 378 bytes/round before the fix,
;; flat after.
(define (~check-flow2-002/losing-get-leaves-no-getter)
  (define ch (make-flow-channel))
  (define rounds 50)
  (flow-run
   (lambda (workers)
     (let round ((i 0))
       (when (fx<? i rounds)
         ;; nobody ever puts to ch, so the timeout wins every round
         (flow-perform (flow-choice (flow-get ch)
                                    (flow-wrap (flow-timeout 0.0005)
                                               (lambda (_) 'late))))
         (round (fx+ i 1))))
     (flow-stop)))
  ;; Not "small": zero. Every one of those gets lost, and a loser must
  ;; take its entry with it.
  (assert (null? (flow-channel-getters ch)))
  ;; ... and the channel still works afterwards.
  (flow-put! ch 'still-fine)
  (assert (eq? 'still-fine (flow-get-try ch 'EMPTY)))
  #t)

;; The diagnostics exist to show the gap between a structure's LOGICAL
;; state and its RAW one -- exactly the gap flow's 44GB leak lived in,
;; where the raw puts list held 62 entries at 70 cumulative puts while
;; logical pending stayed at 0. So this check drives a channel into
;; each of those states and reads both numbers.
(define (~check-flow2-002/diagnostics-see-what-leaks)
  (define ch (make-flow-channel 'diag 2))
  (define parked-getter #f)
  (assert (eqv? 2 (flow-channel-bound ch)))
  (assert (eqv? 0 (flow-channel-queue-length ch)))
  (assert (eqv? 0 (flow-channel-getters-length ch)))
  (assert (eqv? 0 (flow-channel-space-length ch)))
  (flow-run
   (lambda (workers)
     ;; queued values are visible
     (flow-put! ch 'a)
     (assert (eqv? 1 (flow-channel-queue-length ch)))
     ;; a putter parked on a full channel is visible as such, and is
     ;; NOT counted as a queued value
     (flow-put! ch 'b)
     (flow-spawn (lambda () (flow-put! ch 'c)))
     (flow-sleep 0.01)
     (assert (eqv? 2 (flow-channel-queue-length ch)))
     (assert (eqv? 1 (flow-channel-space-length ch)))
     ;; draining wakes the parked putter, so the space list empties
     (assert (eq? 'a (flow-get! ch)))
     (flow-sleep 0.01)
     (assert (eqv? 0 (flow-channel-space-length ch)))
     ;; a parked getter shows up on the getters list
     (let ((empty (make-flow-channel 'empty 4)))
       (flow-spawn (lambda () (set! parked-getter (flow-get! empty))))
       (flow-sleep 0.01)
       (assert (eqv? 1 (flow-channel-getters-length empty)))
       (assert (eqv? 0 (flow-channel-queue-length empty)))
       ;; ... and leaves it when it is served
       (flow-put! empty 'served)
       (flow-sleep 0.01)
       (assert (eq? 'served parked-getter))
       (assert (eqv? 0 (flow-channel-getters-length empty))))
     ;; scope bookkeeping: a nursery with a child in flight
     (flow-nursery
      (lambda (scope)
        (assert (eqv? 0 (flow-scope-children-count scope)))
        (flow-spawn (lambda () (flow-sleep 0.02)))
        (assert (eqv? 1 (flow-scope-children-count scope)))
        (assert (eqv? 0 (flow-scope-join-waiters-length scope)))))
     (flow-stop)))
  #t)

;; Channels are bounded by default, because unbounded is not a capacity
;; choice -- it is the decision to turn a rate mismatch into unbounded
;; memory growth and meet it as an OOM hours later. #f is still
;; available, but you have to say so at the call site.
(define (~check-flow2-002/default-bound-is-finite)
  (define ch (make-flow-channel))
  (define named (make-flow-channel 'small 2))
  (define unbounded (make-flow-channel 'big #f))
  (assert (eqv? 43 (flow-channel-bound ch)))
  (assert (eqv? 2 (flow-channel-bound named)))
  (assert (not (flow-channel-bound unbounded)))
  ;; a bad bound is a mistake at the call site, not a surprise later
  (assert (guard (ex (#t #t)) (make-flow-channel 'bad 0) #f))
  (assert (guard (ex (#t #t)) (make-flow-channel 'bad -1) #f))
  #t)

;; A put to a full channel parks and is resumed by the get that makes
;; room -- the whole point of choosing park over raise. The ordering is
;; asserted, not just the final contents: a put that "succeeded" by
;; silently exceeding the bound would leave the same contents behind.
(define (~check-flow2-002/put-parks-when-full)
  (define ch (make-flow-channel 'tiny 2))
  (define order '())
  (flow-run
   (lambda (workers)
     (flow-put! ch 1)
     (flow-put! ch 2)                    ;; at the bound
     (flow-spawn (lambda ()
                   (flow-put! ch 3)      ;; must park
                   (set! order (cons 'put-3-done order))))
     (flow-sleep 0.01)                   ;; let it park
     (set! order (cons 'before-drain order))
     (assert (eqv? 1 (flow-get! ch)))    ;; frees a slot, wakes the putter
     (flow-sleep 0.01)
     (set! order (cons 'after-drain order))
     (flow-stop)))
  ;; the parked put completed only AFTER the get made room
  (assert (equal? '(after-drain put-3-done before-drain) order))
  (assert (eqv? 2 (flow-get-try ch 'EMPTY)))
  (assert (eqv? 3 (flow-get-try ch 'EMPTY)))
  (assert (eq? 'EMPTY (flow-get-try ch 'EMPTY)))
  #t)

;; Parking makes flow-put! a suspension point, so it must also be a
;; cancellation point: a fiber parked on a full channel inside a
;; monitor has to be woken by the deadline like any other parked fiber,
;; and its space waiter has to be unregistered on the way out.
(define (~check-flow2-002/put-parked-on-full-is-cancellable)
  (define ch (make-flow-channel 'full-forever 1))
  (define outcome 'not-set)
  (flow-run
   (lambda (workers)
     (flow-put! ch 'fills-it)
     (guard (ex ((flow-error-timeout? ex) (set! outcome 'timeout)))
       (flow-monitor 0.02 (lambda () (flow-put! ch 'never))))
     (flow-stop)))
  (assert (eq? outcome 'timeout))
  ;; the cancelled putter left nothing behind
  (assert (null? (flow-channel-space ch)))
  (assert (eq? 'fills-it (flow-get-try ch 'EMPTY)))
  #t)

;; The saturation warning is edge-triggered: one line per episode, not
;; one per blocked put. Three putters pile up behind the same full
;; channel and produce exactly one warning, which names the channel --
;; the reason channels got names at all.
(define (~check-flow2-002/channel-full-warns-once)
  (define ch (make-flow-channel 'saturating 2))
  (flow-log-drain!)
  (flow-run
   (lambda (workers)
     (flow-put! ch 1)
     (flow-put! ch 2)
     (for-each (lambda (i)
                 (flow-spawn (lambda () (flow-put! ch (fx+ 10 i)))))
               '(1 2 3))
     (flow-sleep 0.02)
     (flow-stop)))
  (let ((warnings (filter (lambda (e) (and (pair? e) (eq? (car e) 'flow2)))
                          (map cdr (flow-log-drain!)))))
    (assert (= 1 (length warnings)))
    (assert (equal? '(flow2 channel-full saturating 2) (car warnings))))
  #t)

;; flow-write reports the count it actually wrote and does NOT loop
;; internally. The old shape resubmitted the remainder from inside the
;; completion handler, which made the write surface uncancellable, made
;; a flow-choice timeout unable to stop it, and copied the whole
;; remainder per partial write. This pins the contract that replaced it:
;; a positive count, a START offset that needs no copying, and #f on
;; failure -- the shape flow-write-at has always had.
(define (~check-flow2-006/write-reports-its-count)
  (define PORT 18248)
  (define first-count #f)
  (define rest-count #f)
  (define empty-count #f)
  (define echoed #f)
  (define payload (string->utf8 "0123456789"))
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let* ((client (flow-perform (flow-accept listen-fd)))
                 (data   (flow-perform (flow-read client))))
            (set! echoed (and (bytevector? data) (utf8->string data)))
            (loop-close client))))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                ;; a count, not #t
                (set! first-count (flow-perform (flow-write fd payload)))
                ;; START resumes a partial write with no copying; when
                ;; the first send took everything there is nothing left,
                ;; which the caller expresses as start = length
                (set! rest-count
                      (if (fx=? first-count (bytevector-length payload))
                          0
                          (flow-perform
                           (flow-write fd payload first-count))))
                ;; start = length is a legal index and a zero-byte
                ;; remainder: ready with count 0, not a failure --
                ;; res = 0 from an actual send still reads as one
                (set! empty-count
                      (flow-perform
                       (flow-write fd payload (bytevector-length payload))))
                (loop-close fd))))
          (loop-close listen-fd)
          (flow-stop))))))
  (assert (fixnum? first-count))
  (assert (fx>? first-count 0))
  (assert (fx=? (bytevector-length payload)
                (fx+ first-count rest-count)))
  (assert (eqv? 0 empty-count))
  (assert (equal? "0123456789" echoed))
  ;; an out-of-range start is a mistake at the call site, not a
  ;; surprise at completion time
  (assert (guard (ex (#t #t)) (flow-write 0 payload 999) #f))
  #t)

;; flow-run must not return until its workers are provably gone. It
;; used to signal the eventfd, close it, and null the global handle
;; with workers possibly still inside a task -- so a worker reaching
;; %flow-spawn-safe afterwards either found no pool and raised from
;; inside its own guard, or won the race and wrote eight bytes into
;; whatever the next loop-new or socket call had since been given that
;; fd number.
;;
;; The task here deliberately outlives flow-stop: it is submitted at the
;; root scope, so no nursery join waits for it, and the only thing that
;; can wait for it is the shutdown itself. FINISHED set at all is the
;; evidence: without the join, flow-run returns while the worker is
;; still asleep. The pool state itself is per-run now and unreachable
;; once flow-run returns, which is the point -- there is no global left
;; for this check to inspect, or for a straggler to corrupt.
(define (~check-flow2-005/shutdown-joins-the-worker-pool)
  (define finished #f)
  (flow-run
   (lambda (workers)
     (let ((worker (car workers))
           (reply (make-flow-channel 'reply 4)))
       (flow-submit! worker
                     (lambda ()
                       (sleep (make-time 'time-duration 40000000 0))
                       (set! finished #t))
                     reply)
       (flow-stop)))
   1)
  (assert finished)
  #t)

;; flow-submit! is a channel operation like flow-put!, so a dead scope
;; is observable through it too — the raise is how the sender learns of
;; its own death. It used to enqueue silently, which was doubly
;; useless: the worker skips a dead scope's task at dequeue anyway, so
;; the caller paid the put and the child count for work guaranteed
;; never to run. No worker is needed to prove the boundary: the
;; request channel is an ordinary channel.
(define (~check-flow2-005/submit-in-dead-scope-raises)
  (define outcome 'unset)
  (define requests (make-flow-channel 'requests))
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-cancelled? ex) (void)))
       (flow-nursery
        (lambda (scope)
          (flow-scope-cancel! scope)
          (set! outcome
                (guard (ex ((flow-error-cancelled? ex) 'cancelled))
                  (flow-submit! requests
                                (lambda () 'never)
                                (make-flow-channel 'resp))
                  'submitted)))))
     (flow-stop)))
  (assert (eq? outcome 'cancelled))
  ;; nothing was enqueued for the raise to strand
  (assert (= 0 (flow-channel-queue-length requests)))
  #t)

;; A straggler worker -- one that outlived its run's bounded shutdown
;; join -- must not corrupt the NEXT flow-run. The pool state used to
;; be global, so the straggler's eventual exit decremented the new
;; run's live count: the new shutdown undercounted, concluded all
;; workers had exited while its own was still inside a task, and
;; dismantled the pool under it -- flow-run returned early, and the
;; eventfd closed with a live writer holding the fd number. The pool
;; is per-run now, handed to workers as a closure, so a straggler can
;; only ever touch the run that created it.
;;
;; The differential: run 2's task takes 1.0s, and the run-1 straggler
;; exits ~0.55s into run 2. With shared globals run 2's shutdown
;; returned at the straggler's exit, before its own task finished;
;; with per-run pools it waits the full 1.0s. Slow by check standards
;; (~3s), and deliberately so -- the whole scenario IS the timing.
(define (~check-flow2-005/straggler-does-not-corrupt-the-next-run)
  (define straggler-done? #f)
  (define second-task-done? #f)
  (flow-log-drain!)
  ;; run 1: the task outlives the 2s join -> logged straggler
  (flow-run
   (lambda (workers)
     (flow-submit! (car workers)
                   (lambda ()
                     (sleep (make-time 'time-duration 600000000 2))
                     (set! straggler-done? #t))
                   (make-flow-channel 'resp))
     (flow-sleep 0.05)   ;; the worker has certainly dequeued by now
     (flow-stop))
   1)
  ;; flow-run returned with the worker still inside the task, and said so
  (assert (not straggler-done?))
  (let ((logged (filter (lambda (e)
                          (and (pair? e)
                               (eq? (cadr e) 'shutdown-workers-still-running)))
                        (map cdr (flow-log-drain!)))))
    (assert (= 1 (length logged))))
  ;; run 2, while the straggler is still alive and exits mid-run
  (flow-run
   (lambda (workers)
     (flow-submit! (car workers)
                   (lambda ()
                     (sleep (make-time 'time-duration 0 1))
                     (set! second-task-done? #t))
                   (make-flow-channel 'resp))
     (flow-sleep 0.05)
     (flow-stop))
   1)
  ;; run 2's shutdown joined ITS worker, not whatever count the
  ;; straggler's exit left behind
  (assert second-task-done?)
  ;; and by now the straggler has finished on its own leaked pool
  (assert straggler-done?)
  #t)

;; A scope owns the compute tasks submitted inside it, so its join must
;; wait for them. flow-submit! used to only TAG a task with the scope:
;; cancellation reached it, ownership did not, and a join could return
;; while a scope-tagged task was still running on a worker -- and that
;; task could still put to a channel afterwards.
;;
;; The worker sleeps on its own OS thread, so "did the join wait" is
;; decided by real elapsed time and not by loop scheduling order.
(define (~check-flow2-005/nursery-waits-for-its-compute-task)
  (define finished #f)
  (define at-join #f)
  (flow-run
   (lambda (workers)
     (let ((worker (car workers))
           (reply (make-flow-channel 'reply 4)))
       (flow-nursery
        (lambda (scope)
          (flow-submit! worker
                        (lambda ()
                          (sleep (make-time 'time-duration 50000000 0))
                          (set! finished #t))
                        reply)))
       ;; sampled the instant the nursery returned
       (set! at-join finished)
       (flow-stop)))
   1)
  (assert at-join)
  #t)

;; Cancellation must be observable through a channel operation on
;; EITHER thread. Both checks used to test only %worker-current?, so a
;; main-thread fiber in a cancelled scope could keep putting and
;; draining indefinitely as long as it never performed a suspending
;; event -- while the identical code on a worker raised at once. The
;; README's "channel operations check it implicitly" claimed the
;; universal version of this.
;;
;; Driven through flow-scope-cancel! rather than a deadline so the
;; scope is dead at a known point with nothing else in flight.
(define (~check-flow2-003/cancel-is-visible-to-non-suspending-ops)
  (define ch (make-flow-channel 'sym 8))
  (define put-raised #f)
  (define get-raised #f)
  (define before-cancel #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-cancelled? ex) (void)))
       (flow-nursery
        (lambda (scope)
          ;; while the scope is alive both work normally
          (flow-put! ch 'first)
          (set! before-cancel (flow-get-try ch 'EMPTY))
          (flow-scope-cancel! scope)
          ;; and once it is dead, neither may pretend otherwise
          (set! put-raised
                (guard (ex ((flow-error-cancelled? ex) #t)) (flow-put! ch 'second) #f))
          (set! get-raised
                (guard (ex ((flow-error-cancelled? ex) #t)) (flow-get-try ch 'EMPTY) #f)))))
     (flow-stop)))
  (assert (eq? 'first before-cancel))
  (assert put-raised)
  (assert get-raised)
  ;; the put that raised must not have enqueued anything
  (assert (eq? 'EMPTY (flow-get-try ch 'EMPTY)))
  #t)

;; A cancelled parent must not abandon its grandchildren. %scope-finish
;; performs the join under the PARENT scope on purpose, so an enclosing
;; cancellation reaches it -- but it used to raise on the spot with this
;; scope's own children still running. They were cancelled transitively,
;; yet nobody waited for them to finish, so fibers outlived the scope
;; that owned them, which is the one thing a nursery exists to prevent.
;;
;; The inner scope owns a compute task that outlasts the monitor's
;; deadline, so the two failures are separable: without the ownership
;; fix the task is not counted and the join does not happen at all;
;; without the drain fix it is counted but the join is abandoned
;; mid-flight. Either way the task is still running when the timeout
;; escapes, and at-raise is #f.
(define (~check-flow2-003/cancelled-parent-drains-grandchildren)
  (define finished #f)
  (define at-raise 'not-set)
  (define outcome 'not-set)
  (flow-run
   (lambda (workers)
     (let ((worker (car workers))
           (reply (make-flow-channel 'reply 4)))
       (guard (ex ((flow-error-timeout? ex)
                   (set! outcome 'timeout)
                   (set! at-raise finished)))
         (flow-monitor
          0.02
          (lambda ()
            (flow-nursery
             (lambda (inner)
               (flow-submit! worker
                             (lambda ()
                               (sleep (make-time 'time-duration 60000000 0))
                               (set! finished #t))
                             reply))))))
       (flow-stop)))
   1)
  (assert (eq? outcome 'timeout))
  (assert at-raise)
  #t)

;;------------------------------------------------------------
;; Nurseries
;;------------------------------------------------------------

(define (~check-flow2-003/nursery-join-waits-children)
  (define done '())
  (define after-nursery #f)
  (flow-run
   (lambda (workers)
     (flow-nursery
      (lambda (scope)
        (for-each (lambda (i)
                    (flow-spawn
                     (lambda ()
                       (flow-sleep 0.005)
                       (set! done (cons i done)))))
                  '(1 2 3))))
     ;; the join guarantees all three ran before the nursery returned
     (set! after-nursery (length done))
     (flow-stop)))
  (eqv? after-nursery 3))

(define (~check-flow2-003/nursery-child-raise-cancels-siblings)
  (define never (make-flow-channel))
  (define sibling-cancelled? #f)
  (define reraised #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((eq? ex 'boom) (set! reraised #t)))
       (flow-nursery
        (lambda (scope)
          ;; sibling parked forever on an empty channel: only the
          ;; scope's cancellation can resume it
          (flow-spawn
           (lambda ()
             (guard (ex ((flow-error-cancelled? ex)
                         (set! sibling-cancelled? #t)
                         (raise ex)))
               (flow-get! never))))
          (flow-spawn
           (lambda ()
             (flow-sleep 0.005)
             (raise 'boom))))))
     (flow-stop)))
  (and sibling-cancelled? reraised))

(define (~check-flow2-003/nursery-scope-cancel)
  (define never (make-flow-channel))
  (define outcome #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-cancelled? ex) (set! outcome 'cancelled)))
       (flow-nursery
        (lambda (scope)
          (flow-spawn (lambda () (flow-get! never)))
          (flow-spawn
           (lambda ()
             (flow-sleep 0.005)
             (flow-scope-cancel! scope))))))
     (flow-stop)))
  (eq? outcome 'cancelled))

;; Once the scope is dead, the next synchronization raises before
;; even polling — the fast-path check at flow-perform's entry.
(define (~check-flow2-003/nursery-perform-after-cancel-raises)
  (define ch (make-flow-channel))
  (define raised-inside? #f)
  (flow-run
   (lambda (workers)
     (flow-put! ch 'ready)  ;; even a ready value must not mask cancellation
     (guard (ex ((flow-error-cancelled? ex) (void)))
       (flow-nursery
        (lambda (scope)
          (flow-scope-cancel! scope)
          (guard (ex ((flow-error-cancelled? ex) (set! raised-inside? #t)))
            (flow-get! ch)))))
     (flow-stop)))
  raised-inside?)

;; Opening a nursery -- or a monitor -- inside a scope that is already
;; dead must raise, exactly as flow-perform does. The subscope link
;; lands AFTER %scope-fail!'s subscope walk, and the walk is
;; CAS-guarded so it never reruns: a scope created past that point was
;; invisible to the cancellation forever, and its body ran SHIELDED
;; under a permanently-open scope -- it could park on a channel nobody
;; writes and nothing could ever reach it. flow-monitor was worse
;; still: its child fiber spawned first, then the join/deadline race
;; raised on the dead parent BEFORE the deadline was armed, orphaning
;; the child with no deadline and no join.
(define (~check-flow2-003/nursery-in-dead-scope-raises)
  (define body-ran? #f)
  (define nursery-outcome 'unset)
  (define monitor-outcome 'unset)
  (define outer-raised? #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-cancelled? ex) (set! outer-raised? #t)))
       (flow-nursery
        (lambda (scope)
          (flow-scope-cancel! scope)
          (set! nursery-outcome
                (guard (ex ((flow-error-cancelled? ex) 'cancelled))
                  (flow-nursery
                   (lambda (sub)
                     (set! body-ran? #t)
                     (flow-sleep 0.01)))
                  'returned))
          (set! monitor-outcome
                (guard (ex ((flow-error-cancelled? ex) 'cancelled))
                  (flow-monitor 1.0 (lambda () (set! body-ran? #t)))
                  'returned)))))
     (flow-stop)))
  (assert (eq? nursery-outcome 'cancelled))
  (assert (eq? monitor-outcome 'cancelled))
  (assert (not body-ran?))
  ;; and the outer join still reports the cancellation as usual
  (assert outer-raised?)
  #t)

;; A raise from a base event's BLOCK procedure must reach the fiber,
;; and through it the scope -- exactly as a raise from the fiber's body
;; does. Before the fix, block procs ran inside loop-abort's thunk, on
;; the scheduler's stack with the prompt already unwound, so the raise
;; escaped to loop-apply's catch-all: the fiber died without
;; %scope-child-done!, the scope's child count never reached zero, and
;; the nursery's join parked forever. Case B below HUNG.
;;
;; Not synthetic. loop-get-sqe raises "submission queue full" past 256
;; queued ops in one tick, reachable from flow-timeout / flow-read /
;; flow-write / flow-open / flow-read-at / flow-write-at; and
;; loop-accept-block raises "concurrent accept on fd". Standalone
;; reproducer: checks/repro-flow2-block-raise.scm.
(define (~check-flow2-003/block-raise-reaches-the-scope)
  ;; never ready, so flow-perform must call block -- and block raises
  (define (bad-event)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume register-cancel!)
                 (error 'bad-event "raised from block"))))
  (define root-saw #f)
  (define nursery-saw #f)
  (flow-run
   (lambda (workers)
     ;; A: root scope -- flow-perform raises on the performing fiber
     (guard (ex (#t (set! root-saw #t)))
       (flow-perform (bad-event)))
     ;; B: inside a nursery -- the child's raise fails the scope and
     ;; re-raises at the join, instead of hanging it
     (guard (ex (#t (set! nursery-saw #t)))
       (flow-nursery
        (lambda (scope)
          (flow-spawn (lambda () (flow-perform (bad-event)))))))
     (flow-stop)))
  (assert root-saw)
  (assert nursery-saw)
  #t)

;; A waiter registered on a scope that is ALREADY dead must be woken
;; by the registration itself. %scope-fail! CASes the state and then
;; drains the waiters list, so anything consed on after that drain is
;; attached to a corpse -- and on a compute thread, which registers its
;; own waiter from its own thread, losing that race parks the worker
;; forever and shrinks the pool by one with no other symptom.
;;
;; Asserted deterministically against the internals rather than by
;; racing: the real interleaving needs the loop thread's CAS to land
;; inside a ~1us window on the worker, which took a 6000-round deadline
;; sweep to hit even once (checks/repro-flow2-scope-waiter-race.scm
;; does exactly that, and is kept for the end-to-end proof). What
;; belongs in `make check` is the invariant the fix establishes, and
;; that is checkable in microseconds.
(define (~check-flow2-003/waiter-on-dead-scope-is-woken)
  (define scope (%make-scope %root-scope))
  (define woken 'not-woken)
  ;; kill it first: the waiters list has already been drained
  (%scope-fail! scope 'cancelled)
  (%scope-add-waiter! scope (box 'waiting)
                      (lambda (value) (set! woken value) #t))
  (assert (eq? woken %flow-cancel-sentinel))
  ;; and the ordinary order still works: register, then cancel
  (let ((live (%make-scope %root-scope))
        (seen 'not-woken))
    (%scope-add-waiter! live (box 'waiting)
                        (lambda (value) (set! seen value) #t))
    (assert (eq? seen 'not-woken))
    (%scope-fail! live 'cancelled)
    (assert (eq? seen %flow-cancel-sentinel)))
  #t)

;;------------------------------------------------------------
;; Monitor
;;------------------------------------------------------------

(define (~check-flow2-004/monitor-in-time)
  (define result #f)
  (flow-run
   (lambda (workers)
     (set! result (flow-monitor 5.0
                                (lambda ()
                                  (flow-sleep 0.005)
                                  'done)))
     (flow-stop)))
  (eq? result 'done))

(define (~check-flow2-004/monitor-deadline)
  (define never (make-flow-channel))
  (define outcome #f)
  (define child-cancelled? #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-timeout? ex) (set! outcome 'timeout)))
       (flow-monitor 0.01
                     (lambda ()
                       ;; a nested spawn, cancelled transitively
                       (flow-spawn
                        (lambda ()
                          (guard (ex ((flow-error-cancelled? ex)
                                      (set! child-cancelled? #t)
                                      (raise ex)))
                            (flow-get! never))))
                       (flow-get! never))))
     (flow-stop)))
  (and (eq? outcome 'timeout) child-cancelled?))

;;------------------------------------------------------------
;; Compute threads
;;------------------------------------------------------------

;; The monitor-side twin of cancelled-parent-drains-grandchildren: the
;; join/deadline race runs under the PARENT scope so an enclosing
;; cancellation reaches it, but when it did, the raise used to
;; propagate straight out of flow-monitor — no %scope-fail!, no
;; %scope-finish, no drain — so the monitor's children were cancelled
;; transitively yet nobody waited for them, and they outlived the
;; monitor call. The child here is a compute task whose completion is
;; timestamped by a flag: the fiber that called flow-monitor must
;; observe that flag already set at the moment the interruption passes
;; through it.
(define (~check-flow2-004/monitor-interrupted-by-parent-drains-children)
  (define task-finished? #f)
  (define seen-at-monitor-exit 'unset)
  (define outer-raised? #f)
  (flow-run
   (lambda (workers)
     (guard (ex (#t (set! outer-raised? #t)))
       (flow-nursery
        (lambda (outer)
          (flow-spawn
           (lambda ()
             (guard (ex (#t (set! seen-at-monitor-exit task-finished?)
                            (raise ex)))
               (flow-monitor
                5.0
                (lambda ()
                  ;; owned by the monitor's scope; the worker sleeps
                  ;; past the sibling's raise, so the drain has
                  ;; something real to wait for
                  (flow-submit! (car workers)
                                (lambda ()
                                  (sleep (make-time 'time-duration
                                                    80000000 0))
                                  (set! task-finished? #t))
                                (make-flow-channel 'resp))
                  ;; park the monitor's own fiber too, so the join
                  ;; cannot win before the interruption arrives
                  (flow-sleep 5.0))))))
          (flow-spawn
           (lambda ()
             (flow-sleep 0.02)
             (error 'sibling "boom"))))))
     (flow-stop))
   1)
  (assert outer-raised?)
  (assert (eq? seen-at-monitor-exit #t))
  #t)

(define (~check-flow2-005/worker-task-replies)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda () (flow-put! response 'pong))
                     response)
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (eq? result 'pong))

;; The always-a-reply guarantee: a raising task cannot hang its
;; submitter — the guard wraps the raise as a compute <flow-error>
;; carrying the original in its cause.
(define (~check-flow2-005/worker-raise-becomes-compute-error)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda () (raise 'kaboom))
                     response)
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (and (flow-error-compute? result)
       (eq? 'kaboom (flow-error-cause result))
       ;; the reply names the worker it came from -- its request
       ;; channel's name -- so a shared response channel still says
       ;; WHERE the task failed
       (equal? '((worker . 0)) (flow-error-irritants result))))

;; Workers have no I/O verbs: performing a ring event raises
;; wrong-thread on the compute thread, catchable by the task.
(define (~check-flow2-005/worker-ring-event-raises-wrong-thread)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda ()
                       (guard (ex ((flow-error-wrong-thread? ex)
                                   (flow-put! response 'wrong-thread)))
                         (flow-sleep 0.01)
                         (flow-put! response 'slept)))
                     response)
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (eq? result 'wrong-thread))

;; A monitor's deadline reaches a task parked on a channel: the get
;; raises cancelled on the compute thread, the framework drops the
;; unwound task without a reply, and the worker survives to serve
;; the next submission.
(define (~check-flow2-005/worker-cancelled-along-monitor)
  (define timed-out? #f)
  (define alive #f)
  (flow-run
   (lambda (workers)
     (guard (ex ((flow-error-timeout? ex) (set! timed-out? #t)))
       (flow-monitor 0.01
                     (lambda ()
                       (let ((up (make-flow-channel))
                             (down (make-flow-channel)))
                         (flow-submit! (car workers)
                                       (lambda () (flow-get! down))
                                       up)
                         (flow-get! up)))))
     ;; same worker, fresh scope: still serving
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda () (flow-put! response 'alive))
                     response)
       (set! alive (flow-get! response)))
     (flow-stop))
   1)
  (and timed-out? (eq? alive 'alive)))

;; The verb-less I/O protocol from the design document, in miniature:
;; the task requests work over its response channel, the submitting
;; fiber serves each request in a fiber of its own, results return on
;; the task's downlink.
(define (~check-flow2-005/worker-io-protocol-roundtrip)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((up (make-flow-channel))
           (down (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda ()
                       (flow-put! up (list 'double 21))
                       (let ((doubled (flow-get! down)))
                         (flow-put! up (list 'done doubled))))
                     up)
       (let serve ()
         (let ((msg (flow-get! up)))
           (cond
            ((flow-error? msg) (set! result msg))
            ((eq? (car msg) 'double)
             (flow-spawn
              (lambda () (flow-put! down (* 2 (cadr msg)))))
             (serve))
            ((eq? (car msg) 'done)
             (set! result (cadr msg))))))
       (flow-stop)))
   1)
  (eqv? result 42))

;; resume-from's contract -- the losers' cancels land before the
;; resumed fiber runs -- must hold when a WORKER completes the
;; rendezvous, not only when the resume happens on-loop. The
;; cross-thread path goes through %cross-thread-spawns, which drains
;; newest-first; spawning that list without reversing it inverted the
;; order, so a fiber that won a worker's put against a losing
;; flow-accept re-accepted before the cancel had freed the multishot's
;; handler slot and raised "concurrent accept on fd". The probe's
;; cancel sets a flag; the fiber reads it as its first act after the
;; resume, so this fails on the inversion itself rather than on any
;; particular resource the cancel happens to free.
(define (~check-flow2-005/worker-resume-runs-cancels-first)
  (define registered? #f)
  (define cancel-ran? #f)
  (define cancel-ran-at-resume 'unset)
  (flow-run
   (lambda (workers)
     (let ((ch (make-flow-channel 'ctrl))
           (resp (make-flow-channel 'resp))
           (probe (make-flow
                   (lambda (x) x)
                   (lambda () #f)
                   (lambda (state resume register-cancel!)
                     (set! registered? #t)
                     (register-cancel!
                      (lambda () (set! cancel-ran? #t)))))))
       ;; the worker sleeps so the fiber is PARKED on the choice --
       ;; a put that lands before the park is taken at poll time and
       ;; never exercises the resume path at all
       (flow-submit! (car workers)
                     (lambda ()
                       (sleep (make-time 'time-duration 50000000 0))
                       (flow-put! ch 'msg))
                     resp)
       (let ((v (flow-perform (flow-choice probe (flow-get ch)))))
         (assert (eq? v 'msg))
         ;; first act after the resume: the loser's cancel already ran
         (set! cancel-ran-at-resume cancel-ran?))
       (flow-stop)))
   1)
  (assert registered?)
  (assert (eq? cancel-ran-at-resume #t))
  #t)

;;------------------------------------------------------------
;; Block-and-wait machinery
;;------------------------------------------------------------
;;
;; Ported 2026-08-17 from (letloop flow)'s ~check-flow-011 series,
;; which the fork had also dropped. These cover flow-block-and-wait-on-
;; loop itself -- synchronous wins during registration, a raising cancel
;; thunk, and which cancels fire -- i.e. exactly the procedure finding 1
;; of the review lives in.
;;
;; They deliberately drive the loop with BOUNDED loop-run-once ticks
;; rather than flow-run, keeping flow's rationale verbatim: a buggy
;; build must FAIL these rather than hang `make check`. That also means
;; they run outside flow-run, which never gets to reset %scope-current
;; -- so each sets it explicitly, the way flow-run does, rather than
;; inheriting whatever scope the previous check happened to leave in
;; that global.

;; A base that resumes INLINE, during the registration for-each, wins
;; before the bases after it have registered their cancels. The cancel
;; list is therefore unboxed inside a spawned thunk rather than at
;; resume time; snapshotting it at resume would fire an incomplete list
;; and leave the later base armed forever.
(define (~check-flow2-011/sync-resume-runs-later-cancels)
  (define cancelled #f)
  (define result #f)
  (define sync (make-flow (lambda (x) x)
                          (lambda () #f)        ;; try: not ready
                          (lambda (state resume register-cancel!)
                            (resume 'sync))))   ;; resume inline, mid-registration
  (define parked (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (register-cancel!
                               (lambda () (set! cancelled #t))))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice sync parked)))))
  (let tick ((n 0))
    (when (fx<? n 4)
      (loop-run-once)
      (tick (fx+ n 1))))
  (and (eq? result 'sync) cancelled))

;; A cancel thunk that raises -- loop-get-sqe does exactly that on a
;; full submission queue -- must not take the winning continuation down
;; with it: the state box has already CASed to 'synched, so if k is lost
;; here no other base can ever resume the fiber and it is gone for good,
;; silently. The raise itself is reported by loop-apply's guard, which
;; is fine; what this pins down is that the fiber still gets its value.
(define (~check-flow2-011/raising-cancel-does-not-lose-fiber)
  (define result #f)
  (define winner (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (loop-spawn (lambda () (resume 'won))))))
  (define raising (make-flow (lambda (x) x)
                             (lambda () #f)
                             (lambda (state resume register-cancel!)
                               (register-cancel!
                                (lambda ()
                                  (error 'raising-cancel "boom"))))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice winner raising)))))
  (let tick ((n 0))
    (when (fx<? n 6)
      (loop-run-once)
      (tick (fx+ n 1))))
  (eq? result 'won))

;; The winner of a choice must not fire its OWN cancel: its operation
;; already completed, so the cancel SQE it would prep is a guaranteed
;; no-op the kernel answers with -ENOENT -- one wasted SQE + CQE round
;; trip per completed operation, on the hottest path this bookkeeping
;; has. Losers' cancels must of course still all fire.
(define (~check-flow2-011/winner-own-cancel-not-fired)
  (define winner-cancelled #f)
  (define loser-cancelled #f)
  (define result #f)
  (define winner (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (register-cancel!
                               (lambda () (set! winner-cancelled #t)))
                              (loop-spawn (lambda () (resume 'won))))))
  (define loser (make-flow (lambda (x) x)
                           (lambda () #f)
                           (lambda (state resume register-cancel!)
                             (register-cancel!
                              (lambda () (set! loser-cancelled #t))))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice winner loser)))))
  (let tick ((n 0))
    (when (fx<? n 6)
      (loop-run-once)
      (tick (fx+ n 1))))
  (and (eq? result 'won)
       loser-cancelled
       (not winner-cancelled)))

;; The two dropped checks above, composed -- and the branch finding 1's
;; fix introduced. An earlier base wins synchronously during
;; registration, and a LATER base's block proc then raises. The fiber is
;; already committed to the winner's value, so the raise has nowhere to
;; go: the fix reports it on stderr rather than swallowing it, and must
;; not disturb the winner. Asserted here: the fiber still gets 'sync,
;; the later base's own cancel still fires, and nothing hangs.
(define (~check-flow2-011/raise-after-sync-win-keeps-winner)
  (define cancelled #f)
  (define result 'not-set)
  (define sync (make-flow (lambda (x) x)
                          (lambda () #f)
                          (lambda (state resume register-cancel!)
                            (resume 'sync))))
  (define raising (make-flow (lambda (x) x)
                             (lambda () #f)
                             (lambda (state resume register-cancel!)
                               (register-cancel!
                                (lambda () (set! cancelled #t)))
                               (error 'raising-block "boom"))))
  (loop-new)
  (set! %scope-current %root-scope)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice sync raising)))))
  (let tick ((n 0))
    (when (fx<? n 6)
      (loop-run-once)
      (tick (fx+ n 1))))
  (and (eq? result 'sync) cancelled))

;;------------------------------------------------------------
;; Network and file I/O
;;------------------------------------------------------------
;;
;; Ported 2026-08-17 from (letloop flow)'s ~check-flow-006/* and
;; ~check-flow-009/*, which the flow2 fork dropped along with the other
;; fd- and ring-touching checks (flow ships 40 checks, flow2 shipped
;; 21, and all 11 I/O ones were on the missing side). The numbering is
;; kept deliberately -- 006 for sockets, 009 for files -- so each check
;; here is traceable to the flow original it came from.
;;
;; Two adaptations, no semantic changes: they drive the loop through
;; flow-run / flow-spawn / flow-stop rather than loop-new / loop-spawn /
;; loop-run, per this file's header, and they use ports 1824x + 10 so a
;; single `make check` process running both suites never contends for a
;; listening address.

;; Under /tmp/letloop so `make clean` sweeps anything a crashed check
;; leaves behind; each check also deletes its own file on the way out.
(define %flow2-check-directory "/tmp/letloop")

(define (flow2-check-path name)
  (unless (file-exists? %flow2-check-directory)
    (mkdir %flow2-check-directory))
  (string-append %flow2-check-directory "/" name))

(define (flow2-check-remove! path)
  (when (file-exists? path)
    (delete-file path)))

;; Deterministic filler, so a mis-offset read is caught by content and
;; not merely by length.
(define (flow2-check-bytes size)
  (let ((bv (make-bytevector size)))
    (let loop ((i 0))
      (if (fx=? i size)
          bv
          (begin (bytevector-u8-set! bv i (fxmod (fx* i 7) 251))
                 (loop (fx+ i 1)))))))

(define (flow2-check-concatenate bvs)
  (let ((out (make-bytevector (apply + (map bytevector-length bvs)))))
    (let loop ((bvs bvs) (offset 0))
      (if (null? bvs)
          out
          (let ((n (bytevector-length (car bvs))))
            (bytevector-copy! (car bvs) 0 out offset n)
            (loop (cdr bvs) (fx+ offset n)))))))

;; flow-write-at reports what it actually wrote rather than looping, so
;; a caller that wants "all of it" writes the loop itself -- as here.
(define (flow2-check-write-all fd offset bv)
  (let loop ((offset offset) (bv bv))
    (let ((n (flow-perform (flow-write-at fd offset bv))))
      (cond
       ((not n) #f)
       ((fx=? n (bytevector-length bv)) #t)
       (else (loop (fx+ offset n) (subbytevector bv n)))))))

(define (flow2-check-create! path bv)
  (let ((fd (flow-perform
             (flow-open path (fxior O-WRONLY O-CREAT O-TRUNC) #o600))))
    (and fd
         (let ((ok (flow2-check-write-all fd 0 bv)))
           (flow-perform (flow-close fd))
           ok))))

;; Real loopback TCP: a listener accepts via flow-accept, echoes one
;; message back via flow-read/flow-write; the peer connects, sends, and
;; reads the echo back via flow-write/flow-read too, so both directions
;; of both events run over a real socket pair.
(define (~check-flow2-006/echo-pair)
  (define PORT 18244)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let* ((client (flow-perform (flow-accept listen-fd)))
                 (data   (flow-perform (flow-read client))))
            (flow-write-all! client data)
            (loop-close client))))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                (flow-write-all! fd (string->utf8 "hello"))
                (set! result (flow-perform (flow-read fd)))
                (loop-close fd))))
          (loop-close listen-fd)
          (flow-stop))))))
  (equal? result (string->utf8 "hello")))

;; A read racing a short timeout on a silent socket must resolve via
;; the timeout (not hang), and -- the actual point of this check -- the
;; fd must still be usable afterward: a fresh flow-read on the same fd
;; must see the client's message once it actually arrives, proving the
;; cancelled/lost read did not consume or corrupt the connection.
;;
;; This is the check whose accept-side analogue flow2 still lacks: see
;; checks/repro-flow2-accept-cancel.scm, where a cancelled flow-accept
;; leaves its handler registered and poisons the listening fd. flow-read
;; passes here because it calls register-cancel! and flow-accept does
;; not.
(define (~check-flow2-006/read-or-timeout-leaves-fd-usable)
  (define PORT 18245)
  (define timed-out #f)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let ((client (flow-perform (flow-accept listen-fd))))
            (set! timed-out
                  (eq? (flow-perform
                        (flow-choice (flow-read client) (flow-timeout 0.05)))
                       (void)))
            (set! result (flow-perform (flow-read client)))
            (loop-close client)
            (loop-close listen-fd)
            (flow-stop))))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                ;; stay silent well past the server's 50ms
                ;; read-or-timeout before finally sending
                (flow-sleep 0.2)
                (flow-write-all! fd (string->utf8 "late"))
                (loop-close fd)))))))))
  (and timed-out
       (equal? result (string->utf8 "late"))))

;; The accept-side counterpart of read-or-timeout-leaves-fd-usable, and
;; the check flow never had either. A cancelled flow-accept used to
;; leave its handler registered against the multishot's id, so the next
;; flow-accept on that listener raised "concurrent accept on fd" --
;; permanently, for as long as no client arrived to clear the slot.
;; What is asserted is the part that matters: after the cancellation the
;; listener still ACCEPTS, and the client that connects afterwards is
;; delivered intact. Reproducer: checks/repro-flow2-accept-cancel.scm.
(define (~check-flow2-006/accept-cancel-leaves-listener-usable)
  (define PORT 18247)
  (define timed-out #f)
  (define accepted #f)
  (define received #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          ;; The whole body is guarded so a regression FAILS this check
          ;; rather than hanging the suite: an unguarded raise here
          ;; would kill the fiber before it reaches flow-stop, and
          ;; flow-run would never return.
          (guard (ex (#t (set! accepted 'raised)))
            ;; nothing is connecting yet, so the monitor's deadline
            ;; cancels this accept
            (set! timed-out
                  (guard (ex ((flow-error-timeout? ex) #t))
                    (flow-monitor 0.05
                                  (lambda ()
                                    (flow-perform (flow-accept listen-fd))))
                    #f))
            ;; the listener must still be usable
            (let ((client (flow-perform (flow-accept listen-fd))))
              (set! accepted (fixnum? client))
              (set! received (flow-perform (flow-read client)))
              (loop-close client)))
          (loop-close listen-fd)
          (flow-stop)))
       (flow-spawn
        (lambda ()
          ;; connect only after the first accept has been cancelled
          (flow-sleep 0.15)
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                (flow-write-all! fd (string->utf8 "after-cancel"))
                (flow-sleep 0.05)
                (loop-close fd)))))))))
  (and timed-out
       (eq? accepted #t)
       (equal? received (string->utf8 "after-cancel"))))

;; A per-connection request/echo loop that races each read against an
;; idle timeout and closes gracefully once the peer goes silent -- the
;; realistic consumer shape, and the one http/server.body.scm's dispatch
;; race now uses on flow (see fbacb46).
(define (~check-flow2-006/request-loop-idle-timeout)
  (define PORT 18246)
  (define echoed '())
  (define closed-on-timeout #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let ((client (flow-perform (flow-accept listen-fd))))
            (let request-loop ()
              (let ((result (flow-perform
                             (flow-choice (flow-read client)
                                          (flow-timeout 0.1)))))
                (cond
                 ((eq? result (void))     ;; idle timeout won
                  (set! closed-on-timeout #t)
                  (loop-close client))
                 ((eq? result #t)         ;; peer EOF
                  (loop-close client))
                 (else
                  (set! echoed (cons result echoed))
                  (flow-write-all! client result)
                  (request-loop)))))
            (loop-close listen-fd)
            (flow-stop))))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                (flow-write-all! fd (string->utf8 "one"))
                (flow-perform (flow-read fd))
                (flow-write-all! fd (string->utf8 "two"))
                (flow-perform (flow-read fd))
                ;; go silent well past the server's 100ms per-read idle
                ;; timeout before closing
                (flow-sleep 0.3)
                (loop-close fd)))))))))
  (and (equal? (reverse echoed)
               (list (string->utf8 "one") (string->utf8 "two")))
       closed-on-timeout))

;; Round trip through a real file: create + write + close, then reopen
;; read-only and read the whole thing back in one call.
(define (~check-flow2-009/file-write-read-roundtrip)
  (define path (flow2-check-path "flow2-009-roundtrip.bin"))
  (define payload (string->utf8 "the quick brown fox jumps over the lazy dog"))
  (define written #f)
  (define result #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (let ((fd (flow-perform
                (flow-open path (fxior O-WRONLY O-CREAT O-TRUNC) #o600))))
       (set! written (flow-perform (flow-write-at fd 0 payload)))
       (flow-perform (flow-close fd)))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (set! result (flow-perform (flow-read-at fd 0 65536)))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (and (eqv? written (bytevector-length payload))
       (equal? result payload)))

;; A file deliberately larger than the chunk size and not a multiple of
;; it: the loop must see two full chunks, one short chunk, and then
;; 'eof -- the caller tracking its own offset the whole way, since these
;; primitives keep no cursor.
(define (~check-flow2-009/chunked-read-until-eof)
  (define path (flow2-check-path "flow2-009-chunked.bin"))
  (define chunk 4096)
  (define payload (flow2-check-bytes 10000))
  (define created #f)
  (define pieces '())
  (define saw-eof #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (let read-loop ((offset 0))
         (let ((piece (flow-perform (flow-read-at fd offset chunk))))
           (cond
            ((eq? piece 'eof) (set! saw-eof #t))
            ((not piece) (void))     ;; error: fall through, check fails
            (else
             (set! pieces (cons piece pieces))
             (read-loop (fx+ offset (bytevector-length piece)))))))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (let ((pieces (reverse pieces)))
    (and created
         saw-eof
         (fx=? (length pieces) 3)                    ;; 4096 + 4096 + 1808
         (fx=? (bytevector-length (list-ref pieces 2)) 1808)
         (equal? (flow2-check-concatenate pieces) payload))))

;; Neither the write nor the read starts at 0: the marker must land at
;; exactly OFFSET (the head of the file untouched), and reading it back
;; from OFFSET must return it -- an offset silently ignored would fail
;; both halves.
(define (~check-flow2-009/nonzero-offset)
  (define path (flow2-check-path "flow2-009-offset.bin"))
  (define offset 4000)
  (define payload (flow2-check-bytes 8192))
  (define marker (string->utf8 "MARKER-AT-4000"))
  (define created #f)
  (define patched #f)
  (define read-back #f)
  (define head #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDWR 0))))
       (set! patched (flow-perform (flow-write-at fd offset marker)))
       (set! read-back (flow-perform
                        (flow-read-at fd offset (bytevector-length marker))))
       (set! head (flow-perform (flow-read-at fd 0 16)))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (and created
       (eqv? patched (bytevector-length marker))
       (equal? read-back marker)
       (equal? head (subbytevector payload 0 16))))

;; The file-fd counterpart of the socket check above. A regular-file
;; read cannot be made to hang the way a silent socket can, so which
;; base wins is genuinely racy here (a 0-second timeout against an
;; already-satisfiable read) and neither outcome is asserted; what is
;; asserted is the part that matters -- after the choice resolves,
;; whichever way it went, a plain flow-read-at on the same fd still
;; returns the right bytes, so a losing/cancelled read leaves neither
;; the fd nor the loop's handler table in a half-submitted state.
(define (~check-flow2-009/read-or-timeout-leaves-fd-usable)
  (define path (flow2-check-path "flow2-009-choice.bin"))
  (define payload (flow2-check-bytes 512))
  (define created #f)
  (define slow #f)
  (define racy #f)
  (define after #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       ;; a read that cannot lose: 1s is forever next to a 512-byte
       ;; read off the page cache
       (set! slow (flow-perform
                   (flow-choice (flow-read-at fd 0 512) (flow-timeout 1.0))))
       ;; a read that may well lose
       (set! racy (flow-perform
                   (flow-choice (flow-read-at fd 0 512) (flow-timeout 0.0))))
       (set! after (flow-perform (flow-read-at fd 0 512)))
       (flow-perform (flow-close fd)))
     (flow-stop)))
  (flow2-check-remove! path)
  (and created
       (equal? slow payload)
       (or (equal? racy payload) (eq? racy (void)))
       (equal? after payload)))

;; Opening a missing path without O-CREAT must yield #f -- the same
;; shape flow-read/flow-write use for failure -- rather than hanging or
;; handing back a negative "fd" that would then be used as one.
(define (~check-flow2-009/open-nonexistent-fails)
  (define path (flow2-check-path "flow2-009-does-not-exist.bin"))
  (define result 'not-set)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! result (flow-perform (flow-open path O-RDONLY 0)))
     (flow-stop)))
  (eq? result #f))

;; flow-open on the losing side of a choice: the loser-with-success
;; path in flow-open's completion handler must close the fd nobody now
;; owns (detected via resume's #f "did I win" return) rather than leak
;; it. Which base wins each round is genuinely racy (a 0-second timeout
;; against a page-cache openat), so run many rounds and assert the
;; invariant that holds either way: the process's open-fd count is back
;; at its baseline once the dust settles -- a leaked orphan would grow
;; it by one per round the timeout won.
;;
;; flow-open is the ONE place flow2 kept this careful resume-returns-#f
;; handling (flow2.scm:857); this is the check that keeps it honest.
(define (~check-flow2-009/open-loses-choice-no-fd-leak)
  (define path (flow2-check-path "flow2-009-open-choice.bin"))
  (define rounds 50)
  (define failures 0)
  (define baseline #f)
  (define final #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (flow2-check-create! path (flow2-check-bytes 64))
     (set! baseline (length (directory-list "/proc/self/fd")))
     (let round ((n 0))
       (unless (fx=? n rounds)
         (let ((r (flow-perform
                   (flow-choice (flow-open path O-RDONLY 0)
                                (flow-timeout 0.0)))))
           (cond
            ((fixnum? r) (flow-perform (flow-close r)))  ;; open won: ours to close
            ((eq? r (void)) (void))                      ;; timeout won: orphan path
            (else (set! failures (fx+ failures 1)))))
         (round (fx+ n 1))))
     ;; give straggler orphan-close CQEs from the last rounds a tick or
     ;; two to land before counting
     (flow-sleep 0.05)
     (set! final (length (directory-list "/proc/self/fd")))
     (flow-stop)))
  (flow2-check-remove! path)
  (and (fxzero? failures)
       (fixnum? baseline)
       (eqv? final baseline)))

;; flow-close composed under flow-choice: per its committed-at-block
;; caveat, once the choice reaches the block phase the close happens
;; whichever base wins -- so afterward the fd must actually be closed,
;; and a probe read on it must yield #f (EBADF), never data. Nothing
;; opens another fd between the close and the probe, so the descriptor
;; number cannot have been reused out from under the test.
(define (~check-flow2-009/close-under-choice-fd-actually-closed)
  (define path (flow2-check-path "flow2-009-close-choice.bin"))
  (define created #f)
  (define chosen 'not-set)
  (define after 'not-set)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path (flow2-check-bytes 64)))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (set! chosen (flow-perform
                     (flow-choice (flow-close fd) (flow-timeout 1.0))))
       ;; in the unlikely event the timeout won, the committed close's
       ;; CQE still needs a tick to land before the probe
       (flow-sleep 0.02)
       (set! after (flow-perform (flow-read-at fd 0 16))))
     (flow-stop)))
  (flow2-check-remove! path)
  (and created
       (or (eqv? chosen 0) (eq? chosen (void)))
       (eq? after #f)))

;; flow-close while another fiber's flow-read-at is parked on the same
;; fd, both submitted in the same tick: exercises loop-close-block's
;; IORING_OP_ASYNC_CANCEL(CANCEL_ALL) actually matching an in-flight
;; file op. The assertions are liveness and shape: the reader fiber
;; resumes (not stranded) with either the payload or #f, and the close
;; itself succeeds.
(define (~check-flow2-009/close-while-read-in-flight)
  (define path (flow2-check-path "flow2-009-close-inflight.bin"))
  (define payload (flow2-check-bytes 512))
  (define created #f)
  (define read-result 'not-set)
  (define read-done #f)
  (define close-result 'not-set)
  (define close-done #f)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     (set! created (flow2-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       ;; spawn is LIFO within a tick: spawn the closer first so the
       ;; reader's block runs first next tick and its SQE is already
       ;; prepped (handler parked) when loop-close-block preps the
       ;; cancel + close right after it.
       (flow-spawn
        (lambda ()
          (set! close-result (flow-perform (flow-close fd)))
          (set! close-done #t)))
       (flow-spawn
        (lambda ()
          (set! read-result (flow-perform (flow-read-at fd 0 512)))
          (set! read-done #t)))
       (let wait ((n 0))
         (flow-sleep 0.01)
         (if (or (and read-done close-done) (fx>? n 500))
             (flow-stop)
             (wait (fx+ n 1)))))))
  (flow2-check-remove! path)
  (and created
       read-done
       close-done
       (eqv? close-result 0)
       (or (equal? read-result payload) (eq? read-result #f))))

;; F_GETFD on a closed descriptor fails, which is the only way from
;; inside the process to tell "the close was issued" from "the fiber
;; unwound past it". Cheap enough to be a probe rather than a helper
;; the rest of the file uses.
(define %flow2-check-fcntl (foreign-procedure "fcntl" (int int) int))
(define (flow2-check-fd-open? fd) (fx>=? (%flow2-check-fcntl fd 1) 0))

;; Cancellation is delivered by RAISING at a suspension point, so the
;; handler that releases an fd is reached by the very raise it exists
;; to clean up after -- that is the shape the design points at as the
;; one that closes descriptors. But flow-perform's dead-scope test used
;; to raise cancelled a second time, before the close SQE was ever
;; prepped, so the cleanup never touched the ring and the fd leaked on
;; exactly that path. Verified to fail before %bases-cancel-exempt?:
;; the close raised cancelled and F_GETFD still succeeded afterwards.
(define (~check-flow2-009/close-in-a-dead-scope-still-closes)
  (define path (flow2-check-path "flow2-009-close-dead-scope.bin"))
  (define fd #f)
  (define close-outcome 'never-ran)
  (define still-open 'unknown)
  (flow2-check-remove! path)
  (flow-run
   (lambda (workers)
     ;; the nursery re-raises the sibling's boom; this check is about
     ;; what the cancelled child managed to do on its way out
     (guard (ex (#t (void)))
       (flow-nursery
        (lambda (scope)
          (flow-spawn
           (lambda ()
             (set! fd (flow-perform
                       (flow-open path
                                  (fxior O-WRONLY O-CREAT O-TRUNC)
                                  #o600)))
             (guard (ex ((flow-error-cancelled? ex)
                         (set! close-outcome
                               (guard (ex2 (#t (list 'raised
                                                     (and (flow-error? ex2)
                                                          (flow-error-symbol ex2)))))
                                 (flow-perform (flow-close fd))))
                         (raise ex)))
               (flow-sleep 10))))
          (flow-spawn (lambda () (flow-sleep 0.05) (raise 'boom))))))
     ;; the close was issued by a fiber that is unwinding, so give its
     ;; completion a few ticks to land before probing the descriptor
     (flow-sleep 0.1)
     (set! still-open (flow2-check-fd-open? fd))
     (flow-stop)))
  (flow2-check-remove! path)
  (assert (fixnum? fd))
  ;; the cleanup reached the ring rather than being cancelled again
  (assert (eqv? 0 close-outcome))
  ;; and the descriptor really is gone
  (assert (not still-open))
  #t)

;; The README's "Fan out, gather, and never hang" pattern, transcribed.
;; BOUND #f is the naive spelling that leaves the channel at the
;; default; anything else sizes it to the fan-out, which is what the
;; pattern now shows.
(define (flow2-check-fan-out n bound)
  (let ((replies (if bound
                     (make-flow-channel 'replies bound)
                     (make-flow-channel 'replies))))
    (flow-nursery
     (lambda (scope)
       (for-each (lambda (i)
                   (flow-spawn (lambda () (flow-put! replies i))))
                 (iota n))))
    (let loop ((out '()))
      (let ((r (flow-get-try replies #f)))
        (if r (loop (cons r out)) out)))))

;; Gather-after-join and a bound smaller than the fan-out are
;; incompatible, and the failure is silent: the put that fills the
;; channel parks waiting for room, the only drainer runs after the
;; join, and the join waits for the parked putter. Nothing raises --
;; only a monitor turns it into something visible.
;;
;; Both halves are pinned here, because the rule is only worth its
;; space in the README if the naive shape really does hang: the sized
;; channel completes past the default bound, the default-bound one
;; times out at the same size.
(define (~check-flow2-003/gather-after-join-scales-past-the-default-bound)
  (define sized 'not-set)
  (define naive 'not-set)
  (assert (fx>? 50 (flow-channel-bound (make-flow-channel))))
  (flow-run
   (lambda (workers)
     (set! sized
           (guard (ex ((flow-error? ex) (list 'raised (flow-error-symbol ex))))
             (length (flow-monitor 2.0
                                   (lambda () (flow2-check-fan-out 50 50))))))
     (set! naive
           (guard (ex ((flow-error? ex) (list 'raised (flow-error-symbol ex))))
             (length (flow-monitor 0.4
                                   (lambda () (flow2-check-fan-out 50 #f))))))
     (flow-stop)))
  (assert (eqv? 50 sized))
  (assert (equal? '(raised timeout) naive))
  #t)

;; Third adverse pass, finding 3. A recv and the base that beat it can
;; complete in the same tick -- the loop drains the completion queue in
;; CQ order, so the timeout's handler wins the CAS and the recv's
;; handler then finds its resume returning #f. Before the recv backlog
;; those bytes were simply dropped, and the kernel had already taken
;; them off the socket, so a second read on the same fd saw nothing:
;; a truncated request with no error anywhere.
;;
;; Forcing the race needs the loop held busy across the window, which is
;; what the spin does: the peer fiber never yields between the write and
;; the deadline, so both CQEs are waiting together when the loop finally
;; drains. Reproducer: checks/repro-flow2-third-pass.scm.
(define %flow2-check-write2
  (foreign-procedure "write" (int u8* size_t) ssize_t))

(define (flow2-check-spin-until ms)
  (let spin () (when (< (real-time) ms) (spin))))

(define (~check-flow2-006/read-losing-a-same-tick-race-keeps-its-bytes)
  (define PORT 18251)
  (define payload (string->utf8 "payload"))
  (define first-race 'not-set)
  (define second-read 'not-set)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (guard (ex (#t (set! second-read 'raised)))
            (let ((client (flow-perform (flow-accept listen-fd))))
              (set! first-race
                    (flow-perform
                     (flow-choice
                      (flow-wrap (flow-read client) (lambda (x) (list 'read x)))
                      (flow-wrap (flow-timeout 0.05) (lambda (x) 'timeout)))))
              ;; whatever won above, the bytes must still be reachable
              (set! second-read
                    (flow-perform
                     (flow-choice
                      (flow-wrap (flow-read client) (lambda (x) (list 'read x)))
                      (flow-wrap (flow-timeout 0.5) (lambda (x) 'timeout)))))
              (loop-close client)))
          (loop-close listen-fd)
          (flow-stop)))
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (let ((fd (loop-connect addr addrlen)))
                (foreign-free addr)
                ;; let the server park on its choice first
                (flow-sleep 0.01)
                (let ((t0 (real-time)))
                  ;; write(2) rather than flow-write: this fiber must not
                  ;; yield, so the loop cannot drain between the send and
                  ;; the deadline
                  (flow2-check-spin-until (+ t0 70))
                  (%flow2-check-write2 fd payload (bytevector-length payload))
                  (flow2-check-spin-until (+ t0 100)))
                ;; keep the socket open until the server is done with it
                (flow-sleep 1.0)
                (loop-close fd))))))))) 
  ;; Either outcome of the race is legitimate -- what is not is losing
  ;; the payload. If the read won outright the bytes came back there;
  ;; otherwise they were stashed and the second read finds them.
  (assert (or (equal? first-race (list 'read payload))
              (eq? first-race 'timeout)))
  (let ((delivered (if (eq? first-race 'timeout) second-read first-race)))
    (assert (equal? delivered (list 'read payload))))
  #t)

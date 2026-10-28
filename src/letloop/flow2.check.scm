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
  (define wrong (make-flow-error 'wrong-thread "" '() #f))
  (define overflow (make-flow-error 'overflow "" '() 'boom))
  (assert (flow-error-wrong-thread? wrong))
  (assert (not (flow-error-overflow? wrong)))
  (assert (flow-error-overflow? overflow))
  (assert (not (flow-error-wrong-thread? overflow)))
  (assert (eq? 'boom (flow-error-cause overflow)))
  (assert (not (flow-error? 'overflow)))
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
  (assert (eqv? 0 (%dlist-size (flow-channel-getters ch))))
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
;; The task here deliberately outlives flow-stop: nothing in the
;; program waits for it, so the only thing that can is the shutdown
;; itself. FINISHED set at all is the
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
                       (set! finished #t)))
       (flow-stop)))
   1)
  (assert finished)
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
;; Fifth pass: the pool record isolates the straggler's OWN state, not
;; the objects it shares with the next run. A channel is a plain object;
;; a straggler holding one the next run also uses (a global, as here)
;; popped the new run's parked getter, consed its continuation into the
;; dead run's mailbox, and returned normally -- the fiber was stranded
;; past its own timeout, since the dead resume had already won the state
;; CAS, and the value was gone. A straggler is now refused at every entry
;; point like a stray thread, because from the live run's point of view
;; that is what it is.
(define (~check-flow2-005/straggler-does-not-corrupt-the-next-run)
  (define straggler-done? #f)
  (define straggler-put 'not-yet)
  (define shared (make-flow-channel 'shared-across-runs 4))
  (define live-fiber 'never-resumed)
  (define second-task-done? #f)
  (flow-log-drain!)
  ;; run 1: the task outlives the 2s join -> logged straggler
  (flow-run
   (lambda (workers)
     (flow-submit! (car workers)
                   (lambda ()
                     (sleep (make-time 'time-duration 600000000 2))
                     ;; ~0.6s into run 2, whose fiber is parked on SHARED
                     (set! straggler-put
                           (guard (ex (#t (and (flow-error? ex)
                                               (flow-error-symbol ex))))
                             (flow-put! shared 'from-the-dead-run)
                             'returned))
                     (set! straggler-done? #t)))
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
     (flow-spawn
      (lambda ()
        (set! live-fiber
              (flow-perform
               (flow-choice (flow-get shared)
                            (flow-wrap (flow-timeout 0.8)
                                       (lambda (_) 'timed-out)))))))
     (flow-submit! (car workers)
                   (lambda ()
                     (sleep (make-time 'time-duration 0 1))
                     (set! second-task-done? #t)))
     ;; keep the loop running until the parked fiber has resolved one
     ;; way or the other -- its deadline needs a tick to fire on
     (let wait ((n 0))
       (flow-sleep 0.01)
       (if (or (not (eq? live-fiber 'never-resumed)) (fx>? n 150))
           (flow-stop)
           (wait (fx+ n 1)))))
   1)
  ;; run 2's shutdown joined ITS worker, not whatever count the
  ;; straggler's exit left behind
  (assert second-task-done?)
  ;; and by now the straggler has finished on its own leaked pool
  (assert straggler-done?)
  ;; its put into the live run was refused, and the live fiber was
  ;; neither handed a value it could not receive nor stranded: its own
  ;; deadline still reached it
  (assert (eq? straggler-put 'wrong-thread))
  (assert (eq? live-fiber 'timed-out))
  (assert (eqv? 0 (flow-channel-queue-length shared)))
  #t)

;; A raise from a base event's BLOCK procedure must reach the fiber --
;; exactly as a raise from the fiber's body does. Before the fix, block
;; procs ran inside loop-abort's thunk, on the scheduler's stack with
;; the prompt already unwound, so the raise escaped to loop-apply's
;; catch-all: the fiber's own guards never saw it (in a nursery, as
;; flow2 had then, the join parked forever).
;;
;; Not synthetic. loop-get-sqe raises "submission queue full" past 256
;; queued ops in one tick, reachable from flow-timeout / flow-read /
;; flow-write / flow-open / flow-read-at / flow-write-at; and
;; loop-accept-block raises "concurrent accept on fd". Standalone
;; reproducer: checks/repro-flow2-block-raise.scm.
(define (~check-flow2-003/block-raise-reaches-the-fiber)
  ;; never ready, so flow-perform must call block -- and block raises
  (define (bad-event)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume register-cancel!)
                 (error 'bad-event "raised from block"))))
  (define caught #f)
  (flow-log-drain!)
  (flow-run
   (lambda (workers)
     ;; A: flow-perform raises on the performing fiber, inside its guard
     (guard (ex (#t (set! caught (condition-who ex))))
       (flow-perform (bad-event)))
     ;; B: unhandled, it ends the fiber as an uncaught entry rather
     ;; than vanishing into the scheduler's catch-all
     (flow-spawn (lambda () (flow-perform (bad-event))))
     (flow-sleep 0.01)
     (flow-stop)))
  (assert (eq? caught 'bad-event))
  (let ((uncaught (flow2-check-uncaught (flow-log-drain!))))
    (assert (= 1 (length uncaught)))
    (assert (flow2-check-substring? "raised from block" (cadddr (car uncaught)))))
  #t)

;;------------------------------------------------------------
;; Compute threads
;;------------------------------------------------------------

(define (~check-flow2-005/worker-task-replies)
  (define result #f)
  (flow-run
   (lambda (workers)
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda () (flow-put! response 'pong)))
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (eq? result 'pong))

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
                         (flow-put! response 'slept))))
       (set! result (flow-get! response))
       (flow-stop)))
   1)
  (eq? result 'wrong-thread))

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
                         (flow-put! up (list 'done doubled)))))
       (let serve ()
         (let ((msg (flow-get! up)))
           (cond
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
                       (flow-put! ch 'msg)))
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
;; build must FAIL these rather than hang `make check`.

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
;; go: the fix reports it through flow-log rather than swallowing it, and must
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
  (flow-log-drain!)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-choice sync raising)))))
  (let tick ((n 0))
    (when (fx<? n 6)
      (loop-run-once)
      (tick (fx+ n 1))))
  (and (eq? result 'sync)
       cancelled
       ;; the raise that had nowhere to go is a log entry, not stderr
       (exists (lambda (sexp)
                 (and (pair? sexp) (pair? (cdr sexp))
                      (eq? 'block-raised-after-win (cadr sexp))
                      (flow2-check-substring? "boom" (caddr sexp))))
               (map cdr (flow-log-drain!)))))

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

;; Only used to assert that a log line rendered a condition rather than
;; writing #<condition> -- the whole point of the entry.
(define (flow2-check-substring? needle haystack)
  (let ((n (string-length needle))
        (h (string-length haystack)))
    (let loop ((i 0))
      (and (fx<=? (fx+ i n) h)
           (or (string=? needle (substring haystack i (fx+ i n)))
               (loop (fx+ i 1)))))))

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
            ;; nothing is connecting yet, so the timeout wins and the
            ;; losing accept is cancelled
            (set! timed-out
                  (eq? 'timeout
                       (flow-perform
                        (flow-choice (flow-accept listen-fd)
                                     (flow-wrap (flow-timeout 0.05)
                                                (lambda (_) 'timeout))))))
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
;; it: the loop must see two full chunks, one short chunk, and then a
;; clean EOF -- the caller tracking its own offset the whole way, since
;; these primitives keep no cursor.
;;
;; EOF is #t, the same as flow-read's, and #f is still a failure. This
;; used to be 'eof here and #t there, which is the kind of difference
;; that is only ever discovered by a caller getting it wrong.
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
            ((eq? piece #t) (set! saw-eof #t))
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

;; Third adverse pass, finding 4. "Callable from any thread" was true
;; only of flow-log. A thread the USER forked holds no worker pool, so
;; a channel operation from it fell through to %flow-spawn-safe's
;; loop-spawn branch: it mutated the loop's pending-thunk list with no
;; synchronization against loop-run-once's take-and-clear, and sent no
;; eventfd wake. A lost resume, or one delayed by a whole wait timeout,
;; from an operation the documentation said was fine.
(define (~check-flow2-005/a-thread-the-user-forked-is-refused)
  (define channel (make-flow-channel 'foreign))
  (define put-outcome (box 'not-set))
  (define spawn-outcome (box 'not-set))
  (define done (box #f))
  ;; before any run there is no loop to corrupt, and priming a channel
  ;; is legitimate -- the check must not turn that into an error
  (flow-put! channel 'primed)
  (flow-run
   (lambda (workers)
     (fork-thread
      (lambda ()
        (set-box! put-outcome
                  (guard (ex (#t (and (flow-error? ex) (flow-error-symbol ex))))
                    (flow-put! channel 'from-a-stray-thread)
                    'no-raise))
        (set-box! spawn-outcome
                  (guard (ex (#t (and (flow-error? ex) (flow-error-symbol ex))))
                    (flow-spawn (lambda () (void)))
                    'no-raise))
        (set-box! done #t)))
     (let wait ((n 0))
       (flow-sleep 0.01)
       (if (or (unbox done) (fx>? n 300))
           (flow-stop)
           (wait (fx+ n 1))))))
  (assert (unbox done))
  (assert (eq? 'wrong-thread (unbox put-outcome)))
  (assert (eq? 'wrong-thread (unbox spawn-outcome)))
  ;; the priming put landed and the stray one did not
  (assert (eqv? 1 (flow-channel-queue-length channel)))
  #t)

;; Third adverse pass, finding 8. The losers' cancels run in one thunk
;; -- deliberately, so the whole batch lands before the resumed fiber
;; does -- but they used to share one dynamic extent too, so a raise
;; from any of them aborted the walk and skipped every cancel after it.
;; Most of these thunks call loop-get-sqe, which raises "submission
;; queue full" when the kernel will not take more, so one transient
;; SQ-full could leave unrelated bases uncancelled: a read still in the
;; ring, a timeout still armed with its continuation pinned.
;;
;; The registration order below is what makes this bite. Cancels are
;; consed as they register, so the walk runs them newest-first: the
;; raiser has to register AFTER the base whose cancel it would skip.
(define (~check-flow2-001/a-raising-cancel-does-not-skip-the-others)
  (define ran (box '()))
  (define result 'not-set)
  (define (never-ready-with-cancel thunk)
    (make-flow (lambda (x) x)
               (lambda () #f)
               (lambda (state resume register-cancel!)
                 (register-cancel! thunk))))
  ;; the log is this check's, not the default printer's
  (flow-log-drain!)
  (flow-run
   (lambda (workers)
     (set! result
           (flow-perform
            (flow-choice
             (never-ready-with-cancel
              (lambda () (set-box! ran (cons 'later (unbox ran)))))
             (never-ready-with-cancel
              (lambda () (error '~check-flow2-001 "cancel raised")))
             (flow-wrap (flow-timeout 0.02) (lambda (x) 'timeout)))))
     ;; the cancels are spawned, so they land a tick after the resume
     (flow-sleep 0.05)
     (flow-stop)))
  (assert (eq? 'timeout result))
  (assert (memq 'later (unbox ran)))
  ;; The log line is the only trace a raising cancel leaves, and it used
  ;; to be a bare (flow2 cancel-raised) -- an operator sent here by the
  ;; README after an unexplained hang learned that something raised
  ;; somewhere. It names the base and renders the condition now.
  (let ((entry (let find ((entries (flow-log-drain!)))
                 (cond
                  ((null? entries) #f)
                  ((and (fx>? (length (car entries)) 4)
                        (eq? 'cancel-raised (caddr (car entries)))
                        (string? (list-ref (car entries) 4))
                        (flow2-check-substring? "cancel raised"
                                                (list-ref (car entries) 4)))
                   (car entries))
                  (else (find (cdr entries)))))))
    (assert entry)
    ;; a base built with make-flow carries no data, and #f is the honest
    ;; answer rather than an invented name
    (assert (not (list-ref entry 3))))
  #t)

;; Fourth adverse pass, finding 1. The third pass's own fix, applied at
;; three call sites instead of at the choke point they all pass
;; through. flow-perform went unguarded, so a stray thread took its
;; ON-loop branch -- %worker-current? is #f there -- and flow-get! on a
;; non-empty channel SUCCEEDED: it dequeued off-loop and resumed a
;; parked putter through loop-spawn with no eventfd wake (the putter
;; was still parked a second and a half later), while on an empty
;; channel it died with "attempt to apply non-procedure #f" from
;; loop-abort. flow-submit! and the four scope/lifecycle entry points
;; checked only %worker-current?, which a user thread passes. (The
;; nursery, monitor and scope-cancel entry points it also covered went
;; with nurseries.)
;;
;; One check over every entry point rather than one per procedure: the
;; failure mode was an ENUMERATION that fell behind, and a test shaped
;; like the enumeration would fall behind the same way.
(define (~check-flow2-005/every-entry-point-refuses-a-stray-thread)
  (define channel (make-flow-channel 'stocked))
  (define empty (make-flow-channel 'empty))
  (define latch (make-flow-latch))
  (define outcomes (box '()))
  (define done (box #f))
  (define (attempt name thunk)
    (set-box! outcomes
              (cons (cons name
                          (guard (ex (#t (if (flow-error? ex)
                                             (flow-error-symbol ex)
                                             'not-a-flow-error)))
                            (thunk)
                            'no-raise))
                    (unbox outcomes))))
  (flow-put! channel 'primed)
  (flow-run
   (lambda (workers)
     (fork-thread
      (lambda ()
        (attempt 'get-stocked (lambda () (flow-get! channel)))
        (attempt 'get-empty (lambda () (flow-get! empty)))
        (attempt 'sleep (lambda () (flow-sleep 0.01)))
        (attempt 'submit
                 (lambda ()
                   (flow-submit! (car workers) (lambda () 42))))
        (attempt 'spawn (lambda () (flow-spawn (lambda () (void)))))
        (attempt 'latch-fire (lambda () (flow-latch-fire! latch 'x)))
        (attempt 'stop (lambda () (flow-stop)))
        ;; fifth pass: growing a bound WAKES parked putters, and
        ;; a wake on a stray thread is the unsynchronized
        ;; loop-spawn the guard exists to prevent
        (attempt 'buffer-size
                 (lambda () (flow-channel-buffer-size! channel 8)))
        (set-box! done #t)))
     (let wait ((n 0))
       (flow-sleep 0.01)
       (if (or (unbox done) (fx>? n 300))
           (flow-stop)
           (wait (fx+ n 1)))))
   1)
  (assert (unbox done))
  (for-each (lambda (outcome)
              (unless (eq? 'wrong-thread (cdr outcome))
                (flow-log (list 'flow2-check 'not-refused outcome)))
              (assert (eq? 'wrong-thread (cdr outcome))))
            (unbox outcomes))
  ;; eight entry points tried, and the stocked channel still holds the
  ;; value the off-loop get used to walk away with
  (assert (eqv? 8 (length (unbox outcomes))))
  (assert (not (flow-latch-fired? latch)))
  (assert (eqv? 1 (flow-channel-queue-length channel)))
  #t)

;; Fourth adverse pass, finding 2. loop-close-prep! purges the fd's
;; recv stash, but flow2's recv registered its handler in loop-handlers
;; ONLY -- never in the per-fd operation index -- so the teardown pass
;; skipped it and the handler outlived the close. A recv that completed
;; with data in the window between the cancel submit and the kernel
;; acting on it then ran loop-recv-backlog-put! AFTER the purge,
;; re-creating a stash under a number the kernel was about to reissue:
;; the next connection's first flow-read served the previous
;; connection's bytes.
;;
;; The write is aimed at that window rather than guaranteed to land in
;; it -- whether the kernel takes the send or the cancel first is not
;; ours to decide. So this reproduces sometimes and never fails
;; spuriously: with the recv in the index the stash CANNOT come back,
;; because the purge deletes the handler and the late CQE finds
;; nothing (the drain has already recycled its buffer).
(define (~check-flow2-009/a-closed-fd-does-not-hand-on-a-stash)
  (define PORT 18253)
  (define payload (string->utf8 "after-the-close"))
  (define race 'not-set)
  (define stash 'not-set)
  (define closed-fd #f)
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (let ((client (flow-perform (flow-accept listen-fd))))
            (set! closed-fd client)
            (set! race
                  (flow-perform
                   (flow-choice
                    (flow-wrap (flow-read client) (lambda (x) (list 'read x)))
                    (flow-wrap (flow-timeout 0.05) (lambda (x) 'timeout)))))
            ;; the fd goes away while the recv is still in the ring
            (loop-close client)
            ;; long enough for the late CQE to be drained and for its
            ;; handler to run, if one is still registered
            (flow-sleep 0.3)
            (set! stash (loop-recv-backlog-take! client)))
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
                  ;; write(2), not flow-write: this fiber must not yield,
                  ;; or the loop drains between the deadline and the
                  ;; send and there is no window left to aim at
                  (flow2-check-spin-until (+ t0 52))
                  (%flow2-check-write2 fd payload (bytevector-length payload)))
                (flow-sleep 1.0)
                (loop-close fd))))))))) 
  (assert closed-fd)
  ;; if the read won outright the close raced nothing and there was
  ;; never a payload to strand; either way nothing may be left under a
  ;; closed fd's number
  (assert (or (eq? race 'timeout) (pair? race)))
  (assert (not stash))
  #t)

;;------------------------------------------------------------
;; Fifth adverse pass, 2026-09-03
;;------------------------------------------------------------

;; A flow-wrap's PROC used to run inside the base's resume -- on the
;; stack of whoever completed the rendezvous, BEFORE resume-from's CAS.
;; A PROC that raised therefore raised in the fiber calling flow-put!,
;; the getter was never resumed, and the value was gone; the identical
;; program with the value already queued (the try path) raised in the
;; getter, as CML says. The wrap now travels with the raw value and is
;; applied by %flow-settle on the performing fiber's own stack, after
;; the commit, inside its own guards.
(define (~check-flow2-001/wrap-runs-on-the-performer-after-commit)
  (define ch (make-flow-channel 'wrapped))
  (define getter-outcome 'never-resumed)
  (define putter-outcome 'not-set)
  (define (bad-wrap v) (error 'wrap "boom"))
  (flow-run
   (lambda (workers)
     ;; try path, for contrast: the value is already there
     (flow-put! ch 'queued)
     (assert (equal? '(getter-raised wrap)
                     (guard (ex (#t (list 'getter-raised (condition-who ex))))
                       (flow-perform (flow-wrap (flow-get ch) bad-wrap)))))
     ;; block path: the getter parks, then a sibling puts
     (flow-spawn
      (lambda ()
        (set! getter-outcome
              (guard (ex (#t (list 'getter-raised (condition-who ex))))
                (flow-perform (flow-wrap (flow-get ch) bad-wrap))))))
     (flow-sleep 0.01)
     (set! putter-outcome
           (guard (ex (#t (list 'putter-raised (condition-who ex))))
             (flow-put! ch 'delivered)
             'put-returned))
     (flow-sleep 0.02)
     (flow-stop)))
  (assert (eq? putter-outcome 'put-returned))
  (assert (equal? getter-outcome '(getter-raised wrap)))
  ;; nothing left behind by either side
  (assert (eqv? 0 (flow-channel-queue-length ch)))
  (assert (eqv? 0 (flow-channel-getters-length ch)))
  #t)

;; The cross-thread half of the same finding, and the one that broke the
;; Rationale's promise that "there is no API through which a compute
;; thread can reach the loop's state": when the deliverer was a worker,
;; the wrap ran on the worker. Here the wrap reports its thread and
;; spawns a fiber; both must be the loop's.
(define (~check-flow2-005/wrap-runs-on-the-loop-when-a-worker-delivers)
  (define ch (make-flow-channel 'tid))
  (define loop-tid (get-thread-id))
  (define wrap-tid 'not-set)
  (define spawned? #f)
  (flow-run
   (lambda (workers)
     (flow-spawn
      (lambda ()
        (set! wrap-tid
              (flow-perform
               (flow-wrap (flow-get ch)
                          (lambda (v)
                            (flow-spawn (lambda () (set! spawned? #t)))
                            (get-thread-id)))))))
     (flow-sleep 0.01)                 ;; the getter is parked
     (flow-submit! (car workers)
                   (lambda ()
                     (sleep (make-time 'time-duration 20000000 0))
                     (flow-put! ch 'x)))
     (let wait ((n 0))
       (flow-sleep 0.01)
       (if (or spawned? (fx>? n 100))
           (flow-stop)
           (wait (fx+ n 1)))))
   1)
  (assert (eqv? wrap-tid loop-tid))
  (assert spawned?)
  #t)

;; The pool's eventfd wake cell used to be the collector's read target
;; too, and an eventfd read stores the counter into its buffer. After
;; the first wake the cell held the count that read returned, every
;; later signal added THAT instead of 1, and whenever several wakes
;; coalesced inside one busy tick the cell was multiplied -- it reached
;; 2^64 in about twenty windows, after which a second signal per read
;; cycle blocked the worker in write(2) until the loop's next tick.
;; Observed through /proc/self/fdinfo, which reports the live counter:
;; at the end of a busy window it must be the number of signals in the
;; window, never their product with the previous window's.
(define (flow2-check-eventfd-counts)
  (define (count-after info i)
    ;; the hex value following "eventfd-count:" at I, whitespace-trimmed
    (let skip ((j (fx+ i 14)))
      (if (and (fx<? j (string-length info))
               (char-whitespace? (string-ref info j)))
          (skip (fx+ j 1))
          (let end ((k j))
            (if (or (fx=? k (string-length info))
                    (char-whitespace? (string-ref info k)))
                (string->number (substring info j k) 16)
                (end (fx+ k 1)))))))
  (let loop ((names (directory-list "/proc/self/fd")) (out '()))
    (if (null? names)
        out
        (let ((info (guard (ex (#t #f))
                      (call-with-input-file
                          (string-append "/proc/self/fdinfo/" (car names))
                        get-string-all))))
          (loop (cdr names)
                (let find ((i 0))
                  (cond
                   ((or (not info) (fx>? (fx+ i 14) (string-length info))) out)
                   ((string=? "eventfd-count:" (substring info i (fx+ i 14)))
                    (cons (count-after info i) out))
                   (else (find (fx+ i 1))))))))))

(define (~check-flow2-005/coalesced-wakes-do-not-inflate-the-eventfd)
  (define workers 4)
  (define rounds 8)
  (define peak 0)
  (flow-run
   (lambda (ws)
     (let round ((r 0))
       (when (fx<? r rounds)
         (let ((channels (map (lambda (i) (make-flow-channel (cons 'wake i) 4))
                              (iota workers)))
               (arrived (box 0)))
           ;; one fiber parked per channel, so every worker put has to
           ;; RESUME a fiber -- a put that merely enqueues sends no wake
           (for-each (lambda (ch)
                       (flow-spawn
                        (lambda ()
                          (flow-get! ch)
                          (set-box! arrived (fx+ 1 (unbox arrived))))))
                     channels)
           (flow-sleep 0.01)
           (for-each (lambda (w ch)
                       (flow-submit! w
                                     (lambda ()
                                       (sleep (make-time 'time-duration 10000000 0))
                                       (flow-put! ch 'x))))
                     ws channels)
           ;; hold the loop busy so the wakes coalesce, then read the
           ;; live counter before the loop can drain it
           (let ((until (+ (real-time) 60)))
             (let spin () (when (< (real-time) until) (spin))))
           (set! peak (apply max peak (flow2-check-eventfd-counts)))
           (let settle ((n 0))
             (when (and (fx<? (unbox arrived) workers) (fx<? n 200))
               (flow-sleep 0.01)
               (settle (fx+ n 1))))
           (round (fx+ r 1)))))
     (flow-stop))
   workers)
  ;; a handful of resumes' worth of unit signals, not their product:
  ;; the multiplied cell read 589824 by round six
  (assert (fx<=? peak 64))
  #t)

;; current-error-port is a thread parameter: a flush thread forked
;; before a parameterize keeps the port it inherited, so "reparameterize
;; and it is honored on the next cycle" was never true of a thread
;; started earlier. The port is now captured on the CALLING thread when
;; the flusher starts, or passed explicitly; this pins the former.
(define (~check-flow2-000/log-flush-writes-to-the-port-current-at-start)
  (define captured (open-output-string))
  (flow-log-drain!)
  (parameterize ((current-error-port captured))
    (flow-log-start! 0.01)
    (flow-log '(flow2-check captured-line))
    (flow-log-stop!))
  (assert (flow2-check-substring? "captured-line" (get-output-string captured)))
  ;; and an explicit port wins over the current one
  (let ((explicit (open-output-string)))
    (flow-log-start! 0.01 explicit)
    (flow-log '(flow2-check explicit-line))
    (flow-log-stop!)
    (assert (flow2-check-substring? "explicit-line" (get-output-string explicit))))
  #t)

;; A negative COMPUTE-COUNT is not zero, so a pool was created, and the
;; forking loop stopped on (fx=? i compute-count) -- never, for i >= 0.
;; It forked until fork-thread failed with EAGAIN (351 threads under a
;; test limit). The argument is validated before anything is touched.
(define (~check-flow2-005/compute-count-is-validated)
  (define (refused? count)
    (guard (ex (#t (not (flow-error? ex))))
      (flow-run (lambda (workers) (flow-stop)) count)
      #f))
  (assert (refused? -1))
  (assert (refused? 1.5))
  (assert (refused? 'two))
  ;; zero and a positive count are still fine
  (flow-run (lambda (workers) (assert (null? workers)) (flow-stop)) 0)
  (flow-run (lambda (workers) (assert (= 1 (length workers))) (flow-stop)) 1)
  #t)

;;------------------------------------------------------------
;; Uncaught errors
;;------------------------------------------------------------

;; Entries whose sexp is (flow2 uncaught ...), oldest first.
(define (flow2-check-uncaught entries)
  (filter (lambda (sexp)
            (and (pair? sexp) (eq? (car sexp) 'flow2)
                 (pair? (cdr sexp)) (eq? (cadr sexp) 'uncaught)))
          (map cdr entries)))

;; An error nobody handled ends its fiber and becomes a log entry; the
;; loop and every other fiber carry on. The condition is rendered on the
;; way in -- written raw it would be #<condition>, which says nothing.
;; Fiber zero is a fiber like any other.
(define (~check-flow2-012/uncaught-raise-in-a-fiber-is-logged)
  (define after 'not-set)
  (flow-log-drain!)
  (flow-run
   (lambda (workers)
     (flow-spawn (lambda () (flow-sleep 0.005) (error 'child "child boom")))
     (flow-spawn (lambda () (raise 'plain-object)))
     (flow-sleep 0.02)
     (set! after 'loop-still-running)
     (flow-spawn (lambda () (flow-stop)))
     (error 'fiber-zero "zero boom")))
  (assert (eq? after 'loop-still-running))
  (let ((uncaught (flow2-check-uncaught (flow-log-drain!))))
    (assert (= 3 (length uncaught)))
    (for-each (lambda (sexp) (assert (eq? 'fiber (caddr sexp)))) uncaught)
    (assert (member '(flow2 uncaught fiber plain-object) uncaught))
    (assert (exists (lambda (sexp)
                      (let ((x (cadddr sexp)))
                        (and (string? x) (flow2-check-substring? "child boom" x))))
                    uncaught))
    (assert (exists (lambda (sexp)
                      (let ((x (cadddr sexp)))
                        (and (string? x) (flow2-check-substring? "zero boom" x))))
                    uncaught)))
  #t)
;; A task that raises and does not handle it gets no reply from the
;; framework -- that is the task's protocol, not flow2's -- but it is
;; logged, named by the worker it ran on, and the worker survives to
;; serve the next submission. A task that wants its submitter to hear
;; about failure says so itself, with one guard.
(define (~check-flow2-012/uncaught-raise-in-a-task-is-logged)
  (define alive #f)
  (define reported #f)
  (flow-log-drain!)
  (flow-run
   (lambda (workers)
     (flow-submit! (car workers) (lambda () (raise 'kaboom)))
     ;; same worker, still serving
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers) (lambda () (flow-put! response 'alive)))
       (set! alive (flow-get! response)))
     ;; the user-code spelling of a failure reply
     (let ((response (make-flow-channel)))
       (flow-submit! (car workers)
                     (lambda ()
                       (flow-put! response
                                  (guard (ex (#t (cons 'failed ex)))
                                    (cons 'done (raise 'reported))))))
       (set! reported (flow-get! response)))
     (flow-stop))
   1)
  (assert (eq? alive 'alive))
  (assert (equal? reported '(failed . reported)))
  (assert (equal? (flow2-check-uncaught (flow-log-drain!))
                  '((flow2 uncaught task (worker . 0) kaboom))))
  #t)

;; The coordination a nursery could not express, and the reason flow2
;; no longer has one: a request fans out over producers that stream
;; results, gathers until a deadline, answers with what it has, and
;; hands the SAME channels to a completer that outlives the request and
;; gathers the rest -- a search that ranks approximately now and caches
;; the full result for the next query. Each producer reports its own
;; end on EXITS, failure included; that guard is the user-code spelling
;; of a death notice, and nothing in flow2 had to know about it.
(define (~check-flow2-012/fan-out-gather-until-a-deadline-then-hand-off)
  (define answered 'not-set)
  (define completed 'not-set)
  (define (producer id count delay pages exits)
    (lambda ()
      (flow-put! exits
                 (guard (ex (#t (list 'failed id)))
                   (let loop ((n 0))
                     (when (< n count)
                       (flow-sleep delay)
                       (flow-put! pages (cons id n))
                       (loop (+ n 1))))
                   (when (eq? id 'broken) (error 'producer "broken"))
                   (list 'done id)))))
  ;; Gather until every producer exited or, with a deadline, until it
  ;; passes; a flow-timeout arms from the perform, so the remaining time
  ;; is recomputed for each one.
  (define (gather pages exits live seen failed deadline)
    (let loop ((live live) (seen seen) (failed failed))
      (if (zero? live)
          (list 'complete live seen failed)
          (let ((ev (flow-perform
                     (apply flow-choice
                            (flow-wrap (flow-get pages) (lambda (p) (cons 'page p)))
                            (flow-wrap (flow-get exits) (lambda (x) (cons 'exit x)))
                            (if deadline
                                (list (flow-wrap
                                       (flow-timeout
                                        (max 0 (/ (- deadline (real-time)) 1000.0)))
                                       (lambda (_) '(deadline))))
                                '())))))
            (case (car ev)
              ((page) (loop live (cons (cdr ev) seen) failed))
              ((exit) (loop (- live 1) seen
                            (if (eq? (cadr ev) 'failed) (cons (caddr ev) failed) failed)))
              (else (list 'partial live seen failed)))))))
  (flow-run
   (lambda (workers)
     (let ((pages (make-flow-channel 'pages))
           (exits (make-flow-channel 'exits)))
       (flow-spawn (producer 'fast 3 0.005 pages exits))
       (flow-spawn (producer 'slow 3 0.04 pages exits))
       (flow-spawn (producer 'broken 1 0.005 pages exits))
       (let ((now (gather pages exits 3 '() '() (+ (real-time) 30))))
         (set! answered now)
         (when (eq? (car now) 'partial)
           ;; the fork: answer now, and let a completer take over the
           ;; very channels the producers are still writing to
           (flow-spawn
            (lambda ()
              (set! completed
                    (apply gather pages exits (append (cdr now) (list #f))))))))
       (let wait ((n 0))
         (flow-sleep 0.01)
         (if (or (not (eq? completed 'not-set)) (fx>? n 100))
             (flow-stop)
             (wait (fx+ n 1)))))))
  ;; the slow producer needs 120ms, the deadline is 30ms
  (assert (eq? 'partial (car answered)))
  (assert (< (length (caddr answered)) 7))
  (assert (eq? 'complete (car completed)))
  (assert (= 7 (length (caddr completed))))
  (assert (equal? '(broken) (cadddr completed)))
  #t)

;;------------------------------------------------------------
;; Latches
;;------------------------------------------------------------

;; One fire reaches every parked waiter, a later wait completes at
;; once with the same value, and a second fire changes nothing.
(define (~check-flow2-013/latch-wakes-every-waiter-once)
  (define latch (make-flow-latch))
  (define seen '())
  (define late 'not-set)
  (define second-fire 'not-set)
  (flow-run
   (lambda (workers)
     (for-each (lambda (i)
                 (flow-spawn
                  (lambda ()
                    (set! seen (cons (cons i (flow-latch-wait! latch)) seen)))))
               '(1 2 3))
     (flow-sleep 0.01)
     (assert (null? seen))
     (assert (not (flow-latch-fired? latch)))
     (assert (eq? #t (flow-latch-fire! latch 'complete)))
     (flow-sleep 0.01)
     (set! late (flow-latch-wait! latch))
     (set! second-fire (flow-latch-fire! latch 'again))
     (flow-stop)))
  (assert (= 3 (length seen)))
  (assert (for-all (lambda (entry) (eq? 'complete (cdr entry))) seen))
  (assert (eq? late 'complete))
  (assert (eq? second-fire #f))
  (assert (flow-latch-fired? latch))
  (assert (eqv? 0 (%dlist-size (flow-latch-waiters latch))))
  #t)

;; flow-get's lesson, for the latch: a wait that loses a choice takes
;; its entry with it. A stop latch may never fire, so a leftover waiter
;; would pin its continuation forever.
(define (~check-flow2-013/losing-latch-wait-leaves-no-waiter)
  (define latch (make-flow-latch))
  (flow-run
   (lambda (workers)
     (let round ((i 0))
       (when (fx<? i 50)
         (flow-perform (flow-choice (flow-latch-wait latch)
                                    (flow-wrap (flow-timeout 0.0005)
                                               (lambda (_) 'late))))
         (round (fx+ i 1))))
     (flow-stop)))
  (assert (eqv? 0 (%dlist-size (flow-latch-waiters latch))))
  (assert (eq? #t (flow-latch-fire! latch 'fine)))
  #t)

;; A worker parks on a latch the loop fires, and fires one a fiber is
;; parked on.
(define (~check-flow2-013/latch-crosses-threads)
  (define go (make-flow-latch))
  (define done (make-flow-latch))
  (define fiber-saw 'not-set)
  (flow-run
   (lambda (workers)
     (flow-submit! (car workers)
                   (lambda ()
                     (flow-latch-fire! done (list 'worker-saw (flow-latch-wait! go)))))
     (flow-sleep 0.02)                  ;; the worker is parked by now
     (flow-latch-fire! go 'go)
     (set! fiber-saw (flow-latch-wait! done))
     (flow-stop))
   1)
  (assert (equal? fiber-saw '(worker-saw go)))
  #t)

;; Stopping without cancellation: producers include the stop latch in
;; their own choices, so they stop where they chose to be stoppable,
;; and they say so on a channel.
(define (~check-flow2-013/latch-as-a-stop-event)
  (define stop (make-flow-latch))
  (define exits (make-flow-channel 'exits))
  (define reasons 'not-set)
  (flow-run
   (lambda (workers)
     (for-each (lambda (i)
                 (flow-spawn
                  (lambda ()
                    (let loop ((n 0))
                      (if (flow-perform
                           (flow-choice (flow-wrap (flow-latch-wait stop) (lambda (_) #t))
                                        (flow-wrap (flow-timeout 0.005) (lambda (_) #f))))
                          (flow-put! exits (list i 'stopped))
                          (loop (+ n 1)))))))
               '(1 2 3))
     (flow-sleep 0.03)
     (flow-latch-fire! stop 'please)
     (set! reasons (list (flow-get! exits) (flow-get! exits) (flow-get! exits)))
     (flow-stop)))
  (assert (equal? '(1 2 3) (list-sort < (map car reasons))))
  (assert (for-all (lambda (r) (eq? 'stopped (cadr r))) reasons))
  #t)

;; Sixth adverse pass. A flush that raised killed the flush thread
;; before it marked itself stopped, so flow-log-stop! spun forever and
;; flow-log-start! would not start another. The stop is run on its own
;; thread with a bounded wait, so a regression FAILS here instead of
;; hanging the suite.
(define (~check-flow2-000/a-failing-flush-stops-cleanly-and-keeps-its-batch)
  (define bad (make-custom-textual-output-port
               "bad" (lambda (str start count) (error 'bad-port "disk full"))
               #f #f #f))
  (define stopped (box #f))
  (flow-log-drain!)
  (flow-log-start! 0.01 bad)
  (flow-log '(flow2-check kept))
  (sleep (make-time 'time-duration 50000000 0))
  (fork-thread (lambda () (flow-log-stop!) (set-box! stopped #t)))
  (let wait ((n 0))
    (when (and (not (unbox stopped)) (fx<? n 200))
      (sleep (make-time 'time-duration 10000000 0))
      (wait (fx+ n 1))))
  (assert (unbox stopped))
  ;; the batch the port refused is still in the log, with the reason
  (let ((sexps (map cdr (flow-log-drain!))))
    (assert (member '(flow2-check kept) sexps))
    (assert (exists (lambda (x)
                      (and (pair? x) (pair? (cdr x))
                           (eq? 'log-flush-raised (cadr x))
                           (flow2-check-substring? "disk full" (caddr x))))
                    sexps)))
  ;; and a new flusher starts
  (let ((good (open-output-string)))
    (flow-log-start! 0.01 good)
    (flow-log '(flow2-check after-restart))
    (flow-log-stop!)
    (assert (flow2-check-substring? "after-restart" (get-output-string good))))
  #t)

;; The sink is where a program decides what flow2's own events mean to
;; it. Here it counts uncaught errors from a run -- the policy that
;; lives at the logger level now that the library has none of its own.
(define (~check-flow2-000/log-sink-can-be-a-procedure)
  (define batches (box '()))
  (define uncaught (box 0))
  (define (sink entries)
    (set-box! batches (cons entries (unbox batches)))
    (for-each (lambda (entry)
                (let ((sexp (cdr entry)))
                  (when (and (pair? sexp) (eq? 'flow2 (car sexp))
                             (pair? (cdr sexp)) (eq? 'uncaught (cadr sexp)))
                    (set-box! uncaught (+ 1 (unbox uncaught))))))
              entries))
  (flow-log-drain!)
  (flow-log-start! 0.01 sink)
  (flow-run
   (lambda (workers)
     (flow-spawn (lambda () (raise 'one)))
     (flow-spawn (lambda () (raise 'two)))
     (flow-log '(flow2-check ordinary))
     (flow-sleep 0.01)
     (flow-stop)))
  (flow-log-stop!)
  (assert (= 2 (unbox uncaught)))
  ;; every batch handed over was non-empty, and nothing was lost
  (assert (for-all pair? (unbox batches)))
  (assert (= 3 (apply + (map length (unbox batches)))))
  ;; a sink that is neither is a mistake at the call site
  (assert (guard (ex (#t #t)) (flow-log-start! 0.01 'stderr) #f))
  #t)

;;------------------------------------------------------------
;; Sixth adverse pass
;;------------------------------------------------------------

;; There is one loop per process and loop-new frees the ring that is
;; running. A flow-run nested in a fiber tore down its caller's loop --
;; the outer fiber died with "attempt to apply non-procedure #f" and the
;; outer run returned early -- and one called from a compute task did
;; the same to the main thread's ring, after which two threads ran one
;; loop and the process hung. Both are refused now, and the outer run
;; carries on.
(define (~check-flow2-005/flow-run-refuses-to-nest)
  (define nested 'not-set)
  (define from-task 'not-set)
  (define outer-alive #f)
  (flow-run
   (lambda (workers)
     (set! nested
           (guard (ex ((flow-error? ex) (flow-error-symbol ex))
                      ((message-condition? ex) (condition-message ex)))
             (flow-run (lambda (w) (flow-stop)))
             'returned))
     (let ((reply (make-flow-channel 'reply)))
       (flow-submit! (car workers)
                     (lambda ()
                       (flow-put! reply
                                  (guard (ex ((flow-error? ex) (flow-error-symbol ex))
                                             (#t 'other))
                                    (flow-run (lambda (w) (flow-stop)))
                                    'returned))))
       (set! from-task (flow-get! reply)))
     (flow-sleep 0.01)
     (set! outer-alive #t)
     (flow-stop))
   1)
  (assert (equal? nested "a flow-run is already in progress"))
  (assert (eq? from-task 'wrong-thread))
  (assert outer-alive)
  #t)

;; A start that failed -- here eventfd creation, refused for want of a
;; descriptor -- left %flow-loop-thread set, so flow2 believed a run was
;; in progress and every call from another thread raised wrong-thread.
;; The descriptor table is filled under a lowered soft limit so this is
;; quick; the limit is restored on every path.
(define (~check-flow2-005/a-failed-start-releases-the-loop)
  (define getrlimit (foreign-procedure "getrlimit" (int void*) int))
  (define setrlimit (foreign-procedure "setrlimit" (int void*) int))
  (define open2 (foreign-procedure "open" (string int int) int))
  (define close2 (foreign-procedure "close" (int) int))
  (define RLIMIT-NOFILE 7)
  (define saved (foreign-alloc 16))
  (define lowered (foreign-alloc 16))
  (define start-outcome 'not-set)
  (define stray (box 'not-set))
  (define again #f)
  ;; a ring for loop-new to recycle, so it is the eventfd that fails
  (flow-run (lambda (workers) (flow-stop)))
  (getrlimit RLIMIT-NOFILE saved)
  (dynamic-wind
    (lambda ()
      (foreign-set! 'unsigned-64 lowered 0
                    (+ 16 (apply max (map string->number
                                          (directory-list "/proc/self/fd")))))
      (foreign-set! 'unsigned-64 lowered 8 (foreign-ref 'unsigned-64 saved 8))
      (setrlimit RLIMIT-NOFILE lowered))
    (lambda ()
      (let ((held (let fill ((acc '()))
                    (let ((fd (open2 "/dev/null" 0 0)))
                      (if (fx<? fd 0) acc (fill (cons fd acc)))))))
        (set! start-outcome
              (guard (ex (#t 'raised))
                (flow-run (lambda (workers) (flow-stop)) 1)
                'returned))
        (for-each close2 held)))
    (lambda () (setrlimit RLIMIT-NOFILE saved)))
  (foreign-free saved)
  (foreign-free lowered)
  ;; no run is in progress, so another thread may prime a channel
  (let ((ch (make-flow-channel 'prime))
        (done (box #f)))
    (fork-thread
     (lambda ()
       (set-box! stray (guard (ex ((flow-error? ex) (flow-error-symbol ex)))
                         (flow-put! ch 'primed)
                         'accepted))
       (set-box! done #t)))
    (let wait ((n 0))
      (when (and (not (unbox done)) (fx<? n 200))
        (sleep (make-time 'time-duration 5000000 0))
        (wait (fx+ n 1)))))
  ;; and the next run starts
  (flow-run (lambda (workers) (set! again (length workers)) (flow-stop)) 1)
  (assert (eq? start-outcome 'raised))
  (assert (eq? (unbox stray) 'accepted))
  (assert (eqv? again 1))
  #t)

;; fork-thread copies thread parameters, so a thread the user forked
;; inside a compute task held the worker's pool: its flow-put! was
;; accepted as the worker's instead of refused, and once the run had
;; closed the eventfd it signalled the closed number -- eight bytes of
;; the freed pool buffer written into whatever file reused it. The
;; worker itself must still be recognised.
(define (~check-flow2-005/a-thread-forked-in-a-task-is-refused)
  (define ch (make-flow-channel 'shared))
  (define forked (box 'not-set))
  (define worker-put 'not-set)
  (flow-run
   (lambda (workers)
     (let ((reply (make-flow-channel 'reply)))
       (flow-submit! (car workers)
                     (lambda ()
                       (fork-thread
                        (lambda ()
                          (set-box! forked
                                    (guard (ex ((flow-error? ex) (flow-error-symbol ex)))
                                      (flow-put! ch 'from-a-user-thread)
                                      'accepted))))
                       (flow-put! reply 'worker-put-ok)))
       (set! worker-put (flow-get! reply)))
     (let wait ((n 0))
       (flow-sleep 0.01)
       (if (or (not (eq? (unbox forked) 'not-set)) (fx>? n 100))
           (flow-stop)
           (wait (fx+ n 1)))))
   1)
  (assert (eq? worker-put 'worker-put-ok))
  (assert (eq? (unbox forked) 'wrong-thread))
  (assert (eqv? 0 (flow-channel-queue-length ch)))
  #t)

;; Per-thread log boxes were inherited across fork-thread, so a forked
;; thread logged into its parent's box: two threads CASing one box, and
;; entries interleaved where the drain order promises per-thread runs.
(define (~check-flow2-000/a-forked-thread-logs-to-its-own-box)
  (define done (box #f))
  (flow-log-drain!)
  (flow-log '(flow2-check parent-before))
  (fork-thread (lambda () (flow-log '(flow2-check child)) (set-box! done #t)))
  (let wait ((n 0))
    (when (and (not (unbox done)) (fx<? n 200))
      (sleep (make-time 'time-duration 5000000 0))
      (wait (fx+ n 1))))
  (flow-log '(flow2-check parent-after))
  ;; the parent's box was registered first, so its two entries come
  ;; first and together; a shared box gave (before child after)
  (assert (equal? '((flow2-check parent-before)
                    (flow2-check parent-after)
                    (flow2-check child))
                  (filter (lambda (x) (and (pair? x) (eq? 'flow2-check (car x))))
                          (map cdr (flow-log-drain!)))))
  #t)

;; A read that lost its choice used to cancel its recv, and the cancel
;; is asynchronous: the kernel could still complete the old recv with
;; data after the next flow-read had found the backlog empty and
;; submitted its own. The new recv took the NEXT bytes, the late one
;; parked the earlier bytes on the backlog, and the read after that
;; returned them -- (timeout "two" "one") for a peer that sent "one"
;; then "two". The bytes "one" are sent the instant the timeout wins,
;; which is the window the old cancel raced.
(define (~check-flow2-006/reads-after-a-lost-race-keep-stream-order)
  (define PORT 18255)
  (define peer (box #f))
  (define client #f)
  (define results '())
  (define (send! str)
    (let ((bv (string->utf8 str)))
      (%flow2-check-write2 (unbox peer) bv (bytevector-length bv))))
  (define (race seconds)
    (flow-perform
     (flow-choice
      (flow-wrap (flow-read client) (lambda (x) (if (bytevector? x) (utf8->string x) x)))
      (flow-wrap (flow-timeout seconds) (lambda (_) 'timeout)))))
  (flow-run
   (lambda (workers)
     (let ((listen-fd (loop-socket-new AF-INET SOCK-STREAM 0)))
       (loop-bind listen-fd "127.0.0.1" PORT)
       (loop-listen listen-fd 128)
       (flow-spawn
        (lambda ()
          (call-with-values (lambda () (make-sockaddr-in 127 0 0 1 PORT))
            (lambda (addr addrlen)
              (set-box! peer (loop-connect addr addrlen))
              (foreign-free addr)))))
       (set! client (flow-perform (flow-accept listen-fd)))
       (let wait () (unless (unbox peer) (flow-sleep 0.005) (wait)))
       (set! results (cons (race 0.05) results))
       (send! "one")
       (flow-spawn (lambda () (flow-sleep 0.1) (send! "two")))
       (set! results (cons (race 0.5) results))
       (set! results (cons (race 0.5) results))
       (loop-close client)
       (loop-close (unbox peer))
       (loop-close listen-fd)
       (flow-stop))))
  (assert (equal? '(timeout "one" "two") (reverse results)))
  #t)

;; A flow-get that dequeued during registration and then lost to an
;; earlier base puts the value back -- and must not wake a putter for
;; room it never made. It did: the wake came before the resume, and on
;; a compute thread the woken putter could fill the slot before the
;; unget, leaving the channel one past its bound.
;;
;; Made deterministic the way losing-get-does-not-eat-a-value is: the
;; winning base's block runs after the poll, fills the channel to its
;; bound, parks a probe on the space list, and wins -- so the get that
;; registers after it takes the immediate path and loses. The probe
;; records whether it was woken.
(define (~check-flow2-002/a-losing-get-wakes-no-putter)
  (define ch (make-flow-channel 'full 1))
  (define woken #f)
  ;; a parked putter's shape: (state resume . token)
  (define probe (cons* (box 'waiting) (lambda (v) (set! woken #t) #t) (box #t)))
  (define result #f)
  (define winner (make-flow (lambda (x) x)
                            (lambda () #f)
                            (lambda (state resume register-cancel!)
                              (flow-put! ch 'the-value)          ;; at the bound
                              (%dlist-link! (flow-channel-space ch)
                                            (%dnode-new probe))
                              (resume 'winner))))
  (flow-run
   (lambda (workers)
     (set! result (flow-perform (flow-choice winner (flow-get ch))))
     (flow-stop)))
  (assert (eq? result 'winner))
  (assert (not woken))
  (assert (eq? probe (%dnode-value (%dlist-first (flow-channel-space ch)))))
  (assert (eqv? 1 (flow-channel-queue-length ch)))
  #t)

;;------------------------------------------------------------
;; The default printer
;;------------------------------------------------------------

;; With no flusher started, entries used to accumulate in memory for the
;; life of the process and were written nowhere -- uncaught errors
;; included. The first flow-log now starts a printer to stderr, and a
;; program that drains the log takes it over: the printer stops and does
;; not come back by itself.
(define (~check-flow2-000/log-prints-to-stderr-by-default)
  (define mutex (make-mutex))
  (define text "")
  (define (captured) (with-mutex mutex text))
  (define port
    (make-custom-textual-output-port
     "flow2-check-stderr"
     (lambda (str start count)
       (with-mutex mutex
         (set! text (string-append text (substring str start (+ start count)))))
       count)
     #f #f #f))
  (define (contains? haystack needle)
    (let ((n (string-length needle)) (h (string-length haystack)))
      (let loop ((i 0))
        (and (<= (+ i n) h)
             (or (string=? needle (substring haystack i (+ i n)))
                 (loop (+ i 1)))))))
  (define (nap) (sleep (make-time 'time-duration 10000000 0)))
  ;; Take the log over, which stops any printer, then put it back in the
  ;; state a fresh process starts in.
  (flow-log-drain!)
  (set-box! %flow-log-mode 'auto)
  (parameterize ((current-error-port port))
    (flow-log '(flow2-check by-default)))
  (let wait ((n 0))
    (unless (or (contains? (captured) "by-default") (= n 300))
      (nap)
      (wait (+ n 1))))
  (assert (contains? (captured) "flow2-check by-default)"))
  (assert (unbox %flow-log-default-running?))
  ;; Draining takes the log over: the printer is gone, and what is
  ;; logged next is the drainer's, not stderr's.
  (flow-log-drain!)
  (assert (not (unbox %flow-log-default-running?)))
  (assert (unbox %flow-log-stopped?))
  (flow-log '(flow2-check after-take-over))
  (do ((i 0 (+ i 1))) ((= i 20)) (nap))
  (assert (not (contains? (captured) "after-take-over")))
  (assert (equal? (map cdr (flow-log-drain!)) '((flow2-check after-take-over))))
  #t)

;; A procedure sink runs on the loop, so the README's "Route uncaught
;; errors" pattern works as printed: the sink fires a latch and the
;; supervising fiber wakes. On the flush thread, where the sink used to
;; run, flow-latch-fire! raised wrong-thread and the flusher died on the
;; first uncaught error it saw.
(define (~check-flow2-000/a-procedure-sink-runs-on-the-loop)
  (define failures (make-flow-latch))
  (define reported (box '()))
  (define sink-threads (box '()))
  (define (report! sexp) (set-box! reported (cons sexp (unbox reported))))
  (define woke 'not-set)
  (define off-loop-start 'not-set)
  (define main (get-thread-id))
  (flow-log-drain!)
  ;; the README's code, with a record of the thread it ran on
  (flow-log-start! 0.01
    (lambda (entries)
      (set-box! sink-threads (cons (get-thread-id) (unbox sink-threads)))
      (for-each (lambda (entry)
                  (let ((sexp (cdr entry)))
                    (when (and (pair? sexp) (eq? 'flow2 (car sexp))
                               (pair? (cdr sexp))
                               (eq? 'uncaught (cadr sexp)))
                      (report! sexp)
                      (flow-latch-fire! failures sexp))))
                entries)))
  (flow-run
   (lambda (workers)
     (flow-spawn (lambda () (raise 'boom)))
     (set! woke (flow-perform
                 (flow-choice (flow-latch-wait failures)
                              (flow-wrap (flow-timeout 2.0)
                                         (lambda (_) 'timed-out)))))
     ;; the sink is the loop's, so starting or stopping one from a
     ;; compute thread during a run is refused
     (let ((done (make-flow-channel 'done)))
       (flow-submit! (car workers)
                     (lambda ()
                       (flow-put! done
                                  (guard (ex ((flow-error-wrong-thread? ex)
                                              'wrong-thread))
                                    (flow-log-stop!)
                                    'not-refused))))
       (set! off-loop-start (flow-get! done)))
     (flow-stop))
   1)
  (flow-log-stop!)
  (assert (equal? woke '(flow2 uncaught fiber boom)))
  (assert (equal? (unbox reported) '((flow2 uncaught fiber boom))))
  (assert (pair? (unbox sink-threads)))
  (assert (for-all (lambda (id) (eqv? id main)) (unbox sink-threads)))
  (assert (eq? off-loop-start 'wrong-thread))
  #t)

;; A sink that raises is unregistered, and its batch stays in the log
;; with the reason -- the procedure counterpart of a flush thread whose
;; port failed.
(define (~check-flow2-000/a-raising-procedure-sink-keeps-its-batch)
  (define calls (box 0))
  (flow-log-drain!)
  (flow-log-start! 0.01
    (lambda (entries)
      (set-box! calls (+ 1 (unbox calls)))
      (error 'sink "refused")))
  (flow-run
   (lambda (workers)
     (flow-log '(flow2-check kept))
     (flow-sleep 0.1)
     (flow-stop)))
  (flow-log-stop!)
  (assert (= 1 (unbox calls)))
  (let ((sexps (map cdr (flow-log-drain!))))
    (assert (member '(flow2-check kept) sexps))
    (assert (exists (lambda (x)
                      (and (pair? x) (pair? (cdr x))
                           (eq? 'log-flush-raised (cadr x))))
                    sexps)))
  #t)

;;------------------------------------------------------------
;; Seventh adverse pass
;;------------------------------------------------------------

;; A channel outlives the run that parked a fiber on it. The fiber's
;; getter used to stay on the channel marked waiting, so a put in the
;; next run handed the value to it and resumed run 1's fiber inside
;; run 2, while run 2's reader found the channel empty.
(define (~check-flow2-002/a-dead-runs-getter-takes-nothing)
  (define ch (make-flow-channel 'shared))
  (define run1-got 'never)
  (define run2-got 'not-set)
  (flow-run
   (lambda (_)
     (flow-spawn (lambda () (set! run1-got (flow-get! ch))))
     (flow-sleep 0.01)
     (flow-stop)))
  (flow-run
   (lambda (_)
     (flow-put! ch 'for-run-2)
     (flow-sleep 0.01)
     (set! run2-got (flow-get-try ch 'empty))
     (flow-stop)))
  (assert (eq? run2-got 'for-run-2))
  (assert (eq? run1-got 'never))
  #t)

;; Priming a channel between runs is documented as legitimate, and the
;; put used to go to the previous run's dead getter instead of the
;; queue.
(define (~check-flow2-002/priming-between-runs-is-not-eaten)
  (define ch (make-flow-channel 'primed))
  (define got 'not-set)
  (flow-run
   (lambda (_)
     (flow-spawn (lambda () (flow-get! ch)))
     (flow-sleep 0.01)
     (flow-stop)))
  (flow-put! ch 'primed)
  (assert (= 1 (flow-channel-queue-length ch)))
  (flow-run
   (lambda (_)
     (set! got (flow-get-try ch 'empty))
     (flow-stop)))
  (assert (eq? got 'primed))
  #t)

;; A putter parked on a full channel when its run stopped used to be
;; woken by the next run's dequeue and push its stale value in.
(define (~check-flow2-002/a-dead-runs-putter-pushes-nothing)
  (define ch (make-flow-channel 'full 1))
  (define seen '())
  (flow-run
   (lambda (_)
     (flow-put! ch 'run-1-first)
     (flow-spawn (lambda () (flow-put! ch 'run-1-stale)))
     (flow-sleep 0.01)
     (flow-stop)))
  (assert (= 1 (flow-channel-space-length ch)))
  (flow-run
   (lambda (_)
     (set! seen (list (flow-get! ch)))
     (flow-sleep 0.01)
     (set! seen (cons (flow-get-try ch 'empty) seen))
     (flow-stop)))
  (assert (equal? seen '(empty run-1-first)))
  #t)

;; Same for a latch: firing it in run 2 used to resume run 1's waiter
;; inside run 2.
(define (~check-flow2-013/a-dead-runs-latch-waiter-stays-dead)
  (define latch (make-flow-latch))
  (define run1-woke #f)
  (define run2-got 'not-set)
  (flow-run
   (lambda (_)
     (flow-spawn (lambda () (flow-latch-wait! latch) (set! run1-woke #t)))
     (flow-sleep 0.01)
     (flow-stop)))
  (flow-run
   (lambda (_)
     (flow-latch-fire! latch 'go)
     (set! run2-got (flow-latch-wait! latch))
     (flow-sleep 0.01)
     (flow-stop)))
  (assert (eq? run2-got 'go))
  (assert (not run1-woke))
  #t)

;; flow-stop with tasks queued on a worker: the stop sentinel used to be
;; queued behind them, so the worker ran them all first -- past the join
;; deadline, with the eventfd leaked and the tasks replying to nobody.
(define (~check-flow2-005/flow-stop-does-not-run-queued-tasks)
  (define ran (box 0))
  (define started (make-flow-latch))
  (flow-log-drain!)
  (let ((t0 (real-time)))
    (flow-run
     (lambda (workers)
       (do ((i 0 (+ i 1))) ((= i 6))
         (flow-submit! (car workers)
                       (lambda ()
                         (flow-latch-fire! started #t)
                         (sleep (make-time 'time-duration 300000000 0))
                         (set-box! ran (+ 1 (unbox ran))))))
       ;; the first task is running, five are queued behind it
       (flow-latch-wait! started)
       (flow-stop))
     1)
    (let ((took (- (real-time) t0)))
      (assert (< took 1500))
      ;; the running task finished; the queued ones never started
      (assert (= 1 (unbox ran)))
      (sleep (make-time 'time-duration 500000000 0))
      (assert (= 1 (unbox ran)))
      (assert (not (exists (lambda (e)
                             (and (pair? (cdr e)) (pair? (cddr e))
                                  (eq? 'shutdown-workers-still-running
                                       (caddr e))))
                           (flow-log-drain!))))))
  #t)

;; A recv that fails while its read is losing a choice. The failure used
;; to be dropped on the theory that it is level-triggered like EOF, but
;; Linux reports ECONNRESET once and the next recv returns 0: the reader
;; saw a clean EOF (#t) where the peer had reset the connection. Same
;; forcing as read-losing-a-same-tick-race-keeps-its-bytes: the peer
;; resets inside the window, with the loop held busy, so the timeout and
;; the failed recv complete in one tick.
(define %flow2-check-setsockopt
  (foreign-procedure "setsockopt" (int int int u8* int) int))
(define %flow2-check-close (foreign-procedure "close" (int) int))

(define (flow2-check-reset! fd)
  ;; struct linger { int l_onoff = 1; int l_linger = 0; }: close sends RST
  (let ((linger (make-bytevector 8 0)))
    (bytevector-s32-native-set! linger 0 1)
    (%flow2-check-setsockopt fd 1 13 linger 8)  ; SOL_SOCKET, SO_LINGER
    (%flow2-check-close fd)))

(define (~check-flow2-006/a-failure-losing-a-race-is-not-an-eof)
  (define PORT 18252)
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
                (flow-sleep 0.01)
                (let ((t0 (real-time)))
                  (flow2-check-spin-until (+ t0 70))
                  (flow2-check-reset! fd)
                  (flow2-check-spin-until (+ t0 100)))))))))))
  ;; the reset is reported as a failure exactly once, and never as EOF
  (assert (not (equal? first-race '(read #t))))
  (assert (not (equal? second-read '(read #t))))
  (assert (or (equal? first-race '(read #f)) (equal? second-read '(read #f))))
  #t)

;; Joining and leaving a waiter list used to be append and remq, linear
;; in the number already parked: 1000 losing waits took ~13ms with 100
;; fibers parked on the same latch or channel and ~98ms with 20000. The
;; lists are doubly linked now. The margin is generous on purpose -- the
;; old code was 7.5x slower, so 3x plus a scheduling allowance still
;; catches it without flaking on a loaded machine.
(define (flow2-check-time-losing-waits parked rounds make-wait)
  (let ((elapsed 0))
    (flow-run
     (lambda (_)
       (do ((i 0 (+ i 1))) ((= i parked))
         (flow-spawn (lambda () (flow-perform (make-wait)))))
       (flow-sleep 0.05)
       (let ((t0 (real-time)))
         (do ((i 0 (+ i 1))) ((= i rounds))
           (flow-perform (flow-choice (make-wait) (flow-timeout 0))))
         (set! elapsed (- (real-time) t0)))
       (flow-stop)))
    elapsed))

(define (~check-flow2-002/waiting-costs-the-same-however-many-wait)
  (define latch (make-flow-latch))
  (define ch (make-flow-channel 'many #f))
  (define (flat? make-wait)
    (let ((few (flow2-check-time-losing-waits 100 1000 make-wait))
          (many (flow2-check-time-losing-waits 20000 1000 make-wait)))
      (< many (+ (* 3 few) 20))))
  (assert (flat? (lambda () (flow-latch-wait latch))))
  (assert (flat? (lambda () (flow-get ch))))
  #t)


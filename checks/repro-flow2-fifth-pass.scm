;; Reproducers for the 2026-09-03 adverse review of (letloop flow2),
;; the fifth pass, run against dev @ 2a77f72. Written as a library of
;; ~check- procedures so they can be run with
;;
;;   letloop check ./src/ ./checks/ ./checks/repro-flow2-fifth-pass.scm
;;
;; and each one PASSES only when the library behaves as documented --
;; so a run against the tree as it was on 2026-09-03 is a list of the
;; findings. Each check also PRINTS what it observed, so a failure comes
;; with its evidence.
;;
;; ALL ARE NOW FIXED (2026-09-18), and each has a regression check in
;; flow2.check.scm:
;;
;;   1, 2  ~check-flow2-005/coalesced-wakes-do-not-inflate-the-eventfd
;;   3     ~check-flow2-001/wrap-runs-on-the-performer-after-commit
;;   4     ~check-flow2-005/wrap-runs-on-the-loop-when-a-worker-delivers
;;   5     ~check-flow2-005/every-entry-point-refuses-a-stray-thread
;;   6     ~check-flow2-005/straggler-does-not-corrupt-the-next-run
;;   7     ~check-flow2-000/log-flush-writes-to-the-port-current-at-start
;;
;; What is kept here is the original reproduction of each, in the shape
;; it was first written, because the shape is the argument. Finding 2 in
;; particular -- a worker blocked in write(2) once the eventfd cell had
;; been multiplied past 2^63 -- takes a couple of seconds of coalesced
;; wakes to reach and is the consequence the in-library check only
;; asserts the cause of.
;;
;; Run under `timeout`: on the unfixed tree check 2 could hang flow-run
;; at shutdown, which was part of the finding.
(library (repro-flow2-fifth-pass)
  (export ~check-repro/eventfd-counter-feeds-back-into-its-own-buffer
          ~check-repro/eventfd-saturation-blocks-worker-writes
          ~check-repro/wrap-raise-lands-on-the-putter-not-the-getter
          ~check-repro/wrap-runs-on-the-worker-thread
          ~check-repro/buffer-size-from-a-stray-thread-is-not-refused
          ~check-repro/straggler-strands-a-fiber-of-the-next-run
          ~check-repro/log-flush-thread-ignores-a-later-parameterize)
  (import (chezscheme)
          (letloop flow2))

  (define (say . xs)
    (for-each (lambda (x) (display x (current-error-port))) xs)
    (newline (current-error-port))
    (flush-output-port (current-error-port)))

  (define (spin-until ms)
    (let spin () (when (< (real-time) ms) (spin))))

  (define (nap-ms ms)
    (sleep (make-time 'time-duration
                      (* (mod ms 1000) 1000000)
                      (div ms 1000))))

  ;; -- 1. The pool's eventfd buffer was both the write source and the
  ;;       read target. -------------------------------------------------
  ;;
  ;; <flow2-pool> said: "The buffer is one 8-byte cell holding the
  ;; value 1, allocated with the eventfd and never written from Scheme
  ;; again". True of Scheme; false of the kernel: %eventfd-wait prepped
  ;; io_uring_prep_read(eventfd, THAT SAME BUFFER, 8), and an eventfd
  ;; read stores the counter into the buffer and resets the counter.
  ;; So after the first wake the cell held whatever count the read
  ;; returned, and every later %eventfd-signal! added THAT to the
  ;; counter instead of 1. Whenever k signals coalesced between two
  ;; collector reads the cell was multiplied by k; it never shrank.
  ;;
  ;; Observed through /proc/self/fdinfo, which reports the eventfd's
  ;; live counter. With a unit cell it is the number of signals in the
  ;; busy window (a dozen here); with the shared cell it read 589824 by
  ;; the sixth window.
  (define (eventfd-counts)
    ;; every eventfd this process holds, as (fd . count)
    (let loop ((names (directory-list "/proc/self/fd")) (out '()))
      (if (null? names)
          out
          (let* ((name (car names))
                 (info (guard (ex (#t #f))
                         (call-with-input-file
                             (string-append "/proc/self/fdinfo/" name)
                           get-string-all))))
            (loop (cdr names)
                  (let find ((i 0))
                    (cond
                     ((or (not info)
                          (> (+ i 14) (string-length info)))
                      out)
                     ((string=? "eventfd-count:" (substring info i (+ i 14)))
                      (let* ((rest (substring info (+ i 14) (string-length info)))
                             (hex (let trim ((s rest))
                                    (cond
                                     ((and (> (string-length s) 0)
                                           (char-whitespace? (string-ref s 0)))
                                      (trim (substring s 1 (string-length s))))
                                     (else
                                      (let end ((j 0))
                                        (if (or (= j (string-length s))
                                                (char-whitespace? (string-ref s j)))
                                            (substring s 0 j)
                                            (end (+ j 1)))))))))
                        (cons (cons (string->number name)
                                    (string->number hex 16))
                              out)))
                     (else (find (+ i 1))))))))))

  (define (max-count counts)
    (apply max 0 (map cdr counts)))

  ;; One busy window: WORKERS loop fibers park on their own channels,
  ;; WORKERS tasks put to them at about the same moment while the loop
  ;; is held busy for SPIN-MS, so their wakes coalesce. Returns the
  ;; largest eventfd counter seen at the end of the window.
  (define (coalescing-round ws spin-ms)
    (let* ((workers (length ws))
           (channels (map (lambda (i) (make-flow-channel (cons 'ch i) 4))
                          (iota workers)))
           (arrived (box 0)))
      (for-each (lambda (ch)
                  (flow-spawn
                   (lambda ()
                     (flow-get! ch)
                     (set-box! arrived (+ 1 (unbox arrived))))))
                channels)
      (flow-sleep 0.01)
      (for-each (lambda (w ch)
                  (flow-submit! w
                                (lambda () (nap-ms 10) (flow-put! ch 'x))
                                (make-flow-channel 'resp)))
                ws channels)
      (spin-until (+ (real-time) spin-ms))
      (let ((seen (max-count (eventfd-counts))))
        (let settle ((n 0))
          (when (and (< (unbox arrived) workers) (< n 300))
            (flow-sleep 0.01)
            (settle (+ n 1))))
        seen)))

  (define (~check-repro/eventfd-counter-feeds-back-into-its-own-buffer)
    (define workers 4)
    (define rounds 10)
    (define counts '())
    (flow-run
     (lambda (ws)
       (say "eventfds before any cross-thread wake: " (eventfd-counts))
       (let round ((r 1))
         (when (<= r rounds)
           (let ((seen (coalescing-round ws 80)))
             (set! counts (cons seen counts))
             (say "round " r " eventfd counter at the end of the busy window: " seen))
           (round (+ r 1))))
       (flow-stop))
     workers)
    (let ((peak (apply max counts)))
      (say "counter per window: " (reverse counts) "; peak " peak)
      ;; a handful of resumes' worth of unit signals, not their product
      (assert (<= peak 64)))
    #t)

  ;; -- 2. ... and once the cell passed 2^63, a worker's write(2)
  ;;       blocked until the loop's next tick. ---------------------------
  ;;
  ;; Measured from inside a task: the time two consecutive flow-put!s to
  ;; two parked loop fibers take to RETURN, while the loop is held busy
  ;; for 300 ms. A put's wake is fire-and-forget, so both must return at
  ;; once, before and after a few dozen coalescing windows. With the
  ;; shared cell the windows drove it to 2^64 in about twenty rounds and
  ;; the second put then sat in write(2) for the rest of the busy
  ;; window: 290 ms against 0. The final flow-stop could then hang too:
  ;; %flow-shutdown-pool!'s own %eventfd-signal! added the same huge
  ;; cell, and if a worker's signal was still pending that write blocked
  ;; on the loop thread with nothing left to read it.
  (define (two-puts-elapsed-ms ws spin-ms)
    (define a (make-flow-channel 'a 4))
    (define b (make-flow-channel 'b 4))
    (define elapsed (box #f))
    (define arrived (box 0))
    (flow-spawn (lambda () (flow-get! a) (set-box! arrived (+ 1 (unbox arrived)))))
    (flow-spawn (lambda () (flow-get! b) (set-box! arrived (+ 1 (unbox arrived)))))
    (flow-sleep 0.01)
    (flow-submit! (car ws)
                  (lambda ()
                    (nap-ms 10)
                    (let ((t0 (real-time)))
                      (flow-put! a 'x)
                      (flow-put! b 'y)
                      (set-box! elapsed (- (real-time) t0))))
                  (make-flow-channel 'resp))
    (spin-until (+ (real-time) spin-ms))
    (let settle ((n 0))
      (when (and (or (< (unbox arrived) 2) (not (unbox elapsed))) (< n 300))
        (flow-sleep 0.01)
        (settle (+ n 1))))
    (unbox elapsed))

  (define (~check-repro/eventfd-saturation-blocks-worker-writes)
    (define workers 4)
    (define rounds 25)
    (define before 'unset)
    (define after 'unset)
    (define peak 0)
    (flow-run
     (lambda (ws)
       (set! before (two-puts-elapsed-ms ws 300))
       (say "two puts from a worker, loop busy 300 ms, fresh pool: " before " ms")
       ;; ~12x per window with the shared cell, so 25 windows is past
       ;; 2^63 with margin; with the unit cell the peak stays a dozen
       (let round ((r 1))
         (when (<= r rounds)
           (set! peak (max peak (coalescing-round ws 30)))
           (round (+ r 1))))
       (say "peak counter over " rounds " windows: " peak
            " (2^" (exact (round (/ (log (max peak 1)) (log 2)))) ")")
       (set! after (two-puts-elapsed-ms ws 300))
       (say "two puts from a worker, loop busy 300 ms, after those windows: " after " ms")
       (say "calling flow-stop; if the next line never prints, flow-run hung in %flow-shutdown-pool!'s eventfd write")
       (flow-stop))
     workers)
    (say "flow-run returned")
    ;; generous slack over the 10 ms nap for scheduling; the failure
    ;; mode is the whole 300 ms window
    (assert (and (number? before) (< before 100)))
    (assert (and (number? after) (< after 100)))
    (assert (<= peak 64))
    #t)

  ;; -- 3. flow-wrap's PROC ran on the deliverer, before commitment. ----
  ;;
  ;; README, flow-wrap, then: "Returns an event that synchronizes as
  ;; EVENT does and applies PROC to the result." Nothing said on which
  ;; stack. In the block path the wrap was applied inside the base's
  ;; resume, i.e. by whoever completed the rendezvous -- the fiber
  ;; calling flow-put!, a completion handler on the scheduler, or a
  ;; compute thread -- and BEFORE resume-from's CAS. A PROC that raised
  ;; therefore raised in the putter, the getter was never resumed, and
  ;; the value was gone. The same program with the value already queued
  ;; (try path) raised in the getter, as CML says it should. The README
  ;; now says where PROC runs, and both paths agree.
  (define (~check-repro/wrap-raise-lands-on-the-putter-not-the-getter)
    (define ch (make-flow-channel 'wrapped))
    (define getter-outcome 'never-resumed)
    (define putter-outcome 'not-set)
    (define try-path-outcome 'not-set)
    (define (bad-wrap v) (error 'wrap "boom on " v))
    (flow-run
     (lambda (ws)
       ;; try path first, for contrast: the value is already there
       (flow-put! ch 'queued)
       (set! try-path-outcome
             (guard (ex (#t (list 'getter-raised (condition-who ex))))
               (flow-perform (flow-wrap (flow-get ch) bad-wrap))))
       ;; block path: the getter parks, then a sibling puts
       (flow-spawn
        (lambda ()
          (set! getter-outcome
                (guard (ex (#t (list 'getter-raised (condition-who ex))))
                  (list 'got (flow-perform (flow-wrap (flow-get ch) bad-wrap)))))))
       (flow-sleep 0.01)
       (set! putter-outcome
             (guard (ex (#t (list 'putter-raised (condition-who ex))))
               (flow-put! ch 'delivered)
               'put-returned))
       (flow-sleep 0.05)
       (flow-stop)))
    (say "try path:   " try-path-outcome)
    (say "block path: putter " putter-outcome ", getter " getter-outcome
         ", queued " (flow-channel-queue-length ch)
         ", getters " (flow-channel-getters-length ch))
    (assert (equal? try-path-outcome '(getter-raised wrap)))
    (assert (eq? putter-outcome 'put-returned))
    (assert (equal? getter-outcome '(getter-raised wrap)))
    #t)

  ;; -- 4. ... and when the deliverer was a compute thread, PROC ran
  ;;       there. ---------------------------------------------------------
  ;;
  ;; README, Rationale: "There is no API through which a compute thread
  ;; can reach the loop's state, so the bug class cannot be written."
  ;; A wrap handed to a loop-side flow-get was exactly that API: the
  ;; worker that put ran it. Here the wrap reports the thread it ran on,
  ;; and a second wrap calls flow-spawn -- which used to raise
  ;; wrong-thread into the WORKER's flow-put!, be converted by the task
  ;; guard into a compute error reply, and leave the loop fiber parked.
  (define (~check-repro/wrap-runs-on-the-worker-thread)
    (define ch (make-flow-channel 'tid))
    (define ch2 (make-flow-channel 'spawn))
    (define resp (make-flow-channel 'resp 8))
    (define loop-tid (get-thread-id))
    (define wrap-tid 'not-set)
    (define second-outcome 'never-resumed)
    (define reply 'not-set)
    (flow-run
     (lambda (ws)
       (flow-spawn
        (lambda ()
          (set! wrap-tid
                (flow-perform (flow-wrap (flow-get ch)
                                         (lambda (v) (get-thread-id)))))))
       (flow-spawn
        (lambda ()
          (set! second-outcome
                (guard (ex (#t (list 'raised ex)))
                  (flow-perform
                   (flow-wrap (flow-get ch2)
                              (lambda (v)
                                (flow-spawn (lambda () (void)))
                                'spawned-from-wrap)))))))
       (flow-sleep 0.01)
       (flow-submit! (car ws)
                     (lambda () (flow-put! ch 'x) (flow-put! ch2 'y) (flow-put! resp 'task-ok))
                     resp)
       (set! reply (flow-perform (flow-choice (flow-get resp)
                                              (flow-wrap (flow-timeout 0.5)
                                                         (lambda (_) 'no-reply)))))
       (flow-sleep 0.05)
       (flow-stop))
     1)
    (say "loop thread " loop-tid ", wrap ran on thread " wrap-tid)
    (say "second wrap (calls flow-spawn): loop fiber saw " second-outcome
         "; worker's reply: "
         (if (flow-error? reply)
             (list 'flow-error (flow-error-symbol reply)
                   (let ((c (flow-error-cause reply)))
                     (and (flow-error? c) (flow-error-symbol c))))
             reply))
    (assert (eqv? wrap-tid loop-tid))
    (assert (eq? second-outcome 'spawned-from-wrap))
    (assert (eq? reply 'task-ok))
    #t)

  ;; -- 5. flow-channel-buffer-size! from a thread the user forked. -----
  ;;
  ;; README, Threads: "Every flow2 operation raises wrong-thread when
  ;; called from one." flow-channel-buffer-size! wakes the putters the
  ;; new bound admits, and a wake is a resume: on a stray thread that is
  ;; %flow-spawn-safe -> loop-spawn, the unsynchronized mutation of the
  ;; loop's thunk list the guard exists to prevent. It carried no guard
  ;; -- the fourth pass's enumeration lesson, one procedure over.
  (define (~check-repro/buffer-size-from-a-stray-thread-is-not-refused)
    (define ch (make-flow-channel 'grown 1))
    (define outcome (box 'not-set))
    (define putter-done (box #f))
    (define resumed-at 'never)
    (flow-run
     (lambda (ws)
       (flow-put! ch 1)                                     ; at the bound
       (flow-spawn (lambda () (flow-put! ch 2) (set-box! putter-done #t)))
       (flow-sleep 0.01)                                    ; it parks
       (fork-thread
        (lambda ()
          (set-box! outcome
                    (guard (ex (#t (if (flow-error? ex) (flow-error-symbol ex) ex)))
                      (flow-channel-buffer-size! ch 4)
                      'no-raise))))
       (let wait ((n 0))
         (flow-sleep 0.01)
         (when (unbox putter-done) (set! resumed-at (* n 10)))
         (if (or (unbox putter-done) (> n 50))
             (flow-stop)
             (wait (+ n 1))))))
    (say "stray-thread flow-channel-buffer-size!: " (unbox outcome)
         "; parked putter resumed after ~" resumed-at " ms")
    (assert (eq? 'wrong-thread (unbox outcome)))
    ;; refused, so the bound did not move and the putter stayed parked
    (assert (eqv? 1 (flow-channel-bound ch)))
    (assert (not (unbox putter-done)))
    #t)

  ;; -- 6. A straggler could reach the NEXT run through a shared channel.
  ;;
  ;; <flow2-pool> said: "a straggler can only ever touch the run that
  ;; created it: its signals land on its own leaked fd, its thunks in a
  ;; mailbox nobody drains (a dead run's resumes SHOULD be dropped)".
  ;; The resume it dropped was not necessarily a dead run's. A channel
  ;; is a plain object; if the straggler's task holds one the next run
  ;; also uses -- a global, as in every check in this repository -- its
  ;; flow-put! popped the NEW run's parked getter, handed the value to a
  ;; continuation consed into the dead mailbox, and returned #t. The new
  ;; run's fiber parked forever -- past its own deadline, since the dead
  ;; resume had already won the state CAS -- and the value was gone. A
  ;; straggler is refused now, like the stray thread it is to the live
  ;; run.
  (define shared (make-flow-channel 'shared-across-runs 4))

  (define (~check-repro/straggler-strands-a-fiber-of-the-next-run)
    (define straggler-put 'not-yet)
    (define got 'never)
    (flow-log-drain!)
    ;; run 1: the task outlives the 2 s shutdown join
    (flow-run
     (lambda (ws)
       (flow-submit! (car ws)
                     (lambda ()
                       (nap-ms 2600)
                       (set! straggler-put
                             (guard (ex (#t (if (flow-error? ex)
                                                (flow-error-symbol ex)
                                                (list 'raised ex))))
                               (flow-put! shared 'from-the-dead-run)
                               'returned)))
                     (make-flow-channel 'resp))
       (flow-sleep 0.05)
       (flow-stop))
     1)
    (assert (pair? (filter (lambda (e) (and (pair? e)
                                           (eq? (cadr e) 'shutdown-workers-still-running)))
                           (map cdr (flow-log-drain!)))))
    ;; run 2 starts ~2.05 s after run 1's flow-stop; the straggler's put
    ;; lands ~0.5 s into it, while this fiber is parked on the channel
    (flow-run
     (lambda (ws)
       (flow-spawn
        (lambda ()
          (set! got (flow-perform
                     (flow-choice (flow-get shared)
                                  (flow-wrap (flow-timeout 2.0)
                                             (lambda (_) 'timed-out-waiting)))))))
       (let wait ((n 0))
         (flow-sleep 0.05)
         (if (or (not (eq? got 'never)) (> n 60))
             (flow-stop)
             (wait (+ n 1)))))
     1)
    (say "straggler's flow-put! into the live run: " straggler-put
         "; live fiber got: " got
         "; left in channel: " (flow-channel-queue-length shared))
    ;; refused at the source, and the live fiber's own deadline still
    ;; reached it
    (assert (eq? straggler-put 'wrong-thread))
    (assert (eq? got 'timed-out-waiting))
    (assert (eqv? 0 (flow-channel-queue-length shared)))
    #t)

  ;; -- 7. The flush thread read current-error-port at flush time, on
  ;;       ITS thread. -----------------------------------------------------
  ;;
  ;; README, flow-log-start!, then: "The port is read at flush time, not
  ;; captured at start, so reparameterizing it is honored on the next
  ;; cycle." current-error-port is a thread parameter in Chez: a thread
  ;; forked before the parameterize keeps the value it inherited at fork
  ;; time. So the documented shape -- start the flusher at program
  ;; start, redirect stderr later -- wrote to the old port. The README
  ;; now says the port is captured at start, on the calling thread, and
  ;; names the two remedies: start inside the parameterize (which the
  ;; old code happened to honour too, since the thread inherited the
  ;; port at fork), or pass the port -- the form that did not exist,
  ;; asserted here. The call goes through an apply cp0 cannot fold,
  ;; because on the unfixed tree a visible two-argument call is an arity
  ;; warning that stops `letloop check` from finding any check at all.
  (define (~check-repro/log-flush-thread-ignores-a-later-parameterize)
    (define later (open-output-string))
    (define explicit (open-output-string))
    (flow-log-drain!)
    ;; the original shape: started first, redirected later
    (flow-log-start! 0.02)
    (parameterize ((current-error-port later))
      (flow-log '(fifth-pass redirected-after-start))
      (nap-ms 150))
    (flow-log-stop!)
    ;; get-output-string DRAINS a Chez string port: read each one once
    (let ((text (get-output-string later)))
      (say "redirected after start, captured: " (string-length text)
           " chars (the entry above, if any, went to the ORIGINAL stderr, as now documented)"))
    ;; the documented remedy: name the port
    (apply flow-log-start! (vector->list (vector 0.02 explicit)))
    (flow-log '(fifth-pass explicit-port))
    (flow-log-stop!)
    (let ((text (get-output-string explicit)))
      (say "explicit port, captured: " (string-length text) " chars")
      (assert (> (string-length text) 0)))
    #t)
  )

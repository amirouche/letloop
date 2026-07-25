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
      (make-flow-channel-entry state (lambda (v) #f) i (box #f))))
  (define (build-list n f)
    (let loop ((i 0) (acc '()))
      (if (fx=? i n) acc (loop (fx+ i 1) (cons (f i) acc)))))
  (set-box! (flow-channel-puts ch) (build-list 5 dead-entry))
  (let loop ((i 0))
    (when (fx<? i %flow-channel-gc-threshold)
      (flow-channel-bump-gc! ch)
      (loop (fx+ i 1))))
  (null? (unbox (flow-channel-puts ch))))

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

;;------------------------------------------------------------
;; File I/O (flow-open / flow-read-at / flow-write-at / flow-close)
;;------------------------------------------------------------

;; Under /tmp/letloop so `make clean` sweeps anything a crashed check
;; leaves behind; each check also deletes its own file on the way out.
(define %flow-check-directory "/tmp/letloop")

(define (flow-check-path name)
  (unless (file-exists? %flow-check-directory)
    (mkdir %flow-check-directory))
  (string-append %flow-check-directory "/" name))

(define (flow-check-remove! path)
  (when (file-exists? path)
    (delete-file path)))

;; Deterministic filler, so a mis-offset read is caught by content and
;; not merely by length.
(define (flow-check-bytes size)
  (let ((bv (make-bytevector size)))
    (let loop ((i 0))
      (if (fx=? i size)
          bv
          (begin (bytevector-u8-set! bv i (fxmod (fx* i 7) 251))
                 (loop (fx+ i 1)))))))

(define (flow-check-concatenate bvs)
  (let ((out (make-bytevector (apply + (map bytevector-length bvs)))))
    (let loop ((bvs bvs) (offset 0))
      (if (null? bvs)
          out
          (let ((n (bytevector-length (car bvs))))
            (bytevector-copy! (car bvs) 0 out offset n)
            (loop (cdr bvs) (fx+ offset n)))))))

;; flow-write-at reports what it actually wrote rather than looping, so
;; a caller that wants "all of it" writes the loop itself — as here.
(define (flow-check-write-all fd offset bv)
  (let loop ((offset offset) (bv bv))
    (let ((n (flow-perform (flow-write-at fd offset bv))))
      (cond
       ((not n) #f)
       ((fx=? n (bytevector-length bv)) #t)
       (else (loop (fx+ offset n) (subbytevector bv n)))))))

(define (flow-check-create! path bv)
  (let ((fd (flow-perform
             (flow-open path (fxior O-WRONLY O-CREAT O-TRUNC) #o600))))
    (and fd
         (let ((ok (flow-check-write-all fd 0 bv)))
           (flow-perform (flow-close fd))
           ok))))

;; Round trip through a real file: create + write + close, then reopen
;; read-only and read the whole thing back in one call.
(define (~check-flow-009/file-write-read-roundtrip)
  (define path (flow-check-path "flow-009-roundtrip.bin"))
  (define payload (string->utf8 "the quick brown fox jumps over the lazy dog"))
  (define written #f)
  (define result #f)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (let ((fd (flow-perform
                (flow-open path (fxior O-WRONLY O-CREAT O-TRUNC) #o600))))
       (set! written (flow-perform (flow-write-at fd 0 payload)))
       (flow-perform (flow-close fd)))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (set! result (flow-perform (flow-read-at fd 0 65536)))
       (flow-perform (flow-close fd)))
     (loop-stop)))
  (loop-run)
  (flow-check-remove! path)
  (and (eqv? written (bytevector-length payload))
       (equal? result payload)))

;; A file deliberately larger than the chunk size and not a multiple of
;; it: the loop must see two full chunks, one short chunk, and then
;; 'eof — the caller tracking its own offset the whole way, since these
;; primitives keep no cursor.
(define (~check-flow-009/chunked-read-until-eof)
  (define path (flow-check-path "flow-009-chunked.bin"))
  (define chunk 4096)
  (define payload (flow-check-bytes 10000))
  (define created #f)
  (define pieces '())
  (define saw-eof #f)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! created (flow-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (let read-loop ((offset 0))
         (let ((piece (flow-perform (flow-read-at fd offset chunk))))
           (cond
            ((eq? piece 'eof) (set! saw-eof #t))
            ((not piece) (void))       ;; error: fall through, check fails
            (else
             (set! pieces (cons piece pieces))
             (read-loop (fx+ offset (bytevector-length piece)))))))
       (flow-perform (flow-close fd)))
     (loop-stop)))
  (loop-run)
  (flow-check-remove! path)
  (let ((pieces (reverse pieces)))
    (and created
         saw-eof
         (fx=? (length pieces) 3)                       ;; 4096 + 4096 + 1808
         (fx=? (bytevector-length (list-ref pieces 2)) 1808)
         (equal? (flow-check-concatenate pieces) payload))))

;; Neither the write nor the read starts at 0: the marker must land at
;; exactly OFFSET (the head of the file untouched), and reading it back
;; from OFFSET must return it — an offset silently ignored would fail
;; both halves.
(define (~check-flow-009/nonzero-offset)
  (define path (flow-check-path "flow-009-offset.bin"))
  (define offset 4000)
  (define payload (flow-check-bytes 8192))
  (define marker (string->utf8 "MARKER-AT-4000"))
  (define created #f)
  (define patched #f)
  (define read-back #f)
  (define head #f)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! created (flow-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDWR 0))))
       (set! patched (flow-perform (flow-write-at fd offset marker)))
       (set! read-back (flow-perform
                        (flow-read-at fd offset (bytevector-length marker))))
       (set! head (flow-perform (flow-read-at fd 0 16)))
       (flow-perform (flow-close fd)))
     (loop-stop)))
  (loop-run)
  (flow-check-remove! path)
  (and created
       (eqv? patched (bytevector-length marker))
       (equal? read-back marker)
       (equal? head (subbytevector payload 0 16))))

;; The file-fd counterpart of ~check-flow-006/read-or-timeout-leaves-fd-
;; usable. A regular-file read cannot be made to hang the way a silent
;; socket can, so which base wins is genuinely racy here (a 0-second
;; timeout against an already-satisfiable read) and neither outcome is
;; asserted; what is asserted is the part that matters — after the
;; choice resolves, whichever way it went, a plain flow-read-at on the
;; same fd still returns the right bytes, so a losing/cancelled read
;; leaves neither the fd nor the loop's handler table in a half-
;; submitted state.
(define (~check-flow-009/read-or-timeout-leaves-fd-usable)
  (define path (flow-check-path "flow-009-choice.bin"))
  (define payload (flow-check-bytes 512))
  (define created #f)
  (define slow #f)
  (define racy #f)
  (define after #f)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! created (flow-check-create! path payload))
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
     (loop-stop)))
  (loop-run)
  (flow-check-remove! path)
  (and created
       (equal? slow payload)
       (or (equal? racy payload) (eq? racy (void)))
       (equal? after payload)))

;; Opening a missing path without O-CREAT must yield #f — the same
;; shape flow-read/flow-write use for failure — rather than hanging or
;; handing back a negative "fd" that would then be used as one.
(define (~check-flow-009/open-nonexistent-fails)
  (define path (flow-check-path "flow-009-does-not-exist.bin"))
  (define result 'not-set)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! result (flow-perform (flow-open path O-RDONLY 0)))
     (loop-stop)))
  (loop-run)
  (eq? result #f))

;; flow-open on the losing side of a choice: the loser-with-success
;; path in flow-open's completion handler must close the fd nobody now
;; owns (detected via resume's #f "did I win" return) rather than leak
;; it. Which base wins each round is genuinely racy (a 0-second
;; timeout against a page-cache openat), so run many rounds and assert
;; the invariant that holds either way: the process's open-fd count is
;; back at its baseline once the dust settles — a leaked orphan would
;; grow it by one per round the timeout won.
(define (~check-flow-009/open-loses-choice-no-fd-leak)
  (define path (flow-check-path "flow-009-open-choice.bin"))
  (define rounds 50)
  (define failures 0)
  (define baseline #f)
  (define final #f)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (flow-check-create! path (flow-check-bytes 64))
     (set! baseline (length (directory-list "/proc/self/fd")))
     (let round ((n 0))
       (unless (fx=? n rounds)
         (let ((r (flow-perform
                   (flow-choice (flow-open path O-RDONLY 0)
                                (flow-timeout 0.0)))))
           (cond
            ((fixnum? r) (flow-perform (flow-close r))) ;; open won: ours to close
            ((eq? r (void)) (void))                     ;; timeout won: orphan path
            (else (set! failures (fx+ failures 1)))))
         (round (fx+ n 1))))
     ;; give straggler orphan-close CQEs from the last rounds a tick
     ;; or two to land before counting
     (flow-sleep 0.05)
     (set! final (length (directory-list "/proc/self/fd")))
     (loop-stop)))
  (loop-run)
  (flow-check-remove! path)
  (and (fxzero? failures)
       (fixnum? baseline)
       (eqv? final baseline)))

;; flow-close composed under flow-choice: per its committed-at-block
;; caveat, once the choice reaches the block phase the close happens
;; whichever base wins — so afterward the fd must actually be closed,
;; and a probe read on it must yield #f (EBADF), never data. Nothing
;; opens another fd between the close and the probe, so the descriptor
;; number cannot have been reused out from under the test.
(define (~check-flow-009/close-under-choice-fd-actually-closed)
  (define path (flow-check-path "flow-009-close-choice.bin"))
  (define created #f)
  (define chosen 'not-set)
  (define after 'not-set)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! created (flow-check-create! path (flow-check-bytes 64)))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       (set! chosen (flow-perform
                     (flow-choice (flow-close fd) (flow-timeout 1.0))))
       ;; in the unlikely event the timeout won, the committed close's
       ;; CQE still needs a tick to land before the probe
       (flow-sleep 0.02)
       (set! after (flow-perform (flow-read-at fd 0 16))))
     (loop-stop)))
  (loop-run)
  (flow-check-remove! path)
  (and created
       (or (eqv? chosen 0) (eq? chosen (void)))
       (eq? after #f)))

;; flow-close while another fiber's flow-read-at is parked on the same
;; fd, both submitted in the same tick: exercises loop-close-block's
;; IORING_OP_ASYNC_CANCEL(CANCEL_ALL) actually matching an in-flight
;; file op. The read's handler lives in loop-handlers only, never
;; %fd-handlers, so the synthetic-resume pass skips it — the real CQE
;; (data, -ECANCELED or -EBADF depending on how the kernel orders the
;; three ops) must come back, unlock the buffer and resume the parked
;; fiber. The assertions are liveness and shape: the reader fiber
;; resumes (not stranded) with either the payload or #f, and the close
;; itself succeeds.
(define (~check-flow-009/close-while-read-in-flight)
  (define path (flow-check-path "flow-009-close-inflight.bin"))
  (define payload (flow-check-bytes 512))
  (define created #f)
  (define read-result 'not-set)
  (define read-done #f)
  (define close-result 'not-set)
  (define close-done #f)
  (flow-check-remove! path)
  (loop-new)
  (loop-spawn
   (lambda ()
     (set! created (flow-check-create! path payload))
     (let ((fd (flow-perform (flow-open path O-RDONLY 0)))
           ;; Both helper fibers park on this channel (nobody ever
           ;; puts) once they are done, instead of returning.
           (parked (make-flow-channel)))
       ;; loop-spawn is LIFO within a tick: spawn the closer first so
       ;; the reader's block runs first next tick and its SQE is
       ;; already prepped (handler parked) when loop-close-block preps
       ;; the cancel + close right after it.
       (loop-spawn
        (lambda ()
          (set! close-result (flow-perform (flow-close fd)))
          (set! close-done #t)
          (flow-perform (flow-get parked))))
       (loop-spawn
        (lambda ()
          (set! read-result (flow-perform (flow-read-at fd 0 512)))
          (set! read-done #t)
          (flow-perform (flow-get parked))))
       (let wait ((n 0))
         (flow-sleep 0.01)
         (if (or (and read-done close-done) (fx>? n 500))
             (loop-stop)
             (wait (fx+ n 1)))))))
  (loop-run)
  (flow-check-remove! path)
  (and created
       read-done
       close-done
       (eqv? close-result 0)
       (or (equal? read-result payload) (eq? read-result #f))))

;; FL-7: a channel shared between two genuinely separate OS threads
;; (shards), each with its own ring — not the same-thread scheduling
;; tricks (spawn order, loop-run-once tick counts) FL-1..FL-6's checks
;; use. shard-b's flow-get! blocks and parks a continuation owned by
;; shard-b; shard-a's flow-put! matches it from a different thread
;; entirely, so resume must route through flow-shard-post! (the
;; mailbox + msg_ring path) rather than loop-spawn — if owner-tracking
;; were wrong this would either hang (never resumed) or crash
;; (continuation invoked on the wrong thread's stack).
(define (~check-flow-007/two-shard-channel-rendezvous)
  (define ch (make-flow-channel))
  (define result (box #f))
  (define done (box #f))
  (define shard-b
    (flow-shard-spawn
     (lambda ()
       (set-box! result (flow-get! ch))
       (set-box! done #t))))
  (define shard-a
    (flow-shard-spawn
     (lambda ()
       (flow-put! ch 'cross-shard-value))))
  (let wait ((n 0))
    (unless (or (unbox done) (fx>=? n 200))
      (sleep (make-time 'time-duration 10000000 0))
      (wait (fx+ n 1))))
  (flow-shard-stop! shard-a)
  (flow-shard-stop! shard-b)
  (sleep (make-time 'time-duration 0 1))
  (eq? (unbox result) 'cross-shard-value))

;; The milestone's stress check: 3 producer shards each spawning 20
;; concurrent put fibers into one shared channel, a 4th collector
;; shard doing all 60 gets. Every rendezvous here crosses shards (the
;; collector's gets almost never land on the same shard as the put
;; that satisfies them), so this exercises the box-cas! channel lists
;; under genuine concurrent cross-thread push/pop and the mailbox
;; wakeup path under real load, not just the single pairing above.
(define (~check-flow-007/stress-n-shards-m-messages)
  (define n-per-shard 20)
  (define shard-ids (list 0 1 2))
  (define total (fx* (length shard-ids) n-per-shard))
  (define ch (make-flow-channel))
  (define received (box '()))
  (define done (box #f))
  (define (shard-range sid)
    (let loop ((i 0) (acc '()))
      (if (fx>=? i n-per-shard)
          acc
          (loop (fx+ i 1) (cons (fx+ (fx* sid 1000) i) acc)))))
  (define expected (apply append (map shard-range shard-ids)))
  (define collector
    (flow-shard-spawn
     (lambda ()
       (let loop ((i 0) (acc '()))
         (if (fx>=? i total)
             (begin (set-box! received acc) (set-box! done #t))
             (loop (fx+ i 1) (cons (flow-get! ch) acc)))))))
  (define producers
    (map (lambda (sid)
           (flow-shard-spawn
            (lambda ()
              (let loop ((i 0))
                (when (fx<? i n-per-shard)
                  (loop-spawn (lambda () (flow-put! ch (fx+ (fx* sid 1000) i))))
                  (loop (fx+ i 1)))))))
         shard-ids))
  (let wait ((n 0))
    (unless (or (unbox done) (fx>=? n 500))
      (sleep (make-time 'time-duration 10000000 0))
      (wait (fx+ n 1))))
  (for-each flow-shard-stop! producers)
  (flow-shard-stop! collector)
  (sleep (make-time 'time-duration 0 1))
  (and (unbox done)
       (equal? (sort < (unbox received)) (sort < expected))))

;; Regression for a real crash under heavy persistent-shard-pool reuse
;; (reproduced by scripts/louds-shard-decode-benchmark.scm in
;; atlas-stoa): flow-shard-post! preps an IORING_OP_MSG_RING SQE on the
;; *poster's own* ring every call, via raw io-uring-get-sqe. That
;; returns NULL once the ring's 256-entry submission queue is full and
;; nothing has submitted yet -- exactly what happens when a fiber posts
;; many times in a tight loop with no suspension in between, since
;; loop-run-once (the only place that calls io_uring_submit) never gets
;; control back until the fiber returns. Posting more than 256 times in
;; one shot from a single fiber invocation reproduces the overflow; the
;; fix (flow-shard-post! using loop-get-sqe, which submits and retries
;; once on NULL, same as every other flow.scm SQE call site) prevents
;; io-uring-prep-msg-ring from ever writing through a NULL pointer.
(define (~check-flow-008/shard-post-sqe-ring-overflow)
  (define n 400) ;; > the ring's 256-entry submission queue
  (define count (box 0))
  (define done (box #f))
  (define (bump!)
    (let ((v (unbox count)))
      (unless (box-cas! count v (fx+ v 1))
        (bump!))))
  (define receiver (flow-shard-spawn (lambda () (void))))
  (define poster
    (flow-shard-spawn
     (lambda ()
       (let loop ((i 0))
         (if (fx>=? i n)
             (set-box! done #t)
             (begin
               (flow-shard-post! receiver bump!)
               (loop (fx+ i 1))))))))
  (let wait ((k 0))
    (unless (or (unbox done) (fx>=? k 500))
      (sleep (make-time 'time-duration 10000000 0))
      (wait (fx+ k 1))))
  (let wait ((k 0))
    (unless (or (fx=? (unbox count) n) (fx>=? k 500))
      (sleep (make-time 'time-duration 10000000 0))
      (wait (fx+ k 1))))
  (flow-shard-stop! poster)
  (flow-shard-stop! receiver)
  (sleep (make-time 'time-duration 0 1))
  (fx=? (unbox count) n))

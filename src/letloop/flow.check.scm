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
     (let ((fd (flow-perform (flow-open path O-RDONLY 0))))
       ;; loop-spawn is LIFO within a tick: spawn the closer first so
       ;; the reader's block runs first next tick and its SQE is
       ;; already prepped (handler parked) when loop-close-block preps
       ;; the cancel + close right after it.
       (loop-spawn
        (lambda ()
          (set! close-result (flow-perform (flow-close fd)))
          (set! close-done #t)))
       (loop-spawn
        (lambda ()
          (set! read-result (flow-perform (flow-read-at fd 0 512)))
          (set! read-done #t)))
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

;; FL-10: flow-log. Basic single-shard accumulate-then-drain round
;; trip — flow-log entries come back in the order they were logged
;; (flow-log-drain! reverses each box's most-recent-first CAS list, see
;; there), oldest first.
(define (~check-flow-010/log-drain-roundtrip)
  (define entries #f)
  (loop-new)
  (loop-spawn
   (lambda ()
     (flow-log 'a)
     (flow-log 'b)
     (flow-log 'c)
     (set! entries (flow-log-drain!))
     (loop-stop)))
  (loop-run)
  (equal? (map cdr entries) '(a b c)))

;; Timestamps come from loop-jiffy (the per-tick cached clock), so
;; entries logged in the same tick can share a timestamp, but the
;; sequence across an intervening flow-sleep (which crosses ticks)
;; must never go backwards.
(define (~check-flow-010/timestamps-non-decreasing)
  (define entries #f)
  (loop-new)
  (loop-spawn
   (lambda ()
     (flow-log 'tick-0)
     (flow-sleep 0.01)
     (flow-log 'tick-1)
     (flow-sleep 0.01)
     (flow-log 'tick-2)
     (set! entries (flow-log-drain!))
     (loop-stop)))
  (loop-run)
  (let ((ts (map car entries)))
    (and (fx=? (length ts) 3)
         (<= (car ts) (cadr ts))
         (<= (cadr ts) (caddr ts)))))

;; flow-log-start! actually reaches (current-error-port) on its own,
;; with no explicit flow-log-drain! call from the test — proves the
;; dedicated flush thread runs and drains independently. Captures
;; current-error-port via parameterize (fork-thread inherits the
;; dynamic binding in effect at fork time, confirmed directly) rather
;; than touching the real stderr. Sleeps a fixed several-periods-worth
;; of wall-clock time rather than polling get-output-string in a loop:
;; a string port is not synchronized, so reading it from this thread
;; while the flush thread might be mid-write would be a real data
;; race, not just a slow poll — read it exactly once, only after
;; flow-log-stop! has returned (which guarantees the flush thread has
;; performed its final flush and exited, so nothing else can be
;; touching the port anymore).
(define (~check-flow-010/start-reaches-destination)
  (define captured (open-output-string))
  (parameterize ((current-error-port captured))
    (loop-new)
    (loop-spawn
     (lambda ()
       (flow-log 'hello)
       (loop-stop)))
    (flow-log-start! 0.02)
    (loop-run)
    (sleep (make-time 'time-duration 200000000 0)) ;; ~10 flush periods
    (flow-log-stop!))
  (fx>? (string-length (get-output-string captured)) 0))

;; flow-log-stop! performs one final drain-and-flush before returning,
;; so an entry logged just before stop is never lost even when the
;; flush period itself is far longer than the test could wait for.
(define (~check-flow-010/stop-flushes-remaining)
  (define captured (open-output-string))
  (parameterize ((current-error-port captured))
    (loop-new)
    (loop-spawn
     (lambda ()
       (flow-log 'final-entry)
       (loop-stop)))
    (flow-log-start! 1000.0)
    (loop-run)
    (flow-log-stop!))
  (let* ((s (get-output-string captured))
         (entry (read (open-input-string s))))
    (and (pair? entry) (eq? (cdr entry) 'final-entry))))


;;------------------------------------------------------------
;; FL-review 4b8bbc1: cancel-list semantics of flow-block-and-wait
;;------------------------------------------------------------

;; A base whose block proc resumes SYNCHRONOUSLY, during the
;; block-registration pass itself, wins the choice before the bases
;; after it in flatten order have registered their cancels. The
;; cancel list must nonetheless fire every registered cancel — the
;; late ones included — or a losing flow-read stays armed on its fd
;; with nobody left to cancel it, and silently eats (then discards)
;; the next bytes that arrive on the socket. In-tree this shape is
;; reachable through flow-put-block/flow-get-block's post-register
;; rescan, which calls an entry's own resume inline. So: `sync` wins
;; during registration; `parked`, registered after it, must still
;; see its cancel run once the resume is actually delivered.
(define (~check-flow-011/sync-resume-runs-later-cancels)
  (define cancelled #f)
  (define result #f)
  (define sync (make-flow (lambda (x) x)
                          (lambda () #f)         ;; try: not ready
                          (lambda (state resume register-cancel!)
                            (resume 'sync))))    ;; resume inline, mid-registration
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

;; A cancel thunk that raises (loop-get-sqe does exactly that on a
;; full submission queue — see the NULL-SQE fix e27eb79) must not
;; take the winning continuation down with it: the state box has
;; already CASed to 'synched, so if k is lost here no other base can
;; ever resume the fiber — it is gone for good, silently. The raise
;; itself is reported by loop-apply's guard (that is fine); what this
;; check pins down is that the fiber still gets its value. Bounded
;; loop-run-once ticks instead of loop-run so the buggy case fails
;; instead of hanging.
(define (~check-flow-011/raising-cancel-does-not-lose-fiber)
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

;; The winner of a choice must not fire its OWN cancel: its
;; operation already completed, so the cancel SQE it would prep is a
;; guaranteed no-op the kernel answers with -ENOENT — one wasted
;; SQE + CQE round-trip per completed operation, on the hottest path
;; the flow-choice bookkeeping has (48f0273's benchmark notice
;; identified exactly that bookkeeping as the remaining throughput
;; gap). Losers' cancels must of course still all fire.
(define (~check-flow-011/winner-own-cancel-not-fired)
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

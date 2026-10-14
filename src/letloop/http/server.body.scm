;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>

(define bytevector-append
  (lambda bvs
    (let* ((total (apply fx+ (map bytevector-length bvs)))
           (out (make-bytevector total)))
      (let loop ((bvs bvs) (offset 0))
        (if (null? bvs)
            out
            (let ((bv (car bvs)))
              (bytevector-copy! bv 0 out offset (bytevector-length bv))
              (loop (cdr bvs) (fx+ offset (bytevector-length bv)))))))))

(define status-code->reason
  (lambda (code)
    (case code
      ((200) "OK")
      ((201) "Created")
      ((204) "No Content")
      ((301) "Moved Permanently")
      ((302) "Found")
      ((304) "Not Modified")
      ((400) "Bad Request")
      ((401) "Unauthorized")
      ((403) "Forbidden")
      ((404) "Not Found")
      ((405) "Method Not Allowed")
      ((500) "Internal Server Error")
      (else "OK"))))

;; DISPATCH returns a response pair (body-bytevector . content-type);
;; these helpers build one from a Scheme object.
(define response
  (lambda (type obj)
    (case type
      ((json) (cons (string->utf8 (jsonify obj)) "application/json"))
      ((html) (cons (string->utf8 (html-write obj)) "text/html"))
      ((xml)  (cons (string->utf8 (xml-write obj)) "application/xml"))
      ((text) (cons (string->utf8 obj) "text/plain"))
      (else (error 'transparent "Unknown response type" type)))))

(define json (lambda (obj) (response 'json obj)))
(define html (lambda (obj) (response 'html obj)))
(define xml  (lambda (obj) (response 'xml obj)))

;; Pre-computed keys for the zero-allocation header primitives
(define %hdr-connection (string->utf8 "connection"))
(define %hdr-content-length (string->utf8 "content-length"))
(define %val-close (string->utf8 "close"))

;; RFC 9110 IMF-fixdate for the Date header every response carries
;; (§6.6.1 says a server with a clock MUST send it, and the reference
;; implementations this server is benchmarked against all do). The
;; clock is read per response but the bytes are re-rendered only when
;; the second changes — the same per-second cache hyper uses — so the
;; steady-state cost is one clock read and an eqv? test.
(define %imf-days '#("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))
(define %imf-months
  '#("Jan" "Feb" "Mar" "Apr" "May" "Jun"
     "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(define %date-cache-second -1)
(define %date-cache-bytes (bytevector))

(define http-date-bytes
  (lambda ()
    (let* ((t (current-time 'time-utc))
           (sec (time-second t)))
      (unless (eqv? sec %date-cache-second)
        (let ((d (time-utc->date t 0))
              (pad2 (lambda (n)
                      (if (fx<? n 10)
                          (string-append "0" (number->string n))
                          (number->string n)))))
          (set! %date-cache-bytes
                (string->utf8
                 (string-append
                  (vector-ref %imf-days (date-week-day d)) ", "
                  (pad2 (date-day d)) " "
                  (vector-ref %imf-months (fx- (date-month d) 1)) " "
                  (number->string (date-year d)) " "
                  (pad2 (date-hour d)) ":"
                  (pad2 (date-minute d)) ":"
                  (pad2 (date-second d)) " GMT")))
          (set! %date-cache-second sec)))
      %date-cache-bytes)))

;; Canned response for unparsable requests, written best-effort
;; before closing the connection.
(define %response-400
  (string->utf8
   "HTTP/1.1 400 Bad Request\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"))

;; Canned response for a request DISPATCH did not finish within
;; %dispatch-timeout-seconds. See the request-context/handle-connection
;; comments below for the full mechanism.
(define %response-504
  (string->utf8
   "HTTP/1.1 504 Gateway Timeout\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"))

;; A request that takes longer than this to answer gets a real 504,
;; not a bare connection reset from the idle reaper's unrelated
;; %idle-timeout-seconds sweep (the bug this replaces: a handler doing
;; genuine upstream work -- e.g. multiple S3 fetches -- produces no
;; read/write activity on ITS OWN fd while it runs, so the reaper's
;; per-fd timestamp goes stale and eventually kills the connection out
;; from under an in-flight, healthy request, silently, with no log
;; line anywhere).
(define %dispatch-timeout-seconds 28)

;; Cooperative cancellation handed to DISPATCH alongside REQ. NEEDED?
;; starts #t; the server flips it to #f once it has given up on this
;; request (timeout, or the connection dying mid-dispatch) so a
;; handler fanning work out over multiple fibers can stop starting new
;; work and stop waiting on stragglers instead of running to
;; completion for a response nobody will ever receive.
;;
;; Backed by a box (box-cas!), not a plain mutable field: a DISPATCH
;; implementation is free to run its fan-out via flow-worker-call on a
;; real OS thread (a downstream search handler's query dispatch does
;; exactly this), so NEEDED? is genuinely read and written across threads --
;; matching the box/box-cas! discipline this codebase already uses
;; everywhere else two threads touch shared state (e.g.
;; flow-channel-entry-claimed).
(define-record-type request-context
  (fields needed-box))

(define (request-context-make) (make-request-context (box #t)))
(define (request-context-needed? rctx) (unbox (request-context-needed-box rctx)))
(define (request-context-cancel! rctx) (box-cas! (request-context-needed-box rctx) #t #f))

;; ---- Bytevector-range URI parsing ----

;; Scan buf[start..end) for a byte value, return index or #f.
(define bytevector-find-byte
  (lambda (bv start end byte)
    (let loop ((i start))
      (cond
        ((fx>=? i end) #f)
        ((fx=? (bytevector-u8-ref bv i) byte) i)
        (else (loop (fx+ i 1)))))))

;; Split path on #\/ bytes working on buf[start..end) directly.
;; Only allocates one slice + utf8->string per segment.
(define path-split/range
  (lambda (buf start end)
    ;; Skip leading /
    (let ((start (if (and (fx<? start end)
                          (fx=? (bytevector-u8-ref buf start) 47))
                     (fx+ start 1)
                     start)))
      ;; Skip trailing /
      (let ((end (if (and (fx<? start end)
                          (fx=? (bytevector-u8-ref buf (fx- end 1)) 47))
                     (fx- end 1)
                     end)))
        (if (fx>=? start end)
            '()
            (let loop ((i start) (seg-start start) (acc '()))
              (cond
                ((fx>=? i end)
                 ;; #f: + is a literal character in path segments (RFC
                 ;; 3986), unlike in query strings.
                 (reverse (cons (percent-decode
                                 (utf8->string (subbytevector buf seg-start end))
                                 #f)
                                acc)))
                ((fx=? (bytevector-u8-ref buf i) 47) ;; #\/
                 (loop (fx+ i 1) (fx+ i 1)
                       (cons (percent-decode
                              (utf8->string (subbytevector buf seg-start i))
                              #f)
                             acc)))
                (else (loop (fx+ i 1) seg-start acc)))))))))

;; Parse the request target from buf[offset..offset+len) without
;; creating the full URI string. Returns (values path-list
;; query-alist-or-#f).
(define uri-parse/range
  (lambda (buf offset len)
    (let* ((end (fx+ offset len))
           ;; Find # boundary
           (h-pos (bytevector-find-byte buf offset end 35))
           (before-frag (or h-pos end))
           ;; Find ? boundary (before fragment)
           (q-pos (bytevector-find-byte buf offset before-frag 63))
           (path-end (or q-pos before-frag))
           (path (path-split/range buf offset path-end))
           (query (and q-pos
                       (let ((qstart (fx+ q-pos 1))
                             (qend before-frag))
                         (if (fx>=? qstart qend)
                             '()
                             (www-query-read
                              (utf8->string (subbytevector buf qstart qend))))))))
      (values path query))))

;; Parse BUF with the reusable OUT (and optionally REQ-VEC); returns
;; (values req remainder) once the head and the whole content-length
;; body are buffered, (values #f #f) when more bytes are needed, and
;; (values 'bad-request #f) on a definite parse error.
(define try-parse-http-request
  (lambda (buf out . rest)
    (let ((req-vec (if (pair? rest) (car rest) #f)))
      (if (fxzero? (bytevector-length buf))
          (values #f #f)
          (let ((req (if req-vec
                         (phr-parse-request buf out req-vec)
                         (phr-parse-request buf out))))
            (cond
              ((eq? req 'incomplete) (values #f #f))
              ((not req) (values 'bad-request #f))
              (else
               (let* ((consumed (phr-request-bytes-consumed req))
                      (content-length (phr-request-header-ref-as-integer req %hdr-content-length))
                      (body-len (or content-length 0)))
                 ;; Content-length header present but unparsable
                 ;; (non-digit, or fixnum overflow): bad request.
                 (if (and (not content-length)
                          (phr-request-header-ref/bv req %hdr-content-length))
                     (values 'bad-request #f)
                     (let ((total (fx+ consumed body-len))
                           (have (bytevector-length buf)))
                       (if (fx<? have total)
                           (values #f #f)
                           (let ((remainder (if (fx>=? total have)
                                                (bytevector)
                                                (subbytevector buf total have))))
                             (values req remainder)))))))))))))

(define http-response-write*
  (lambda (write-proc status reason headers body-bv)
    (http-response-write
     write-proc "HTTP/1.1" status reason headers
     (let ((done #f))
       (lambda ()
         (if done (eof-object) (begin (set! done #t) body-bv)))))))

(define handle-connection
  (lambda (application context dispatch peer-ip read write close fd)
    (define request-state #f)
    (define out (make-phr-out))
    (define req-vec (vector 'phr-request #f #f 0))

    (define done? #f)

    ;; Idempotent: also called from the guard below when the request
    ;; path raises after the normal-path cleanup already ran.
    (define (cleanup)
      (unless done?
        (set! done? #t)
        (unlock-object out)
        (close)))

    (define (handle-loop buf)
      (let-values (((req remainder) (try-parse-http-request buf out req-vec)))
        (cond
          ((eq? req 'bad-request)
           ;; Definite parse error: best-effort 400, then close, so
           ;; garbage is not buffered and re-parsed forever.
           (write %response-400)
           (cleanup))
          ((not req)
            ;; Unbounded per-request read: no per-read timeout race
            ;; here (that was tried in ec70498 via flow-choice/flow-
            ;; timeout and reverted — see the commit message: it cost
            ;; ~45% throughput to CML bookkeeping overhead for a
            ;; precision gain the coarse sweep below already covers
            ;; within %idle-sweep-interval seconds, same as flow-write
            ;; already accepts on the write side per §4.5). A
            ;; connection idle here relies on the sweep's loop-close
            ;; to eventually unblock this read, exactly as it always
            ;; has for writes.
            (let ((data (read)))
              (cond
                ((not data) (cleanup))            ;; read error
                ((eq? data #t) (cleanup))          ;; peer EOF
                (else (handle-loop (bytevector-append buf data))))))
          (else
              (unless request-state
                (set! request-state (context application peer-ip req)))
              (let ((method (phr-request-method-symbol req)))
                (let-values (((path-offset path-len) (phr-request-path-range req)))
                  (let-values (((path params) (uri-parse/range (phr-request-buffer req) path-offset path-len)))
                    (let ((params (or params '()))
                          (rctx (request-context-make))
                          (result-channel (make-flow-channel)))
                      ;; DISPATCH runs as its own fiber so it can be
                      ;; raced against a timeout and against the
                      ;; connection dying, rather than blocking this
                      ;; fiber (and therefore this connection's own
                      ;; read/write activity) unconditionally until it
                      ;; returns. flow-put-try, not flow-put!: if
                      ;; nobody is listening on result-channel anymore
                      ;; (the race below already resolved via timeout
                      ;; or a dead connection), a blocking put would
                      ;; park this fiber forever waiting for a
                      ;; rendezvous that will never come -- the exact
                      ;; shape of the leak fixed in flow.scm's
                      ;; flow-put-try/flow-get-try 2026-08-14. A
                      ;; dropped-on-the-floor late result is fine: the
                      ;; response it would have produced has nowhere
                      ;; left to go.
                      (flow-spawn
                        (lambda ()
                          (let ((result
                                  (guard (exception (#t (cons 'dispatch-raised exception)))
                                    (call-with-values
                                      (lambda ()
                                        (dispatch application request-state method
                                                  path params req rctx))
                                      (lambda (status response-pair extra-headers)
                                        (cons 'dispatch-ok
                                              (vector status response-pair extra-headers)))))))
                            (flow-put-try! result-channel result))))
                      (let ((outcome
                              (flow-perform
                                (flow-choice (flow-get result-channel)
                                             (flow-timeout %dispatch-timeout-seconds)
                                             (flow-read fd)))))
                        (cond
                          ((and (pair? outcome) (eq? (car outcome) 'dispatch-ok))
                           (let* ((v (cdr outcome))
                                  (status (vector-ref v 0))
                                  (response-pair (vector-ref v 1))
                                  (extra-headers (vector-ref v 2))
                                  (reason (status-code->reason status))
                                  (body-bv (car response-pair))
                                  (content-type (cdr response-pair))
                                  (all-headers (cons (cons 'content-type content-type)
                                                     (cons (cons 'date (http-date-bytes))
                                                           extra-headers)))
                                  (response-bv
                                   (let ((chunks '()))
                                     (http-response-write
                                      (lambda (bv) (set! chunks (cons bv chunks)) #t)
                                      "HTTP/1.1" status reason all-headers
                                      (let ((done #f))
                                        (lambda ()
                                          (if done (eof-object) (begin (set! done #t) body-bv)))))
                                     ;; http-response-write hands back the
                                     ;; whole response in one piece, so the
                                     ;; common case is a single chunk and
                                     ;; re-appending it would copy every
                                     ;; response a second time for nothing.
                                     (if (and (pair? chunks) (null? (cdr chunks)))
                                         (car chunks)
                                         (apply bytevector-append (reverse chunks))))))
                             (write response-bv)
                             (if (phr-request-header-value-ci=? req %hdr-connection %val-close)
                                 (cleanup)
                                 (handle-loop remainder))))
                          ((and (pair? outcome) (eq? (car outcome) 'dispatch-raised))
                           (request-context-cancel! rctx)
                           (cleanup)
                           (raise (cdr outcome)))
                          ((eq? outcome (void))
                           ;; flow-timeout won: DISPATCH is taking too
                           ;; long. A real 504, not a bare reset.
                           (request-context-cancel! rctx)
                           (write %response-504)
                           (cleanup))
                          (else
                           ;; flow-read won: the peer sent EOF, an
                           ;; error, or (a misbehaving/pipelining
                           ;; client) unexpected bytes while DISPATCH
                           ;; was still running. Either way this
                           ;; connection is no longer trustworthy --
                           ;; abandon the response, don't write to it.
                           (request-context-cancel! rctx)
                           (cleanup))))))))))))

    ;; No dynamic-wind here: coroutine suspensions (loop-read /
    ;; loop-write) are non-local exits through the wind and would run
    ;; the after-thunk mid-suspension, unpinning OUT while the kernel
    ;; still references it. GUARD only fires on raise, so suspending
    ;; and resuming across it is safe; the loop swallows coroutine
    ;; exceptions, so without this the connection would leak the
    ;; GC-pinned OUT and the fd.
    (guard (ex (else (cleanup)))
      (handle-loop (bytevector)))))

;; Idle connection reaping
(define %idle-timeout-seconds 30)
(define %idle-sweep-interval 5)

(define transparent
  (case-lambda
    ((port-number application context dispatch)
     (transparent port-number "0.0.0.0" application context dispatch))
    ((port-number bind-address application context dispatch)
     (transparent* port-number bind-address application context dispatch))))

(define transparent*
  (lambda (port-number bind-address application context dispatch)
    (loop-new)
    ;; SIGINT/SIGTERM → graceful shutdown
    (register-signal-handler 2  ;; SIGINT
      (lambda (sig)
        (when (and (loop-current) (loop-running? (loop-current)))
          (format #t "\nReceived SIGINT, shutting down...\n")
          (flush-output-port)
          (loop-stop))))
    (register-signal-handler 15 ;; SIGTERM
      (lambda (sig)
        (when (and (loop-current) (loop-running? (loop-current)))
          (format #t "\nReceived SIGTERM, shutting down...\n")
          (flush-output-port)
          (loop-stop))))
    ;; Idle connection reaper — closes connections with no activity
    (loop-spawn
      (lambda ()
        (let reap ()
          (when (loop-running? (loop-current))
            (loop-sleep %idle-sweep-interval)
            (let ((now (jiffy-current))
                  (timeout-ns (* %idle-timeout-seconds (expt 10 9))))
              (let-values (((fds jiffies) (hashtable-entries (loop-active-connections))))
                (vector-for-each
                  (lambda (fd last-active)
                    (when (> (- now last-active) timeout-ns)
                      (loop-close fd)))
                  fds jiffies)))
            (reap)))))
    (loop-spawn
      (lambda ()
        ;; APPLICATION failing here must end the PROCESS, not just
        ;; this fiber: the loop's own generic fiber-failure handler
        ;; prints "fiber died" and moves on, and every other fiber
        ;; already spawned above (the idle reaper, in particular)
        ;; keeps loop-running? true forever -- a process supervisor
        ;; (systemd's Restart=on-failure, for instance) only acts on
        ;; an actual exit, so an application that never finishes
        ;; building would otherwise sit there indefinitely, reporting
        ;; healthy while nothing is listening on PORT-NUMBER at all.
        ;; Found live: a transient DNS failure right at boot (systemd
        ;; started this before resolution was actually usable, despite
        ;; ordering after network-online.target) killed application-
        ;; build, and the process then "ran" for 18 minutes doing
        ;; nothing before anyone noticed.
        (define app-state
          (guard (ex (else
                       (let ((port (current-error-port)))
                         (display "transparent: application failed to build, exiting: " port)
                         (if (condition? ex) (display-condition ex port) (display ex port))
                         (newline port)
                         (flush-output-port port))
                       (exit 1)))
            (application)))
        (call-with-values (lambda () (loop-tcp-serve bind-address port-number))
          (lambda (accept close)
            (format #t "transparent server at http://~a:~a/\n" bind-address port-number)
            (flush-output-port)
            (let loop ()
              (when (loop-running? (loop-current))
                (guard (ex (else (void)))
                  (call-with-values accept
                    (lambda (read write close peer-ip fd)
                      (when (and read write close)
                        (loop-spawn
                          (lambda () (handle-connection app-state context dispatch peer-ip read write close fd)))))))
                (loop)))))))
    (loop-run)
    ;; Cleanup after loop exits
    (io-uring-queue-exit (loop-ring (loop-current)))))

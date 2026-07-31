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
  (lambda (application context dispatch peer-ip read write close)
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
                    (let ((params (or params '())))
                      (let-values (((status response-pair extra-headers)
                                    (dispatch application request-state method path params req)))
                        (let* ((reason (status-code->reason status))
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
                          (write response-bv)))))))
              (if (phr-request-header-value-ci=? req %hdr-connection %val-close)
                  (cleanup)
                  (handle-loop remainder))))))

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
        (define app-state (application))
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
                          (lambda () (handle-connection app-state context dispatch peer-ip read write close)))))))
                (loop)))))))
    (loop-run)
    ;; Cleanup after loop exits
    (io-uring-queue-exit (loop-ring (loop-current)))))

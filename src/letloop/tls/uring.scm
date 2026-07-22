;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Non-blocking TLS client over the io_uring loop from (letloop
;; liburing low): the handshake and read/write paths yield via
;; loop-poll-wait on TLS_WANT_POLLIN/POLLOUT instead of busy-looping,
;; so they must run inside a loop coroutine (loop-spawn).
;;
;; The blocking twin lives in (letloop tls base) with ctx-only
;; arities; here every entry point carries (ctx fd). www-request
;; deliberately mirrors the blocking (letloop www) www-request —
;; importers of both must rename one.
;;
;; Extracted from examples/picotransparenturing.scm sections 12c/12e.
(library (letloop tls uring)

  (export tls-open
          tls-reader
          tls-writer
          tls-shutdown
          www-request

          ~check-tls-uring-000)

  (import (chezscheme)
          (letloop tls low)
          (letloop dns)
          (letloop http)
          (only (letloop picohttpparser)
                phr-parse-response
                phr-response-bytes-consumed
                phr-response-status
                phr-response-minor-version
                phr-response-header-count
                phr-response-header-name
                phr-response-header-value
                phr-response-header-ref)
          (rename (only (letloop www) www-url-read) (www-url-read url-parse))
          (letloop liburing low))

  (define %tls-initialized #f)

  (define %tls-ensure-init
    (lambda ()
      (unless %tls-initialized
        (let ((rc (tls-init)))
          (unless (zero? rc)
            (error 'tls-open "tls_init failed" rc))
          (set! %tls-initialized #t)))))

  ;; The tls_config is created once and shared by every connection:
  ;; building it per connection makes libtls reload the CA bundle from
  ;; disk inside a blocking foreign call on every tls-open. The CA
  ;; bundle is loaded in memory once per process; set LETLOOP_CA_FILE
  ;; to override the bundle path, e.g. to talk to a server signed by a
  ;; private CA.
  (define %tls-config #f)

  (define %tls-config-get
    (lambda ()
      (unless %tls-config
        (%tls-ensure-init)
        (let ((config (tls-config-new)))
          (when (zero? config)
            (error 'tls-open "tls_config_new failed"))
          (let ((rc (tls-config-set-protocols config TLS_PROTOCOLS_DEFAULT)))
            (unless (zero? rc)
              (let ((msg (tls-config-error config)))
                (tls-config-free config)
                (error 'tls-open "tls_config_set_protocols failed" msg))))
          (let ((path (or (getenv "LETLOOP_CA_FILE")
                          (tls-default-ca-cert-file))))
            (when (and path (file-exists? path))
              ;; blocking read, but it happens once per process
              (guard (ex (else (void))) ;; fall back to libtls' own loading
                (let* ((port (open-file-input-port path))
                       (ca (get-bytevector-all port)))
                  (close-port port)
                  (when (bytevector? ca)
                    (with-lock (list ca)
                      (tls-config-set-ca-mem config
                                             (bytevector-pointer ca)
                                             (bytevector-length ca))))))))
          (set! %tls-config config)))
      %tls-config))

  ;; Returns (values ctx fd); tear down with tls-shutdown.
  (define tls-open
    (lambda (host port)
      (let ((config (%tls-config-get)))
        (let ((ctx (tls-client)))
          (when (zero? ctx)
            (error 'tls-open "tls_client failed"))
          (let ((rc (tls-configure ctx config)))
            (unless (zero? rc)
              (let ((msg (tls-error ctx)))
                (tls-free ctx)
                (error 'tls-open "tls_configure failed" msg))))
          ;; Async DNS + connect
          (let-values (((addr addrlen) (dns-resolve-a host port)))
            (let ((fd (loop-connect addr addrlen)))
              (foreign-free addr)
              (unless fd
                (tls-free ctx)
                (error 'tls-open "connect failed"))
              ;; Attach TLS to connected socket
              (let ((rc (tls-connect-socket ctx fd host)))
                (unless (zero? rc)
                  (let ((msg (tls-error ctx)))
                    (tls-free ctx)
                    (loop-close fd)
                    (error 'tls-open "tls_connect_socket failed" msg))))
              ;; Non-blocking handshake — yield on WANT_POLLIN/POLLOUT
              (let loop ()
                (let ((rc (tls-handshake ctx)))
                  (cond
                    ((zero? rc) (void))
                    ((= rc TLS_WANT_POLLIN)
                     (loop-poll-wait fd POLLIN)
                     (loop))
                    ((= rc TLS_WANT_POLLOUT)
                     (loop-poll-wait fd POLLOUT)
                     (loop))
                    (else
                     (let ((msg (tls-error ctx)))
                       (tls-close ctx)
                       (tls-free ctx)
                       (loop-close fd)
                       (error 'tls-open "tls_handshake failed" msg))))))
              (values ctx fd)))))))

  ;; Thunk yielding bytevectors, eof-object at end of stream.
  (define tls-reader
    (lambda (ctx fd)
      (let ((buf (make-bytevector 4096)))
        (lambda ()
          (let loop ()
            (let ((n (with-lock (list buf)
                       (tls-read ctx (bytevector-pointer buf) 4096))))
              (cond
                ((> n 0)
                 (let ((out (make-bytevector n)))
                   (bytevector-copy! buf 0 out 0 n)
                   out))
                ((zero? n) (eof-object))
                ((= n TLS_WANT_POLLIN)
                 (loop-poll-wait fd POLLIN)
                 (loop))
                ((= n TLS_WANT_POLLOUT)
                 (loop-poll-wait fd POLLOUT)
                 (loop))
                (else
                 (error 'tls-reader "tls_read failed" (tls-error ctx))))))))))

  ;; Procedure writing a whole bytevector, yielding as needed.
  (define tls-writer
    (lambda (ctx fd)
      (lambda (bv)
        (let ((total (bytevector-length bv)))
          (let loop ((offset 0))
            (when (< offset total)
              (let ((n (with-lock (list bv)
                         (tls-write ctx
                                    (+ (bytevector-pointer bv) offset)
                                    (- total offset)))))
                (cond
                  ((> n 0) (loop (+ offset n)))
                  ((= n TLS_WANT_POLLIN)
                   (loop-poll-wait fd POLLIN)
                   (loop offset))
                  ((= n TLS_WANT_POLLOUT)
                   (loop-poll-wait fd POLLOUT)
                   (loop offset))
                  (else
                   (error 'tls-writer "tls_write failed" (tls-error ctx)))))))))))

  (define tls-shutdown
    (lambda (ctx fd)
      (tls-close ctx)
      (tls-free ctx)
      (loop-close fd)))

  ;; ------------------------------------------------------------
  ;; www-request — async HTTPS client with a keep-alive pool
  ;;
  ;; (www-request METHOD URL HEADERS BODY) → (values CODE HEADERS BODY)
  ;;
  ;;   BODY is #f for no body, a bytevector sent as-is, or a generator
  ;;   (lambda () → bytevector | eof-object). Returns the status code,
  ;;   the response headers as an alist of (downcased-symbol . string)
  ;;   and the body as a bytevector; (values #f #f #f) on error, with
  ;;   the condition printed on stderr. Must run inside a loop
  ;;   coroutine.
  ;;
  ;; Connections are keyed by "host:port" and kept after a response
  ;; when reuse is safe: exact body framing (content-length or chunked;
  ;; HEAD/204/304 count as empty) and no "Connection: close" (HTTP/1.1;
  ;; HTTP/1.0 needs an explicit keep-alive). Reuse skips DNS, TCP
  ;; connect and the TLS handshake — ~25ms of CPU inside libtls per
  ;; connection; a pooled request costs ~100-200us. At most
  ;; %www-pool-idle-max idle connections per key; idle connections
  ;; older than %www-pool-ttl-jiffies are closed at borrow time. When
  ;; the first use of a pooled connection fails (peer closed it while
  ;; idle), www-request transparently retries once on a fresh one.
  ;; Responses are parsed with the C picohttpparser, accumulating reads
  ;; with the last-len fast path. The pool is per OS thread, so shards
  ;; never share or close each other's connections.

  (define %www-pool-idle-max 4)
  (define %www-pool-ttl-jiffies (* 30 (expt 10 9)))

  (define %www-pool-param (make-thread-parameter #f))

  (define %www-pool
    (lambda ()
      (or (%www-pool-param)
          (let ((ht (make-hashtable string-hash string=?)))
            (%www-pool-param ht)
            ht))))

  ;; Idle entries per key: list of #(ctx fd last-used)
  (define %www-pool-get
    (lambda (key)
      (let ((pool (%www-pool))
            (now (jiffy-current)))
        (let split ((entries (hashtable-ref (%www-pool) key '()))
                    (fresh '())
                    (expired '()))
          (if (pair? entries)
              (if (< now (+ (vector-ref (car entries) 2) %www-pool-ttl-jiffies))
                  (split (cdr entries) (cons (car entries) fresh) expired)
                  (split (cdr entries) fresh (cons (car entries) expired)))
              (begin
                ;; update the table before tls-shutdown: closing yields
                ;; to the loop and the table must not reference dead
                ;; entries meanwhile
                (hashtable-set! pool key (if (null? fresh) '() (cdr fresh)))
                (for-each (lambda (e)
                            (guard (ex (else (void)))
                              (tls-shutdown (vector-ref e 0)
                                            (vector-ref e 1))))
                          expired)
                (if (null? fresh) #f (car fresh))))))))

  (define %www-pool-put
    (lambda (key ctx fd)
      (let* ((pool (%www-pool))
             (entries (hashtable-ref pool key '())))
        (if (fx>=? (length entries) %www-pool-idle-max)
            (tls-shutdown ctx fd)
            (hashtable-set! pool key
                            (cons (vector ctx fd (jiffy-current)) entries))))))

  (define %www-body-generator
    (lambda (body)
      (cond
        ((bytevector? body)
         (let ((sent #f))
           (lambda ()
             (if sent
                 (eof-object)
                 (begin (set! sent #t) body)))))
        ;; #f means no body
        ((not body) (lambda () (eof-object)))
        (else body))))

  ;; index of the CR of the first CRLF at or after POS, or #f
  (define %www-find-crlf
    (lambda (buf pos)
      (let ((len (bytevector-length buf)))
        (let loop ((i pos))
          (cond
            ((fx>=? (fx+ i 1) len) #f)
            ((and (fx=? (bytevector-u8-ref buf i) 13)
                  (fx=? (bytevector-u8-ref buf (fx+ i 1)) 10))
             i)
            (else (loop (fx+ i 1))))))))

  (define %www-bytevector-append
    (lambda (a b)
      (let ((out (make-bytevector (fx+ (bytevector-length a)
                                       (bytevector-length b)))))
        (bytevector-copy! a 0 out 0 (bytevector-length a))
        (bytevector-copy! b 0 out (bytevector-length a) (bytevector-length b))
        out)))

  (define %www-fill
    (lambda (read! buf)
      (let ((chunk (read!)))
        (if (eof-object? chunk)
            (error 'www-request "connection closed mid-body")
            (%www-bytevector-append buf chunk)))))

  ;; grow BUF until it holds at least TOTAL bytes
  (define %www-read-exactly
    (lambda (read! buf total)
      (let loop ((buf buf))
        (if (fx>=? (bytevector-length buf) total)
            buf
            (loop (%www-fill read! buf))))))

  (define %www-read-until-eof
    (lambda (read! buf)
      (let loop ((buf buf))
        (let ((chunk (read!)))
          (if (eof-object? chunk)
              buf
              (loop (%www-bytevector-append buf chunk)))))))

  ;; decode a chunked body starting at START, refilling with READ! as
  ;; needed; returns the assembled body bytevector
  (define %www-read-chunked
    (lambda (read! buf start)

      (define chunk-size
        (lambda (buf pos cr)
          ;; hex size; chunk extensions after ';' are ignored
          (let loop ((i pos) (n 0))
            (if (fx>=? i cr)
                n
                (let ((b (bytevector-u8-ref buf i)))
                  (cond
                    ((fx=? b 59) n) ;; #\;
                    ((and (fx>=? b 48) (fx<=? b 57))
                     (loop (fx+ i 1) (fx+ (fx* n 16) (fx- b 48))))
                    ((and (fx>=? b 97) (fx<=? b 102))
                     (loop (fx+ i 1) (fx+ (fx* n 16) (fx- b 87))))
                    ((and (fx>=? b 65) (fx<=? b 70))
                     (loop (fx+ i 1) (fx+ (fx* n 16) (fx- b 55))))
                    (else (error 'www-request "invalid chunk size"))))))))

      (define assemble
        (lambda (buf pieces total)
          (let ((body (make-bytevector total)))
            (let loop ((pieces (reverse pieces)) (at 0))
              (if (null? pieces)
                  body
                  (let ((piece (car pieces)))
                    (bytevector-copy! buf (car piece) body at (cdr piece))
                    (loop (cdr pieces) (fx+ at (cdr piece)))))))))

      (let loop ((buf buf) (pos start) (pieces '()) (total 0))
        (let ((cr (%www-find-crlf buf pos)))
          (if (not cr)
              (loop (%www-fill read! buf) pos pieces total)
              (let ((size (chunk-size buf pos cr)))
                (if (fxzero? size)
                    ;; trailer section: lines until an empty one
                    (let trailers ((buf buf) (tpos (fx+ cr 2)))
                      (let ((tcr (%www-find-crlf buf tpos)))
                        (cond
                          ((not tcr) (trailers (%www-fill read! buf) tpos))
                          ((fx=? tcr tpos) (assemble buf pieces total))
                          (else (trailers buf (fx+ tcr 2))))))
                    (let ((data-start (fx+ cr 2)))
                      (let ensure ((buf buf))
                        (if (fx<? (bytevector-length buf)
                                  (fx+ data-start size 2))
                            (ensure (%www-fill read! buf))
                            (loop buf
                                  (fx+ data-start size 2)
                                  (cons (cons data-start size) pieces)
                                  (fx+ total size))))))))))))

  ;; response headers as an alist of (downcased-symbol . string), the
  ;; same shape http-response-read returns
  (define %www-response-headers-alist
    (lambda (resp)
      (let ((count (phr-response-header-count resp)))
        (let loop ((i 0) (out '()))
          (if (fx>=? i count)
              (reverse out)
              (let ((name (phr-response-header-name resp i)))
                (loop (fx+ i 1)
                      (if name
                          (cons (cons (string->symbol (string-downcase name))
                                      (phr-response-header-value resp i))
                                out)
                          out))))))))

  ;; Read one HTTP response with the C picohttpparser, framing the body
  ;; exactly so the connection stays clean for reuse. Returns
  ;; (values code headers body reusable?).
  (define %www-response-read
    (lambda (read! head?)
      (let loop ((buf (bytevector)))
        (let ((chunk (read!)))
          (when (eof-object? chunk)
            (error 'www-request "connection closed while reading response"))
          (let* ((prev (bytevector-length buf))
                 (buf (%www-bytevector-append buf chunk))
                 (resp (phr-parse-response buf prev)))
            (cond
              ((eq? resp 'incomplete) (loop buf))
              ((not resp) (error 'www-request "invalid HTTP response"))
              (else
               (let* ((consumed (phr-response-bytes-consumed resp))
                      (code (phr-response-status resp))
                      (headers (%www-response-headers-alist resp))
                      (content-length
                       (let ((v (phr-response-header-ref resp "content-length")))
                         (and v (string->number v))))
                      (chunked?
                       (let ((v (phr-response-header-ref resp "transfer-encoding")))
                         (and v (string-ci=? v "chunked"))))
                      (connection (phr-response-header-ref resp "connection"))
                      (keep? (if (fx=? (phr-response-minor-version resp) 1)
                                 (not (and connection
                                           (string-ci=? connection "close")))
                                 (and connection
                                      (string-ci=? connection "keep-alive")))))
                 (cond
                   ;; no body follows a HEAD response, 204 or 304
                   ((or head? (fx=? code 204) (fx=? code 304))
                    (values code headers (bytevector) keep?))
                   (chunked?
                    (values code headers
                            (%www-read-chunked read! buf consumed)
                            keep?))
                   (content-length
                    (let ((buf (%www-read-exactly
                                read! buf (fx+ consumed content-length))))
                      (values code headers
                              (subbytevector buf consumed
                                             (fx+ consumed content-length))
                              keep?)))
                   (else
                    ;; no framing: body runs to EOF, connection is spent
                    (let ((buf (%www-read-until-eof read! buf)))
                      (values code headers
                              (subbytevector buf consumed
                                             (bytevector-length buf))
                              #f))))))))))))

  ;; Issue one request on an established connection; the connection
  ;; goes back to the pool when the response allows reuse, and is
  ;; closed otherwise. Returns (values code headers body).
  (define %www-request-once
    (lambda (key ctx fd method request-target headers body)
      (http-request-write (tls-writer ctx fd)
                          method request-target 'HTTP/1.1 headers
                          (%www-body-generator body))
      (let-values (((code hdrs bdy keep?)
                    (%www-response-read (tls-reader ctx fd)
                                        (eq? method 'HEAD))))
        ;; the response is complete: a failure while recycling the
        ;; connection must not turn it into a request error
        (guard (ex (else (void)))
          (if keep?
              (%www-pool-put key ctx fd)
              (tls-shutdown ctx fd)))
        (values code hdrs bdy))))

  (define www-request
    (lambda (method url headers body)
      ;; Track the live TLS context and socket so the guard handler can
      ;; release them: without teardown every failed request leaks an fd
      ;; and a libtls context until EMFILE. Pooled connections are not
      ;; tracked here: their failure path closes them explicitly before
      ;; retrying.
      (let ((live-ctx #f)
            (live-fd #f))
        (guard (ex (else
                    ;; Best-effort teardown; by the time this handler
                    ;; runs the coroutine is not suspended, so calling
                    ;; loop-close here is safe (dynamic-wind is not, see
                    ;; NOTE below).
                    (when live-ctx
                      (guard (_ (else #f)) (tls-close live-ctx))
                      (guard (_ (else #f)) (tls-free live-ctx)))
                    (when live-fd
                      (guard (_ (else #f)) (loop-close live-fd)))
                    (if (condition? ex)
                        (display-condition ex (current-error-port))
                        (format (current-error-port) "www-request error: ~a\n" ex))
                    (newline (current-error-port))
                    (flush-output-port (current-error-port))
                    (values #f #f #f)))
          (let-values (((scheme host port request-target) (url-parse url)))
            (let* ((port* (or port (if (string=? scheme "https") 443 80)))
                   (key (string-append host ":" (number->string port*)))
                   (headers* (if (assq 'host headers)
                                 headers
                                 (cons (cons 'host host) headers))))

              ;; NOTE: cannot use dynamic-wind here because loop-abort
              ;; uses continuations that would trigger the exit guard
              ;; prematurely
              (define fresh!
                (lambda ()
                  (let-values (((ctx fd) (tls-open host port*)))
                    (set! live-ctx ctx)
                    (set! live-fd fd)
                    ;; %www-request-once pools or closes the connection
                    ;; itself; on success nothing can raise afterwards,
                    ;; so the guard cannot double free
                    (%www-request-once key ctx fd method request-target
                                       headers* body))))

              (let ((pooled (%www-pool-get key)))
                (if pooled
                    ;; the peer may have closed an idle connection at
                    ;; any time: on failure retry once on a fresh one
                    (call-with-values
                        (lambda ()
                          (guard (ex (else #f))
                            (%www-request-once key
                                               (vector-ref pooled 0)
                                               (vector-ref pooled 1)
                                               method request-target
                                               headers* body)))
                      (lambda maybe
                        (if (and (pair? maybe) (car maybe))
                            (apply values maybe)
                            (begin
                              (guard (ex (else (void)))
                                (tls-shutdown (vector-ref pooled 0)
                                              (vector-ref pooled 1)))
                              (fresh!)))))
                    (fresh!)))))))))

  ;; End-to-end: async HTTPS GET inside the loop (needs network, like
  ;; the ~check-www-* it mirrors). One retry to absorb httpbin flakes.
  (define ~check-tls-uring-000
    (lambda ()
      (define (attempt)
        (let ((result #f))
          (loop-new)
          (loop-spawn
           (lambda ()
             (call-with-values
                 (lambda () (www-request 'GET "https://httpbin.org/anything" '() (bytevector)))
               (lambda (code headers body)
                 (set! result code)
                 (loop-stop)))))
          (loop-run)
          (equal? result 200)))
      (or (attempt) (attempt))))

  )

#!chezscheme
(library (letloop tls base)

  (export tls-open
          https-timeout-seconds
          tls-reader
          tls-writer
          tls-shutdown
          url-parse
          https-request)

  (import (chezscheme)
          (letloop cffi)
          (letloop tls low)
          (letloop http))

  ;; Lazy tls-init: called once on first tls-open
  (define %tls-initialized #f)

  (define %tls-ensure-init
    (lambda ()
      (unless %tls-initialized
        (let ((rc (tls-init)))
          (unless (zero? rc)
            (error 'tls-open "tls_init failed" rc))
          (set! %tls-initialized #t)))))

  ;; ---- Owned socket, with timeouts ----
  ;;
  ;; tls_connect makes libtls create the socket, and libtls sets no
  ;; timeouts on it -- so a peer that stops answering leaves tls_read
  ;; blocked in the kernel forever. Observed exactly that stranding
  ;; multi-hour S3 runs: wchan=wait_woken, ESTABLISHED socket, empty
  ;; queues, indefinitely. There is no way to reach the fd libtls made,
  ;; so the fix is to own it: resolve, connect, set SO_RCVTIMEO and
  ;; SO_SNDTIMEO, then hand the fd to tls_connect_socket.
  ;;
  ;; TLS_WANT_POLLIN is ambiguous here, and both meanings occur. A recv
  ;; that hits SO_RCVTIMEO surfaces as WANT_POLLIN (libtls maps EAGAIN),
  ;; but so does "I consumed a non-application record, call me again" --
  ;; observed immediately in practice: the first tls_read after the
  ;; request reads the server's TLS 1.3 NewSessionTicket and returns
  ;; WANT_POLLIN having made real progress, in microseconds. The two are
  ;; told apart by the clock: an internal record is instant, a timeout
  ;; consumes the whole SO_RCVTIMEO window. So WANT_* retries while the
  ;; elapsed time since last progress is clearly under the timeout, and
  ;; raises once a full window has visibly been eaten. The storage layer
  ;; retries the whole request, which is the right granularity.
  ;;
  ;; The libc calls that can block (getaddrinfo, connect, and the tls
  ;; calls above) use __collect_safe so a worker thread parked in one
  ;; does not stall garbage collection process-wide -- see tls/low.

  (define (%want-means-timeout? started)
    ;; A WANT_POLLIN/POLLOUT that arrives after ~a full timeout window
    ;; of no progress is the socket timeout; one that arrives sooner is
    ;; libtls asking to be called again.
    (>= (- (real-time) started)
        (exact (round (* 900 (https-timeout-seconds))))))

  (define https-timeout-seconds
    ;; Applied to connect, and to every individual send and recv. Not a
    ;; whole-request deadline: a healthy large transfer makes steady
    ;; progress and never trips it, a dead peer trips it in one window.
    (make-parameter 60))

  ;; struct addrinfo, glibc x86_64: flags/family/socktype/protocol,
  ;; addrlen + padding, then three pointers.
  (define-ftype %addrinfo
    (struct (flags int) (family int) (socktype int) (protocol int)
            (addrlen unsigned-32) (pad unsigned-32)
            (addr void*) (canonname void*) (next void*)))

  (define-ftype %timeval (struct (sec long) (usec long)))

  (define %AF-UNSPEC 0)
  (define %SOCK-STREAM 1)
  (define %SOL-SOCKET 1)
  (define %SO-RCVTIMEO 20)
  (define %SO-SNDTIMEO 21)

  (define %getaddrinfo
    ;; Blocks on DNS; collect-safe for the same reason as the tls calls.
    ;; __collect_safe forbids string marshalling (it may allocate), so
    ;; HOST and PORT arrive as addresses of locked NUL-terminated
    ;; bytevectors -- see %string->nul below.
    (foreign-procedure __collect_safe "getaddrinfo"
                       (void* void* void* void*) int))

  (define (%string->nul text)
    (let* ((bytes (string->utf8 text))
           (out (make-bytevector (fx+ 1 (bytevector-length bytes)) 0)))
      (bytevector-copy! bytes 0 out 0 (bytevector-length bytes))
      out))

  (define %freeaddrinfo (foreign-procedure "freeaddrinfo" (void*) void))
  (define %socket (foreign-procedure "socket" (int int int) int))
  (define %connect
    (foreign-procedure __collect_safe "connect" (int void* int) int))
  (define %setsockopt
    (foreign-procedure "setsockopt" (int int int void* int) int))
  (define %close (foreign-procedure "close" (int) int))

  (define (%socket-timeout! fd option seconds)
    (let ((tv (make-ftype-pointer %timeval (foreign-alloc (ftype-sizeof %timeval)))))
      (ftype-set! %timeval (sec) tv (exact (floor seconds)))
      (ftype-set! %timeval (usec) tv
                  (exact (round (* (- seconds (floor seconds)) 1000000))))
      (let ((rc (%setsockopt fd %SOL-SOCKET option
                             (ftype-pointer-address tv)
                             (ftype-sizeof %timeval))))
        (foreign-free (ftype-pointer-address tv))
        rc)))

  (define (%socket-connect host port timeout)
    ;; A connected fd with both timeouts set, or an error. Tries each
    ;; resolved address in order, as getaddrinfo intends.
    (let ((hints (make-ftype-pointer %addrinfo
                                     (foreign-alloc (ftype-sizeof %addrinfo))))
          (out (foreign-alloc 8)))
      (do ((i 0 (fx+ i 1))) ((fx= i (ftype-sizeof %addrinfo)))
        (foreign-set! 'unsigned-8 (ftype-pointer-address hints) i 0))
      (ftype-set! %addrinfo (family) hints %AF-UNSPEC)
      (ftype-set! %addrinfo (socktype) hints %SOCK-STREAM)
      (let ((rc (let ((host-nul (%string->nul host))
                      (port-nul (%string->nul port)))
                  (with-lock (list host-nul port-nul)
                    (%getaddrinfo (bytevector-pointer host-nul)
                                  (bytevector-pointer port-nul)
                                  (ftype-pointer-address hints) out)))))
        (foreign-free (ftype-pointer-address hints))
        (unless (zero? rc)
          (foreign-free out)
          (error 'tls-open "getaddrinfo failed" host rc)))
      (let ((head (foreign-ref 'void* out 0)))
        (foreign-free out)
        (let try ((address head))
          (if (zero? address)
            (begin
              (%freeaddrinfo head)
              (error 'tls-open "connect failed on every address" host port))
            (let* ((info (make-ftype-pointer %addrinfo address))
                   (fd (%socket (ftype-ref %addrinfo (family) info)
                                (ftype-ref %addrinfo (socktype) info)
                                (ftype-ref %addrinfo (protocol) info))))
              (if (fx= fd -1)
                (try (ftype-ref %addrinfo (next) info))
                (begin
                  (%socket-timeout! fd %SO-RCVTIMEO timeout)
                  (%socket-timeout! fd %SO-SNDTIMEO timeout)
                  (if (zero? (%connect fd
                                       (ftype-ref %addrinfo (addr) info)
                                       (ftype-ref %addrinfo (addrlen) info)))
                    (begin (%freeaddrinfo head) fd)
                    (begin
                      (%close fd)
                      (try (ftype-ref %addrinfo (next) info))))))))))))

  ;; tls-open: connect to host:port with timeouts on an owned socket.
  ;; Returns (values ctx fd); tls-shutdown takes both.
  (define tls-open
    (lambda (host port)
      (%tls-ensure-init)
      (let ((fd (%socket-connect host
                                 (if port (number->string port) "443")
                                 (https-timeout-seconds)))
            (config (tls-config-new)))
        (when (zero? config)
          (%close fd)
          (error 'tls-open "tls_config_new failed"))
        (let ((rc (tls-config-set-protocols config TLS_PROTOCOLS_DEFAULT)))
          (unless (zero? rc)
            (let ((msg (tls-config-error config)))
              (tls-config-free config)
              (%close fd)
              (error 'tls-open "tls_config_set_protocols failed" msg))))
        (let ((ctx (tls-client)))
          (when (zero? ctx)
            (tls-config-free config)
            (%close fd)
            (error 'tls-open "tls_client failed"))
          (let ((rc (tls-configure ctx config)))
            (unless (zero? rc)
              (let ((msg (tls-error ctx)))
                (tls-config-free config)
                (tls-free ctx)
                (%close fd)
                (error 'tls-open "tls_configure failed" msg))))
          (tls-config-free config)
          ;; SERVERNAME argument carries SNI and certificate
          ;; verification, exactly as tls_connect's host did.
          (let ((rc (tls-connect-socket ctx fd host)))
            (unless (zero? rc)
              (let ((msg (tls-error ctx)))
                (tls-free ctx)
                (%close fd)
                (error 'tls-open "tls_connect_socket failed" msg))))
          (let loop ((started (real-time)))
            (let ((rc (tls-handshake-safe ctx)))
              (cond
               ((zero? rc) (void))
               ((and (or (= rc TLS_WANT_POLLIN) (= rc TLS_WANT_POLLOUT))
                     (not (%want-means-timeout? started)))
                (loop started))
               ((or (= rc TLS_WANT_POLLIN) (= rc TLS_WANT_POLLOUT))
                (tls-close-safe ctx)
                (tls-free ctx)
                (%close fd)
                (error 'tls-open "handshake timed out" host
                       (https-timeout-seconds)))
               (else
                (let ((msg (tls-error ctx)))
                  (tls-close-safe ctx)
                  (tls-free ctx)
                  (%close fd)
                  (error 'tls-open "tls_handshake failed" msg))))))
          (values ctx fd)))))

  ;; tls-reader: return a thunk (lambda () -> bytevector | eof-object)
  (define tls-reader
    (lambda (ctx)
      (let ((buf (make-bytevector 4096)))
        (lambda ()
          (let loop ((started (real-time)))
            (let ((n (with-lock (list buf)
                       (tls-read-safe ctx (bytevector-pointer buf) 4096))))
              (cond
               ((> n 0)
                (let ((out (make-bytevector n)))
                  (bytevector-copy! buf 0 out 0 n)
                  out))
               ((zero? n) (eof-object))
               ((or (= n TLS_WANT_POLLIN) (= n TLS_WANT_POLLOUT))
                (if (%want-means-timeout? started)
                  (error 'tls-reader "read timed out" (https-timeout-seconds))
                  (loop started)))
               (else
                (error 'tls-reader "tls_read failed" (tls-error ctx))))))))))

  ;; tls-writer: return a procedure (lambda (bytevector) -> void)
  (define tls-writer
    (lambda (ctx)
      (lambda (bv)
        (let ((total (bytevector-length bv)))
          (let loop ((offset 0) (started (real-time)))
            (when (< offset total)
              (let ((n (with-lock (list bv)
                         (tls-write-safe ctx
                                         (+ (bytevector-pointer bv) offset)
                                         (- total offset)))))
                (cond
                 ((> n 0) (loop (+ offset n) (real-time)))
                 ((or (= n TLS_WANT_POLLIN) (= n TLS_WANT_POLLOUT))
                  (if (%want-means-timeout? started)
                    (error 'tls-writer "write timed out"
                           (https-timeout-seconds))
                    (loop offset started)))
                 (else
                  (error 'tls-writer "tls_write failed" (tls-error ctx)))))))))))

  ;; tls-shutdown: close and free the context, then close the fd we
  ;; own -- with tls_connect_socket libtls does not consider the socket
  ;; its to close.
  (define tls-shutdown
    (lambda (ctx fd)
      (tls-close-safe ctx)
      (tls-free ctx)
      (%close fd)))

  ;; URL parser, re-exported by (letloop www) as www-url-read.
  ;; Returns (values scheme host port request-target)
  (define url-parse
    (lambda (url)
      (let ((sep (let loop ((i 0))
                   (and (< i (- (string-length url) 2))
                        (if (and (char=? (string-ref url i) #\:)
                                 (char=? (string-ref url (+ i 1)) #\/)
                                 (char=? (string-ref url (+ i 2)) #\/))
                            i
                            (loop (+ i 1)))))))
        (unless sep
          (error 'url-parse "invalid URL: no ://" url))
        (let* ((scheme (substring url 0 sep))
               (rest (substring url (+ sep 3) (string-length url)))
               ;; Split host+port from path
               (slash-pos (let loop ((i 0))
                            (if (>= i (string-length rest))
                                #f
                                (if (char=? (string-ref rest i) #\/)
                                    i
                                    (loop (+ i 1))))))
               (authority (if slash-pos
                              (substring rest 0 slash-pos)
                              rest))
               (request-target (if slash-pos
                                   (substring rest slash-pos (string-length rest))
                                   "/"))
               ;; Split host:port
               (colon-pos (let loop ((i (- (string-length authority) 1)))
                            (if (< i 0)
                                #f
                                (if (char=? (string-ref authority i) #\:)
                                    i
                                    (loop (- i 1))))))
               (host (if colon-pos
                         (substring authority 0 colon-pos)
                         authority))
               (port (if colon-pos
                         (string->number (substring authority (+ colon-pos 1) (string-length authority)))
                         #f)))
          (values scheme host port request-target)))))

  ;; https-request: high-level HTTPS request
  ;; Returns (values version code reason headers body)
  (define https-request
    (lambda (method url headers body)
      (let-values (((scheme host port request-target) (url-parse url)))
        (let-values (((ctx fd) (tls-open host (or port 443))))
          (dynamic-wind
            (lambda () (void))
            (lambda ()
              ;; Add Host header if not present
              (let ((headers* (if (assq 'host headers)
                                  headers
                                  (cons (cons 'host host) headers))))
                ;; Write request
                (let ((write! (tls-writer ctx))
                      (done #f))
                  (http-request-write write!
                                      method
                                      request-target
                                      'HTTP/1.1
                                      headers*
                                      (lambda ()
                                        (if done
                                            (eof-object)
                                            (begin (set! done #t) body)))))
                ;; Read response
                (http-response-read (tls-reader ctx))))
            (lambda ()
              (tls-shutdown ctx fd)))))))

)

;; Checks for (letloop tls base) -- included into the library, so the
;; private %socket / %close / %want-means-timeout? are in scope.
;;
;; The timeout checks are the point of this file. Before tls-open owned
;; its socket there was no way to bound a blocking read, and a peer that
;; stopped answering hung the caller in the kernel forever; the shape to
;; protect is "raises in about one timeout window", not merely "raises".

;; ---- a TCP blackhole on loopback ----
;;
;; A listening socket that never calls accept(2) is enough: Linux
;; completes the TCP handshake in the kernel and parks the connection on
;; the accept queue, so connect(2) succeeds and the peer then says
;; nothing at all -- which is exactly the dead-peer case, with no
;; network and no certificate involved. tls_handshake writes its
;; ClientHello, waits for a ServerHello that never comes, and must come
;; back out via SO_RCVTIMEO.

(define %AF-INET 2)

(define-ftype %sockaddr-in
  ;; 16 bytes: family, port (network order), address, then sin_zero[8].
  (struct (family unsigned-16)
          (port unsigned-16)
          (addr unsigned-32)
          (zero1 unsigned-32)
          (zero2 unsigned-32)))

(define %bind (foreign-procedure "bind" (int void* int) int))
(define %listen (foreign-procedure "listen" (int int) int))
(define %getsockname (foreign-procedure "getsockname" (int void* void*) int))

(define (%swap16 n)
  ;; htons/ntohs, which are macros and so not reachable by dlsym.
  (fxlogor (fxsll (fxand n #xff) 8) (fxsrl n 8)))

(define (%blackhole-listen)
  ;; Returns (values fd port) for a bound, listening, never-accepted
  ;; socket on 127.0.0.1. Port 0 lets the kernel pick a free one, which
  ;; getsockname then reports -- no fixed port to collide with.
  (let ((fd (%socket %AF-INET %SOCK-STREAM 0)))
    (when (fx= fd -1)
      (error '~check-tls "socket failed"))
    (let ((address (make-ftype-pointer
                    %sockaddr-in (foreign-alloc (ftype-sizeof %sockaddr-in)))))
      (ftype-set! %sockaddr-in (family) address %AF-INET)
      (ftype-set! %sockaddr-in (port) address 0)
      ;; 127.0.0.1, already in network order as a little-endian word.
      (ftype-set! %sockaddr-in (addr) address #x0100007f)
      (ftype-set! %sockaddr-in (zero1) address 0)
      (ftype-set! %sockaddr-in (zero2) address 0)
      (let ((rc (%bind fd (ftype-pointer-address address)
                       (ftype-sizeof %sockaddr-in))))
        (unless (zero? rc)
          (foreign-free (ftype-pointer-address address))
          (%close fd)
          (error '~check-tls "bind failed")))
      (let ((rc (%listen fd 1)))
        (unless (zero? rc)
          (foreign-free (ftype-pointer-address address))
          (%close fd)
          (error '~check-tls "listen failed")))
      (let ((length* (foreign-alloc 4)))
        (foreign-set! 'unsigned-32 length* 0 (ftype-sizeof %sockaddr-in))
        (let ((rc (%getsockname fd (ftype-pointer-address address) length*)))
          (foreign-free length*)
          (unless (zero? rc)
            (foreign-free (ftype-pointer-address address))
            (%close fd)
            (error '~check-tls "getsockname failed"))))
      (let ((port (%swap16 (ftype-ref %sockaddr-in (port) address))))
        (foreign-free (ftype-pointer-address address))
        (values fd port)))))

(define (%condition->string e)
  (let ((out (open-output-string)))
    (display-condition e out)
    (get-output-string out)))

(define (%string-contains? text pattern)
  (let ((n (string-length text))
        (m (string-length pattern)))
    (let loop ((i 0))
      (cond
       ((fx> (fx+ i m) n) #f)
       ((string=? (substring text i (fx+ i m)) pattern) #t)
       (else (loop (fx+ i 1)))))))

(define (%elapsed-raising thunk)
  ;; Returns (values seconds condition-text) for a thunk expected to
  ;; raise, or (values seconds #f) when it returned instead.
  (let ((started (real-time)))
    (guard (e (#t (values (/ (- (real-time) started) 1000.0)
                          (%condition->string e))))
      (thunk)
      (values (/ (- (real-time) started) 1000.0) #f))))

;; ---- url-parse: pure, no libtls, no network ----

(define (~check-tls-url-parse-000)
  (let-values (((scheme host port target)
                (url-parse "https://example.com/a/b?c=d")))
    (and (string=? scheme "https")
         (string=? host "example.com")
         (not port)
         (string=? target "/a/b?c=d"))))

(define (~check-tls-url-parse-001)
  ;; Explicit port, and no path at all -- the target must default to /.
  (let-values (((scheme host port target)
                (url-parse "https://example.com:8443")))
    (and (string=? scheme "https")
         (string=? host "example.com")
         (eqv? port 8443)
         (string=? target "/"))))

(define (~check-tls-url-parse-002)
  (let-values (((seconds text) (%elapsed-raising
                                (lambda () (url-parse "example.com/a")))))
    (and text (%string-contains? text "invalid URL"))))

;; ---- the handshake read timeout, deterministically ----

(define (~check-tls-handshake-timeout)
  (check-skip-unless libtls
    (let-values (((listener port) (%blackhole-listen)))
      (let-values (((seconds text)
                    (%elapsed-raising
                     (lambda ()
                       (parameterize ((https-timeout-seconds 1))
                         (tls-open "127.0.0.1" port))))))
        (%close listener)
        (and text
             (%string-contains? text "timed out")
             ;; One window, not zero (which would mean it failed for
             ;; some other reason) and not forever (the bug). The upper
             ;; bound is loose on purpose: a loaded machine may take a
             ;; while to notice, but nothing legitimate takes 10s.
             (>= seconds 0.5)
             (<= seconds 10.0))))))

;; ---- the connect timeout, where the environment permits ----

(define (~check-tls-connect-timeout)
  (check-skip-unless libtls
    ;; SO_SNDTIMEO is what bounds connect(2). Proving that needs an
    ;; address that silently drops SYNs: 192.0.2.1 is TEST-NET-1, which
    ;; is reserved and normally goes nowhere. But a host with no route
    ;; to it fails instantly with ENETUNREACH instead of hanging, and
    ;; then there is nothing here to measure -- so an instant failure is
    ;; reported and passed rather than called a regression.
    (let-values (((seconds text)
                  (%elapsed-raising
                   (lambda ()
                     (parameterize ((https-timeout-seconds 2))
                       (tls-open "192.0.2.1" 443))))))
      (cond
       ((not text) #f)
       ((< seconds 0.5)
        (display "** SKIP: no blackhole route to 192.0.2.1 (")
        (display seconds)
        (display "s, rejected rather than dropped)")
        (newline)
        #t)
       (else (and (%string-contains? text "connect failed")
                  (<= seconds 10.0)))))))

;; ---- end to end, against a live host ----

(define (%request-attempt)
  ;; A top-level helper rather than an internal define, because
  ;; check-skip-unless expands its body into an `if` arm -- an
  ;; expression context, where a definition is not allowed.
  (guard (e (#t #f))
    (let-values (((version code reason headers body)
                  (https-request "GET" "https://example.com/" '()
                                 (bytevector))))
      (and (eqv? code 200)
           (bytevector? body)
           (> (bytevector-length body) 0)))))

(define (~check-tls-request-000)
  ;; Needs the network, like the ~check-tls-uring-000 it mirrors. One
  ;; retry to absorb a flake.
  (check-skip-unless libtls
    (or (%request-attempt) (%request-attempt))))

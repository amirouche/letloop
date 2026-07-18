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

  ;; Returns (values ctx fd); tear down with tls-shutdown.
  (define tls-open
    (lambda (host port)
      (%tls-ensure-init)
      (let ((config (tls-config-new)))
        (when (zero? config)
          (error 'tls-open "tls_config_new failed"))
        (let ((rc (tls-config-set-protocols config TLS_PROTOCOLS_DEFAULT)))
          (unless (zero? rc)
            (let ((msg (tls-config-error config)))
              (tls-config-free config)
              (error 'tls-open "tls_config_set_protocols failed" msg))))
        (let ((ctx (tls-client)))
          (when (zero? ctx)
            (tls-config-free config)
            (error 'tls-open "tls_client failed"))
          (let ((rc (tls-configure ctx config)))
            (unless (zero? rc)
              (let ((msg (tls-error ctx)))
                (tls-config-free config)
                (tls-free ctx)
                (error 'tls-open "tls_configure failed" msg))))
          (tls-config-free config)
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

  ;; Async HTTPS client; returns (values code headers body), or
  ;; (values #f #f #f) on error. Must run inside a loop coroutine.
  (define www-request
    (lambda (method url headers body)
      ;; Track the live TLS context and socket so the guard handler can
      ;; release them: without teardown every failed request leaks an fd
      ;; and a libtls context until EMFILE.
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
            (let ((port* (or port (if (string=? scheme "https") 443 80))))
              ;; NOTE: cannot use dynamic-wind here because loop-abort
              ;; uses continuations that would trigger the exit guard
              ;; prematurely
              (let-values (((ctx fd) (tls-open host port*)))
                (set! live-ctx ctx)
                (set! live-fd fd)
                (let ((headers* (if (assq 'host headers)
                                    headers
                                    (cons (cons 'host host) headers))))
                  ;; Write request
                  (let ((write! (tls-writer ctx fd)))
                    (http-request-write write!
                                        method
                                        request-target
                                        'HTTP/1.1
                                        headers*
                                        (if (bytevector? body)
                                            (let ((sent #f))
                                              (lambda ()
                                                (if sent
                                                    (eof-object)
                                                    (begin (set! sent #t) body))))
                                            body)))
                  ;; Read response
                  (let-values (((version code reason resp-headers resp-body)
                                (http-response-read (tls-reader ctx fd))))
                    ;; Clear before tls-shutdown so a failure inside it
                    ;; cannot lead to a double free from the guard.
                    (set! live-ctx #f)
                    (set! live-fd #f)
                    (tls-shutdown ctx fd)
                    (values code resp-headers resp-body))))))))))

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

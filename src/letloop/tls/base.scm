#!chezscheme
(library (letloop tls base)

  (export tls-open
          tls-reader
          tls-writer
          tls-shutdown
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

  ;; tls-open: connect to host:port, return opaque TLS context
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
          (let ((rc (tls-connect ctx host (if port (number->string port) "443"))))
            (unless (zero? rc)
              (let ((msg (tls-error ctx)))
                (tls-free ctx)
                (error 'tls-open "tls_connect failed" msg))))
          ;; Retry handshake on WANT_POLLIN/POLLOUT
          (let loop ()
            (let ((rc (tls-handshake ctx)))
              (cond
               ((zero? rc) (void))
               ((or (= rc TLS_WANT_POLLIN) (= rc TLS_WANT_POLLOUT))
                (loop))
               (else
                (let ((msg (tls-error ctx)))
                  (tls-close ctx)
                  (tls-free ctx)
                  (error 'tls-open "tls_handshake failed" msg))))))
          ctx))))

  ;; tls-reader: return a thunk (lambda () -> bytevector | eof-object)
  (define tls-reader
    (lambda (ctx)
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
               ((or (= n TLS_WANT_POLLIN) (= n TLS_WANT_POLLOUT))
                (loop))
               (else
                (error 'tls-reader "tls_read failed" (tls-error ctx))))))))))

  ;; tls-writer: return a procedure (lambda (bytevector) -> void)
  (define tls-writer
    (lambda (ctx)
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
                 ((or (= n TLS_WANT_POLLIN) (= n TLS_WANT_POLLOUT))
                  (loop offset))
                 (else
                  (error 'tls-writer "tls_write failed" (tls-error ctx)))))))))))

  ;; tls-shutdown: close and free context
  (define tls-shutdown
    (lambda (ctx)
      (tls-close ctx)
      (tls-free ctx)))

  ;; URL parser (internal)
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
        (let ((ctx (tls-open host (or port 443))))
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
              (tls-shutdown ctx)))))))

)

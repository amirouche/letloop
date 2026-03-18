(library (http-serve)
  (export main)
  (import (chezscheme) (letloop http) (untangle))

  (define pk
    (lambda args
      (display ";; ")(write args)(newline)
      (flush-output-port)
      (car (reverse args))))

  (define message "Hello, World!")

  (define handle
    (lambda (read write close)
      (define reader (lambda ()
                       (let ((r (read)))
                         (if (bytevector? r) r (eof-object)))))
      (let loop ()
        (guard (ex (else (pk 'handle (apply format #f (condition-message ex)
                                            (condition-irritants ex)))))
          (call-with-values (lambda () (http-request-read reader))
            (lambda (method uri version headers body)
              (when method
                (let ((body-bv (string->utf8 message)))
                  (http-response-write write "HTTP/1.1" 200 "Found" '()
                                       (let ((done #f))
                                         (lambda ()
                                           (if done
                                               (eof-object)
                                               (begin (set! done #t) body-bv))))))
                (loop))))))
      (close)))

  (define main*
    (lambda (port)
      (pk 'port port)
      (call-with-values (lambda () (untangle-tcp-serve "0.0.0.0" port))
        (lambda (accept close)
          (pk 'fu43)
          (format #t "HTTP server running at http://127.0.0.1:~a\n" port)
          (let loop ()
            (when (guard (ex (else
                              (pk 'accept (apply format #f
                                                 (condition-message ex)
                                                 (condition-irritants ex)))
                              (untangle-stop)
                        #f))
                    (call-with-values accept
                      (lambda (read write close)
                        (pk 'recv read write close)
                        (if (not (and read write close))
                            #f
                            (untangle-spawn
                             (lambda ()
                               (handle read write close)
                               #t))))))
              (loop)))))))

  (define main
    (lambda (port)
      (define port* (string->number port))
      (untangle-new)
      (untangle-spawn (lambda () (main* port*)))
      (untangle-run)))

  )

;; Application for checks/repro-http-tenth-pass.sh, the tenth-pass HTTP
;; reproducers. Answers every request with what the server made of it:
;;   M=<method> P=<path segments> B=<body length>
(library (repro-http-tenth-pass-lib)
  (export application context dispatch)
  (import (chezscheme)
          (letloop http server)
          (letloop picohttpparser))
  (define application (lambda () #f))
  (define context (lambda (application client req) client))
  (define dispatch
    (lambda (application state method path params req)
      (values 200
              (cons (string->utf8
                     (format #f "M=~a P=~s B=~a\n" method path
                             (let ((body (phr-request-body req)))
                               (if (bytevector? body)
                                   (bytevector-length body)
                                   body))))
                    "text/plain")
              '()))))

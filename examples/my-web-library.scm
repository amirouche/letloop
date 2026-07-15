;; Serve with:
;;
;;   letloop http serve [--port=8080] src/ examples/my-web-library.scm
;;
;; Routes:
;;   GET /            → HTML greeting
;;   GET /api?who=you → JSON echo of the query
;;   POST /api        → JSON with the request body length
;;   anything else    → 404
(library (my-web-library)

  (export application context dispatch)

  (import (chezscheme)
          (letloop http server))

  ;; App-wide state, created once at startup.
  (define application
    (lambda ()
      (let ((hits (box 0)))
        hits)))

  ;; Per-connection state, created on the first request; CLIENT is
  ;; the peer IP, REQ the parsed request.
  (define context
    (lambda (app client req)
      client))

  (define dispatch
    (lambda (app client method path params req)
      (set-box! app (+ 1 (unbox app)))
      (cond
       ((and (eq? method 'GET) (null? path))
        (values 200
                (html `(html (body (h1 "hello, world")
                                   (p "hits: " ,(number->string (unbox app))))))
                '()))
       ((and (eq? method 'GET) (equal? path '("api")))
        (values 200
                (json `((hello . ,(cond ((assq 'who params) => cdr)
                                        (else "world")))
                        (hits . ,(unbox app))))
                '()))
       ((and (eq? method 'POST) (equal? path '("api")))
        (values 201
                (json `((received . ,(bytevector-length (phr-request-body req)))))
                '()))
       (else
        (values 404 (json '((error . "not found"))) '()))))))

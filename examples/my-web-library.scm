#!chezscheme
;; Serve with:
;;
;;   letloop http serve [--port=8080] examples/ examples/my-web-library.scm
;;
;; Routes:
;;   GET /            → HTML counter page
;;   POST /increment  → 302 back to /
;;   GET /sleep       → 200 after a 1s io_uring sleep
;;   GET /api?who=you → JSON echo of the query
;;   POST /api        → JSON with the request body length
;;   anything else    → 404
(library (my-web-library)

  (export application context dispatch)

  (import (chezscheme)
          (letloop match)
          (letloop http server)
          (only (letloop liburing low) loop-sleep))

  ;; App-wide state, created once at startup.
  (define (application) (box 0))

  ;; Per-connection state, created on the first request; CLIENT is
  ;; the peer IP, REQ the parsed request.
  (define (context application client req) client)

  (define (dispatch application request-state method path params req)
    (match (cons method path)
      ((GET)
       (values 200
               (html `(html (body
                 (h1 ,(format #f "Count: ~a" (unbox application)))
                 (p "Press Ctrl-C for graceful shutdown")
                 (form (@ (method "POST") (action "/increment"))
                   (button (@ (type "submit")) "Increment")))))
               '()))
      ((POST "increment")
       (set-box! application (+ (unbox application) 1))
       (values 302 (cons (bytevector) "text/plain") '((location . "/"))))
      ((GET "sleep")
       ;; Demo: io_uring-based sleep (1 second)
       (loop-sleep 1)
       (values 200
               (html `(html (body (h1 "Slept 1 second (via io_uring timeout)"))))
               '()))
      ((GET "api")
       (values 200
               (json `((hello . ,(cond ((assq 'who params) => cdr)
                                       (else "world")))
                       (count . ,(unbox application))))
               '()))
      ((POST "api")
       (values 201
               (json `((received . ,(bytevector-length (phr-request-body req)))))
               '()))
      (,_
       (values 404 (html `(html (body (h1 "Not Found")))) '())))))

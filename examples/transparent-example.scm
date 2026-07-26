#!chezscheme
;; Serve with:
;;
;;   letloop http serve [--port=8080] examples/ examples/transparent-example.scm
;;
;; or standalone via letloop compile/exec, see benchmarks/scheme/bench-server.scm.
(library (transparent-example)
  (export application context dispatch main)
  (import (chezscheme) (letloop match) (letloop http server))

  (define (application) (box 0))
  (define (context application client req) #f)

  (define (dispatch application request-state method path params req)
    (match (cons method path)
      ((GET)
       (values 200
               (html `(html (body
                 (h1 ,(format #f "Count: ~a" (unbox application)))
                 (form (@ (method "POST") (action "/increment"))
                   (button (@ (type "submit")) "Increment")))))
               '()))
      ((POST "increment")
       (set-box! application (+ (unbox application) 1))
       (values 302 (cons (bytevector) "text/plain") '((location . "/"))))
      (,_
       (values 404 (html `(html (body (h1 "Not Found")))) '()))))

  (define (main port)
    (transparent (string->number port) application context dispatch)))

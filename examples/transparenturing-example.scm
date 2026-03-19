#!chezscheme
(library (transparenturing-example)
  (export main)
  (import (chezscheme) (transparenturing))

  (define (app) (box 0))
  (define (init) #f)

  (define (handler app-state request-state method path params body)
    (match (cons method path)
      ((GET)
       (values 200
               (html `(html (body
                 (h1 ,(format #f "Count: ~a" (unbox app-state)))
                 (p "Press Ctrl-C for graceful shutdown")
                 (form (@ (method "POST") (action "/increment"))
                   (button (@ (type "submit")) "Increment")))))
               '()))
      ((GET "sleep")
       ;; Demo: io_uring-based sleep (1 second)
       (loop-sleep 1000000000)
       (values 200
               (html `(html (body (h1 "Slept 1 second (via io_uring timeout)"))))
               '()))
      ((POST "increment")
       (set-box! app-state (+ (unbox app-state) 1))
       (values 302 (cons (bytevector) "text/plain") '((location . "/"))))
      (,_
       (values 404 (html `(html (body (h1 "Not Found")))) '()))))

  (define (main port)
    (transparent (string->number port) app init handler)))

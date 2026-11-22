;; Application for checks/check-http-keepalive-semantics.sh. /slow
;; suspends for 0.3s, long enough for the client to pipeline or
;; half-close while DISPATCH runs; anything else answers at once.
(library (check-http-keepalive-semantics-lib)
  (export application context dispatch)
  (import (chezscheme)
          (letloop http server)
          (only (letloop flow2) flow-sleep))
  (define (application) #f)
  (define (context application client req) client)
  (define (dispatch application state method path params req)
    (when (equal? path '("slow")) (flow-sleep 0.3))
    (values 200
            (cons (string->utf8 (format #f "ok ~a" path)) "text/plain")
            '())))

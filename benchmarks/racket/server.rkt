#lang racket/base

(require racket/cmdline
         web-server/servlet-env
         web-server/http/request-structs
         web-server/http/response-structs
         web-server/http/redirect
         net/url)

(define count 0)

(define (start req)
  (define method (request-method req))
  (define path (url->string (request-uri req)))

  (cond
    [(and (bytes=? method #"GET") (or (string=? path "/") (string=? path "")))
     (response/full
      200 #"OK"
      (current-seconds) TEXT/HTML-MIME-TYPE
      '()
      (list (string->bytes/utf-8
             (format "<html><body>
<h1>Count: ~a</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method=\"POST\" action=\"/increment\">
<button type=\"submit\">Increment</button>
</form>
<footer><small>Racket ~a [cs] | web-server (stdlib) | epoll | single-threaded</small></footer>
</body></html>" count (version)))))]

    [(and (bytes=? method #"POST") (string=? path "/increment"))
     (set! count (add1 count))
     (redirect-to "/" temporarily)]

    [(and (bytes=? method #"GET") (string=? path "/sleep"))
     (sleep 1)
     (response/full
      200 #"OK"
      (current-seconds) TEXT/HTML-MIME-TYPE
      '()
      (list #"<html><body><h1>Slept 1 second (via sleep)</h1></body></html>"))]

    [else
     (response/full
      404 #"Not Found"
      (current-seconds) TEXT/HTML-MIME-TYPE
      '()
      (list #"<html><body><h1>Not Found</h1></body></html>"))]))

(define port
  (command-line
   #:args (port-str)
   (string->number port-str)))

(serve/servlet start
               #:port port
               #:listen-ip "127.0.0.1"
               #:servlet-path "/"
               #:servlet-regexp #rx""
               #:command-line? #t
               #:launch-browser? #f)

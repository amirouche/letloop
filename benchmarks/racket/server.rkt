#lang racket/base

;; Served through web-server's core `serve` with a lifted
;; request->response function (dispatch-lift) rather than
;; serve/servlet: the servlet path wraps every request in the
;; stateful-servlet machinery — a threshold-LRU continuation manager,
;; instance bookkeeping, and a dispatcher-sequence that falls through
;; to filesystem dispatchers — none of which any other implementation
;; in this suite pays for. This handler never captures continuations
;; (no send/suspend), so the lean dispatcher is the honest equivalent
;; of what Rust/Go/Node do: route, build response, write it.
;;
;; `sleep` is Racket's green-thread sleep: it parks only this
;; connection's thread, the server keeps answering — same
;; non-blocking behaviour as tokio::time::sleep / setTimeout.

(require racket/cmdline
         web-server/web-server
         (prefix-in lift: web-server/dispatchers/dispatch-lift)
         web-server/http/request-structs
         web-server/http/response-structs
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
     ;; 302 with an explicit empty body: redirect-to builds a
     ;; response/output, which the server frames as a chunked body
     ;; even though it is empty — every other implementation sends
     ;; Content-Length: 0 here.
     (response/full
      302 #"Found"
      (current-seconds) #f
      (list (make-header #"Location" #"/"))
      '())]

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

(serve #:dispatch (lift:make start)
       #:listen-ip "127.0.0.1"
       #:port port)

(do-not-return)

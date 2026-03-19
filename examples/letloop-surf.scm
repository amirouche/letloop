(library (letloop-surf)
  (export main)
  (import (chezscheme) (letloop www))

  (define extension->content-type
    (lambda (filename)
      (define ext
        (let loop ((chars (reverse (string->list filename)))
                   (out '()))
          (cond
            ((null? chars) #f)
            ((char=? (car chars) #\.)
             (list->string (cons #\. out)))
            (else (loop (cdr chars) (cons (car chars) out))))))
      (cond
        ((not ext) "application/octet-stream")
        ((string=? ext ".json") "application/json")
        ((string=? ext ".xml") "application/xml")
        ((string=? ext ".html") "text/html")
        ((string=? ext ".txt") "text/plain")
        ((string=? ext ".csv") "text/csv")
        ((string=? ext ".js") "application/javascript")
        ((string=? ext ".css") "text/css")
        ((string=? ext ".png") "image/png")
        ((string=? ext ".jpg") "image/jpeg")
        ((string=? ext ".jpeg") "image/jpeg")
        ((string=? ext ".gif") "image/gif")
        ((string=? ext ".pdf") "application/pdf")
        (else "application/octet-stream"))))

  (define read-file-as-bytevector
    (lambda (path)
      (let* ((port (open-file-input-port path))
             (data (get-bytevector-all port)))
        (close-port port)
        (if (eof-object? data) (bytevector) data))))

  (define display-response
    (lambda (code headers body)
      (display "HTTP ")
      (display code)
      (newline)
      (for-each
        (lambda (h)
          (display (car h))
          (display ": ")
          (display (cdr h))
          (newline))
        headers)
      (newline)
      (when (and body (> (bytevector-length body) 0))
        (display (utf8->string body)))
      (flush-output-port)))

  (define main
    (lambda args
      (when (< (length args) 2)
        (display "Usage: letloop-surf METHOD URL [PAYLOAD-FILE [CONTENT-TYPE]]\n")
        (exit 1))
      (let* ((method (string->symbol (list-ref args 0)))
             (url (list-ref args 1))
             (payload-file (and (>= (length args) 3) (list-ref args 2)))
             (content-type-arg (and (>= (length args) 4) (list-ref args 3)))
             (body (if payload-file
                       (read-file-as-bytevector payload-file)
                       (bytevector)))
             (content-type (cond
                             (content-type-arg content-type-arg)
                             (payload-file (extension->content-type payload-file))
                             (else #f)))
             (headers (if content-type
                          (list (cons 'content-type content-type))
                          '())))
        (call-with-values
          (lambda () (www-request method url headers body))
          display-response)))))

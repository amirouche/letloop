#!chezscheme
(library (letloop html base)
  (export
   html-read
   html-write
   string->html-string
   ~check-letloop-html-write-0
   ~check-letloop-html-write-1
   ~check-letloop-html-write-2
   ~check-letloop-html-write-3
   ~check-letloop-html-write-4
  )
  (import (chezscheme) (letloop match) (letloop html htmlprag))

  ;; ref: https://html.spec.whatwg.org/

  (define html-element-no-end-tag
    '(area
      base
      br
      col
      command
      embed
      hr
      img
      input
      keygen
      link
      meta
      param
      source
      track
      wbr))

  (define html-element-no-end-tag?
    (lambda (tag)
      (pair? (memq tag html-element-no-end-tag))))

  (define html-character->string
    (lambda (char)
      (cdr
       (or (assv char
                 '((#\" . "&quot;")
                   (#\& . "&amp;")
                   (#\< . "&lt;")
                   (#\> . "&gt;")))
           (cons char (list->string (list char)))))))

  ;; One output port, no per-character allocation. The obvious
  ;; (apply string-append (map html-character->string (string->list s)))
  ;; costs a cons + a one-char string per character plus an N-argument
  ;; apply, which dominated HTML rendering on the server's hot path.
  (define string->html-string
    (lambda (string)
      (let ((port (open-output-string)))
        (string-for-each
         (lambda (ch)
           (case ch
             ((#\<) (put-string port "&lt;"))
             ((#\>) (put-string port "&gt;"))
             ((#\&) (put-string port "&amp;"))
             ((#\") (put-string port "&quot;"))
             (else (put-char port ch))))
         string)
        (get-output-string port))))

  (define html-doctype "<!DOCTYPE html>")

  (define html-write-tag-start
    (lambda (tag attributes accumulator)
      (accumulator (string-append "<" (symbol->string tag)))
      (for-each
       (lambda (attribute)
         ;; Escape the value, otherwise a quote inside it breaks out
         ;; of the attribute (injection).
         (let ((value (cadr attribute)))
           (accumulator (string-append " " (symbol->string (car attribute)) "=\""
                                       (string->html-string
                                        (if (string? value)
                                            value
                                            (format #f "~a" value)))
                                       "\""))))
       attributes)
      (if (html-element-no-end-tag? tag)
          (accumulator "/>")
          (accumulator ">"))))

  (define html-write-tag-end
    (lambda (tag accumulator)
      (unless (html-element-no-end-tag? tag)
        (accumulator (string-append "</" (symbol->string tag) ">")))))

  (define html-write
    (case-lambda
     ((object accumulator)
      (cond
       ((string? object) (accumulator (string->html-string object)))
       ((number? object) (accumulator (number->string object)))
       (else
        (match object
          ((,tag (@ ,attributes ...) ,elements ...)
           (html-write-tag-start tag attributes accumulator)
           (for-each (lambda (element) (html-write element accumulator))
                     elements)
           (html-write-tag-end tag accumulator))
          ((,tag ,elements ...)
           (html-write-tag-start tag '() accumulator)
           (for-each (lambda (element) (html-write element accumulator))
                     elements)
           (html-write-tag-end tag accumulator))))))
     ((object)
      (define out (make-accumulator))
      (html-write object out)
      (out (eof-object)))))

  (define html-read html->sxml)

  (define make-accumulator
    (lambda ()
      (let ((out '()))
        (lambda (object)
          (if (eof-object? object)
              (apply string-append (reverse out))
              (set! out (cons object out)))))))

  (define ~check-letloop-html-write-0
    (lambda ()
      (define html `(h1 "hello" (b "world")))

      (assert
       (string=? "<h1>hello<b>world</b></h1>"
                 (html-write html)))))

  (define ~check-letloop-html-write-1
    (lambda ()
      (define html `(h1 "<&>!"))

      (assert
       (string=? "<h1>&lt;&amp;&gt;!</h1>"
                 (html-write html)))))

  (define ~check-letloop-html-write-2
    (lambda ()
      (define html `(a (@ (href "https://hyper.dev"))
                       "hello you"))
      (assert
       (string=? "<a href=\"https://hyper.dev\">hello you</a>"
                 (html-write html)))))
                 
  (define ~check-letloop-html-write-3
    (lambda ()
      (define html `(p "echo" (br) "bravo"))

      (assert
       (string=? "<p>echo<br/>bravo</p>"
                 (html-write html)))))

  (define ~check-letloop-html-write-4
    (lambda ()
      ;; Attribute values are escaped; non-strings are coerced.
      (define html `(input (@ (value "say \"hi\" & <bye>") (size 10))))
      (assert
       (string=? "<input value=\"say &quot;hi&quot; &amp; &lt;bye&gt;\" size=\"10\"/>"
                 (html-write html)))))

  )

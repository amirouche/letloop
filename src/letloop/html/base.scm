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
   ~check-letloop-html-read-0
   ~check-letloop-html-read-1
   ~check-letloop-html-read-2
   ~check-letloop-html-read-3
  )
  ;; Only html->sxml: (letloop html justhtml) also exports its tables,
  ;; tokenizer and generic helpers such as char-ascii-digit?.
  (import (chezscheme) (letloop match)
          (only (letloop html justhtml) html->sxml))

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

  ;; Parse an HTML document, given as a string or a textual input port,
  ;; into one SXML tree rooted at *TOP*. The parser is the WHATWG
  ;; algorithm of (letloop html justhtml): the html, head and body
  ;; elements are always there, implied when the source omits them, and
  ;; malformed markup is recovered, never raised.
  (define html-read
    (lambda (object)
      (html->sxml
       (if (string? object)
           object
           (let ((string (get-string-all object)))
             (if (eof-object? string) "" string))))))

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

  (define ~check-letloop-html-read-0
    (lambda ()
      ;; html, head and body are implied, as a browser builds them.
      (assert
       (equal? '(*TOP* (html (head) (body (p "a" (br) "b"))))
               (html-read "<p>a<br>b")))))

  (define ~check-letloop-html-read-1
    (lambda ()
      ;; A character reference is decoded in text and in an attribute
      ;; value alike.
      (assert
       (equal? '(*TOP* (html (head)
                             (body (a (@ (href "?a=1&b=2")) "x & y"))))
               (html-read "<a href=\"?a=1&amp;b=2\">x &amp; y</a>")))))

  (define ~check-letloop-html-read-2
    (lambda ()
      ;; A textual port reads the same as its content; an empty one is
      ;; an empty document.
      (assert
       (equal? (html-read "<title>t</title><p>x")
               (html-read (open-input-string "<title>t</title><p>x"))))
      (assert
       (equal? '(*TOP* (html (head) (body)))
               (html-read (open-input-string ""))))))

  (define ~check-letloop-html-read-3
    (lambda ()
      ;; What html-read returns for a page, html-write accepts.
      (assert
       (string=? "<html><head></head><body><p>a<br/>b</p></body></html>"
                 (html-write (cadr (html-read "<p>a<br>b</p>")))))))

  )

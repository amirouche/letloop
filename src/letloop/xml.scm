#!chezscheme
;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop xml)

  (export xml-write
          ~check-xml-000
          ~check-xml-001
          ~check-xml-002)

  (import (chezscheme)
          (letloop match)
          (letloop html base))

  ;; SXML writer. Unlike html-write, every element gets an explicit
  ;; end tag (XML has no void elements).

  (define make-accumulator
    (lambda ()
      (let ((out '()))
        (lambda (object)
          (if (eof-object? object)
              (apply string-append (reverse out))
              (set! out (cons object out)))))))

  (define xml-write
    (case-lambda
     ((object accumulator)
      (cond
       ((string? object) (accumulator (string->html-string object)))
       ((number? object) (accumulator (number->string object)))
       (else
        (match object
          ((,tag (@ ,attributes ...) ,elements ...)
           (accumulator (format #f "<~a" tag))
           (for-each
            (lambda (attribute)
              (accumulator (format #f " ~a=\"~a\""
                                   (car attribute)
                                   (string->html-string (format #f "~a" (cadr attribute))))))
            attributes)
           (accumulator ">")
           (for-each (lambda (element) (xml-write element accumulator)) elements)
           (accumulator (format #f "</~a>" tag)))
          ((,tag ,elements ...)
           (accumulator (format #f "<~a>" tag))
           (for-each (lambda (element) (xml-write element accumulator)) elements)
           (accumulator (format #f "</~a>" tag)))))))
     ((object)
      (let ((out (make-accumulator)))
        (xml-write object out)
        (out (eof-object))))))

  (define ~check-xml-000
    (lambda ()
      (string=? "<feed><title>hello</title><count>42</count></feed>"
                (xml-write '(feed (title "hello") (count 42))))))

  (define ~check-xml-001
    (lambda ()
      ;; Text and attribute values are escaped.
      (string=? "<entry lang=\"&quot;fr&quot;\">a &lt; b &amp; c</entry>"
                (xml-write '(entry (@ (lang "\"fr\"")) "a < b & c")))))

  (define ~check-xml-002
    (lambda ()
      ;; No void elements: empty tags still close explicitly.
      (string=? "<br></br>" (xml-write '(br)))))

  )

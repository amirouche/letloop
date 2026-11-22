;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Included at the tail of the library; discovered by `make check` via
;; the ~check- exports. The checks of the entity, scanner, tokenizer and
;; tree-construction layers come first, in that order, then the generated
;; fixtures (section 6), which also define html-fixture-check,
;; html-fixtures-report and html-fixture-entries.

;; Tests -- every case of
;; submodules/justhtml/tests/justhtml-tests/entities.test plus a few
;; direct checks of the numeric edge cases.

(define check-decode
  (lambda (input expected)
    (let ((actual (html-entity-text-decode input #f)))
      (unless (string=? actual expected)
        (error 'html-entity-text-decode "mismatch" input expected actual))
      #t)))

(define check-decode-attribute
  (lambda (input expected)
    (let ((actual (html-entity-text-decode input #t)))
      (unless (string=? actual expected)
        (error 'html-entity-text-decode "mismatch in attribute" input expected actual))
      #t)))

(define ~check-entities-numeric-missing-semicolon
  (lambda ()
    (check-decode "&#65" "A")))

(define ~check-entities-numeric-hexadecimal-c1
  (lambda ()
    (check-decode "&#x80" (string (integer->char #x20AC)))))

(define ~check-entities-numeric-noncharacter
  (lambda ()
    (check-decode "&#xFDD0;" (string (integer->char #xFDD0)))))

(define ~check-entities-legacy-prefix-with-semicolon
  (lambda ()
    (check-decode "&notit;" (string-append (string (integer->char #xAC)) "it;"))))

(define ~check-entities-legacy-without-semicolon
  (lambda ()
    (check-decode "&not" (string (integer->char #xAC)))))

(define ~check-entities-legacy-prefix-without-semicolon
  (lambda ()
    (check-decode "&notit" (string-append (string (integer->char #xAC)) "it"))))

(define ~check-entities-named-basic
  (lambda ()
    (check-decode "&amp;" "&")
    (check-decode "&lt;&gt;" "<>")
    (check-decode "a&nbsp;b" (string-append "a" (string (integer->char #xA0)) "b"))
    (check-decode "&notin;" (string (integer->char #x2209)))))

(define ~check-entities-numeric-out-of-range
  (lambda ()
    (check-decode "&#x110000;" replacement-character-string)))

(define ~check-entities-numeric-surrogate
  (lambda ()
    (check-decode "&#xD800;" replacement-character-string)))

(define ~check-entities-numeric-null
  (lambda ()
    (check-decode "&#0;" replacement-character-string)))

(define ~check-entities-attribute-ambiguous-ampersand
  (lambda ()
    (check-decode-attribute "&notit" "&notit")
    (check-decode-attribute "&not=x" "&not=x")))

(define ~check-entities-attribute-semicolon-terminated
  (lambda ()
    (check-decode-attribute "&amp;" "&")
    (check-decode-attribute "&notit;" "&notit;")))

(define ~check-entities-bare-ampersand
  (lambda ()
    (check-decode "&" "&")
    (check-decode "a & b" "a & b")
    (check-decode "&#" "&#")
    (check-decode "&#x" "&#x")))

(define ~check-entities-multi-character-value
  (lambda ()
    ;; "NotEqualTilde;" decodes to two code points.
    (check-decode "&NotEqualTilde;"
                  (string (integer->char #x2242) (integer->char #x338)))))

;; Tests

(define check-scanner-equal
  (lambda (name actual expected)
    (unless (equal? actual expected)
      (error name "mismatch" expected actual))
    #t))

(define ~check-scanner-ascii-find
  (lambda ()
    (check-scanner-equal 'html-scanner-ascii-find
                 (html-scanner-ascii-find "abc</SCRIPT>" "</script" 0 12) 3)
    (check-scanner-equal 'html-scanner-ascii-find
                 (html-scanner-ascii-find "abc</SCRIPT>" "</style" 0 12) #f)
    ;; The needle must fit inside the bound.
    (check-scanner-equal 'html-scanner-ascii-find
                 (html-scanner-ascii-find "abc</SCRIPT>" "</script" 0 8) #f)))

(define ~check-scanner-ascii-startswith
  (lambda ()
    (check-scanner-equal 'html-scanner-ascii-startswith?
                 (html-scanner-ascii-startswith? "<!DOCTYPE html>" "<!doctype" 0 15) #t)
    (check-scanner-equal 'html-scanner-ascii-startswith?
                 (html-scanner-ascii-startswith? "<!DOCTYPE html>" "<!doctype" 0 5) #f)))

(define ~check-scanner-ascii-rfind
  (lambda ()
    (check-scanner-equal 'html-scanner-ascii-rfind
                 (html-scanner-ascii-rfind "aXaXa" "x" 0 5) 3)
    (check-scanner-equal 'html-scanner-ascii-rfind
                 (html-scanner-ascii-rfind "aXaXa" "x" 0 3) 1)))

(define ~check-scanner-tag-end-unquoted
  (lambda ()
    (check-scanner-equal 'html-scanner-tag-end-find
                 (html-scanner-tag-end-find "<div class=a>rest" 4 17) 12)))

(define ~check-scanner-tag-end-quoted
  (lambda ()
    ;; The ">" inside the quoted attribute value must be skipped.
    (check-scanner-equal 'html-scanner-tag-end-find
                 (html-scanner-tag-end-find "<div title=\"a>b\">x" 4 18) 16)
    (check-scanner-equal 'html-scanner-tag-end-find
                 (html-scanner-tag-end-find "<div title='a>b'>x" 4 18) 16)))

(define ~check-scanner-tag-end-missing
  (lambda ()
    (check-scanner-equal 'html-scanner-tag-end-find
                 (html-scanner-tag-end-find "<div title=\"a>b" 4 15) #f)))

(define ~check-scanner-rawtext-end-tag
  (lambda ()
    (call-with-values
      (lambda ()
        (html-scanner-rawtext-end-tag-find "abc</STYLE>d" "style" 0 12))
      (lambda (close next)
        (check-scanner-equal 'html-scanner-rawtext-end-tag-find (list close next)
                     (list 3 11))))))

(define ~check-scanner-rawtext-end-tag-prefix
  (lambda ()
    ;; "</styles" is not an end tag for "style"; the real one follows.
    (call-with-values
      (lambda ()
        (html-scanner-rawtext-end-tag-find "a</styles></style>" "style" 0 18))
      (lambda (close next)
        (check-scanner-equal 'html-scanner-rawtext-end-tag-find (list close next)
                     (list 10 18))))))

(define ~check-scanner-rawtext-end-tag-missing
  (lambda ()
    (call-with-values
      (lambda ()
        (html-scanner-rawtext-end-tag-find "abc" "style" 0 3))
      (lambda (close next)
        (check-scanner-equal 'html-scanner-rawtext-end-tag-find (list close next)
                     (list #f 3))))))

(define ~check-scanner-script-end-tag-plain
  (lambda ()
    (let ((text "var a = 1;</script>tail"))
      (call-with-values
        (lambda () (html-scanner-script-end-tag-find text 0 (string-length text)))
        (lambda (close next)
          (check-scanner-equal 'html-scanner-script-end-tag-find (list close next)
                       (list 10 19)))))))

(define ~check-scanner-script-end-tag-escaped
  (lambda ()
    ;; Inside "<!-- ... -->" a "</script" still terminates script data, but
    ;; the escaped state must be entered and left across the "--" boundary.
    (let ((text "<!--a--></script>"))
      (call-with-values
        (lambda () (html-scanner-script-end-tag-find text 0 (string-length text)))
        (lambda (close next)
          (check-scanner-equal 'html-scanner-script-end-tag-find (list close next)
                       (list 8 17)))))))

(define ~check-scanner-script-end-tag-double-escaped
  (lambda ()
    ;; In script-data-double-escaped state the first "</script" only leaves
    ;; the double escape; the second one ends the script data.
    (let ((text "<!--<script></script>--></script>"))
      (call-with-values
        (lambda () (html-scanner-script-end-tag-find text 0 (string-length text)))
        (lambda (close next)
          (check-scanner-equal 'html-scanner-script-end-tag-find (list close next)
                       (list 24 33)))))))

(define ~check-scanner-script-start-marker
  (lambda ()
    (let ((text "a<script>b"))
      (check-scanner-equal 'html-scanner-script-start-marker-find
                   (html-scanner-script-start-marker-find text 0 10 10) 1))
    (let ((text "a<scriptx>b"))
      (check-scanner-equal 'html-scanner-script-start-marker-find
                   (html-scanner-script-start-marker-find text 0 11 11) #f))))

;; Tests
;;
;; Every case of submodules/justhtml/tests/justhtml-tests/tokenizer_states.test
;; and tokenizer_state_transitions.test is represented below.  Two of those
;; fixtures are stale -- they are not run by justhtml's own harness, which
;; only globs "*.dat" -- and are recorded here with the behaviour justhtml
;; actually produces (checked against the library) rather than the value in
;; the file; see the comments at those cases.

(define token->list
  (lambda (token)
    (cond
      ((token-start-tag? token)
       (list 'start (token-start-tag-name token)
             (token-start-tag-attributes token)
             (token-start-tag-self-closing? token)))
      ((token-end-tag? token) (list 'end (token-end-tag-name token)))
      ((token-character? token) (list 'char (token-character-text token)))
      ((token-comment? token) (list 'comment (token-comment-text token)))
      ((token-processing-instruction? token)
       (list 'processing-instruction
             (token-processing-instruction-target token)
             (token-processing-instruction-data token)))
      ((token-doctype? token)
       (list 'doctype (token-doctype-name token)
             (token-doctype-public-id token)
             (token-doctype-system-id token)
             (token-doctype-force-quirks? token)))
      (else (list 'eof)))))

;; Adjacent character tokens are merged so expectations can be written the
;; way the html5lib fixtures write them.
(define tokens->lists
  (lambda (tokens)
    (let loop ((tokens tokens) (result '()))
      (cond
        ((null? tokens) (reverse result))
        ((and (token-character? (car tokens))
              (pair? result)
              (eq? (car (car result)) 'char))
         (loop (cdr tokens)
               (cons (list 'char (string-append (cadr (car result))
                                                (token-character-text (car tokens))))
                     (cdr result))))
        (else (loop (cdr tokens) (cons (token->list (car tokens)) result)))))))

(define check-tokens
  (lambda (input expected)
    (let ((actual (tokens->lists (html-tokenize input))))
      (unless (equal? actual expected)
        (error 'html-tokenize "mismatch" input expected actual))
      #t)))

(define ~check-tokenizer-preprocessing
  (lambda ()
    ;; BOM removal, CR and CRLF normalization.
    (check-tokens (string-append (string (integer->char #xFEFF)) "<div>")
                  '((start "div" () #f)))
    (check-tokens "abc\rdef" '((char "abc\ndef")))
    (check-tokens "\r\n" '((char "\n")))
    ;; U+0000 passes through the data state unchanged.
    (check-tokens (string #\a #\nul #\b)
                  (list (list 'char (string #\a #\nul #\b))))))

(define ~check-tokenizer-basic-tags
  (lambda ()
    (check-tokens "<div>" '((start "div" () #f)))
    (check-tokens "<DIV>" '((start "div" () #f)))
    (check-tokens "</div>" '((end "div")))
    (check-tokens "<br/>" '((start "br" () #t)))
    (check-tokens "</>" '())
    (check-tokens "</?" '((comment "?")))
    (check-tokens "<?foo>" '((processing-instruction "foo" "")))
    (check-tokens "<?foo bar>" '((processing-instruction "foo" "bar")))
    ;; An unterminated processing instruction emits nothing, unless it looks
    ;; like an XML declaration or does not start with a name.
    (check-tokens "<?foo" '())
    (check-tokens "<?xml" '((comment "?xml")))
    (check-tokens "<?#abc" '((comment "?#abc")))
    (check-tokens "<?\t" '((comment "?\t")))
    (check-tokens "<?xml version=\"1.0\"?>" '((comment "?xml version=\"1.0\"?")))
    (check-tokens "<" '((char "<")))
    (check-tokens "</" '((char "</")))
    (check-tokens (string #\< #\nul #\d #\i #\v #\>)
                  (list (list 'char (string-append
                                      (string #\< (integer->char #xFFFD))
                                      "div>"))))
    (check-tokens "<div\r>" '((start "div" () #f)))
    (check-tokens "<div\n>" '((start "div" () #f)))
    (check-tokens (string #\< (integer->char #xFDD0))
                  (list (list 'char (string #\< (integer->char #xFDD0)))))
    (check-tokens (string #\a #\b (integer->char #xFDD0) #\c #\d)
                  (list (list 'char (string #\a #\b (integer->char #xFDD0) #\c #\d))))))

(define ~check-tokenizer-attributes
  (lambda ()
    (check-tokens "<div attr>" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div\r\nattr>" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div attr\r>" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div attr\r >" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div attr\r\n>" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div attr\r\t>" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div attr\n>" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div \r\n attr>" '((start "div" (("attr" . "")) #f)))
    (check-tokens "<div attr=\"a\rb\">" '((start "div" (("attr" . "a\nb")) #f)))
    (check-tokens "<div attr='a\rb'>" '((start "div" (("attr" . "a\nb")) #f)))
    (check-tokens "<div attr=\"a\nb\">" '((start "div" (("attr" . "a\nb")) #f)))
    (check-tokens "<div attr='a\nb'>" '((start "div" (("attr" . "a\nb")) #f)))
    (check-tokens "<div attr=abc>" '((start "div" (("attr" . "abc")) #f)))
    (check-tokens "<div /a>" '((start "div" (("a" . "")) #f)))
    (check-tokens "<div a<b>" '((start "div" (("a<b" . "")) #f)))
    (check-tokens "<div\r=abc>" '((start "div" (("=abc" . "")) #f)))
    (check-tokens "<div foo=\"" '())
    (check-tokens "<div foo='" '())
    (check-tokens "<div a=>" '((start "div" (("a" . "")) #f)))
    ;; U+0000 becomes U+FFFD in attribute names and values.
    (let ((r (string (integer->char #xFFFD))))
      (check-tokens (string-append "<div foo=\"a" (string #\nul) "b\">")
                    (list (list 'start "div" (list (cons "foo" (string-append "a" r "b"))) #f)))
      (check-tokens (string-append "<div foo='a" (string #\nul) "b'>")
                    (list (list 'start "div" (list (cons "foo" (string-append "a" r "b"))) #f)))
      (check-tokens (string-append "<div a" (string #\nul) "b='c'>")
                    (list (list 'start "div" (list (cons (string-append "a" r "b") "c")) #f))))
    ;; First attribute wins on duplicates.
    (check-tokens "<div a=1 a=2>" '((start "div" (("a" . "1")) #f)))
    ;; Attribute values are entity decoded in attribute context.
    (check-tokens "<div a=\"&amp;\">" '((start "div" (("a" . "&")) #f)))
    (check-tokens "<div a=\"&notit\">" '((start "div" (("a" . "&notit")) #f)))))

(define ~check-tokenizer-comments
  (lambda ()
    (check-tokens "<!--x-->" '((comment "x")))
    (check-tokens "<!---->" '((comment "")))
    (check-tokens "<!-->" '((comment "")))
    (check-tokens "<!-- test\rcomment -->" '((comment " test\ncomment ")))
    (check-tokens "<!----!\r\n" '((comment "--!\n")))
    (check-tokens "<!--a--!>" '((comment "a")))
    (check-tokens "<!x>" '((comment "x")))))

(define ~check-tokenizer-doctype
  (lambda ()
    (check-tokens "<!DOCTYPE html>" '((doctype "html" #f #f #f)))
    (check-tokens "<!doctype HTML>" '((doctype "html" #f #f #f)))
    (check-tokens "<!DOCTYPE>" '((doctype #f #f #f #t)))
    (check-tokens "<!DOCTYPE html PUBLIC \"a\" \"b\">"
                  '((doctype "html" "a" "b" #f)))
    (check-tokens "<!DOCTYPE html SYSTEM 'b'>" '((doctype "html" #f "b" #f)))
    (check-tokens "<!DOCTYPE html junk>" '((doctype "html" #f #f #t)))))

(define ~check-tokenizer-rawtext
  (lambda ()
    (check-tokens "<style>a<b</style>"
                  '((start "style" () #f) (char "a<b") (end "style")))
    (check-tokens "<style>a</styles></style>"
                  '((start "style" () #f) (char "a</styles>") (end "style")))
    (check-tokens "<xmp>&amp;</xmp>"
                  '((start "xmp" () #f) (char "&amp;") (end "xmp")))
    (check-tokens "<plaintext>a</plaintext>b"
                  '((start "plaintext" () #f) (char "a</plaintext>b")))))

(define ~check-tokenizer-script-data
  (lambda ()
    (check-tokens "<script>var a = 1;</script>"
                  '((start "script" () #f) (char "var a = 1;") (end "script")))
    ;; tokenizer_states.test records "<!--a--<<b" for this input; the value
    ;; below is what justhtml actually produces and what the spec requires.
    (check-tokens "<script><!--a--<b</script>"
                  '((start "script" () #f) (char "<!--a--<b") (end "script")))
    (check-tokens (string-append "<script><!---" (string #\nul))
                  (list '(start "script" () #f)
                        (list 'char (string-append "<!---"
                                                   (string (integer->char #xFFFD))))))
    (check-tokens "<script><!--<script></script>--></script>"
                  '((start "script" () #f)
                    (char "<!--<script></script>-->")
                    (end "script")))
    ;; U+0000 in a tag name is replaced, and the RAWTEXT switch keys off the
    ;; original tag name.
    (check-tokens (string-append "<script" (string #\nul) ">x</script>")
                  (list (list 'start (string-append "script"
                                                    (string (integer->char #xFFFD)))
                              '() #f)
                        '(char "x")
                        '(end "script")))))

(define ~check-tokenizer-rcdata
  (lambda ()
    (check-tokens "<title>a&amp;b</title>"
                  '((start "title" () #f) (char "a&b") (end "title")))
    (check-tokens "<textarea><b></textarea>"
                  '((start "textarea" () #f) (char "<b>") (end "textarea")))))

(define ~check-tokenizer-cdata
  (lambda ()
    ;; CDATA sections are only recognised when the adjusted current node is a
    ;; foreign element; otherwise they become bogus comments.
    (check-tokens "<![CDATA[x]]>" '((comment "[CDATA[x]]")))
    (let ((tokenizer (html-tokenizer-make "<![CDATA[x]]>y")))
      (html-tokenizer-foreign-set! tokenizer #t)
      (let loop ((tokens '()))
        (let ((token (html-tokenizer-next tokenizer)))
          (if (or (not token) (token-end-of-file? token))
            (let ((actual (tokens->lists (reverse tokens))))
              (unless (equal? actual '((char "xy")))
                (error 'html-tokenize "cdata mismatch" actual))
              #t)
            (loop (cons token tokens))))))))

(define ~check-tokenizer-state-transitions
  (lambda ()
    ;; tokenizer_state_transitions.test
    (check-tokens "<title >" '((start "title" () #f)))
    (check-tokens "<title id>" '((start "title" (("id" . "")) #f)))
    (check-tokens "<title id\\\">" '((start "title" (("id\\\"" . "")) #f)))
    (check-tokens "<title id >" '((start "title" (("id" . "")) #f)))
    (check-tokens "<title id=>" '((start "title" (("id" . "")) #f)))))

(define ~check-tokenizer-fixture-states
  (lambda ()
    ;; The remaining tokenizer_states.test cases not covered above.
    (check-tokens "abc\rdef" '((char "abc\ndef")))
    (check-tokens (string #\a #\newline #\b (integer->char #xFDD0) #\c)
                  (list (list 'char (string #\a #\newline #\b
                                            (integer->char #xFDD0) #\c))))
    #t))

;; ------------------------------------------------------------------
;; Tests
;; ------------------------------------------------------------------

(define check-equal
  (lambda (name actual expected)
    (unless (equal? actual expected)
      (error name "mismatch" expected actual))
    #t))

(define ~check-parser-minimal-document
  (lambda ()
    (check-equal 'html->sxml
                 (html->sxml "<html><head></head><body>x</body></html>")
                 '(*TOP* (html (head) (body "x"))))))

(define ~check-parser-implied-elements
  (lambda ()
    ;; No html/head/body in the source at all.
    (check-equal 'html->sxml
                 (html->sxml "<p>hello")
                 '(*TOP* (html (head) (body (p "hello")))))
    (check-equal 'html->sxml
                 (html->sxml "<title>t</title>x")
                 '(*TOP* (html (head (title "t")) (body "x"))))))

(define ~check-parser-doctype
  (lambda ()
    (check-equal 'html->sxml
                 (html->sxml "<!DOCTYPE html><p>x")
                 '(*TOP* (*DOCTYPE* "html" #f #f)
                         (html (head) (body (p "x")))))
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format (html->sxml "<!DOCTYPE html>"))
                 (string-append "| <!DOCTYPE html>\n"
                                "| <html>\n"
                                "|   <head>\n"
                                "|   <body>"))))

(define ~check-parser-text-merge
  (lambda ()
    ;; Adjacent character tokens must collapse into a single text node.
    (check-equal 'html->sxml
                 (html->sxml "<p>a&amp;b<!--c-->d")
                 '(*TOP* (html (head) (body (p "a&b" (*COMMENT* "c") "d")))))))

(define ~check-sxml-boolean-attribute
  (lambda ()
    (check-equal 'html->sxml
                 (html->sxml "<input disabled>")
                 '(*TOP* (html (head) (body (input (\x40; (disabled "")))))))
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format '(*TOP* (input (\x40; (disabled "")))))
                 (string-append "| <input>\n"
                                "|   disabled=\"\""))))

(define ~check-sxml-comment
  (lambda ()
    (check-equal 'html->sxml
                 (html->sxml "<!-- hi --><p>")
                 '(*TOP* (*COMMENT* " hi ") (html (head) (body (p)))))
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format '(*TOP* (*COMMENT* " hi ")))
                 "| <!--  hi  -->")))

(define ~check-sxml-doctype-public-only
  (lambda ()
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format '(*TOP* (*DOCTYPE* "html" "public-id" #f)))
                 "| <!DOCTYPE html \"public-id\" \"\">")
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format '(*TOP* (*DOCTYPE* "html" #f #f)))
                 "| <!DOCTYPE html>")))

(define ~check-sxml-template
  (lambda ()
    ;; Template content is a separate fragment, never a direct child.
    (check-equal 'html->sxml
                 (html->sxml "<template><div>x</div></template>")
                 '(*TOP* (html (head (template (*CONTENT* (div "x")))) (body))))
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format '(*TOP* (template (*CONTENT* (div "x")))))
                 (string-append "| <template>\n"
                                "|   content\n"
                                "|     <div>\n"
                                "|       \"x\""))))

(define ~check-sxml-foreign-content
  (lambda ()
    (check-equal 'html->sxml
                 (html->sxml "<svg viewBox='0 0 1 1'><g/></svg>")
                 '(*TOP* (html (head)
                               (body (svg (\x40; (viewBox "0 0 1 1")) (g))))))
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format
                   (html->sxml "<math><annotation-xml><div>"))
                 (string-append "| <html>\n"
                                "|   <head>\n"
                                "|   <body>\n"
                                "|     <math math>\n"
                                "|       <math annotation-xml>\n"
                                "|     <div>"))))

(define ~check-serializer-attribute-order
  (lambda ()
    ;; Attributes print sorted by display name, not in source order.
    (check-equal 'html-sxml->test-format
                 (html-sxml->test-format '(*TOP* (div (\x40; (zebra "1") (alpha "2")))))
                 (string-append "| <div>\n"
                                "|   alpha=\"2\"\n"
                                "|   zebra=\"1\""))))

(define ~check-html-serializer
  (lambda ()
    (check-equal 'html-sxml->html
                 (html-sxml->html '(*TOP* (*DOCTYPE* "html" #f #f)
                                          (html (head (title "t"))
                                                (body (p "a < b & c")
                                                      (br)))))
                 (string-append "<!DOCTYPE html><html><head><title>t</title>"
                                "</head><body><p>a &lt; b &amp; c</p><br>"
                                "</body></html>"))
    ;; Raw text elements keep their content unescaped.
    (check-equal 'html-sxml->html
                 (html-sxml->html '(script "if (a < b) {}"))
                 "<script>if (a < b) {}</script>")
    (check-equal 'html-sxml->html
                 (html-sxml->html '(*COMMENT* " hi "))
                 "<!-- hi -->")))

(define ~check-html-serializer-round-trip
  (lambda ()
    ;; Serializing and reparsing must reach the same tree.
    (let* ((source "<!DOCTYPE html><p>a&amp;b<em>c</em></p><ul><li>x<li>y</ul>")
           (once (html->sxml source))
           (twice (html->sxml (html-sxml->html once))))
      (check-equal 'html-sxml->html twice once))))

(define ~check-quirks-mode-detection
  (lambda ()
    (check-equal 'html-doctype-quirks-mode
                 (html-doctype-quirks-mode "html" #f #f #f #f) 'no-quirks)
    (check-equal 'html-doctype-quirks-mode
                 (html-doctype-quirks-mode "html" #f #f #t #f) 'quirks)
    (check-equal 'html-doctype-quirks-mode
                 (html-doctype-quirks-mode "xml" #f #f #f #f) 'quirks)
    (check-equal 'html-doctype-quirks-mode
                 (html-doctype-quirks-mode "html" "-//W3C//DTD HTML 4.01 Frameset//EN"
                                           #f #f #f)
                 'quirks)
    (check-equal 'html-doctype-quirks-mode
                 (html-doctype-quirks-mode "html" "-//W3C//DTD HTML 4.01 Frameset//EN"
                                           "x" #f #f)
                 'limited-quirks)
    (check-equal 'html-doctype-quirks-mode
                 (html-doctype-quirks-mode "html" "-//W3C//DTD XHTML 1.0 Frameset//EN"
                                           #f #f #f)
                 'limited-quirks)))

(define ~check-parser-fragment
  (lambda ()
    (check-equal 'html->sxml
                 (html->sxml "<td>x" '((fragment-context . "tr")))
                 '(*TOP* (td "x")))
    (check-equal 'html->sxml
                 (html->sxml "a<b>c" '((fragment-context . "div")))
                 '(*TOP* "a" (b "c")))))

;; ====================================================================
;; Section 6 -- tree-construction fixtures (generated)
;; ====================================================================
;; Generated file -- do not edit by hand.
;;
;; Every tree-construction case of
;; submodules/justhtml/tests/justhtml-tests/*.dat, in the classic html5lib
;; pipe-indented format: parse the #data section, run the result through the
;; layer 5 test-format serializer and compare with the #document section.
;; Fields of an entry are file name, index within the file, the source HTML,
;; the expected document, the fragment context (or #false), the scripting
;; flag, the iframe-srcdoc flag and the XML-coercion flag.

(define string-trim
  (lambda (text)
    (let* ((size (string-length text))
           (start (let loop ((i 0))
                    (cond
                      ((fx>= i size) size)
                      ((char-whitespace? (string-ref text i)) (loop (fx+ i 1)))
                      (else i))))
           (end (let loop ((i size))
                  (cond
                    ((fx<= i start) start)
                    ((char-whitespace? (string-ref text (fx- i 1))) (loop (fx- i 1)))
                    (else i)))))
      (substring text start end))))

(define string-right-trim
  (lambda (text)
    (let loop ((i (string-length text)))
      (cond
        ((fx= i 0) "")
        ((char-whitespace? (string-ref text (fx- i 1))) (loop (fx- i 1)))
        (else (substring text 0 i))))))

;; Python's str.splitlines, which the justhtml harness relies on: line
;; breaks include U+000B, U+000C, U+000D, U+001C-U+001E and U+0085 as well
;; as U+000A, and CR LF counts as one break.
(define line-break-character?
  (lambda (c)
    (let ((code (char->integer c)))
      (or (fx= code #x0A) (fx= code #x0B) (fx= code #x0C) (fx= code #x0D)
          (fx= code #x1C) (fx= code #x1D) (fx= code #x1E) (fx= code #x85)
          (fx= code #x2028) (fx= code #x2029)))))

(define string-lines
  (lambda (text)
    (let ((size (string-length text)))
      (let loop ((start 0) (i 0) (result '()))
        (cond
          ((fx>= i size) (reverse (cons (substring text start size) result)))
          ((line-break-character? (string-ref text i))
           (let ((next (if (and (char=? (string-ref text i) #\return)
                                (fx< (fx+ i 1) size)
                                (char=? (string-ref text (fx+ i 1)) #\newline))
                         (fx+ i 2)
                         (fx+ i 1))))
             (loop next next (cons (substring text start i) result))))
          (else (loop start (fx+ i 1) result)))))))

;; Mirrors the compare_outputs helper of justhtml's own test harness.
(define test-format-normalize
  (lambda (text)
    (let ((lines (map string-right-trim (string-lines (string-trim text)))))
      (let loop ((lines lines) (port (open-output-string)) (first? #t))
        (cond
          ((null? lines) (get-output-string port))
          (else
           (unless first? (write-char #\newline port))
           (put-string port (car lines))
           (loop (cdr lines) port #f)))))))

(define fixture-actual
  (lambda (entry)
    (let* ((data (vector-ref entry 2))
           (fragment (vector-ref entry 4))
           (options (append (if fragment (list (cons 'fragment-context fragment)) '())
                            (list (cons 'scripting (vector-ref entry 5))
                                  (cons 'iframe-srcdoc (vector-ref entry 6))
                                  (cons 'xml-coercion (vector-ref entry 7))))))
      (html-sxml->test-format (html->sxml data options)))))

(define html-fixture-check
  (lambda (position)
    (let* ((entry (vector-ref html-fixture-entries position))
           (expected (test-format-normalize (vector-ref entry 3)))
           (actual (test-format-normalize (fixture-actual entry))))
      (unless (string=? expected actual)
        (error 'html-fixture-check "tree mismatch"
               (vector-ref entry 0) (vector-ref entry 1) (vector-ref entry 2)
               expected actual))
      #t)))

;; Convenience driver: prints a per-file pass/fail summary.
(define html-fixtures-report
  (lambda ()
    (let ((failures 0) (total 0))
      (let loop ((position 0))
        (when (fx< position (vector-length html-fixture-entries))
          (let ((entry (vector-ref html-fixture-entries position)))
            (set! total (fx+ total 1))
            (guard (ex (else
                        (set! failures (fx+ failures 1))
                        (format #t "FAIL ~a[~a] ~s\n"
                                (vector-ref entry 0) (vector-ref entry 1)
                                (vector-ref entry 2))
                        (format #t "--- expected ---\n~a\n--- actual ---\n~a\n"
                                (test-format-normalize (vector-ref entry 3))
                                (guard (ex2 (else "<error>"))
                                  (test-format-normalize (fixture-actual entry))))))
              (html-fixture-check position)))
          (loop (fx+ position 1))))
      (format #t "~a/~a fixtures passed\n" (fx- total failures) total)
      (fx= failures 0))))

(define html-fixture-entries
  '#(
    #("character_preprocessing.dat" 0 "<math><mi>\x0;</mi></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math mi>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 1 "<math><mi>\x0;\xC;</mi></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math mi>\xA;|         \"\xC;\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 2 "<math><mi>   </mi></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math mi>\xA;|         \"   \"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 3 "<math><mi>\xC;text</mi></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math mi>\xA;|         \"\xC;text\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 4 "<select>\xC;text</select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       \"\xC;text\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 5 "<table>\x0;</table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 6 "<head></head>\x0;" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 7 "<table>\xC;</table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       \"\xC;\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 8 "<!doctype html>\x0;" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 9 "<!--a\x0;b-->" "| <!-- a\xFFFD;b -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 10 "<frameset>\xD;\xA;" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     \"\xA;\"" #f #t #f #f)
    #("character_preprocessing.dat" 11 "<!--a-" "| <!-- a -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 12 "<!x\xD;\xA;y>" "| <!-- x\xA;y -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 13 "<\x0;div>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"<\xFFFD;div>\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 14 "</>" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 15 "\x0;\xC;A" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"A\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 16 "<!DOCTYPE\x0;html>" "| <!DOCTYPE \xFFFD;html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 17 "&#x;" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"&#x;\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 18 "<!--first--><!DOCTYPE\xD;\xA;html>" "| <!-- first -->\xA;| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 19 "<o\xC;e=\"\xD;\">" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <o>\xA;|       e=\"\xA;\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 20 "<d 2=\"\xD;\">" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <d>\xA;|       2=\"\xA;\"\xA;" #f #t #f #f)
    #("character_preprocessing.dat" 21 "<a 8=&#13\xD;>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <a>\xA;|       8=\"\xA;\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 0 "</template>" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 1 "<body><input type=\"hidden\">" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <input>\xA;|       type=\"hidden\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 2 "<html><body><html attr=\"test\">" "| <html>\xA;|   attr=\"test\"\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 3 "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//\" \"http://www.w3.org/TR/html4/loose.dtd\">" "| <!DOCTYPE html \"-//W3C//DTD HTML 4.01 Transitional//\" \"http://www.w3.org/TR/html4/loose.dtd\">\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 4 "<head></head></template>text" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"text\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 5 "<meta><!--x-->" "| <html>\xA;|   <head>\xA;|     <meta>\xA;|     <!-- x -->\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 6 "<!DOCTYPE\xA0;" "| <!DOCTYPE \xA0;>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 7 "<!doctype html>x<head><meta>" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"x\"\xA;|     <meta>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 8 "<!DOCTYPE html foo><p><table>" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       <table>\xA;\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 9 "<div a=\"unterminated" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 10 "<DIV A=1 a=2>x</DIV>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       a=\"1\"\xA;|       \"x\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 11 "<! first><?second" "| <!--  first -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 12 "<div \x0;name=value>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       \xFFFD;name=\"value\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 13 "<source\x0; x=y>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <source\xFFFD;>\xA;|       x=\"y\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 14 "<html 1name='\x0;'>" "| <html>\xA;|   1name=\"\xFFFD;\"\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 15 "<source\x0; '='<script>alert(1)</script>'>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <source\xFFFD;>\xA;|       '=\"<script>alert(1)</script>\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 16 "</html><script>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <script>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 17 "</head></html><y>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <y>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 18 "</html><</ " "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"<\"\xA;|     <!--   -->\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 19 "<i></body></f><" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <i>\xA;|       \"<\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 20 "</>&#9" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 21 "<!>&#xD" "| <!--  -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 22 "<!DOCTYPE>&#xD" "| <!DOCTYPE >\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 23 "</e>&#9" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 24 "</head></html>2</t></-" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"2\"\xA;|     <!-- - -->\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 25 "<body id='a'><div><body id='b'>x</div>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     id=\"a\"\xA;|     <div>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 26 "<div><li>x<body class='late'>y" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     class=\"late\"\xA;|     <div>\xA;|       <li>\xA;|         \"xy\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 27 "<div>x<head><title>ignored</title></head>y" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       \"x\"\xA;|       <title>\xA;|         \"ignored\"\xA;|       \"y\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 28 "<!DOCTYPE html><body><command>A" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <command>\xA;|       \"A\"\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 29 "<head></head>\xA;" "| <html>\xA;|   <head>\xA;|   \"\xA;\"\xA;|   <body>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 30 "<!doctype html><div></span\xA;>" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;" #f #t #f #f)
    #("document_shell_recovery.dat" 31 "\x130;<!DOCTYPE html><p>x</p>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"\x130;\"\xA;|     <p>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 0 "<math><annotation-xml encoding=\"text/plain\"><div></div></annotation-xml></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math annotation-xml>\xA;|         encoding=\"text/plain\"\xA;|     <div>\xA;" #f #t #f #f)
    #("foreign_content.dat" 1 "<math><annotation-xml><div></div></annotation-xml></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math annotation-xml>\xA;|     <div>\xA;" #f #t #f #f)
    #("foreign_content.dat" 2 "<svg><font color=\"red\">text</font></svg>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|     <font>\xA;|       color=\"red\"\xA;|       \"text\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 3 "<svg><g><rect></rect><circle></circle><path></path></g></svg><div></div>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg g>\xA;|         <svg rect>\xA;|         <svg circle>\xA;|         <svg path>\xA;|     <div>\xA;" #f #t #f #f)
    #("foreign_content.dat" 4 "<math><annotation-xml encoding=\"text/html\"><div><table><tr></tr></table></div></annotation-xml></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math annotation-xml>\xA;|         encoding=\"text/html\"\xA;|         <div>\xA;|           <table>\xA;|             <tbody>\xA;|               <tr>\xA;" #f #t #f #f)
    #("foreign_content.dat" 5 "<math><annotation-xml foo=\"bar\"><div>test</div></annotation-xml></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math annotation-xml>\xA;|         foo=\"bar\"\xA;|     <div>\xA;|       \"test\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 6 "<svg><g><rect><circle><path><div>text</div></path></circle></rect></g></svg>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg g>\xA;|         <svg rect>\xA;|           <svg circle>\xA;|             <svg path>\xA;|     <div>\xA;|       \"text\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 7 "<svg><colgroup>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg colgroup>\xA;|         \"x\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 8 "<h1><math><h3>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <h1>\xA;|       <math math>\xA;|     <h3>\xA;" #f #t #f #f)
    #("foreign_content.dat" 9 "<table><svg><tr>n" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg tr>\xA;|         \"n\"\xA;|     <table>\xA;" #f #t #f #f)
    #("foreign_content.dat" 10 "<svg><th><o></th>0" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg th>\xA;|         <svg o>\xA;|       \"0\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 11 "<p><a><math><td></td><listing>U" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       <a>\xA;|         <math math>\xA;|           <math td>\xA;|     <listing>\xA;|       <a>\xA;|         \"U\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 12 "<p><svg><article>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       <svg svg>\xA;|         <svg article>\xA;" #f #t #f #f)
    #("foreign_content.dat" 13 "<p><math><td><listing>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       <math math>\xA;|         <math td>\xA;|     <listing>\xA;" #f #t #f #f)
    #("foreign_content.dat" 14 "<table><math><tr><d>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math tr>\xA;|         <math d>\xA;|     <table>\xA;" #f #t #f #f)
    #("foreign_content.dat" 15 "<form><math></form>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <form>\xA;|       <math math>\xA;|         \"x\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 16 "<b><svg><i></b>z" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <b>\xA;|       <svg svg>\xA;|       <i>\xA;|     <i>\xA;|       \"z\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 17 "<svg><code><h2></code>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|     <code>\xA;|     <h2>\xA;|       <code>\xA;\xA;" #f #t #f #f)
    #("foreign_content.dat" 18 "<svg><g/>x</svg>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg g>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 19 "<math><mi>x</mi></math>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math mi>\xA;|         \"x\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 20 "<svg><image href='x'></svg>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg image>\xA;|         href=\"x\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 21 "<button><p><math></button>>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <button>\xA;|       <p>\xA;|         <math math>\xA;|     \">\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 22 "<math><source>>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math source>\xA;|         \">\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 23 "<svg><input>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg input>\xA;|         \"x\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 24 "<math><frame><" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math frame>\xA;|         \"<\"\xA;" #f #t #f #f)
    #("foreign_content.dat" 25 "<math><html>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <math math>\xA;|       <math html>\xA;" #f #t #f #f)
    #("foreign_content.dat" 26 "<svg><body>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;" #f #t #f #f)
    #("foreign_content.dat" 27 "<h3><svg><title><d></h3><" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <h3>\xA;|       <svg svg>\xA;|         <svg title>\xA;|           <d>\xA;|             \"<\"\xA;" #f #t #f #f)
    ;; Expected value corrected: justhtml's fixture records a justhtml
    ;; bug here, not spec behavior -- see spec/justhtml-sxml-prompt.md,
    ;; "Known, deliberate divergences".
    #("foreign_stack_recovery.dat" 0 "<!><svg><th><title><n><select><td>" "| <!--  -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg th>\xA;|         <svg title>\xA;|           <n>\xA;|             <select>" #f #t #f #f)
    #("foreign_stack_recovery.dat" 1 "<svg><slot><select/e><title/a><select><select></slot></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg slot>\xA;|         <svg select>\xA;|           e=\"\"\xA;|           <svg title>\xA;|             a=\"\"\xA;|             <select>\xA;\xA;" #f #t #f #f)
    ;; Expected value corrected: justhtml's fixture records a justhtml
    ;; bug here, not spec behavior -- see spec/justhtml-sxml-prompt.md,
    ;; "Known, deliberate divergences".
    #("foreign_stack_recovery.dat" 2 "<svg><tr><title><section\xA;><math><p><tr>>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <svg svg>\xA;|       <svg tr>\xA;|         <svg title>\xA;|           <section>\xA;|             <math math>\xA;|             <p>\xA;|               \">\"" #f #t #f #f)
    #("frameset_recovery.dat" 0 "<!DOCTYPE html><html><head></head><frameset></frameset>" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 1 "<!DOCTYPE html><html><head></head><frameset></frameset>abc" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 2 "<frameset></frameset></frameset>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    ;; Expected value corrected: justhtml's fixture records a justhtml
    ;; bug here, not spec behavior -- see spec/justhtml-sxml-prompt.md,
    ;; "Known, deliberate divergences".
    #("frameset_recovery.dat" 3 "<figure><frameset><h1><aside><figcaption><html><frameset>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     <frameset>" #f #f #f #f)
    #("frameset_recovery.dat" 4 "<i><frameset>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 5 "<frameset><frame></frameset><frameset>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     <frame>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 6 "<frameset>x" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 7 "<frameset><body>x</body></frameset>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 8 "<frameset></frameset></html><!--a--><script><!--b--></script>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;| <!-- a -->\xA;| <!-- b -->\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 9 "<frameset></frameset><frame>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 10 "<frameset></frameset><frameset>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 11 "<frameset></body><!" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     <!--  -->\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 12 "<frameset>&#9" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     \"\x9;\"\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 13 "<html><frameset><frame></frameset></html><linkN\xB;\x0;href=x>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     <frame>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 14 "<html><frameset><frame></frameset></html><a0<>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     <frame>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 15 "<frameset><div\x0;>x" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 16 "<frame>" "| <frame>\xA;" "frameset" #t #f #f)
    #("frameset_recovery.dat" 17 "</body>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"x\"\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 18 "</body>x<!--c-->" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"x\"\xA;|     <!-- c -->\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 19 "<frameset></frameset></body>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 20 "<frameset><frame><frame>" "| <html>\xA;|   <head>\xA;|   <frameset>\xA;|     <frame>\xA;|     <frame>\xA;" #f #t #f #f)
    #("frameset_recovery.dat" 21 "x<frameset>" "| <head>\xA;| <body>\xA;|   \"x\"\xA;" "html" #t #f #f)
    #("frameset_recovery.dat" 22 "<input><frameset>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <input>\xA;" #f #t #f #f)
    #("head_noscript_recovery.dat" 0 "<head><noscript><!DOCTYPE html></noscript>" "| <html>\xA;|   <head>\xA;|     <noscript>\xA;|   <body>\xA;" #f #f #f #f)
    #("head_noscript_recovery.dat" 1 "<head><noscript></p></noscript>" "| <html>\xA;|   <head>\xA;|     <noscript>\xA;|   <body>\xA;" #f #f #f #f)
    #("head_noscript_recovery.dat" 2 "</head><noscript>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <noscript>\xA;\xA;" #f #t #f #f)
    #("head_noscript_recovery.dat" 3 "<head><noscript><head class=\"foo\"><!--foo--></noscript>" "| <html>\xA;|   <head>\xA;|     <noscript>\xA;|       <!-- foo -->\xA;|   <body>\xA;" #f #f #f #f)
    #("head_noscript_recovery.dat" 4 "<noscript><script>" "| <html>\xA;|   <head>\xA;|     <noscript>\xA;|     <script>\xA;|   <body>\xA;" #f #f #f #f)
    #("iframe_srcdoc.dat" 0 "<!DOCTYPE foo><p><table></table>" "| <!DOCTYPE foo>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|     <table>\xA;" #f #t #t #f)
    #("in_body_recovery.dat" 0 "<dl><dd>x</dd></dl>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <dl>\xA;|       <dd>\xA;|         \"x\"\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 1 "<p><u><section><meta>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       <u>\xA;|     <section>\xA;|       <meta>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 2 "<marquee></body><!" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <marquee>\xA;|       <!--  -->\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 3 "<div><tt></div><rt>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       <tt>\xA;|     <rt>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 4 "<form><table></form><table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <form>\xA;|       <table>\xA;|       <table>\xA;\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 5 "<p><b>x</p>y</b>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       <b>\xA;|         \"x\"\xA;|     <b>\xA;|       \"y\"\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 6 "<rt><rt>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <rt>\xA;|       <rt>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 7 "<f><frameset>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <f>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 8 "<div><b>x</div><span>y</span><svg>z</svg>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       <b>\xA;|         \"x\"\xA;|     <b>\xA;|       <span>\xA;|         \"y\"\xA;|       <svg svg>\xA;|         \"z\"\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 9 "<a><dialog><a>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <a>\xA;|       <dialog>\xA;|     <a>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 10 "</r\xA;==\"><" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 11 "<p><a><xmp>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       <a>\xA;|     <a>\xA;|       <xmp>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 12 "<!DOCTYPE html><li><menuitem><li>" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <li>\xA;|       <menuitem>\xA;|     <li>\xA;" #f #t #f #f)
    #("in_body_recovery.dat" 13 "<object><h2><button><ul></ul></h2><iframe>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <object>\xA;|       <h2>\xA;|         <button>\xA;|           <ul>\xA;|       <iframe>\xA;|         \"x\"\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 0 "<script>x" "| <html>\xA;|   <head>\xA;|     <script>\xA;|       \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 1 "<style>x" "| <html>\xA;|   <head>\xA;|     <style>\xA;|       \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 2 "<body><script>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <script>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 3 "<body><style>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <style>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 4 "<xmp>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <xmp>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 5 "<iframe>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <iframe>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 6 "<noembed>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <noembed>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 7 "<noframes>x" "| <html>\xA;|   <head>\xA;|     <noframes>\xA;|       \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 8 "<textarea\xB;/>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <textarea\xA;>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("raw_text_recovery.dat" 9 "\xA;" "\xA;" "textarea" #t #f #f)
    #("raw_text_recovery.dat" 10 "" "\xA;" "style" #t #f #f)
    #("raw_text_recovery.dat" 11 "a&amp;b</title><p>x" "| \"a&b</title><p>x\"\xA;" "title" #t #f #f)
    #("raw_text_recovery.dat" 12 "a</script><p>x" "| \"a</script><p>x\"\xA;" "script" #t #f #f)
    #("raw_text_recovery.dat" 13 "<b>x</b>" "| <b>\xA;|   \"x\"\xA;" "noscript" #f #f #f)
    #("raw_text_recovery.dat" 14 "<b>x</b>" "| \"<b>x</b>\"\xA;" "noscript" #t #f #f)
    #("raw_text_recovery.dat" 15 "x</textarea>y" "| \"x</textarea>y\"\xA;" "textarea" #t #f #f)
    #("raw_text_recovery.dat" 16 "a<b" "| \"a<b\"\xA;" "plaintext" #t #f #f)
    #("raw_text_recovery.dat" 17 "a</style>b" "| \"a</style>b\"\xA;" "style" #t #f #f)
    #("select_recovery.dat" 0 "<select><optgroup><option>1</option></optgroup></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <optgroup>\xA;|         <option>\xA;|           \"1\"\xA;" #f #t #f #f)
    #("select_recovery.dat" 1 "<select><option>1</option></optgroup></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <option>\xA;|         \"1\"\xA;" #f #t #f #f)
    #("select_recovery.dat" 2 "<b><select></b></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <b>\xA;|       <select>\xA;" #f #t #f #f)
    #("select_recovery.dat" 3 "<a href=\"x\"><select></a></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <a>\xA;|       href=\"x\"\xA;|       <select>\xA;" #f #t #f #f)
    #("select_recovery.dat" 4 "<select><plaintext></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <plaintext>\xA;|         \"</select>\"\xA;" #f #t #f #f)
    #("select_recovery.dat" 5 "<select></a></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;" #f #t #f #f)
    #("select_recovery.dat" 6 "<select></b></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;" #f #t #f #f)
    #("select_recovery.dat" 7 "<select><aside>text</aside></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <aside>\xA;|         \"text\"\xA;" #f #t #f #f)
    #("select_recovery.dat" 8 "<select></regularitem>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;" #f #t #f #f)
    #("select_recovery.dat" 9 "<div><select></div>text" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       <select>\xA;|         \"text\"\xA;" #f #t #f #f)
    #("select_recovery.dat" 10 "<select><template><input>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <template>\xA;|         content\xA;|           <input>\xA;" #f #t #f #f)
    #("select_recovery.dat" 11 "<select></html><!--c-->" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <!-- c -->\xA;" #f #t #f #f)
    #("select_recovery.dat" 12 "<select><o></body><!" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <o>\xA;|         <!--  -->\xA;" #f #t #f #f)
    #("select_recovery.dat" 13 "<select><v></html><!" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <v>\xA;|         <!--  -->\xA;\xA;" #f #t #f #f)
    #("select_recovery.dat" 14 "<select><b>x</b></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <b>\xA;|         \"x\"\xA;" #f #t #f #f)
    #("select_recovery.dat" 15 "<optgroup><optgroup>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <optgroup>\xA;|       <optgroup>\xA;" #f #t #f #f)
    #("select_recovery.dat" 16 "<select><table><input><select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <input>\xA;|       <select>\xA;|       <table>\xA;" #f #t #f #f)
    #("select_recovery.dat" 17 "<select><table><d><select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <d>\xA;|         <select>\xA;|       <table>\xA;" #f #t #f #f)
    #("select_recovery.dat" 18 "<input><option>" "| <option>\xA;" "select" #t #f #f)
    #("select_recovery.dat" 19 "<input><option>x" "| <option>\xA;|   \"x\"\xA;" "select" #t #f #f)
    #("selectedcontent.dat" 0 "<select><selectedcontent></selectedcontent><option>A</option><option selected>B</option></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <selectedcontent>\xA;|         \"B\"\xA;|       <option>\xA;|         \"A\"\xA;|       <option>\xA;|         selected=\"\"\xA;|         \"B\"\xA;" #f #t #f #f)
    #("selectedcontent.dat" 1 "<select><selectedcontent></selectedcontent><option>A</option><option>B</option></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <selectedcontent>\xA;|         \"A\"\xA;|       <option>\xA;|         \"A\"\xA;|       <option>\xA;|         \"B\"\xA;" #f #t #f #f)
    #("selectedcontent.dat" 2 "<select><selectedcontent></selectedcontent><option disabled>A</option></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <selectedcontent>\xA;|       <option>\xA;|         disabled=\"\"\xA;|         \"A\"\xA;" #f #t #f #f)
    #("selectedcontent.dat" 3 "<select><selectedcontent></selectedcontent><option class=\"x\">A</option><option selected>B</option></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <selectedcontent>\xA;|         \"B\"\xA;|       <option>\xA;|         class=\"x\"\xA;|         \"A\"\xA;|       <option>\xA;|         selected=\"\"\xA;|         \"B\"\xA;" #f #t #f #f)
    #("selectedcontent.dat" 4 "<select><selectedcontent></selectedcontent></select>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <select>\xA;|       <selectedcontent>\xA;" #f #t #f #f)
    #("table_recovery.dat" 0 "<table><input id=\"x\" class=\"y\" type=\"hidden\"></table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <input>\xA;|         class=\"y\"\xA;|         id=\"x\"\xA;|         type=\"hidden\"\xA;" #f #t #f #f)
    #("table_recovery.dat" 1 "<table><caption><!--comment--></caption></table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <caption>\xA;|         <!-- comment -->\xA;" #f #t #f #f)
    #("table_recovery.dat" 2 "<table><caption><table></table></caption></table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <caption>\xA;|         <table>\xA;" #f #t #f #f)
    #("table_recovery.dat" 3 "<table>text</table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"text\"\xA;|     <table>\xA;" #f #t #f #f)
    #("table_recovery.dat" 4 "<table><td><!-- comment in cell --></td></table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <tbody>\xA;|         <tr>\xA;|           <td>\xA;|             <!--  comment in cell  -->\xA;" #f #t #f #f)
    #("table_recovery.dat" 5 "<table><colgroup></p>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|     <table>\xA;|       <colgroup>\xA;\xA;" #f #t #f #f)
    #("table_recovery.dat" 6 "<table><form><input>x" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <input>\xA;|     \"x\"\xA;|     <table>\xA;|       <form>\xA;" #f #t #f #f)
    #("table_recovery.dat" 7 "<table><colgroup></colgroup><colgroup></colgroup></table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <colgroup>\xA;|       <colgroup>\xA;" #f #t #f #f)
    #("table_recovery.dat" 8 "<table><c><col>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <c>\xA;|     <table>\xA;|       <colgroup>\xA;|         <col>\xA;" #f #t #f #f)
    #("table_recovery.dat" 9 "<table><caption>x<table><tr><td>nested</td></tr></table></caption></table>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <caption>\xA;|         \"x\"\xA;|         <table>\xA;|           <tbody>\xA;|             <tr>\xA;|               <td>\xA;|                 \"nested\"\xA;" #f #t #f #f)
    #("table_recovery.dat" 10 "<table><a><th></th></br>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <a>\xA;|     <a>\xA;|       <br>\xA;|     <table>\xA;|       <tbody>\xA;|         <tr>\xA;|           <th>\xA;" #f #t #f #f)
    #("table_recovery.dat" 11 "<table></> </l>\xA;<" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"\xA;<\"\xA;|     <table>\xA;|       \" \"\xA;" #f #t #f #f)
    #("table_recovery.dat" 12 "<table></>\xA;<" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"\xA;<\"\xA;|     <table>\xA;" #f #t #f #f)
    #("table_recovery.dat" 13 "<div><strong></div><table><colgroup>H" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       <strong>\xA;|     <strong>\xA;|       \"H\"\xA;|     <table>\xA;|       <colgroup>\xA;" #f #t #f #f)
    #("template_recovery.dat" 0 "<template><table><colgroup></colgroup><script></script></table></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|           <colgroup>\xA;|           <script>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 1 "<template><table><colgroup></colgroup><template></template></table></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|           <colgroup>\xA;|           <template>\xA;|             content\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 2 "<template><table><colgroup><script></script></table></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|           <colgroup>\xA;|           <script>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 3 "<template><table><colgroup><style></style></table></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|           <colgroup>\xA;|           <style>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 4 "<template><tbody><colgroup></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tbody>\xA;|         <colgroup>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 5 "<template><tbody></table><script></script></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tbody>\xA;|         <script>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 6 "<template><tr></table><template></template></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tr>\xA;|         <template>\xA;|           content\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 7 "<template><tbody><table></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tbody>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 8 "<template><tr><table></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tr>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 9 "<template><caption>x</caption><table></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <caption>\xA;|           \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 10 "<template><title>x</title><tbody></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <title>\xA;|           \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 11 "<template><title>x</title><tr></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <title>\xA;|           \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 12 "<template><title>x</title><td>x</template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <title>\xA;|           \"x\"\xA;|         \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 13 "<template><optgroup></p></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <optgroup>\xA;|           <p>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 14 "<template></p><select></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <select>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 15 "<template><tbody><table><tr></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tbody>\xA;|           <tr>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 16 "<template><select><table></select><option></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <select>\xA;|           <option>\xA;|           <table>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 17 "<template><base><tbody></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <base>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 18 "<template><noframes></noframes><td>x</template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <noframes>\xA;|         \"x\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 19 "<template></template>&#32;" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|     \" \"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 20 "<body><template></template>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <template>\xA;|       content\xA;" #f #t #f #f)
    #("template_recovery.dat" 21 "<template></br>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 22 "<template><noscript></noscript>Y" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <noscript>\xA;|         \"Y\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 23 "<template><dialog><object></dialog>e" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <dialog>\xA;|           <object>\xA;|             \"e\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 24 "<head><template></template></head><!--c-->" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|   <!-- c -->\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 25 "<template><caption><tr>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <caption>\xA;|         <tbody>\xA;|           <tr>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 26 "<template><xmp></xmp><td>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <xmp>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 27 "<template><td></th>x" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <td>\xA;|           \"x\"\xA;|   <body>\xA;\xA;" #f #t #f #f)
    #("template_recovery.dat" 28 "<template><title>x</title><base><link></template>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <title>\xA;|           \"x\"\xA;|         <base>\xA;|         <link>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 29 "<template></html><//" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <!-- / -->\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 30 "<template><tr>d" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tr>\xA;|         \"d\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 31 "<!><template></template><?" "| <!--  -->\xA;| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 32 "<template><d><table><tr>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <d>\xA;|           <table>\xA;|             <tbody>\xA;|               <tr>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 33 "<template><table><tr><table>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|           <tbody>\xA;|             <tr>\xA;|         <table>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 34 "<template><table><col>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|           <colgroup>\xA;|             <col>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 35 "<template><colgroup>X" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <colgroup>\xA;|         \"X\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 36 "<template><colgroup><v>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <colgroup>\xA;|         <v>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 37 "<template><col><" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <col>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 38 "<template><table><table><" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|         \"<\"\xA;|         <table>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 39 "<template><td><table><tr>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <td>\xA;|           <table>\xA;|             <tbody>\xA;|               <tr>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 40 "<template><table><body><td>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <table>\xA;|           <tbody>\xA;|             <tr>\xA;|               <td>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 41 "<template><tr><form>V" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tr>\xA;|           <form>\xA;|         \"V\"\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 42 "<template><tbody><e><tr>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tbody>\xA;|           <tr>\xA;|         <e>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 43 "<template><tr><u><td>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tr>\xA;|           <td>\xA;|         <u>\xA;|   <body>\xA;" #f #t #f #f)
    #("template_recovery.dat" 44 "<table><template><n><form><" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <template>\xA;|         content\xA;|           <n>\xA;|             <form>\xA;|               \"<\"\xA;" #f #t #f #f)
    #("template_recovery.dat" 45 "<table><template><tr>s" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <table>\xA;|       <template>\xA;|         content\xA;|           <tr>\xA;|           \"s\"\xA;" #f #t #f #f)
    #("template_recovery.dat" 46 "<template><tr><script>" "| <html>\xA;|   <head>\xA;|     <template>\xA;|       content\xA;|         <tr>\xA;|           <script>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 0 "<?x>" "| <?x ?>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 1 "<?x" "| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 2 "</!x>" "| <!-- !x -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 3 "</!x" "| <!-- !x -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 4 "<!x>" "| <!-- x -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 5 "<!x" "| <!-- x -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 6 "<!--x" "| <!-- x -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 7 "<!--x--!>" "| <!-- x -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 8 "<h\xA;=>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <h>\xA;|       ==\"\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 9 "<h\xA;=9>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <h>\xA;|       =9=\"\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 10 "<h\xA;==>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <h>\xA;|       ==\"\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 11 "<p ==>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <p>\xA;|       ==\"\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 12 "<m\xC;i=''=\">" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <m>\xA;|       =\"=\"\"\xA;|       i=\"\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 13 "<r/Y>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <r>\xA;|       y=\"\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 14 "<x/\">" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <x>\xA;|       \"=\"\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 15 "a<?x>b" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     \"a\"\xA;|     <?x ?>\xA;|     \"b\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 16 "<?x a\xD;\x0;b>" "| <?x a\xA;\xFFFD;b?>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 17 "<?xml" "| <!-- ?xml -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 18 "<?\x1F680;>" "| <!-- ?\x1F680; -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 19 "<?#abc" "| <!-- ?#abc -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 20 "<?\x9;" "| <!-- ?\x9; -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 21 "<!doctype html><div\xD;class\xD;=\xD;'a'\xD;>w</div>" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       class=\"a\"\xA;|       \"w\"\xA;" #f #t #f #f)
    #("tokenizer_recovery.dat" 22 "<?pi>" "| <?pi ?>\xA;" "div" #t #f #f)
    #("tokenizer_recovery.dat" 23 "<!doctype html><div\xD;/>x" "| <!DOCTYPE html>\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       \"x\"\xA;" #f #t #f #f)
    #("xml_coercion.dat" 0 "<!-- normal comment -->" "| <!--  normal comment  -->\xA;| <html>\xA;|   <head>\xA;|   <body>\xA;\xA;" #f #t #f #t)
    #("xml_coercion.dat" 1 "<div>normal text</div>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       \"normal text\"\xA;\xA;" #f #t #f #t)
    #("xml_coercion.dat" 2 "<div>\xFC;ber</div>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       \"\xFC;ber\"\xA;\xA;" #f #t #f #t)
    #("xml_coercion.dat" 3 "<div>\xFC;ber\xC;</div>" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <div>\xA;|       \"\xFC;ber \"\xA;" #f #t #f #t)
    #("xml_coercion.dat" 4 "<style>a\xD;\xA;b\xC;c\x0;</style>" "| <html>\xA;|   <head>\xA;|     <style>\xA;|       \"a\xA;b c\xFFFD;\"\xA;|   <body>\xA;" #f #t #f #t)
    #("xml_coercion.dat" 5 "<plaintext>a\xD;\xA;b\xC;c\x0;" "| <html>\xA;|   <head>\xA;|   <body>\xA;|     <plaintext>\xA;|       \"a\xA;b c\xFFFD;\"\xA;" #f #t #f #t)
    ))

(define ~check-character-preprocessing-0 (lambda () (html-fixture-check 0)))
(define ~check-character-preprocessing-1 (lambda () (html-fixture-check 1)))
(define ~check-character-preprocessing-2 (lambda () (html-fixture-check 2)))
(define ~check-character-preprocessing-3 (lambda () (html-fixture-check 3)))
(define ~check-character-preprocessing-4 (lambda () (html-fixture-check 4)))
(define ~check-character-preprocessing-5 (lambda () (html-fixture-check 5)))
(define ~check-character-preprocessing-6 (lambda () (html-fixture-check 6)))
(define ~check-character-preprocessing-7 (lambda () (html-fixture-check 7)))
(define ~check-character-preprocessing-8 (lambda () (html-fixture-check 8)))
(define ~check-character-preprocessing-9 (lambda () (html-fixture-check 9)))
(define ~check-character-preprocessing-10 (lambda () (html-fixture-check 10)))
(define ~check-character-preprocessing-11 (lambda () (html-fixture-check 11)))
(define ~check-character-preprocessing-12 (lambda () (html-fixture-check 12)))
(define ~check-character-preprocessing-13 (lambda () (html-fixture-check 13)))
(define ~check-character-preprocessing-14 (lambda () (html-fixture-check 14)))
(define ~check-character-preprocessing-15 (lambda () (html-fixture-check 15)))
(define ~check-character-preprocessing-16 (lambda () (html-fixture-check 16)))
(define ~check-character-preprocessing-17 (lambda () (html-fixture-check 17)))
(define ~check-character-preprocessing-18 (lambda () (html-fixture-check 18)))
(define ~check-character-preprocessing-19 (lambda () (html-fixture-check 19)))
(define ~check-character-preprocessing-20 (lambda () (html-fixture-check 20)))
(define ~check-character-preprocessing-21 (lambda () (html-fixture-check 21)))
(define ~check-document-shell-recovery-0 (lambda () (html-fixture-check 22)))
(define ~check-document-shell-recovery-1 (lambda () (html-fixture-check 23)))
(define ~check-document-shell-recovery-2 (lambda () (html-fixture-check 24)))
(define ~check-document-shell-recovery-3 (lambda () (html-fixture-check 25)))
(define ~check-document-shell-recovery-4 (lambda () (html-fixture-check 26)))
(define ~check-document-shell-recovery-5 (lambda () (html-fixture-check 27)))
(define ~check-document-shell-recovery-6 (lambda () (html-fixture-check 28)))
(define ~check-document-shell-recovery-7 (lambda () (html-fixture-check 29)))
(define ~check-document-shell-recovery-8 (lambda () (html-fixture-check 30)))
(define ~check-document-shell-recovery-9 (lambda () (html-fixture-check 31)))
(define ~check-document-shell-recovery-10 (lambda () (html-fixture-check 32)))
(define ~check-document-shell-recovery-11 (lambda () (html-fixture-check 33)))
(define ~check-document-shell-recovery-12 (lambda () (html-fixture-check 34)))
(define ~check-document-shell-recovery-13 (lambda () (html-fixture-check 35)))
(define ~check-document-shell-recovery-14 (lambda () (html-fixture-check 36)))
(define ~check-document-shell-recovery-15 (lambda () (html-fixture-check 37)))
(define ~check-document-shell-recovery-16 (lambda () (html-fixture-check 38)))
(define ~check-document-shell-recovery-17 (lambda () (html-fixture-check 39)))
(define ~check-document-shell-recovery-18 (lambda () (html-fixture-check 40)))
(define ~check-document-shell-recovery-19 (lambda () (html-fixture-check 41)))
(define ~check-document-shell-recovery-20 (lambda () (html-fixture-check 42)))
(define ~check-document-shell-recovery-21 (lambda () (html-fixture-check 43)))
(define ~check-document-shell-recovery-22 (lambda () (html-fixture-check 44)))
(define ~check-document-shell-recovery-23 (lambda () (html-fixture-check 45)))
(define ~check-document-shell-recovery-24 (lambda () (html-fixture-check 46)))
(define ~check-document-shell-recovery-25 (lambda () (html-fixture-check 47)))
(define ~check-document-shell-recovery-26 (lambda () (html-fixture-check 48)))
(define ~check-document-shell-recovery-27 (lambda () (html-fixture-check 49)))
(define ~check-document-shell-recovery-28 (lambda () (html-fixture-check 50)))
(define ~check-document-shell-recovery-29 (lambda () (html-fixture-check 51)))
(define ~check-document-shell-recovery-30 (lambda () (html-fixture-check 52)))
(define ~check-document-shell-recovery-31 (lambda () (html-fixture-check 53)))
(define ~check-foreign-content-0 (lambda () (html-fixture-check 54)))
(define ~check-foreign-content-1 (lambda () (html-fixture-check 55)))
(define ~check-foreign-content-2 (lambda () (html-fixture-check 56)))
(define ~check-foreign-content-3 (lambda () (html-fixture-check 57)))
(define ~check-foreign-content-4 (lambda () (html-fixture-check 58)))
(define ~check-foreign-content-5 (lambda () (html-fixture-check 59)))
(define ~check-foreign-content-6 (lambda () (html-fixture-check 60)))
(define ~check-foreign-content-7 (lambda () (html-fixture-check 61)))
(define ~check-foreign-content-8 (lambda () (html-fixture-check 62)))
(define ~check-foreign-content-9 (lambda () (html-fixture-check 63)))
(define ~check-foreign-content-10 (lambda () (html-fixture-check 64)))
(define ~check-foreign-content-11 (lambda () (html-fixture-check 65)))
(define ~check-foreign-content-12 (lambda () (html-fixture-check 66)))
(define ~check-foreign-content-13 (lambda () (html-fixture-check 67)))
(define ~check-foreign-content-14 (lambda () (html-fixture-check 68)))
(define ~check-foreign-content-15 (lambda () (html-fixture-check 69)))
(define ~check-foreign-content-16 (lambda () (html-fixture-check 70)))
(define ~check-foreign-content-17 (lambda () (html-fixture-check 71)))
(define ~check-foreign-content-18 (lambda () (html-fixture-check 72)))
(define ~check-foreign-content-19 (lambda () (html-fixture-check 73)))
(define ~check-foreign-content-20 (lambda () (html-fixture-check 74)))
(define ~check-foreign-content-21 (lambda () (html-fixture-check 75)))
(define ~check-foreign-content-22 (lambda () (html-fixture-check 76)))
(define ~check-foreign-content-23 (lambda () (html-fixture-check 77)))
(define ~check-foreign-content-24 (lambda () (html-fixture-check 78)))
(define ~check-foreign-content-25 (lambda () (html-fixture-check 79)))
(define ~check-foreign-content-26 (lambda () (html-fixture-check 80)))
(define ~check-foreign-content-27 (lambda () (html-fixture-check 81)))
;; Asserts the spec-correct tree, not justhtml's fixture (see spec/justhtml-sxml-prompt.md).
(define ~check-foreign-stack-recovery-0 (lambda () (html-fixture-check 82)))
(define ~check-foreign-stack-recovery-1 (lambda () (html-fixture-check 83)))
;; Asserts the spec-correct tree, not justhtml's fixture (see spec/justhtml-sxml-prompt.md).
(define ~check-foreign-stack-recovery-2 (lambda () (html-fixture-check 84)))
(define ~check-frameset-recovery-0 (lambda () (html-fixture-check 85)))
(define ~check-frameset-recovery-1 (lambda () (html-fixture-check 86)))
(define ~check-frameset-recovery-2 (lambda () (html-fixture-check 87)))
;; Asserts the spec-correct tree, not justhtml's fixture (see spec/justhtml-sxml-prompt.md).
(define ~check-frameset-recovery-3 (lambda () (html-fixture-check 88)))
(define ~check-frameset-recovery-4 (lambda () (html-fixture-check 89)))
(define ~check-frameset-recovery-5 (lambda () (html-fixture-check 90)))
(define ~check-frameset-recovery-6 (lambda () (html-fixture-check 91)))
(define ~check-frameset-recovery-7 (lambda () (html-fixture-check 92)))
(define ~check-frameset-recovery-8 (lambda () (html-fixture-check 93)))
(define ~check-frameset-recovery-9 (lambda () (html-fixture-check 94)))
(define ~check-frameset-recovery-10 (lambda () (html-fixture-check 95)))
(define ~check-frameset-recovery-11 (lambda () (html-fixture-check 96)))
(define ~check-frameset-recovery-12 (lambda () (html-fixture-check 97)))
(define ~check-frameset-recovery-13 (lambda () (html-fixture-check 98)))
(define ~check-frameset-recovery-14 (lambda () (html-fixture-check 99)))
(define ~check-frameset-recovery-15 (lambda () (html-fixture-check 100)))
(define ~check-frameset-recovery-16 (lambda () (html-fixture-check 101)))
(define ~check-frameset-recovery-17 (lambda () (html-fixture-check 102)))
(define ~check-frameset-recovery-18 (lambda () (html-fixture-check 103)))
(define ~check-frameset-recovery-19 (lambda () (html-fixture-check 104)))
(define ~check-frameset-recovery-20 (lambda () (html-fixture-check 105)))
(define ~check-frameset-recovery-21 (lambda () (html-fixture-check 106)))
(define ~check-frameset-recovery-22 (lambda () (html-fixture-check 107)))
(define ~check-head-noscript-recovery-0 (lambda () (html-fixture-check 108)))
(define ~check-head-noscript-recovery-1 (lambda () (html-fixture-check 109)))
(define ~check-head-noscript-recovery-2 (lambda () (html-fixture-check 110)))
(define ~check-head-noscript-recovery-3 (lambda () (html-fixture-check 111)))
(define ~check-head-noscript-recovery-4 (lambda () (html-fixture-check 112)))
(define ~check-iframe-srcdoc-0 (lambda () (html-fixture-check 113)))
(define ~check-in-body-recovery-0 (lambda () (html-fixture-check 114)))
(define ~check-in-body-recovery-1 (lambda () (html-fixture-check 115)))
(define ~check-in-body-recovery-2 (lambda () (html-fixture-check 116)))
(define ~check-in-body-recovery-3 (lambda () (html-fixture-check 117)))
(define ~check-in-body-recovery-4 (lambda () (html-fixture-check 118)))
(define ~check-in-body-recovery-5 (lambda () (html-fixture-check 119)))
(define ~check-in-body-recovery-6 (lambda () (html-fixture-check 120)))
(define ~check-in-body-recovery-7 (lambda () (html-fixture-check 121)))
(define ~check-in-body-recovery-8 (lambda () (html-fixture-check 122)))
(define ~check-in-body-recovery-9 (lambda () (html-fixture-check 123)))
(define ~check-in-body-recovery-10 (lambda () (html-fixture-check 124)))
(define ~check-in-body-recovery-11 (lambda () (html-fixture-check 125)))
(define ~check-in-body-recovery-12 (lambda () (html-fixture-check 126)))
(define ~check-in-body-recovery-13 (lambda () (html-fixture-check 127)))
(define ~check-raw-text-recovery-0 (lambda () (html-fixture-check 128)))
(define ~check-raw-text-recovery-1 (lambda () (html-fixture-check 129)))
(define ~check-raw-text-recovery-2 (lambda () (html-fixture-check 130)))
(define ~check-raw-text-recovery-3 (lambda () (html-fixture-check 131)))
(define ~check-raw-text-recovery-4 (lambda () (html-fixture-check 132)))
(define ~check-raw-text-recovery-5 (lambda () (html-fixture-check 133)))
(define ~check-raw-text-recovery-6 (lambda () (html-fixture-check 134)))
(define ~check-raw-text-recovery-7 (lambda () (html-fixture-check 135)))
(define ~check-raw-text-recovery-8 (lambda () (html-fixture-check 136)))
(define ~check-raw-text-recovery-9 (lambda () (html-fixture-check 137)))
(define ~check-raw-text-recovery-10 (lambda () (html-fixture-check 138)))
(define ~check-raw-text-recovery-11 (lambda () (html-fixture-check 139)))
(define ~check-raw-text-recovery-12 (lambda () (html-fixture-check 140)))
(define ~check-raw-text-recovery-13 (lambda () (html-fixture-check 141)))
(define ~check-raw-text-recovery-14 (lambda () (html-fixture-check 142)))
(define ~check-raw-text-recovery-15 (lambda () (html-fixture-check 143)))
(define ~check-raw-text-recovery-16 (lambda () (html-fixture-check 144)))
(define ~check-raw-text-recovery-17 (lambda () (html-fixture-check 145)))
(define ~check-select-recovery-0 (lambda () (html-fixture-check 146)))
(define ~check-select-recovery-1 (lambda () (html-fixture-check 147)))
(define ~check-select-recovery-2 (lambda () (html-fixture-check 148)))
(define ~check-select-recovery-3 (lambda () (html-fixture-check 149)))
(define ~check-select-recovery-4 (lambda () (html-fixture-check 150)))
(define ~check-select-recovery-5 (lambda () (html-fixture-check 151)))
(define ~check-select-recovery-6 (lambda () (html-fixture-check 152)))
(define ~check-select-recovery-7 (lambda () (html-fixture-check 153)))
(define ~check-select-recovery-8 (lambda () (html-fixture-check 154)))
(define ~check-select-recovery-9 (lambda () (html-fixture-check 155)))
(define ~check-select-recovery-10 (lambda () (html-fixture-check 156)))
(define ~check-select-recovery-11 (lambda () (html-fixture-check 157)))
(define ~check-select-recovery-12 (lambda () (html-fixture-check 158)))
(define ~check-select-recovery-13 (lambda () (html-fixture-check 159)))
(define ~check-select-recovery-14 (lambda () (html-fixture-check 160)))
(define ~check-select-recovery-15 (lambda () (html-fixture-check 161)))
(define ~check-select-recovery-16 (lambda () (html-fixture-check 162)))
(define ~check-select-recovery-17 (lambda () (html-fixture-check 163)))
(define ~check-select-recovery-18 (lambda () (html-fixture-check 164)))
(define ~check-select-recovery-19 (lambda () (html-fixture-check 165)))
(define ~check-selectedcontent-0 (lambda () (html-fixture-check 166)))
(define ~check-selectedcontent-1 (lambda () (html-fixture-check 167)))
(define ~check-selectedcontent-2 (lambda () (html-fixture-check 168)))
(define ~check-selectedcontent-3 (lambda () (html-fixture-check 169)))
(define ~check-selectedcontent-4 (lambda () (html-fixture-check 170)))
(define ~check-table-recovery-0 (lambda () (html-fixture-check 171)))
(define ~check-table-recovery-1 (lambda () (html-fixture-check 172)))
(define ~check-table-recovery-2 (lambda () (html-fixture-check 173)))
(define ~check-table-recovery-3 (lambda () (html-fixture-check 174)))
(define ~check-table-recovery-4 (lambda () (html-fixture-check 175)))
(define ~check-table-recovery-5 (lambda () (html-fixture-check 176)))
(define ~check-table-recovery-6 (lambda () (html-fixture-check 177)))
(define ~check-table-recovery-7 (lambda () (html-fixture-check 178)))
(define ~check-table-recovery-8 (lambda () (html-fixture-check 179)))
(define ~check-table-recovery-9 (lambda () (html-fixture-check 180)))
(define ~check-table-recovery-10 (lambda () (html-fixture-check 181)))
(define ~check-table-recovery-11 (lambda () (html-fixture-check 182)))
(define ~check-table-recovery-12 (lambda () (html-fixture-check 183)))
(define ~check-table-recovery-13 (lambda () (html-fixture-check 184)))
(define ~check-template-recovery-0 (lambda () (html-fixture-check 185)))
(define ~check-template-recovery-1 (lambda () (html-fixture-check 186)))
(define ~check-template-recovery-2 (lambda () (html-fixture-check 187)))
(define ~check-template-recovery-3 (lambda () (html-fixture-check 188)))
(define ~check-template-recovery-4 (lambda () (html-fixture-check 189)))
(define ~check-template-recovery-5 (lambda () (html-fixture-check 190)))
(define ~check-template-recovery-6 (lambda () (html-fixture-check 191)))
(define ~check-template-recovery-7 (lambda () (html-fixture-check 192)))
(define ~check-template-recovery-8 (lambda () (html-fixture-check 193)))
(define ~check-template-recovery-9 (lambda () (html-fixture-check 194)))
(define ~check-template-recovery-10 (lambda () (html-fixture-check 195)))
(define ~check-template-recovery-11 (lambda () (html-fixture-check 196)))
(define ~check-template-recovery-12 (lambda () (html-fixture-check 197)))
(define ~check-template-recovery-13 (lambda () (html-fixture-check 198)))
(define ~check-template-recovery-14 (lambda () (html-fixture-check 199)))
(define ~check-template-recovery-15 (lambda () (html-fixture-check 200)))
(define ~check-template-recovery-16 (lambda () (html-fixture-check 201)))
(define ~check-template-recovery-17 (lambda () (html-fixture-check 202)))
(define ~check-template-recovery-18 (lambda () (html-fixture-check 203)))
(define ~check-template-recovery-19 (lambda () (html-fixture-check 204)))
(define ~check-template-recovery-20 (lambda () (html-fixture-check 205)))
(define ~check-template-recovery-21 (lambda () (html-fixture-check 206)))
(define ~check-template-recovery-22 (lambda () (html-fixture-check 207)))
(define ~check-template-recovery-23 (lambda () (html-fixture-check 208)))
(define ~check-template-recovery-24 (lambda () (html-fixture-check 209)))
(define ~check-template-recovery-25 (lambda () (html-fixture-check 210)))
(define ~check-template-recovery-26 (lambda () (html-fixture-check 211)))
(define ~check-template-recovery-27 (lambda () (html-fixture-check 212)))
(define ~check-template-recovery-28 (lambda () (html-fixture-check 213)))
(define ~check-template-recovery-29 (lambda () (html-fixture-check 214)))
(define ~check-template-recovery-30 (lambda () (html-fixture-check 215)))
(define ~check-template-recovery-31 (lambda () (html-fixture-check 216)))
(define ~check-template-recovery-32 (lambda () (html-fixture-check 217)))
(define ~check-template-recovery-33 (lambda () (html-fixture-check 218)))
(define ~check-template-recovery-34 (lambda () (html-fixture-check 219)))
(define ~check-template-recovery-35 (lambda () (html-fixture-check 220)))
(define ~check-template-recovery-36 (lambda () (html-fixture-check 221)))
(define ~check-template-recovery-37 (lambda () (html-fixture-check 222)))
(define ~check-template-recovery-38 (lambda () (html-fixture-check 223)))
(define ~check-template-recovery-39 (lambda () (html-fixture-check 224)))
(define ~check-template-recovery-40 (lambda () (html-fixture-check 225)))
(define ~check-template-recovery-41 (lambda () (html-fixture-check 226)))
(define ~check-template-recovery-42 (lambda () (html-fixture-check 227)))
(define ~check-template-recovery-43 (lambda () (html-fixture-check 228)))
(define ~check-template-recovery-44 (lambda () (html-fixture-check 229)))
(define ~check-template-recovery-45 (lambda () (html-fixture-check 230)))
(define ~check-template-recovery-46 (lambda () (html-fixture-check 231)))
(define ~check-tokenizer-recovery-0 (lambda () (html-fixture-check 232)))
(define ~check-tokenizer-recovery-1 (lambda () (html-fixture-check 233)))
(define ~check-tokenizer-recovery-2 (lambda () (html-fixture-check 234)))
(define ~check-tokenizer-recovery-3 (lambda () (html-fixture-check 235)))
(define ~check-tokenizer-recovery-4 (lambda () (html-fixture-check 236)))
(define ~check-tokenizer-recovery-5 (lambda () (html-fixture-check 237)))
(define ~check-tokenizer-recovery-6 (lambda () (html-fixture-check 238)))
(define ~check-tokenizer-recovery-7 (lambda () (html-fixture-check 239)))
(define ~check-tokenizer-recovery-8 (lambda () (html-fixture-check 240)))
(define ~check-tokenizer-recovery-9 (lambda () (html-fixture-check 241)))
(define ~check-tokenizer-recovery-10 (lambda () (html-fixture-check 242)))
(define ~check-tokenizer-recovery-11 (lambda () (html-fixture-check 243)))
(define ~check-tokenizer-recovery-12 (lambda () (html-fixture-check 244)))
(define ~check-tokenizer-recovery-13 (lambda () (html-fixture-check 245)))
(define ~check-tokenizer-recovery-14 (lambda () (html-fixture-check 246)))
(define ~check-tokenizer-recovery-15 (lambda () (html-fixture-check 247)))
(define ~check-tokenizer-recovery-16 (lambda () (html-fixture-check 248)))
(define ~check-tokenizer-recovery-17 (lambda () (html-fixture-check 249)))
(define ~check-tokenizer-recovery-18 (lambda () (html-fixture-check 250)))
(define ~check-tokenizer-recovery-19 (lambda () (html-fixture-check 251)))
(define ~check-tokenizer-recovery-20 (lambda () (html-fixture-check 252)))
(define ~check-tokenizer-recovery-21 (lambda () (html-fixture-check 253)))
(define ~check-tokenizer-recovery-22 (lambda () (html-fixture-check 254)))
(define ~check-tokenizer-recovery-23 (lambda () (html-fixture-check 255)))
(define ~check-xml-coercion-0 (lambda () (html-fixture-check 256)))
(define ~check-xml-coercion-1 (lambda () (html-fixture-check 257)))
(define ~check-xml-coercion-2 (lambda () (html-fixture-check 258)))
(define ~check-xml-coercion-3 (lambda () (html-fixture-check 259)))
(define ~check-xml-coercion-4 (lambda () (html-fixture-check 260)))
(define ~check-xml-coercion-5 (lambda () (html-fixture-check 261)))

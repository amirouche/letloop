#!chezscheme
;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Port of yxml (submodules/yxml) to Chez Scheme. Input is a bytevector
;; of raw UTF-8 bytes, not a decoded string: yxml's state machine works
;; on single bytes, 0 to 255, and never decodes UTF-8 itself. It passes
;; a multi-byte sequence through untouched, so names and content are
;; accumulated as bytes and decoded once, when a span is complete.
;; State names match yxml.c's YXMLS_* enum
;; (yxml.c:28-95) so the two can be read side by side.
;;
;; Two layers. yxml-parser-make / yxml-step! / yxml-eof? are the push
;; parser: one byte in, one (values kind payload) out, errors returned
;; as a kind (esyn, eref, eclose, estack, eeof), never raised.
;; xml->sxml runs it over a whole bytevector and returns the root
;; element as SXML, raising on malformed input.
;;
;; As in yxml: comments and the DOCTYPE are dropped, <a/> and <a></a>
;; are the same, namespaces are not resolved ("dc:title" stays one
;; name), and only the five predefined entities and numeric references
;; are known.
;;
;; This file was imported from the atlas-stoa repository, where
;; spec/yxml-scheme-port-prompt.md describes the port. It was written
;; against yxml.c and test/ as of yxml f943875 (2020-03-07).
;;
;; yxml is MIT-licensed:
;;
;; Copyright (c) 2013-2014 Yoran Heling
;;
;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions:
;;
;; The above copyright notice and this permission notice shall be included
;; in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;; IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
;; CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
;; TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;; SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
(library (letloop xml yxml)
  (export xml->sxml
          yxml-parser-make
          yxml-step!
          yxml-eof?
          ~check-yxml-elem-minimal
          ~check-yxml-elem-nesting-content
          ~check-yxml-elem-mismatched-close
          ~check-yxml-attr
          ~check-yxml-numeric-ref-multibyte
          ~check-yxml-cdata-bracket-lookahead
          ~check-yxml-comment-no-token
          ~check-yxml-xmldecl-no-pi-token
          ~check-yxml-real-pi
          ~check-yxml-eof-incomplete
          ~check-yxml-eof-complete
          ~check-xml->sxml-minimal
          ~check-xml->sxml-nested-mixed-content
          ~check-xml->sxml-numeric-ref-assembled
          ~check-xml->sxml-pi-alongside-content
          ~check-xml->sxml-leading-pi-before-root
          ~check-yxml-official-fixtures)
  (import (chezscheme))

  ;; -------------------------------------------------------------------
  ;; Byte-class predicates (yxml.c:98-112)
  ;; -------------------------------------------------------------------

  (define (yxml-char? ch) #t)

  (define (yxml-sp? ch)
    (or (fx=? ch #x20) (fx=? ch #x09) (fx=? ch #x0a)))

  (define (yxml-alpha? ch)
    (let ((folded (fxior ch 32)))
      (and (fx>=? folded (char->integer #\a))
           (fx<=? folded (char->integer #\z)))))

  (define (yxml-num? ch)
    (and (fx>=? ch (char->integer #\0)) (fx<=? ch (char->integer #\9))))

  (define (yxml-hex? ch)
    (or (yxml-num? ch)
        (let ((folded (fxior ch 32)))
          (and (fx>=? folded (char->integer #\a))
               (fx<=? folded (char->integer #\f))))))

  (define (yxml-enc-name? ch)
    (or (yxml-alpha? ch) (yxml-num? ch)
        (fx=? ch (char->integer #\.))
        (fx=? ch (char->integer #\_))
        (fx=? ch (char->integer #\-))))

  (define (yxml-name-start? ch)
    (or (yxml-alpha? ch)
        (fx=? ch (char->integer #\:))
        (fx=? ch (char->integer #\_))
        (fx>=? ch 128)))

  (define (yxml-name? ch)
    (or (yxml-name-start? ch) (yxml-num? ch)
        (fx=? ch (char->integer #\-))
        (fx=? ch (char->integer #\.))))

  (define (yxml-att-value? ch quote)
    (and (yxml-char? ch)
         (not (fx=? ch quote))
         (not (fx=? ch (char->integer #\<)))
         (not (fx=? ch (char->integer #\&)))))

  (define (yxml-ref? ch)
    (or (yxml-num? ch) (yxml-alpha? ch) (fx=? ch (char->integer #\#))))

  ;; -------------------------------------------------------------------
  ;; Parser record (yxml_t, yxml.h:76-124)
  ;; -------------------------------------------------------------------
  ;;
  ;; No fixed-size stack buffer: yxml.c uses one because the C version
  ;; must not malloc (yxml.h's own commentary). Chez has no equivalent
  ;; reason, so open elements are a plain list of strings and the
  ;; currently-being-read name is a growable reversed byte list --
  ;; see the spec's layer-1 note on this. yxml_symlen's pointer-length
  ;; assertion (test.c:73/84/101) has no analogue here: real strings
  ;; replace pointer arithmetic, so that failure mode cannot occur.

  (define-record-type (yxml-parser yxml-parser-raw-make yxml-parser?)
    (fields (mutable state)
            (mutable nextstate)
            (mutable quote)
            (mutable ignore)
            (mutable match-remaining)   ; string still to match in 'string state, or #f
            (mutable match-nextstate)
            (mutable name-acc)          ; reversed list of bytes, name being read
            (mutable elem-stack)        ; list of strings, open elements, innermost first
            (mutable close-index)       ; bytes matched so far against elem-stack's top
            (mutable attr-name)
            (mutable pi-name)
            (mutable ref-acc)           ; reversed list of ASCII bytes, reference body
            (mutable line)
            (mutable byte)
            (mutable total)))

  (define (yxml-parser-make)
    (yxml-parser-raw-make 'init #f 0 0 #f #f '() '() 0 "" "" '() 1 0 0))

  ;; -------------------------------------------------------------------
  ;; Small helpers
  ;; -------------------------------------------------------------------

  (define (bytes->bytevector reversed-bytes)
    (let* ((bytes (reverse reversed-bytes))
           (length (length bytes))
           (bv (make-bytevector length)))
      (let loop ((i 0) (rest bytes))
        (if (null? rest)
          bv
          (begin (bytevector-u8-set! bv i (car rest))
                 (loop (fx+ i 1) (cdr rest)))))))

  (define (bytes->string reversed-bytes)
    (utf8->string (bytes->bytevector reversed-bytes)))

  (define (name-push! p ch)
    (yxml-parser-name-acc-set! p (cons ch (yxml-parser-name-acc p))))

  (define (name-finish-bytes! p)
    (let ((bytes (bytes->bytevector (yxml-parser-name-acc p))))
      (yxml-parser-name-acc-set! p '())
      bytes))

  (define (name-finish! p)
    (utf8->string (name-finish-bytes! p)))

  (define (utf8-encode-codepoint ch)
    ;; yxml_setutf8, yxml.c:130-147.
    (cond
     ((fx<=? ch #x007F) (list ch))
     ((fx<=? ch #x07FF)
      (list (fxior #xC0 (fxsrl ch 6))
            (fxior #x80 (fxand ch #x3F))))
     ((fx<=? ch #xFFFF)
      (list (fxior #xE0 (fxsrl ch 12))
            (fxior #x80 (fxand (fxsrl ch 6) #x3F))
            (fxior #x80 (fxand ch #x3F))))
     (else
      (list (fxior #xF0 (fxsrl ch 18))
            (fxior #x80 (fxand (fxsrl ch 12) #x3F))
            (fxior #x80 (fxand (fxsrl ch 6) #x3F))
            (fxior #x80 (fxand ch #x3F))))))

  (define (ref-push! p ch)
    ;; yxml_ref, yxml.c:286-292 -- 7-byte cap (sizeof(data)-1), real
    ;; validation, not an implementation artifact: an overlong numeric
    ;; or named reference is genuinely invalid XML.
    (if (fx>=? (length (yxml-parser-ref-acc p)) 7)
      'eref
      (begin (yxml-parser-ref-acc-set! p (cons ch (yxml-parser-ref-acc p)))
             'ok)))

  (define (ref-resolve p)
    ;; yxml_refend, yxml.c:295-322. Returns a codepoint or #f (invalid).
    (let ((bytes (reverse (yxml-parser-ref-acc p))))
      (yxml-parser-ref-acc-set! p '())
      (let ((ch
             (if (and (pair? bytes) (fx=? (car bytes) (char->integer #\#)))
               (if (and (pair? (cdr bytes)) (fx=? (cadr bytes) (char->integer #\x)))
                 (let loop ((rest (cddr bytes)) (value 0))
                   (cond
                    ((null? rest) value)
                    ((yxml-hex? (car rest))
                     (let* ((b (car rest))
                            (digit (if (yxml-num? b)
                                     (fx- b (char->integer #\0))
                                     (fx+ 10 (fx- (fxior b 32) (char->integer #\a))))))
                       (loop (cdr rest) (fx+ (fxsll value 4) digit))))
                    (else 0)))
                 (let loop ((rest (cdr bytes)) (value 0))
                   (cond
                    ((null? rest) value)
                    ((yxml-num? (car rest))
                     (loop (cdr rest) (fx+ (fx* value 10) (fx- (car rest) (char->integer #\0)))))
                    (else 0))))
               ;; bytes is already forward-order here (reversed once,
               ;; above); bytes->string expects reversed input and
               ;; reverses internally, so pass it reversed again or it
               ;; decodes every named entity backwards ("amp" -> "pma",
               ;; matching nothing).
               (let ((name (bytes->string (reverse bytes))))
                 (cond
                  ((string=? name "lt") (char->integer #\<))
                  ((string=? name "gt") (char->integer #\>))
                  ((string=? name "amp") (char->integer #\&))
                  ((string=? name "apos") (char->integer #\'))
                  ((string=? name "quot") (char->integer #\"))
                  (else 0))))))
        ;; yxml_refend's C check is `(unsigned)(ch-0xDFFF) < 0x7FF`, which
        ;; relies on unsigned 32-bit wraparound for ch < 0xDFFF. For any
        ;; ch in the valid codepoint range [0, 0x10FFFF] that is
        ;; equivalent to the plain range below -- computed once here
        ;; instead of emulating wraparound arithmetic.
        (if (or (fx=? ch 0) (fx>? ch #x10FFFF) (fx=? ch #xFFFE) (fx=? ch #xFFFF)
                (and (fx>=? ch #xDFFF) (fx<=? ch #xE7FD)))
          #f
          ch))))

  ;; -------------------------------------------------------------------
  ;; The state machine (yxml_parse, yxml.c:340-1054)
  ;; -------------------------------------------------------------------
  ;;
  ;; Returns two values: a token-kind symbol and a payload (string or
  ;; #f). Token kinds: ok, elem-start, content, elem-end, attr-start,
  ;; attr-val, attr-end, pi-start, pi-content, pi-end, eeof, eref,
  ;; eclose, estack, esyn.

  (define (yxml-step! p ch0)
    (yxml-parser-total-set! p (fx+ 1 (yxml-parser-total p)))
    (if (fx=? ch0 0)
      (values 'esyn #f)
      (if (fx=? (yxml-parser-ignore p) ch0)
        (begin (yxml-parser-ignore-set! p 0) (values 'ok #f))
        (let ()
          (yxml-parser-ignore-set! p (if (fx=? ch0 #x0d) #x0a 0))
          (let ((ch (if (or (fx=? ch0 #x0a) (fx=? ch0 #x0d))
                      (begin (yxml-parser-line-set! p (fx+ 1 (yxml-parser-line p)))
                             (yxml-parser-byte-set! p 0)
                             #x0a)
                      ch0)))
            (yxml-parser-byte-set! p (fx+ 1 (yxml-parser-byte p)))
            (yxml-dispatch! p ch))))))

  (define (elem-open! p ch)
    ;; yxml_elemstart + yxml_elemname/yxml_elemnameend, but here the
    ;; element's own name (not the fixed byte-stack) drives everything
    ;; downstream, so "open" just starts the accumulator.
    (name-push! p ch)
    (values 'ok #f))

  (define (elem-name-finish! p)
    ;; Close-tag matching (elem-close-byte!/elem-close-end! below) must
    ;; compare against the element name's raw UTF-8 bytes, not its
    ;; decoded string -- yxml.c has no decode step at all, it matches
    ;; the incoming closing-tag bytes directly against the still-open
    ;; name's own bytes. Comparing decoded characters instead breaks
    ;; the moment a name has any non-ASCII byte (reproduced directly
    ;; against submodules/yxml/test/elem06.xml, whose element name is
    ;; CJK): one raw byte can never equal one whole decoded codepoint.
    (let* ((bytes (name-finish-bytes! p))
           (name (utf8->string bytes)))
      (yxml-parser-elem-stack-set! p (cons bytes (yxml-parser-elem-stack p)))
      (values 'elem-start name)))

  (define (attr-name-finish! p)
    (let ((name (name-finish! p)))
      (yxml-parser-attr-name-set! p name)
      (values 'attr-start name)))

  (define (pi-name-finish! p)
    (let ((name (name-finish! p)))
      (yxml-parser-pi-name-set! p name)
      (values 'pi-start name)))

  (define (selfclose! p)
    ;; yxml_selfclose, yxml.c:233-245.
    (yxml-parser-elem-stack-set! p (cdr (yxml-parser-elem-stack p)))
    (yxml-parser-close-index-set! p 0)
    (when (null? (yxml-parser-elem-stack p))
      (yxml-parser-state-set! p 'misc3))
    (values 'elem-end #f))

  (define (elem-close-byte! p ch)
    ;; yxml_elemclose, yxml.c:248-253. open is a bytevector -- see
    ;; elem-name-finish!'s comment.
    (let* ((open (car (yxml-parser-elem-stack p)))
           (idx (yxml-parser-close-index p)))
      (if (and (fx<? idx (bytevector-length open))
               (fx=? (bytevector-u8-ref open idx) ch))
        (begin (yxml-parser-close-index-set! p (fx+ idx 1)) (values 'ok #f))
        (values 'eclose #f))))

  (define (elem-close-end! p)
    ;; yxml_elemcloseend, yxml.c:256-260.
    (let ((open (car (yxml-parser-elem-stack p))))
      (if (fx=? (yxml-parser-close-index p) (bytevector-length open))
        (selfclose! p)
        (values 'eclose #f))))

  (define (ref-start! p) (yxml-parser-ref-acc-set! p '()) (values 'ok #f))

  (define (ref-end! p kind)
    ;; Token payload is the raw UTF-8 bytes of the resolved codepoint,
    ;; not a decoded string -- see "content payloads are raw bytes,
    ;; not decoded strings" below. utf8-encode-codepoint already
    ;; returns forward-order bytes, so reverse once for
    ;; bytes->bytevector's "already reversed" convention.
    (let ((codepoint (ref-resolve p)))
      (if (not codepoint)
        (values 'eref #f)
        (values kind (bytes->bytevector (reverse (utf8-encode-codepoint codepoint)))))))

  (define (attr-data! p ch)
    ;; yxml_dataattr, yxml.c:189-194: tab/newline normalize to space.
    (let ((normalized (if (or (fx=? ch #x9) (fx=? ch #xa)) #x20 ch)))
      (values 'attr-val (bytevector normalized))))

  (define (start-string-match! p literal nextstate)
    (yxml-parser-match-remaining-set! p literal)
    (yxml-parser-match-nextstate-set! p nextstate)
    (yxml-parser-state-set! p 'string))

  (define (yxml-dispatch! p ch)
    (case (yxml-parser-state p)

      ((string)
       (let ((remaining (yxml-parser-match-remaining p)))
         (if (fx=? ch (char->integer (string-ref remaining 0)))
           (let ((rest (substring remaining 1 (string-length remaining))))
             (if (fx=? (string-length rest) 0)
               (yxml-parser-state-set! p (yxml-parser-match-nextstate p))
               (yxml-parser-match-remaining-set! p rest))
             (values 'ok #f))
           (values 'esyn #f))))

      ;; ---- attr0..attr4 (yxml.c:373-421) ----
      ((attr0)
       (cond
        ((yxml-name? ch) (name-push! p ch) (values 'ok #f))
        ((yxml-sp? ch) (yxml-parser-state-set! p 'attr1) (attr-name-finish! p))
        ((fx=? ch (char->integer #\=)) (yxml-parser-state-set! p 'attr2) (attr-name-finish! p))
        (else (values 'esyn #f))))
      ((attr1)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\=)) (yxml-parser-state-set! p 'attr2) (values 'ok #f))
        (else (values 'esyn #f))))
      ((attr2)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((or (fx=? ch (char->integer #\')) (fx=? ch (char->integer #\")))
         (yxml-parser-state-set! p 'attr3) (yxml-parser-quote-set! p ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((attr3)
       (cond
        ((yxml-att-value? ch (yxml-parser-quote p)) (attr-data! p ch))
        ((fx=? ch (char->integer #\&))
         (yxml-parser-state-set! p 'attr4) (ref-start! p))
        ((fx=? (yxml-parser-quote p) ch)
         (yxml-parser-state-set! p 'elem2) (values 'attr-end #f))
        (else (values 'esyn #f))))
      ((attr4)
       (cond
        ((yxml-ref? ch) (let ((r (ref-push! p ch))) (values r #f)))
        ((fx=? ch (char->integer #\;))
         (yxml-parser-state-set! p 'attr3) (ref-end! p 'attr-val))
        (else (values 'esyn #f))))

      ;; ---- cd0..cd2 (yxml.c:422-451) ----
      ((cd0)
       (cond
        ((fx=? ch (char->integer #\])) (yxml-parser-state-set! p 'cd1) (values 'ok #f))
        ((yxml-char? ch) (values 'content (bytevector ch)))
        (else (values 'esyn #f))))
      ((cd1)
       (cond
        ((fx=? ch (char->integer #\])) (yxml-parser-state-set! p 'cd2) (values 'ok #f))
        ((yxml-char? ch)
         (yxml-parser-state-set! p 'cd0)
         (values 'content (bytevector (char->integer #\]) ch)))
        (else (values 'esyn #f))))
      ((cd2)
       (cond
        ((fx=? ch (char->integer #\])) (values 'content (bytevector (char->integer #\]))))
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'misc2) (values 'ok #f))
        ((yxml-char? ch)
         (yxml-parser-state-set! p 'cd0)
         (values 'content (bytevector (char->integer #\]) (char->integer #\]) ch)))
        (else (values 'esyn #f))))

      ;; ---- comment0..comment4 (yxml.c:452-487) ----
      ((comment0)
       (if (fx=? ch (char->integer #\-)) (begin (yxml-parser-state-set! p 'comment1) (values 'ok #f)) (values 'esyn #f)))
      ((comment1)
       (if (fx=? ch (char->integer #\-)) (begin (yxml-parser-state-set! p 'comment2) (values 'ok #f)) (values 'esyn #f)))
      ((comment2)
       (cond
        ((fx=? ch (char->integer #\-)) (yxml-parser-state-set! p 'comment3) (values 'ok #f))
        ((yxml-char? ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((comment3)
       (cond
        ((fx=? ch (char->integer #\-)) (yxml-parser-state-set! p 'comment4) (values 'ok #f))
        ((yxml-char? ch) (yxml-parser-state-set! p 'comment2) (values 'ok #f))
        (else (values 'esyn #f))))
      ((comment4)
       (if (fx=? ch (char->integer #\>))
         (begin (yxml-parser-state-set! p (yxml-parser-nextstate p)) (values 'ok #f))
         (values 'esyn #f)))

      ;; ---- dt0..dt4 (yxml.c:488-549) ----
      ((dt0)
       (cond
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'misc1) (values 'ok #f))
        ((or (fx=? ch (char->integer #\')) (fx=? ch (char->integer #\")))
         (yxml-parser-state-set! p 'dt1) (yxml-parser-quote-set! p ch) (yxml-parser-nextstate-set! p 'dt0) (values 'ok #f))
        ((fx=? ch (char->integer #\<)) (yxml-parser-state-set! p 'dt2) (values 'ok #f))
        ((yxml-char? ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((dt1)
       (cond
        ((fx=? (yxml-parser-quote p) ch) (yxml-parser-state-set! p (yxml-parser-nextstate p)) (values 'ok #f))
        ((yxml-char? ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((dt2)
       (cond
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'pi0) (yxml-parser-nextstate-set! p 'dt0) (values 'ok #f))
        ((fx=? ch (char->integer #\!)) (yxml-parser-state-set! p 'dt3) (values 'ok #f))
        (else (values 'esyn #f))))
      ((dt3)
       (cond
        ((fx=? ch (char->integer #\-))
         (yxml-parser-state-set! p 'comment1) (yxml-parser-nextstate-set! p 'dt0) (values 'ok #f))
        ((yxml-char? ch) (yxml-parser-state-set! p 'dt4) (values 'ok #f))
        (else (values 'esyn #f))))
      ((dt4)
       (cond
        ((or (fx=? ch (char->integer #\')) (fx=? ch (char->integer #\")))
         (yxml-parser-state-set! p 'dt1) (yxml-parser-quote-set! p ch) (yxml-parser-nextstate-set! p 'dt4) (values 'ok #f))
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'dt0) (values 'ok #f))
        ((yxml-char? ch) (values 'ok #f))
        (else (values 'esyn #f))))

      ;; ---- elem0..elem3 (yxml.c:550-601) ----
      ((elem0)
       (cond
        ((yxml-name? ch) (elem-open! p ch))
        ((yxml-sp? ch) (yxml-parser-state-set! p 'elem1) (elem-name-finish! p))
        ((fx=? ch (char->integer #\/)) (yxml-parser-state-set! p 'elem3) (elem-name-finish! p))
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'misc2) (elem-name-finish! p))
        (else (values 'esyn #f))))
      ((elem1)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\/)) (yxml-parser-state-set! p 'elem3) (values 'ok #f))
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'misc2) (values 'ok #f))
        ((yxml-name-start? ch) (yxml-parser-state-set! p 'attr0) (name-push! p ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((elem2)
       (cond
        ((yxml-sp? ch) (yxml-parser-state-set! p 'elem1) (values 'ok #f))
        ((fx=? ch (char->integer #\/)) (yxml-parser-state-set! p 'elem3) (values 'ok #f))
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'misc2) (values 'ok #f))
        (else (values 'esyn #f))))
      ((elem3)
       (if (fx=? ch (char->integer #\>))
         (begin (yxml-parser-state-set! p 'misc2) (selfclose! p))
         (values 'esyn #f)))

      ;; ---- enc0..enc3 (yxml.c:602-632) ----
      ((enc0)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\=)) (yxml-parser-state-set! p 'enc1) (values 'ok #f))
        (else (values 'esyn #f))))
      ((enc1)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((or (fx=? ch (char->integer #\')) (fx=? ch (char->integer #\")))
         (yxml-parser-state-set! p 'enc2) (yxml-parser-quote-set! p ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((enc2)
       (if (yxml-alpha? ch) (begin (yxml-parser-state-set! p 'enc3) (values 'ok #f)) (values 'esyn #f)))
      ((enc3)
       (cond
        ((yxml-enc-name? ch) (values 'ok #f))
        ((fx=? (yxml-parser-quote p) ch) (yxml-parser-state-set! p 'xmldecl6) (values 'ok #f))
        (else (values 'esyn #f))))

      ;; ---- etag0..etag2 (yxml.c:633-658) ----
      ((etag0)
       (if (yxml-name-start? ch)
         (begin (yxml-parser-state-set! p 'etag1) (elem-close-byte! p ch))
         (values 'esyn #f)))
      ((etag1)
       (cond
        ((yxml-name? ch) (elem-close-byte! p ch))
        ((yxml-sp? ch) (yxml-parser-state-set! p 'etag2) (elem-close-end! p))
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'misc2) (elem-close-end! p))
        (else (values 'esyn #f))))
      ((etag2)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\>)) (yxml-parser-state-set! p 'misc2) (values 'ok #f))
        (else (values 'esyn #f))))

      ;; ---- init (yxml.c:659-674) ----
      ((init)
       (cond
        ((fx=? ch #xef) (start-string-match! p "\xbb;\xbf;" 'misc0) (values 'ok #f))
        ((yxml-sp? ch) (yxml-parser-state-set! p 'misc0) (values 'ok #f))
        ((fx=? ch (char->integer #\<)) (yxml-parser-state-set! p 'le0) (values 'ok #f))
        (else (values 'esyn #f))))

      ;; ---- le0..le3 (yxml.c:675-734) ----
      ((le0)
       (cond
        ((fx=? ch (char->integer #\!)) (yxml-parser-state-set! p 'lee1) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'leq0) (values 'ok #f))
        ((yxml-name-start? ch) (yxml-parser-state-set! p 'elem0) (elem-open! p ch))
        (else (values 'esyn #f))))
      ((le1)
       (cond
        ((fx=? ch (char->integer #\!)) (yxml-parser-state-set! p 'lee1) (values 'ok #f))
        ((fx=? ch (char->integer #\?))
         (yxml-parser-state-set! p 'pi0) (yxml-parser-nextstate-set! p 'misc1) (values 'ok #f))
        ((yxml-name-start? ch) (yxml-parser-state-set! p 'elem0) (elem-open! p ch))
        (else (values 'esyn #f))))
      ((le2)
       (cond
        ((fx=? ch (char->integer #\!)) (yxml-parser-state-set! p 'lee2) (values 'ok #f))
        ((fx=? ch (char->integer #\?))
         (yxml-parser-state-set! p 'pi0) (yxml-parser-nextstate-set! p 'misc2) (values 'ok #f))
        ((fx=? ch (char->integer #\/))
         (yxml-parser-state-set! p 'etag0) (yxml-parser-close-index-set! p 0) (values 'ok #f))
        ((yxml-name-start? ch) (yxml-parser-state-set! p 'elem0) (elem-open! p ch))
        (else (values 'esyn #f))))
      ((le3)
       (cond
        ((fx=? ch (char->integer #\!))
         (yxml-parser-state-set! p 'comment0) (yxml-parser-nextstate-set! p 'misc3) (values 'ok #f))
        ((fx=? ch (char->integer #\?))
         (yxml-parser-state-set! p 'pi0) (yxml-parser-nextstate-set! p 'misc3) (values 'ok #f))
        (else (values 'esyn #f))))

      ;; ---- lee1, lee2, leq0 (yxml.c:735-772) ----
      ((lee1)
       (cond
        ((fx=? ch (char->integer #\-))
         (yxml-parser-state-set! p 'comment1) (yxml-parser-nextstate-set! p 'misc1) (values 'ok #f))
        ((fx=? ch (char->integer #\D)) (start-string-match! p "OCTYPE" 'dt0) (values 'ok #f))
        (else (values 'esyn #f))))
      ((lee2)
       (cond
        ((fx=? ch (char->integer #\-))
         (yxml-parser-state-set! p 'comment1) (yxml-parser-nextstate-set! p 'misc2) (values 'ok #f))
        ((fx=? ch (char->integer #\[)) (start-string-match! p "CDATA[" 'cd0) (values 'ok #f))
        (else (values 'esyn #f))))
      ((leq0)
       (cond
        ((fx=? ch (char->integer #\x))
         (yxml-parser-state-set! p 'xmldecl0) (yxml-parser-nextstate-set! p 'misc1)
         (pi-open! p ch))
        ((yxml-name-start? ch)
         (yxml-parser-state-set! p 'pi1) (yxml-parser-nextstate-set! p 'misc1) (pi-open! p ch))
        (else (values 'esyn #f))))

      ;; ---- misc0..misc3, misc2a (yxml.c:773-816) ----
      ((misc0)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\<)) (yxml-parser-state-set! p 'le0) (values 'ok #f))
        (else (values 'esyn #f))))
      ((misc1)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\<)) (yxml-parser-state-set! p 'le1) (values 'ok #f))
        (else (values 'esyn #f))))
      ((misc2)
       (cond
        ((fx=? ch (char->integer #\<)) (yxml-parser-state-set! p 'le2) (values 'ok #f))
        ((fx=? ch (char->integer #\&)) (yxml-parser-state-set! p 'misc2a) (ref-start! p))
        ((yxml-char? ch) (values 'content (bytevector ch)))
        (else (values 'esyn #f))))
      ((misc2a)
       (cond
        ((yxml-ref? ch) (let ((r (ref-push! p ch))) (values r #f)))
        ((fx=? ch (char->integer #\;))
         (yxml-parser-state-set! p 'misc2) (ref-end! p 'content))
        (else (values 'esyn #f))))
      ((misc3)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\<)) (yxml-parser-state-set! p 'le3) (values 'ok #f))
        (else (values 'esyn #f))))

      ;; ---- pi0..pi4 (yxml.c:817-858) ----
      ((pi0)
       (if (yxml-name-start? ch)
         (begin (yxml-parser-state-set! p 'pi1) (pi-open! p ch))
         (values 'esyn #f)))
      ((pi1)
       (cond
        ((yxml-name? ch) (pi-name-push! p ch) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'pi4) (pi-name-end! p))
        ((yxml-sp? ch) (yxml-parser-state-set! p 'pi2) (pi-name-end! p))
        (else (values 'esyn #f))))
      ((pi2)
       (cond
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'pi3) (values 'ok #f))
        ((yxml-char? ch) (values 'pi-content (bytevector ch)))
        (else (values 'esyn #f))))
      ((pi3)
       (cond
        ((fx=? ch (char->integer #\>))
         (yxml-parser-state-set! p (yxml-parser-nextstate p)) (values 'pi-end #f))
        ((yxml-char? ch) (yxml-parser-state-set! p 'pi2) (values 'pi-content (bytevector (char->integer #\?) ch)))
        (else (values 'esyn #f))))
      ((pi4)
       (if (fx=? ch (char->integer #\>))
         (begin (yxml-parser-state-set! p (yxml-parser-nextstate p)) (values 'pi-end #f))
         (values 'esyn #f)))

      ;; ---- std0..std3 (yxml.c:859-895) ----
      ((std0)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\=)) (yxml-parser-state-set! p 'std1) (values 'ok #f))
        (else (values 'esyn #f))))
      ((std1)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((or (fx=? ch (char->integer #\')) (fx=? ch (char->integer #\")))
         (yxml-parser-state-set! p 'std2) (yxml-parser-quote-set! p ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((std2)
       (cond
        ((fx=? ch (char->integer #\y)) (start-string-match! p "es" 'std3) (values 'ok #f))
        ((fx=? ch (char->integer #\n)) (start-string-match! p "o" 'std3) (values 'ok #f))
        (else (values 'esyn #f))))
      ((std3)
       (if (fx=? (yxml-parser-quote p) ch)
         (begin (yxml-parser-state-set! p 'xmldecl8) (values 'ok #f))
         (values 'esyn #f)))

      ;; ---- ver0..ver3 (yxml.c:896-928) ----
      ((ver0)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\=)) (yxml-parser-state-set! p 'ver1) (values 'ok #f))
        (else (values 'esyn #f))))
      ((ver1)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((or (fx=? ch (char->integer #\')) (fx=? ch (char->integer #\")))
         (yxml-parser-quote-set! p ch) (start-string-match! p "1." 'ver2) (values 'ok #f))
        (else (values 'esyn #f))))
      ((ver2)
       (if (yxml-num? ch) (begin (yxml-parser-state-set! p 'ver3) (values 'ok #f)) (values 'esyn #f)))
      ((ver3)
       (cond
        ((yxml-num? ch) (values 'ok #f))
        ((fx=? (yxml-parser-quote p) ch) (yxml-parser-state-set! p 'xmldecl4) (values 'ok #f))
        (else (values 'esyn #f))))

      ;; ---- xmldecl0..xmldecl9 (yxml.c:929-1052) ----
      ((xmldecl0)
       (cond
        ((fx=? ch (char->integer #\m)) (yxml-parser-state-set! p 'xmldecl1) (pi-name-push! p ch) (values 'ok #f))
        ((yxml-name? ch) (yxml-parser-state-set! p 'pi1) (pi-name-push! p ch) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'pi4) (pi-name-end! p))
        ((yxml-sp? ch) (yxml-parser-state-set! p 'pi2) (pi-name-end! p))
        (else (values 'esyn #f))))
      ((xmldecl1)
       (cond
        ((fx=? ch (char->integer #\l)) (yxml-parser-state-set! p 'xmldecl2) (pi-name-push! p ch) (values 'ok #f))
        ((yxml-name? ch) (yxml-parser-state-set! p 'pi1) (pi-name-push! p ch) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'pi4) (pi-name-end! p))
        ((yxml-sp? ch) (yxml-parser-state-set! p 'pi2) (pi-name-end! p))
        (else (values 'esyn #f))))
      ((xmldecl2)
       (cond
        ((yxml-sp? ch) (yxml-parser-state-set! p 'xmldecl3) (pi-abort! p))
        ((yxml-name? ch) (yxml-parser-state-set! p 'pi1) (pi-name-push! p ch) (values 'ok #f))
        (else (values 'esyn #f))))
      ((xmldecl3)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\v)) (start-string-match! p "ersion" 'ver0) (values 'ok #f))
        (else (values 'esyn #f))))
      ((xmldecl4)
       (cond
        ((yxml-sp? ch) (yxml-parser-state-set! p 'xmldecl5) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'xmldecl9) (values 'ok #f))
        (else (values 'esyn #f))))
      ((xmldecl5)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'xmldecl9) (values 'ok #f))
        ((fx=? ch (char->integer #\e)) (start-string-match! p "ncoding" 'enc0) (values 'ok #f))
        ((fx=? ch (char->integer #\s)) (start-string-match! p "tandalone" 'std0) (values 'ok #f))
        (else (values 'esyn #f))))
      ((xmldecl6)
       (cond
        ((yxml-sp? ch) (yxml-parser-state-set! p 'xmldecl7) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'xmldecl9) (values 'ok #f))
        (else (values 'esyn #f))))
      ((xmldecl7)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'xmldecl9) (values 'ok #f))
        ((fx=? ch (char->integer #\s)) (start-string-match! p "tandalone" 'std0) (values 'ok #f))
        (else (values 'esyn #f))))
      ((xmldecl8)
       (cond
        ((yxml-sp? ch) (values 'ok #f))
        ((fx=? ch (char->integer #\?)) (yxml-parser-state-set! p 'xmldecl9) (values 'ok #f))
        (else (values 'esyn #f))))
      ((xmldecl9)
       (if (fx=? ch (char->integer #\>))
         (begin (yxml-parser-state-set! p 'misc1) (values 'ok #f))
         (values 'esyn #f)))

      (else (values 'esyn #f))))

  ;; pi-open!/pi-name-push!/pi-name-end!/pi-abort! -- yxml_pistart/
  ;; yxml_piname/yxml_pinameend/yxml_piabort, yxml.c:269-274.
  (define (pi-open! p ch) (name-push! p ch) (values 'ok #f))
  (define (pi-name-push! p ch) (name-push! p ch))
  (define (pi-name-end! p)
    ;; yxml_pinameend: reject a PI literally named "xml" reached via
    ;; the generic path -- only the dedicated xmldecl0 sub-machine may
    ;; claim that name (yxml.c:272-274).
    (let ((name (name-finish! p)))
      (if (and (fx=? (string-length name) 3)
               (char-ci=? (string-ref name 0) #\x)
               (char-ci=? (string-ref name 1) #\m)
               (char-ci=? (string-ref name 2) #\l))
        (values 'esyn #f)
        (begin (yxml-parser-pi-name-set! p name) (values 'pi-start name)))))
  (define (pi-abort! p) (name-finish! p) (values 'ok #f))

  (define (yxml-eof? p) (eq? (yxml-parser-state p) 'misc3))

  ;; -------------------------------------------------------------------
  ;; Layer 2 -- SXML assembly, entry point (spec layer 2)
  ;; -------------------------------------------------------------------
  ;;
  ;; Element: (name (@ (attr "value") ...) child ...); text: a bare
  ;; string, adjacent chunks merged; PI: (*PI* target "data"). No
  ;; comment/DOCTYPE node -- yxml never surfaces either (see spec).

  (define sxml-attribute-mark (string->symbol "@"))

  (define (bytevector-append-list bvs)
    ;; Not bound by (chezscheme) in this environment -- a small local
    ;; replacement, not an extra import.
    (let* ((total (fold-left (lambda (n bv) (fx+ n (bytevector-length bv))) 0 bvs))
           (out (make-bytevector total)))
      (let loop ((bvs bvs) (offset 0))
        (if (null? bvs)
          out
          (begin (bytevector-copy! (car bvs) 0 out offset (bytevector-length (car bvs)))
                 (loop (cdr bvs) (fx+ offset (bytevector-length (car bvs)))))))))

  ;; content/attr-val/pi-content payloads are raw UTF-8 bytevectors, not
  ;; decoded strings (see yxml-dispatch!'s content-producing arms): a
  ;; single content byte may be one byte of a multi-byte UTF-8
  ;; character, so decoding it in isolation would corrupt it (this was
  ;; reproduced directly against submodules/yxml/test/elem06.xml, whose
  ;; content is Cyrillic). Byte chunks must be concatenated into a full
  ;; run first and decoded exactly once.
  (define (chunks->string reversed-chunks)
    (if (null? reversed-chunks)
      ""
      (utf8->string (bytevector-append-list (reverse reversed-chunks)))))

  (define (xml->sxml bytes)
    (let ((p (yxml-parser-make))
          (size (bytevector-length bytes))
          ;; Each frame: (name attrs-reversed children-reversed pending-text-chunks-reversed)
          (stack (list (list '*TOP* '() '() '())))
          (attr-value-chunks '())
          (pi-content-chunks '()))

      (define (top) (car stack))
      (define (top-name f) (list-ref f 0))
      (define (top-attrs f) (list-ref f 1))
      (define (top-children f) (list-ref f 2))
      (define (top-text f) (list-ref f 3))

      ;; Move the current top frame's pending text into its children
      ;; list, in place. Must run before ANY sibling (element or PI)
      ;; is added as a child -- otherwise text that arrived before that
      ;; sibling silently merges with text that arrives after it.
      (define (flush-top-text!)
        (let ((frame (top)))
          (unless (null? (top-text frame))
            (set-car! stack (list (top-name frame) (top-attrs frame)
                                   (cons (chunks->string (top-text frame)) (top-children frame))
                                   '())))))

      (define (append-text! chunk)
        (let ((frame (top)))
          (set-car! stack (list (top-name frame) (top-attrs frame) (top-children frame)
                                 (cons chunk (top-text frame))))))

      (define (add-attribute! name value)
        (let ((frame (top)))
          (set-car! stack (list (top-name frame) (cons (list (string->symbol name) value) (top-attrs frame))
                                 (top-children frame) (top-text frame)))))

      (define (add-child! node)
        (let ((frame (top)))
          (set-car! stack (list (top-name frame) (top-attrs frame) (cons node (top-children frame))
                                 (top-text frame)))))

      (define (close-element!)
        (flush-top-text!)
        (let* ((frame (top))
               (children (reverse (top-children frame)))
               (attrs (reverse (top-attrs frame)))
               (element (if (null? attrs)
                          (cons (top-name frame) children)
                          (cons* (top-name frame) (cons sxml-attribute-mark attrs) children))))
          (set! stack (cdr stack))
          (add-child! element)))

      (let loop ((i 0))
        (if (fx=? i size)
          (void)
          (let-values (((kind payload) (yxml-step! p (bytevector-u8-ref bytes i))))
            (case kind
              ((ok) (void))
              ((elem-start)
               (flush-top-text!)
               (set! stack (cons (list (string->symbol payload) '() '() '()) stack)))
              ((content) (append-text! payload))
              ((elem-end) (close-element!))
              ((attr-start) (set! attr-value-chunks '()))
              ((attr-val) (set! attr-value-chunks (cons payload attr-value-chunks)))
              ((attr-end) (add-attribute! (yxml-parser-attr-name p) (chunks->string attr-value-chunks)))
              ((pi-start) (set! pi-content-chunks '()))
              ((pi-content) (set! pi-content-chunks (cons payload pi-content-chunks)))
              ((pi-end)
               (flush-top-text!)
               (add-child! (list '*PI* (string->symbol (yxml-parser-pi-name p)) (chunks->string pi-content-chunks))))
              (else (error 'xml->sxml "malformed XML" kind (yxml-parser-line p) (yxml-parser-byte p))))
            (loop (fx+ i 1)))))
      (flush-top-text!)
      ;; *TOP*'s children can include leading *PI* nodes (e.g. a
      ;; <?xml-stylesheet?> before the root, common in OAI-PMH
      ;; responses) and whitespace-only text strings between them --
      ;; skip past both to the actual root element, don't just take the
      ;; first child in document order.
      (let find-root ((children (reverse (top-children (top)))))
        (cond
          ((null? children) (error 'xml->sxml "no root element found"))
          ((and (pair? (car children)) (not (eq? (car (car children)) '*PI*)))
           (car children))
          (else (find-root (cdr children)))))))

  ;; -------------------------------------------------------------------
  ;; Layer 1 tests -- hand-verified cases from the spec
  ;; -------------------------------------------------------------------

  (define (drive-string p text)
    ;; Feed an ASCII test string byte by byte, collecting (kind . payload).
    (let loop ((i 0) (out '()))
      (if (fx=? i (string-length text))
        (reverse out)
        (let-values (((kind payload) (yxml-step! p (char->integer (string-ref text i)))))
          (loop (fx+ i 1) (cons (cons kind payload) out))))))

  (define (non-ok events)
    (filter (lambda (e) (not (eq? (car e) 'ok))) events))

  (define error-kinds '(esyn eref eclose estack eeof))

  (define (until-first-error events)
    ;; yxml_parse's behavior past the first error is unspecified (the
    ;; real harness, test.c, exits immediately on one) -- truncate a
    ;; driven event list the same way before asserting on it.
    (let loop ((events events) (out '()))
      (cond
       ((null? events) (reverse out))
       ((memq (caar events) error-kinds) (reverse (cons (car events) out)))
       (else (loop (cdr events) (cons (car events) out))))))

  (define (~check-yxml-elem-minimal)
    (let ((p (yxml-parser-make)))
      (assert (equal? (non-ok (drive-string p "<a/>"))
                       '((elem-start . "a") (elem-end . #f))))
      (assert (yxml-eof? p))))

  (define (~check-yxml-elem-nesting-content)
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<a><b>x</b></a>"))))
      (assert (equal? (map car events) '(elem-start elem-start content elem-end elem-end)))
      (assert (bytevector=? (cdr (list-ref events 2)) (bytevector (char->integer #\x))))
      (assert (yxml-eof? p))))

  (define (~check-yxml-elem-mismatched-close)
    (let ((p (yxml-parser-make)))
      (assert (equal? (until-first-error (non-ok (drive-string p "<a></b>")))
                       '((elem-start . "a") (eclose . #f))))))

  (define (~check-yxml-attr)
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<a b=\"c\"/>"))))
      (assert (equal? (map car events) '(elem-start attr-start attr-val attr-end elem-end)))
      (assert (bytevector=? (cdr (list-ref events 2)) (bytevector (char->integer #\c))))))

  (define (~check-yxml-numeric-ref-multibyte)
    (let* ((p (yxml-parser-make))
           (content-events (filter (lambda (e) (eq? (car e) 'content)) (drive-string p "<a>&#8364;</a>"))))
      ;; euro sign U+20AC, 3-byte UTF-8, produced as one content event.
      (assert (fx=? 1 (length content-events)))
      (assert (string=? (utf8->string (cdr (car content-events))) "\x20ac;"))))

  (define (~check-yxml-cdata-bracket-lookahead)
    (let* ((p (yxml-parser-make))
           (events (drive-string p "<a><![CDATA[x]]y]]></a>"))
           (content-events (filter (lambda (e) (eq? (car e) 'content)) events))
           (assembled (utf8->string (bytevector-append-list (map cdr content-events)))))
      (assert (string=? assembled "x]]y"))))

  (define (~check-yxml-comment-no-token)
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<a><!-- hi --></a>"))))
      (assert (equal? events '((elem-start . "a") (elem-end . #f))))))

  (define (~check-yxml-xmldecl-no-pi-token)
    (let* ((p (yxml-parser-make))
           (events (drive-string p "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")))
      (assert (not (memq 'pi-start (map car events))))
      (assert (equal? (map car (filter (lambda (e) (memq (car e) '(elem-start elem-end))) events))
                       '(elem-start elem-end)))))

  (define (~check-yxml-real-pi)
    (let* ((p (yxml-parser-make))
           (events (non-ok (drive-string p "<?target data?><a/>")))
           (pi-content-events (filter (lambda (e) (eq? (car e) 'pi-content)) events)))
      (assert (equal? (map car events)
                       '(pi-start pi-content pi-content pi-content pi-content pi-end elem-start elem-end)))
      (assert (string=? (cdr (car events)) "target"))
      (assert (string=? (utf8->string (bytevector-append-list (map cdr pi-content-events))) "data"))))

  (define (~check-yxml-eof-incomplete)
    (let ((p (yxml-parser-make)))
      (drive-string p "<a><b>x</b>")
      (assert (not (yxml-eof? p)))))

  (define (~check-yxml-eof-complete)
    (let ((p (yxml-parser-make)))
      (drive-string p "<a></a>")
      (assert (yxml-eof? p))))

  ;; -------------------------------------------------------------------
  ;; Layer 2 tests
  ;; -------------------------------------------------------------------

  (define (~check-xml->sxml-minimal)
    (assert (equal? (xml->sxml (string->utf8 "<a/>")) '(a))))

  (define (~check-xml->sxml-nested-mixed-content)
    (assert (equal? (xml->sxml (string->utf8 "<a>t1<b>x</b>t2</a>"))
                     '(a "t1" (b "x") "t2"))))

  (define (~check-xml->sxml-numeric-ref-assembled)
    (assert (equal? (xml->sxml (string->utf8 "<a>&#8364;</a>"))
                     (list 'a "\x20ac;"))))

  (define (~check-xml->sxml-pi-alongside-content)
    (assert (equal? (xml->sxml (string->utf8 "<a><?target data?>x</a>"))
                     '(a (*PI* target "data") "x"))))

  ;; Regression: a PI before the root element (e.g. a real-world
  ;; <?xml-stylesheet?>, common in OAI-PMH responses) must not become
  ;; what xml->sxml returns as "top" -- it has to be skipped in favor of
  ;; the actual root element that follows it. Found via a real Persee
  ;; OAI-PMH fixture during incorporated.scm's development: the old
  ;; implementation returned (*PI* xml-stylesheet "...") itself as top,
  ;; so every subsequent sxpath query against it silently matched
  ;; nothing instead of erroring.
  (define (~check-xml->sxml-leading-pi-before-root)
    (assert (equal? (xml->sxml (string->utf8 "<?xml-stylesheet type=\"text/xsl\" href=\"x.xsl\"?><a>x</a>"))
                     '(a "x")))
    ;; Whitespace between the PI and the root element must also not
    ;; become a spurious extra "child" that confuses root-finding.
    (assert (equal? (xml->sxml (string->utf8 "<?xml-stylesheet type=\"text/xsl\" href=\"x.xsl\"?>\n<a>x</a>"))
                     '(a "x"))))

  ;; -------------------------------------------------------------------
  ;; Official yxml test corpus (submodules/yxml/test/*.xml + *.out)
  ;; -------------------------------------------------------------------
  ;;
  ;; Reproduces test.c's y_printres formatting exactly (line-per-event,
  ;; adjacent data chunks concatenated on one line, control bytes < 0x20
  ;; and 0x7F hex-escaped, everything else -- including raw UTF-8 lead/
  ;; continuation bytes >= 0x80 -- passed through verbatim), then
  ;; compares byte-for-byte against the real *.out files. One
  ;; aggregating check, not one per fixture, since letloop's export
  ;; list is static; a failure names the specific fixture and shows
  ;; expected vs. actual.

  (define (read-file-bytes path)
    (call-with-port (open-file-input-port path)
      (lambda (port) (get-bytevector-all port))))

  (define (byte-escape-push! out b)
    ;; printf("\\x%02x", c) -- literal backslash, "x", two lowercase hex digits.
    (if (or (fx=? b #x7f) (fx<? b #x20))
      (let ((hex "0123456789abcdef"))
        (set! out (cons (char->integer (string-ref hex (fxand (fxsrl b 4) #xf)))
                         (cons (char->integer #\x)
                               (cons (char->integer #\\) out))))
        (cons (char->integer (string-ref hex (fxand b #xf))) out))
      (cons b out)))

  (define (string-bytes-escape-push! out s)
    (fold-left byte-escape-push! out (bytevector->u8-list (string->utf8 s))))

  (define (bytevector-escape-push! out bv)
    (fold-left byte-escape-push! out (bytevector->u8-list bv)))

  (define (ascii-push! out s)
    (fold-left (lambda (out c) (cons (char->integer c) out)) out (string->list s)))

  (define (fixture-render bytes)
    (let ((p (yxml-parser-make))
          (size (bytevector-length bytes))
          (out '())
          (indata #f)
          (errored? #f))
      (define (newline!) (set! out (cons (char->integer #\newline) out)))
      (let loop ((i 0))
        (if (or errored? (fx=? i size))
          (void)
          (let-values (((kind payload) (yxml-step! p (bytevector-u8-ref bytes i))))
            (case kind
              ((ok) (void))
              ((elem-start) (newline!) (set! out (ascii-push! out "elemstart ")) (set! out (string-bytes-escape-push! out payload)) (set! indata #f))
              ((elem-end) (newline!) (set! out (ascii-push! out "elemend")) (set! indata #f))
              ((attr-start) (newline!) (set! out (ascii-push! out "attrstart ")) (set! out (string-bytes-escape-push! out payload)) (set! indata #f))
              ((attr-end) (newline!) (set! out (ascii-push! out "attrend")) (set! indata #f))
              ((pi-start) (newline!) (set! out (ascii-push! out "pistart ")) (set! out (string-bytes-escape-push! out payload)) (set! indata #f))
              ((pi-end) (newline!) (set! out (ascii-push! out "piend")) (set! indata #f))
              ((content) (unless indata (newline!) (set! out (ascii-push! out "content "))) (set! out (bytevector-escape-push! out payload)) (set! indata #t))
              ((attr-val) (unless indata (newline!) (set! out (ascii-push! out "attrval "))) (set! out (bytevector-escape-push! out payload)) (set! indata #t))
              ((pi-content) (unless indata (newline!) (set! out (ascii-push! out "picontent "))) (set! out (bytevector-escape-push! out payload)) (set! indata #t))
              (else (newline!) (set! out (ascii-push! out "error\n")) (set! errored? #t)))
            (loop (fx+ i 1)))))
      (unless errored?
        (newline!)
        (set! out (ascii-push! out (if (yxml-eof? p) "ok\n" "error\n"))))
      (let* ((rev (reverse out)) (bv (make-bytevector (length rev))))
        (let fill ((i 0) (rest rev))
          (if (null? rest) bv (begin (bytevector-u8-set! bv i (car rest)) (fill (fx+ i 1) (cdr rest))))))))

  (define (~check-yxml-official-fixtures)
    (let* ((directory "submodules/yxml/test")
           ;; The corpus is a git submodule, and the path is relative to
           ;; the repository root, where `make check` runs. Without it
           ;; there is nothing to compare against.
           (entries (if (file-directory? directory)
                      (directory-list directory)
                      (begin
                        (format #t "** SKIP: no yxml test corpus at ~a (git submodule update --init)\n"
                                directory)
                        '())))
           (xml-files (filter (lambda (name) (string-suffix? ".xml" name)) entries)))
      (for-each
       (lambda (xml-name)
         (let* ((base (substring xml-name 0 (fx- (string-length xml-name) 4)))
                (out-name (string-append base ".out"))
                (xml-path (string-append directory "/" xml-name))
                (out-path (string-append directory "/" out-name)))
           (when (file-exists? out-path)
             (let* ((input (read-file-bytes xml-path))
                    (expected (read-file-bytes out-path))
                    (actual (fixture-render input)))
               (unless (bytevector=? actual expected)
                 (error '~check-yxml-official-fixtures
                        "fixture mismatch"
                        xml-name
                        (utf8->string actual)
                        (utf8->string expected)))))))
       xml-files)
      ;; letloop check treats a void/falsy return as FAILED regardless
      ;; of whether an assertion inside actually failed -- for-each
      ;; returns void, so this needs an explicit truthy tail.
      #t))

  (define (string-suffix? suffix string)
    (let ((sl (string-length suffix)) (l (string-length string)))
      (and (fx>=? l sl) (string=? suffix (substring string (fx- l sl) l)))))

  )

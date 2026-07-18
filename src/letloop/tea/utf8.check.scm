;; Checks for (letloop tea utf8), driving the module through its exported
;; API the way a caller would.  Included at the tail of the library;
;; discovered by `make check` via the ~check- exports.


  (define-syntax expect
    (syntax-rules ()
      ((_ a b)
       (let ((a* a) (b* b))
         (or (equal? a* b*)
             (begin (display (list 'expected b* 'got a*)) (newline) #f))))))

  (define (~check-utf8-encode-ascii)
    (expect (bytevector->u8-list (utf8-encode 65)) '(65)))

  (define (~check-utf8-encode-2byte)
    ;; é = U+00E9 -> 0xC3 0xA9
    (expect (bytevector->u8-list (utf8-encode #xE9)) '(#xC3 #xA9)))

  (define (~check-utf8-encode-3byte)
    ;; € = U+20AC -> 0xE2 0x82 0xAC
    (expect (bytevector->u8-list (utf8-encode #x20AC)) '(#xE2 #x82 #xAC)))

  (define (~check-utf8-encode-4byte)
    ;; 🎉 = U+1F389 -> 0xF0 0x9F 0x8E 0x89
    (expect (bytevector->u8-list (utf8-encode #x1F389)) '(#xF0 #x9F #x8E #x89)))

  (define (~check-utf8-encode-roundtrip)
    ;; encode then decode, every codepoint type
    (let ((d (make-utf8-decoder)))
      (define (round cp)
        (let* ((bv (utf8-encode cp))
               (n  (bytevector-length bv)))
          (let loop ((i 0))
            (let ((r (utf8-decoder-feed! d (bytevector-u8-ref bv i))))
              (cond
               ((fx=? i (fx- n 1)) r)
               ((eq? r 'incomplete) (loop (fx+ i 1)))
               (else r))))))
      (and (eqv? (round 65)      65)
           (eqv? (round #xE9)    #xE9)
           (eqv? (round #x20AC)  #x20AC)
           (eqv? (round #x1F389) #x1F389))))

  (define (~check-utf8-decode-ascii)
    (let ((d (make-utf8-decoder)))
      (and (eqv? (utf8-decoder-feed! d 65) 65)
           (eqv? (utf8-decoder-feed! d 66) 66))))

  (define (~check-utf8-decode-multibyte)
    (let ((d (make-utf8-decoder)))
      (and (eq? (utf8-decoder-feed! d #xC3) 'incomplete)
           (eqv? (utf8-decoder-feed! d #xA9) #xE9))))

  (define (~check-utf8-decode-byte-by-byte)
    ;; 4-byte sequence delivered one byte at a time
    (let ((d (make-utf8-decoder)))
      (and (eq? (utf8-decoder-feed! d #xF0) 'incomplete)
           (eq? (utf8-decoder-feed! d #x9F) 'incomplete)
           (eq? (utf8-decoder-feed! d #x8E) 'incomplete)
           (eqv? (utf8-decoder-feed! d #x89) #x1F389))))

  (define (~check-utf8-decode-rejects-overlong)
    ;; 0xC0 0x80 = overlong NUL — must be rejected
    (let ((d (make-utf8-decoder)))
      (and (eq? (utf8-decoder-feed! d #xC0) 'incomplete)
           (eq? (utf8-decoder-feed! d #x80) 'invalid))))

  (define (~check-utf8-decode-rejects-surrogate)
    ;; 0xED 0xA0 0x80 = U+D800, a surrogate
    (let ((d (make-utf8-decoder)))
      (and (eq? (utf8-decoder-feed! d #xED) 'incomplete)
           (eq? (utf8-decoder-feed! d #xA0) 'incomplete)
           (eq? (utf8-decoder-feed! d #x80) 'invalid))))

  (define (~check-utf8-decode-rejects-stray-continuation)
    (let ((d (make-utf8-decoder)))
      (eq? (utf8-decoder-feed! d #x80) 'invalid)))

  (define (~check-utf8-encode-rejects-surrogate)
    ;; D800..DFFF are not scalar values; the encoder must refuse them
    ;; instead of emitting bytes the decoder rejects.
    (and (guard (c (#t #t)) (utf8-encode #xD800) #f)
         (guard (c (#t #t)) (utf8-encode #xDFFF) #f)
         ;; boundary neighbours still encode
         (bytevector? (utf8-encode #xD7FF))
         (bytevector? (utf8-encode #xE000))))

  (define (~check-utf8-decode-redrives-broken-continuation)
    ;; #xC3 #x41: the sequence breaks on 'A', which was never part of it.
    ;; The decoder must signal invalid-redrive so the caller re-feeds the
    ;; byte — ending up with replacement + 'A', not just replacement.
    (let ((d (make-utf8-decoder)))
      (and (eq?  (utf8-decoder-feed! d #xC3) 'incomplete)
           (eq?  (utf8-decoder-feed! d #x41) 'invalid-redrive)
           (eqv? (utf8-decoder-feed! d #x41) 65))))

  (define (~check-utf8-decode-string-roundtrip)
    ;; Decode "Héllo €" byte-stream and rebuild the string of codepoints.
    (let* ((s   "Héllo €")
           (bv  (string->utf8 s))
           (d   (make-utf8-decoder)))
      (let loop ((i 0) (out '()))
        (cond
         ((fx=? i (bytevector-length bv))
          (let ((cps (reverse out)))
            (string=? (apply string (map integer->char cps)) s)))
         (else
          (let ((r (utf8-decoder-feed! d (bytevector-u8-ref bv i))))
            (cond
             ((eq? r 'incomplete) (loop (fx+ i 1) out))
             ((eq? r 'invalid)    #f)
             (else                (loop (fx+ i 1) (cons r out))))))))))

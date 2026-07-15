#!chezscheme
;; (letloop tea utf8) — UTF-8 codec.
;;
;; The encoder is functional: codepoint -> bytevector (1..4 bytes).  Useful
;; when writing to a byte port; for textual ports just (write-char (integer->
;; char cp) port), the port flush handles UTF-8.
;;
;; The decoder is stateful so input.scm can feed it one byte at a time as
;; bytes arrive in arbitrary chunks from read(2):
;;
;;   (define d (make-utf8-decoder))
;;   (utf8-decoder-feed! d byte)   ; -> codepoint | 'incomplete | 'invalid
;;
;; On 'invalid the decoder is automatically reset; on 'incomplete state
;; persists for the next byte.
(library (letloop tea utf8)
  (export
   utf8-encode
   utf8-encode!
   utf8-codepoint-length
   make-utf8-decoder
   utf8-decoder?
   utf8-decoder-feed!
   utf8-decoder-reset!

   ~check-utf8-encode-ascii
   ~check-utf8-encode-2byte
   ~check-utf8-encode-3byte
   ~check-utf8-encode-4byte
   ~check-utf8-encode-roundtrip
   ~check-utf8-decode-ascii
   ~check-utf8-decode-multibyte
   ~check-utf8-decode-byte-by-byte
   ~check-utf8-decode-rejects-overlong
   ~check-utf8-decode-rejects-surrogate
   ~check-utf8-decode-rejects-stray-continuation
   ~check-utf8-decode-string-roundtrip)
  (import (chezscheme))

  ;; ----- encoder -----------------------------------------------------------

  (define (utf8-codepoint-length cp)
    (cond
     ((fx<? cp #x80)     1)
     ((fx<? cp #x800)    2)
     ((fx<? cp #x10000)  3)
     ((fx<? cp #x110000) 4)
     (else (error 'utf8-codepoint-length "out of range" cp))))

  (define (utf8-encode! bv off cp)
    ;; Writes the encoding of cp into bv starting at off.  Returns the
    ;; number of bytes written.  Caller is responsible for ensuring at
    ;; least 4 bytes are available.
    (cond
     ((fx<? cp #x80)
      (bytevector-u8-set! bv off cp)
      1)
     ((fx<? cp #x800)
      (bytevector-u8-set! bv off       (fxior #xC0 (fxsrl cp 6)))
      (bytevector-u8-set! bv (fx+ off 1) (fxior #x80 (fxand cp #x3F)))
      2)
     ((fx<? cp #x10000)
      (bytevector-u8-set! bv off         (fxior #xE0 (fxsrl cp 12)))
      (bytevector-u8-set! bv (fx+ off 1) (fxior #x80 (fxand (fxsrl cp 6) #x3F)))
      (bytevector-u8-set! bv (fx+ off 2) (fxior #x80 (fxand cp #x3F)))
      3)
     ((fx<? cp #x110000)
      (bytevector-u8-set! bv off         (fxior #xF0 (fxsrl cp 18)))
      (bytevector-u8-set! bv (fx+ off 1) (fxior #x80 (fxand (fxsrl cp 12) #x3F)))
      (bytevector-u8-set! bv (fx+ off 2) (fxior #x80 (fxand (fxsrl cp 6)  #x3F)))
      (bytevector-u8-set! bv (fx+ off 3) (fxior #x80 (fxand cp #x3F)))
      4)
     (else (error 'utf8-encode! "out of range" cp))))

  (define (utf8-encode cp)
    (let* ((n  (utf8-codepoint-length cp))
           (bv (make-bytevector n)))
      (utf8-encode! bv 0 cp)
      bv))

  ;; ----- decoder -----------------------------------------------------------
  ;;
  ;; State:
  ;;   need     bytes still needed for the current codepoint (0 if idle)
  ;;   acc      accumulator with bits decoded so far
  ;;   minimum  smallest codepoint that this byte length would be valid for —
  ;;            used to reject overlong encodings (e.g. \xC0\x80 for NUL)

  (define-record-type utf8-decoder
    (fields (mutable need)
            (mutable acc)
            (mutable minimum))
    (protocol
     (lambda (new) (lambda () (new 0 0 0)))))

  (define (utf8-decoder-reset! d)
    (utf8-decoder-need-set!    d 0)
    (utf8-decoder-acc-set!     d 0)
    (utf8-decoder-minimum-set! d 0))

  (define (utf8-decoder-feed! d byte)
    (cond
     ((fx=? (utf8-decoder-need d) 0)
      ;; first byte of a sequence
      (cond
       ((fx<? byte #x80)
        ;; ASCII fast path
        byte)
       ((fx<? byte #xC0)
        ;; lone continuation byte
        (utf8-decoder-reset! d)
        'invalid)
       ((fx<? byte #xE0)
        (utf8-decoder-need-set!    d 1)
        (utf8-decoder-acc-set!     d (fxand byte #x1F))
        (utf8-decoder-minimum-set! d #x80)
        'incomplete)
       ((fx<? byte #xF0)
        (utf8-decoder-need-set!    d 2)
        (utf8-decoder-acc-set!     d (fxand byte #x0F))
        (utf8-decoder-minimum-set! d #x800)
        'incomplete)
       ((fx<? byte #xF8)
        (utf8-decoder-need-set!    d 3)
        (utf8-decoder-acc-set!     d (fxand byte #x07))
        (utf8-decoder-minimum-set! d #x10000)
        'incomplete)
       (else
        (utf8-decoder-reset! d)
        'invalid)))
     (else
      ;; continuation expected
      (cond
       ((not (fx=? (fxand byte #xC0) #x80))
        ;; not a continuation byte — drop and rewind so the caller can
        ;; redrive this byte as a fresh first byte.
        (utf8-decoder-reset! d)
        'invalid)
       (else
        (let ((acc* (fxior (fxsll (utf8-decoder-acc d) 6) (fxand byte #x3F)))
              (need* (fx- (utf8-decoder-need d) 1)))
          (utf8-decoder-acc-set!  d acc*)
          (utf8-decoder-need-set! d need*)
          (cond
           ((fx>? need* 0) 'incomplete)
           ((fx<? acc* (utf8-decoder-minimum d))
            ;; overlong encoding — reject
            (utf8-decoder-reset! d)
            'invalid)
           ((or (and (fx>=? acc* #xD800) (fx<? acc* #xE000))
                (fx>=? acc* #x110000))
            ;; surrogate or out-of-range — reject
            (utf8-decoder-reset! d)
            'invalid)
           (else
            (utf8-decoder-reset! d)
            acc*))))))))
  

  (include "letloop/tea/utf8.check.scm")
  )

;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop sha256)
  (export sha256
          sha256-hex
          hmac-sha256
          hmac-sha256-hex
          bytevector-hex-encode
          ~check-sha256-empty
          ~check-sha256-abc
          ~check-sha256-two-blocks
          ~check-sha256-million-a
          ~check-hmac-sha256-rfc4231-case-1
          ~check-hmac-sha256-rfc4231-case-2
          ~check-hmac-sha256-long-key)
  (import (chezscheme))

  ;; SHA-256 (FIPS 180-4) in pure Scheme. Words are 32-bit values held
  ;; in fixnums; every left shift masks its operand first so no
  ;; intermediate exceeds 2^32, well inside the 61-bit fixnum range.

  (define sha256-round-constants
    '#(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5
       #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
       #xd807aa98 #x12835b01 #x243185be #x550c7dc3
       #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
       #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc
       #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
       #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7
       #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
       #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
       #x650a7354 #x766a0abb #x81c2c92e #x92722c85
       #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3
       #xd192e819 #xd6990624 #xf40e3585 #x106aa070
       #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5
       #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
       #x748f82ee #x78a5636f #x84c87814 #x8cc70208
       #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

  (define (word32-truncate x)
    (fxand x #xFFFFFFFF))

  (define (word32-rotate-right x n)
    (fxior (fxarithmetic-shift-right x n)
           (fxarithmetic-shift-left
             (fxand x (fx- (fxarithmetic-shift-left 1 n) 1))
             (fx- 32 n))))

  (define (sha256-message-pad data)
    (let* ((length (bytevector-length data))
           (padded-length
             (let loop ((n (fx+ length 9)))
               (if (fxzero? (fxmod n 64)) n (loop (fx+ n 1)))))
           (padded (make-bytevector padded-length 0)))
      (bytevector-copy! data 0 padded 0 length)
      (bytevector-u8-set! padded length #x80)
      ;; 64-bit big-endian bit count; generic arithmetic because the
      ;; bit count of a very large input can exceed the fixnum range
      (let loop ((i 0) (value (* length 8)))
        (when (fx< i 8)
          (bytevector-u8-set! padded (fx- padded-length 1 i)
                              (bitwise-and value #xFF))
          (loop (fx+ i 1) (bitwise-arithmetic-shift-right value 8))))
      padded))

  (define (sha256 data)
    (let ((padded (sha256-message-pad data))
          (schedule (make-vector 64 0))
          (state (vector #x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
                         #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19)))
      (do ((block 0 (fx+ block 64)))
        ((fx>= block (bytevector-length padded)))
        (do ((t 0 (fx+ t 1)))
          ((fx= t 16))
          (let ((base (fx+ block (fx* t 4))))
            (vector-set! schedule t
                         (fxior
                           (fxarithmetic-shift-left
                             (bytevector-u8-ref padded base) 24)
                           (fxarithmetic-shift-left
                             (bytevector-u8-ref padded (fx+ base 1)) 16)
                           (fxarithmetic-shift-left
                             (bytevector-u8-ref padded (fx+ base 2)) 8)
                           (bytevector-u8-ref padded (fx+ base 3))))))
        (do ((t 16 (fx+ t 1)))
          ((fx= t 64))
          (let* ((w2 (vector-ref schedule (fx- t 2)))
                 (w15 (vector-ref schedule (fx- t 15)))
                 (sigma1 (fxxor (word32-rotate-right w2 17)
                                (word32-rotate-right w2 19)
                                (fxarithmetic-shift-right w2 10)))
                 (sigma0 (fxxor (word32-rotate-right w15 7)
                                (word32-rotate-right w15 18)
                                (fxarithmetic-shift-right w15 3))))
            (vector-set! schedule t
                         (word32-truncate
                           (fx+ sigma1
                                (vector-ref schedule (fx- t 7))
                                sigma0
                                (vector-ref schedule (fx- t 16)))))))
        (let loop ((t 0)
                   (a (vector-ref state 0)) (b (vector-ref state 1))
                   (c (vector-ref state 2)) (d (vector-ref state 3))
                   (e (vector-ref state 4)) (f (vector-ref state 5))
                   (g (vector-ref state 6)) (h (vector-ref state 7)))
          (if (fx= t 64)
            (begin
              (vector-set! state 0 (word32-truncate (fx+ (vector-ref state 0) a)))
              (vector-set! state 1 (word32-truncate (fx+ (vector-ref state 1) b)))
              (vector-set! state 2 (word32-truncate (fx+ (vector-ref state 2) c)))
              (vector-set! state 3 (word32-truncate (fx+ (vector-ref state 3) d)))
              (vector-set! state 4 (word32-truncate (fx+ (vector-ref state 4) e)))
              (vector-set! state 5 (word32-truncate (fx+ (vector-ref state 5) f)))
              (vector-set! state 6 (word32-truncate (fx+ (vector-ref state 6) g)))
              (vector-set! state 7 (word32-truncate (fx+ (vector-ref state 7) h))))
            (let* ((big-sigma1 (fxxor (word32-rotate-right e 6)
                                      (word32-rotate-right e 11)
                                      (word32-rotate-right e 25)))
                   (choose (fxxor (fxand e f)
                                  (fxand (word32-truncate (fxnot e)) g)))
                   (temp1 (word32-truncate
                            (fx+ (word32-truncate
                                   (fx+ h big-sigma1 choose))
                                 (vector-ref sha256-round-constants t)
                                 (vector-ref schedule t))))
                   (big-sigma0 (fxxor (word32-rotate-right a 2)
                                      (word32-rotate-right a 13)
                                      (word32-rotate-right a 22)))
                   (majority (fxxor (fxand a b) (fxand a c) (fxand b c)))
                   (temp2 (word32-truncate (fx+ big-sigma0 majority))))
              (loop (fx+ t 1)
                    (word32-truncate (fx+ temp1 temp2)) a b c
                    (word32-truncate (fx+ d temp1)) e f g)))))
      (let ((digest (make-bytevector 32)))
        (do ((i 0 (fx+ i 1)))
          ((fx= i 8) digest)
          (let ((word (vector-ref state i)))
            (bytevector-u8-set! digest (fx* i 4)
                                (fxarithmetic-shift-right word 24))
            (bytevector-u8-set! digest (fx+ (fx* i 4) 1)
                                (fxand (fxarithmetic-shift-right word 16) #xFF))
            (bytevector-u8-set! digest (fx+ (fx* i 4) 2)
                                (fxand (fxarithmetic-shift-right word 8) #xFF))
            (bytevector-u8-set! digest (fx+ (fx* i 4) 3)
                                (fxand word #xFF)))))))

  ;; ---- Hex ----

  (define bytevector-hex-characters "0123456789abcdef")

  (define (bytevector-hex-encode data)
    (let* ((length (bytevector-length data))
           (out (make-string (fx* length 2))))
      (do ((i 0 (fx+ i 1)))
        ((fx= i length) out)
        (let ((byte (bytevector-u8-ref data i)))
          (string-set! out (fx* i 2)
                       (string-ref bytevector-hex-characters
                                   (fxarithmetic-shift-right byte 4)))
          (string-set! out (fx+ (fx* i 2) 1)
                       (string-ref bytevector-hex-characters
                                   (fxand byte #xF)))))))

  (define (sha256-hex data)
    (bytevector-hex-encode (sha256 data)))

  ;; ---- HMAC-SHA256 (RFC 2104) ----

  (define (bytevector-concatenate left right)
    (let* ((left-length (bytevector-length left))
           (right-length (bytevector-length right))
           (out (make-bytevector (fx+ left-length right-length))))
      (bytevector-copy! left 0 out 0 left-length)
      (bytevector-copy! right 0 out left-length right-length)
      out))

  (define (hmac-sha256 key data)
    (let* ((key (if (fx> (bytevector-length key) 64) (sha256 key) key))
           (inner (make-bytevector 64 #x36))
           (outer (make-bytevector 64 #x5c)))
      (do ((i 0 (fx+ i 1)))
        ((fx= i (bytevector-length key)))
        (let ((byte (bytevector-u8-ref key i)))
          (bytevector-u8-set! inner i (fxxor #x36 byte))
          (bytevector-u8-set! outer i (fxxor #x5c byte))))
      (sha256 (bytevector-concatenate
                outer
                (sha256 (bytevector-concatenate inner data))))))

  (define (hmac-sha256-hex key data)
    (bytevector-hex-encode (hmac-sha256 key data)))

  (include "letloop/sha256.check.scm"))

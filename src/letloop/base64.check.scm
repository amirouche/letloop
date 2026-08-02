;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>

;; RFC 4648 test vectors.
(define ~check-base64-000
  (lambda ()
    (define (encodes? input expected)
      (string=? (utf8->string (base64-encode (string->utf8 input))) expected))
    (check #t (and (encodes? "" "")
                   (encodes? "f" "Zg==")
                   (encodes? "fo" "Zm8=")
                   (encodes? "foo" "Zm9v")
                   (encodes? "foob" "Zm9vYg==")
                   (encodes? "fooba" "Zm9vYmE=")
                   (encodes? "foobar" "Zm9vYmFy")
                   (encodes? "Man" "TWFu")))))

;; Every input size 0..4096 with pseudo-random bytes: the public path
;; (jit when available) must agree byte-for-byte with the scalar
;; reference — the same gate b64simd.c ran on its C kernels.
(define ~check-base64-001
  (lambda ()
    (let ((source (make-bytevector 4096)))
      (let fill ((i 0) (state #x2545f491))
        (unless (fx=? i 4096)
          (let ((state (bitwise-and (+ (* state 1664525) 1013904223)
                                    #xFFFFFFFF)))
            (bytevector-u8-set! source i
                                (bitwise-arithmetic-shift-right state 24))
            (fill (fx+ i 1) state))))
      (check #t
             (let sizes ((n 0))
               (cond
                ((fx>? n 4096)
                 (or (base64-jit?)
                     (begin (display "base64 check: no AVX2, scalar only\n")
                            #t)))
                (else
                 (let* ((input (let ((b (make-bytevector n)))
                                 (bytevector-copy! source 0 b 0 n)
                                 b))
                        (out-length (fx* 4 (fxdiv (fx+ n 2) 3)))
                        (jit (base64-encode input))
                        (scalar (%base64-scalar!
                                 input n (make-bytevector out-length) 0 0)))
                   (if (bytevector=? jit scalar)
                       (sizes (fx+ n 1))
                       (begin
                         (format #t "base64 mismatch at n=~a~%" n)
                         #f))))))))))

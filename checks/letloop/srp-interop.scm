(library (srp-interop)
  (export main)
  (import (chezscheme)
          (letloop srp)
          (letloop sodium)
          (letloop bytevector))

  ;; Hex conversion utilities

  (define hex->bytevector
    (lambda (str)
      (define clean
        (list->string
         (filter (lambda (c) (not (char=? c #\space)))
                 (string->list str))))
      (define len (div (string-length clean) 2))
      (define out (make-bytevector len))
      (let loop ((i 0))
        (when (< i len)
          (bytevector-u8-set! out i
            (string->number (substring clean (* i 2) (+ (* i 2) 2)) 16))
          (loop (+ i 1))))
      out))

  (define bytevector->hex
    (lambda (bv)
      (define hex-chars "0123456789abcdef")
      (define len (bytevector-length bv))
      (define out (make-string (* len 2)))
      (do ((i 0 (fx+ i 1)))
        ((fx= i len) out)
        (let ((b (bytevector-u8-ref bv i)))
          (string-set! out (fx* i 2)
                       (string-ref hex-chars (fxsrl b 4)))
          (string-set! out (fx+ (fx* i 2) 1)
                       (string-ref hex-chars (fxand b #xf)))))))

  ;; Deterministic secret derivation using SHA-256 counter mode.
  ;; Must match the Python derive_secret() exactly.

  (define integer->counter-bytes
    (lambda (i)
      (let ((bv (make-bytevector 4 0)))
        (bytevector-u8-set! bv 0 (fxand (fxsrl i 24) #xff))
        (bytevector-u8-set! bv 1 (fxand (fxsrl i 16) #xff))
        (bytevector-u8-set! bv 2 (fxand (fxsrl i 8) #xff))
        (bytevector-u8-set! bv 3 (fxand i #xff))
        bv)))

  (define derive-secret
    (lambda (seed length)
      (let loop ((out #vu8()) (i 0))
        (if (fx>= (bytevector-length out) length)
            (let ((result (make-bytevector length)))
              (bytevector-copy! out 0 result 0 length)
              result)
            (loop (bytevector-append
                   out
                   (crypto-hash-sha256
                    (bytevector-append seed (integer->counter-bytes i))))
                  (fx+ i 1))))))

  (define emit
    (lambda (key value)
      (display key)
      (display "=")
      (display (bytevector->hex value))
      (newline)))

  (define main
    (lambda args
      (define _init (sodium-init))

      ;; Fixed test inputs (must match Python script exactly)
      (define salt (hex->bytevector "BEB25379D1A8581EB5A727673A2441EE"))
      (define identity (string->utf8 "alice"))
      (define password (string->utf8 "password123"))
      (define a-secret (derive-secret (string->utf8 "srp-test-client-secret") 256))
      (define b-secret (derive-secret (string->utf8 "srp-test-server-secret") 256))

      ;; Compute verifier
      (define verifier (make-srp-client-verifier PARAMETER-2048
                                                 salt identity password))

      ;; Create client and server with fixed secrets
      (define client (make-srp-client PARAMETER-2048 a-secret
                                      salt identity password))
      (define server (make-srp-server PARAMETER-2048 b-secret
                                      salt identity verifier))

      ;; Protocol exchange
      (define A (srp-client-A client))
      (define _s1 (srp-server-A! server A))
      (define B (srp-server-B server))
      (define _s2 (srp-client-B! client B))

      ;; Internal consistency checks
      (define _c1 (assert (equal? (srp-client-K client) (srp-server-K server))))
      (define _c2 (assert (srp-server-check-M1? server (srp-client-M1 client))))
      (define _c3 (assert (srp-client-check-M2? client (srp-server-M2 server))))

      ;; Output values for cross-implementation comparison
      (emit "verifier" verifier)
      (emit "A" A)
      (emit "B" B)
      (emit "K" (srp-client-K client))
      (emit "M1" (srp-client-M1 client))
      (emit "M2" (srp-server-M2 server))))

)

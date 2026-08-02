;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop base64) — base64 encoding with an AVX2 fast path
;; assembled in-image by (letloop asm): the Muła/Lemire reshuffle +
;; translate technique of b64simd.c (invvv apps/letloop), no C
;; toolchain involved. The jit kernel consumes whole 24-byte blocks
;; (32 output characters each); the tail and the padding stay in the
;; scalar Scheme encoder, and machines without AVX2 take the scalar
;; path for everything. Output is byte-identical either way.

(define %base64-alphabet
  (string->utf8
   "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))

(define %base64-pad 61)                 ; #\=

(define %base64-scalar!
  ;; Encode BV[i0 .. n-1] into OUT starting at o0. Assumes i0 is a
  ;; multiple of 3 and OUT has room for the whole encoding.
  (lambda (bv n out i0 o0)
    (let next ((i i0) (o o0))
      (if (fx>=? i n)
          out
          (let* ((b0 (bytevector-u8-ref bv i))
                 (have1 (fx<? (fx+ i 1) n))
                 (have2 (fx<? (fx+ i 2) n))
                 (b1 (if have1 (bytevector-u8-ref bv (fx+ i 1)) 0))
                 (b2 (if have2 (bytevector-u8-ref bv (fx+ i 2)) 0))
                 (v (fx+ (fx* b0 65536) (fx* b1 256) b2)))
            (bytevector-u8-set! out o
              (bytevector-u8-ref %base64-alphabet
                                 (fxand (fxarithmetic-shift-right v 18) 63)))
            (bytevector-u8-set! out (fx+ o 1)
              (bytevector-u8-ref %base64-alphabet
                                 (fxand (fxarithmetic-shift-right v 12) 63)))
            (bytevector-u8-set! out (fx+ o 2)
              (if have1
                  (bytevector-u8-ref %base64-alphabet
                                     (fxand (fxarithmetic-shift-right v 6) 63))
                  %base64-pad))
            (bytevector-u8-set! out (fx+ o 3)
              (if have2
                  (bytevector-u8-ref %base64-alphabet (fxand v 63))
                  %base64-pad))
            (next (fx+ i 3) (fx+ o 4)))))))

;; Constant block handed to the kernel as its fourth argument, so the
;; code needs no RIP-relative addressing. Layout, 32 bytes each:
;;   +0   per-lane shuffle putting the 12 input bytes in output order
;;   +32  0x0fc0fc00  mask: high sextet pair of each 32-bit group
;;   +64  0x04000040  mulhi factors moving those into place
;;   +96  0x003f03f0  mask: low sextet pair
;;   +128 0x01000010  mullo factors
;;   +160 offset LUT for sextet -> ASCII (indexed by saturated class)
;;   +192 51 x32      saturation threshold
;;   +224 25 x32      'Z' class boundary
(define %base64-constants
  (let ((c (make-bytevector 256 0)))
    (define (fill-bytes! offset bytes)
      (let loop ((i 0) (bytes bytes))
        (unless (null? bytes)
          (bytevector-u8-set! c (fx+ offset i) (car bytes))
          (loop (fx+ i 1) (cdr bytes)))))
    (define (fill-u32! offset value)
      (do ((i 0 (fx+ i 4))) ((fx=? i 32))
        (bytevector-u32-set! c (fx+ offset i) value (endianness little))))
    (define shuffle '(1 0 2 1 4 3 5 4 7 6 8 7 10 9 11 10))
    (define lut '(65 71 252 252 252 252 252 252 252 252 252 252 237 240 0 0))
    (fill-bytes! 0 shuffle)
    (fill-bytes! 16 shuffle)
    (fill-u32! 32 #x0fc0fc00)
    (fill-u32! 64 #x04000040)
    (fill-u32! 96 #x003f03f0)
    (fill-u32! 128 #x01000010)
    (fill-bytes! 160 lut)
    (fill-bytes! 176 lut)
    (do ((i 0 (fx+ i 1))) ((fx=? i 32))
      (bytevector-u8-set! c (fx+ 192 i) 51)
      (bytevector-u8-set! c (fx+ 224 i) 25))
    c))

(define %base64-avx2?
  ;; Linux-only detection, like everything mmap here.
  (guard (ex (else #f))
    (call-with-input-file "/proc/cpuinfo"
      (lambda (port)
        (let loop ()
          (let ((line (get-line port)))
            (cond ((eof-object? line) #f)
                  ((let ((n (string-length line)))
                     (let scan ((i 0))
                       (and (fx<=? (fx+ i 4) n)
                            (or (string=? (substring line i (fx+ i 4)) "avx2")
                                (scan (fx+ i 1))))))
                   #t)
                  (else (loop)))))))))

;; encode_blocks(src rdi, k rsi, dst rdx, constants rcx): consume K
;; whole 24-byte blocks, write 32 characters each. Per 128-bit lane:
;; shuffle 12 input bytes into four 6-bit groups per 32-bit word,
;; then map sextets to ASCII with saturating-subtract + pshufb.
(define %base64-kernel-code
  '((vmovdqu ymm8 (& rcx 0))            ; shuffle
    (vmovdqu ymm9 (& rcx 32))           ; 0x0fc0fc00
    (vmovdqu ymm10 (& rcx 64))          ; 0x04000040
    (vmovdqu ymm11 (& rcx 96))          ; 0x003f03f0
    (vmovdqu ymm12 (& rcx 128))         ; 0x01000010
    (vmovdqu ymm13 (& rcx 160))         ; LUT
    (vmovdqu ymm14 (& rcx 192))         ; 51s
    (vmovdqu ymm15 (& rcx 224))         ; 25s
    (test rsi rsi)
    (je done)
    (label loop)
    ;; lanes: 16 bytes at src and at src+12 (12 consumed each)
    (vmovdqu xmm0 (& rdi))
    (vinserti128 ymm0 ymm0 (& rdi 12) 1)
    ;; reshuffle
    (vpshufb ymm0 ymm0 ymm8)
    (vpand ymm1 ymm0 ymm9)              ; t0
    (vpmulhuw ymm1 ymm1 ymm10)          ; t1
    (vpand ymm2 ymm0 ymm11)             ; t2
    (vpmullw ymm2 ymm2 ymm12)           ; t3
    (vpor ymm0 ymm1 ymm2)               ; sextets
    ;; translate
    (vpsubusb ymm1 ymm0 ymm14)          ; saturated class
    (vpcmpgtb ymm2 ymm0 ymm15)          ; > 25
    (vpsubb ymm1 ymm1 ymm2)
    (vpshufb ymm3 ymm13 ymm1)           ; per-class ASCII offset
    (vpaddb ymm0 ymm0 ymm3)
    (vmovdqu (& rdx) ymm0)
    (add rdi 24)
    (add rdx 32)
    (sub rsi 1)
    (jne loop)
    (label done)
    (vzeroupper)
    (ret)))

(define %base64-kernel
  (guard (ex (else #f))
    (assembly->procedure (sexp->assembly %base64-kernel-code)
      (u8* unsigned-64 u8* u8*)
      void)))

(define base64-jit?
  (lambda ()
    (and %base64-avx2? (and %base64-kernel #t))))

(define base64-encode!
  ;; Encode BV[0 .. n-1] into OUT, which must have room for
  ;; 4 * ceil(n / 3) bytes. Returns OUT.
  (lambda (bv n out)
    (if (and %base64-avx2? %base64-kernel (fx>=? n 28))
        ;; the kernel's paired loads read 4 bytes past the 24 consumed,
        ;; so keep the last block for the scalar tail (same bound as C)
        (let ((k (fxdiv (fx- n 4) 24)))
          (%base64-kernel bv k out %base64-constants)
          (%base64-scalar! bv n out (fx* k 24) (fx* k 32)))
        (%base64-scalar! bv n out 0 0))))

(define base64-encode
  (lambda (bv)
    (let ((n (bytevector-length bv)))
      (base64-encode! bv n (make-bytevector (fx* 4 (fxdiv (fx+ n 2) 3)))))))

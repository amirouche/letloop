;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop xxhash64)
  (export xxhash64
          xxhash64-hex
          ~check-xxhash64-empty
          ~check-xxhash64-short
          ~check-xxhash64-boundary-31-32-33
          ~check-xxhash64-long
          ~check-xxhash64-phrases
          ~check-xxhash64-assembly-agrees-with-scheme)
  (import (chezscheme)
          (letloop asm))

  ;; xxHash64 (non-cryptographic), seed 0, in pure Scheme. It agrees
  ;; bit-for-bit with Python's xxhash.xxh64(text).intdigest(), so a
  ;; value hashed there can be looked up here.
  ;; Algorithm per the xxHash spec; verified below against vectors
  ;; generated with the reference `xxhash` Python package.

  (define prime64-1 #x9E3779B185EBCA87)
  (define prime64-2 #xC2B2AE3D27D4EB4F)
  (define prime64-3 #x165667B19E3779F9)
  (define prime64-4 #x85EBCA77C2B2AE63)
  (define prime64-5 #x27D4EB2F165667C5)
  (define word64-mask #xFFFFFFFFFFFFFFFF)

  (define (word64-truncate x)
    (bitwise-and x word64-mask))

  (define (word64-rotate-left x n)
    (word64-truncate
      (bitwise-ior (bitwise-arithmetic-shift x n) (bitwise-arithmetic-shift x (- n 64)))))

  (define (bytevector-u64-ref-le bv offset)
    (let loop ((i 7) (value 0))
      (if (< i 0)
        value
        (loop (- i 1) (+ (bitwise-arithmetic-shift value 8)
                         (bytevector-u8-ref bv (+ offset i)))))))

  (define (bytevector-u32-ref-le bv offset)
    (let loop ((i 3) (value 0))
      (if (< i 0)
        value
        (loop (- i 1) (+ (bitwise-arithmetic-shift value 8)
                         (bytevector-u8-ref bv (+ offset i)))))))

  (define (xxhash64-round accumulator input)
    (word64-truncate
      (* (word64-rotate-left
           (word64-truncate (+ accumulator (word64-truncate (* input prime64-2))))
           31)
         prime64-1)))

  (define (xxhash64-merge-round accumulator value)
    (let* ((value (xxhash64-round 0 value))
           (accumulator (bitwise-xor accumulator value)))
      (word64-truncate (+ (word64-truncate (* accumulator prime64-1)) prime64-4))))

  (define (xxhash64-avalanche h64)
    (let* ((h64 (bitwise-xor h64 (bitwise-arithmetic-shift h64 -33)))
           (h64 (word64-truncate (* h64 prime64-2)))
           (h64 (bitwise-xor h64 (bitwise-arithmetic-shift h64 -29)))
           (h64 (word64-truncate (* h64 prime64-3)))
           (h64 (bitwise-xor h64 (bitwise-arithmetic-shift h64 -32))))
      h64))

  (define (xxhash64-block-loop data length)
    ;; Consume 32-byte blocks; returns (values h64 position) with
    ;; position at the first unconsumed byte.
    (let loop ((v1 (word64-truncate (+ prime64-1 prime64-2)))
               (v2 prime64-2)
               (v3 0)
               (v4 (word64-truncate (- prime64-1)))
               (position 0))
      (if (<= (+ position 32) length)
        (loop (xxhash64-round v1 (bytevector-u64-ref-le data position))
              (xxhash64-round v2 (bytevector-u64-ref-le data (+ position 8)))
              (xxhash64-round v3 (bytevector-u64-ref-le data (+ position 16)))
              (xxhash64-round v4 (bytevector-u64-ref-le data (+ position 24)))
              (+ position 32))
        (let* ((h64 (word64-truncate
                      (+ (word64-rotate-left v1 1)
                         (word64-rotate-left v2 7)
                         (word64-rotate-left v3 12)
                         (word64-rotate-left v4 18))))
               (h64 (xxhash64-merge-round h64 v1))
               (h64 (xxhash64-merge-round h64 v2))
               (h64 (xxhash64-merge-round h64 v3))
               (h64 (xxhash64-merge-round h64 v4)))
          (values h64 position)))))

  (define (xxhash64-tail h64 data length position)
    (cond
      ((<= (+ position 8) length)
       (let* ((k1 (xxhash64-round 0 (bytevector-u64-ref-le data position)))
              (h64 (bitwise-xor h64 k1))
              (h64 (word64-truncate
                     (+ (word64-truncate (* (word64-rotate-left h64 27) prime64-1))
                        prime64-4))))
         (xxhash64-tail h64 data length (+ position 8))))
      ((<= (+ position 4) length)
       (let* ((h64 (bitwise-xor
                     h64 (word64-truncate
                           (* (bytevector-u32-ref-le data position) prime64-1))))
              (h64 (word64-truncate
                     (+ (word64-truncate (* (word64-rotate-left h64 23) prime64-2))
                        prime64-3))))
         (xxhash64-tail h64 data length (+ position 4))))
      ((< position length)
       (let* ((h64 (bitwise-xor
                     h64 (word64-truncate
                           (* (bytevector-u8-ref data position) prime64-5))))
              (h64 (word64-truncate (* (word64-rotate-left h64 11) prime64-1))))
         (xxhash64-tail h64 data length (+ position 1))))
      (else (xxhash64-avalanche h64))))

  (define (xxhash64-scheme data)
    (let ((length (bytevector-length data)))
      (let-values (((h64 position)
                    (if (>= length 32)
                      (xxhash64-block-loop data length)
                      (values (word64-truncate prime64-5) 0))))
        (xxhash64-tail (word64-truncate (+ h64 length)) data length position))))

  ;; JIT-assembled accelerator via (letloop asm) -- no C toolchain, no
  ;; shared object to build or ship: the sexp assembler maps the
  ;; machine code into the running image at library load. Every 64-bit
  ;; multiply in the Scheme path above is a bignum operation under
  ;; Chez's 61-bit fixnums, which became a measured cost once bloom
  ;; filters started hashing every point-lookup key.
  ;; This is the same XXH64 algorithm instruction for instruction --
  ;; the check vectors below exercise whichever path is live, and
  ;; ~check-xxhash64-assembly-agrees-with-scheme compares the two
  ;; directly over every length class, so which path answered is
  ;; unobservable. The kernel honours the leaf-FFI contract: no
  ;; allocation, no calls back into Scheme, arguments are a byte span
  ;; and its length, result in rax.
  ;;
  ;; Register plan: rdi = cursor, rsi = length, rdx = end, rcx =
  ;; limit/scratch, rbx = scratch (callee-saved, pushed), rax = h64,
  ;; r8-r11 = v1-v4, r12 = PRIME64-1, r13 = PRIME64-2 (callee-saved,
  ;; pushed). rotl(x,n) is the 3-op shl/shr/or idiom; the other
  ;; primes are movabs'd into scratch at their use sites.
  (define _xxhash64-assembly-program
    '((push rbx) (push r12) (push r13)
      (mov r12 #x9E3779B185EBCA87)      ; PRIME64-1
      (mov r13 #xC2B2AE3D27D4EB4F)      ; PRIME64-2
      (lea rdx (& rdi rsi 1))           ; end = data + length
      (cmp rsi 32)
      (jb small)
      (lea rcx (& rdx -32))             ; limit = end - 32
      (mov r8 r12) (add r8 r13)         ; v1 = P1 + P2
      (mov r9 r13)                      ; v2 = P2
      (xor r10 r10)                     ; v3 = 0
      (xor r11 r11) (sub r11 r12)       ; v4 = 0 - P1
      (label block)                     ; round v, [p+k] for v1..v4
      (mov rbx (& rdi)) (imul rbx r13) (add r8 rbx)
      (mov rbx r8) (shl r8 31) (shr rbx 33) (or r8 rbx) (imul r8 r12)
      (mov rbx (& rdi 8)) (imul rbx r13) (add r9 rbx)
      (mov rbx r9) (shl r9 31) (shr rbx 33) (or r9 rbx) (imul r9 r12)
      (mov rbx (& rdi 16)) (imul rbx r13) (add r10 rbx)
      (mov rbx r10) (shl r10 31) (shr rbx 33) (or r10 rbx) (imul r10 r12)
      (mov rbx (& rdi 24)) (imul rbx r13) (add r11 rbx)
      (mov rbx r11) (shl r11 31) (shr rbx 33) (or r11 rbx) (imul r11 r12)
      (add rdi 32)
      (cmp rdi rcx) (jbe block)
      ;; h64 = rotl(v1,1) + rotl(v2,7) + rotl(v3,12) + rotl(v4,18)
      (mov rax r8) (mov rbx r8) (shl rax 1) (shr rbx 63) (or rax rbx)
      (mov rcx r9) (mov rbx r9) (shl rcx 7) (shr rbx 57) (or rcx rbx) (add rax rcx)
      (mov rcx r10) (mov rbx r10) (shl rcx 12) (shr rbx 52) (or rcx rbx) (add rax rcx)
      (mov rcx r11) (mov rbx r11) (shl rcx 18) (shr rbx 46) (or rcx rbx) (add rax rcx)
      ;; merge round x4: v = rotl(v*P2, 31)*P1; h ^= v; h = h*P1 + P4
      (imul r8 r13) (mov rbx r8) (shl r8 31) (shr rbx 33) (or r8 rbx) (imul r8 r12)
      (xor rax r8) (imul rax r12) (mov rbx #x85EBCA77C2B2AE63) (add rax rbx)
      (imul r9 r13) (mov rbx r9) (shl r9 31) (shr rbx 33) (or r9 rbx) (imul r9 r12)
      (xor rax r9) (imul rax r12) (mov rbx #x85EBCA77C2B2AE63) (add rax rbx)
      (imul r10 r13) (mov rbx r10) (shl r10 31) (shr rbx 33) (or r10 rbx) (imul r10 r12)
      (xor rax r10) (imul rax r12) (mov rbx #x85EBCA77C2B2AE63) (add rax rbx)
      (imul r11 r13) (mov rbx r11) (shl r11 31) (shr rbx 33) (or r11 rbx) (imul r11 r12)
      (xor rax r11) (imul rax r12) (mov rbx #x85EBCA77C2B2AE63) (add rax rbx)
      (jmp lenadd)
      (label small)
      (mov rax #x27D4EB2F165667C5)      ; PRIME64-5
      (label lenadd)
      (add rax rsi)                     ; h64 += length
      (label tail8)                     ; while p + 8 <= end
      (lea rbx (& rdi 8)) (cmp rbx rdx) (ja tail4)
      (mov rbx (& rdi)) (imul rbx r13)  ; k1 = round(0, [p])
      (mov rcx rbx) (shl rbx 31) (shr rcx 33) (or rbx rcx) (imul rbx r12)
      (xor rax rbx)
      (mov rbx rax) (shl rax 27) (shr rbx 37) (or rax rbx) (imul rax r12)
      (mov rbx #x85EBCA77C2B2AE63) (add rax rbx)
      (add rdi 8) (jmp tail8)
      (label tail4)                     ; one u32 if p + 4 <= end
      (lea rbx (& rdi 4)) (cmp rbx rdx) (ja tail1)
      (mov ecx (& rdi))                 ; zero-extending 32-bit load
      (imul rcx r12)
      (xor rax rcx)
      (mov rbx rax) (shl rax 23) (shr rbx 41) (or rax rbx) (imul rax r13)
      (mov rbx #x165667B19E3779F9) (add rax rbx)
      (add rdi 4)
      (label tail1)                     ; remaining bytes one at a time
      (cmp rdi rdx) (jae avalanche)
      (movzx rbx (& rdi))
      (mov rcx #x27D4EB2F165667C5) (imul rbx rcx)
      (xor rax rbx)
      (mov rbx rax) (shl rax 11) (shr rbx 53) (or rax rbx) (imul rax r12)
      (add rdi 1) (jmp tail1)
      (label avalanche)
      (mov rbx rax) (shr rbx 33) (xor rax rbx)
      (imul rax r13)
      (mov rbx rax) (shr rbx 29) (xor rax rbx)
      (mov rcx #x165667B19E3779F9) (imul rax rcx)
      (mov rbx rax) (shr rbx 32) (xor rax rbx)
      (pop r13) (pop r12) (pop rbx)
      (ret)))

  ;; #f (pure-Scheme fallback) if assembling or mapping fails for any
  ;; reason -- same graceful-degradation contract as every optional
  ;; accelerator in this codebase.
  (define _xxhash64-native
    (guard (ex (else #f))
      (assembly->procedure (sexp->assembly _xxhash64-assembly-program)
                           (u8* size_t) unsigned-64)))

  (define (xxhash64 data)
    ;; DATA is a bytevector; seed is fixed at 0. Returns an exact
    ;; non-negative integer in [0, 2^64).
    (if _xxhash64-native
      (_xxhash64-native data (bytevector-length data))
      (xxhash64-scheme data)))

  (define (xxhash64-hex data)
    (number->string (xxhash64 data) 16))

  (include "letloop/xxhash64.check.scm"))

;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop crc32)
  (export crc32
          crc32-update
          crc32-bytevector-compute
          ~check-crc32-empty
          ~check-crc32-known-value
          ~check-crc32-single-byte
          ~check-crc32-incremental
          ~check-crc32-assembly-agrees-with-scheme)
  (import (chezscheme)
          (letloop asm))

  ;; CRC32 lookup table, polynomial #xEDB88320
  (define crc32-table
    (let ((table (make-vector 256)))
      (do ((i 0 (fx+ i 1)))
        ((fx= i 256) table)
        (let ((crc i))
          (do ((j 0 (fx+ j 1)))
            ((fx= j 8)
             (vector-set! table i crc))
            (if (fx= (fxand crc 1) 1)
              (set! crc (fxxor (fxarithmetic-shift-right crc 1)
                               #xEDB88320))
              (set! crc (fxarithmetic-shift-right crc 1))))))))

  (define crc32-update
    (lambda (crc byte)
      (fxxor (fxarithmetic-shift-right crc 8)
             (vector-ref crc32-table (fxand (fxxor crc byte) #xFF)))))

  (define crc32-bytevector-scheme
    (lambda (bytevector start end)
      (let loop ((i start) (crc #xFFFFFFFF))
        (if (fx>= i end)
          (fxand (fxxor crc #xFFFFFFFF) #xFFFFFFFF)
          (loop (fx+ i 1)
                (crc32-update crc (bytevector-u8-ref bytevector i)))))))

  ;; ---- JIT-assembled slicing-by-8 ----
  ;;
  ;; The byte-at-a-time loop above measures ~394MB/s, which is the
  ;; bottleneck for a caller that checksums gigabytes. Slicing-by-8
  ;; (standard zlib technique): eight derived 256-entry tables let one
  ;; iteration consume 8 bytes -- two 32-bit loads, eight table
  ;; lookups, seven xors -- with the byte loop kept for the tail and
  ;; as the fallback. Table k advances a byte's influence k+1 bytes:
  ;; T0 is the plain table, T[k][i] = (T[k-1][i] >> 8) ^
  ;; T0[T[k-1][i] & 0xFF]. Layout: one flat bytevector, T[k][i] as a
  ;; native u32 at offset k*1024 + i*4, so the kernel indexes it with
  ;; one scaled memory operand per lookup.
  (define crc32-slicing-tables
    (let ((tables (make-bytevector (* 8 256 4))))
      (do ((i 0 (fx+ i 1))) ((fx= i 256))
        (bytevector-u32-native-set! tables (fx* i 4) (vector-ref crc32-table i)))
      (do ((k 1 (fx+ k 1))) ((fx= k 8) tables)
        (do ((i 0 (fx+ i 1))) ((fx= i 256))
          (let ((previous (bytevector-u32-native-ref
                            tables (fx+ (fx* (fx- k 1) 1024) (fx* i 4)))))
            (bytevector-u32-native-set!
              tables (fx+ (fx* k 1024) (fx* i 4))
              (fxxor (fxarithmetic-shift-right previous 8)
                     (bytevector-u32-native-ref
                       tables (fx* (fxand previous #xFF) 4)))))))))

  ;; Arguments: tables (u8*, the flat slicing tables), data (u8*),
  ;; length, crc-in (pre-inverted). Returns the advanced crc, NOT
  ;; final-xored -- the wrapper handles init/final inversion so the
  ;; kernel composes for incremental use. All ALU is 64-bit (the
  ;; assembler's alu forms are r64-only); values stay in 32 bits
  ;; because every load is a zero-extending 32-bit or byte load and
  ;; every xor mixes such values.
  (define _crc32-assembly-program
    '((mov rax rcx)                     ; crc accumulator
      (label chunk)                     ; while length >= 8
      (cmp rdx 8)
      (jb tail)
      (mov ebx (& rsi))                 ; low 4 bytes
      (xor rbx rax)                     ; x = crc ^ le32(data)
      (mov ecx (& rsi 4))               ; high 4 bytes
      ;; T7[x&255] ^ T6[(x>>8)&255] ^ T5[(x>>16)&255] ^ T4[x>>24]
      (mov r8 rbx) (and r8 255)
      (mov eax (& rdi r8 4 7168))
      (mov r8 rbx) (shr r8 8) (and r8 255)
      (mov r9d (& rdi r8 4 6144)) (xor rax r9)
      (mov r8 rbx) (shr r8 16) (and r8 255)
      (mov r9d (& rdi r8 4 5120)) (xor rax r9)
      (mov r8 rbx) (shr r8 24)
      (mov r9d (& rdi r8 4 4096)) (xor rax r9)
      ;; ^ T3[h&255] ^ T2[(h>>8)&255] ^ T1[(h>>16)&255] ^ T0[h>>24]
      (mov r8 rcx) (and r8 255)
      (mov r9d (& rdi r8 4 3072)) (xor rax r9)
      (mov r8 rcx) (shr r8 8) (and r8 255)
      (mov r9d (& rdi r8 4 2048)) (xor rax r9)
      (mov r8 rcx) (shr r8 16) (and r8 255)
      (mov r9d (& rdi r8 4 1024)) (xor rax r9)
      (mov r8 rcx) (shr r8 24)
      (mov r9d (& rdi r8 4 0)) (xor rax r9)
      (add rsi 8)
      (sub rdx 8)
      (jmp chunk)
      (label tail)                      ; remaining bytes one at a time
      (cmp rdx 0)
      (je done)
      (movzx rbx (& rsi))               ; crc = (crc>>8) ^ T0[(crc^b)&255]
      (xor rbx rax)
      (and rbx 255)
      (shr rax 8)
      (mov r9d (& rdi rbx 4 0))
      (xor rax r9)
      (add rsi 1)
      (sub rdx 1)
      (jmp tail)
      (label done)
      (ret)))

  (define _crc32-native
    (guard (ex (else #f))
      (assembly->procedure (sexp->assembly _crc32-assembly-program)
                           (u8* u8* size_t unsigned-32) unsigned-32)))

  (define crc32-bytevector-compute
    (lambda (bytevector start end)
      ;; The kernel path only serves START = 0 -- u8* passes the
      ;; bytevector's base address and the kernel has no offset
      ;; argument. Every production caller checksums whole bytevectors
      ;; (crc32 below); ranged callers take the Scheme loop.
      (if (and _crc32-native (fx= start 0) (fx> end start))
        (fxxor (_crc32-native crc32-slicing-tables bytevector end #xFFFFFFFF)
               #xFFFFFFFF)
        (crc32-bytevector-scheme bytevector start end))))

  (define crc32
    (lambda (bytevector)
      (crc32-bytevector-compute bytevector 0 (bytevector-length bytevector))))

  (include "letloop/crc32.check.scm"))

;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; (letloop asm) — a deliberately tiny x86-64 assembler and in-image
;; code loader. See plans/v12/20260802-sexp-assembler-jit.md.
;;
;; The instruction menu is exactly what the LOUDS and base64 kernels
;; need; this is not a general assembler. Intel operand order:
;; destination first. Memory operands:
;;
;;   (& base)  (& base disp)  (& base index scale)  (& base index scale disp)
;;
;; where base and index are 64-bit registers, scale is 1, 2, 4 or 8,
;; disp a signed 32-bit integer. Width comes from the register: a
;; 64-bit destination loads/stores a qword, a 32-bit destination
;; (eax ... r15d) loads a dword zero-extended, and movzx loads a byte
;; zero-extended. Kernels must honor the leaf-FFI contract: no
;; allocation, no calls back into Scheme, arguments are machine words
;; (unsigned-64 & friends) or bytevector spans (u8*).

;; --- executable memory ---------------------------------------------

(define asm-libc
  (load-shared-object "libc.so.6"))

(define %asm-mmap
  (foreign-procedure "mmap" (void* size_t int int int integer-64) void*))
(define %asm-mprotect
  (foreign-procedure "mprotect" (void* size_t int) int))
(define %asm-memcpy
  (foreign-procedure "memcpy" (void* u8* size_t) void*))

(define ASM-PROT-READ 1)
(define ASM-PROT-WRITE 2)
(define ASM-PROT-EXEC 4)
(define ASM-MAP-PRIVATE 2)
(define ASM-MAP-ANONYMOUS #x20)

(define assembly->address
  (lambda (code)
    ;; Copy machine bytes into a fresh executable mapping. W^X: the
    ;; page is never writable and executable at once. The mapping is
    ;; never reclaimed — call once per kernel, not in a loop.
    (let* ((length (bytevector-length code))
           (address (%asm-mmap 0 length
                               (fxior ASM-PROT-READ ASM-PROT-WRITE)
                               (fxior ASM-MAP-PRIVATE ASM-MAP-ANONYMOUS)
                               -1 0)))
      (when (or (= address 0) (= address (- (expt 2 64) 1)))
        (error 'assembly->address "mmap failed" length))
      (%asm-memcpy address code length)
      (unless (fxzero? (%asm-mprotect address length
                                      (fxior ASM-PROT-READ ASM-PROT-EXEC)))
        (error 'assembly->address "mprotect failed" address))
      address)))

(define-syntax assembly->procedure
  (syntax-rules ()
    ((_ code (type ...) return)
     (foreign-procedure (assembly->address code) (type ...) return))))

;; --- registers -----------------------------------------------------

(define %asm-r64
  '((rax . 0) (rcx . 1) (rdx . 2) (rbx . 3)
    (rsp . 4) (rbp . 5) (rsi . 6) (rdi . 7)
    (r8 . 8) (r9 . 9) (r10 . 10) (r11 . 11)
    (r12 . 12) (r13 . 13) (r14 . 14) (r15 . 15)))

(define %asm-r32
  '((eax . 0) (ecx . 1) (edx . 2) (ebx . 3)
    (esp . 4) (ebp . 5) (esi . 6) (edi . 7)
    (r8d . 8) (r9d . 9) (r10d . 10) (r11d . 11)
    (r12d . 12) (r13d . 13) (r14d . 14) (r15d . 15)))

(define asm-r64 (lambda (x) (cond ((assq x %asm-r64) => cdr) (else #f))))
(define asm-r32 (lambda (x) (cond ((assq x %asm-r32) => cdr) (else #f))))
(define asm-mem? (lambda (x) (and (pair? x) (eq? (car x) '&))))
(define asm-int8? (lambda (x) (and (integer? x) (<= -128 x 127))))
(define asm-int32?
  (lambda (x) (and (integer? x) (<= -2147483648 x 2147483647))))
(define asm-int64?
  (lambda (x) (and (integer? x) (<= (- (expt 2 63)) x (- (expt 2 64) 1)))))

;; --- assembler -----------------------------------------------------

(define sexp->assembly
  (lambda (program)
    ;; Assemble a list of instruction sexps into a bytevector of
    ;; x86-64 machine code. Labels are symbols introduced with
    ;; (label name); jumps always use rel32 except that GAS-compatible
    ;; short forms are not attempted (the differential check pads).
    (let ((buffer '())                  ; bytes, reversed
          (offset 0)
          (labels '())                  ; (name . offset)
          (fixups '()))                 ; (offset . target-label)

      (define oops
        (lambda (message instruction)
          (error 'sexp->assembly message instruction)))

      (define emit!
        (lambda bytes
          (for-each (lambda (b)
                      (set! buffer (cons (bitwise-and b #xFF) buffer))
                      (set! offset (fx+ offset 1)))
                    bytes)))

      (define emit-imm!
        (lambda (value count)           ; little-endian, two's complement
          (let loop ((i 0) (v (bitwise-and value (- (expt 2 (* 8 count)) 1))))
            (unless (fx=? i count)
              (emit! (bitwise-and v #xFF))
              (loop (fx+ i 1) (bitwise-arithmetic-shift-right v 8))))))

      (define rex
        (lambda (w r x b)               ; booleans except w
          (fxior #x40
                 (if w 8 0) (if r 4 0) (if x 2 0) (if b 1 0))))

      (define emit-rex!
        ;; Emit a REX prefix when any bit is needed.
        (lambda (w r x b)
          (when (or w r x b)
            (emit! (rex w r x b)))))

      (define modrm
        (lambda (mod reg rm)
          (fxior (fxsll mod 6) (fxsll (fxand reg 7) 3) (fxand rm 7))))

      (define parse-mem
        ;; (& base [index scale] [disp]) → (values base index scale disp)
        (lambda (operand instruction)
          (let ((rest (cdr operand)))
            (define base
              (or (and (pair? rest) (asm-r64 (car rest)))
                  (oops "bad memory base" instruction)))
            (case (length rest)
              ((1) (values base #f 1 0))
              ((2) (if (integer? (cadr rest))
                       (values base #f 1 (cadr rest))
                       (oops "bad memory displacement" instruction)))
              ((3 4)
               (let ((index (asm-r64 (cadr rest)))
                     (scale (caddr rest))
                     (disp (if (null? (cdddr rest)) 0 (cadddr rest))))
                 (unless (and index (not (fx=? index 4)))
                   (oops "bad memory index (rsp cannot index)" instruction))
                 (unless (memv scale '(1 2 4 8))
                   (oops "bad memory scale" instruction))
                 (unless (asm-int32? disp)
                   (oops "bad memory displacement" instruction))
                 (values base index scale disp)))
              (else (oops "bad memory operand" instruction))))))

      (define emit-modrm-mem!
        ;; Emit REX (with W per width) + opcode bytes + ModRM/SIB/disp
        ;; for reg-code against a memory operand.
        (lambda (w reg mem opcodes instruction)
          (let-values (((base index scale disp) (parse-mem mem instruction)))
            (let* ((base-low (fxand base 7))
                   (need-sib (or index (fx=? base-low 4)))
                   (mod (cond ((and (zero? disp) (not (fx=? base-low 5))) 0)
                              ((asm-int8? disp) 1)
                              (else 2))))
              (unless (asm-int32? disp) (oops "displacement too large" instruction))
              (emit-rex! w (fx>=? reg 8) (and index (fx>=? index 8)) (fx>=? base 8))
              (apply emit! opcodes)
              (emit! (modrm mod reg (if need-sib 4 base-low)))
              (when need-sib
                (emit! (fxior (fxsll (case scale ((1) 0) ((2) 1) ((4) 2) (else 3)) 6)
                              (fxsll (fxand (or index 4) 7) 3)
                              base-low)))
              (case mod
                ((1) (emit-imm! disp 1))
                ((2) (emit-imm! disp 4)))))))

      (define emit-modrm-reg!
        ;; REX.W + opcodes + ModRM for register-to-register forms.
        (lambda (w reg rm opcodes)
          (emit-rex! w (fx>=? reg 8) #f (fx>=? rm 8))
          (apply emit! opcodes)
          (emit! (modrm 3 reg rm))))

      (define emit-jump!
        (lambda (opcodes target)
          (apply emit! opcodes)
          (set! fixups (cons (cons offset target) fixups))
          (emit-imm! 0 4)))

      ;; ALU ops: (mnemonic MR-opcode /n-for-imm A-opcode-for-rax)
      (define %asm-alu
        '((add #x01 0 #x05) (or #x09 1 #x0D) (and #x21 4 #x25)
          (sub #x29 5 #x2D) (xor #x31 6 #x35) (cmp #x39 7 #x3D)))

      (define alu!
        (lambda (mnemonic dst src instruction)
          (let* ((entry (assq mnemonic %asm-alu))
                 (mr (cadr entry)) (/n (caddr entry)) (a-form (cadddr entry))
                 (d64 (asm-r64 dst)))
            (cond
             ((and d64 (asm-r64 src))   ; op r64, r64 — MR form, reg = src
              (emit-modrm-reg! #t (asm-r64 src) d64 (list mr)))
             ((and d64 (asm-mem? src))  ; op r64, m64 — RM form, reg = dst
              (emit-modrm-mem! #t d64 src (list (fx+ mr 2)) instruction))
             ((and d64 (integer? src))
              (cond ((asm-int8? src)
                     (emit-rex! #t #f #f (fx>=? d64 8))
                     (emit! #x83 (modrm 3 /n d64))
                     (emit-imm! src 1))
                    ((not (asm-int32? src)) (oops "immediate too large" instruction))
                    ((fx=? d64 0)          ; rax, imm32 — short A form, as GAS does
                     (emit! (rex #t #f #f #f) a-form)
                     (emit-imm! src 4))
                    (else
                     (emit-rex! #t #f #f (fx>=? d64 8))
                     (emit! #x81 (modrm 3 /n d64))
                     (emit-imm! src 4))))
             (else (oops "bad operands" instruction))))))

      (define shift!
        (lambda (/n dst count instruction)
          (let ((d64 (or (asm-r64 dst) (oops "bad shift destination" instruction))))
            (cond ((eq? count 'cl)
                   (emit-rex! #t #f #f (fx>=? d64 8))
                   (emit! #xD3 (modrm 3 /n d64)))
                  ((eqv? count 1)       ; short form, as GAS does
                   (emit-rex! #t #f #f (fx>=? d64 8))
                   (emit! #xD1 (modrm 3 /n d64)))
                  ((and (integer? count) (<= 0 count 63))
                   (emit-rex! #t #f #f (fx>=? d64 8))
                   (emit! #xC1 (modrm 3 /n d64))
                   (emit-imm! count 1))
                  (else (oops "bad shift count" instruction))))))

      (define %asm-jcc                  ; condition code low nibble
        '((jo . 0) (jno . 1) (jb . 2) (jae . 3) (je . 4) (jne . 5)
          (jbe . 6) (ja . 7) (js . 8) (jns . 9) (jl . #xC) (jge . #xD)
          (jle . #xE) (jg . #xF)))

      (define assemble-one!
        (lambda (instruction)
          (let ((head (car instruction))
                (operands (cdr instruction)))
            (define dst (and (pair? operands) (car operands)))
            (define src (and (pair? operands) (pair? (cdr operands)) (cadr operands)))
            (case head
              ((label)
               (set! labels (cons (cons dst offset) labels)))
              ((ret) (emit! #xC3))
              ((nop) (emit! #x90))
              ((mov)
               (let ((d64 (asm-r64 dst)) (d32 (asm-r32 dst)))
                 (cond
                  ((and d64 (asm-r64 src)) ; mov r64, r64
                   (emit-modrm-reg! #t (asm-r64 src) d64 '(#x89)))
                  ((and d64 (asm-mem? src)) ; mov r64, m64
                   (emit-modrm-mem! #t d64 src '(#x8B) instruction))
                  ((and d32 (asm-mem? src)) ; mov r32, m32 (zero-extends)
                   (emit-modrm-mem! #f d32 src '(#x8B) instruction))
                  ((and (asm-mem? dst) (asm-r64 src)) ; mov m64, r64
                   (emit-modrm-mem! #t (asm-r64 src) dst '(#x89) instruction))
                  ((and d64 (integer? src))
                   (cond ((asm-int32? src) ; sign-extended imm32, as GAS does
                          (emit-rex! #t #f #f (fx>=? d64 8))
                          (emit! #xC7 (modrm 3 0 d64))
                          (emit-imm! src 4))
                         ((asm-int64? src) ; movabs
                          (emit-rex! #t #f #f (fx>=? d64 8))
                          (emit! (fx+ #xB8 (fxand d64 7)))
                          (emit-imm! src 8))
                         (else (oops "immediate too large" instruction))))
                  ((and d32 (integer? src))
                   (unless (<= 0 src (- (expt 2 32) 1))
                     (oops "bad 32-bit immediate" instruction))
                   (emit-rex! #f #f #f (fx>=? d32 8))
                   (emit! (fx+ #xB8 (fxand d32 7)))
                   (emit-imm! src 4))
                  (else (oops "bad operands" instruction)))))
              ((movzx)                  ; movzx r64, byte [mem]
               (let ((d64 (or (asm-r64 dst) (oops "bad operands" instruction))))
                 (unless (asm-mem? src) (oops "movzx wants a memory source" instruction))
                 (emit-modrm-mem! #t d64 src '(#x0F #xB6) instruction)))
              ((lea)
               (let ((d64 (or (asm-r64 dst) (oops "bad operands" instruction))))
                 (unless (asm-mem? src) (oops "lea wants a memory source" instruction))
                 (emit-modrm-mem! #t d64 src '(#x8D) instruction)))
              ((add or and sub xor cmp)
               (alu! head dst src instruction))
              ((test)
               (let ((d64 (asm-r64 dst)))
                 (cond ((and d64 (asm-r64 src))
                        (emit-modrm-reg! #t (asm-r64 src) d64 '(#x85)))
                       ((and d64 (integer? src))
                        (unless (asm-int32? src) (oops "immediate too large" instruction))
                        (if (fx=? d64 0)
                            (begin (emit! (rex #t #f #f #f) #xA9))
                            (begin (emit-rex! #t #f #f (fx>=? d64 8))
                                   (emit! #xF7 (modrm 3 0 d64))))
                        (emit-imm! src 4))
                       (else (oops "bad operands" instruction)))))
              ((not) (let ((d64 (or (asm-r64 dst) (oops "bad operands" instruction))))
                       (emit-rex! #t #f #f (fx>=? d64 8))
                       (emit! #xF7 (modrm 3 2 d64))))
              ((neg) (let ((d64 (or (asm-r64 dst) (oops "bad operands" instruction))))
                       (emit-rex! #t #f #f (fx>=? d64 8))
                       (emit! #xF7 (modrm 3 3 d64))))
              ((shl) (shift! 4 dst src instruction))
              ((shr) (shift! 5 dst src instruction))
              ((imul)                   ; imul r64, r64 — RM form, reg = dst
               (let ((d64 (asm-r64 dst)) (s64 (asm-r64 src)))
                 (unless (and d64 s64) (oops "bad operands" instruction))
                 (emit-modrm-reg! #t d64 s64 '(#x0F #xAF))))
              ((popcnt tzcnt)           ; F3 REX.W 0F B8/BC /r, reg = dst
               (let ((d64 (asm-r64 dst)) (s64 (asm-r64 src)))
                 (unless (and d64 s64) (oops "bad operands" instruction))
                 (emit! #xF3)
                 (emit-modrm-reg! #t d64 s64
                                  (list #x0F (if (eq? head 'popcnt) #xB8 #xBC)))))
              ((pdep)                   ; VEX.LZ.F2.0F38.W1 F5 /r
               (let ((d64 (asm-r64 dst))
                     (s164 (asm-r64 src))
                     (s264 (asm-r64 (caddr operands))))
                 (unless (and d64 s164 s264) (oops "bad operands" instruction))
                 (emit! #xC4
                        (fxior (if (fx>=? d64 8) 0 #x80)  ; ~R
                               #x40                       ; ~X (no index)
                               (if (fx>=? s264 8) 0 #x20) ; ~B
                               #b00010)                   ; 0F38
                        (fxior #x80                       ; W=1
                               (fxsll (fxand (fxnot s164) #xF) 3) ; ~vvvv
                               #b011)                     ; L=0, pp=F2
                        #xF5
                        (modrm 3 d64 s264))))
              ((jmp) (emit-jump! '(#xE9) dst))
              ((je jne jb jae jbe ja jl jge jle jg js jns jo jno)
               (emit-jump! (list #x0F (fx+ #x80 (cdr (assq head %asm-jcc)))) dst))
              (else (oops "unknown mnemonic" instruction))))))

      (for-each
       (lambda (instruction)
         (unless (pair? instruction) (oops "bad instruction" instruction))
         (assemble-one! instruction))
       program)

      (let ((code (u8-list->bytevector (reverse buffer))))
        (for-each
         (lambda (fixup)
           (let* ((position (car fixup))
                  (target (assq (cdr fixup) labels)))
             (unless target
               (oops "undefined label" (cdr fixup)))
             (bytevector-u32-set! code position
                                  (bitwise-and (- (cdr target) (+ position 4))
                                               #xFFFFFFFF)
                                  (endianness little))))
         fixups)
        code))))

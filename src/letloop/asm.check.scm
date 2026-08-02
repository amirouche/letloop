;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Checks for (letloop asm). Two families:
;;
;;   1. Differential: render each supported instruction form to GNU as
;;      Intel syntax, assemble with the system `as`, and compare bytes
;;      with our encoder. Encoding bugs die here, not in a segfault.
;;      These checks skip (and say so) when binutils is unavailable.
;;
;;   2. Semantic: assemble small kernels, map them executable, call
;;      them through the FFI and compare against a Scheme reference.

;; Local copy of the (letloop aql shims) check macro: importing the
;; shims would drag (letloop cffi) into consumers' whole-program
;; compiles, and a boot-image library carries no .wpo to fold.
(define-syntax check
  (syntax-rules ()
    ((check v)
     (let ((v* v))
       (eq? v* #t)))
    ((check a b)
     (let ((a* a)
           (b* b))
       (check (equal? a* b*))))))

(define %asm-check-counter 0)

(define %asm-check-tmpdir
  (lambda ()
    (set! %asm-check-counter (fx+ %asm-check-counter 1))
    (let ((directory (format "/tmp/letloop-asm-check-~a-~a"
                             (real-time) %asm-check-counter)))
      (system (string-append "mkdir -p " directory))
      directory)))

(define %asm-check-binutils?
  (lambda ()
    (and (zero? (system "as --version > /dev/null 2>&1"))
         (zero? (system "objcopy --version > /dev/null 2>&1")))))

(define %asm-check-file->bytevector
  (lambda (path)
    (let* ((port (open-file-input-port path))
           (bytes (get-bytevector-all port)))
      (close-port port)
      (if (eof-object? bytes) (make-bytevector 0) bytes))))

(define %asm-check-hex
  (lambda (bytes)
    (apply string-append
           (map (lambda (b)
                  (let ((s (number->string b 16)))
                    (if (fx=? (string-length s) 1)
                        (string-append "0" s " ")
                        (string-append s " "))))
                (bytevector->u8-list bytes)))))

(define %asm-check-gas-mem*
  (lambda (operand)
    (let ((rest (cdr operand)))
      (define disp->string
        (lambda (disp)
          (cond ((zero? disp) "")
                ((negative? disp) (number->string disp))
                (else (string-append "+" (number->string disp))))))
      (case (length rest)
        ((1) (format "[~a]" (car rest)))
        ((2) (format "[~a~a]" (car rest) (disp->string (cadr rest))))
        ((3) (format "[~a+~a*~a]" (car rest) (cadr rest) (caddr rest)))
        (else (format "[~a+~a*~a~a]" (car rest) (cadr rest) (caddr rest)
                      (disp->string (cadddr rest))))))))

(define %asm-check-gas
  (lambda (instruction)
    (let ((head (car instruction))
          (operands (cdr instruction)))
      (define operand->string
        (lambda (operand)
          (cond ((symbol? operand) (symbol->string operand))
                ((integer? operand) (number->string operand))
                ((asm-mem? operand) (%asm-check-gas-mem* operand))
                (else (error '%asm-check-gas "bad operand" instruction)))))
      (case head
        ((label) (format "~a:" (car operands)))
        ((ret) "ret")
        ((nop) "nop")
        ((vzeroupper) "vzeroupper")
        ((movzx) (format "movzx ~a, byte ptr ~a"
                         (car operands)
                         (%asm-check-gas-mem* (cadr operands))))
        ((mov)
         (if (and (asm-r64 (car operands))
                  (integer? (cadr operands))
                  (not (asm-int32? (cadr operands))))
             (format "movabs ~a, ~a" (car operands) (cadr operands))
             (format "mov ~a" (apply string-append
                                     (cdr (apply append
                                                 (map (lambda (o)
                                                        (list ", " (operand->string o)))
                                                      operands)))))))
        ((jmp je jne jb jae jbe ja jl jge jle jg js jns jo jno)
         (format "~a ~a" head (car operands)))
        (else
         (format "~a ~a" head
                 (apply string-append
                        (cdr (apply append
                                    (map (lambda (o) (list ", " (operand->string o)))
                                        operands))))))))))

(define %asm-check-gas-assemble
  ;; Assemble instructions with the system `as`; #f on failure.
  (lambda (directory instructions)
    (let ((source (string-append directory "/check.s"))
          (object (string-append directory "/check.o"))
          (binary (string-append directory "/check.bin")))
      (call-with-output-file source
        (lambda (port)
          (put-string port ".intel_syntax noprefix\n.text\n")
          (for-each (lambda (i) (put-string port (%asm-check-gas i))
                            (put-string port "\n"))
                    instructions))
        'replace)
      (and (zero? (system (format "as --64 -o ~a ~a" object source)))
           (zero? (system (format "objcopy -O binary --only-section=.text ~a ~a"
                                  object binary)))
           (%asm-check-file->bytevector binary)))))

(define %asm-check-differential
  ;; Compare our encoder against the system assembler over a program
  ;; of straight-line instructions; on mismatch, isolate and report
  ;; the first offending instruction.
  (lambda (instructions)
    (if (not (%asm-check-binutils?))
        (begin (display "asm check: binutils not found, differential check skipped\n")
               #t)
        (let* ((directory (%asm-check-tmpdir))
               (ours (sexp->assembly instructions))
               (gas (%asm-check-gas-assemble directory instructions))
               (verdict
                (cond
                 ((not gas)
                  (format #t "asm check: system as rejected the program in ~a\n"
                          directory)
                  #f)
                 ((bytevector=? ours gas) #t)
                 (else
                  (let loop ((rest instructions))
                    (if (null? rest)
                        (format #t "asm check: whole-program mismatch only (~a)\n"
                                directory)
                        (let* ((instruction (car rest))
                               (mine (sexp->assembly (list instruction)))
                               (theirs (%asm-check-gas-assemble
                                        directory (list instruction))))
                          (if (and theirs (bytevector=? mine theirs))
                              (loop (cdr rest))
                              (format #t "asm check mismatch: ~s\n  ours:   ~a\n  gnu as: ~a\n"
                                      instruction
                                      (%asm-check-hex mine)
                                      (if theirs (%asm-check-hex theirs) "rejected"))))))
                  #f))))
          (when verdict
            (system (string-append "rm -rf " directory)))
          verdict))))

;; --- 000: executable memory, no assembler involved -----------------

(define ~check-asm-000
  (lambda ()
    ;; mov rax, rdi; add rax, rsi; ret — hand-assembled bytes.
    (let ((f (assembly->procedure
              (u8-list->bytevector '(#x48 #x89 #xF8 #x48 #x01 #xF0 #xC3))
              (unsigned-64 unsigned-64) unsigned-64)))
      (check #t (and (= (f 1 2) 3)
                     (= (f 1099511627776 5) 1099511627781)
                     (= (f 0 0) 0))))))

;; --- 001: register-register forms ----------------------------------

(define ~check-asm-001
  (lambda ()
    (let ((dsts '(rax rcx rdx rbx rsp rbp rsi rdi r8 r9 r12 r13 r15))
          (srcs '(rcx r9 rbp)))
      (check #t (%asm-check-differential
                 (apply append
                        (map (lambda (op)
                               (apply append
                                      (map (lambda (dst)
                                             (map (lambda (src) (list op dst src))
                                                  srcs))
                                           dsts)))
                             '(mov add sub and or xor cmp test imul))))))))

;; --- 002: memory addressing ----------------------------------------

(define ~check-asm-002
  (lambda ()
    (let ((bases '(rax rcx rdx rbx rsp rbp rsi rdi r8 r9 r10 r11 r12 r13 r14 r15))
          (indexes '(rax rbp r8 r13 r15))
          (scales '(1 2 4 8)))
      (check #t (%asm-check-differential
                 (append
                  (apply append
                         (map (lambda (base)
                                (list (list 'mov 'rax (list '& base))
                                      (list 'mov 'rax (list '& base 8))
                                      (list 'mov 'rax (list '& base 300))
                                      (list 'mov 'rax (list '& base -8))
                                      (list 'mov 'r10 (list '& base 'rcx 8 16))
                                      (list 'mov 'eax (list '& base))
                                      (list 'mov 'r11d (list '& base 4))
                                      (list 'movzx 'rdx (list '& base 1))
                                      (list 'lea 'r11 (list '& base 'rdx 4 -32))
                                      (list 'mov (list '& base 24) 'r9)
                                      (list 'add 'rax (list '& base 40))
                                      (list 'cmp 'rsi (list '& base))))
                              bases))
                  (apply append
                         (map (lambda (index)
                                (map (lambda (scale)
                                       (list 'lea 'rax (list '& 'rdi index scale 8)))
                                     scales))
                              indexes))))))))

;; --- 003: immediates, shifts, unary --------------------------------

(define ~check-asm-003
  (lambda ()
    (check #t (%asm-check-differential
               (append
                (apply append
                       (map (lambda (op)
                              (apply append
                                     (map (lambda (dst)
                                            (map (lambda (imm) (list op dst imm))
                                                 '(1 127 128 -128 -129 1000000 -1)))
                                          '(rax rcx rsp r13))))
                            '(add sub and or xor cmp)))
                '((test rax 255) (test rcx 4096) (test r13 -1)
                  (mov rax 1) (mov rax -1) (mov rax 2147483647)
                  (mov rax 2147483648) (mov rax -2147483648)
                  (mov rax -2147483649) (mov r9 1311768467463790320)
                  (mov eax 5) (mov r10d 300)
                  (not rax) (not r13) (neg rax) (neg r13)
                  (push rax) (push rbp) (push r12) (push r15)
                  (pop rax) (pop rbp) (pop r12) (pop r15))
                (apply append
                       (map (lambda (op)
                              (apply append
                                     (map (lambda (dst)
                                            (map (lambda (count) (list op dst count))
                                                 '(1 5 63 cl)))
                                          '(rax rcx r12))))
                            '(shl shr))))))))

;; --- 004: popcnt, tzcnt, pdep --------------------------------------

(define ~check-asm-004
  (lambda ()
    (check #t (%asm-check-differential
               '((popcnt rax rcx) (popcnt r9 rdx) (popcnt rax rax) (popcnt r12 r13)
                 (tzcnt rax rcx) (tzcnt r9 rdx) (tzcnt rax rax) (tzcnt r12 r13)
                 (pdep rax rcx rdx) (pdep r8 r9 r10)
                 (pdep rax r13 rbp) (pdep r15 rax r8))))))

;; --- 007: AVX2 differential ----------------------------------------

(define ~check-asm-007
  (lambda ()
    (check #t (%asm-check-differential
               (append
                ;; three-operand forms over low/high register mixes
                (apply append
                       (map (lambda (op)
                              (map (lambda (regs)
                                     (cons op regs))
                                   '((ymm0 ymm1 ymm2) (ymm3 ymm4 ymm5)
                                     (ymm0 ymm8 ymm15) (ymm12 ymm1 ymm9)
                                     (ymm8 ymm9 ymm10))))
                            '(vpshufb vpand vpor vpaddb vpsubb vpsubusb
                              vpcmpgtb vpmulhuw vpmullw)))
                ;; memory source forms
                '((vpaddb ymm0 ymm1 (& rdi))
                  (vpand ymm2 ymm3 (& rsi 32))
                  (vpshufb ymm8 ymm9 (& r8 64))
                  (vpmulhuw ymm1 ymm2 (& rax rcx 1 0))
                  ;; loads and stores, both widths
                  (vmovdqu ymm0 (& rdi)) (vmovdqu ymm8 (& rdi 32))
                  (vmovdqu ymm3 (& r13 -8)) (vmovdqu xmm0 (& rdi))
                  (vmovdqu xmm9 (& rsp 16))
                  (vmovdqu (& rdi) ymm0) (vmovdqu (& rsi 32) ymm12)
                  (vmovdqu (& r9 8) xmm4)
                  ;; vinserti128, register and memory sources
                  (vinserti128 ymm0 ymm0 xmm1 1)
                  (vinserti128 ymm2 ymm3 xmm10 0)
                  (vinserti128 ymm8 ymm0 (& rdi 12) 1)
                  (vinserti128 ymm1 ymm1 (& r10 12) 1)
                  (vzeroupper)))))))

;; --- 008: executed AVX2 semantics ----------------------------------

(define ~check-asm-008
  (lambda ()
    ;; dst[0..31] = src[0..31] + src[32..63] (bytewise, mod 256)
    (let ((add32 (assembly->procedure
                  (sexp->assembly '((vmovdqu ymm0 (& rdi))
                                    (vpaddb ymm0 ymm0 (& rdi 32))
                                    (vmovdqu (& rsi) ymm0)
                                    (vzeroupper)
                                    (ret)))
                  (u8* u8*) void))
          (source (make-bytevector 64))
          (target (make-bytevector 32 0)))
      (let loop ((i 0) (state 7))
        (unless (fx=? i 64)
          (let ((state (mod (+ (* state 1103515245) 12345) 2147483648)))
            (bytevector-u8-set! source i (mod state 256))
            (loop (fx+ i 1) state))))
      (add32 source target)
      (check #t (let loop ((i 0))
                  (cond ((fx=? i 32) #t)
                        ((fx=? (bytevector-u8-ref target i)
                               (fxand (fx+ (bytevector-u8-ref source i)
                                           (bytevector-u8-ref source (fx+ i 32)))
                                      #xFF))
                         (loop (fx+ i 1)))
                        (else #f)))))))

;; --- 005: executed bit-manipulation semantics ----------------------

(define ~check-asm-005
  (lambda ()
    (let ((popcount (assembly->procedure
                     (sexp->assembly '((popcnt rax rdi) (ret)))
                     (unsigned-64) unsigned-64))
          (trailing (assembly->procedure
                     (sexp->assembly '((tzcnt rax rdi) (ret)))
                     (unsigned-64) unsigned-64))
          (deposit (assembly->procedure
                    (sexp->assembly '((pdep rax rdi rsi) (ret)))
                    (unsigned-64 unsigned-64) unsigned-64))
          ;; select-in-word: position of the r-th set bit of w —
          ;; tzcnt(pdep(1 << (r-1), w)), the ls_select0 final step.
          (select (assembly->procedure
                   (sexp->assembly '((mov rcx rdi)
                                     (sub rcx 1)
                                     (mov rax 1)
                                     (shl rax cl)
                                     (pdep rax rax rsi)
                                     (tzcnt rax rax)
                                     (ret)))
                   (unsigned-64 unsigned-64) unsigned-64)))
      (check #t (and (= (popcount #xFF00FF) 16)
                     (= (popcount 0) 0)
                     (= (popcount (- (expt 2 64) 1)) 64)
                     (= (trailing 8) 3)
                     (= (trailing 1) 0)
                     (= (trailing 0) 64)
                     (= (deposit #xB #xF0F0) #xB0)
                     (= (select 1 #b10110010) 1)
                     (= (select 3 #b10110010) 5)
                     (= (select 4 #b10110010) 7))))))

;; --- 006: executed loop kernel: labels, jumps, byte loads ----------

(define ~check-asm-006
  (lambda ()
    ;; count occurrences of a byte value in a memory span
    (let ((count-byte
           (assembly->procedure
            (sexp->assembly '((mov rax 0)          ; count
                              (mov rcx 0)          ; i
                              (label loop)
                              (cmp rcx rsi)
                              (jae done)
                              (movzx r8 (& rdi rcx 1 0))
                              (cmp r8 rdx)
                              (jne skip)
                              (add rax 1)
                              (label skip)
                              (add rcx 1)
                              (jmp loop)
                              (label done)
                              (ret)))
            (u8* unsigned-64 unsigned-64) unsigned-64))
          (bytes (make-bytevector 4096)))
      ;; deterministic pseudo-random fill (LCG, fixed seed)
      (let loop ((i 0) (state 42))
        (unless (fx=? i 4096)
          (let ((state (mod (+ (* state 1103515245) 12345) 2147483648)))
            (bytevector-u8-set! bytes i (mod state 256))
            (loop (fx+ i 1) state))))
      (let ((reference (lambda (value)
                         (let loop ((i 0) (n 0))
                           (if (fx=? i 4096)
                               n
                               (loop (fx+ i 1)
                                     (if (fx=? (bytevector-u8-ref bytes i) value)
                                         (fx+ n 1)
                                         n)))))))
        (check #t (and (= (count-byte bytes 4096 42) (reference 42))
                       (= (count-byte bytes 4096 0) (reference 0))
                       (= (count-byte bytes 4096 255) (reference 255))
                       (= (count-byte bytes 0 42) 0)))))))

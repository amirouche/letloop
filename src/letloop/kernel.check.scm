;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>

;; Local copy of the (letloop aql shims) check macro; see the note in
;; asm.check.scm.
(define-syntax check
  (syntax-rules ()
    ((check v)
     (let ((v* v))
       (eq? v* #t)))
    ((check a b)
     (let ((a* a)
           (b* b))
       (check (equal? a* b*))))))

;; straight-line arithmetic; u64 return is the default
(define %kernel-check-mix
  (kernel ((u64 a) (u64 b) (u64 c))
    (band (+ (<< a 4) (* b 3) (- c 1)) 65535)))

(define ~check-kernel-000
  (lambda ()
    (check #t (and (= (%kernel-check-mix 1 1 1) 19)
                   (= (%kernel-check-mix 0 0 1) 0)
                   (= (%kernel-check-mix 4096 100 7)
                      (bitwise-and (+ (* 4096 16) 300 6) 65535))))))

;; loop, byte loads, value-position if, loop-carried accumulator
(define %kernel-check-count
  (kernel ((u8* p) (u64 len) (u64 b))
    (let loop ((i 0) (n 0))
      (if (= i len)
          n
          (loop (+ i 1)
                (if (= (u8@ p i) b) (+ n 1) n))))))

(define ~check-kernel-001
  (lambda ()
    (let ((bytes (make-bytevector 4096)))
      (let fill ((i 0) (state 42))
        (unless (fx=? i 4096)
          (let ((state (mod (+ (* state 1103515245) 12345) 2147483648)))
            (bytevector-u8-set! bytes i (mod state 256))
            (fill (fx+ i 1) state))))
      (let ((reference (lambda (value)
                         (let loop ((i 0) (n 0))
                           (if (fx=? i 4096)
                               n
                               (loop (fx+ i 1)
                                     (if (fx=? (bytevector-u8-ref bytes i) value)
                                         (fx+ n 1)
                                         n)))))))
        (check #t (and (= (%kernel-check-count bytes 4096 42) (reference 42))
                       (= (%kernel-check-count bytes 4096 0) (reference 0))
                       (= (%kernel-check-count bytes 0 42) 0)))))))

;; kernel-source: sum for plain Chez — the definition is recovered
;; from the procedure value itself, the way Kernel's meta operative
;; works on a combiner
(define ~check-kernel-002
  (lambda ()
    (check '(kernel ((u8* p) (u64 len) (u64 b))
              (let loop ((i 0) (n 0))
                (if (= i len)
                    n
                    (loop (+ i 1)
                          (if (= (u8@ p i) b) (+ n 1) n)))))
           (kernel-source %kernel-check-count))))

;; bit-manipulation intrinsics: position of the r-th set bit of w
(define %kernel-check-select
  (kernel ((u64 r) (u64 w))
    (tzcnt (pdep (<< 1 (- r 1)) w))))

;; the assembly escape hatch: raw mnemonics, same signature shape,
;; same source registry
(define %kernel-check-asm-add
  (assembly ((u64 a) (u64 b))
    (lea rax (& rdi rsi 1 0))
    (ret)))

(define ~check-kernel-004
  (lambda ()
    (check #t (and (= (%kernel-check-asm-add 40 2) 42)
                   (= (%kernel-check-asm-add 1099511627776 1) 1099511627777)
                   (equal? (kernel-source %kernel-check-asm-add)
                           '(assembly ((u64 a) (u64 b))
                              (lea rax (& rdi rsi 1 0))
                              (ret)))))))

;; dubito rejects contract violations at definition time, naming
;; the offending expression
(define ~check-kernel-005
  (lambda ()
    (define rejected?
      (lambda (thunk)
        (guard (ex (else #t)) (thunk) #f)))
    (check #t (and (rejected? (lambda () (kernel ((u8* p) (u8* q)) (+ p q))))
                   (rejected? (lambda () (kernel ((u64 a)) (u8@ a 0))))
                   (rejected? (lambda () (kernel ((u8* p)) p)))
                   (rejected? (lambda () (kernel ((u8* p) (u64 n)) (len p))))
                   (rejected? (lambda () (kernel ((u8* p) (u64 n))
                                           (let loop ((x n))
                                             (if (= x 0) 0 (loop p))))))))))

;; entry assumptions: O(1) Scheme-side guards, exact semantics
(define %kernel-check-guarded
  (kernel ((u8* p) (u64 off) (u64 n))
    (assert (<= (+ off n) (len p)))
    (let loop ((i 0) (acc 0))
      (if (= i n)
          acc
          (loop (+ i 1) (+ acc (u8@ p (+ off i))))))))

(define ~check-kernel-006
  (lambda ()
    (let ((bytes (u8-list->bytevector '(1 2 3 4 5))))
      (check #t (and (= (%kernel-check-guarded bytes 1 3) 9)
                     (= (%kernel-check-guarded bytes 0 5) 15)
                     (guard (ex (else #t))          ; off+n out of bounds
                       (%kernel-check-guarded bytes 3 3)
                       #f))))))

;; dubito reports: verified for kernels, trusted for assembly,
;; nothing-to-doubt for opaque procedures
(define ~check-kernel-007
  (lambda ()
    (check #t (and (equal? (assq 'verdict (dubito %kernel-check-count))
                           '(verdict . verified))
                   (equal? (assq 'asserts (dubito %kernel-check-guarded))
                           '(asserts . 1))
                   (equal? (assq 'verdict (dubito %kernel-check-asm-add))
                           '(verdict . trusted))
                   (guard (ex (else #t)) (dubito car) #f)))))

(define ~check-kernel-003
  (lambda ()
    (check #t (and (= (%kernel-check-select 1 #b10110010) 1)
                   (= (%kernel-check-select 3 #b10110010) 5)
                   (= (%kernel-check-select 4 #b10110010) 7)))))

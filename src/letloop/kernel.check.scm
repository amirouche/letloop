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

;; straight-line arithmetic
(define-kernel (%kernel-check-mix (a u64) (b u64) (c u64)) u64
  (band (+ (<< a 4) (* b 3) (- c 1)) 65535))

(define ~check-kernel-000
  (lambda ()
    (check #t (and (= (%kernel-check-mix 1 1 1) 19)
                   (= (%kernel-check-mix 0 0 1) 0)
                   (= (%kernel-check-mix 4096 100 7)
                      (bitwise-and (+ (* 4096 16) 300 6) 65535))))))

;; loop, byte loads, value-position if, loop-carried accumulator
(define-kernel (%kernel-check-count (p u8*) (len u64) (b u64)) u64
  (let loop ((i 0) (n 0))
    (if (= i len)
        n
        (loop (+ i 1)
              (if (= (u8@ p i) b) (+ n 1) n)))))

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

;; kernel-source: sum for plain Chez — the definition is recoverable
(define ~check-kernel-002
  (lambda ()
    (check '(define-kernel (%kernel-check-count (p u8*) (len u64) (b u64)) u64
              (let loop ((i 0) (n 0))
                (if (= i len)
                    n
                    (loop (+ i 1)
                          (if (= (u8@ p i) b) (+ n 1) n)))))
           (kernel-source '%kernel-check-count))))

;; bit-manipulation intrinsics: position of the r-th set bit of w
(define-kernel (%kernel-check-select (r u64) (w u64)) u64
  (tzcnt (pdep (<< 1 (- r 1)) w)))

(define ~check-kernel-003
  (lambda ()
    (check #t (and (= (%kernel-check-select 1 #b10110010) 1)
                   (= (%kernel-check-select 3 #b10110010) 5)
                   (= (%kernel-check-select 4 #b10110010) 7)))))

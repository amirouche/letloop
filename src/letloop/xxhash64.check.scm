;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Included at the tail of the library; discovered by `make check` via
;; the ~check- exports.

;; ---- Checks (vectors from Python's `xxhash` package, seed 0) ----

(define (~check-xxhash64-empty)
  (assert (= (xxhash64 (string->utf8 "")) #xef46db3751d8e999)))

(define (~check-xxhash64-short)
  (assert (= (xxhash64 (string->utf8 "a")) #xd24ec4f1a98c6e5b))
  (assert (= (xxhash64 (string->utf8 "abc")) #x44bc2cf5ad770999))
  (assert (= (xxhash64 (string->utf8 "a b")) #x10dda12a5dc0b218)))

(define (~check-xxhash64-boundary-31-32-33)
  (assert (= (xxhash64 (string->utf8 (make-string 31 #\x)))
             #x60dd0d01083b99f0))
  (assert (= (xxhash64 (string->utf8 (make-string 32 #\x)))
             #xe2df261fc2ec30eb))
  (assert (= (xxhash64 (string->utf8 (make-string 33 #\x)))
             #xb3fa465f554208a6)))

(define (~check-xxhash64-long)
  (assert (= (xxhash64 (string->utf8 (make-string 100 #\x)))
             #x92f0de5a88a3c094)))

(define (~check-xxhash64-phrases)
  (assert (= (xxhash64 (string->utf8 "hello world"))
             #x45ab6734b21e6968))
  (assert (= (xxhash64 (string->utf8
                         "the quick brown fox jumps over the lazy dog"))
             #xed714233c5a9a792))
  (assert (= (xxhash64 (string->utf8 "apple banana cherry"))
             #xa636b2e9f24ea1c8)))

(define (~check-xxhash64-assembly-agrees-with-scheme)
  ;; When the JIT kernel assembled, machine code and Scheme must
  ;; agree on every length class (empty, sub-4, sub-8, sub-32,
  ;; 32-aligned, long with every tail width). If assembling failed
  ;; both sides of the comparison are the Scheme path and the check
  ;; degenerates to trivially true -- the vectors above already pin
  ;; correctness in that case.
  (let loop ((n 0))
    (when (<= n 100)
      (let ((data (make-bytevector n)))
        (do ((i 0 (+ i 1))) ((= i n))
          (bytevector-u8-set! data i (mod (* (+ i 7) (+ n 13)) 256)))
        (assert (= (xxhash64 data) (xxhash64-scheme data))))
      (loop (+ n 1))))
  #t)

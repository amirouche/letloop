;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Included at the tail of the library; discovered by `make check` via
;; the ~check- exports.

;; Tests

(define (~check-crc32-empty)
  (assert (= (crc32 #vu8()) 0)))

(define (~check-crc32-known-value)
  ;; CRC32 of ASCII "123456789" = #xCBF43926
  (assert (= (crc32 (string->bytevector "123456789" (make-transcoder (latin-1-codec))))
             #xCBF43926)))

(define (~check-crc32-single-byte)
  (let ((result (crc32 #vu8(0))))
    (assert (integer? result))
    (assert (>= result 0))
    (assert (<= result #xFFFFFFFF))))

(define (~check-crc32-incremental)
  ;; Streaming crc32-update must match single-call crc32
  (let* ((data (string->bytevector "Hello, World!" (make-transcoder (latin-1-codec))))
         (expected (crc32 data))
         (result (let loop ((i 0) (crc #xFFFFFFFF))
                   (if (fx>= i (bytevector-length data))
                     (fxand (fxxor crc #xFFFFFFFF) #xFFFFFFFF)
                     (loop (fx+ i 1)
                           (crc32-update crc (bytevector-u8-ref data i)))))))
    (assert (= expected result))))

(define (~check-crc32-assembly-agrees-with-scheme)
  ;; Slicing-by-8 kernel vs the byte-loop reference over every
  ;; length class 0-64 (empty, sub-8 tail-only, 8-aligned, mixed)
  ;; plus a larger block. If assembling failed both sides are the
  ;; Scheme path and this degenerates to trivially true -- the known
  ;; vectors above pin correctness in that case.
  (let loop ((n 0))
    (when (<= n 64)
      (let ((data (make-bytevector n)))
        (do ((i 0 (+ i 1))) ((= i n))
          (bytevector-u8-set! data i (mod (* (+ i 3) (+ n 11)) 256)))
        (assert (= (crc32 data)
                   (crc32-bytevector-scheme data 0 n))))
      (loop (+ n 1))))
  (let ((data (make-bytevector 100003)))
    (do ((i 0 (+ i 1))) ((= i 100003))
      (bytevector-u8-set! data i (mod (* i 31) 256)))
    (assert (= (crc32 data) (crc32-bytevector-scheme data 0 100003))))
  #t)

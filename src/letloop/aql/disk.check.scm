;; Copyright © 2024-2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Tests for AQL Block Storage Layer.
;; Follows spec build order: each section independently testable.

;;;
;;; 1. Bytevector comparator
;;;

(define ~check-disk-000/comparator-equal
  (lambda ()
    (check (= (bytevector-compare #vu8(1 2 3) #vu8(1 2 3)) 0))))

(define ~check-disk-001/comparator-less
  (lambda ()
    (check (= (bytevector-compare #vu8(1 2 3) #vu8(1 2 4)) -1))))

(define ~check-disk-002/comparator-greater
  (lambda ()
    (check (= (bytevector-compare #vu8(1 2 4) #vu8(1 2 3)) 1))))

(define ~check-disk-003/comparator-prefix-shorter
  (lambda ()
    ;; shorter bytevector is smaller when prefix matches
    (check (= (bytevector-compare #vu8(1 2) #vu8(1 2 3)) -1))))

(define ~check-disk-004/comparator-prefix-longer
  (lambda ()
    (check (= (bytevector-compare #vu8(1 2 3) #vu8(1 2)) 1))))

(define ~check-disk-005/comparator-empty
  (lambda ()
    (check (= (bytevector-compare #vu8() #vu8()) 0))
    (check (= (bytevector-compare #vu8() #vu8(1)) -1))
    (check (= (bytevector-compare #vu8(1) #vu8()) 1))))

(define ~check-disk-006/comparator-predicates
  (lambda ()
    (check (bytevector<? #vu8(1) #vu8(2)))
    (check (not (bytevector<? #vu8(2) #vu8(1))))
    (check (not (bytevector<? #vu8(1) #vu8(1))))
    (check (bytevector<=? #vu8(1) #vu8(1)))
    (check (bytevector<=? #vu8(1) #vu8(2)))
    (check (not (bytevector<=? #vu8(2) #vu8(1))))))

;;;
;;; 2. Manifest round-trip
;;;

(define ~check-disk-010/manifest-empty
  (lambda ()
    ;; Manifest with no runs
    (let* ((m (make-aql-manifest 1024 100000 65536 #f 1 '()))
           (bv (aql-manifest->bytevector m))
           (m2 (bytevector->aql-manifest bv)))
      (check (= (aql-manifest-key-max-bytes m2) 1024))
      (check (= (aql-manifest-value-max-bytes m2) 100000))
      (check (= (aql-manifest-block-size m2) 65536))
      (check (not (aql-manifest-encrypted? m2)))
      (check (= (aql-manifest-next-sequence m2) 1))
      (check (null? (aql-manifest-runs m2))))))

(define ~check-disk-011/manifest-with-runs
  (lambda ()
    ;; Manifest with 3 runs, newest first
    (let* ((runs (list (make-aql-manifest-run-entry 3 10)
                       (make-aql-manifest-run-entry 2 20)
                       (make-aql-manifest-run-entry 1 5)))
           (m (make-aql-manifest 512 50000 65536 #t 4 runs))
           (bv (aql-manifest->bytevector m))
           (m2 (bytevector->aql-manifest bv)))
      (check (= (aql-manifest-key-max-bytes m2) 512))
      (check (= (aql-manifest-value-max-bytes m2) 50000))
      (check (aql-manifest-encrypted? m2))
      (check (= (aql-manifest-next-sequence m2) 4))
      (check (= (length (aql-manifest-runs m2)) 3))
      ;; Verify run entries
      (let ((r1 (car (aql-manifest-runs m2)))
            (r2 (cadr (aql-manifest-runs m2)))
            (r3 (caddr (aql-manifest-runs m2))))
        (check (= (aql-manifest-run-entry-sequence-number r1) 3))
        (check (= (aql-manifest-run-entry-block-count r1) 10))
        (check (= (aql-manifest-run-entry-sequence-number r2) 2))
        (check (= (aql-manifest-run-entry-block-count r2) 20))
        (check (= (aql-manifest-run-entry-sequence-number r3) 1))
        (check (= (aql-manifest-run-entry-block-count r3) 5))))))

(define ~check-disk-012/manifest-bytevector-size
  (lambda ()
    ;; Verify exact size: 32 header + 2*8 run entries = 48
    (let* ((runs (list (make-aql-manifest-run-entry 1 10)
                       (make-aql-manifest-run-entry 2 20)))
           (m (make-aql-manifest 1024 100000 65536 #f 3 runs))
           (bv (aql-manifest->bytevector m)))
      (check (= (bytevector-length bv) 48)))))

(define ~check-disk-013/run-filename
  (lambda ()
    (check (string=? (aql-run-filename 1) "run-000001.aql"))
    (check (string=? (aql-run-filename 42) "run-000042.aql"))
    (check (string=? (aql-run-filename 999999) "run-999999.aql"))
    (check (string=? (aql-run-filename 1000000) "run-1000000.aql"))))

;;;
;;; 3. Run file header round-trip
;;;

(define ~check-disk-020/run-header-roundtrip
  (lambda ()
    (let* ((h (make-aql-run-header 1024 100000 65536 42 #f))
           (bv (aql-run-header->bytevector h))
           (h2 (bytevector->aql-run-header bv)))
      (check (= (aql-run-header-key-max-bytes h2) 1024))
      (check (= (aql-run-header-value-max-bytes h2) 100000))
      (check (= (aql-run-header-block-size h2) 65536))
      (check (= (aql-run-header-block-count h2) 42))
      (check (not (aql-run-header-encrypted? h2))))))

(define ~check-disk-021/run-header-encrypted
  (lambda ()
    (let* ((h (make-aql-run-header 512 50000 65536 10 #t))
           (bv (aql-run-header->bytevector h))
           (h2 (bytevector->aql-run-header bv)))
      (check (aql-run-header-encrypted? h2))
      (check (= (aql-run-header-block-count h2) 10)))))

(define ~check-disk-022/run-header-size
  (lambda ()
    ;; Header is exactly 32 bytes
    (let* ((h (make-aql-run-header 1024 100000 65536 1 #f))
           (bv (aql-run-header->bytevector h)))
      (check (= (bytevector-length bv) 32)))))

(define ~check-disk-023/run-stride
  (lambda ()
    ;; Unencrypted stride = block-size
    (let ((h (make-aql-run-header 1024 100000 65536 1 #f)))
      (check (= (aql-run-stride h) 65536)))
    ;; Encrypted stride = block-size + 40
    (let ((h (make-aql-run-header 1024 100000 65536 1 #t)))
      (check (= (aql-run-stride h) 65576)))))

(define ~check-disk-024/block-file-offset
  (lambda ()
    ;; Block 0 starts at offset 32
    (let ((h (make-aql-run-header 1024 100000 65536 10 #f)))
      (check (= (aql-run-block-file-offset h 0) 32))
      (check (= (aql-run-block-file-offset h 1) (+ 32 65536)))
      (check (= (aql-run-block-file-offset h 2) (+ 32 (* 2 65536)))))))

;;;
;;; 4. Block header round-trip
;;;

(define ~check-disk-030/block-header-roundtrip
  (lambda ()
    (let* ((h (make-aql-block-header #vu8(1 2 3) #vu8(10 20 30) 100 5000))
           (bv (aql-block-header->bytevector h))
           (h2 (bytevector->aql-block-header bv)))
      (check (bytevector=? (aql-block-header-min-key h2) #vu8(1 2 3)))
      (check (bytevector=? (aql-block-header-max-key h2) #vu8(10 20 30)))
      (check (= (aql-block-header-key-count h2) 100))
      (check (= (aql-block-header-byte-size h2) 5000)))))

(define ~check-disk-031/block-header-empty-keys
  (lambda ()
    ;; Edge case: empty min/max keys (shouldn't happen in practice, but test round-trip)
    (let* ((h (make-aql-block-header #vu8() #vu8() 0 0))
           (bv (aql-block-header->bytevector h))
           (h2 (bytevector->aql-block-header bv)))
      (check (= (bytevector-length (aql-block-header-min-key h2)) 0))
      (check (= (bytevector-length (aql-block-header-max-key h2)) 0))
      (check (= (aql-block-header-key-count h2) 0))
      (check (= (aql-block-header-byte-size h2) 0)))))

(define ~check-disk-032/block-header-max-size
  (lambda ()
    ;; For key-max-bytes=1024, max header = 1 + 2 + 1024 + 2 + 1024 + 8 + 8 = 2069
    (check (= (aql-block-header-max-size 1024) 2069))))

;;;
;;; 5. KV pair packing round-trip
;;;

(define ~check-disk-040/kv-pair-roundtrip
  (lambda ()
    (let* ((key #vu8(1 2 3))
           (val #vu8(10 20 30 40))
           (packed (aql-pack-kv-pair key val))
           (pairs (aql-unpack-kv-pairs packed 0 (bytevector-length packed))))
      (check (= (length pairs) 1))
      (check (bytevector=? (caar pairs) key))
      (check (bytevector=? (cdar pairs) val)))))

(define ~check-disk-041/kv-pair-multiple
  (lambda ()
    (let* ((k1 #vu8(1)) (v1 #vu8(10))
           (k2 #vu8(2)) (v2 #vu8(20 21))
           (k3 #vu8(3 4)) (v3 #vu8(30))
           (p1 (aql-pack-kv-pair k1 v1))
           (p2 (aql-pack-kv-pair k2 v2))
           (p3 (aql-pack-kv-pair k3 v3))
           ;; Concatenate
           (total (+ (bytevector-length p1)
                     (bytevector-length p2)
                     (bytevector-length p3)))
           (bv (make-bytevector total))
           (_ (begin
                (bytevector-copy! p1 0 bv 0 (bytevector-length p1))
                (bytevector-copy! p2 0 bv (bytevector-length p1) (bytevector-length p2))
                (bytevector-copy! p3 0 bv (+ (bytevector-length p1) (bytevector-length p2))
                                  (bytevector-length p3))))
           (pairs (aql-unpack-kv-pairs bv 0 total)))
      (check (= (length pairs) 3))
      (check (bytevector=? (caar pairs) k1))
      (check (bytevector=? (cdar pairs) v1))
      (check (bytevector=? (car (cadr pairs)) k2))
      (check (bytevector=? (cdr (cadr pairs)) v2))
      (check (bytevector=? (car (caddr pairs)) k3))
      (check (bytevector=? (cdr (caddr pairs)) v3)))))

(define ~check-disk-042/kv-pair-size
  (lambda ()
    ;; size = 2 + key-len + 4 + val-len
    (check (= (aql-kv-pair-size #vu8(1 2 3) #vu8(10 20)) (+ 2 3 4 2)))))

(define ~check-disk-043/tombstone
  (lambda ()
    (check (aql-tombstone? aql-tombstone-value))
    (check (aql-tombstone? #vu8()))
    (check (not (aql-tombstone? #vu8(1))))))

;;;
;;; 6. WAL frame round-trip
;;;

(define ~check-disk-050/wal-set-frame
  (lambda ()
    (let* ((key #vu8(1 2 3))
           (val #vu8(10 20 30 40))
           (frame (aql-wal-frame-set key val))
           (parsed (aql-wal-parse-frames frame)))
      (check (= (length parsed) 1))
      (check (eq? (caar parsed) 'set))
      (check (bytevector=? (cadar parsed) key))
      (check (bytevector=? (cddar parsed) val)))))

(define ~check-disk-051/wal-remove-frame
  (lambda ()
    (let* ((key #vu8(5 6 7))
           (frame (aql-wal-frame-remove key))
           (parsed (aql-wal-parse-frames frame)))
      (check (= (length parsed) 1))
      (check (eq? (caar parsed) 'remove))
      (check (bytevector=? (cadar parsed) key)))))

(define ~check-disk-052/wal-multiple-frames
  (lambda ()
    ;; Concatenate set + remove + set frames
    (let* ((f1 (aql-wal-frame-set #vu8(1) #vu8(10)))
           (f2 (aql-wal-frame-remove #vu8(2)))
           (f3 (aql-wal-frame-set #vu8(3) #vu8(30 31)))
           (total (+ (bytevector-length f1)
                     (bytevector-length f2)
                     (bytevector-length f3)))
           (bv (make-bytevector total))
           (_ (begin
                (bytevector-copy! f1 0 bv 0 (bytevector-length f1))
                (bytevector-copy! f2 0 bv (bytevector-length f1) (bytevector-length f2))
                (bytevector-copy! f3 0 bv (+ (bytevector-length f1) (bytevector-length f2))
                                  (bytevector-length f3))))
           (parsed (aql-wal-parse-frames bv)))
      (check (= (length parsed) 3))
      (check (eq? (caar parsed) 'set))
      (check (bytevector=? (cadar parsed) #vu8(1)))
      (check (bytevector=? (cddar parsed) #vu8(10)))
      (check (eq? (caadr parsed) 'remove))
      (check (bytevector=? (cadadr parsed) #vu8(2)))
      (check (eq? (caaddr parsed) 'set))
      (check (bytevector=? (car (cdaddr parsed)) #vu8(3)))
      (check (bytevector=? (cdr (cdaddr parsed)) #vu8(30 31))))))

;;;
;;; 7. Block index search
;;;

(define ~check-disk-060/block-index-empty
  (lambda ()
    (let ((idx (aql-block-index-empty)))
      (check (= (aql-block-index-search idx #vu8(1)) 0)))))

(define ~check-disk-061/block-index-search-single
  (lambda ()
    ;; Single block: min=\x01, max=\x0a
    (let* ((hdr (make-aql-block-header #vu8(1) #vu8(10) 5 100))
           (entry (make-aql-block-index-entry hdr 32))
           (idx (make-aql-block-index (list entry))))
      ;; Key \x05 is within block range → position 0
      (check (= (aql-block-index-search idx #vu8(5)) 0))
      ;; Key \x01 is at min → position 0
      (check (= (aql-block-index-search idx #vu8(1)) 0))
      ;; Key \x0b is past the only block → position 1
      (check (= (aql-block-index-search idx #vu8(11)) 1)))))

(define ~check-disk-062/block-index-search-multiple
  (lambda ()
    ;; Three blocks: [1,5], [6,10], [11,15]
    (let* ((h1 (make-aql-block-header #vu8(1) #vu8(5) 3 60))
           (h2 (make-aql-block-header #vu8(6) #vu8(10) 3 60))
           (h3 (make-aql-block-header #vu8(11) #vu8(15) 3 60))
           (e1 (make-aql-block-index-entry h1 32))
           (e2 (make-aql-block-index-entry h2 (+ 32 65536)))
           (e3 (make-aql-block-index-entry h3 (+ 32 (* 2 65536))))
           (idx (make-aql-block-index (list e1 e2 e3))))
      ;; Key in first block
      (check (= (aql-block-index-search idx #vu8(3)) 0))
      ;; Key in second block
      (check (= (aql-block-index-search idx #vu8(8)) 1))
      ;; Key in third block
      (check (= (aql-block-index-search idx #vu8(13)) 2))
      ;; Key past all blocks
      (check (= (aql-block-index-search idx #vu8(20)) 3)))))

;;;
;;; 8. Key distance
;;;

(define ~check-disk-070/key-distance-equal
  (lambda ()
    (check (= (aql-key-byte-distance #vu8(1 2 3) #vu8(1 2 3)) 0))))

(define ~check-disk-071/key-distance-first-byte
  (lambda ()
    ;; Differ at byte 0: distance is based on u64 extraction
    (let ((d (aql-key-byte-distance #vu8(0) #vu8(1))))
      (check (> d 0)))))

(define ~check-disk-072/key-distance-shared-prefix
  (lambda ()
    ;; Same prefix, differ at byte 2
    (let ((d (aql-key-byte-distance #vu8(1 2 3) #vu8(1 2 5))))
      (check (> d 0)))))

(define ~check-disk-073/key-distance-different-lengths
  (lambda ()
    ;; Different lengths with shared prefix
    (let ((d (aql-key-byte-distance #vu8(1 2) #vu8(1 2 3))))
      (check (> d 0)))))

;;;
;;; 9. Approximate counts
;;;

(define ~check-disk-080/approx-count-empty-index
  (lambda ()
    (let ((idx (aql-block-index-empty)))
      (check (= (aql-approximate-key-count-range idx #vu8(0) #vu8(255)) 0))
      (check (= (aql-approximate-byte-count-range idx #vu8(0) #vu8(255)) 0)))))

(define ~check-disk-081/approx-count-fully-contained
  (lambda ()
    ;; Single block [1,10] with 100 keys, 5000 bytes.
    ;; Query [0,20) fully contains the block.
    (let* ((hdr (make-aql-block-header #vu8(1) #vu8(10) 100 5000))
           (entry (make-aql-block-index-entry hdr 32))
           (idx (make-aql-block-index (list entry))))
      (check (= (aql-approximate-key-count-range idx #vu8(0) #vu8(20)) 100))
      (check (= (aql-approximate-byte-count-range idx #vu8(0) #vu8(20)) 5000)))))

(define ~check-disk-082/approx-count-outside
  (lambda ()
    ;; Block [10,20]. Query [0,5) is entirely before.
    (let* ((hdr (make-aql-block-header #vu8(10) #vu8(20) 100 5000))
           (entry (make-aql-block-index-entry hdr 32))
           (idx (make-aql-block-index (list entry))))
      (check (= (aql-approximate-key-count-range idx #vu8(0) #vu8(5)) 0)))))

(define ~check-disk-083/approx-count-total
  (lambda ()
    ;; Two "runs" with known block counts
    (let* ((h1 (make-aql-block-header #vu8(1) #vu8(5) 50 2000))
           (h2 (make-aql-block-header #vu8(6) #vu8(10) 30 1500))
           (e1 (make-aql-block-index-entry h1 32))
           (e2 (make-aql-block-index-entry h2 (+ 32 65536)))
           (idx1 (make-aql-block-index (list e1)))
           (idx2 (make-aql-block-index (list e2)))
           (run1 (make-aql-run 1 #f (make-aql-run-header 1024 100000 65536 1 #f) idx1))
           (run2 (make-aql-run 2 #f (make-aql-run-header 1024 100000 65536 1 #f) idx2)))
      (check (= (aql-approximate-key-count-total (list run1 run2)) 80))
      (check (= (aql-approximate-byte-count-total (list run1 run2)) 3500)))))

;;;
;;; 10. Block packing round-trip
;;;

(define ~check-disk-090/pack-single-block
  (lambda ()
    ;; Pack 3 small kv pairs into one block
    (let* ((pairs (list (cons #vu8(1) #vu8(10))
                        (cons #vu8(2) #vu8(20))
                        (cons #vu8(3) #vu8(30))))
           (block-size 4096)
           (key-max 256))
      (call-with-values
        (lambda () (aql-pack-block key-max block-size pairs))
        (lambda (block count)
          (check block)
          (check (= count 3))
          (check (= (bytevector-length block) block-size))
          ;; Unpack and verify
          (call-with-values
            (lambda () (aql-unpack-block block))
            (lambda (header unpacked-pairs)
              (check (= (aql-block-header-key-count header) 3))
              (check (bytevector=? (aql-block-header-min-key header) #vu8(1)))
              (check (bytevector=? (aql-block-header-max-key header) #vu8(3)))
              (check (= (length unpacked-pairs) 3))
              (check (bytevector=? (caar unpacked-pairs) #vu8(1)))
              (check (bytevector=? (cdar unpacked-pairs) #vu8(10)))
              (check (bytevector=? (car (cadr unpacked-pairs)) #vu8(2)))
              (check (bytevector=? (car (caddr unpacked-pairs)) #vu8(3))))))))))

(define ~check-disk-091/pack-block-overflow
  (lambda ()
    ;; Fill a small block to test overflow
    (let* ((block-size 128)
           (key-max 16)
           ;; Each pair: 2 + 8 + 4 + 8 = 22 bytes
           ;; Header reserve: 1 + 2 + 16 + 2 + 16 + 8 + 8 = 53 bytes
           ;; Available: 128 - 53 = 75 bytes → fits 3 pairs (66 bytes), not 4
           (pairs (list (cons #vu8(0 0 0 0 0 0 0 1) #vu8(10 10 10 10 10 10 10 10))
                        (cons #vu8(0 0 0 0 0 0 0 2) #vu8(20 20 20 20 20 20 20 20))
                        (cons #vu8(0 0 0 0 0 0 0 3) #vu8(30 30 30 30 30 30 30 30))
                        (cons #vu8(0 0 0 0 0 0 0 4) #vu8(40 40 40 40 40 40 40 40)))))
      (call-with-values
        (lambda () (aql-pack-block key-max block-size pairs))
        (lambda (block count)
          (check block)
          ;; Should fit 3 pairs (not 4)
          (check (= count 3))
          ;; Verify min/max keys
          (call-with-values
            (lambda () (aql-unpack-block block))
            (lambda (header unpacked-pairs)
              (check (= (length unpacked-pairs) 3))
              (check (bytevector=? (aql-block-header-min-key header)
                                   #vu8(0 0 0 0 0 0 0 1)))
              (check (bytevector=? (aql-block-header-max-key header)
                                   #vu8(0 0 0 0 0 0 0 3))))))))))

(define ~check-disk-092/block-search-key
  (lambda ()
    ;; Pack pairs, then search for specific keys
    (let* ((pairs (list (cons #vu8(1) #vu8(10))
                        (cons #vu8(3) #vu8(30))
                        (cons #vu8(5) #vu8(50))
                        (cons #vu8(7) #vu8(70))))
           (block-size 4096)
           (key-max 256))
      (call-with-values
        (lambda () (aql-pack-block key-max block-size pairs))
        (lambda (block count)
          (let ((header (bytevector->aql-block-header block)))
            ;; Find existing key
            (let ((v (aql-block-search-key block #vu8(3) header)))
              (check v)
              (check (bytevector=? v #vu8(30))))
            ;; Find first key
            (let ((v (aql-block-search-key block #vu8(1) header)))
              (check v)
              (check (bytevector=? v #vu8(10))))
            ;; Find last key
            (let ((v (aql-block-search-key block #vu8(7) header)))
              (check v)
              (check (bytevector=? v #vu8(70))))
            ;; Key not present (between existing keys)
            (check (not (aql-block-search-key block #vu8(4) header)))
            ;; Key not present (before all)
            (check (not (aql-block-search-key block #vu8(0) header)))
            ;; Key not present (after all)
            (check (not (aql-block-search-key block #vu8(9) header)))))))))

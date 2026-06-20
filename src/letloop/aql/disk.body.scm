;; Copyright © 2024-2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; AQL Block Storage Layer — LSM tree with sorted runs on disk.
;;
;; Build order (each section independently testable):
;;  1. Bytevector comparator
;;  2. Manifest read/write
;;  3. Run file header read/write
;;  4. Block header read/write
;;  5. KV pair packing
;;  6. WAL frame serialization
;;  7. Block index (per-run, in memory)
;;  8. Run handle
;;  9. Key distance + approximate counts
;; 10. Buffer cache + block I/O + encryption
;; 11. Block serialization (BST → blocks for a new run)
;; 12. Read path (point lookup)
;; 13. Range query (across runs)
;; 14. Compaction
;; 15. Startup / open
;; 16. Write path

;;;
;;; Section 0 — Prerequisites: POSIX constants, database handle, io_uring helper
;;;

(define %AT_FDCWD -100)
(define %O_RDONLY 0)
(define %O_WRONLY 1)
(define %O_RDWR   2)
(define %O_CREAT  64)
(define %O_TRUNC  512)
(define %iovec-size 16)  ;; sizeof(struct iovec) on x86_64

(define %flush-threshold (* 4 1024 1024))  ;; 4 MB BST size triggers flush
(define %compaction-threshold 8)            ;; 8 runs triggers compaction

(define-record-type (<aql-disk-handle> make-aql-disk-handle aql-disk-handle?)
  (nongenerative <aql-disk-handle>)
  (fields (immutable dirpath        aql-disk-handle-dirpath)
          (mutable   manifest       aql-disk-handle-manifest aql-disk-handle-manifest!)
          (mutable   runs           aql-disk-handle-runs aql-disk-handle-runs!)
          (mutable   bst            aql-disk-handle-bst aql-disk-handle-bst!)
          (mutable   wal-fd         aql-disk-handle-wal-fd aql-disk-handle-wal-fd!)
          (mutable   wal-offset     aql-disk-handle-wal-offset aql-disk-handle-wal-offset!)
          (immutable encryption-key aql-disk-handle-encryption-key)
          (immutable buffer-cache   aql-disk-handle-buffer-cache)
          (immutable ring           aql-disk-handle-ring)
          (immutable cqe-ptr        aql-disk-handle-cqe-ptr)))

(define (uring-do ring cqe-ptr prep-thunk)
  ;; Get SQE, apply prep-thunk, submit, wait for CQE, return result.
  (let ((sqe (io-uring-get-sqe ring)))
    (when (zero? sqe)
      (error 'uring-do "no SQE available"))
    (prep-thunk sqe)
    (let ((rc (io-uring-submit ring)))
      (when (fx<? rc 0)
        (error 'uring-do "submit failed" (strerror (fx- 0 rc)))))
    (let ((rc (io-uring-wait-cqe ring cqe-ptr)))
      (when (fx<? rc 0)
        (error 'uring-do "wait-cqe failed" (strerror (fx- 0 rc)))))
    (let* ((cqe (foreign-ref 'void* cqe-ptr 0))
           (res (io-uring-cqe-get-res cqe)))
      (io-uring-cqe-seen ring cqe)
      res)))

;;;
;;; Section 1 — Bytevector Comparator
;;;

(define (bytevector-compare a b)
  (let ((len-a (bytevector-length a))
        (len-b (bytevector-length b)))
    (let ((limit (fxmin len-a len-b)))
      (let loop ((i 0))
        (cond
          ((fx= i limit)
           (cond
             ((fx< len-a len-b) -1)
             ((fx= len-a len-b) 0)
             (else 1)))
          (else
           (let ((ba (bytevector-u8-ref a i))
                 (bb (bytevector-u8-ref b i)))
             (cond
               ((fx< ba bb) -1)
               ((fx> ba bb) 1)
               (else (loop (fx+ i 1)))))))))))

(define (bytevector<? a b)
  (fx= (bytevector-compare a b) -1))

(define (bytevector<=? a b)
  (fx<= (bytevector-compare a b) 0))

;;;
;;; Section 2 — Manifest (binary format)
;;;

(define aql-manifest-magic #vu8(97 113 109 0))  ;; "aqm\0"
(define aql-manifest-version 1)
(define aql-manifest-header-size 32)
(define aql-manifest-run-entry-size 8)

(define-record-type* <aql-manifest>
  (make-aql-manifest key-max-bytes value-max-bytes
                     block-size encrypted?
                     next-sequence runs)
  aql-manifest?
  (key-max-bytes   aql-manifest-key-max-bytes)
  (value-max-bytes aql-manifest-value-max-bytes)
  (block-size      aql-manifest-block-size)
  (encrypted?      aql-manifest-encrypted?)
  (next-sequence   aql-manifest-next-sequence)
  (runs            aql-manifest-runs))  ;; list of <aql-manifest-run-entry>, newest first

(define-record-type* <aql-manifest-run-entry>
  (make-aql-manifest-run-entry sequence-number block-count)
  aql-manifest-run-entry?
  (sequence-number aql-manifest-run-entry-sequence-number)
  (block-count     aql-manifest-run-entry-block-count))

(define (aql-run-filename sequence-number)
  ;; Returns string like "run-000042.aql"
  (string-append "run-"
    (let ((s (number->string sequence-number)))
      (string-append (make-string (max 0 (- 6 (string-length s))) #\0) s))
    ".aql"))

(define (aql-manifest->bytevector manifest)
  (let* ((runs (aql-manifest-runs manifest))
         (run-count (length runs))
         (total (+ aql-manifest-header-size
                   (* run-count aql-manifest-run-entry-size)))
         (bv (make-bytevector total 0)))
    ;; header
    (bytevector-copy! aql-manifest-magic 0 bv 0 4)
    (bytevector-u8-set! bv 4 aql-manifest-version)
    (bytevector-u16-set! bv 8 (aql-manifest-key-max-bytes manifest) (endianness big))
    (bytevector-u32-set! bv 12 (aql-manifest-value-max-bytes manifest) (endianness big))
    (bytevector-u32-set! bv 16 (aql-manifest-block-size manifest) (endianness big))
    (bytevector-u8-set! bv 20 (if (aql-manifest-encrypted? manifest) #x01 #x00))
    (bytevector-u32-set! bv 24 (aql-manifest-next-sequence manifest) (endianness big))
    (bytevector-u32-set! bv 28 run-count (endianness big))
    ;; run entries
    (let loop ((runs runs) (pos aql-manifest-header-size))
      (unless (null? runs)
        (let ((entry (car runs)))
          (bytevector-u32-set! bv pos
            (aql-manifest-run-entry-sequence-number entry) (endianness big))
          (bytevector-u32-set! bv (+ pos 4)
            (aql-manifest-run-entry-block-count entry) (endianness big))
          (loop (cdr runs) (+ pos aql-manifest-run-entry-size)))))
    bv))

(define (bytevector->aql-manifest bv)
  (unless (>= (bytevector-length bv) aql-manifest-header-size)
    (error 'bytevector->aql-manifest "too short" (bytevector-length bv)))
  (unless (and (= (bytevector-u8-ref bv 0) 97)
               (= (bytevector-u8-ref bv 1) 113)
               (= (bytevector-u8-ref bv 2) 109)
               (= (bytevector-u8-ref bv 3) 0))
    (error 'bytevector->aql-manifest "bad magic"))
  (let ((version (bytevector-u8-ref bv 4)))
    (unless (= version aql-manifest-version)
      (error 'bytevector->aql-manifest "unsupported version" version))
    (let* ((key-max-bytes (bytevector-u16-ref bv 8 (endianness big)))
           (value-max-bytes (bytevector-u32-ref bv 12 (endianness big)))
           (block-size (bytevector-u32-ref bv 16 (endianness big)))
           (encrypted? (= (bytevector-u8-ref bv 20) #x01))
           (next-sequence (bytevector-u32-ref bv 24 (endianness big)))
           (run-count (bytevector-u32-ref bv 28 (endianness big)))
           (runs (let loop ((i 0) (pos aql-manifest-header-size) (acc '()))
                   (if (= i run-count)
                       (reverse acc)
                       (let ((seq (bytevector-u32-ref bv pos (endianness big)))
                             (bc (bytevector-u32-ref bv (+ pos 4) (endianness big))))
                         (loop (+ i 1)
                               (+ pos aql-manifest-run-entry-size)
                               (cons (make-aql-manifest-run-entry seq bc) acc)))))))
      (make-aql-manifest key-max-bytes value-max-bytes
                         block-size encrypted?
                         next-sequence runs))))

(define (aql-manifest-write! dirpath manifest ring cqe-ptr)
  ;; Atomic write: write to temp file, fsync, rename over manifest.aql, fsync dir.
  (let* ((bv (aql-manifest->bytevector manifest))
         (tmp-path (string-append dirpath "/manifest.aql.tmp"))
         (final-path (string-append dirpath "/manifest.aql"))
         (flags (fxlogor %O_WRONLY (fxlogor %O_CREAT %O_TRUNC)))
         ;; Open temp file
         (fd (uring-do ring cqe-ptr
               (lambda (sqe)
                 (io-uring-prep-openat sqe %AT_FDCWD tmp-path flags #o644)))))
    (when (fx<? fd 0)
      (error 'aql-manifest-write! "open temp failed" (strerror (fx- 0 fd))))
    ;; Write manifest data
    (with-lock (list bv)
      (let ((res (uring-do ring cqe-ptr
                   (lambda (sqe)
                     (io-uring-prep-write sqe fd (bytevector-pointer bv)
                                          (bytevector-length bv) 0)))))
        (when (fx<? res 0)
          (error 'aql-manifest-write! "write failed" (strerror (fx- 0 res))))))
    ;; Fsync temp file
    (let ((res (uring-do ring cqe-ptr
                 (lambda (sqe) (io-uring-prep-fsync sqe fd 0)))))
      (when (fx<? res 0)
        (error 'aql-manifest-write! "fsync failed" (strerror (fx- 0 res)))))
    ;; Close temp file
    (let ((res (uring-do ring cqe-ptr
                 (lambda (sqe) (io-uring-prep-close sqe fd)))))
      (when (fx<? res 0)
        (error 'aql-manifest-write! "close failed" (strerror (fx- 0 res)))))
    ;; Rename temp -> final (atomic)
    (let ((res (uring-do ring cqe-ptr
                 (lambda (sqe)
                   (io-uring-prep-renameat sqe %AT_FDCWD tmp-path
                                           %AT_FDCWD final-path 0)))))
      (when (fx<? res 0)
        (error 'aql-manifest-write! "rename failed" (strerror (fx- 0 res)))))
    ;; Fsync directory
    (let ((dir-fd (uring-do ring cqe-ptr
                    (lambda (sqe)
                      (io-uring-prep-openat sqe %AT_FDCWD dirpath %O_RDONLY #o0)))))
      (when (fx>=? dir-fd 0)
        (uring-do ring cqe-ptr
          (lambda (sqe) (io-uring-prep-fsync sqe dir-fd 0)))
        (uring-do ring cqe-ptr
          (lambda (sqe) (io-uring-prep-close sqe dir-fd)))))))

;;;
;;; Section 3 — Run File Format
;;;

(define aql-magic #vu8(97 113 108 0))  ;; "aql\0"
(define aql-version 1)
(define aql-run-header-size 32)
(define aql-default-block-size 65536)
(define aql-crypto-overhead 40)  ;; 24 nonce + 16 tag

(define-record-type* <aql-run-header>
  (make-aql-run-header key-max-bytes value-max-bytes
                       block-size block-count encrypted?)
  aql-run-header?
  (key-max-bytes   aql-run-header-key-max-bytes)
  (value-max-bytes aql-run-header-value-max-bytes)
  (block-size      aql-run-header-block-size)
  (block-count     aql-run-header-block-count)
  (encrypted?      aql-run-header-encrypted?))

(define (aql-run-stride header)
  (if (aql-run-header-encrypted? header)
      (+ (aql-run-header-block-size header) aql-crypto-overhead)
      (aql-run-header-block-size header)))

(define (aql-run-block-file-offset header block-index)
  (+ aql-run-header-size (* block-index (aql-run-stride header))))

(define (aql-run-header->bytevector header)
  (let ((bv (make-bytevector aql-run-header-size 0)))
    (bytevector-copy! aql-magic 0 bv 0 4)
    (bytevector-u8-set! bv 4 aql-version)
    (bytevector-u16-set! bv 8 (aql-run-header-key-max-bytes header) (endianness big))
    (bytevector-u32-set! bv 12 (aql-run-header-value-max-bytes header) (endianness big))
    (bytevector-u32-set! bv 16 (aql-run-header-block-size header) (endianness big))
    (bytevector-u32-set! bv 20 (aql-run-header-block-count header) (endianness big))
    (bytevector-u8-set! bv 24 (if (aql-run-header-encrypted? header) #x01 #x00))
    bv))

(define (bytevector->aql-run-header bv)
  (unless (>= (bytevector-length bv) aql-run-header-size)
    (error 'bytevector->aql-run-header "header too short" (bytevector-length bv)))
  (unless (and (= (bytevector-u8-ref bv 0) 97)
               (= (bytevector-u8-ref bv 1) 113)
               (= (bytevector-u8-ref bv 2) 108)
               (= (bytevector-u8-ref bv 3) 0))
    (error 'bytevector->aql-run-header "bad magic"))
  (let ((version (bytevector-u8-ref bv 4)))
    (unless (= version aql-version)
      (error 'bytevector->aql-run-header "unsupported version" version))
    (make-aql-run-header
      (bytevector-u16-ref bv 8 (endianness big))
      (bytevector-u32-ref bv 12 (endianness big))
      (bytevector-u32-ref bv 16 (endianness big))
      (bytevector-u32-ref bv 20 (endianness big))
      (= (bytevector-u8-ref bv 24) #x01))))

;;;
;;; Section 4 — Block Format
;;;

(define aql-block-tag-data #x01)

(define-record-type* <aql-block-header>
  (make-aql-block-header min-key max-key key-count byte-size)
  aql-block-header?
  (min-key    aql-block-header-min-key)
  (max-key    aql-block-header-max-key)
  (key-count  aql-block-header-key-count)
  (byte-size  aql-block-header-byte-size))

(define (aql-block-header-max-size key-max-bytes)
  ;; Worst-case block header size for reserving space during packing
  (+ 1 2 key-max-bytes 2 key-max-bytes 8 8))

(define (aql-block-header->bytevector header)
  (let* ((min-key (aql-block-header-min-key header))
         (max-key (aql-block-header-max-key header))
         (min-len (bytevector-length min-key))
         (max-len (bytevector-length max-key))
         (total (+ 1 2 min-len 2 max-len 8 8))
         (bv (make-bytevector total 0))
         (pos 0))
    (bytevector-u8-set! bv pos aql-block-tag-data)
    (set! pos (+ pos 1))
    (bytevector-u16-set! bv pos min-len (endianness big))
    (set! pos (+ pos 2))
    (bytevector-copy! min-key 0 bv pos min-len)
    (set! pos (+ pos min-len))
    (bytevector-u16-set! bv pos max-len (endianness big))
    (set! pos (+ pos 2))
    (bytevector-copy! max-key 0 bv pos max-len)
    (set! pos (+ pos max-len))
    (bytevector-u64-set! bv pos (aql-block-header-key-count header) (endianness big))
    (set! pos (+ pos 8))
    (bytevector-u64-set! bv pos (aql-block-header-byte-size header) (endianness big))
    bv))

(define (bytevector->aql-block-header bv)
  (unless (>= (bytevector-length bv) 1)
    (error 'bytevector->aql-block-header "empty"))
  (unless (= (bytevector-u8-ref bv 0) aql-block-tag-data)
    (error 'bytevector->aql-block-header "not a data block"
           (bytevector-u8-ref bv 0)))
  (let* ((pos 1)
         (min-len (bytevector-u16-ref bv pos (endianness big)))
         (pos (+ pos 2))
         (min-key (let ((k (make-bytevector min-len)))
                    (bytevector-copy! bv pos k 0 min-len)
                    k))
         (pos (+ pos min-len))
         (max-len (bytevector-u16-ref bv pos (endianness big)))
         (pos (+ pos 2))
         (max-key (let ((k (make-bytevector max-len)))
                    (bytevector-copy! bv pos k 0 max-len)
                    k))
         (pos (+ pos max-len))
         (key-count (bytevector-u64-ref bv pos (endianness big)))
         (pos (+ pos 8))
         (byte-size (bytevector-u64-ref bv pos (endianness big))))
    (make-aql-block-header min-key max-key key-count byte-size)))

;;;
;;; Section 5 — WAL Format
;;;

(define aql-wal-tag-set    #x02)
(define aql-wal-tag-remove #x03)

(define (aql-wal-frame-set key value)
  (let* ((key-len (bytevector-length key))
         (val-len (bytevector-length value))
         (total (+ 1 2 key-len 4 val-len))
         (bv (make-bytevector total 0))
         (pos 0))
    (bytevector-u8-set! bv pos aql-wal-tag-set)
    (set! pos (+ pos 1))
    (bytevector-u16-set! bv pos key-len (endianness big))
    (set! pos (+ pos 2))
    (bytevector-copy! key 0 bv pos key-len)
    (set! pos (+ pos key-len))
    (bytevector-u32-set! bv pos val-len (endianness big))
    (set! pos (+ pos 4))
    (bytevector-copy! value 0 bv pos val-len)
    bv))

(define (aql-wal-frame-remove key)
  (let* ((key-len (bytevector-length key))
         (total (+ 1 2 key-len))
         (bv (make-bytevector total 0))
         (pos 0))
    (bytevector-u8-set! bv pos aql-wal-tag-remove)
    (set! pos (+ pos 1))
    (bytevector-u16-set! bv pos key-len (endianness big))
    (set! pos (+ pos 2))
    (bytevector-copy! key 0 bv pos key-len)
    bv))

(define (aql-wal-parse-frames bv)
  ;; Parse a bytevector containing concatenated WAL frames.
  ;; Returns a list of (tag key . value-or-#f) entries.
  (let ((len (bytevector-length bv)))
    (let loop ((pos 0) (acc '()))
      (if (>= pos len)
          (reverse acc)
          (let ((tag (bytevector-u8-ref bv pos)))
            (cond
              ((= tag aql-wal-tag-set)
               (let* ((pos (+ pos 1))
                      (key-len (bytevector-u16-ref bv pos (endianness big)))
                      (pos (+ pos 2))
                      (key (let ((k (make-bytevector key-len)))
                             (bytevector-copy! bv pos k 0 key-len)
                             k))
                      (pos (+ pos key-len))
                      (val-len (bytevector-u32-ref bv pos (endianness big)))
                      (pos (+ pos 4))
                      (value (let ((v (make-bytevector val-len)))
                               (bytevector-copy! bv pos v 0 val-len)
                               v))
                      (pos (+ pos val-len)))
                 (loop pos (cons (cons* 'set key value) acc))))
              ((= tag aql-wal-tag-remove)
               (let* ((pos (+ pos 1))
                      (key-len (bytevector-u16-ref bv pos (endianness big)))
                      (pos (+ pos 2))
                      (key (let ((k (make-bytevector key-len)))
                             (bytevector-copy! bv pos k 0 key-len)
                             k))
                      (pos (+ pos key-len)))
                 (loop pos (cons (cons* 'remove key #f) acc))))
              (else
               (error 'aql-wal-parse-frames "unknown WAL tag" tag))))))))

;;;
;;; Section 6 — KV Pair Packing
;;;

(define (aql-pack-kv-pair key value)
  ;; Returns bytevector: [key-len u16][key][value-len u32][value]
  (let* ((key-len (bytevector-length key))
         (val-len (bytevector-length value))
         (total (+ 2 key-len 4 val-len))
         (bv (make-bytevector total 0))
         (pos 0))
    (bytevector-u16-set! bv pos key-len (endianness big))
    (set! pos (+ pos 2))
    (bytevector-copy! key 0 bv pos key-len)
    (set! pos (+ pos key-len))
    (bytevector-u32-set! bv pos val-len (endianness big))
    (set! pos (+ pos 4))
    (bytevector-copy! value 0 bv pos val-len)
    bv))

(define (aql-kv-pair-size key value)
  (+ 2 (bytevector-length key) 4 (bytevector-length value)))

(define (aql-tombstone? value)
  ;; Zero-length value = tombstone (deleted key)
  (= (bytevector-length value) 0))

(define aql-tombstone-value (bytevector))

(define (aql-unpack-kv-pairs bv start end)
  ;; Parse kv pairs from bv[start..end).
  ;; Returns list of (key . value) pairs in order.
  (let loop ((pos start) (acc '()))
    (if (>= pos end)
        (reverse acc)
        (let* ((key-len (bytevector-u16-ref bv pos (endianness big)))
               (pos (+ pos 2))
               (key (let ((k (make-bytevector key-len)))
                      (bytevector-copy! bv pos k 0 key-len)
                      k))
               (pos (+ pos key-len))
               (val-len (bytevector-u32-ref bv pos (endianness big)))
               (pos (+ pos 4))
               (value (let ((v (make-bytevector val-len)))
                        (bytevector-copy! bv pos v 0 val-len)
                        v))
               (pos (+ pos val-len)))
          (loop pos (cons (cons key value) acc))))))

;;;
;;; Section 7 — Block Index (per run, in memory)
;;;

(define-record-type* <aql-block-index-entry>
  (make-aql-block-index-entry header file-offset)
  aql-block-index-entry?
  (header      aql-block-index-entry-header)
  (file-offset aql-block-index-entry-file-offset))

(define (make-aql-block-index entries)
  ;; entries: list of <aql-block-index-entry>
  ;; returns: sorted vector by min-key
  (let ((vec (list->vector entries)))
    (vector-sort!
      (lambda (a b)
        (bytevector<?
          (aql-block-header-min-key (aql-block-index-entry-header a))
          (aql-block-header-min-key (aql-block-index-entry-header b))))
      vec)
    vec))

(define (aql-block-index-empty)
  (vector))

(define (aql-block-index-search index key)
  ;; Returns position of first block whose max-key >= key,
  ;; or (vector-length index) if none.
  (let ((len (vector-length index)))
    (let loop ((lo 0) (hi len))
      (if (fx>= lo hi)
          lo
          (let* ((mid (fxsra (fx+ lo hi) 1))
                 (entry (vector-ref index mid))
                 (max-key (aql-block-header-max-key
                            (aql-block-index-entry-header entry))))
            (if (bytevector<? max-key key)
                (loop (fx+ mid 1) hi)
                (loop lo mid)))))))

;;;
;;; Section 8 — Run Handle
;;;

(define-record-type* <aql-run>
  (make-aql-run sequence-number fd header block-index)
  aql-run?
  (sequence-number aql-run-sequence-number)
  (fd              aql-run-fd)
  (header          aql-run-header)
  (block-index     aql-run-block-index))

;;;
;;; Section 9 — Key Distance (for interpolation in approximate counts)
;;;

(define (aql-key-extract-u64 bv start)
  (let ((buf (make-bytevector 8 0))
        (n (fxmin 8 (fxmax 0 (fx- (bytevector-length bv) start)))))
    (when (fx> n 0)
      (bytevector-copy! bv start buf 0 n))
    (bytevector-u64-ref buf 0 (endianness big))))

(define (aql-key-tail-distance bv start n)
  (aql-key-extract-u64 bv start))

(define (aql-key-distance-from a b start)
  (let ((va (aql-key-extract-u64 a start))
        (vb (aql-key-extract-u64 b start)))
    (abs (- vb va))))

(define (aql-key-byte-distance a b)
  ;; Skip shared prefix, compute distance from first differing
  ;; byte using up to 8 bytes of context.
  (let ((len-a (bytevector-length a))
        (len-b (bytevector-length b))
        (limit (fxmin (bytevector-length a) (bytevector-length b))))
    (let loop ((i 0))
      (cond
        ((fx= i limit)
         (if (fx= len-a len-b)
             0
             (let ((longer (if (fx> len-a len-b) a b))
                   (extra (fx- (fxmax len-a len-b) limit)))
               (aql-key-tail-distance longer limit (fxmin extra 8)))))
        ((not (fx= (bytevector-u8-ref a i) (bytevector-u8-ref b i)))
         (aql-key-distance-from a b i))
        (else (loop (fx+ i 1)))))))

;;;
;;; Section 10 — Approximate Counts
;;;

;; Per-run counts

(define (aql-run-approximate-key-count run start-key end-key)
  (aql-approximate-key-count-range
    (aql-run-block-index run) start-key end-key))

(define (aql-run-approximate-byte-count run start-key end-key)
  (aql-approximate-byte-count-range
    (aql-run-block-index run) start-key end-key))

(define (aql-interpolate-count header start-key end-key)
  (let* ((min-key (aql-block-header-min-key header))
         (max-key (aql-block-header-max-key header))
         (key-count (aql-block-header-key-count header))
         (block-span (aql-key-byte-distance min-key max-key))
         (effective-start (if (bytevector<? start-key min-key) min-key start-key))
         (effective-end (if (bytevector<? max-key end-key) max-key end-key))
         (range-span (aql-key-byte-distance effective-start effective-end)))
    (if (zero? block-span)
        key-count
        (let ((fraction (/ range-span block-span)))
          (exact (round (* fraction key-count)))))))

(define (aql-approximate-key-count-range index start-key end-key)
  (let ((len (vector-length index)))
    (if (fx= len 0)
        0
        (let ((first (aql-block-index-search index start-key)))
          (let loop ((i first) (count 0))
            (if (fx>= i len)
                count
                (let* ((entry (vector-ref index i))
                       (header (aql-block-index-entry-header entry))
                       (min-key (aql-block-header-min-key header))
                       (max-key (aql-block-header-max-key header))
                       (key-count (aql-block-header-key-count header)))
                  (if (bytevector<=? end-key min-key)
                      count
                      (if (and (bytevector<=? start-key min-key)
                               (bytevector<? max-key end-key))
                          (loop (fx+ i 1) (+ count key-count))
                          (loop (fx+ i 1)
                                (+ count
                                   (aql-interpolate-count
                                     header start-key end-key))))))))))))

(define (aql-interpolate-byte-size header start-key end-key)
  (let* ((min-key (aql-block-header-min-key header))
         (max-key (aql-block-header-max-key header))
         (byte-size (aql-block-header-byte-size header))
         (block-span (aql-key-byte-distance min-key max-key))
         (effective-start (if (bytevector<? start-key min-key) min-key start-key))
         (effective-end (if (bytevector<? max-key end-key) max-key end-key))
         (range-span (aql-key-byte-distance effective-start effective-end)))
    (if (zero? block-span)
        byte-size
        (let ((fraction (/ range-span block-span)))
          (exact (round (* fraction byte-size)))))))

(define (aql-approximate-byte-count-range index start-key end-key)
  (let ((len (vector-length index)))
    (if (fx= len 0)
        0
        (let ((first (aql-block-index-search index start-key)))
          (let loop ((i first) (count 0))
            (if (fx>= i len)
                count
                (let* ((entry (vector-ref index i))
                       (header (aql-block-index-entry-header entry))
                       (min-key (aql-block-header-min-key header))
                       (max-key (aql-block-header-max-key header))
                       (byte-size (aql-block-header-byte-size header)))
                  (if (bytevector<=? end-key min-key)
                      count
                      (if (and (bytevector<=? start-key min-key)
                               (bytevector<? max-key end-key))
                          (loop (fx+ i 1) (+ count byte-size))
                          (loop (fx+ i 1)
                                (+ count
                                   (aql-interpolate-byte-size
                                     header start-key end-key))))))))))))

;; Whole-database counts

(define (aql-approximate-key-count-total runs)
  ;; Sum across all runs. Over-counts due to duplicates.
  (let loop ((runs runs) (count 0))
    (if (null? runs)
        count
        (let* ((run (car runs))
               (index (aql-run-block-index run))
               (len (vector-length index)))
          (let iloop ((i 0) (c count))
            (if (fx>= i len)
                (loop (cdr runs) c)
                (iloop (fx+ i 1)
                       (+ c (aql-block-header-key-count
                              (aql-block-index-entry-header
                                (vector-ref index i)))))))))))

(define (aql-approximate-byte-count-total runs)
  (let loop ((runs runs) (count 0))
    (if (null? runs)
        count
        (let* ((run (car runs))
               (index (aql-run-block-index run))
               (len (vector-length index)))
          (let iloop ((i 0) (c count))
            (if (fx>= i len)
                (loop (cdr runs) c)
                (iloop (fx+ i 1)
                       (+ c (aql-block-header-byte-size
                              (aql-block-index-entry-header
                                (vector-ref index i)))))))))))

;;;
;;; Section 11 — Buffer Cache
;;;

(define-record-type* <aql-buffer-cache>
  (make-aql-buffer-cache buffers block-size free-list mapping)
  aql-buffer-cache?
  (buffers    aql-buffer-cache-buffers)    ;; vector of foreign pointers
  (block-size aql-buffer-cache-block-size)
  (free-list  aql-buffer-cache-free-list aql-buffer-cache-free-list!)  ;; mutable: list of free buffer indices
  (mapping    aql-buffer-cache-mapping))   ;; mutable: hashtable (run-seq . block-idx) → buffer-idx

(define (aql-buffer-cache-init pool-size block-size ring)
  ;; Allocate pool-size buffers via foreign-alloc.
  ;; Register with io_uring via io_uring_register_buffers.
  ;; Returns <aql-buffer-cache>.
  (let* ((buf-size (+ block-size aql-crypto-overhead))
         (bufs (let ((v (make-vector pool-size)))
                 (let loop ((i 0))
                   (when (fx< i pool-size)
                     (vector-set! v i (foreign-alloc buf-size))
                     (loop (fx+ i 1))))
                 v))
         ;; Build iovec array for registration
         (iovecs (foreign-alloc (* pool-size %iovec-size))))
    (let loop ((i 0))
      (when (fx< i pool-size)
        (let ((off (* i %iovec-size)))
          (foreign-set! 'void* iovecs off (vector-ref bufs i))
          (foreign-set! 'size_t iovecs (+ off (foreign-sizeof 'void*)) buf-size))
        (loop (fx+ i 1))))
    ;; Register with io_uring
    (let ((rc (io-uring-register-buffers ring iovecs pool-size)))
      (unless (fxzero? rc)
        (error 'aql-buffer-cache-init
               "register-buffers failed" (strerror (fx- 0 rc)))))
    (foreign-free iovecs)
    ;; Build free list: all indices free initially
    (let ((free-list (let loop ((i (fx- pool-size 1)) (acc '()))
                       (if (fx< i 0) acc
                           (loop (fx- i 1) (cons i acc))))))
      (make-aql-buffer-cache bufs block-size free-list
                             (make-hashtable equal-hash equal?)))))

(define (aql-buffer-cache-get cache run-seq block-idx)
  ;; Returns buffer index if cached, or #f.
  (hashtable-ref (aql-buffer-cache-mapping cache)
                 (cons run-seq block-idx)
                 #f))

(define (aql-buffer-cache-claim cache run-seq block-idx)
  ;; Claim a free buffer for this (run, block) pair.
  ;; If no free buffers, evict arbitrary entry.
  ;; Returns buffer index.
  (let ((free (aql-buffer-cache-free-list cache)))
    (if (null? free)
        ;; Evict: pick first entry from mapping
        (let-values (((keys vals) (hashtable-entries
                                    (aql-buffer-cache-mapping cache))))
          (when (fxzero? (vector-length keys))
            (error 'aql-buffer-cache-claim "cache exhausted"))
          (let ((evict-key (vector-ref keys 0))
                (evict-idx (vector-ref vals 0)))
            (hashtable-delete! (aql-buffer-cache-mapping cache) evict-key)
            (hashtable-set! (aql-buffer-cache-mapping cache)
                            (cons run-seq block-idx) evict-idx)
            evict-idx))
        ;; Take from free list
        (let ((buf-idx (car free)))
          (aql-buffer-cache-free-list! cache (cdr free))
          (hashtable-set! (aql-buffer-cache-mapping cache)
                          (cons run-seq block-idx) buf-idx)
          buf-idx))))

(define (aql-buffer-cache-release cache run-seq block-idx)
  ;; Release buffer back to free list.
  ;; Called when a run is deleted after compaction.
  (let ((mapping (aql-buffer-cache-mapping cache)))
    (let ((buf-idx (hashtable-ref mapping (cons run-seq block-idx) #f)))
      (when buf-idx
        (hashtable-delete! mapping (cons run-seq block-idx))
        (aql-buffer-cache-free-list! cache
          (cons buf-idx (aql-buffer-cache-free-list cache)))))))

;;;
;;; Section 12 — Block I/O Layer
;;;

(define (foreign-copy-to-bytevector ptr len)
  ;; Copy len bytes from foreign pointer to a new bytevector.
  (let ((bv (make-bytevector len)))
    (let loop ((i 0))
      (when (fx< i len)
        (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 ptr i))
        (loop (fx+ i 1))))
    bv))

(define (aql-block-read run block-idx encryption-key buffer-cache ring cqe-ptr)
  ;; Returns block-size bytevector (decrypted logical block).
  (let* ((header (aql-run-header run))
         (stride (aql-run-stride header))
         (offset (aql-run-block-file-offset header block-idx))
         (fd (aql-run-fd run))
         (seq (aql-run-sequence-number run))
         (block-size (aql-run-header-block-size header))
         (encrypted? (aql-run-header-encrypted? header))
         ;; Check cache
         (cached (aql-buffer-cache-get buffer-cache seq block-idx))
         (buf-idx (or cached
                      (aql-buffer-cache-claim buffer-cache seq block-idx)))
         (buf-ptr (vector-ref (aql-buffer-cache-buffers buffer-cache) buf-idx)))
    ;; Read if not cached
    (unless cached
      (let ((res (uring-do ring cqe-ptr
                   (lambda (sqe)
                     (io-uring-prep-read-fixed sqe fd buf-ptr stride offset buf-idx)))))
        (when (fx<? res 0)
          (error 'aql-block-read "read failed" (strerror (fx- 0 res))))
        (when (fx<? res stride)
          (error 'aql-block-read "short read" res stride))))
    ;; Copy from foreign buffer to Scheme bytevector
    (let ((bv (foreign-copy-to-bytevector buf-ptr stride)))
      (if encrypted?
          (aql-block-decrypt bv block-size encryption-key)
          (let ((out (make-bytevector block-size)))
            (bytevector-copy! bv 0 out 0 block-size)
            out)))))

(define (aql-block-write-to-run fd header block-idx data encryption-key ring cqe-ptr)
  ;; Write a logical block to a run file at the given block index.
  (let* ((offset (aql-run-block-file-offset header block-idx))
         (buf (if (aql-run-header-encrypted? header)
                  (aql-block-encrypt data encryption-key)
                  data)))
    (with-lock (list buf)
      (let ((res (uring-do ring cqe-ptr
                   (lambda (sqe)
                     (io-uring-prep-write sqe fd (bytevector-pointer buf)
                                          (bytevector-length buf) offset)))))
        (when (fx<? res 0)
          (error 'aql-block-write-to-run "write failed" (strerror (fx- 0 res))))
        (when (fx<? res (bytevector-length buf))
          (error 'aql-block-write-to-run "short write" res (bytevector-length buf)))))))

;;;
;;; Section 13 — Encryption Primitives
;;;

(define (aql-block-encrypt plaintext encryption-key)
  ;; Returns bytevector: [nonce 24][ciphertext+tag (block-size + 16)]
  ;; Total output size: block-size + 40 = block-size + aql-crypto-overhead
  (let* ((nonce (randombytes-buf 24))
         (ct (crypto-aead-xchacha20poly1305-ietf-encrypt
               plaintext encryption-key nonce))
         (ct-len (bytevector-length ct))
         (out (make-bytevector (+ 24 ct-len) 0)))
    (bytevector-copy! nonce 0 out 0 24)
    (bytevector-copy! ct 0 out 24 ct-len)
    out))

(define (aql-block-decrypt slot block-size encryption-key)
  ;; slot: bytevector [nonce 24][ciphertext (block-size + 16)]
  ;; Returns decrypted block-size bytevector.
  ;; Raises error if auth fails (wrong key or tampered).
  (let* ((nonce (let ((n (make-bytevector 24)))
                  (bytevector-copy! slot 0 n 0 24)
                  n))
         (ct-len (+ block-size 16))
         (ct (let ((c (make-bytevector ct-len)))
               (bytevector-copy! slot 24 c 0 ct-len)
               c))
         (plaintext (crypto-aead-xchacha20poly1305-ietf-decrypt
                      ct encryption-key nonce)))
    (unless plaintext
      (error 'aql-block-decrypt "authentication failed"))
    plaintext))

;;;
;;; Section 14 — Block Serialization (BST → blocks for a new run)
;;;

(define (aql-pack-block key-max-bytes block-size pairs)
  ;; Pack a list of sorted (key . value) pairs into a block bytevector.
  ;; Returns the block bytevector (exactly block-size bytes) and the
  ;; number of pairs consumed, or #f if no pairs fit.
  ;;
  ;; Strategy: reserve worst-case header space at front, fill kv pairs
  ;; after that, then write actual header at front.
  (when (null? pairs)
    (error 'aql-pack-block "no pairs to pack"))
  (let* ((header-reserve (aql-block-header-max-size key-max-bytes))
         (block (make-bytevector block-size 0))
         (capacity (- block-size header-reserve)))
    (let loop ((pairs pairs) (pos header-reserve) (count 0)
               (byte-total 0) (min-key #f) (max-key #f))
      (if (null? pairs)
          ;; All pairs consumed
          (if (= count 0)
              (values #f 0)
              (let* ((header (make-aql-block-header min-key max-key count byte-total))
                     (hdr-bv (aql-block-header->bytevector header))
                     (hdr-len (bytevector-length hdr-bv))
                     ;; Write header at offset (header-reserve - hdr-len)
                     ;; so that header ends exactly at header-reserve.
                     ;; Actually, header goes at offset 0, kv pairs follow.
                     ;; Repack: write header at 0, shift kv data.
                     (out (make-bytevector block-size 0)))
                (bytevector-copy! hdr-bv 0 out 0 hdr-len)
                (bytevector-copy! block header-reserve out hdr-len
                                  (- pos header-reserve))
                (values out count)))
          (let* ((key (car (car pairs)))
                 (value (cdr (car pairs)))
                 (pair-size (aql-kv-pair-size key value))
                 (new-pos (+ pos pair-size)))
            (if (> new-pos block-size)
                ;; Block full
                (if (= count 0)
                    (error 'aql-pack-block
                           "single kv pair exceeds block capacity"
                           (bytevector-length key) (bytevector-length value))
                    (let* ((header (make-aql-block-header min-key max-key count byte-total))
                           (hdr-bv (aql-block-header->bytevector header))
                           (hdr-len (bytevector-length hdr-bv))
                           (out (make-bytevector block-size 0)))
                      (bytevector-copy! hdr-bv 0 out 0 hdr-len)
                      (bytevector-copy! block header-reserve out hdr-len
                                        (- pos header-reserve))
                      (values out count)))
                ;; Pack this pair
                (let ((packed (aql-pack-kv-pair key value)))
                  (bytevector-copy! packed 0 block pos (bytevector-length packed))
                  (loop (cdr pairs) new-pos (+ count 1)
                        (+ byte-total pair-size)
                        (or min-key key)
                        key))))))))

(define (aql-block-header-byte-length header)
  ;; Compute the actual serialized size of a block header.
  (+ 1 2 (bytevector-length (aql-block-header-min-key header))
     2 (bytevector-length (aql-block-header-max-key header))
     8 8))

(define (aql-unpack-block block-bv)
  ;; Parse a block: extract block header and list of kv pairs.
  ;; Returns (values header pairs) where pairs is a list of (key . value).
  (let* ((header (bytevector->aql-block-header block-bv))
         (hdr-len (aql-block-header-byte-length header))
         (byte-size (aql-block-header-byte-size header)))
    (values header
            (aql-unpack-kv-pairs block-bv hdr-len (+ hdr-len byte-size)))))

(define (aql-serialize-bst-to-run handle)
  ;; Flush BST to a new run file. Returns the new <aql-run>.
  (define (lbst-to-alist tree)
    ;; Traverse from start to end using lbst-next (forward order).
    (let loop ((node (lbst-start tree)) (out '()))
      (if (not node)
          (reverse out)
          (loop (lbst-next node)
                (cons (cons (lbst-key node) (lbst-value node)) out)))))
  (let* ((bst (aql-disk-handle-bst handle))
         (manifest (aql-disk-handle-manifest handle))
         (encryption-key (aql-disk-handle-encryption-key handle))
         (dirpath (aql-disk-handle-dirpath handle))
         (ring (aql-disk-handle-ring handle))
         (cqe-ptr (aql-disk-handle-cqe-ptr handle))
         (key-max (aql-manifest-key-max-bytes manifest))
         (val-max (aql-manifest-value-max-bytes manifest))
         (block-size (aql-manifest-block-size manifest))
         (encrypted? (aql-manifest-encrypted? manifest))
         (seq (aql-manifest-next-sequence manifest))
         (filename (string-append dirpath "/" (aql-run-filename seq)))
         ;; Collect all kv pairs from BST in sorted order
         (pairs (lbst-to-alist bst)))
    (when (null? pairs)
      (error 'aql-serialize-bst-to-run "BST is empty"))
    ;; Open run file
    (let* ((flags (fxlogor %O_RDWR (fxlogor %O_CREAT %O_TRUNC)))
           (fd (uring-do ring cqe-ptr
                 (lambda (sqe)
                   (io-uring-prep-openat sqe %AT_FDCWD filename flags #o644)))))
      (when (fx<? fd 0)
        (error 'aql-serialize-bst-to-run "open failed" (strerror (fx- 0 fd))))
      ;; Write placeholder header (32 bytes of zeros)
      (let ((placeholder (make-bytevector aql-run-header-size 0)))
        (with-lock (list placeholder)
          (uring-do ring cqe-ptr
            (lambda (sqe)
              (io-uring-prep-write sqe fd (bytevector-pointer placeholder)
                                   aql-run-header-size 0)))))
      ;; Pack and write blocks
      (let loop ((remaining pairs) (block-idx 0) (index-entries '()))
        (if (null? remaining)
            ;; Finalize
            (let* ((block-count block-idx)
                   (header (make-aql-run-header key-max val-max
                             block-size block-count encrypted?)))
              ;; Rewrite header with actual block-count
              (let ((hdr-bv (aql-run-header->bytevector header)))
                (with-lock (list hdr-bv)
                  (uring-do ring cqe-ptr
                    (lambda (sqe)
                      (io-uring-prep-write sqe fd (bytevector-pointer hdr-bv)
                                           aql-run-header-size 0)))))
              ;; Fsync the run file
              (uring-do ring cqe-ptr
                (lambda (sqe) (io-uring-prep-fsync sqe fd 0)))
              ;; Build block index
              (let* ((block-index (make-aql-block-index (reverse index-entries)))
                     (run (make-aql-run seq fd header block-index))
                     ;; Update manifest
                     (new-entry (make-aql-manifest-run-entry seq block-count))
                     (new-manifest (make-aql-manifest
                                     key-max val-max block-size encrypted?
                                     (+ seq 1)
                                     (cons new-entry (aql-manifest-runs manifest)))))
                (aql-manifest-write! dirpath new-manifest ring cqe-ptr)
                (aql-disk-handle-manifest! handle new-manifest)
                (aql-disk-handle-runs! handle
                  (cons run (aql-disk-handle-runs handle)))
                ;; Clear BST
                (aql-disk-handle-bst! handle (make-lbst))
                ;; Truncate WAL
                (uring-do ring cqe-ptr
                  (lambda (sqe)
                    (io-uring-prep-ftruncate sqe
                      (aql-disk-handle-wal-fd handle) 0)))
                (aql-disk-handle-wal-offset! handle 0)
                run))
            ;; Pack next block
            (call-with-values
              (lambda () (aql-pack-block key-max block-size remaining))
              (lambda (block-bv count)
                (let* ((tmp-header (make-aql-run-header key-max val-max
                                     block-size 0 encrypted?))
                       (file-offset (aql-run-block-file-offset tmp-header block-idx))
                       (block-header (bytevector->aql-block-header block-bv)))
                  ;; Write block to run file
                  (aql-block-write-to-run fd tmp-header block-idx
                    block-bv encryption-key ring cqe-ptr)
                  ;; Accumulate index entry
                  (loop (list-tail remaining count)
                        (fx+ block-idx 1)
                        (cons (make-aql-block-index-entry block-header file-offset)
                              index-entries))))))))))

;;;
;;; Section 15 — Read Path (point lookup)
;;;

(define (aql-block-search-key block-bv key block-header)
  ;; Linear scan sorted kv pairs within a block for the given key.
  ;; Returns value bytevector if found, #f if not found.
  (let* ((hdr-len (aql-block-header-byte-length block-header))
         (byte-size (aql-block-header-byte-size block-header))
         (end (+ hdr-len byte-size)))
    (let loop ((pos hdr-len))
      (if (>= pos end)
          #f
          (let* ((key-len (bytevector-u16-ref block-bv pos (endianness big)))
                 (pos2 (+ pos 2))
                 (found-key (let ((k (make-bytevector key-len)))
                              (bytevector-copy! block-bv pos2 k 0 key-len)
                              k))
                 (pos3 (+ pos2 key-len))
                 (val-len (bytevector-u32-ref block-bv pos3 (endianness big)))
                 (pos4 (+ pos3 4)))
            (let ((cmp (bytevector-compare found-key key)))
              (cond
                ((= cmp 0)
                 ;; Found — extract value
                 (let ((v (make-bytevector val-len)))
                   (bytevector-copy! block-bv pos4 v 0 val-len)
                   v))
                ((> cmp 0)
                 ;; Past the key in sorted order — not found
                 #f)
                (else
                 ;; Keep scanning
                 (loop (+ pos4 val-len))))))))))

(define (aql-disk-get handle key)
  ;; Point lookup: check BST then runs newest-to-oldest.
  (let ((bst (aql-disk-handle-bst handle))
        (runs (aql-disk-handle-runs handle))
        (encryption-key (aql-disk-handle-encryption-key handle))
        (buffer-cache (aql-disk-handle-buffer-cache handle))
        (ring (aql-disk-handle-ring handle))
        (cqe-ptr (aql-disk-handle-cqe-ptr handle)))
    ;; 1. Check BST
    (let ((node (lbst-ref bst key)))
      (if node
          (let ((value (lbst-value node)))
            (if (aql-tombstone? value)
                #f
                value))
          ;; 2. Search runs newest-to-oldest
          (let run-loop ((runs runs))
            (if (null? runs)
                #f
                (let* ((run (car runs))
                       (index (aql-run-block-index run))
                       (pos (aql-block-index-search index key)))
                  (if (fx>=? pos (vector-length index))
                      (run-loop (cdr runs))
                      (let* ((entry (vector-ref index pos))
                             (hdr (aql-block-index-entry-header entry))
                             (min-key (aql-block-header-min-key hdr))
                             (max-key (aql-block-header-max-key hdr)))
                        (if (and (bytevector<=? min-key key)
                                 (bytevector<=? key max-key))
                            ;; Read block and search
                            (let* ((block-bv (aql-block-read run pos
                                               encryption-key buffer-cache
                                               ring cqe-ptr))
                                   (value (aql-block-search-key block-bv key hdr)))
                              (if value
                                  (if (aql-tombstone? value)
                                      #f   ;; tombstone stops search
                                      value)
                                  (run-loop (cdr runs))))
                            (run-loop (cdr runs))))))))))))

;;;
;;; Section 16 — Range Query (across runs)
;;;

(define (make-bst-range-iterator bst start-key end-key)
  ;; Returns a thunk that yields (key . value) pairs in order,
  ;; or #f when exhausted. Range is [start-key, end-key).
  (let ((current #f)
        (started #f))
    (lambda ()
      (unless started
        (set! started #t)
        (call-with-lbst bst start-key
          (lambda (node position)
            (cond
              ((not position) (set! current #f))
              ((eq? position 'exact) (set! current node))
              ((eq? position 'after) (set! current node))
              ((eq? position 'before)
               (set! current (and node (lbst-next node))))))))
      (if (not current)
          #f
          (let ((key (lbst-key current))
                (value (lbst-value current)))
            (if (bytevector<? key end-key)
                (let ((result (cons key value)))
                  (set! current (lbst-next current))
                  result)
                (begin (set! current #f) #f)))))))

(define (make-run-range-iterator run start-key end-key
                                 encryption-key buffer-cache ring cqe-ptr)
  ;; Returns a thunk that yields (key . value) pairs from a run
  ;; in sorted order for [start-key, end-key), or #f when done.
  (let* ((index (aql-run-block-index run))
         (len (vector-length index))
         (block-pos (aql-block-index-search index start-key))
         (current-pairs '())
         (done? #f))
    (lambda ()
      (let loop ()
        (cond
          (done? #f)
          ((not (null? current-pairs))
           (let ((pair (car current-pairs)))
             (set! current-pairs (cdr current-pairs))
             (if (bytevector<? (car pair) end-key)
                 pair
                 (begin (set! done? #t) #f))))
          ((fx>=? block-pos len)
           (set! done? #t)
           #f)
          (else
           (let* ((entry (vector-ref index block-pos))
                  (hdr (aql-block-index-entry-header entry))
                  (min-key (aql-block-header-min-key hdr)))
             (if (bytevector<=? end-key min-key)
                 (begin (set! done? #t) #f)
                 (let* ((block-bv (aql-block-read run block-pos
                                    encryption-key buffer-cache ring cqe-ptr))
                        (all-pairs
                          (call-with-values
                            (lambda () (aql-unpack-block block-bv))
                            (lambda (header pairs) pairs)))
                        (filtered (filter
                                    (lambda (p) (and (bytevector<=? start-key (car p))
                                                     (bytevector<? (car p) end-key)))
                                    all-pairs)))
                   (set! block-pos (fx+ block-pos 1))
                   (set! current-pairs filtered)
                   (loop))))))))))

(define (aql-disk-range handle start-key end-key)
  ;; K-way merge across BST and all runs for [start-key, end-key).
  (let* ((bst (aql-disk-handle-bst handle))
         (runs (aql-disk-handle-runs handle))
         (encryption-key (aql-disk-handle-encryption-key handle))
         (buffer-cache (aql-disk-handle-buffer-cache handle))
         (ring (aql-disk-handle-ring handle))
         (cqe-ptr (aql-disk-handle-cqe-ptr handle))
         ;; Build iterators: BST first (highest priority), then runs newest-first
         (bst-iter (make-bst-range-iterator bst start-key end-key))
         (run-iters (map (lambda (run)
                           (make-run-range-iterator run start-key end-key
                             encryption-key buffer-cache ring cqe-ptr))
                         runs))
         (iters (cons bst-iter run-iters))
         ;; Initialize frontier: current head from each iterator
         (frontier (map (lambda (it) (it)) iters)))
    ;; K-way merge
    (let merge ((frontier frontier) (result '()))
      ;; Find minimum key across all non-#f frontiers
      (let ((min-key #f))
        (for-each
          (lambda (head)
            (when head
              (when (or (not min-key) (bytevector<? (car head) min-key))
                (set! min-key (car head)))))
          frontier)
        (if (not min-key)
            (reverse result)
            ;; Collect all entries with min-key; newest wins (first in list)
            (let loop ((front frontier) (its iters) (new-front '())
                       (value #f) (found? #f))
              (if (null? front)
                  (let ((new-frontier (reverse new-front)))
                    (if (and found? (not (aql-tombstone? value)))
                        (merge new-frontier (cons (cons min-key value) result))
                        (merge new-frontier result)))
                  (let ((head (car front))
                        (it (car its)))
                    (if (and head (= (bytevector-compare (car head) min-key) 0))
                        (loop (cdr front) (cdr its)
                              (cons (it) new-front)
                              (if found? value (cdr head))
                              #t)
                        (loop (cdr front) (cdr its)
                              (cons head new-front)
                              value found?))))))))))

;;;
;;; Section 17 — Compaction
;;;

(define (aql-compact! handle runs-to-merge)
  ;; Merge multiple runs into a single new run.
  ;; Drops tombstones and keeps only newest value for duplicate keys.
  (let* ((manifest (aql-disk-handle-manifest handle))
         (encryption-key (aql-disk-handle-encryption-key handle))
         (dirpath (aql-disk-handle-dirpath handle))
         (buffer-cache (aql-disk-handle-buffer-cache handle))
         (ring (aql-disk-handle-ring handle))
         (cqe-ptr (aql-disk-handle-cqe-ptr handle))
         (key-max (aql-manifest-key-max-bytes manifest))
         (val-max (aql-manifest-value-max-bytes manifest))
         (block-size (aql-manifest-block-size manifest))
         (encrypted? (aql-manifest-encrypted? manifest))
         (seq (aql-manifest-next-sequence manifest))
         (filename (string-append dirpath "/" (aql-run-filename seq)))
         ;; Build iterators for all runs being merged (newest first)
         (iters (map (lambda (run)
                       (make-run-range-iterator run #vu8() #vu8(255 255 255 255)
                         encryption-key buffer-cache ring cqe-ptr))
                     runs-to-merge))
         (frontier (map (lambda (it) (it)) iters)))
    ;; K-way merge → collect all pairs (newest wins, drop tombstones)
    (let merge-loop ((frontier frontier) (pairs '()))
      (let ((min-key #f))
        (for-each
          (lambda (head)
            (when head
              (when (or (not min-key) (bytevector<? (car head) min-key))
                (set! min-key (car head)))))
          frontier)
        (if (not min-key)
            ;; All exhausted — write merged pairs as new run
            (let ((sorted-pairs (reverse pairs)))
              (if (null? sorted-pairs)
                  (void)  ;; nothing to compact
                  (let* ((flags (fxlogor %O_RDWR (fxlogor %O_CREAT %O_TRUNC)))
                         (fd (uring-do ring cqe-ptr
                               (lambda (sqe)
                                 (io-uring-prep-openat sqe %AT_FDCWD filename flags #o644)))))
                    (when (fx<? fd 0)
                      (error 'aql-compact! "open failed" (strerror (fx- 0 fd))))
                    ;; Write placeholder header
                    (let ((placeholder (make-bytevector aql-run-header-size 0)))
                      (with-lock (list placeholder)
                        (uring-do ring cqe-ptr
                          (lambda (sqe)
                            (io-uring-prep-write sqe fd (bytevector-pointer placeholder)
                                                 aql-run-header-size 0)))))
                    ;; Pack and write blocks
                    (let bloop ((remaining sorted-pairs) (block-idx 0) (index-entries '()))
                      (if (null? remaining)
                          ;; Finalize
                          (let* ((block-count block-idx)
                                 (header (make-aql-run-header key-max val-max
                                           block-size block-count encrypted?)))
                            (let ((hdr-bv (aql-run-header->bytevector header)))
                              (with-lock (list hdr-bv)
                                (uring-do ring cqe-ptr
                                  (lambda (sqe)
                                    (io-uring-prep-write sqe fd (bytevector-pointer hdr-bv)
                                                         aql-run-header-size 0)))))
                            (uring-do ring cqe-ptr
                              (lambda (sqe) (io-uring-prep-fsync sqe fd 0)))
                            ;; Build new run
                            (let* ((block-index (make-aql-block-index (reverse index-entries)))
                                   (new-run (make-aql-run seq fd header block-index))
                                   (new-entry (make-aql-manifest-run-entry seq block-count))
                                   ;; Remove old runs from manifest, add new
                                   (old-seqs (map aql-run-sequence-number runs-to-merge))
                                   (kept-entries (filter
                                                   (lambda (e)
                                                     (not (memv (aql-manifest-run-entry-sequence-number e) old-seqs)))
                                                   (aql-manifest-runs manifest)))
                                   (new-manifest (make-aql-manifest
                                                   key-max val-max block-size encrypted?
                                                   (+ seq 1)
                                                   (cons new-entry kept-entries))))
                              (aql-manifest-write! dirpath new-manifest ring cqe-ptr)
                              (aql-disk-handle-manifest! handle new-manifest)
                              ;; Close and delete old run files
                              (for-each
                                (lambda (run)
                                  (uring-do ring cqe-ptr
                                    (lambda (sqe) (io-uring-prep-close sqe (aql-run-fd run))))
                                  (let ((old-file (string-append dirpath "/"
                                                    (aql-run-filename (aql-run-sequence-number run)))))
                                    (uring-do ring cqe-ptr
                                      (lambda (sqe) (io-uring-prep-unlinkat sqe %AT_FDCWD old-file 0))))
                                  ;; Release buffer cache entries
                                  (let ((idx (aql-run-block-index run)))
                                    (let lp ((i 0))
                                      (when (fx< i (vector-length idx))
                                        (aql-buffer-cache-release buffer-cache
                                          (aql-run-sequence-number run) i)
                                        (lp (fx+ i 1))))))
                                runs-to-merge)
                              ;; Update handle runs list
                              (let ((kept-runs (filter
                                                 (lambda (r)
                                                   (not (memv (aql-run-sequence-number r) old-seqs)))
                                                 (aql-disk-handle-runs handle))))
                                (aql-disk-handle-runs! handle (cons new-run kept-runs)))))
                          ;; Pack next block
                          (call-with-values
                            (lambda () (aql-pack-block key-max block-size remaining))
                            (lambda (block-bv count)
                              (let* ((tmp-header (make-aql-run-header key-max val-max
                                                   block-size 0 encrypted?))
                                     (file-offset (aql-run-block-file-offset tmp-header block-idx))
                                     (block-header (bytevector->aql-block-header block-bv)))
                                (aql-block-write-to-run fd tmp-header block-idx
                                  block-bv encryption-key ring cqe-ptr)
                                (bloop (list-tail remaining count)
                                       (fx+ block-idx 1)
                                       (cons (make-aql-block-index-entry block-header file-offset)
                                             index-entries))))))))))
            ;; Pick min-key entries, advance iterators
            (let loop ((front frontier) (its iters) (new-front '())
                       (value #f) (found? #f))
              (if (null? front)
                  (let ((new-frontier (reverse new-front)))
                    ;; Drop tombstones in compaction
                    (if (and found? (not (aql-tombstone? value)))
                        (merge-loop new-frontier (cons (cons min-key value) pairs))
                        (merge-loop new-frontier pairs)))
                  (let ((head (car front))
                        (it (car its)))
                    (if (and head (= (bytevector-compare (car head) min-key) 0))
                        (loop (cdr front) (cdr its)
                              (cons (it) new-front)
                              (if found? value (cdr head))
                              #t)
                        (loop (cdr front) (cdr its)
                              (cons head new-front)
                              value found?))))))))))


;;;
;;; Section 18 — Startup / Open
;;;

(define (aql-read-run-block-index fd header ring cqe-ptr)
  ;; Scan all block headers in a run file to build the in-memory block index.
  ;; Reads just enough of each block to parse the header.
  (let* ((block-count (aql-run-header-block-count header))
         (block-size (aql-run-header-block-size header))
         (key-max (aql-run-header-key-max-bytes header))
         (max-hdr-size (aql-block-header-max-size key-max)))
    (let loop ((i 0) (entries '()))
      (if (fx>=? i block-count)
          (make-aql-block-index entries)
          (let* ((file-offset (aql-run-block-file-offset header i))
                 ;; Read block header portion
                 (hdr-buf (make-bytevector max-hdr-size 0))
                 (read-size (fxmin max-hdr-size block-size)))
            (with-lock (list hdr-buf)
              (uring-do ring cqe-ptr
                (lambda (sqe)
                  (io-uring-prep-read sqe fd (bytevector-pointer hdr-buf)
                                      read-size file-offset))))
            (let ((block-header (bytevector->aql-block-header hdr-buf)))
              (loop (fx+ i 1)
                    (cons (make-aql-block-index-entry block-header file-offset)
                          entries))))))))

(define (aql-disk-open dirpath encryption-key)
  ;; Open or create database. Returns <aql-disk-handle>.
  ;; 1. Initialize io_uring ring
  (let* ((ring (make-io-uring))
         (cqe-ptr (make-cqe-pointer))
         (_ (let ((rc (io-uring-queue-init 64 ring 0)))
              (unless (fxzero? rc)
                (error 'aql-disk-open "io_uring init failed"
                       (strerror (fx- 0 rc))))))
         (_ (when encryption-key (sodium-init))))
    ;; 2. Read manifest or create new database
    (let* ((manifest-path (string-append dirpath "/manifest.aql"))
           (manifest
             (if (file-exists? manifest-path)
                 (let* ((port (open-file-input-port manifest-path))
                        (bv (get-bytevector-all port)))
                   (close-port port)
                   (bytevector->aql-manifest bv))
                 (begin
                   (unless (file-exists? dirpath)
                     (mkdir dirpath))
                   (let ((m (make-aql-manifest 1024 1048576 aql-default-block-size
                              (if encryption-key #t #f) 1 '())))
                     (aql-manifest-write! dirpath m ring cqe-ptr)
                     m)))))
      ;; 3. Initialize buffer cache
      (let ((cache (aql-buffer-cache-init 64
                     (aql-manifest-block-size manifest) ring)))
        ;; 4. Open each run file
        (let ((runs (map
                      (lambda (entry)
                        (let* ((seq-num (aql-manifest-run-entry-sequence-number entry))
                               (fname (string-append dirpath "/" (aql-run-filename seq-num)))
                               (fd (uring-do ring cqe-ptr
                                     (lambda (sqe)
                                       (io-uring-prep-openat sqe %AT_FDCWD
                                         fname %O_RDONLY #o0)))))
                          (when (fx<? fd 0)
                            (error 'aql-disk-open "open run failed"
                                   fname (strerror (fx- 0 fd))))
                          ;; Read run file header
                          (let ((hdr-bv (make-bytevector aql-run-header-size 0)))
                            (with-lock (list hdr-bv)
                              (uring-do ring cqe-ptr
                                (lambda (sqe)
                                  (io-uring-prep-read sqe fd (bytevector-pointer hdr-bv)
                                                      aql-run-header-size 0))))
                            (let* ((header (bytevector->aql-run-header hdr-bv))
                                   (block-index (aql-read-run-block-index fd header ring cqe-ptr)))
                              (make-aql-run seq-num fd header block-index)))))
                      (aql-manifest-runs manifest))))
          ;; 5. Open or create WAL
          (let* ((wal-path (string-append dirpath "/wal.aql"))
                 (wal-fd (uring-do ring cqe-ptr
                           (lambda (sqe)
                             (io-uring-prep-openat sqe %AT_FDCWD wal-path
                               (fxlogor %O_RDWR %O_CREAT) #o644)))))
            (when (fx<? wal-fd 0)
              (error 'aql-disk-open "open WAL failed" (strerror (fx- 0 wal-fd))))
            ;; 6. Replay WAL into BST
            (let* ((wal-port (open-file-input-port wal-path))
                   (wal-data (get-bytevector-all wal-port))
                   (_ (close-port wal-port))
                   (bst (make-lbst))
                   (wal-offset 0))
              (let ((bst
                      (if (eof-object? wal-data)
                          bst
                          (let ((frames (aql-wal-parse-frames wal-data)))
                            (set! wal-offset (bytevector-length wal-data))
                            (let replay ((frames frames) (tree bst))
                              (if (null? frames)
                                  tree
                                  (let ((frame (car frames)))
                                    (case (car frame)
                                      ((set)
                                       (replay (cdr frames)
                                               (lbst-set tree (cadr frame) (cddr frame))))
                                      ((remove)
                                       (replay (cdr frames)
                                               (lbst-set tree (cadr frame) aql-tombstone-value)))
                                      (else
                                       (error 'aql-disk-open "unknown WAL frame" (car frame)))))))))))
                ;; 7. Return handle
                (make-aql-disk-handle dirpath manifest runs bst
                                      wal-fd wal-offset
                                      encryption-key cache ring cqe-ptr)))))))))


(define (aql-disk-close! handle)
  (let ((ring (aql-disk-handle-ring handle))
        (cqe-ptr (aql-disk-handle-cqe-ptr handle)))
    ;; 1. Flush BST if non-empty
    (unless (lbst-empty? (aql-disk-handle-bst handle))
      (aql-serialize-bst-to-run handle))
    ;; 2. Close all run fds
    (for-each
      (lambda (run)
        (uring-do ring cqe-ptr
          (lambda (sqe) (io-uring-prep-close sqe (aql-run-fd run)))))
      (aql-disk-handle-runs handle))
    ;; 3. Close WAL fd
    (uring-do ring cqe-ptr
      (lambda (sqe)
        (io-uring-prep-close sqe (aql-disk-handle-wal-fd handle))))
    ;; 4. Deregister and free buffer cache
    (io-uring-unregister-buffers ring)
    (let ((bufs (aql-buffer-cache-buffers (aql-disk-handle-buffer-cache handle))))
      (let loop ((i 0))
        (when (fx< i (vector-length bufs))
          (foreign-free (vector-ref bufs i))
          (loop (fx+ i 1)))))
    ;; 5. Tear down io_uring
    (io-uring-queue-exit ring)))

;;;
;;; Section 19 — Write Path
;;;

(define (aql-disk-set! handle key value)
  (let ((ring (aql-disk-handle-ring handle))
        (cqe-ptr (aql-disk-handle-cqe-ptr handle)))
    ;; 1. Write WAL frame
    (let* ((frame (aql-wal-frame-set key value))
           (wal-fd (aql-disk-handle-wal-fd handle))
           (wal-offset (aql-disk-handle-wal-offset handle)))
      (with-lock (list frame)
        (uring-do ring cqe-ptr
          (lambda (sqe)
            (io-uring-prep-write sqe wal-fd (bytevector-pointer frame)
                                 (bytevector-length frame) wal-offset))))
      ;; Fsync WAL
      (uring-do ring cqe-ptr
        (lambda (sqe) (io-uring-prep-fsync sqe wal-fd 0)))
      (aql-disk-handle-wal-offset! handle
        (+ wal-offset (bytevector-length frame))))
    ;; 2. Apply to BST
    (aql-disk-handle-bst! handle
      (lbst-set (aql-disk-handle-bst handle) key value))
    ;; 3. Check flush threshold
    (when (> (lbst-bytes (aql-disk-handle-bst handle)) %flush-threshold)
      (aql-serialize-bst-to-run handle))
    ;; 4. Check compaction threshold
    (when (> (length (aql-disk-handle-runs handle)) %compaction-threshold)
      (aql-compact! handle (aql-disk-handle-runs handle)))))

(define (aql-disk-remove! handle key)
  (let ((ring (aql-disk-handle-ring handle))
        (cqe-ptr (aql-disk-handle-cqe-ptr handle)))
    ;; 1. Write WAL remove frame
    (let* ((frame (aql-wal-frame-remove key))
           (wal-fd (aql-disk-handle-wal-fd handle))
           (wal-offset (aql-disk-handle-wal-offset handle)))
      (with-lock (list frame)
        (uring-do ring cqe-ptr
          (lambda (sqe)
            (io-uring-prep-write sqe wal-fd (bytevector-pointer frame)
                                 (bytevector-length frame) wal-offset))))
      (uring-do ring cqe-ptr
        (lambda (sqe) (io-uring-prep-fsync sqe wal-fd 0)))
      (aql-disk-handle-wal-offset! handle
        (+ wal-offset (bytevector-length frame))))
    ;; 2. Insert tombstone into BST
    (aql-disk-handle-bst! handle
      (lbst-set (aql-disk-handle-bst handle) key aql-tombstone-value))
    ;; 3. Same flush/compaction checks
    (when (> (lbst-bytes (aql-disk-handle-bst handle)) %flush-threshold)
      (aql-serialize-bst-to-run handle))
    (when (> (length (aql-disk-handle-runs handle)) %compaction-threshold)
      (aql-compact! handle (aql-disk-handle-runs handle)))))

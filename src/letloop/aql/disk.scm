;; Copyright © 2024-2026 Amirouche BOUBEKKI <amirouche at hyper dev>
;;
;; AQL Block Storage Layer — LSM tree with sorted runs on disk.
;;
;; Read path:
;;   1. Check BST (recent writes)
;;   2. Check runs newest-to-oldest
;;   3. For each run: binary search block index, read block, search
;;   4. First hit wins
;;
;; Write path:
;;   1. Append WAL frame to wal.aql
;;   2. Apply to in-memory BST
;;   3. When BST exceeds threshold -> flush as new sorted run
;;
(library (letloop aql disk)

  (export
   ;; Bytevector comparator
   bytevector-compare
   bytevector<?
   bytevector<=?

   ;; Manifest
   aql-manifest-magic
   aql-manifest-version
   aql-manifest-header-size
   aql-manifest-run-entry-size
   make-aql-manifest
   aql-manifest?
   aql-manifest-key-max-bytes
   aql-manifest-value-max-bytes
   aql-manifest-block-size
   aql-manifest-encrypted?
   aql-manifest-next-sequence
   aql-manifest-runs
   make-aql-manifest-run-entry
   aql-manifest-run-entry?
   aql-manifest-run-entry-sequence-number
   aql-manifest-run-entry-block-count
   aql-run-filename
   aql-manifest->bytevector
   bytevector->aql-manifest
   aql-manifest-write!

   ;; Run file header
   aql-magic
   aql-version
   aql-run-header-size
   aql-default-block-size
   aql-crypto-overhead
   make-aql-run-header
   aql-run-header?
   aql-run-header-key-max-bytes
   aql-run-header-value-max-bytes
   aql-run-header-block-size
   aql-run-header-block-count
   aql-run-header-encrypted?
   aql-run-stride
   aql-run-block-file-offset
   aql-run-header->bytevector
   bytevector->aql-run-header

   ;; Block header
   aql-block-tag-data
   make-aql-block-header
   aql-block-header?
   aql-block-header-min-key
   aql-block-header-max-key
   aql-block-header-key-count
   aql-block-header-byte-size
   aql-block-header-max-size
   aql-block-header->bytevector
   bytevector->aql-block-header
   aql-block-header-byte-length

   ;; WAL
   aql-wal-tag-set
   aql-wal-tag-remove
   aql-wal-frame-set
   aql-wal-frame-remove
   aql-wal-parse-frames

   ;; KV pair packing
   aql-pack-kv-pair
   aql-kv-pair-size
   aql-tombstone?
   aql-tombstone-value
   aql-unpack-kv-pairs

   ;; Block index
   make-aql-block-index-entry
   aql-block-index-entry?
   aql-block-index-entry-header
   aql-block-index-entry-file-offset
   make-aql-block-index
   aql-block-index-empty
   aql-block-index-search

   ;; Run handle
   make-aql-run
   aql-run?
   aql-run-sequence-number
   aql-run-fd
   aql-run-header
   aql-run-block-index

   ;; Key distance
   aql-key-byte-distance
   aql-key-distance-from
   aql-key-extract-u64
   aql-key-tail-distance

   ;; Approximate counts
   aql-run-approximate-key-count
   aql-run-approximate-byte-count
   aql-approximate-key-count-range
   aql-approximate-byte-count-range
   aql-interpolate-count
   aql-interpolate-byte-size
   aql-approximate-key-count-total
   aql-approximate-byte-count-total

   ;; Buffer cache
   make-aql-buffer-cache
   aql-buffer-cache?
   aql-buffer-cache-init
   aql-buffer-cache-get
   aql-buffer-cache-claim
   aql-buffer-cache-release

   ;; Block I/O
   foreign-copy-to-bytevector
   aql-block-read
   aql-block-write-to-run

   ;; Encryption
   aql-block-encrypt
   aql-block-decrypt

   ;; Block packing
   aql-pack-block
   aql-unpack-block

   ;; Block serialization
   aql-serialize-bst-to-run

   ;; Read path
   aql-block-search-key
   aql-disk-get

   ;; Range query iterators
   make-bst-range-iterator
   make-run-range-iterator
   aql-disk-range

   ;; Compaction
   aql-compact!

   ;; Startup / open / close
   aql-read-run-block-index
   aql-disk-open
   aql-disk-close!

   ;; Write path
   aql-disk-set!
   aql-disk-remove!

   ;; Database handle
   make-aql-disk-handle
   aql-disk-handle?
   aql-disk-handle-dirpath
   aql-disk-handle-manifest
   aql-disk-handle-runs
   aql-disk-handle-bst
   aql-disk-handle-wal-fd
   aql-disk-handle-wal-offset
   aql-disk-handle-encryption-key
   aql-disk-handle-buffer-cache
   aql-disk-handle-ring
   aql-disk-handle-cqe-ptr

   ;; io_uring helper
   uring-do

   ;; Tests
   ~check-disk-000/comparator-equal
   ~check-disk-001/comparator-less
   ~check-disk-002/comparator-greater
   ~check-disk-003/comparator-prefix-shorter
   ~check-disk-004/comparator-prefix-longer
   ~check-disk-005/comparator-empty
   ~check-disk-006/comparator-predicates
   ~check-disk-010/manifest-empty
   ~check-disk-011/manifest-with-runs
   ~check-disk-012/manifest-bytevector-size
   ~check-disk-013/run-filename
   ~check-disk-020/run-header-roundtrip
   ~check-disk-021/run-header-encrypted
   ~check-disk-022/run-header-size
   ~check-disk-023/run-stride
   ~check-disk-024/block-file-offset
   ~check-disk-030/block-header-roundtrip
   ~check-disk-031/block-header-empty-keys
   ~check-disk-032/block-header-max-size
   ~check-disk-040/kv-pair-roundtrip
   ~check-disk-041/kv-pair-multiple
   ~check-disk-042/kv-pair-size
   ~check-disk-043/tombstone
   ~check-disk-050/wal-set-frame
   ~check-disk-051/wal-remove-frame
   ~check-disk-052/wal-multiple-frames
   ~check-disk-060/block-index-empty
   ~check-disk-061/block-index-search-single
   ~check-disk-062/block-index-search-multiple
   ~check-disk-070/key-distance-equal
   ~check-disk-071/key-distance-first-byte
   ~check-disk-072/key-distance-shared-prefix
   ~check-disk-073/key-distance-different-lengths
   ~check-disk-080/approx-count-empty-index
   ~check-disk-081/approx-count-fully-contained
   ~check-disk-082/approx-count-outside
   ~check-disk-083/approx-count-total
   ~check-disk-090/pack-single-block
   ~check-disk-091/pack-block-overflow
   ~check-disk-092/block-search-key
   )

  (import (chezscheme)
          (letloop r999)
          (letloop aql shims)
          (letloop cffi)
          (letloop sodium)
          (letloop liburing low)
          (only (letloop aql lbst)
                make-lbst lbst? lbst-set lbst-ref lbst-empty?
                lbst-key lbst-value lbst-start lbst-end
                lbst-next lbst-bytes lbst-length
                call-with-lbst))

  (include "letloop/aql/disk.body.scm")
  (include "letloop/aql/disk.check.scm")

  )

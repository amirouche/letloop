;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop bloom)
  (export bloom-bits-per-key
          bloom-hash-count
          bloom-key-hash
          bloom-build
          bloom-hashes-build
          bloom-open
          bloom-key-possible?
          bloom-hash-possible?
          ~check-bloom-no-false-negatives
          ~check-bloom-definitely-absent
          ~check-bloom-false-positive-rate-plausible
          ~check-bloom-serialize-round-trip
          ~check-bloom-empty
          ~check-bloom-open-rejects-garbage)
  (import (chezscheme)
          (letloop xxhash64))

  ;; Bloom filter: answers "is this exact key DEFINITELY absent?" so a
  ;; point lookup can skip a sorted file -- and its block fetch and
  ;; checksum verification -- without any I/O. It was written for the
  ;; sstables of an LSM tree, which without filters pays the cost of a
  ;; miss once per overlapping sstable; the comments below still speak
  ;; of sstables for that reason.
  ;;
  ;; Design: standard Kirsch-Mitzenmacher double hashing over a single
  ;; xxhash64 of the key -- a stable, persistent hash, which matters
  ;; because the filter outlives the process that built it: an unstable
  ;; hash (equal-hash, anything seeded per-run) would make every filter
  ;; wrong on the next boot. h1 = the hash's high 32 bits, h2 = the
  ;; low 32 bits forced odd (odd => h2 is coprime with the power-of-
  ;; two-free m below often enough; forcing odd avoids the degenerate
  ;; h2 = 0 which would probe one position k times). Probe i sets/
  ;; tests bit (h1 + i*h2) mod m. k = 7 probes at 10 bits/key gives
  ;; ~0.8% false positives -- the textbook operating point.
  ;;
  ;; Serialized form (no checksum of its own; the caller's framing is
  ;; expected to provide one):
  ;;   magic:4 = "BLM1"
  ;;   k:u32 big-endian (probe count, so the operating point can
  ;;     change later without a format break)
  ;;   bit-count:u64 big-endian (m)
  ;;   bits: ceil(m/8) bytes, bit i at byte i>>3, mask 1<<(i&7)
  ;;
  ;; Everything after the one xxhash64 call is fixnum arithmetic: h1
  ;; and h2 are 32-bit, i*h2 tops out below 2^36, and m for even a
  ;; 25M-key sstable is ~2^28 -- all comfortably inside Chez fixnums.

  (define bloom-bits-per-key 10)
  (define bloom-hash-count 7)
  (define bloom-header-size 16)
  (define bloom-magic #vu8(66 76 77 49)) ;; "BLM1"

  (define (bloom-key-hash key)
    ;; The one place a key is hashed; writer and reader both go
    ;; through this so the filter and its queries can never disagree
    ;; on the hash. Exact integer in [0, 2^64).
    (xxhash64 key))

  (define (bloom-hash-split h)
    ;; h1 (high 32) and h2 (low 32, forced odd) as fixnums. The input
    ;; may be a bignum (xxhash64 spans the full 64-bit range); the
    ;; outputs never are.
    (values (bitwise-arithmetic-shift-right h 32)
            (bitwise-ior (bitwise-and h #xFFFFFFFF) 1)))

  (define (bloom-size-for count)
    ;; m in bits: bits-per-key per key, rounded up to a whole number
    ;; of bytes, floored at 64 bits so the degenerate tiny-count case
    ;; still has room to spread probes.
    (fxmax 64 (fx* 8 (fxdiv (fx+ (fx* count bloom-bits-per-key) 7) 8))))

  (define (bloom-serialize-start bit-count)
    (let ((out (make-bytevector (fx+ bloom-header-size (fxdiv bit-count 8)) 0)))
      (bytevector-copy! bloom-magic 0 out 0 4)
      (bytevector-u32-set! out 4 bloom-hash-count (endianness big))
      (bytevector-u64-set! out 8 bit-count (endianness big))
      out))

  (define (bloom-bit-add! out bit-count h)
    (let-values (((h1 h2) (bloom-hash-split h)))
      (let loop ((i 0))
        (when (fx< i bloom-hash-count)
          (let* ((position (fxmod (fx+ h1 (fx* i h2)) bit-count))
                 (byte-index (fx+ bloom-header-size (fxsrl position 3)))
                 (mask (fxsll 1 (fxand position 7))))
            (bytevector-u8-set! out byte-index
                                (fxior (bytevector-u8-ref out byte-index) mask)))
          (loop (fx+ i 1))))))

  (define (bloom-hashes-build buffer count)
    ;; BUFFER holds COUNT native-endian u64 hashes back to back (the
    ;; writer accumulates hashes this way -- 8 flat bytes per key --
    ;; rather than as a list, so a 25M-key compaction does not retain
    ;; 25M heap-allocated integers while the sstable is written).
    ;; Returns the serialized filter.
    (let* ((bit-count (bloom-size-for count))
           (out (bloom-serialize-start bit-count)))
      (let loop ((i 0))
        (if (fx= i count)
          out
          (begin
            (bloom-bit-add! out bit-count
                            (bytevector-u64-native-ref buffer (fx* i 8)))
            (loop (fx+ i 1)))))))

  (define (bloom-build keys)
    ;; Convenience over a key list (checks, small callers). The
    ;; production writer uses bloom-hashes-build.
    (let* ((count (length keys))
           (bit-count (bloom-size-for count))
           (out (bloom-serialize-start bit-count)))
      (for-each (lambda (key) (bloom-bit-add! out bit-count (bloom-key-hash key)))
                keys)
      out))

  (define-record-type (bloom bloom-make bloom?)
    (fields bytes bit-count probe-count))

  (define (bloom-open bytes)
    (unless (and (fx>= (bytevector-length bytes) bloom-header-size)
                 (bytevector=? (let ((magic (make-bytevector 4)))
                                 (bytevector-copy! bytes 0 magic 0 4)
                                 magic)
                               bloom-magic))
      (error 'bloom-open "not a bloom filter (bad magic or truncated)"))
    (let ((probe-count (bytevector-u32-ref bytes 4 (endianness big)))
          (bit-count (bytevector-u64-ref bytes 8 (endianness big))))
      (unless (fx= (bytevector-length bytes)
                   (fx+ bloom-header-size (fxdiv bit-count 8)))
        (error 'bloom-open "bloom filter size disagrees with its header"))
      (bloom-make bytes bit-count probe-count)))

  (define (bloom-hash-possible? filter h)
    ;; #f: the key is DEFINITELY absent (the guarantee callers act
    ;; on). #t: the key may be present -- proceed to the real lookup.
    (let ((bytes (bloom-bytes filter))
          (bit-count (bloom-bit-count filter))
          (probe-count (bloom-probe-count filter)))
      (let-values (((h1 h2) (bloom-hash-split h)))
        (let loop ((i 0))
          (or (fx= i probe-count)
              (let* ((position (fxmod (fx+ h1 (fx* i h2)) bit-count))
                     (byte (bytevector-u8-ref
                             bytes (fx+ bloom-header-size (fxsrl position 3)))))
                (and (fx= (fxand byte (fxsll 1 (fxand position 7)))
                          (fxsll 1 (fxand position 7)))
                     (loop (fx+ i 1)))))))))

  (define (bloom-key-possible? filter key)
    (bloom-hash-possible? filter (bloom-key-hash key)))

  (include "letloop/bloom.check.scm"))

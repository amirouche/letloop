;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Included at the tail of the library; discovered by `make check` via
;; the ~check- exports.

;; ---- Checks ----

(define bloom-check-key
  (lambda (i)
    ;; Deterministic distinct fixed-width keys: a tag byte and a
    ;; big-endian integer.
    (let ((out (make-bytevector 9 0)))
      (bytevector-u8-set! out 0 (fxand i #xFF))
      (bytevector-u64-set! out 1 (fx* i 2654435761) (endianness big))
      out)))

(define ~check-bloom-no-false-negatives
  (lambda ()
    ;; The one property a bloom filter must never violate: a key that
    ;; went in always answers "possible".
    (let* ((keys (let loop ((i 0) (acc '()))
                   (if (fx= i 5000) acc
                       (loop (fx+ i 1) (cons (bloom-check-key i) acc)))))
           (filter (bloom-open (bloom-build keys))))
      (for-each (lambda (key) (assert (bloom-key-possible? filter key))) keys)
      #t)))

(define ~check-bloom-definitely-absent
  (lambda ()
    ;; A filter over one keyspace must reject at least SOME keys from
    ;; a disjoint keyspace -- if every absent key came back
    ;; "possible" the filter would be a no-op.
    (let* ((keys (let loop ((i 0) (acc '()))
                   (if (fx= i 1000) acc
                       (loop (fx+ i 1) (cons (bloom-check-key i) acc)))))
           (filter (bloom-open (bloom-build keys)))
           (absent-rejected
             (let loop ((i 100000) (rejected 0))
               (if (fx= i 101000) rejected
                   (loop (fx+ i 1)
                         (if (bloom-key-possible? filter (bloom-check-key i))
                           rejected
                           (fx+ rejected 1)))))))
      (assert (fx> absent-rejected 900))
      #t)))

(define ~check-bloom-false-positive-rate-plausible
  (lambda ()
    ;; At 10 bits/key, k=7, theory says ~0.8% false positives. Assert
    ;; only a loose ceiling (5%) so the check pins "the filter works"
    ;; without being brittle to the exact hash mixing.
    (let* ((keys (let loop ((i 0) (acc '()))
                   (if (fx= i 10000) acc
                       (loop (fx+ i 1) (cons (bloom-check-key i) acc)))))
           (filter (bloom-open (bloom-build keys)))
           (false-positives
             (let loop ((i 500000) (hits 0))
               (if (fx= i 510000) hits
                   (loop (fx+ i 1)
                         (if (bloom-key-possible? filter (bloom-check-key i))
                           (fx+ hits 1)
                           hits))))))
      (assert (fx< false-positives 500))
      #t)))

(define ~check-bloom-serialize-round-trip
  (lambda ()
    ;; The serialized bytes ARE the filter -- reopening them must
    ;; answer identically, and the header must describe the bytes.
    (let* ((keys (list (bloom-check-key 1) (bloom-check-key 2) (bloom-check-key 3)))
           (bytes (bloom-build keys))
           (reopened (bloom-open bytes)))
      (assert (fx= (bloom-probe-count reopened) bloom-hash-count))
      (for-each (lambda (key) (assert (bloom-key-possible? reopened key))) keys)
      ;; hashes-build over the same keys must produce the same bytes
      (let ((buffer (make-bytevector (fx* 8 (length keys)))))
        (let loop ((i 0) (rest keys))
          (unless (null? rest)
            (bytevector-u64-native-set! buffer (fx* i 8) (bloom-key-hash (car rest)))
            (loop (fx+ i 1) (cdr rest))))
        (assert (bytevector=? bytes (bloom-hashes-build buffer (length keys)))))
      #t)))

(define ~check-bloom-empty
  (lambda ()
    ;; An empty filter rejects everything -- correct for an empty
    ;; sstable, where every key is definitely absent.
    (let ((filter (bloom-open (bloom-build '()))))
      (assert (not (bloom-key-possible? filter (bloom-check-key 7))))
      #t)))

(define ~check-bloom-open-rejects-garbage
  (lambda ()
    (assert (guard (condition (#t #t))
              (bloom-open (make-bytevector 4 0))
              #f))
    (assert (guard (condition (#t #t))
              ;; right magic, header claims more bits than the bytes hold
              (let ((bytes (bloom-build '())))
                (bytevector-u64-set! bytes 8 (expt 2 20) (endianness big))
                (bloom-open bytes))
              #f))
    #t))

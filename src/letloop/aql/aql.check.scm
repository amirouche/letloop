;; Copyright © 2019-2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>

;; Helpers

(define make-seed
  (lambda ()
    (let* ((now (current-time))
           (seed (* (time-second now) (time-nanosecond now))))
      (+ (modulo seed (expt 2 32)) 1))))

(define random-bytevector
  (lambda (max-length)
    (define bv (make-bytevector (fx+ (random max-length) 1)))
    (let loop ((i (bytevector-length bv)))
      (unless (fxzero? i)
        (bytevector-u8-set! bv (fx- i 1) (random 256))
        (loop (fx- i 1))))
    bv))

(define random-alist
  (lambda (n)
    (map (lambda _ (cons (random-bytevector 16)
                         (random-bytevector 16)))
         (iota n))))

(define bytevector<?
  (lambda (a b)
    (let ((end (fxmin (bytevector-length a)
                      (bytevector-length b))))
      (let loop ((i 0))
        (if (fx=? end i)
            (fx<? (bytevector-length a)
                  (bytevector-length b))
            (let ((ab (bytevector-u8-ref a i))
                  (bb (bytevector-u8-ref b i)))
              (cond
               ((fx<? ab bb) #t)
               ((fx>? ab bb) #f)
               (else (loop (fx+ i 1))))))))))

(define sort-alist
  (lambda (alist)
    (sort (lambda (a b) (bytevector<? (car a) (car b))) alist)))

;; Deduplicate an alist keeping the last occurrence of each key
(define dedup-alist
  (lambda (alist)
    (let loop ((alist (reverse alist))
               (seen '())
               (out '()))
      (if (null? alist)
          (reverse out)
          (let ((key (caar alist)))
            (if (memp (lambda (k) (bytevector=? k key)) seen)
                (loop (cdr alist) seen out)
                (loop (cdr alist)
                      (cons key seen)
                      (cons (car alist) out))))))))

(define get-seed
  (lambda ()
    (string->number
     (or (getenv "LETLOOP_SEED")
         (number->string
          (+ (- (random (expt 2 32)) 1) 1))))))

(define iteration-count
  (lambda ()
    (if (getenv "LETLOOP_SEED") (iota 1) (iota 100))))

;; Deterministic tests

(define ~check-aql-000
  (lambda ()
    (let ((db (make-aql)))
      (check (aql? db))
      (check (= (aql-approximate-keys db) 0)))))

(define ~check-aql-001
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 1 2 3) (bytevector 4 5 6))
      (check (bytevector=? (aql-query db (bytevector 1 2 3))
                           (bytevector 4 5 6))))))

(define ~check-aql-002
  (lambda ()
    (let ((db (make-aql)))
      (check (not (aql-query db (bytevector 1 2 3)))))))

(define ~check-aql-003
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 10) (bytevector 20))
      (aql-remove! db (bytevector 10))
      (check (not (aql-query db (bytevector 10)))))))

(define ~check-aql-004
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 3) (bytevector 30))
      (aql-set! db (bytevector 1) (bytevector 10))
      (aql-set! db (bytevector 2) (bytevector 20))
      (let ((result (aql-query db (bytevector 0) (bytevector 4))))
        (check (= (length result) 3))
        ;; verify sorted order
        (check (bytevector=? (caar result) (bytevector 1)))
        (check (bytevector=? (caadr result) (bytevector 2)))
        (check (bytevector=? (caaddr result) (bytevector 3)))))))

(define ~check-aql-005
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 3) (bytevector 30))
      (aql-set! db (bytevector 1) (bytevector 10))
      (aql-set! db (bytevector 2) (bytevector 20))
      ;; reverse range: key > other
      (let ((result (aql-query db (bytevector 4) (bytevector 0))))
        (check (= (length result) 3))
        ;; verify reverse sorted order
        (check (bytevector=? (caar result) (bytevector 3)))
        (check (bytevector=? (caadr result) (bytevector 2)))
        (check (bytevector=? (caaddr result) (bytevector 1)))))))

(define ~check-aql-006
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 1) (bytevector 10))
      (aql-set! db (bytevector 2) (bytevector 20))
      (aql-set! db (bytevector 3) (bytevector 30))
      (aql-set! db (bytevector 4) (bytevector 40))
      (aql-set! db (bytevector 5) (bytevector 50))
      ;; offset=1, limit=2
      (let ((result (aql-query db (bytevector 0) (bytevector 6) 1 2)))
        (check (= (length result) 2))
        (check (bytevector=? (caar result) (bytevector 2)))
        (check (bytevector=? (caadr result) (bytevector 3)))))))

(define ~check-aql-007
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 42) (bytevector 99))
      (check (bytevector=? (aql-keys db (bytevector 42)) (bytevector 42)))
      (check (not (aql-keys db (bytevector 13)))))))

(define ~check-aql-008
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 3) (bytevector 30))
      (aql-set! db (bytevector 1) (bytevector 10))
      (aql-set! db (bytevector 2) (bytevector 20))
      (let ((result (aql-keys db (bytevector 0) (bytevector 4))))
        (check (= (length result) 3))
        (check (bytevector=? (car result) (bytevector 1)))
        (check (bytevector=? (cadr result) (bytevector 2)))
        (check (bytevector=? (caddr result) (bytevector 3)))))))

(define ~check-aql-009
  (lambda ()
    (check (bytevector=? (aql-bytevector-next-prefix (bytevector 1 2 3))
                         (bytevector 1 2 4)))
    (check (bytevector=? (aql-bytevector-next-prefix (bytevector 1 255))
                         (bytevector 2)))
    (check (not (aql-bytevector-next-prefix (bytevector 255))))))

(define ~check-aql-010
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 1) (bytevector 10))
      (aql-set! db (bytevector 2) (bytevector 20))
      (aql-set! db (bytevector 3) (bytevector 30))
      (aql-set! db (bytevector 4) (bytevector 40))
      (aql-set! db (bytevector 5) (bytevector 50))
      ;; remove range [2, 5) — should remove keys 2, 3, 4
      (aql-remove! db (bytevector 2) (bytevector 5))
      (let ((result (aql-query db (bytevector 0) (bytevector 6))))
        (check (= (length result) 2))
        (check (bytevector=? (caar result) (bytevector 1)))
        (check (bytevector=? (caadr result) (bytevector 5)))))))

(define ~check-aql-011
  (lambda ()
    (let ((db (make-aql)))
      (check (= (aql-approximate-keys db) 0))
      (check (= (aql-approximate-bytes db) 0))
      (aql-set! db (bytevector 1) (bytevector 10))
      (aql-set! db (bytevector 2) (bytevector 20))
      (check (= (aql-approximate-keys db) 2))
      ;; bytes = sum of key + value lengths = (1+1) + (1+1) = 4
      (check (= (aql-approximate-bytes db) 4)))))

(define ~check-aql-012
  (lambda ()
    (let* ((db (make-aql))
           (tv (make-aql-transaction-variable 'init)))
      (aql-in-transaction db
        (lambda (tx)
          (check (eq? (tv tx) 'init))
          (tv tx 'updated)
          (check (eq? (tv tx) 'updated)))))))

(define ~check-aql-013
  (lambda ()
    (let ((db (make-aql)))
      (aql-set! db (bytevector 1) (bytevector 10))
      ;; Transaction that raises — changes should not commit
      (aql-in-transaction db
        (lambda (tx)
          (aql-set! tx (bytevector 2) (bytevector 20))
          (raise 'boom))
        (lambda (ex) #t))  ;; failure handler
      ;; key 2 should not exist
      (check (not (aql-query db (bytevector 2))))
      ;; key 1 should still exist
      (check (bytevector=? (aql-query db (bytevector 1))
                           (bytevector 10))))))

;; Randomized / property tests

(define ~check-aql-100/random
  (lambda ()
    (for-each
     (lambda _
       (let* ((seed (pk 'LETLOOP_SEED= (get-seed)))
              (_ (random-seed seed))
              (n (fx+ 2 (random 50)))
              (pairs (random-alist n))
              (db (make-aql)))
         ;; Insert all pairs in a single transaction
         (aql-in-transaction db
           (lambda (tx)
             (for-each (lambda (p) (aql-set! tx (car p) (cdr p)))
                       pairs)))
         ;; Query each key — last write wins for duplicate keys
         (let ((expected (dedup-alist pairs)))
           (for-each
            (lambda (p)
              (let ((val (aql-query db (car p))))
                (assert val)
                (assert (bytevector=? val (cdr p)))))
            expected))))
     (iteration-count))))

(define ~check-aql-101/random
  (lambda ()
    (for-each
     (lambda _
       (let* ((seed (pk 'LETLOOP_SEED= (get-seed)))
              (_ (random-seed seed))
              (n (fx+ 2 (random 50)))
              (pairs (random-alist n))
              (db (make-aql)))
         (aql-in-transaction db
           (lambda (tx)
             (for-each (lambda (p) (aql-set! tx (car p) (cdr p)))
                       pairs)))
         ;; Range query over everything
         (let* ((result (aql-query db (bytevector 0) (bytevector 255 255)))
                (expected (sort-alist (dedup-alist pairs))))
           (assert (= (length result) (length expected)))
           (for-each
            (lambda (r e)
              (assert (bytevector=? (car r) (car e)))
              (assert (bytevector=? (cdr r) (cdr e))))
            result expected))))
     (iteration-count))))

(define ~check-aql-102/random
  (lambda ()
    (for-each
     (lambda _
       (let* ((seed (pk 'LETLOOP_SEED= (get-seed)))
              (_ (random-seed seed))
              (n (fx+ 4 (random 30)))
              (pairs (dedup-alist (random-alist n)))
              (db (make-aql)))
         (aql-in-transaction db
           (lambda (tx)
             (for-each (lambda (p) (aql-set! tx (car p) (cdr p)))
                       pairs)))
         ;; Remove a random subset
         (let* ((to-remove (filter (lambda _ (fxzero? (random 2))) pairs))
                (to-keep
                 (filter (lambda (p)
                           (not (memp (lambda (r)
                                        (bytevector=? (car r) (car p)))
                                      to-remove)))
                         pairs)))
           (for-each (lambda (p) (aql-remove! db (car p))) to-remove)
           ;; Removed keys return #f
           (for-each
            (lambda (p)
              (assert (not (aql-query db (car p)))))
            to-remove)
           ;; Remaining keys still have correct values
           (for-each
            (lambda (p)
              (let ((val (aql-query db (car p))))
                (assert val)
                (assert (bytevector=? val (cdr p)))))
            to-keep))))
     (iteration-count))))

(define ~check-aql-103/random
  (lambda ()
    (for-each
     (lambda _
       (let* ((seed (pk 'LETLOOP_SEED= (get-seed)))
              (_ (random-seed seed))
              (n (fx+ 2 (random 50)))
              (pairs (random-alist n))
              (db (make-aql))
              (lo (bytevector 0))
              (hi (bytevector 255 255)))
         (aql-in-transaction db
           (lambda (tx)
             (for-each (lambda (p) (aql-set! tx (car p) (cdr p)))
                       pairs)))
         ;; aql-keys range should equal (map car (aql-query ...)) for same range
         (let* ((query-result (aql-query db lo hi))
                (keys-result (aql-keys db lo hi)))
           (assert (= (length keys-result) (length query-result)))
           (for-each
            (lambda (k pair)
              (assert (bytevector=? k (car pair))))
            keys-result query-result))))
     (iteration-count))))

(define ~check-aql-104/random
  (lambda ()
    (for-each
     (lambda _
       (let* ((seed (pk 'LETLOOP_SEED= (get-seed)))
              (_ (random-seed seed))
              (prefix-byte (random 254))
              (prefix (bytevector prefix-byte))
              (next (aql-bytevector-next-prefix prefix))
              (db (make-aql))
              (n (fx+ 1 (random 20)))
              (prefixed-keys
               (map (lambda _
                      (let* ((suffix (random-bytevector 8))
                             (key (make-bytevector (fx+ 1 (bytevector-length suffix)))))
                        (bytevector-u8-set! key 0 prefix-byte)
                        (bytevector-copy! suffix 0 key 1 (bytevector-length suffix))
                        key))
                    (iota n))))
         ;; Insert keys outside the prefix
         (when (fx>? prefix-byte 0)
           (aql-set! db (bytevector (fx- prefix-byte 1)) (bytevector 0)))
         (aql-set! db (bytevector (fx+ prefix-byte 1) 0) (bytevector 0))
         ;; Insert prefixed keys
         (for-each (lambda (k) (aql-set! db k (bytevector 1))) prefixed-keys)
         ;; Query [prefix, next-prefix) should return exactly the prefixed keys
         (let* ((result (aql-query db prefix next))
                (result-keys (map car result))
                (unique-expected
                 (map car
                      (sort-alist
                       (dedup-alist
                        (map (lambda (k) (cons k (bytevector 1)))
                             prefixed-keys))))))
           (assert (= (length result-keys) (length unique-expected)))
           (for-each
            (lambda (r e)
              (assert (bytevector=? r e)))
            result-keys unique-expected))))
     (iteration-count))))

(define ~check-aql-105/random
  (lambda ()
    (for-each
     (lambda _
       (let* ((seed (pk 'LETLOOP_SEED= (get-seed)))
              (_ (random-seed seed))
              (n (fx+ 2 (random 50)))
              (db (make-aql))
              (keys (let loop ((i 0) (ks '()))
                      (if (fx=? i n)
                          ks
                          (let ((k (make-bytevector 8)))
                            (bytevector-u64-set! k 0 i 'big)
                            (loop (fx+ i 1) (cons k ks)))))))
         ;; Insert all
         (aql-in-transaction db
           (lambda (tx)
             (for-each (lambda (k) (aql-set! tx k (bytevector 1))) keys)))
         (assert (= (aql-approximate-keys db) n))
         ;; Remove a random subset
         (let* ((m (random n))
                (to-remove (list-head keys m)))
           (for-each (lambda (k) (aql-remove! db k)) to-remove)
           (assert (= (aql-approximate-keys db) (- n m))))))
     (iteration-count))))

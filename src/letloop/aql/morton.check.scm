(define ~check-morton-000
  (lambda ()
    ;; 2D 32-bit round-trip
    (let ((values '(42 1337)))
      (check values (morton-deinterleave 2 32
                      (morton-interleave 2 32 values))))))

(define ~check-morton-001
  (lambda ()
    ;; 3D 32-bit round-trip
    (let ((values '(100 200 300)))
      (check values (morton-deinterleave 3 32
                      (morton-interleave 3 32 values))))))

(define ~check-morton-002
  (lambda ()
    ;; 4D 32-bit round-trip
    (let ((values '(1 2 3 4)))
      (check values (morton-deinterleave 4 32
                      (morton-interleave 4 32 values))))))

(define ~check-morton-003
  (lambda ()
    ;; Z-order preservation for 2D:
    ;; dim0 bit comes before dim1 bit in interleaving, so:
    ;; (0,0)=0 < (0,1)=1 < (1,0)=2 < (1,1)=3
    (let ((z00 (morton-interleave 2 32 '(0 0)))
          (z01 (morton-interleave 2 32 '(0 1)))
          (z10 (morton-interleave 2 32 '(1 0)))
          (z11 (morton-interleave 2 32 '(1 1))))
      (check #t (and (eq? 'smaller (byter-compare z00 z01))
                      (eq? 'smaller (byter-compare z01 z10))
                      (eq? 'smaller (byter-compare z10 z11)))))))

(define ~check-morton-004
  (lambda ()
    ;; Storage round-trip via aql
    (let* ((okvs (make-aql))
           (m (make-morton (bytevector 200) 2 32)))
      (aql-in-transaction okvs
        (lambda (tx)
          (morton-set! tx m '(10 20) (bytevector 99))))
      (check (bytevector 99)
             (aql-in-transaction okvs
               (lambda (tx)
                 (morton-ref tx m '(10 20))))))))

(define ~check-morton-005
  (lambda ()
    ;; Bounding-box query returns correct points
    (let* ((okvs (make-aql))
           (m (make-morton (bytevector 201) 2 32)))
      (aql-in-transaction okvs
        (lambda (tx)
          (morton-set! tx m '(1 1) (bytevector 1))
          (morton-set! tx m '(5 5) (bytevector 2))
          (morton-set! tx m '(3 3) (bytevector 3))
          (morton-set! tx m '(10 10) (bytevector 4))))
      ;; Query box [2,2]-[6,6] should return (3,3) and (5,5)
      (check 2 (aql-in-transaction okvs
                 (lambda (tx)
                   (length (generator->list
                            (morton-query tx m '(2 2) '(6 6))))))))))

(define ~check-morton-006
  (lambda ()
    ;; Bounding-box query excludes out-of-range points
    (let* ((okvs (make-aql))
           (m (make-morton (bytevector 202) 2 32)))
      (aql-in-transaction okvs
        (lambda (tx)
          (morton-set! tx m '(0 0) (bytevector 1))
          (morton-set! tx m '(100 100) (bytevector 2))))
      ;; Query box [10,10]-[20,20] should return nothing
      (check 0 (aql-in-transaction okvs
                 (lambda (tx)
                   (length (generator->list
                            (morton-query tx m '(10 10) '(20 20))))))))))

(define ~check-morton-007/random
  (lambda ()
    ;; Property-based: random points, query box, compare with brute-force
    (let* ((okvs (make-aql))
           (m (make-morton (bytevector 203) 2 32))
           (points (map (lambda (_) (list (random 1000) (random 1000)))
                        (iota 100))))
      (aql-in-transaction okvs
        (lambda (tx)
          (for-each (lambda (p)
                      (morton-set! tx m p (bytevector)))
                    points)))
      (let ((mins '(200 200))
            (maxs '(500 500)))
        (let ((expected (filter (lambda (p) (morton-in-box? p mins maxs)) points)))
          (check (length expected)
                 (aql-in-transaction okvs
                   (lambda (tx)
                     (length (generator->list
                              (morton-query tx m mins maxs)))))))))))

(define ~check-morton-008
  (lambda ()
    ;; Edge cases: zeros and single-point box
    (let* ((okvs (make-aql))
           (m (make-morton (bytevector 204) 2 32)))
      (aql-in-transaction okvs
        (lambda (tx)
          (morton-set! tx m '(0 0) (bytevector 1))
          (morton-set! tx m '(5 5) (bytevector 2))))
      ;; Single-point box [0,0]-[0,0]
      (check 1 (aql-in-transaction okvs
                 (lambda (tx)
                   (length (generator->list
                            (morton-query tx m '(0 0) '(0 0))))))))))

(define ~check-morton-009
  (lambda ()
    ;; 64-bit values round-trip
    (let ((values (list (- (expt 2 64) 1) (- (expt 2 64) 1))))
      (check values (morton-deinterleave 2 64
                      (morton-interleave 2 64 values))))))

;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>

(define ~check-xz-000
  (lambda ()
    ;; 2D point encoding: same code for same point
    (let ((xz (make-xzstore 2 8)))
      (check (xzstore-index xz '(10.0 20.0) '(10.0 20.0))
             (xzstore-index xz '(10.0 20.0) '(10.0 20.0))))))

(define ~check-xz-001
  (lambda ()
    ;; 2D bounding box: different extents get different codes
    (let ((xz (make-xzstore 2 8)))
      (check #t (not (= (xzstore-index xz '(0.0 0.0) '(1.0 1.0))
                         (xzstore-index xz '(0.0 0.0) '(10.0 10.0))))))))

(define ~check-xz-002
  (lambda ()
    ;; 2D range query finds contained objects
    (let* ((xz (make-xzstore 2 8 (list (cons 0.0 100.0) (cons 0.0 100.0))))
           (okvs (make-aql))
           (prefix (bytevector 70)))
      (aql-in-transaction okvs
        (lambda (tx)
          (xzstore-set! tx prefix xz '(10.0 10.0) '(12.0 12.0) (bytevector 1))
          (xzstore-set! tx prefix xz '(50.0 50.0) '(52.0 52.0) (bytevector 2))
          (xzstore-set! tx prefix xz '(80.0 80.0) '(85.0 85.0) (bytevector 3))))
      (let ((results (aql-in-transaction okvs
                       (lambda (tx)
                         (xzstore-query tx prefix xz '(5.0 5.0) '(55.0 55.0))))))
        (check #t (>= (length results) 2))))))

(define ~check-xz-003
  (lambda ()
    ;; 2D range query excludes non-overlapping objects
    (let* ((xz (make-xzstore 2 8 (list (cons 0.0 100.0) (cons 0.0 100.0))))
           (okvs (make-aql))
           (prefix (bytevector 71)))
      (aql-in-transaction okvs
        (lambda (tx)
          (xzstore-set! tx prefix xz '(90.0 90.0) '(95.0 95.0) (bytevector 1))))
      (let ((results (aql-in-transaction okvs
                       (lambda (tx)
                         (xzstore-query tx prefix xz '(0.0 0.0) '(10.0 10.0))))))
        (check 0 (length results))))))

(define ~check-xz-004
  (lambda ()
    ;; 2D storage round-trip
    (let* ((xz (make-xzstore 2 8 (list (cons 0.0 100.0) (cons 0.0 100.0))))
           (okvs (make-aql))
           (prefix (bytevector 72)))
      (aql-in-transaction okvs
        (lambda (tx)
          (xzstore-set! tx prefix xz '(25.0 25.0) '(30.0 30.0) (bytevector 42))))
      (check (bytevector 42)
             (aql-in-transaction okvs
               (lambda (tx)
                 (xzstore-ref tx prefix xz '(25.0 25.0) '(30.0 30.0))))))))

(define ~check-xz-005
  (lambda ()
    ;; 3D encoding round-trip
    (let* ((xz (make-xzstore 3 6 (list (cons 0.0 100.0) (cons 0.0 100.0) (cons 0.0 100.0))))
           (okvs (make-aql))
           (prefix (bytevector 74)))
      (aql-in-transaction okvs
        (lambda (tx)
          (xzstore-set! tx prefix xz '(10.0 10.0 10.0) '(15.0 15.0 15.0) (bytevector 33))))
      (check (bytevector 33)
             (aql-in-transaction okvs
               (lambda (tx)
                 (xzstore-ref tx prefix xz '(10.0 10.0 10.0) '(15.0 15.0 15.0))))))))

(define ~check-xz-006
  (lambda ()
    ;; 3D range query
    (let* ((xz (make-xzstore 3 6 (list (cons 0.0 100.0) (cons 0.0 100.0) (cons 0.0 100.0))))
           (okvs (make-aql))
           (prefix (bytevector 75)))
      (aql-in-transaction okvs
        (lambda (tx)
          (xzstore-set! tx prefix xz '(10.0 10.0 10.0) '(12.0 12.0 12.0) (bytevector 1))
          (xzstore-set! tx prefix xz '(50.0 50.0 50.0) '(52.0 52.0 52.0) (bytevector 2))
          (xzstore-set! tx prefix xz '(80.0 80.0 80.0) '(85.0 85.0 85.0) (bytevector 3))))
      (let ((results (aql-in-transaction okvs
                       (lambda (tx)
                         (xzstore-query tx prefix xz '(5.0 5.0 5.0) '(55.0 55.0 55.0))))))
        (check #t (>= (length results) 2))))))

(define ~check-xz-007/random
  (lambda ()
    ;; 2D random: insert boxes, query large region
    (let* ((xz (make-xzstore 2 8 (list (cons 0.0 1000.0) (cons 0.0 1000.0))))
           (okvs (make-aql))
           (prefix (bytevector 73)))
      (aql-in-transaction okvs
        (lambda (tx)
          (let loop ((i 0))
            (when (< i 50)
              (let ((x (fixnum->flonum (random 450)))
                    (y (fixnum->flonum (random 450))))
                (xzstore-set! tx prefix xz
                              (list x y)
                              (list (fl+ x (fixnum->flonum (+ 1 (random 10))))
                                    (fl+ y (fixnum->flonum (+ 1 (random 10)))))
                              (bytevector)))
              (loop (+ i 1))))))
      (let ((results (aql-in-transaction okvs
                       (lambda (tx)
                         (xzstore-query tx prefix xz '(0.0 0.0) '(500.0 500.0))))))
        ;; Some objects may collide on the same XZ-code
        (check #t (> (length results) 0))))))

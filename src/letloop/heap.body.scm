;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Vector-backed binary min-heap keyed on numbers. Entries are (key
;; . value) pairs; the minimum key sits at index zero. The vector
;; doubles when full.

(define-record-type* <heap>
  (make-heap vec size)
  heap?
  (vec heap-vec heap-vec!)
  (size heap-size heap-size!))

(define heap-new
  (lambda ()
    (make-heap (make-vector 64) 0)))

(define heap-empty?
  (lambda (h)
    (fxzero? (heap-size h))))

(define heap-min
  (lambda (h)
    (if (heap-empty? h)
        #f
        (vector-ref (heap-vec h) 0))))

(define heap-add!
  (lambda (h k v)
    (let* ((n (heap-size h))
           (vec (heap-vec h)))
      (when (fx>=? n (vector-length vec))
        (let ((new (make-vector (fx* 2 (vector-length vec)))))
          (let cp ((i 0))
            (when (fx<? i n)
              (vector-set! new i (vector-ref vec i))
              (cp (fx+ i 1))))
          (set! vec new)
          (heap-vec! h new)))
      (vector-set! vec n (cons k v))
      (heap-size! h (fx+ n 1))
      (let up ((i n))
        (when (fx>? i 0)
          (let ((parent (fxsrl (fx- i 1) 1)))
            (when (< (car (vector-ref vec i))
                     (car (vector-ref vec parent)))
              (let ((tmp (vector-ref vec i)))
                (vector-set! vec i (vector-ref vec parent))
                (vector-set! vec parent tmp))
              (up parent))))))))

(define heap-pop-min!
  (lambda (h)
    (let* ((n (heap-size h))
           (vec (heap-vec h))
           (min (vector-ref vec 0)))
      (heap-size! h (fx- n 1))
      (let ((last-idx (fx- n 1)))
        (vector-set! vec 0 (vector-ref vec last-idx))
        (vector-set! vec last-idx #f)
        (let down ((i 0))
          (let* ((left (fx+ (fx* 2 i) 1))
                 (right (fx+ left 1))
                 (smallest i))
            (when (and (fx<? left last-idx)
                       (< (car (vector-ref vec left))
                          (car (vector-ref vec smallest))))
              (set! smallest left))
            (when (and (fx<? right last-idx)
                       (< (car (vector-ref vec right))
                          (car (vector-ref vec smallest))))
              (set! smallest right))
            (unless (fx=? smallest i)
              (let ((tmp (vector-ref vec i)))
                (vector-set! vec i (vector-ref vec smallest))
                (vector-set! vec smallest tmp))
              (down smallest)))))
      min)))

;; Destructive: pops every entry with key <= k off H into a fresh
;; heap, returning (values before h). Unlike sq-split, H is mutated.
(define heap-split
  (lambda (h k)
    (let ((before (heap-new)))
      (let pop ()
        (if (heap-empty? h)
            (values before h)
            (let ((min (heap-min h)))
              (if (<= (car min) k)
                  (begin
                    (heap-pop-min! h)
                    (heap-add! before (car min) (cdr min))
                    (pop))
                  (values before h))))))))

;; Visits entries in vector order, not key order.
(define heap-for-each
  (lambda (h proc)
    (let ((n (heap-size h))
          (vec (heap-vec h)))
      (let loop ((i 0))
        (when (fx<? i n)
          (let ((kv (vector-ref vec i)))
            (proc (car kv) (cdr kv)))
          (loop (fx+ i 1)))))))

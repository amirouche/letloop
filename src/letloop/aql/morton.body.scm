;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Morton codes (Z-order curves) for multi-dimensional spatial indexing

;; Record type

(define-record-type* <morton>
  (make-morton prefix dimensions bits)
  morton?
  (prefix morton-prefix)
  (dimensions morton-dimensions)
  (bits morton-bits))

;; Helpers

(define integer->fixed-bytevector
  (lambda (integer byte-count)
    (let ((bv (make-bytevector byte-count 0)))
      (let loop ((i (- byte-count 1))
                 (n integer))
        (when (and (>= i 0) (positive? n))
          (bytevector-u8-set! bv i (bitwise-and n #xFF))
          (loop (- i 1) (bitwise-arithmetic-shift-right n 8))))
      bv)))

(define fixed-bytevector->integer
  (lambda (bv)
    (let loop ((i 0) (acc 0))
      (if (= i (bytevector-length bv))
          acc
          (loop (+ i 1)
                (+ (bitwise-arithmetic-shift-left acc 8)
                   (bytevector-u8-ref bv i)))))))

;; Bit interleaving
;;
;; For ndims dimensions and bits per dimension, iterate from the most
;; significant bit to the least. At each bit position b, process
;; dimensions 0..ndims-1, extracting bit b from each value and
;; shifting it into the result. The output is a fixed-width
;; big-endian bytevector of ceil(ndims * bits / 8) bytes.

(define morton-interleave
  (lambda (ndims bits values)
    (let ((total-bits (* ndims bits))
          (vals (list->vector values)))
      (let loop-bit ((b (- bits 1))
                     (result 0))
        (if (< b 0)
            (integer->fixed-bytevector result
                                       (fxquotient (+ total-bits 7) 8))
            (let loop-dim ((d 0)
                           (result result))
              (if (= d ndims)
                  (loop-bit (- b 1) result)
                  (loop-dim (+ d 1)
                            (bitwise-ior
                             (bitwise-arithmetic-shift-left result 1)
                             (if (bitwise-bit-set? (vector-ref vals d) b)
                                 1 0))))))))))

(define morton-deinterleave
  (lambda (ndims bits bv)
    (let ((z (fixed-bytevector->integer bv)))
      (let ((values (make-vector ndims 0)))
        (let loop-bit ((b 0)
                       (shift 0))
          (if (= b bits)
              (vector->list values)
              (let loop-dim ((d (- ndims 1))
                             (shift shift))
                (if (< d 0)
                    (loop-bit (+ b 1) shift)
                    (begin
                      (when (bitwise-bit-set? z shift)
                        (vector-set! values d
                          (bitwise-ior (vector-ref values d)
                                       (bitwise-arithmetic-shift-left 1 b))))
                      (loop-dim (- d 1) (+ shift 1)))))))))))

;; Key encode/decode with aql prefix

(define morton-encode
  (lambda (morton values)
    (byter-append
     (byter-encode (morton-prefix morton))
     (morton-interleave (morton-dimensions morton)
                        (morton-bits morton)
                        values))))

(define morton-decode
  (lambda (morton key)
    (let* ((prefix-bv (byter-encode (morton-prefix morton)))
           (prefix-len (bytevector-length prefix-bv))
           (morton-bv (byter-slice key prefix-len)))
      (morton-deinterleave (morton-dimensions morton)
                           (morton-bits morton)
                           morton-bv))))

;; aql operations

(define morton-set!
  (lambda (handle morton values value)
    (aql-set! handle (morton-encode morton values) value)))

(define morton-remove!
  (lambda (handle morton values)
    (aql-remove! handle (morton-encode morton values))))

(define morton-ref
  (lambda (handle morton values)
    (aql-query handle (morton-encode morton values))))

;; Bounding-box query

(define morton-in-box?
  (lambda (values mins maxs)
    (let loop ((vs values) (los mins) (his maxs))
      (or (null? vs)
          (and (<= (car los) (car vs) (car his))
               (loop (cdr vs) (cdr los) (cdr his)))))))

;; Morton range decomposition — compute Z-order ranges covering a bounding box.
;; Uses quadtree BFS like xzstore-ranges but for points (no extension).
;; Returns sorted, merged list of (min . max) integer pairs.

(define-record-type* <morton-cell>
  (make-morton-cell mins maxs)
  morton-cell?
  (mins morton-cell-mins)
  (maxs morton-cell-maxs))

(define (morton-cell-contained? cell qmins qmaxs)
  (let loop ((cmins (morton-cell-mins cell)) (cmaxs (morton-cell-maxs cell))
             (qmins qmins) (qmaxs qmaxs))
    (or (null? cmins)
        (and (<= (car qmins) (car cmins))
             (>= (car qmaxs) (car cmaxs))
             (loop (cdr cmins) (cdr cmaxs) (cdr qmins) (cdr qmaxs))))))

(define (morton-cell-overlaps? cell qmins qmaxs)
  (let loop ((cmins (morton-cell-mins cell)) (cmaxs (morton-cell-maxs cell))
             (qmins qmins) (qmaxs qmaxs))
    (or (null? cmins)
        (and (<= (car qmins) (car cmaxs))
             (>= (car qmaxs) (car cmins))
             (loop (cdr cmins) (cdr cmaxs) (cdr qmins) (cdr qmaxs))))))

(define (morton-cell-children cell ndims)
  (let* ((mins (morton-cell-mins cell))
         (maxs (morton-cell-maxs cell))
         (centers (map (lambda (lo hi) (quotient (+ lo hi) 2)) mins maxs))
         (n-children (expt 2 ndims)))
    (let loop ((idx 0) (out '()))
      (if (= idx n-children)
          (reverse out)
          (let* ((child-mins
                  (let dloop ((d 0) (mn mins) (ct centers) (acc '()))
                    (if (null? mn) (reverse acc)
                        (dloop (+ d 1) (cdr mn) (cdr ct)
                               (cons (if (zero? (bitwise-and idx (expt 2 d)))
                                         (car mn) (+ (car ct) 1))
                                     acc)))))
                 (child-maxs
                  (let dloop ((d 0) (mx maxs) (ct centers) (acc '()))
                    (if (null? mx) (reverse acc)
                        (dloop (+ d 1) (cdr mx) (cdr ct)
                               (cons (if (zero? (bitwise-and idx (expt 2 d)))
                                         (car ct) (car mx))
                                     acc))))))
            (loop (+ idx 1) (cons (make-morton-cell child-mins child-maxs) out)))))))

(define (bv<=? a b)
  (memq (byter-compare a b) '(smaller equal)))

(define (bv-max a b)
  (if (eq? 'bigger (byter-compare a b)) a b))

(define morton-merge-ranges
  (lambda (sorted-ranges)
    (if (null? sorted-ranges)
        '()
        (let loop ((ranges (cdr sorted-ranges))
                   (current (car sorted-ranges))
                   (out '()))
          (if (null? ranges)
              (reverse (cons current out))
              (let ((next (car ranges)))
                ;; Adjacent or overlapping bytevector ranges
                (if (bv<=? (car next) (cdr current))
                    (loop (cdr ranges)
                          (cons (car current) (bv-max (cdr current) (cdr next)))
                          out)
                    (loop (cdr ranges) next (cons current out)))))))))

(define morton-ranges
  (lambda (ndims bits mins maxs)
    (let* ((max-val (- (expt 2 bits) 1))
           (root (make-morton-cell (make-list ndims 0) (make-list ndims max-val)))
           (max-ranges 200))

      (define (cell-code-range cell)
        ;; Morton code range as bytevector pairs for all points in this cell
        (cons (morton-interleave ndims bits (morton-cell-mins cell))
              (morton-interleave ndims bits (morton-cell-maxs cell))))

      (let level-loop ((current (morton-cell-children root ndims))
                       (ranges '())
                       (count 0)
                       (depth 0)
                       (max-depth bits))

        (cond
         ((null? current)
          (morton-merge-ranges (list-sort (lambda (a b) (eq? 'smaller (byter-compare (car a) (car b)))) ranges)))

         ((or (>= count max-ranges) (>= depth max-depth))
          (let bottom ((elts current) (acc ranges))
            (if (null? elts)
                (morton-merge-ranges (list-sort (lambda (a b) (< (car a) (car b))) acc))
                (bottom (cdr elts) (cons (cell-code-range (car elts)) acc)))))

         (else
          (let elem-loop ((elts current) (next '()) (ranges ranges) (count count))
            (if (null? elts)
                (level-loop (reverse next) ranges count (+ depth 1) max-depth)
                (let ((head (car elts)) (rest (cdr elts)))
                  (cond
                   ((morton-cell-contained? head mins maxs)
                    (elem-loop rest next (cons (cell-code-range head) ranges) (+ count 1)))
                   ((morton-cell-overlaps? head mins maxs)
                    (elem-loop rest (append (morton-cell-children head ndims) next)
                               (cons (cell-code-range head) ranges) (+ count 1)))
                   (else
                    (elem-loop rest next ranges count))))))))))))

(define make-coroutine-generator
  (lambda (proc)
    (define return #f)
    (define resume #f)
    (define yield (lambda (v)
                    (call/cc (lambda (r) (set! resume r) (return v)))))
    (lambda () (call/cc
                (lambda (cc) (set! return cc)
                        (if resume
                            (resume (if #f #f))
                            (begin (proc yield)
                                   (set! resume (lambda (v) (return (eof-object))))
                                   (return (eof-object)))))))))

(define generator->list
  (lambda (g)
    (let loop ()
      (let ((o (g)))
        (if (eof-object? o)
            '()
            (cons o (loop)))))))

(define morton-query
  (lambda (handle morton mins maxs)
    (let ((lower (morton-encode morton mins))
          (upper (let* ((raw (morton-interleave (morton-dimensions morton)
                                                (morton-bits morton)
                                                maxs))
                        (prefix-bv (byter-encode (morton-prefix morton)))
                        (next (byter-next-prefix raw)))
                   (if next
                       (byter-append prefix-bv next)
                       ;; maxs are all-max, use byter-end as sentinel
                       (byter-append prefix-bv byter-end)))))
      (make-coroutine-generator
       (lambda (yield)
         (let ((gen (aql-query handle lower upper)))
           (if (pair? gen)
               ;; aql-query returned a list (called on aql handle)
               (for-each
                (lambda (pair)
                  (let ((coords (morton-decode morton (car pair))))
                    (when (morton-in-box? coords mins maxs)
                      (yield pair))))
                gen)
               ;; aql-query returned a generator (called on transaction)
               (let loop ()
                 (let ((pair (gen)))
                   (unless (eof-object? pair)
                     (let ((coords (morton-decode morton (car pair))))
                       (when (morton-in-box? coords mins maxs)
                         (yield pair)))
                     (loop)))))))))))

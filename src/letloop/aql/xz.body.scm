;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>

;; XZ-ordering: space-filling curve for objects with spatial extent
;; Based on Böhm, Klump, Kriegel (1999) and GeoMesa's XZ2SFC
;; Generalized to N dimensions (2, 3, 4)

(define log-point-five (log 0.5))

(define every
  (lambda (p? . lists)
    (if (null? (car lists))
        #t
        (and (apply p? (map car lists))
             (apply every p? (map cdr lists))))))

;; Record type

(define-record-type* <xzstore>
  (make-xzstore-base ndims g bounds)
  xzstore?
  (ndims xzstore-ndims)      ;; number of dimensions (2, 3, 4)
  (g xzstore-g)              ;; resolution (max quad/oct-tree depth)
  (bounds xzstore-bounds))   ;; list of (lo . hi) pairs per dimension

(define make-xzstore
  (case-lambda
    ((ndims g)
     ;; Default bounds: [-180,180] x [-90,90] for first two dims,
     ;; [0,1] for additional dims
     (make-xzstore-base ndims g
       (case ndims
         ((2) (list (cons -180.0 180.0) (cons -90.0 90.0)))
         ((3) (list (cons -180.0 180.0) (cons -90.0 90.0) (cons 0.0 1.0)))
         ((4) (list (cons -180.0 180.0) (cons -90.0 90.0) (cons 0.0 1.0) (cons 0.0 1.0))))))
    ((ndims g bounds)
     (make-xzstore-base ndims g bounds))))

;; Branching factor: 2^ndims
(define (xzstore-branching xz) (expt 2 (xzstore-ndims xz)))

;; Normalize coordinates to [0,1] per dimension
;; mins/maxs are lists of N values

(define xzstore-normalize
  (lambda (xz mins maxs)
    (let ((bounds (xzstore-bounds xz)))
      (values
       (map (lambda (v b) (fl/ (fl- v (car b)) (fl- (cdr b) (car b)))) mins bounds)
       (map (lambda (v b) (fl/ (fl- v (car b)) (fl- (cdr b) (car b)))) maxs bounds)))))

;; Sequence code (Definition 2 from the XZ-Ordering paper, generalized to N-D)
;; Iteratively subdivide [0,1]^N, determine which child contains the point,
;; accumulate code using XZ numbering.

(define xzstore-sequence-code
  (lambda (ndims g point length)
    (let ((branch (expt 2 ndims)))
      (let loop ((i 0)
                 (lo (make-list ndims 0.0))
                 (hi (make-list ndims 1.0))
                 (cs 0))
        (if (= i length)
            cs
            (let* ((centers (map (lambda (a b) (fl/ (fl+ a b) 2.0)) lo hi))
                   ;; Determine which child: for each dim, 0 if point < center, 1 otherwise
                   ;; Child offset = sum of bit_d * 2^d
                   (offset (let dim-loop ((d 0) (pt point) (ct centers) (off 0))
                             (if (null? pt)
                                 off
                                 (dim-loop (+ d 1) (cdr pt) (cdr ct)
                                           (if (fl<? (car pt) (car ct))
                                               off
                                               (+ off (expt 2 d)))))))
                   (step (+ 1 (* offset (quotient (- (expt branch (- g i)) 1) (- branch 1)))))
                   ;; Update bounds: for each dim, narrow to the appropriate half
                   (new-lo (map (lambda (p c lo-v)
                                  (if (fl<? p c) lo-v c))
                                point centers lo))
                   (new-hi (map (lambda (p c hi-v)
                                  (if (fl<? p c) c hi-v))
                                point centers hi)))
              (loop (+ i 1) new-lo new-hi (+ cs step))))))))

;; Sequence interval: compute min/max codes for a range

(define xzstore-sequence-interval
  (lambda (ndims g point length partial?)
    (let* ((branch (expt 2 ndims))
           (min-code (xzstore-sequence-code ndims g point length)))
      (if partial?
          (cons min-code min-code)
          (cons min-code
                (+ min-code (quotient (- (expt branch (- g length -1)) 1) (- branch 1))))))))

;; Index: encode a bounding box as an XZ-code

(define xzstore-index
  (lambda (xz mins maxs)
    (let-values (((nmins nmaxs) (xzstore-normalize xz mins maxs)))
      (let* ((ndims (xzstore-ndims xz))
             (g (xzstore-g xz))
             (max-dim (apply flmax (map fl- nmaxs nmins)))
             (l1 (if (fl<=? max-dim 0.0)
                     g
                     (min g (inexact->exact (floor (/ (log max-dim) log-point-five))))))
             (length
              (if (>= l1 g)
                  g
                  (let ((w2 (expt 0.5 (+ l1 1))))
                    (define (fits? mn mx)
                      (fl<=? mx (fl+ (fl* (flfloor (fl/ mn w2)) w2) (fl* 2.0 w2))))
                    (if (every fits? nmins nmaxs)
                        (+ l1 1)
                        l1)))))
        (xzstore-sequence-code ndims g nmins length)))))

;; N-dimensional XZ-element for query processing

(define-record-type* <xz-element>
  (make-xz-element mins maxs len)
  xz-element?
  (mins xze-mins)    ;; list of N lower bounds
  (maxs xze-maxs)    ;; list of N upper bounds
  (len xze-len))     ;; side length

;; Extended bounds
(define (xze-exts e) (map (lambda (mx) (fl+ mx (xze-len e))) (xze-maxs e)))

;; Is the XZ-element fully contained in the query window?
(define xze-contained?
  (lambda (e qmins qmaxs)
    (and (every fl<=? qmins (xze-mins e))
         (every fl>=? qmaxs (xze-exts e)))))

;; Does the XZ-element overlap the query window?
(define xze-overlaps?
  (lambda (e qmins qmaxs)
    (and (every fl>=? qmaxs (xze-mins e))
         (every fl<=? qmins (xze-exts e)))))

;; Children of an XZ-element (2^N children)
(define xze-children
  (lambda (e)
    (let* ((mins (xze-mins e))
           (maxs (xze-maxs e))
           (centers (map (lambda (a b) (fl/ (fl+ a b) 2.0)) mins maxs))
           (half-len (fl/ (xze-len e) 2.0))
           (ndims (length mins)))
      ;; Generate 2^ndims children by iterating over all bit combinations
      (let loop ((child-idx 0)
                 (out '()))
        (if (= child-idx (expt 2 ndims))
            (reverse out)
            (let* ((child-mins
                    (let dim-loop ((d 0) (mn mins) (ct centers) (acc '()))
                      (if (null? mn)
                          (reverse acc)
                          (dim-loop (+ d 1) (cdr mn) (cdr ct)
                                   (cons (if (zero? (bitwise-and child-idx (expt 2 d)))
                                             (car mn)
                                             (car ct))
                                         acc)))))
                   (child-maxs
                    (let dim-loop ((d 0) (mx maxs) (ct centers) (acc '()))
                      (if (null? mx)
                          (reverse acc)
                          (dim-loop (+ d 1) (cdr mx) (cdr ct)
                                   (cons (if (zero? (bitwise-and child-idx (expt 2 d)))
                                             (car ct)
                                             (car mx))
                                         acc))))))
              (loop (+ child-idx 1)
                    (cons (make-xz-element child-mins child-maxs half-len) out))))))))

;; Root element and level-one elements

(define (xzstore-level-one ndims)
  (xze-children (make-xz-element (make-list ndims 0.0)
                                  (make-list ndims 1.0)
                                  1.0)))

;; Ranges: compute XZ-code ranges covering a query region
;; Returns a sorted, merged list of (min . max) pairs.

(define xzstore-ranges
  (lambda (xz qmins qmaxs)
    (let-values (((nqmins nqmaxs) (xzstore-normalize xz qmins qmaxs)))
      (let ((ndims (xzstore-ndims xz))
            (g (xzstore-g xz)))

        (define max-ranges 200)

        (define (sort-and-merge ranges)
          (xzstore-merge-ranges (list-sort (lambda (a b) (< (car a) (car b))) ranges)))

        ;; Process level by level
        (let level-loop ((current (xzstore-level-one ndims))
                         (level 1)
                         (ranges '())
                         (count 0))

          (cond
           ((null? current)
            (sort-and-merge ranges))

           ((or (>= count max-ranges) (>= level g))
            (let bottom ((elts current) (acc ranges))
              (if (null? elts)
                  (sort-and-merge acc)
                  (bottom (cdr elts)
                          (cons (xzstore-sequence-interval ndims g (xze-mins (car elts)) level #f)
                                acc)))))

           (else
            (let elem-loop ((elts current)
                            (next '())
                            (ranges ranges)
                            (count count))
              (if (null? elts)
                  (level-loop (reverse next) (+ level 1) ranges count)
                  (let ((head (car elts))
                        (rest (cdr elts)))
                    (cond
                     ((xze-contained? head nqmins nqmaxs)
                      (elem-loop rest next
                                 (cons (xzstore-sequence-interval ndims g (xze-mins head) level #f)
                                       ranges)
                                 (+ count 1)))

                     ((xze-overlaps? head nqmins nqmaxs)
                      (elem-loop rest
                                 (append (xze-children head) next)
                                 (cons (xzstore-sequence-interval ndims g (xze-mins head) level #t)
                                       ranges)
                                 (+ count 1)))

                     (else
                      (elem-loop rest next ranges count)))))))))))))

;; Merge overlapping/adjacent ranges

(define xzstore-merge-ranges
  (lambda (sorted-ranges)
    (if (null? sorted-ranges)
        '()
        (let loop ((ranges (cdr sorted-ranges))
                   (current (car sorted-ranges))
                   (out '()))
          (if (null? ranges)
              (reverse (cons current out))
              (let ((next (car ranges)))
                (if (<= (car next) (+ (cdr current) 1))
                    (loop (cdr ranges)
                          (cons (car current) (max (cdr current) (cdr next)))
                          out)
                    (loop (cdr ranges)
                          next
                          (cons current out)))))))))

;; aql integration

(define xzstore-make-key
  (lambda (prefix code)
    (byter-encode (list prefix code))))

(define xzstore-set!
  (lambda (handle prefix xz mins maxs value)
    (let ((code (xzstore-index xz mins maxs)))
      (aql-set! handle (xzstore-make-key prefix code) value))))

(define xzstore-remove!
  (lambda (handle prefix xz mins maxs)
    (let ((code (xzstore-index xz mins maxs)))
      (aql-remove! handle (xzstore-make-key prefix code)))))

(define xzstore-ref
  (lambda (handle prefix xz mins maxs)
    (let ((code (xzstore-index xz mins maxs)))
      (aql-query handle (xzstore-make-key prefix code)))))

(define xzstore-query
  (lambda (handle prefix xz qmins qmaxs)
    (let ((ranges (xzstore-ranges xz qmins qmaxs)))
      (apply append
             (map (lambda (range)
                    (aql-query handle
                               (xzstore-make-key prefix (car range))
                               (byter-encode (fold-right cons byter-end
                                                         (list prefix (cdr range))))))
                  ranges)))))

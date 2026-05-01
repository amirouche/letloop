(define any
  (lambda (p? objects)
    (let loop ((objects objects))
      (if (null? objects)
          #f
          (if (p? (car objects))
              #t
              (loop (cdr objects)))))))

(define filter-map
  (lambda (proc lst)
    (let loop ((lst lst) (out '()))
      (if (null? lst)
          (reverse out)
          (let ((v (proc (car lst))))
            (loop (cdr lst) (if v (cons v out) out)))))))

(define every
  (lambda (p? objects)
    (let loop ((objects objects))
      (if (null? objects)
          #t
          (if (p? (car objects))
              (loop (cdr objects))
              #f)))))

;; combinatorics helpers

(define (permutations s)
  ;; http://rosettacode.org/wiki/Permutations#Scheme
  (cond
   ((null? s) '(()))
   ((null? (cdr s)) (list s))
   (else ;; extract each item in list in turn and permutations the rest
    (let splice ((l '()) (m (car s)) (r (cdr s)))
      (append
       (map (lambda (x) (cons m x)) (permutations (append l r)))
       (if (null? r) '()
           (splice (cons m l) (car r) (cdr r))))))))

(define (combination k lst)
  (cond
   ((= k 0) '(()))
   ((null? lst) '())
   (else
    (let ((head (car lst))
          (tail (cdr lst)))
      (append (map (lambda (y) (cons head y)) (combination (- k 1) tail))
              (combination k tail))))))

(define (combinations lst)
  (if (null? lst) '(())
      (let* ((head (car lst))
             (tail (cdr lst))
             (s (combinations tail))
             (v (map (lambda (x) (cons head x)) s)))
        (append s v))))

;; make-indices will compute smallest set of
;; indices/tables/subspaces required to bind any pattern in one
;; hop. The math behind this computation is explained at:
;;
;;   https://math.stackexchange.com/q/3146568/23663
;;
;; make-indices will return the smallest set of permutations in
;; lexicographic order of the base index ie. the output of (iota
;; n) where n is the length of ITEMS ie. the n in nstore.

(define (prefix? lst other)
  "Return #t if LST is prefix of OTHER"
  (let loop ((lst lst)
             (other other))
    (if (null? lst)
        #t
        (if (= (car lst) (car other))
            (loop (cdr lst) (cdr other))
            #f))))

(define (permutation-prefix? c o)
  (any (lambda (p) (prefix? p o)) (permutations c)))

(define (ok? combinations candidate)
  (every (lambda (c) (any (lambda (p) (permutation-prefix? c p)) candidate)) combinations))

(define (findij L)
  (let loop3 ((x L)
              (y '()))
    (if (or (null? x) (null? (cdr x)))
        (values #f (append (reverse y) x) #f #f)
        (if (and (not (cdr (list-ref x 0))) (cdr (list-ref x 1)))
            (values #t
                    (append (cddr x) (reverse y))
                    (car (list-ref x 0))
                    (car (list-ref x 1)))
            (loop3 (cdr x) (cons (car x) y))))))

(define (lex< a b)
  (let loop ((a a)
             (b b))
    (if (null? a)
        #t
        (if (not (= (car a) (car b)))
            (< (car a) (car b))
            (loop (cdr a) (cdr b))))))

(define (make-indices n)
  ;; This is based on:
  ;;
  ;;   https://math.stackexchange.com/a/3146793/23663
  ;;
  (let* ((tab (iota n))
         (cx (combination (floor (/ n 2)) tab)))
    (let loop1 ((cx cx)
                (out '()))
      (if (null? cx)
          (begin (unless (ok? (combinations tab) out)
                   (error 'nstore "impossible..."))
                 (list-sort lex< out))
          (let loop2 ((L (map (lambda (i) (cons i (not (not (memv i (car cx)))))) tab))
                      (a '())
                      (b '()))
            (call-with-values (lambda () (findij L))
              (lambda (continue? L i j)
                (if continue?
                    (loop2 L (cons j a) (cons i b))
                    (loop1 (cdr cx)
                           (cons (append (reverse a) (map car L) (reverse b))
                                 out))))))))))

(define-record-type* <nstore>
  (make-nstore% prefix indices n)
  nstore?
  (prefix nstore-prefix)
  (indices nstore-indices)
  (n nstore-n))

(define (make-nstore prefix n)
  (make-nstore% prefix
               (make-indices n)
               n))

(define (make-tuple list permutation)
  ;; Construct a permutation of LIST based on PERMUTATION
  (let ((tuple (make-vector (length permutation))))
    (for-each (lambda (index value) (vector-set! tuple index value)) permutation list)
    (vector->list tuple)))

(define (permute items index)
  ;; inverse of `make-tuple`
  (let ((items (list->vector items)))
    (let loop ((index index)
               (out '()))
      (if (null? index)
          (reverse out)
          (loop (cdr index)
                (cons (vector-ref items (car index)) out))))))

(define nstore-add!
  (lambda (transaction nstore items value)
    (define prefix (nstore-prefix nstore))
    ;; add ITEMS into aql and prefix each of the permutation
    ;; of ITEMS with the nstore-prefix and the index of the
    ;; permutation inside the list INDICES called SUBSPACE.
    (let loop ((indices (nstore-indices nstore))
               (subspace 0))
      (unless (null? indices)
        (let ((key (byter-encode (append (list prefix subspace)
                                        (permute items (car indices))))))
          (aql-set! transaction key value)
          (loop (cdr indices) (+ subspace 1)))))))

(define nstore-clear!
  (lambda (transaction nstore items)
    (define prefix (nstore-prefix nstore))
    ;; Similar to the above but remove ITEMS
    (let loop ((indices (nstore-indices nstore))
               (subspace 0))
      (unless (null? indices)
        (let ((key (byter-encode (append (list prefix subspace)
                                        (permute items (car indices))))))
          (aql-remove! transaction key)
          (loop (cdr indices) (+ subspace 1)))))))

;; Constraint records

(define-record-type* <nstore-gte> (nstore-gte value) nstore-gte? (value nstore-gte-value))
(define-record-type* <nstore-gt>  (nstore-gt value)  nstore-gt?  (value nstore-gt-value))
(define-record-type* <nstore-lte> (nstore-lte value) nstore-lte? (value nstore-lte-value))
(define-record-type* <nstore-lt>  (nstore-lt value)  nstore-lt?  (value nstore-lt-value))

(define-record-type* <nstore-morton>
  (nstore-morton ndims bits mins maxs)
  nstore-morton?
  (ndims nstore-morton-ndims)
  (bits nstore-morton-bits)
  (mins nstore-morton-mins)
  (maxs nstore-morton-maxs))

;; XZ constraint — spatial rectangle for extended objects (bounding boxes)
;; Unlike morton (point-in-region), xz handles region-overlaps-region.
;; The stored value is an xzstore code (integer).
;; Binds decoded min/max bounds as ((mins . maxs)) to the var name.
(define-record-type* <nstore-xz>
  (nstore-xz xzstore qmins qmaxs)
  nstore-xz?
  (xzstore nstore-xz-xzstore)
  (qmins nstore-xz-qmins)
  (qmaxs nstore-xz-qmaxs))

;; Variable with optional constraints

(define-record-type* <nstore-var>
  (make-nstore-var name constraints)
  nstore-var?
  (name nstore-var-name)
  (constraints nstore-var-constraints))

(define nstore-var
  (case-lambda
    ((name) (make-nstore-var name '()))
    ((name . constraints) (make-nstore-var name constraints))))

;; Constraint helpers

(define (constraint-lower-bound c)
  (cond
   ((nstore-gte? c) (nstore-gte-value c))
   ((nstore-gt? c) (nstore-gt-value c))
   ((nstore-morton? c)
    (morton-interleave (nstore-morton-ndims c)
                       (nstore-morton-bits c)
                       (nstore-morton-mins c)))
   ((nstore-xz? c)
    ;; XZ lower bound: smallest code in the query ranges
    (let ((ranges (xzstore-ranges (nstore-xz-xzstore c)
                                   (nstore-xz-qmins c)
                                   (nstore-xz-qmaxs c))))
      (if (null? ranges) 0 (caar ranges))))
   (else #f)))

(define (constraint-upper-bound c)
  (cond
   ((nstore-lte? c) (nstore-lte-value c))
   ((nstore-lt? c) (nstore-lt-value c))
   ((nstore-morton? c)
    (morton-interleave (nstore-morton-ndims c)
                       (nstore-morton-bits c)
                       (nstore-morton-maxs c)))
   ((nstore-xz? c)
    ;; XZ upper bound: largest code in the query ranges
    (let ((ranges (xzstore-ranges (nstore-xz-xzstore c)
                                   (nstore-xz-qmins c)
                                   (nstore-xz-qmaxs c))))
      (if (null? ranges) 0 (cdar (reverse ranges)))))
   (else #f)))

(define (constraint-satisfies? val c)
  (cond
   ((nstore-gte? c) (memq (byter-compare* val (nstore-gte-value c)) '(equal bigger)))
   ((nstore-gt? c) (eq? (byter-compare* val (nstore-gt-value c)) 'bigger))
   ((nstore-lte? c) (memq (byter-compare* val (nstore-lte-value c)) '(equal smaller)))
   ((nstore-lt? c) (eq? (byter-compare* val (nstore-lt-value c)) 'smaller))
   ((nstore-morton? c)
    (morton-in-box? (morton-deinterleave (nstore-morton-ndims c)
                                          (nstore-morton-bits c)
                                          val)
                    (nstore-morton-mins c)
                    (nstore-morton-maxs c)))
   ((nstore-xz? c)
    ;; XZ satisfaction: the stored code falls within one of the query ranges
    (let ((ranges (xzstore-ranges (nstore-xz-xzstore c)
                                   (nstore-xz-qmins c)
                                   (nstore-xz-qmaxs c))))
      (any (lambda (range) (and (<= (car range) val) (<= val (cdr range))))
           ranges)))))

(define (constraint-decode val c)
  (cond
   ((nstore-morton? c)
    (morton-deinterleave (nstore-morton-ndims c)
                         (nstore-morton-bits c)
                         val))
   ((nstore-xz? c)
    ;; XZ code is an integer — bind as-is (caller knows the xzstore)
    val)
   (else val)))

(define (nstore-var-constrained? v)
  (and (nstore-var? v)
       (not (null? (nstore-var-constraints v)))
       (any (lambda (c) (or (nstore-gte? c) (nstore-gt? c) (nstore-morton? c) (nstore-xz? c)))
            (nstore-var-constraints v))))

(define (nstore-var-lower v)
  (let loop ((cs (nstore-var-constraints v)))
    (if (null? cs) #f
        (or (constraint-lower-bound (car cs)) (loop (cdr cs))))))

(define (nstore-var-upper v)
  (let loop ((cs (nstore-var-constraints v)))
    (if (null? cs) #f
        (or (constraint-upper-bound (car cs)) (loop (cdr cs))))))

(define (nstore-var-upper-inclusive? v)
  (any (lambda (c) (or (nstore-lte? c) (nstore-morton? c) (nstore-xz? c)))
       (nstore-var-constraints v)))

;; bind* — for nstore-query (no constraints)

(define (bind* pattern tuple seed)
  (let loop ((tuple tuple)
             (pattern pattern)
             (out seed))
    (if (null? tuple)
        out
        (if (nstore-var? (car pattern))
            (loop (cdr tuple)
                  (cdr pattern)
                  (cons (cons (nstore-var-name (car pattern))
                              (car tuple))
                        out))
            (loop (cdr tuple) (cdr pattern) out)))))

;; bind*+ — for nstore-query* (decodes morton constraints)

(define (bind*+ pattern tuple seed)
  (let loop ((tuple tuple)
             (pattern pattern)
             (out seed))
    (if (null? tuple)
        out
        (if (nstore-var? (car pattern))
            (let* ((v (car pattern))
                   (val (car tuple))
                   (morton-c (find nstore-morton? (nstore-var-constraints v)))
                   (bound-val (if morton-c (constraint-decode val morton-c) val)))
              (loop (cdr tuple)
                    (cdr pattern)
                    (cons (cons (nstore-var-name v) bound-val) out)))
            (loop (cdr tuple) (cdr pattern) out)))))

(define (pattern->combination pattern)
  (let loop ((pattern pattern)
             (index 0)
             (out '()))
    (if (null? pattern)
        (reverse out)
        (loop (cdr pattern)
              (+ 1 index)
              (if (and (nstore-var? (car pattern))
                       (not (nstore-var-constrained? (car pattern))))
                  out
                  (cons index out))))))

(define (pattern->index pattern indices)
  ;; Retrieve the index and subspace that will allow to bind
  ;; PATTERN in one hop. This is done by getting all non-variable
  ;; items of PATTERN and looking up the first index that is
  ;; permutation-prefix...
  (let ((combination (pattern->combination pattern)))
    (let loop ((indices indices)
               (subspace 0))
      (if (null? indices)
          (error 'nstore "Impossible, there is always a matching index" pattern)
          (if (permutation-prefix? combination (car indices))
              (values (car indices) subspace)
              (loop (cdr indices) (+ subspace 1)))))))

(define (pattern->prefix pattern index)
  ;; Return the list that correspond to INDEX, that is the items
  ;; of PATTERN that are not variables (or constrained var lower
  ;; bounds). Stops at unconstrained variables.
  (let loop ((index index)
             (out '()))
    (let ((v (list-ref pattern (car index))))
      (cond
       ((and (nstore-var? v) (not (nstore-var-constrained? v)))
        ;; Unconstrained variable: stop
        (reverse out))
       ((nstore-var-constrained? v)
        ;; Constrained variable: include lower bound, then stop
        (reverse (cons (nstore-var-lower v) out)))
       (else
        ;; Exact value: include and continue
        (loop (cdr index) (cons v out)))))))

(define (nstore-from transaction nstore pattern seed)
  (call-with-values (lambda () (pattern->index pattern (nstore-indices nstore)))
    (lambda (index subspace)
      (define pattern-prefix (pattern->prefix pattern index))
      (define items (append (list (nstore-prefix nstore) subspace)
                            pattern-prefix))
      (define lower (byter-encode items))
      ;; Upper bound: same prefix but with a bytevector sentinel as
      ;; the last cdr instead of null. Since bytevector tag (#x06) >
      ;; pair tag (#x03) > null (#x00), this is greater than any
      ;; list extension of items.
      (define upper (byter-encode (fold-right cons byter-end items)))

      (map (lambda (pair)
             (bind* pattern
                    (make-tuple (cddr (byter-decode (car pair))) index)
                    seed))
           (aql-query transaction lower upper)))))

(define (pattern-bind pattern seed)
  ;; Return a pattern where variables that have a binding in SEED
  ;; are replaced with the associated value. In practice, most of
  ;; the time, it is the same pattern with less variables.
  (map (lambda (item)
         (or (and (nstore-var? item)
                  (and (assq (nstore-var-name item) seed)
                       (cdr (assq (nstore-var-name item) seed))))
             item))
       pattern))

(define nstore-where
  (lambda (transaction nstore pattern from)
    (apply append
           (map (lambda (bindings)
                  (nstore-from transaction
                               nstore
                               (pattern-bind pattern bindings)
                               bindings))
                from))))

(define nstore-ref
  (lambda (transaction nstore items)
    ;; indices are sorted in lexicographic order, that is the
    ;; first index is always (iota n) (also known as the base
    ;; index). So that there is no need to permute ITEMS.  zero in
    ;; the following `list` is the index of the base subspace in
    ;; nstore-indices

    (let* ((key (byter-encode (append (list (nstore-prefix nstore) 0) items))))
       (aql-query transaction key))))

(define nstore-query
  (lambda (transaction nstore patterns)
    (if (null? patterns)
        '()
        (let loop ((results (nstore-from transaction nstore (car patterns) '()))
                   (patterns (cdr patterns)))
          (if (null? patterns)
              results
              (loop (nstore-where transaction nstore (car patterns) results)
                    (cdr patterns)))))))

;; nstore-query* — supports constrained variables

(define (nstore-check-constraints pattern unpermuted)
  ;; Verify all constrained var values satisfy their constraints
  (let loop ((pattern pattern) (tuple unpermuted))
    (if (null? pattern)
        #t
        (if (and (nstore-var? (car pattern))
                 (nstore-var-constrained? (car pattern)))
            (and (every (lambda (c) (constraint-satisfies? (car tuple) c))
                        (nstore-var-constraints (car pattern)))
                 (loop (cdr pattern) (cdr tuple)))
            (loop (cdr pattern) (cdr tuple))))))

(define (nstore-from* transaction nstore pattern seed)
  (call-with-values (lambda () (pattern->index pattern (nstore-indices nstore)))
    (lambda (index subspace)
      (define pattern-prefix (pattern->prefix pattern index))
      (define base-head (append (list (nstore-prefix nstore) subspace)
                                (if (null? pattern-prefix)
                                    '()
                                    (reverse (cdr (reverse pattern-prefix))))))

      ;; Check if last prefix element came from a constrained var
      (define last-var
        (and (> (length pattern-prefix) 0)
             (let ((last-idx (list-ref index (- (length pattern-prefix) 1))))
               (let ((v (list-ref pattern last-idx)))
                 (and (nstore-var? v) (nstore-var-constrained? v) v)))))

      ;; Find spatial constraint if any
      (define xz-constraint
        (and last-var (find nstore-xz? (nstore-var-constraints last-var))))
      (define morton-constraint
        (and last-var (find nstore-morton? (nstore-var-constraints last-var))))

      (define (decode-and-filter pairs)
        (filter-map
         (lambda (pair)
           (let* ((tuple (cddr (byter-decode (car pair))))
                  (unpermuted (make-tuple tuple index)))
             (and (nstore-check-constraints pattern unpermuted)
                  (bind*+ pattern unpermuted seed))))
         pairs))

      (define (multi-range-query ranges)
        ;; Issue one aql-query per range interval, merge results
        (decode-and-filter
         (apply append
                (map (lambda (range)
                       (let ((lower (byter-encode (append base-head (list (car range)))))
                             (upper (byter-encode (fold-right cons byter-end
                                                              (append base-head (list (cdr range)))))))
                         (aql-query transaction lower upper)))
                     ranges))))

      (cond
       ;; XZ: multiple targeted range queries
       (xz-constraint
        (multi-range-query
         (xzstore-ranges (nstore-xz-xzstore xz-constraint)
                          (nstore-xz-qmins xz-constraint)
                          (nstore-xz-qmaxs xz-constraint))))

       ;; Morton: multiple targeted range queries
       (morton-constraint
        (multi-range-query
         (morton-ranges (nstore-morton-ndims morton-constraint)
                        (nstore-morton-bits morton-constraint)
                        (nstore-morton-mins morton-constraint)
                        (nstore-morton-maxs morton-constraint))))

       ;; Scalar constraints or unconstrained: single range scan
       (else
        (let* ((base (append (list (nstore-prefix nstore) subspace)
                             pattern-prefix))
               (lower (byter-encode base))
               (upper
                (if (and last-var (nstore-var-upper last-var))
                    (let ((upper-items (append base-head
                                                (list (nstore-var-upper last-var)))))
                      (if (nstore-var-upper-inclusive? last-var)
                          (byter-encode (fold-right cons byter-end upper-items))
                          (byter-encode upper-items)))
                    (byter-encode (fold-right cons byter-end base)))))
          (decode-and-filter (aql-query transaction lower upper))))))))

(define nstore-where*
  (lambda (transaction nstore pattern from)
    (apply append
           (map (lambda (bindings)
                  (nstore-from* transaction nstore
                                (pattern-bind pattern bindings)
                                bindings))
                from))))

(define nstore-query*
  (lambda (transaction nstore patterns)
    (if (null? patterns)
        '()
        (let loop ((results (nstore-from* transaction nstore (car patterns) '()))
                   (patterns (cdr patterns)))
          (if (null? patterns)
              results
              (loop (nstore-where* transaction nstore (car patterns) results)
                    (cdr patterns)))))))

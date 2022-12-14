#!r6rs
;; Test suite for SRFI-1
;; 2003-12-29 / lth
;;
;; $Id: srfi-1-test.sps 5842 2008-12-11 23:04:51Z will $
;;
;; Note: In Larceny, we require that the procedures designated as
;; "linear update" variants in the spec (eg append!) side-effect their
;; arguments, and there are tests here that check that side-effecting
;; occurs.
;;
;; For linear update we only require that the cells of the result are
;; taken from the cells of the input.  We could be stricter and require
;; that the cells of the results are the cells of the input with only
;; the CDR changed, ie, values are never moved from one cell to another.
;;
;; Comments:
;;
;; - Test cases are ordered as in the spec.  R5RS procedures are left
;;   out.
;;
;; - Adapted to arew scheme tests
;;

(library (srfi srfi-1-check)

  (export ~check-srfi-1-001
          ~check-srfi-1-002
          ~check-srfi-1-003
          ~check-srfi-1-004
          ~check-srfi-1-005
          ~check-srfi-1-006
          ~check-srfi-1-007
          ~check-srfi-1-008
          ~check-srfi-1-009
          ~check-srfi-1-010
          ~check-srfi-1-011
          ~check-srfi-1-012
          ~check-srfi-1-013
          ~check-srfi-1-014
          ~check-srfi-1-015
          ~check-srfi-1-016
          ~check-srfi-1-017
          ~check-srfi-1-018
          ~check-srfi-1-019
          ~check-srfi-1-020
          ~check-srfi-1-021
          ~check-srfi-1-022
          ~check-srfi-1-023
          ~check-srfi-1-024
          ~check-srfi-1-025
          ~check-srfi-1-026
          ~check-srfi-1-027
          ~check-srfi-1-028
          ~check-srfi-1-029
          ~check-srfi-1-030
          ~check-srfi-1-031
          ~check-srfi-1-032
          ~check-srfi-1-033
          ~check-srfi-1-034
          ~check-srfi-1-035
          ~check-srfi-1-036
          ~check-srfi-1-037
          ~check-srfi-1-038
          ~check-srfi-1-039
          ~check-srfi-1-040
          ~check-srfi-1-041
          ~check-srfi-1-042
          ~check-srfi-1-043
          ~check-srfi-1-044
          ~check-srfi-1-045
          ~check-srfi-1-046
          ~check-srfi-1-047
          ~check-srfi-1-048
          ~check-srfi-1-049
          ~check-srfi-1-050
          ~check-srfi-1-051
          ~check-srfi-1-052
          ~check-srfi-1-053
          ~check-srfi-1-054
          ~check-srfi-1-055
          ~check-srfi-1-056
          ~check-srfi-1-057
          ~check-srfi-1-058
          ~check-srfi-1-059
          ~check-srfi-1-060
          ~check-srfi-1-061
          ~check-srfi-1-062
          ~check-srfi-1-063
          ~check-srfi-1-064
          ~check-srfi-1-065
          ~check-srfi-1-066
          ~check-srfi-1-067
          ~check-srfi-1-068
          ~check-srfi-1-069
          ~check-srfi-1-070
          ~check-srfi-1-071
          ~check-srfi-1-072
          ~check-srfi-1-073
          ~check-srfi-1-074
          ~check-srfi-1-075
          ~check-srfi-1-076
          ~check-srfi-1-077
          ~check-srfi-1-078
          ~check-srfi-1-079
          ~check-srfi-1-080
          ~check-srfi-1-081
          ~check-srfi-1-082
          ~check-srfi-1-083
          ~check-srfi-1-084
          ~check-srfi-1-085
          ~check-srfi-1-086
          ~check-srfi-1-087
          ~check-srfi-1-088
          ~check-srfi-1-089
          ~check-srfi-1-090
          ~check-srfi-1-091
          ~check-srfi-1-092
          ~check-srfi-1-093
          ~check-srfi-1-094
          ~check-srfi-1-095
          ~check-srfi-1-096
          ~check-srfi-1-097
          ~check-srfi-1-098
          ~check-srfi-1-099
          ~check-srfi-1-100
          ~check-srfi-1-101
          ~check-srfi-1-102
          ~check-srfi-1-103
          ~check-srfi-1-104
          ~check-srfi-1-105
          ~check-srfi-1-106
          ~check-srfi-1-107
          ~check-srfi-1-108
          ~check-srfi-1-109
          ~check-srfi-1-110
          ~check-srfi-1-111
          ~check-srfi-1-112
          ~check-srfi-1-113
          ~check-srfi-1-114
          ~check-srfi-1-115
          ~check-srfi-1-116
          ~check-srfi-1-117
          ~check-srfi-1-118
          ~check-srfi-1-119
          ~check-srfi-1-120
          ~check-srfi-1-121
          ~check-srfi-1-122
          ~check-srfi-1-123
          ~check-srfi-1-124
          ~check-srfi-1-125
          ~check-srfi-1-126
          ~check-srfi-1-127
          ~check-srfi-1-128
          ~check-srfi-1-129
          ~check-srfi-1-130
          ~check-srfi-1-131
          ~check-srfi-1-132
          ~check-srfi-1-133
          ~check-srfi-1-134
          ~check-srfi-1-135
          ~check-srfi-1-136
          ~check-srfi-1-137
          ~check-srfi-1-138
          ~check-srfi-1-139
          ~check-srfi-1-140
          ~check-srfi-1-141
          ~check-srfi-1-142
          ~check-srfi-1-143
          ~check-srfi-1-144
          ~check-srfi-1-145
          ~check-srfi-1-146
          ~check-srfi-1-147
          ~check-srfi-1-148
          ~check-srfi-1-149
          ~check-srfi-1-150
          ~check-srfi-1-151
          ~check-srfi-1-152
          ~check-srfi-1-153
          ~check-srfi-1-154
          ~check-srfi-1-155
          ~check-srfi-1-156
          ~check-srfi-1-157
          ~check-srfi-1-158
          ~check-srfi-1-159
          ~check-srfi-1-160
          ~check-srfi-1-161
          ~check-srfi-1-162
          ~check-srfi-1-163
          ~check-srfi-1-164
          ~check-srfi-1-165
          ~check-srfi-1-166
          ~check-srfi-1-167
          ~check-srfi-1-168
          ~check-srfi-1-169
          ~check-srfi-1-170
          ~check-srfi-1-171)

  (import (only (chezscheme)
                if define begin quote lambda error
                call-with-current-continuation
                not eq? eqv? list? let let* or and equal?
                = let-values quasiquote even? < max + > * -
                zero? set! number? symbol? integer? remainder
                unquote)
          (letloop check)
          (srfi srfi-1))

  (begin

    (define ~check-srfi-1-001
      (check '(2 . 1) (xcons 1 2)))

    (define ~check-srfi-1-002
      (check 1 (cons* 1)))

    (define ~check-srfi-1-003
      (check '(1 2 3 4 . 5) (cons* 1 2 3 4 5)))

    (define ~check-srfi-1-004
      (check '(#t #t #t #t #t) (make-list 5 #t)))

    (define ~check-srfi-1-005
      (check '() (make-list 0 #f)))

    (define ~check-srfi-1-006
      (check 3 (length (make-list 3))))

    (define ~check-srfi-1-007
      (check '(0 1 2 3 4) (list-tabulate 5 (lambda (x) x))))

    (define ~check-srfi-1-008
      (check '() (list-tabulate 0 (lambda (x) (error 'srfi-1-tests "tests")))))

    (define ~check-srfi-1-009
      (check #t
            (call-with-current-continuation
             (lambda (abort)
               (let* ((c  (list 1 2 3 4 5))
	              (cp (list-copy c)))
	         (or (equal? c cp)
	             (abort #f))
	         (let loop ((c c) (cp cp))
	           (if (not (null? c))
	               (begin
		         (or (not (eq? c cp))
		             (abort #f))
		         (loop (cdr c) (cdr cp)))))
	         #t)))))

    (define ~check-srfi-1-010
      (check '(1 2 3 . 4) (list-copy '(1 2 3 . 4))))

    (define ~check-srfi-1-011
      (check #t (not (list? (circular-list 1 2 3)))))

    (define ~check-srfi-1-012
      (check #t
            (let* ((a (list 'a))
	           (b (list 'b))
	           (c (list 'c))
	           (x (circular-list a b c)))
              (and (eq? a (car x))
	           (eq? b (cadr x))
	           (eq? c (caddr x))
	           (eq? a (cadddr x))))))

    (define ~check-srfi-1-013
      (check '() (iota 0)))

    (define ~check-srfi-1-014
      (check '(2 5 8 11 14) (iota 5 2 3)))

    (define ~check-srfi-1-015
      (check '(2 3 4 5 6) (iota 5 2)))

    (define ~check-srfi-1-016
      (check #t (proper-list? '(1 2 3 4 5))))

    (define ~check-srfi-1-017
      (check #t (proper-list? '())))

    (define ~check-srfi-1-018
      (check #f (proper-list? '(1 2 . 3))))

    (define ~check-srfi-1-019
      (check #f (proper-list? (circular-list 1 2 3))))

    (define ~check-srfi-1-020
      (check #f (circular-list? '(1 2 3 4 5))))

    (define ~check-srfi-1-021
      (check #f (circular-list? '())))

    (define ~check-srfi-1-022
      (check #f (circular-list? '(1 2 . 3))))

    (define ~check-srfi-1-023
      (check #t (circular-list? (circular-list 1 2 3))))

    (define ~check-srfi-1-024
      (check #f (dotted-list? '(1 2 3))))

    (define ~check-srfi-1-025
      (check #f (dotted-list? '())))

    (define ~check-srfi-1-026
      (check #t (dotted-list? '(1 2 . 3))))

    (define ~check-srfi-1-027
      (check #f (dotted-list? (circular-list 1 2 3))))

    (define ~check-srfi-1-028
      (check #t (null-list? '())))

    (define ~check-srfi-1-029
      (check #f (null-list? '(1 2))))

    (define ~check-srfi-1-030
      (check #f (null-list? (circular-list 1 2))))

    (define ~check-srfi-1-031
      (check #t (not-pair? 1)))

    (define ~check-srfi-1-032
      (check #f (not-pair? (cons 1 2))))

    (define ~check-srfi-1-033
      (check #t (list= = '(1 2 3) '(1 2 3) '(1 2 3))))

    (define ~check-srfi-1-034
      (check #f (list= = '(1 2 3) '(1 2 3) '(4 5 6))))

    (define ~check-srfi-1-035
      ;; Checks that l0 is not being used when testing l2, cf spec
      (check #t (list= (lambda (a b) (not (eq? a b))) '(#f #f #f) '(#t #t #t) '(#f #f #f))))

    (define ~check-srfi-1-036
      (check 1 (first '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-037
      (check 2 (second '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-038
      (check 3 (third '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-039
      (check 4 (fourth '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-040
      (check 5 (fifth '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-041
      (check 6 (sixth '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-042
      (check 7 (seventh '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-043
      (check 8 (eighth '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-044
      (check 9 (ninth '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-045
      (check 10 (tenth '(1 2 3 4 5 6 7 8 9 10))))

    (define ~check-srfi-1-046
      (check #t (let-values (((a b) (car+cdr (cons 1 2))))
                 (and (= a 1) (= b 2)))))

    (define ~check-srfi-1-047
      (check '(1 2 3) (take '(1 2 3 4 5 6) 3)))

    (define ~check-srfi-1-048
      (check '(1) (take '(1) 1)))

    (define ~check-srfi-1-049
      (let ((x (list 1 2 3 4 5 6)))
        (check (cdddr x) (drop x 3))))

    (define ~check-srfi-1-050
      (let ((x (list 1 2 3)))
        (check #t (eq? x (drop x 0)))))

    (define ~check-srfi-1-051
      (check '(4 5 6) (take-right '(1 2 3 4 5 6) 3)))

    (define ~check-srfi-1-052
      (check '() (take-right '(1 2 3 4 5 6) 0)))

    (define ~check-srfi-1-053
      (check '(2 3 . 4) (take-right '(1 2 3 . 4) 2)))

    (define ~check-srfi-1-054
      (check 4 (take-right '(1 2 3 . 4) 0)))

    (define ~check-srfi-1-055
      (check '(1 2 3) (drop-right '(1 2 3 4 5 6) 3)))

    (define ~check-srfi-1-056
      (check '(1 2 3) (drop-right '(1 2 3) 0)))

    (define ~check-srfi-1-057
      (check '(1 2 3) (drop-right '(1 2 3 . 4) 0)))

    (define ~check-srfi-1-058
      (check #t (let ((x (list 1 2 3 4 5 6)))
                 (let ((y (take! x 3)))
	           (and (eq? x y)
	                (eq? (cdr x) (cdr y))
	                (eq? (cddr x) (cddr y))
	                (equal? y '(1 2 3)))))))

    (define ~check-srfi-1-059
      (check #t (let ((x (list 1 2 3 4 5 6)))
                 (let ((y (drop-right! x 3)))
	           (and (eq? x y)
	                (eq? (cdr x) (cdr y))
	                (eq? (cddr x) (cddr y))
	                (equal? y '(1 2 3)))))))

    (define ~check-srfi-1-060
      (check #t (let-values (((a b) (split-at '(1 2 3 4 5 6) 2)))
                 (and (equal? a '(1 2))
	              (equal? b '(3 4 5 6))))))

    (define ~check-srfi-1-061
      (check #t (let* ((x (list 1 2 3 4 5 6))
	              (y (cddr x)))
                 (let-values (((a b) (split-at! x 2)))
                   (and (equal? a '(1 2))
	                (eq? a x)
	                (equal? b '(3 4 5 6))
	                (eq? b y))))))

    (define ~check-srfi-1-062
      (check #t (= 37 (last '(1 2 3 37)))))

    (define ~check-srfi-1-063
      (check #f (length+ (circular-list 1 2 3))))

    (define ~check-srfi-1-064
      (check 4 (length+ '(1 2 3 4))))

    (define ~check-srfi-1-065
      (check #t (let ((x (list 1 2))
	             (y (list 3 4))
	             (z (list 5 6)))
                 (let ((r (append! x y '() z)))
	           (and (equal? r '(1 2 3 4 5 6))
	                (eq? r x)
	                (eq? (cdr r) (cdr x))
	                (eq? (cddr r) y)
	                (eq? (cdddr r) (cdr y))
	                (eq? (cddddr r) z)
	                (eq? (cdr (cddddr r)) (cdr z)))))))

    (define ~check-srfi-1-066
      (check '(1 2 3 4 5 6 7 8 9) (concatenate '((1 2 3) (4 5 6) () (7 8 9))) ))

    (define ~check-srfi-1-067
      (check '(1 2 3 4 5 6 7 8 9)
            (concatenate! `(,(list 1 2 3) ,(list 4 5 6) () ,(list 7 8 9)))))

    (define ~check-srfi-1-068
      (check '(1 2 3 4 5 6) (append-reverse '(3 2 1) '(4 5 6))))

    (define ~check-srfi-1-069
      (check '(1 2 3 4 5 6) (append-reverse! '(3 2 1) '(4 5 6))))

    (define ~check-srfi-1-070
      (check  '((1 4) (2 5) (3 6)) (zip '(1 2 3) '(4 5 6))))

    (define ~check-srfi-1-071
      (check '() (zip '() '() '() '())))

    (define ~check-srfi-1-072
      (check '((1 1)) (zip '(1) (circular-list 1 2))))

    (define ~check-srfi-1-073
      (check '(1 2 3 4 5) (unzip1 '((1) (2) (3) (4) (5)))))

    (define ~check-srfi-1-074
      (check #t
            (let-values (((a b) (unzip2 '((10 11) (20 21) (30 31)))))
              (and (equal? a '(10 20 30))
               	   (equal? b '(11 21 31))))))

    (define ~check-srfi-1-075
      (check #t (let-values (((a b c) (unzip3 '((10 11 12) (20 21 22) (30 31 32)))))
                 (and (equal? a '(10 20 30))
	              (equal? b '(11 21 31))
	              (equal? c '(12 22 32))))))

    (define ~check-srfi-1-076
      (check #t (let-values (((a b c d) (unzip4 '((10 11 12 13)
				                 (20 21 22 23)
				                 (30 31 32 33)))))
                 (and (equal? a '(10 20 30))
	              (equal? b '(11 21 31))
	              (equal? c '(12 22 32))
	              (equal? d '(13 23 33))))))

    (define ~check-srfi-1-077
      (check #t (let-values (((a b c d e) (unzip5 '((10 11 12 13 14)
					           (20 21 22 23 24)
					           (30 31 32 33 34)))))
                 (and (equal? a '(10 20 30))
	              (equal? b '(11 21 31))
	              (equal? c '(12 22 32))
	              (equal? d '(13 23 33))
	              (equal? e '(14 24 34))))))

    (define ~check-srfi-1-078
      (check 3 (count even? '(3 1 4 1 5 9 2 5 6))))

    (define ~check-srfi-1-079
      (check 3 (count < '(1 2 4 8) '(2 4 6 8 10 12 14 16))))

    (define ~check-srfi-1-080
      (check 2 (count < '(3 1 4 1) (circular-list 1 10))))

    (define ~check-srfi-1-081
      (check '(c 3 b 2 a 1) (fold cons* '() '(a b c) '(1 2 3 4 5))))

    (define ~check-srfi-1-082
      (check '(a 1 b 2 c 3) (fold-right cons* '() '(a b c) '(1 2 3 4 5))))

    (define ~check-srfi-1-083
      (check #t (let* ((x (list 1 2 3))
	              (r (list x (cdr x) (cddr x)))
	              (y (pair-fold (lambda (pair tail)
			              (set-cdr! pair tail) pair)
			            '()
			            x)))
                 (and (equal? y '(3 2 1))
	              (every (lambda (c) (memq c r)) (list y (cdr y) (cddr y)))
                      #t))))

    (define ~check-srfi-1-084
      (check '((a b c) (b c) (c)) (pair-fold-right cons '() '(a b c))))

    (define ~check-srfi-1-085
      (check 5 (reduce max 'illegal '(1 2 3 4 5))))

    (define ~check-srfi-1-086
      (check 0 (reduce max 0 '())))

    (define ~check-srfi-1-087
      (check '(1 2 3 4 5) (reduce-right append 'illegal '((1 2) () (3 4 5)))))

    (define ~check-srfi-1-088
      (check '(1 4 9 16 25 36 49 64 81 100)
	    (unfold (lambda (x) (> x 10))
		    (lambda (x) (* x x))
		    (lambda (x) (+ x 1))
		    1)))

    (define ~check-srfi-1-089
      (check '(1 4 9 16 25 36 49 64 81 100)
	    (unfold-right zero?
			  (lambda (x) (* x x))
			  (lambda (x) (- x 1))
			  10)))

    (define ~check-srfi-1-090
      (check '(4 1 5 1)
	    (map + '(3 1 4 1) (circular-list 1 0))))

    (define ~check-srfi-1-091
      (check '(5 4 3 2 1)
	    (let ((v 1)
		  (l '()))
	      (for-each (lambda (x y)
			  (let ((n v))
			    (set! v (+ v 1))
			    (set! l (cons n l))))
			'(0 0 0 0 0)
			(circular-list 1 2))
	      l)))

    (define ~check-srfi-1-092
      (check '(1 -1 3 -3 8 -8)
	    (append-map (lambda (x) (list x (- x))) '(1 3 8))))

    (define ~check-srfi-1-093
      (check '(1 -1 3 -3 8 -8)
	    (append-map! (lambda (x) (list x (- x))) '(1 3 8))))

    (define ~check-srfi-1-094
      (check #t (let* ((l (list 1 2 3))
	              (m (map! (lambda (x) (* x x)) l)))
                 (and (equal? m '(1 4 9))
	              (equal? l '(1 4 9))))))

    (define ~check-srfi-1-095
      (check '(1 2 3 4 5)
	    (let ((v 1))
	      (map-in-order (lambda (x)
			      (let ((n v))
				(set! v (+ v 1))
				n))
			    '(0 0 0 0 0)))))

    (define ~check-srfi-1-096
      (check '((3) (2 3) (1 2 3))
	    (let ((xs (list 1 2 3))
		  (l '()))
	      (pair-for-each (lambda (x) (set! l (cons x l))) xs)
	      l)))

    (define ~check-srfi-1-097
      (check '(1 9 49)
            (filter-map (lambda (x y) (and (number? x) (* x x)))
			'(a 1 b 3 c 7)
			(circular-list 1 2))))

    (define ~check-srfi-1-098
      (check '(0 8 8 -4) (filter even? '(0 7 8 8 43 -4))))

    (define ~check-srfi-1-099
      (check #t (let-values (((a b) (partition symbol? '(one 2 3 four five 6))))
                 (and (equal? a '(one four five))
	              (equal? b '(2 3 6))))))

    (define ~check-srfi-1-100
      (check '(7 43) (remove even? '(0 7 8 8 43 -4))))

    (define ~check-srfi-1-101
      (check #t (let* ((x (list 0 7 8 8 43 -4))
	              (y (pair-fold cons '() x))
	              (r (filter! even? x)))
                 (and (equal? '(0 8 8 -4) r)
	              (every (lambda (c) (memq c y)) (pair-fold cons '() r))
                      #t))))

    (define ~check-srfi-1-102
      (check #t (let* ((x (list 'one 2 3 'four 'five 6))
	              (y (pair-fold cons '() x)))
                 (let-values (((a b) (partition! symbol? x)))
	           (and (equal? a '(one four five))
	                (equal? b '(2 3 6))
	                (every (lambda (c) (memq c y)) (pair-fold cons '() a))
	                (every (lambda (c) (memq c y)) (pair-fold cons '() b))
                        #t)))))

    (define ~check-srfi-1-103
      (check #t (let* ((x (list 0 7 8 8 43 -4))
	              (y (pair-fold cons '() x))
	              (r (remove! even? x)))
                 (and (equal? '(7 43) r)
	              (every (lambda (c) (memq c y)) (pair-fold cons '() r))
                      #t))))

    (define ~check-srfi-1-104
      (check 4 (find even? '(3 1 4 1 5 9 8))))

    (define ~check-srfi-1-105
      (check '(4 1 5 9 8) (find-tail even? '(3 1 4 1 5 9 8))))

    (define ~check-srfi-1-106
      (check '#f (find-tail even? '(1 3 5 7))))

    (define ~check-srfi-1-107
      (check '(2 18) (take-while even? '(2 18 3 10 22 9))))

    (define ~check-srfi-1-108
      (check #t (let* ((x (list 2 18 3 10 22 9))
	              (r (take-while! even? x)))
                 (and (equal? r '(2 18))
	              (eq? r x)
	              (eq? (cdr r) (cdr x))))))

    (define ~check-srfi-1-109
      (check '(3 10 22 9) (drop-while even? '(2 18 3 10 22 9))))

    (define ~check-srfi-1-110
      (check #t (let-values (((a b) (span even? '(2 18 3 10 22 9))))
                 (and (equal? a '(2 18))
	              (equal? b '(3 10 22 9))))))

    (define ~check-srfi-1-111
      (check #t (let-values (((a b) (break even? '(3 1 4 1 5 9))))
                 (and (equal? a '(3 1))
	              (equal? b '(4 1 5 9))))))

    (define ~check-srfi-1-112
      (check #t (let* ((x (list 2 18 3 10 22 9))
	              (cells (pair-fold cons '() x)))
                 (let-values (((a b) (span! even? x)))
                   (and (equal? a '(2 18))
	                (equal? b '(3 10 22 9))
	                (every (lambda (x) (memq x cells)) (pair-fold cons '() a))
	                (every (lambda (x) (memq x cells)) (pair-fold cons '() b))
                        #t)))))

    (define ~check-srfi-1-113
      (check #t (let* ((x     (list 3 1 4 1 5 9))
	              (cells (pair-fold cons '() x)))
                 (let-values (((a b) (break! even? x)))
                   (and (equal? a '(3 1))
	                (equal? b '(4 1 5 9))
	                (every (lambda (x) (memq x cells)) (pair-fold cons '() a))
	                (every (lambda (x) (memq x cells)) (pair-fold cons '() b))
                        #t)))))

    (define ~check-srfi-1-114
      (check #t (any integer? '(a 3 b 2.7))))

    (define ~check-srfi-1-115
      (check #f (any integer? '(a 3.1 b 2.7))))

    (define ~check-srfi-1-116
      (check #t (any < '(3 1 4 1 5) (circular-list 2 7 1 8 2))))

    (define ~check-srfi-1-117
      (check 'yes (any (lambda (a b) (if (< a b) 'yes #f))
		      '(1 2 3) '(0 1 4))))

    (define ~check-srfi-1-118
      (check #t (every integer? '(1 2 3))))

    (define ~check-srfi-1-119
      (check #f (every integer? '(3 4 5.1))))

    (define ~check-srfi-1-120
      (check #t (every < '(1 2 3) (circular-list 2 3 4))))

    (define ~check-srfi-1-121
      (check 2 (list-index even? '(3 1 4 1 5 9))))

    (define ~check-srfi-1-122
      (check 1 (list-index < '(3 1 4 1 5 9 2 5 6) '(2 7 1 8 2))))

    (define ~check-srfi-1-123
      (check #f (list-index = '(3 1 4 1 5 9 2 5 6) '(2 7 1 8 2))))

    (define ~check-srfi-1-124
      (check '(37 48) (member 5 '(1 2 5 37 48) <)))

    (define ~check-srfi-1-125
      (check '(1 2 5) (delete 5 '(1 48 2 5 37) <)))

    (define ~check-srfi-1-126
      (check '(1 2 7) (delete 5 '(1 5 2 5 7))))

    (define ~check-srfi-1-127
      (check #t (let* ((x (list 1 48 2 5 37))
	              (cells (pair-fold cons '() x))
	              (r (delete! 5 x <)))
                 (and (equal? r '(1 2 5))
	              (every (lambda (x) (memq x cells)) (pair-fold cons '() r))
                      #t))))

    (define ~check-srfi-1-128
      (check '((a . 3) (b . 7) (c . 1))
	    (delete-duplicates '((a . 3) (b . 7) (a . 9) (c . 1))
			       (lambda (x y) (eq? (car x) (car y))))))

    (define ~check-srfi-1-129
      (check '(a b c z) (delete-duplicates '(a b a c a b c z) eq?)))

    (define ~check-srfi-1-130
      (check '((a b c z))
            (let* ((x     (list 'a 'b 'a 'c 'a 'b 'c 'z))
	           (cells (pair-fold cons '() x))
	           (r     (delete-duplicates! x)))
              (and (equal? '(a b c z) r)
	           (every (lambda (x) (memq x cells)) (pair-fold cons '() r))))))

    (define ~check-srfi-1-131
      (check '(3 . #t) (assoc 6
			     '((4 . #t) (3 . #t) (5 . #t))
			     (lambda (x y)
			       (zero? (remainder x y))))))

    (define ~check-srfi-1-132
      (check '((1 . #t) (2 . #f)) (alist-cons 1 #t '((2 . #f)))))

    (define ~check-srfi-1-133
      (check #t (let* ((a (list (cons 1 2) (cons 3 4)))
	              (b (alist-copy a)))
                 (and (equal? a b)
	              (every (lambda (x) (not (memq x b))) a)
	              (every (lambda (x) (not (memq x a))) b)))))

    (define ~check-srfi-1-134
      (check '((1 . #t) (2 . #t) (4 . #t))
	    (alist-delete 5 '((1 . #t) (2 . #t) (37 . #t) (4 . #t) (48 #t)) <)))

    (define ~check-srfi-1-135
      (check '((1 . #t) (2 . #t) (4 . #t))
	    (alist-delete 7 '((1 . #t) (2 . #t) (7 . #t) (4 . #t) (7 #t)))))

    (define ~check-srfi-1-136
      (check '((4 . #t) (7 . #t))
            (let* ((x (list-copy '((1 . #t) (2 . #t) (7 . #t) (4 . #t) (7 . #t))))
	           (y (list-copy x))
	           (cells (pair-fold cons '() x))
	           (r (alist-delete! 7 x)))
              (and (equal? r '((1 . #t) (2 . #t) (4 . #t)))
	           (every (lambda (x) (memq x cells)) (pair-fold cons '() r))
	           (every (lambda (x) (memq x y)) r)))))

    (define ~check-srfi-1-137
      (check #t (lset<= eq? '(a) '(a b a) '(a b c c))))

    (define ~check-srfi-1-138
      (check #f (lset<= eq? '(a) '(a b a) '(a))))

    (define ~check-srfi-1-139
      (check #t (lset<= eq?)))

    (define ~check-srfi-1-140
      (check #t (lset<= eq? '(a))))

    (define ~check-srfi-1-141
      (check #t (lset= eq? '(b e a) '(a e b) '(e e b a))))

    (define ~check-srfi-1-142
      (check #f (lset= eq? '(b e a) '(a e b) '(e e b a c))))

    (define ~check-srfi-1-143
      (check #t (lset= eq?)))

    (define ~check-srfi-1-144
      (check #t (lset= eq? '(a))))

    (define ~check-srfi-1-145
      (check '(u o i a b c d c e)
	    (lset-adjoin eq? '(a b c d c e) 'a 'e 'i 'o 'u)))

    (define ~check-srfi-1-146
      (check '(u o i a b c d e)
	    (lset-union eq? '(a b c d e) '(a e i o u))))

    (define ~check-srfi-1-147
      (check '(x a a c) (lset-union eq? '(a a c) '(x a x))))

    (define ~check-srfi-1-148
      (check #t (null? (lset-union eq?))))

    (define ~check-srfi-1-149
      (check '(a b c) (lset-union eq? '(a b c))))

    (define ~check-srfi-1-150
      (check '(a e) (lset-intersection eq? '(a b c d e) '(a e i o u))))

    (define ~check-srfi-1-151
      (check '(a x a) (lset-intersection eq? '(a x y a) '(x a x z))))

    (define ~check-srfi-1-152
      (check '(a b c) (lset-intersection eq? '(a b c))))

    (define ~check-srfi-1-153
      (check '(b c d) (lset-difference eq? '(a b c d e) '(a e i o u))))

    (define ~check-srfi-1-154
      (check '(a b c) (lset-difference eq? '(a b c))))

    (define ~check-srfi-1-155
      (let ((x '(d c b i o u)))
        (check x (lset= eq? x (lset-xor eq? '(a b c d e) '(a e i o u))))))

    (define ~check-srfi-1-156
      (check #t (lset= eq? '() (lset-xor eq?))))

    (define ~check-srfi-1-157
      (let ((x '(a b c d e)))
        (check '(e) (lset= eq? x (lset-xor eq? '(a b c d e))))))

    (define ~check-srfi-1-158
      (check #t (let-values (((d i) (lset-diff+intersection eq? '(a b c d e) '(c d f))))
                 (and (equal? d '(a b e))
	              (equal? i '(c d))))))

    ;; FIXME: For the following five procedures, need to check that
    ;; cells returned are from the arguments.

    (define ~check-srfi-1-159
      (check '(u o i a b c d e)
	    (lset-union! eq? (list 'a 'b 'c 'd 'e) (list 'a 'e 'i 'o 'u))))

    (define ~check-srfi-1-160
      (check '(x a a c) (lset-union! eq? (list 'a 'a 'c) (list 'x 'a 'x))))

    (define ~check-srfi-1-161
      (check #t (null? (lset-union! eq?))))

    (define ~check-srfi-1-162
      (check '(a b c) (lset-union! eq? (list 'a 'b 'c))))

    (define ~check-srfi-1-163
      (check '(a e) (lset-intersection! eq?
                                       (list 'a 'b 'c 'd 'e)
				       (list 'a 'e 'i 'o 'u))))

    (define ~check-srfi-1-164
      (check '(a x a) (lset-intersection! eq?
                                         (list 'a 'x 'y 'a)
					 (list 'x 'a 'x 'z))))
    (define ~check-srfi-1-165
      (check '(a b c) (lset-intersection! eq? (list 'a 'b 'c))))

    (define ~check-srfi-1-166
      (check '(b c d) (lset-difference! eq?
                                       (list 'a 'b 'c 'd 'e)
				       (list 'a 'e 'i 'o 'u))))

    (define ~check-srfi-1-167
      (check '(a b c) (lset-difference! eq? (list 'a 'b 'c))))

    (define ~check-srfi-1-168
      (let ((x '(d c b i o u)))
        (check x (lset= eq? x
                       (lset-xor! eq?
                                  (list 'a 'b 'c 'd 'e)
				  (list 'a 'e 'i 'o 'u))))))

    (define ~check-srfi-1-169
      (check #t (lset= eq? '() (lset-xor! eq?))))

    (define ~check-srfi-1-170
      (check '(e) (lset= eq? '(a b c d e) (lset-xor! eq? (list 'a 'b 'c 'd 'e)))))

    (define ~check-srfi-1-171
      (check #t (let-values (((d i) (lset-diff+intersection! eq?
                                                            (list 'a 'b 'c 'd 'e)
						            (list 'c 'd 'f))))
                 (and (equal? d '(a b e))
	              (equal? i '(c d))))))))

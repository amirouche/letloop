(library (srfi srfi-134 check)

  (export check-000 check-001 check-002 check-003 check-004 check-005
check-006 check-007 check-008 check-009 check-010 check-011 check-012
check-013 check-014 check-015 check-016 check-017 check-018 check-019
check-020 check-021 check-022 check-023 check-024 check-025 check-026
check-027 check-028 check-029 check-030 check-031 check-032 check-033
check-034 check-035 #;check-036 #;check-037 #;check-038 check-039 check-040
check-041 check-042 check-043 check-044 check-045 check-046 check-047
check-048 check-049 check-050 check-051 check-052 check-053 check-054
check-055 check-056 check-057 check-058 check-059 check-060 check-061
check-062 check-063 check-064 check-065 check-066 check-067 check-068
check-069 check-070 check-071 check-072 check-073 check-074 check-075
check-076 check-077 check-078 check-079 check-080 check-081 check-082
check-083 check-084 check-085 check-086 check-087 check-088 check-089
check-090 check-091 check-092 check-093 check-094 check-095)

  (import (scheme base)
          (scheme char)
          (srfi srfi-158)
          (srfi srfi-134)
          (check))

  (begin

    (define-syntax receive
      (syntax-rules ()
        ((receive ?formals ?producer ?body1 ?body2 ...)
         (call-with-values (lambda () ?producer)
           (lambda ?formals ?body1 ?body2 ...)))))

    (define check-000
      (check '() (ideque->list (ideque))))

    (define check-001
      (check '() (ideque->list (list->ideque '()))))

    (define check-002
      (check '(1 2 3) (ideque->list (ideque 1 2 3))))

    (define check-003
      (check '(4 5 6 7) (ideque->list (list->ideque '(4 5 6 7)))))

    (define check-004
      (check '(10 9 8 7 6 5 4 3 2 1)
             (ideque->list (ideque-unfold zero? values (lambda (n) (- n 1)) 10))))

    (define check-005
      (check '(1 2 3 4 5 6 7 8 9 10)
             (ideque->list (ideque-unfold-right zero? values (lambda (n) (- n 1)) 10))))

    (define check-006
      (check '(0 2 4 6 8 10)
             (ideque->list (ideque-tabulate 6 (lambda (n) (* n 2))))))

    ;; corner cases
    (define check-007
      (check '() (ideque->list
                  (ideque-unfold (lambda (n) #t) values (lambda (n) (+ n 1)) 0))))

    (define check-008
      (check '() (ideque->list
                  (ideque-unfold-right (lambda (n) #t) values (lambda (n) (+ n 1)) 0))))

    (define check-009
      (check '() (ideque->list (ideque-tabulate 0 values))))

    (define check-010
      (check (ideque? (ideque))))

    (define check-011
      (check (not (ideque? 1))))

    (define check-012
      (check (ideque-empty? (ideque))))

    (define check-013
      (check (not (ideque-empty? (ideque 1)))))

    (define check-014
      (check (ideque= eq?)))

    (define check-015
      (check (ideque= eq? (ideque 1))))

    (define check-016
      (check (ideque= char-ci=? (ideque #\a #\b) (ideque #\A #\B))))

    (define check-017
      (check (ideque= char-ci=? (ideque) (ideque))))

    (define check-018
      (check (not (ideque= char-ci=? (ideque #\a #\b) (ideque #\A #\B #\c)))))

    (define check-019
      (check (not (ideque= char-ci=? (ideque #\a #\b) (ideque #\A)))))

    (define check-020
      (check (ideque= char-ci=? (ideque) (ideque) (ideque))))

    (define check-021
      (check (ideque= char-ci=? (ideque #\a #\b) (ideque #\A #\B) (ideque #\a #\B))))

    (define check-022
      (check (not (ideque= char-ci=? (ideque #\a #\b) (ideque #\A) (ideque #\a #\B)))))

    (define check-023
      (check (not (ideque= char-ci=? (ideque #\a #\b) (ideque #\A #\B) (ideque #\A #\B #\c)))))

    (define check-024
      (check-raise (lambda (x) #t) (ideque-front (ideque))))

    (define check-025
      (check-raise (lambda (x) #t) (ideque-back (ideque))))

    (define check-026
      (check 1 (ideque-front (ideque 1 2 3))))

    (define check-027
      (check 3 (ideque-back (ideque 1 2 3))))

    (define check-028
      (check 2 (ideque-front (ideque-remove-front (ideque 1 2 3)))))

    (define check-029
      (check 2 (ideque-back (ideque-remove-back (ideque 1 2 3)))))

    (define check-030
      (check 1 (ideque-front (ideque-remove-back (ideque 1 2 3)))))

    (define check-031
      (check 3 (ideque-back (ideque-remove-front (ideque 1 2 3)))))

    (define check-032
      (check (ideque-empty? (ideque-remove-front (ideque 1)))))

    (define check-033
      (check (ideque-empty? (ideque-remove-back (ideque 1)))))

    (define check-034
      (check 0 (ideque-front (ideque-add-front (ideque 1 2 3) 0))))

    (define check-035
      (check 0 (ideque-back (ideque-add-back (ideque 1 2 3) 0))))

    ;; TODO: uncomment and adapt

    ;; (define (check* name ideque-op list-op n)
    ;;   (let* ((lis (iota n))
    ;;          (dq (list->ideque lis)))
    ;;     (for-each (lambda (i)
    ;;                 (check (cons name i)
    ;;                        (receive xs (list-op lis i) xs)
    ;;                        (receive xs (ideque-op dq i)
    ;;                          (map ideque->list xs))))
    ;;               lis)))

    ;; (check* 'ideque-take ideque-take take 7)
    ;; (check* 'ideque-drop ideque-drop drop 6)
    ;; (check* 'ideque-split-at ideque-split-at split-at 8)

    ;; out-of-range conditions
    (define check-039
      (check-raise (lambda (x) #t) (ideque->list (ideque-take (ideque 1 2 3 4 5 6 7) 10))))

    (define check-040
      (check-raise (lambda (x) #t) (ideque->list (ideque-take-right (ideque 1 2 3 4 5 6 7) 10))))

    (define check-041
      (check-raise (lambda (x) #t) (ideque-split-at (ideque 1 2 3 4 5 6 7) 10)))

    (define check-042
      (check '(3 2 1) (map (lambda (n) (ideque-ref (ideque 3 2 1) n)) '(0 1 2))))

    (define check-043
      (check-raise (lambda (x) #t) (ideque-ref (ideque 3 2 1) -1)))

    (define check-044
      (check-raise (lambda (x) #t) (ideque-ref (ideque 3 2 1) 3)))

    (define check-045
      (check 7 (ideque-length (ideque 1 2 3 4 5 6 7))))

    (define check-046
      (check 0 (ideque-length (ideque))))

    (define check-047
      (check '() (ideque->list (ideque-append))))

    (define check-048
      (check '() (ideque->list (ideque-append (ideque) (ideque)))))

    (define check-049
      (check '(1 2 3 a b c d 5 6 7 8 9)
             (ideque->list (ideque-append (ideque 1 2 3)
                                          (ideque 'a 'b 'c 'd)
                                          (ideque)
                                          (ideque 5 6 7 8 9)))))

    (define check-050
      (check '() (ideque->list (ideque-reverse (ideque)))))

    (define check-051
      (check '(5 4 3 2 1) (ideque->list (ideque-reverse (ideque 1 2 3 4 5)))))

    (define check-052
      (check 0 (ideque-count odd? (ideque))))

    (define check-053
      (check 3 (ideque-count odd? (ideque 1 2 3 4 5))))

    (define check-054
      (check '((1 a) (2 b) (3 c))
             (ideque->list (ideque-zip (ideque 1 2 3) (ideque 'a 'b 'c 'd 'e)))))

    (define check-055
      (check '((1 a x) (2 b y) (3 c z))
             (ideque->list (ideque-zip (ideque 1 2 3 4 5)
                                       (ideque 'a 'b 'c 'd 'e)
                                       (ideque 'x 'y 'z)))))

    (define check-056
      (check '((1) (2) (3))
             (ideque->list (ideque-zip (ideque 1 2 3)))))

    (define check-057
      (check '()
             (ideque->list (ideque-zip (ideque 1 2 3) (ideque)))))

    (define check-058
      (check (ideque-empty? (ideque-map list (ideque)))))

    (define check-059
      (check '(-1 -2 -3 -4 -5) (ideque->list (ideque-map - (ideque 1 2 3 4 5)))))

    (define check-060
      (check '(-1 -3 5 -8)
             (ideque->list (ideque-filter-map (lambda (x) (and (number? x) (- x)))
                                              (ideque 1 3 'a -5 8)))))

    (define check-061
      (check '(5 4 3 2 1)
             (let ((r '()))
               (ideque-for-each (lambda (n) (set! r (cons n r)))
                                (ideque 1 2 3 4 5))
               r)))

    (define check-062
      (check '(1 2 3 4 5)
             (let ((r '()))
               (ideque-for-each-right (lambda (n) (set! r (cons n r)))
                                      (ideque 1 2 3 4 5))
               r)))

    (define check-063
      (check '(5 4 3 2 1 . z)
             (ideque-fold cons 'z (ideque 1 2 3 4 5))))

    (define check-064
      (check '(1 2 3 4 5 . z)
             (ideque-fold-right cons 'z (ideque 1 2 3 4 5))))

    (define check-065
      (check '(a a b b c c)
             (ideque->list (ideque-append-map (lambda (x) (list x x))
                                              (ideque 'a 'b 'c)))))

    (define check-066
      (check '(1 3 5)
             (ideque->list (ideque-filter odd? (ideque 1 2 3 4 5)))))

    (define check-067
      (check '(2 4)
             (ideque->list (ideque-remove odd? (ideque 1 2 3 4 5)))))

    (define check-068
      (check '((1 3 5) (2 4))
             (receive xs (ideque-partition odd? (ideque 1 2 3 4 5))
               (map ideque->list xs))))

    (define check-069
      (check 3 (ideque-find number? (ideque 'a 3 'b 'c 4 'd) (lambda () 'boo))))

    (define check-070
      (check 'boo (ideque-find number? (ideque 'a 'b 'c 'd) (lambda () 'boo))))

    (define check-071
      (check #f (ideque-find number? (ideque 'a 'b 'c 'd))))

    (define check-072
      (check 4 (ideque-find-right number? (ideque 'a 3 'b 'c 4 'd) (lambda () 'boo))))

    (define check-073
      (check 'boo (ideque-find-right number? (ideque 'a 'b 'c 'd) (lambda () 'boo))))

    (define check-074
      (check #f (ideque-find-right number? (ideque 'a 'b 'c 'd))))

    (define check-075
      (check '(1 3 2)
             (ideque->list (ideque-take-while (lambda (n) (< n 5))
                                              (ideque 1 3 2 5 8 4 6 3 4 2)))))

    (define check-076
      (check '(5 8 4 6 3 4 2)
             (ideque->list (ideque-drop-while (lambda (n) (< n 5))
                                              (ideque 1 3 2 5 8 4 6 3 4 2)))))

    (define check-077
      (check '(3 4 2)
             (ideque->list (ideque-take-while-right (lambda (n) (< n 5))
                                                    (ideque 1 3 2 5 8 4 6 3 4 2)))))

    (define check-078
      (check '(1 3 2 5 8 4 6)
             (ideque->list (ideque-drop-while-right (lambda (n) (< n 5))
                                                    (ideque 1 3 2 5 8 4 6 3 4 2)))))

    (define check-079
      (check '()
             (ideque->list (ideque-take-while (lambda (n) (< n 5))
                                              (ideque 5 8 4 6 3 4 2 9)))))

    (define check-080
      (check '()
             (ideque->list (ideque-drop-while (lambda (n) (< n 5))
                                              (ideque 1 4 3 2 3 4 2 1)))))

    (define check-081
      (check '()
             (ideque->list (ideque-take-while-right (lambda (n) (< n 5))
                                                    (ideque 5 8 4 6 3 4 2 9)))))

    (define check-082
      (check '()
             (ideque->list (ideque-drop-while-right (lambda (n) (< n 5))
                                                    (ideque 1 3 2 4 3 2 3 2)))))

    (define check-083
      (check '((1 3 2) (5 8 4 6 3 4 2))
             (receive xs (ideque-span (lambda (n) (< n 5))
                                      (ideque 1 3 2 5 8 4 6 3 4 2))
               (map ideque->list xs))))

    (define check-084
      (check '((5 8) (4 6 3 4 2 9))
             (receive xs (ideque-break (lambda (n) (< n 5))
                                       (ideque 5 8 4 6 3 4 2 9))
               (map ideque->list xs))))

    (define check-085
      (check 3 (ideque-any (lambda (x) (and (number? x) x))
                           (ideque 'a 3 'b 'c 4 'd 'e))))

    (define check-086
      (check 5 (ideque-any (lambda (x) (and (number? x) x))
                           (ideque 'a 'b 'c 'd 'e 5))))

    (define check-087
      (check #f (ideque-any (lambda (x) (and (number? x) x))
                            (ideque 'a 'b 'c 'd 'e))))

    (define check-088
      (check 9 (ideque-every (lambda (x) (and (number? x) x))
                             (ideque 1 5 3 2 9))))

    (define check-089
      (check #f (ideque-every (lambda (x) (and (number? x) x))
                              (ideque 1 5 'a 2 9))))

    (define check-090
      ;; check if we won't see further once we found the result
      (check 1 (ideque-any (lambda (x) (and (odd? x) x))
                           (ideque 2 1 'a 'b 'c 'd))))

    (define check-091
      (check #f (ideque-every (lambda (x) (and (odd? x) x))
                              (ideque 1 2 'a 'b 'c 'd))))

    (define check-092
      (check '(1 2 3) (generator->list (ideque->generator (ideque 1 2 3)))))

    (define check-093
      (check '() (generator->list (ideque->generator (ideque)))))

    (define check-094
      (check '(1 2 3) (ideque->list (generator->ideque (generator 1 2 3)))))

    (define check-095
      (check '() (ideque->list (generator->ideque (generator)))))))

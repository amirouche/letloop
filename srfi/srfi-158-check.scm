(library (srfi srfi-158-check)
  (export
   ~check-srfi-158-000 ~check-srfi-158-001 ~check-srfi-158-002 ~check-srfi-158-003 ~check-srfi-158-004 ~check-srfi-158-005 ~check-srfi-158-006 ~check-srfi-158-007 ~check-srfi-158-008 ~check-srfi-158-009
   ~check-srfi-158-010 ~check-srfi-158-011 ~check-srfi-158-012 ~check-srfi-158-013 ~check-srfi-158-014 ~check-srfi-158-015 ~check-srfi-158-016 ~check-srfi-158-017 ~check-srfi-158-018 ~check-srfi-158-019
   ~check-srfi-158-020 ~check-srfi-158-021 ~check-srfi-158-022 ~check-srfi-158-023 ~check-srfi-158-024 ~check-srfi-158-025 ~check-srfi-158-026 ~check-srfi-158-027 ~check-srfi-158-028 ~check-srfi-158-029
   ~check-srfi-158-030 ~check-srfi-158-031 ~check-srfi-158-032 ~check-srfi-158-033 ~check-srfi-158-034 ~check-srfi-158-035 ~check-srfi-158-036 ~check-srfi-158-037 ~check-srfi-158-038 ~check-srfi-158-039
   ~check-srfi-158-040 ~check-srfi-158-041 ~check-srfi-158-042 ~check-srfi-158-043 ~check-srfi-158-044 ~check-srfi-158-045 ~check-srfi-158-046 ~check-srfi-158-047 ~check-srfi-158-048 ~check-srfi-158-049
   ~check-srfi-158-050 ~check-srfi-158-051 ~check-srfi-158-052 ~check-srfi-158-053 ~check-srfi-158-054 ~check-srfi-158-055 ~check-srfi-158-056 ~check-srfi-158-057 ~check-srfi-158-058 ~check-srfi-158-059
   ~check-srfi-158-060 ~check-srfi-158-061 ~check-srfi-158-062 ~check-srfi-158-063 ~check-srfi-158-064 ~check-srfi-158-065 ~check-srfi-158-066 ~check-srfi-158-067 ~check-srfi-158-068 ~check-srfi-158-069
   ~check-srfi-158-070 ~check-srfi-158-071)

  (import (scheme base)
          (letloop check)
          (srfi srfi-1)
          (srfi srfi-4)
          (srfi srfi-158))

  ;; generators/constructors

  (define ~check-srfi-158-000
    (check '() (generator->list (generator))))

  (define ~check-srfi-158-001
    (check '(1 2 3) (generator->list (generator 1 2 3))))

    ;; TODO: FIXME
    ;; (check-equal '(1 2 3 1 2) (generator->list (circular-generator 1 2 3) 5))

  (define ~check-srfi-158-002
    (check '(8 9 10) (generator->list (make-iota-generator 3 8))))

  (define ~check-srfi-158-003
    (check '(8 10 12) (generator->list (make-iota-generator 3 8 2))))

  (define ~check-srfi-158-004
    (check '(3 4 5 6) (generator->list (make-range-generator 3) 4)))

  (define ~check-srfi-158-005
    (check '(3 4 5 6 7) (generator->list (make-range-generator 3 8))))

  (define ~check-srfi-158-006
    (check '(3 5 7) (generator->list (make-range-generator 3 8 2))))

  (define ~check-srfi-158-007
    (let ()
      (define g
        (make-coroutine-generator
         (lambda (yield) (let loop ((i 0))
                           (when (< i 3) (yield i) (loop (+ i 1)))))))
      (check '(0 1 2) (generator->list g))))

  (define ~check-srfi-158-008
    (check '(1 2 3 4 5) (generator->list (list->generator '(1 2 3 4 5)))))

  (define ~check-srfi-158-009
    (check '(1 2 3 4 5) (generator->list (vector->generator '#(1 2 3 4 5)))))

  (define ~check-srfi-158-010
    (check '#(0 0 1 2 4)
          (let ((v (make-vector 5 0)))
            (generator->vector! v 2 (generator 1 2 4))
            v)))

  (define ~check-srfi-158-011
    (check '(5 4 3 2 1) (generator->list (reverse-vector->generator '#(1 2 3 4 5)))))

  (define ~check-srfi-158-012
    (check '(#\a #\b #\c #\d #\e) (generator->list (string->generator "abcde"))))

  (define ~check-srfi-158-013
    (check '(10 20 30) (generator->list (bytevector->generator (bytevector 10 20 30)))))

  (define ~check-srfi-158-014
    (let ()
      (define (for-each-digit proc n)
        (when (> n 0)
          (let-values (((div rem) (truncate/ n 10)))
            (proc rem)
            (for-each-digit proc div))))
      (check '(5 4 3 2 1) (generator->list
                                (make-for-each-generator for-each-digit
                                                         12345)))))

  (define ~check-srfi-158-015
    (check '(0 2 4 6 8 10) (generator->list
                           (make-unfold-generator
                            (lambda (s) (> s 5))
                            (lambda (s) (* s 2))
                            (lambda (s) (+ s 1))
                            0))))

  ;; generators/operators

  (define ~check-srfi-158-016
    (check '(a b 0 1) (generator->list (gcons* 'a 'b (make-range-generator 0 2)))))

  (define ~check-srfi-158-017
    (check '(0 1 2 0 1) (generator->list (gappend (make-range-generator 0 3)
                                                 (make-range-generator 0 2)))))

  (define ~check-srfi-158-018
    (check '() (generator->list (gappend))))

  (define ~check-srfi-158-019
    (let ()
      (define g1 (generator 1 2 3))
      (define g2 (generator 4 5 6 7))
      (define (proc . args) (values (apply + args) (apply + args)))
      (check '(15 22 31) (generator->list (gcombine proc 10 g1 g2)))))

  (define ~check-srfi-158-020
    (check '(1 3 5 7 9) (generator->list (gfilter
                                         odd?
                                         (make-range-generator 1 11)))))

  (define ~check-srfi-158-021
    (check '(2 4 6 8 10) (generator->list (gremove
                                          odd?
                                          (make-range-generator 1 11)))))

  (define g (make-range-generator 1 5))

  (define ~check-srfi-158-022
    (check '(1 2 3) (generator->list (gtake g 3))))

  (define ~check-srfi-158-023
    (check '(4) (generator->list g)))

  (define ~check-srfi-158-024
    (check '(1 2) (generator->list (gtake (make-range-generator 1 3) 3))))

  (define ~check-srfi-158-025
    (check '(1 2 0) (generator->list (gtake (make-range-generator 1 3) 3 0))))

  (define ~check-srfi-158-026
    (check '(3 4) (generator->list (gdrop (make-range-generator 1 5) 2))))

  (define g2 (make-range-generator 1 5))

  (define (small? x) (< x 3))

  (define ~check-srfi-158-027
    (check '(1 2) (generator->list (gtake-while small? g2))))

  (define g3 (make-range-generator 1 5))

  (define ~check-srfi-158-028
    (check '(3 4) (generator->list (gdrop-while small? g3))))

  (define ~check-srfi-158-029
    (check '() (generator->list (gdrop-while (lambda args #t) (generator 1 2 3)))))

  (define ~check-srfi-158-030
    (check '(0.0 1.0 0 2) (generator->list (gdelete 1
                                                   (generator 0.0 1.0 0 1 2)))))

  (define ~check-srfi-158-031
    (check '(0.0 0 2) (generator->list (gdelete 1
                                               (generator 0.0 1.0 0 1 2)
                                               =))))

  (define ~check-srfi-158-032
    (check '(a c e) (generator->list (gindex (list->generator '(a b c d e f))
                                            (list->generator '(0 2 4))))))

  (define ~check-srfi-158-033
    (check '(a d e) (generator->list (gselect (list->generator '(a b c d e f))
                                             (list->generator '(#t #f #f #t #t #f))))))

  (define ~check-srfi-158-034
    (check '(1 2 3) (generator->list (gdelete-neighbor-dups
                                     (generator 1 1 2 3 3 3)
                                     =))))

  (define ~check-srfi-158-035
    (check '(1) (generator->list (gdelete-neighbor-dups
                                 (generator 1 2 3)
                                 (lambda args #t)))))

  (define ~check-srfi-158-036
    (check '(1 2 3 a b c)
          (generator->list
           (gflatten (generator '(1 2 3) '(a b c))))))

  (define ~check-srfi-158-037
    (check '((1 2 3) (4 5 6) (7 8))
          (generator->list (ggroup (generator 1 2 3 4 5 6 7 8) 3))))

  (define ~check-srfi-158-038
    (check '((1 2 3) (4 5 6) (7 8 0))
          (generator->list (ggroup (generator 1 2 3 4 5 6 7 8) 3 0))))

  (define ~check-srfi-158-039
    (check '(1 2 3)
          (generator->list (gmerge < (generator 1 2 3)))))

  (define ~check-srfi-158-040
    (check '(1 2 3 4 5 6)
          (generator->list (gmerge < (generator 1 2 3) (generator 4 5 6)))))

  (define ~check-srfi-158-041
    (check '(1 2 3 4 4 5 6)
      (generator->list (gmerge <
                               (generator 1 2 4 6)
                               (generator)
                               (generator 3 4 5)))))

  (define ~check-srfi-158-042
    (check '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
          (generator->list (gmerge <
                                   (generator 1 10 11)
                                   (generator 2 9 12)
                                   (generator 3 8 13)
                                   (generator 4 7 14)
                                   (generator 5 6 15)))))

  (define ~check-srfi-158-043
    ;; check the tie-break rule
    (check '((1 a) (1 e) (1 b) (1 c) (1 d))
          (generator->list (gmerge (lambda (x y) (< (car x) (car y)))
                                   (generator '(1 a) '(1 e))
                                   (generator '(1 b))
                                   (generator '(1 c) '(1 d))))))

  (define ~check-srfi-158-044
    (check '(-1 -2 -3 -4 -5)
          (generator->list (gmap - (generator 1 2 3 4 5)))))

  (define ~check-srfi-158-045
    (check '(7 9 11 13)
          (generator->list (gmap +
                                 (generator 1 2 3 4 5)
                                 (generator 6 7 8 9)))))

  (define ~check-srfi-158-046
    (check '(54 140 264)
          (generator->list (gmap *
                                 (generator 1 2 3 4 5)
                                 (generator 6 7 8)
                                 (generator 9 10 11 12 13)))))

  (define ~check-srfi-158-047
    (check '(a c e g i)
          (generator->list
           (gstate-filter
            (lambda (item state) (values (even? state) (+ 1 state)))
            0
            (generator 'a 'b 'c 'd 'e 'f 'g 'h 'i 'j)))))

  ;; generators/consumers

  (define ~check-srfi-158-048
    ;; no ~check-srfi-158-equal for plain generator->list (used throughout)
    (check '(1 2 3) (generator->list (generator 1 2 3 4 5) 3)))

  (define ~check-srfi-158-049
    (check '(5 4 3 2 1) (generator->reverse-list (generator 1 2 3 4 5))))

  (define ~check-srfi-158-050
    (check '#(1 2 3 4 5) (generator->vector (generator 1 2 3 4 5))))

  (define ~check-srfi-158-051
    (check '#(1 2 3) (generator->vector (generator 1 2 3 4 5) 3)))

  (define ~check-srfi-158-052
    (check "abc" (generator->string (generator #\a #\b #\c))))

  ;; TODO: FIXME
  ;; (check-equal '(e d c b a . z) (with-input-from-string "a b c d e"
  ;;                                (lambda () (generator-fold cons 'z read))))

  (define ~check-srfi-158-053
    (check 6 (let ()
              (define n 0)
              (generator-for-each (lambda values (set! n (apply + values)))
                                  (generator 1) (generator 2) (generator 3))
              n)))

  (define ~check-srfi-158-054
    (check '(6 15)
          (generator-map->list (lambda values (apply + values))
                               (generator 1 4) (generator 2 5) (generator 3 6))))

  (define ~check-srfi-158-055
    (check 3 (generator-find (lambda (x) (> x 2)) (make-range-generator 1 5))))

  (define ~check-srfi-158-056
    (check 2 (generator-count odd? (make-range-generator 1 5))))

  (define ~check-srfi-158-057
    (check #t
          (let ()
            (define g (make-range-generator 2 5))
            (and
             (equal? #t (generator-any odd? g))
             (equal? '(4) (generator->list g))))))

  (define ~check-srfi-158-058
    (check #t
          (let ()
            (define g (make-range-generator 2 5))
            (and
             (equal? #f (generator-every odd? g))
             (equal? '(3 4) (generator->list g))))))

  (define ~check-srfi-158-059
    (check '(#\a #\b #\c)
          (generator-unfold (make-for-each-generator string-for-each "abc") unfold)))

  ;; accumulators

  (define ~check-srfi-158-060
    (check -8
          (let ((a (make-accumulator * 1 -)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-061
    (check 3
          (let ((a (count-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-062
    (check '(1 2 4)
          (let ((a (list-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-063
    (check '(4 2 1)
          (let ((a (reverse-list-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-064
    (check '#(1 2 4)
          (let ((a (vector-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-065
    (check '#(0 0 1 2 4)
          (let* ((v (vector 0 0 0 0 0))
                 (a (vector-accumulator! v 2)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-066
    (check '#vu8(0 0 1 2 4)
          (let* ((v (bytevector 0 0 0 0 0))
                 (a (bytevector-accumulator! v 2)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-067
    (check '#(4 2 1)
          (let ((a (reverse-vector-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-068
    (check "abc"
          (let ((a (string-accumulator)))
            (a #\a)
            (a #\b)
            (a #\c)
            (a (eof-object)))))

  (define ~check-srfi-158-069
    (check #vu8(1 2 4)
          (let ((a (bytevector-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-070
    (check 7
          (let ((a (sum-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object)))))

  (define ~check-srfi-158-071
    (check 8
          (let ((a (product-accumulator)))
            (a 1)
            (a 2)
            (a 4)
            (a (eof-object))))))

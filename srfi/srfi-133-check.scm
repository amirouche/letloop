(library (srfi srfi-133-check)

  (export ~check-srfi-133-000 ~check-srfi-133-001 ~check-srfi-133-002 ~check-srfi-133-003 ~check-srfi-133-004 ~check-srfi-133-005
~check-srfi-133-006 ~check-srfi-133-007 ~check-srfi-133-008 ~check-srfi-133-009 ~check-srfi-133-010 ~check-srfi-133-011 ~check-srfi-133-012
~check-srfi-133-013 ~check-srfi-133-014 ~check-srfi-133-015 ~check-srfi-133-016 ~check-srfi-133-017 ~check-srfi-133-018 ~check-srfi-133-019
~check-srfi-133-020 ~check-srfi-133-021 ~check-srfi-133-022 ~check-srfi-133-023 ~check-srfi-133-024 ~check-srfi-133-025 ~check-srfi-133-026
~check-srfi-133-027 ~check-srfi-133-028 ~check-srfi-133-029 ~check-srfi-133-030 ~check-srfi-133-031 ~check-srfi-133-032 ~check-srfi-133-033
~check-srfi-133-034 ~check-srfi-133-035 ~check-srfi-133-036 ~check-srfi-133-037 ~check-srfi-133-038 ~check-srfi-133-039 ~check-srfi-133-040
~check-srfi-133-041 ~check-srfi-133-042 ~check-srfi-133-043 ~check-srfi-133-044 ~check-srfi-133-045 ~check-srfi-133-046 ~check-srfi-133-047
~check-srfi-133-048 ~check-srfi-133-049 ~check-srfi-133-050 ~check-srfi-133-051 ~check-srfi-133-052 ~check-srfi-133-053 ~check-srfi-133-054
~check-srfi-133-055 ~check-srfi-133-056 ~check-srfi-133-057 ~check-srfi-133-058 ~check-srfi-133-059 ~check-srfi-133-060 ~check-srfi-133-061
~check-srfi-133-062 ~check-srfi-133-063 ~check-srfi-133-064 ~check-srfi-133-065 ~check-srfi-133-066 ~check-srfi-133-067 ~check-srfi-133-068
~check-srfi-133-069 ~check-srfi-133-070 ~check-srfi-133-071 ~check-srfi-133-072 ~check-srfi-133-073 ~check-srfi-133-074 ~check-srfi-133-075
~check-srfi-133-076 ~check-srfi-133-077 ~check-srfi-133-078 ~check-srfi-133-079 ~check-srfi-133-080 ~check-srfi-133-081 ~check-srfi-133-082
~check-srfi-133-083 ~check-srfi-133-084 ~check-srfi-133-085 ~check-srfi-133-086 ~check-srfi-133-087 ~check-srfi-133-088 ~check-srfi-133-089
~check-srfi-133-090 ~check-srfi-133-091 ~check-srfi-133-092 ~check-srfi-133-093 ~check-srfi-133-094 ~check-srfi-133-095 ~check-srfi-133-096
~check-srfi-133-097 ~check-srfi-133-098 ~check-srfi-133-099 ~check-srfi-133-100 ~check-srfi-133-101 ~check-srfi-133-102 ~check-srfi-133-103
~check-srfi-133-104)

  (import (except (scheme base) string->vector vector->string
                  list->vector vector->list vector-copy! vector-fill! vector-map
                  vector-append vector-copy)
          (srfi srfi-133)
          (letloop check))


  (define v (make-vector 3 3))

  (define ~check-srfi-133-000
    (check (vector? '#(1 2 3))))

  (define ~check-srfi-133-001
    (check (vector? (make-vector 10))))

  (define ~check-srfi-133-002
    (check 3 (vector-ref v 0)))

  (define ~check-srfi-133-003
    (check 3 (vector-ref v 1)))

  (define ~check-srfi-133-004
    (check 3 (vector-ref v 2)))

  (define ~check-srfi-133-005
    (~check-srfi-133-raise (vector-ref v -1)))

  (define ~check-srfi-133-006
    (~check-srfi-133-raise (vector-ref v 3)))

  (define ~check-srfi-133-007
    (check -32 (begin
                 (vector-set! v 0 -32)
                 (vector-ref v 0))))

  (define ~check-srfi-133-008
    (check 3 (vector-length v)))

  (define ~check-srfi-133-009
    (check 0 (vector-length '#())))

  (define a2i '#(a b c d e f g h i))

  (define ~check-srfi-133-010
    (check '#(0 1 2 3 4) (vector 0 1 2 3 4)))

  (define ~check-srfi-133-011
    (check '#(0 -1 -2 -3 -4 -5 -6 -7 -8 -9)
           (vector-unfold (lambda (i x) (values x (- x 1))) 10 0)))

  (define ~check-srfi-133-012
    (check '#(0 1 2 3 4 5 6) (vector-unfold values 7)))

  (define ~check-srfi-133-013
    (check '#((0 . 4) (1 . 3) (2 . 2) (3 . 1) (4 . 0))
           (vector-unfold-right (lambda (i x) (values (cons i x) (+ x 1))) 5 0)))

  (define ~check-srfi-133-014
    (check a2i (vector-copy a2i)))

  (define ~check-srfi-133-015
    (check (not (eqv? a2i (vector-copy a2i)))))

  (define ~check-srfi-133-016
    (check '#(g h i) (vector-copy a2i 6)))

  (define ~check-srfi-133-017
    (check '#(d e f) (vector-copy a2i 3 6)))

  (define ~check-srfi-133-018
    (check '#(1 2 3 4) (vector-reverse-copy '#(5 4 3 2 1 0) 1 5)))

  (define ~check-srfi-133-019
    (check '#(x y) (vector-append '#(x) '#(y))))

  (define ~check-srfi-133-020
    (check '#(a b c d) (vector-append '#(a) '#(b c d))))

  (define ~check-srfi-133-021
    (check '#(a #(b) #(c)) (vector-append '#(a #(b)) '#(#(c)))))

  (define ~check-srfi-133-022
    (check '#(a b c d) (vector-concatenate '(#(a b) #(c d)))))

  (define ~check-srfi-133-023
    (check '#(a b h i) (vector-append-subvectors '#(a b c d e) 0 2 '#(f g h i j) 2 4)))

  (define ~check-srfi-133-024
    (check #f (vector-empty? '#(a))))

  (define ~check-srfi-133-025
    (check #f (vector-empty? '#(()))))

  (define ~check-srfi-133-026
    (check #f (vector-empty? '#(#()))))

  (define ~check-srfi-133-027
    (check (vector-empty? '#())))

  (define ~check-srfi-133-028
    (check (vector= eq? '#(a b c d) '#(a b c d))))

  (define ~check-srfi-133-029
    (check #f (vector= eq? '#(a b c d) '#(a b d c))))

  (define ~check-srfi-133-030
    (check #f (vector= = '#(1 2 3 4 5) '#(1 2 3 4))))

  (define ~check-srfi-133-031
    (check #t (vector= = '#(+nan.0) '#(+nan.0))))

  (define ~check-srfi-133-032
    (check #t (let ((nan '+nan.0)) (vector= = (vector nan) (vector nan)))))

  (define ~check-srfi-133-033
    (check #t (let ((nanvec '#(+nan.0))) (vector= = nanvec nanvec))))

  (define ~check-srfi-133-034
    (check (vector= eq?)))

  (define ~check-srfi-133-035
    (check (vector= eq? '#(a))))

  (define ~check-srfi-133-036
    (check #f (vector= eq? (vector (vector 'a)) (vector (vector 'a)))))

  (define ~check-srfi-133-037
    (check (vector= equal? (vector (vector 'a)) (vector (vector 'a)))))

  (define vos '#("abc" "abcde" "abcd"))
  (define vec '#(0 1 2 3 4 5))
  (define vec2 (vector 0 1 2 3 4))
  (define vec3 (vector 1 2 3 4 5))
  (define result '())
  (define (sqr x) (* x x))

  (define ~check-srfi-133-038
    (check 5 (vector-fold (lambda (len str) (max (string-length str) len))
                          0 vos)))

  (define ~check-srfi-133-039
    (check '(5 4 3 2 1 0)
           (vector-fold (lambda (tail elt) (cons elt tail)) '() vec)))

  (define ~check-srfi-133-040
    (check 3 (vector-fold (lambda (ctr n) (if (even? n) (+ ctr 1) ctr)) 0 vec)))

  (define ~check-srfi-133-041
    (check '(a b c d) (vector-fold-right (lambda (tail elt) (cons elt tail))
                                         '() '#(a b c d))))

  (define ~check-srfi-133-042
    (check '#(1 4 9 16) (vector-map sqr '#(1 2 3 4))))

  (define ~check-srfi-133-043
    (check '#(5 8 9 8 5) (vector-map * '#(1 2 3 4 5) '#(5 4 3 2 1))))

  (define ~check-srfi-133-044
    (check '#(0 1 4 9 16) (begin
                            (vector-map! sqr vec2)
                            (vector-copy vec2))))

  (define ~check-srfi-133-045
    (check '#(0 2 12 36 80) (begin   (vector-map! * vec2 vec3) (vector-copy vec2))))

  (define ~check-srfi-133-046
    (check '(5 4 3 2 1 0) (begin
                            (vector-for-each (lambda (x) (set! result (cons x result))) vec)
                            (cons (car result) (cdr result)))))

  (define ~check-srfi-133-047
    (check 3 (vector-count even? '#(3 1 4 1 5 9 2 5 6))))

  (define ~check-srfi-133-048
    (check 2 (vector-count < '#(1 3 6 9) '#(2 4 6 8 10 12))))

  (define ~check-srfi-133-049
    (check '#(3 4 8 9 14 23 25 30 36) (vector-cumulate + '#(3 1 4 1 5 9 2 5 6) 0)))

  (define (cmp a b)
    (cond
     ((< a b) -1)
     ((= a b) 0)
     (else 1)))
  (define vbis '#(0 2 4 6 8 10 12))

  (define ~check-srfi-133-050
    (check 2 (vector-index even? '#(3 1 4 1 5 9 6))))

  (define ~check-srfi-133-051
    (check 1 (vector-index < '#(3 1 4 1 5 9 2 5 6) '#(2 7 1 8 2))))

  (define ~check-srfi-133-052
    (check #f (vector-index = '#(3 1 4 1 5 9 2 5 6) '#(2 7 1 8 2))))

  (define ~check-srfi-133-053
    (check 5 (vector-index-right odd? '#(3 1 4 1 5 9 6))))

  (define ~check-srfi-133-054
    (check 3 (vector-index-right < '#(3 1 4 1 5) '#(2 7 1 8 2))))

  (define ~check-srfi-133-055
    (check 2 (vector-skip number? '#(1 2 a b 3 4 c d))))

  (define ~check-srfi-133-056
    (check 2 (vector-skip = '#(1 2 3 4 5) '#(1 2 -3 4))))

  (define ~check-srfi-133-057
    (check 7 (vector-skip-right number? '#(1 2 a b 3 4 c d))))

  (define ~check-srfi-133-058
    (check 3 (vector-skip-right = '#(1 2 3 4 5) '#(1 2 -3 -4 5))))

  (define ~check-srfi-133-059
    (check 0 (vector-binary-search vbis 0 cmp)))

  (define ~check-srfi-133-060
    (check 3 (vector-binary-search vbis 6 cmp)))

  (define ~check-srfi-133-061
    (check #f (vector-binary-search vbis 1 cmp)))

  (define ~check-srfi-133-062
    (check (vector-any number? '#(1 2 x y z))))

  (define ~check-srfi-133-063
    (check (vector-any < '#(1 2 3 4 5) '#(2 1 3 4 5))))

  (define ~check-srfi-133-064
    (check #f (vector-any number? '#(a b c d e))))

  (define ~check-srfi-133-065
    (check #f (vector-any > '#(1 2 3 4 5) '#(1 2 3 4 5))))

  (define ~check-srfi-133-066
    (check #f (vector-every number? '#(1 2 x y z))))

  (define ~check-srfi-133-067
    (check (vector-every number? '#(1 2 3 4 5))))

  (define ~check-srfi-133-068
    (check #f (vector-every < '#(1 2 3) '#(2 3 3))))

  (define ~check-srfi-133-069
    (check (vector-every < '#(1 2 3) '#(2 3 4))))

  (define ~check-srfi-133-070
    (check 'yes (vector-any (lambda (x) (if (number? x) 'yes #f)) '#(1 2 x y z))))

  (define ~check-srfi-133-071
    (let-values (((new off) (vector-partition number? '#(1 x 2 y 3 z))))
      (check (and (equal? '#(1 2 3 x y z) (vector-copy new))
                  (equal? 3 (+ off 0))))))

  (define vs (vector 1 2 3))
  (define vf0 (vector 1 2 3))
  (define vf1 (vector 1 2 3))
  (define vf2 (vector 1 2 3))
  (define vr0 (vector 1 2 3))
  (define vr1 (vector 1 2 3))
  (define vr2 (vector 1 2 3))
  (define vc0 (vector 1 2 3 4 5))
  (define vc1 (vector 1 2 3 4 5))
  (define vc2 (vector 1 2 3 4 5))
  (define vrc0 (vector 1 2 3 4 5))
  (define vrc1 (vector 1 2 3 4 5))
  (define vrc2 (vector 1 2 3 4 5))
  (define vu0 (vector 1 2 3 4 5))
  (define vu1 (vector 1 2 3 4 5))
  (define vu2 (vector 1 2 3 4 5))
  (define vur0 (vector 1 2 3 4 5))
  (define vur1 (vector 1 2 3 4 5))
  (define vur2 (vector 1 2 3 4 5))

  (define ~check-srfi-133-072
    (check '#(2 1 3) (begin   (vector-swap! vs 0 1)
                              (vector-copy vs))))

  (define ~check-srfi-133-073
    (check '#(0 0 0) (begin (vector-fill! vf0 0) (vector-copy vf0))))

  (define ~check-srfi-133-074
    (check '#(1 0 0) (begin     (vector-fill! vf1 0 1)
                                (vector-copy vf1))))

  (define ~check-srfi-133-075
    (check '#(0 2 3) (begin   (vector-fill! vf2 0 0 1)
                              (vector-copy vf2))))

  (define ~check-srfi-133-076
    (check '#(3 2 1) (begin   (vector-reverse! vr0)
                              (vector-copy vr0))))

  (define ~check-srfi-133-077
    (check '#(1 3 2) (begin   (vector-reverse! vr1 1)
                              (vector-copy vr1))))

  (define ~check-srfi-133-078
    (check '#(2 1 3) (begin   (vector-reverse! vr2 0 2)
                              (vector-copy vr2))))

  (define ~check-srfi-133-079
    (check '#(1 10 20 30 5) (begin   (vector-copy! vc0 1 '#(10 20 30))
                                     (vector-copy vc0))))

  (define ~check-srfi-133-080
    (check '#(1 10 20 30 40)
           (begin
             (vector-copy! vc1 1 '#(0 10 20 30 40) 1)
             (vector-copy vc1))))

  (define ~check-srfi-133-081
    (check '#(1 10 20 30 5)
           (begin
             (vector-copy! vc2 1 '#(0 10 20 30 40) 1 4)
             (vector-copy vc2))))

  (define ~check-srfi-133-082
    (check '#(1 30 20 10 5)
           (begin
               (vector-reverse-copy! vrc0 1 '#(10 20 30))
               (vector-copy vrc0))))

  (define ~check-srfi-133-083
    (check '#(1 40 30 20 10)
           (begin
             (vector-reverse-copy! vrc1 1 '#(0 10 20 30 40) 1)
             (vector-copy vrc1))))

  (define ~check-srfi-133-084
    (check '#(1 30 20 10 5)
           (begin
             (vector-reverse-copy! vrc2 1 '#(0 10 20 30 40) 1 4)
             (vector-copy vrc2))))

  (define ~check-srfi-133-085
    (check '#(1 11 12 13 5)
           (begin
             (vector-unfold! (lambda (i) (+ 10 i)) vu0 1 4)
             (vector-copy vu0))))

  (define ~check-srfi-133-086
    (check '#(1 1 3 5 5)
           (begin
             (vector-unfold! (lambda (i x) (values (+ i x) (+ x 1))) vu1 1 4 0)
             (vector-copy vu1))))

  (define ~check-srfi-133-087
    (check '#(1 1 4 7 5)
           (begin
             (vector-unfold! (lambda (i x y) (values (+ i x y) (+ x 1) (+ x 1))) vu2 1 4 0 0)
             (vector-copy vu2))))

  (define ~check-srfi-133-088
    (check '#(1 11 12 13 5)
           (begin
             (vector-unfold-right! (lambda (i) (+ 10 i)) vur0 1 4)
             (vector-copy vur0))))

  (define ~check-srfi-133-089
    (check '#(1 3 3 3 5)
           (begin
             (vector-unfold-right! (lambda (i x) (values (+ i x) (+ x 1))) vur1 1 4 0)
             (vector-copy vur1))))

  (define ~check-srfi-133-090
    (check '#(1 5 4 3 5)
           (begin
             (vector-unfold-right! (lambda (i x y) (values (+ i x y) (+ x 1) (+ x 1))) vur2 1 4 0 0)
             (vector-copy vur2))))

  (define ~check-srfi-133-091
    (check '(1 2 3) (vector->list '#(1 2 3))))

  (define ~check-srfi-133-092
    (check '(2 3) (vector->list '#(1 2 3) 1)))

  (define ~check-srfi-133-093
    (check '(1 2) (vector->list '#(1 2 3) 0 2)))

  (define ~check-srfi-133-094
    (check '#(1 2 3) (list->vector '(1 2 3))))

  (define ~check-srfi-133-095
    (check '(3 2 1) (reverse-vector->list '#(1 2 3))))

  (define ~check-srfi-133-096
    (check '(3 2) (reverse-vector->list '#(1 2 3) 1)))

  (define ~check-srfi-133-097
    (check '(2 1) (reverse-vector->list '#(1 2 3) 0 2)))

  (define ~check-srfi-133-098
    (check '#(3 2 1) (reverse-list->vector '(1 2 3))))

  (define ~check-srfi-133-099
    (check "abc" (vector->string '#(#\a #\b #\c))))

  (define ~check-srfi-133-100
    (check "bc" (vector->string '#(#\a #\b #\c) 1)))

  (define ~check-srfi-133-101
    (check "ab" (vector->string '#(#\a #\b #\c) 0 2)))

  (define ~check-srfi-133-102
    (check '#(#\a #\b #\c) (string->vector "abc")))

  (define ~check-srfi-133-103
    (check '#(#\b #\c) (string->vector "abc" 1)))

  (define ~check-srfi-133-104
    (check '#(#\a #\b) (string->vector "abc" 0 2))))

(library (srfi srfi-127-check)

  (export ~check-srfi-127-001 ~check-srfi-127-002 ~check-srfi-127-003 ~check-srfi-127-004 ~check-srfi-127-005 ~check-srfi-127-006
~check-srfi-127-007 ~check-srfi-127-008 ~check-srfi-127-009 ~check-srfi-127-010 ~check-srfi-127-011 ~check-srfi-127-012 ~check-srfi-127-013
~check-srfi-127-014 ~check-srfi-127-015 ~check-srfi-127-016 ~check-srfi-127-017 ~check-srfi-127-018 ~check-srfi-127-019 ~check-srfi-127-020
~check-srfi-127-021 ~check-srfi-127-022 ~check-srfi-127-023 ~check-srfi-127-024 ~check-srfi-127-025 ~check-srfi-127-026 ~check-srfi-127-027
~check-srfi-127-028 ~check-srfi-127-029 ~check-srfi-127-030 ~check-srfi-127-031 ~check-srfi-127-032 ~check-srfi-127-033 ~check-srfi-127-034
~check-srfi-127-035 ~check-srfi-127-036 ~check-srfi-127-037 ~check-srfi-127-038 ~check-srfi-127-039 ~check-srfi-127-040 ~check-srfi-127-041
~check-srfi-127-042 ~check-srfi-127-043 ~check-srfi-127-044 ~check-srfi-127-045 ~check-srfi-127-046 ~check-srfi-127-047 ~check-srfi-127-048
~check-srfi-127-049 ~check-srfi-127-050 ~check-srfi-127-051 ~check-srfi-127-052 ~check-srfi-127-053 ~check-srfi-127-054 ~check-srfi-127-055
~check-srfi-127-056 ~check-srfi-127-057 ~check-srfi-127-058 ~check-srfi-127-059 ~check-srfi-127-060 ~check-srfi-127-061 ~check-srfi-127-062
~check-srfi-127-063 ~check-srfi-127-064 ~check-srfi-127-065 ~check-srfi-127-066 ~check-srfi-127-068 ~check-srfi-127-069 ~check-srfi-127-070
~check-srfi-127-071 ~check-srfi-127-072 ~check-srfi-127-073 ~check-srfi-127-074 ~check-srfi-127-075 ~check-srfi-127-076 ~check-srfi-127-077
~check-srfi-127-078 ~check-srfi-127-079 ~check-srfi-127-080 ~check-srfi-127-081 ~check-srfi-127-082 ~check-srfi-127-083 ~check-srfi-127-084
~check-srfi-127-085 ~check-srfi-127-086 ~check-srfi-127-087 ~check-srfi-127-088 ~check-srfi-127-089 ~check-srfi-127-090 ~check-srfi-127-091
~check-srfi-127-092 ~check-srfi-127-093 ~check-srfi-127-094 ~check-srfi-127-095 ~check-srfi-127-096 ~check-srfi-127-097 ~check-srfi-127-098
~check-srfi-127-099 ~check-srfi-127-100 ~check-srfi-127-101 ~check-srfi-127-102 ~check-srfi-127-103 ~check-srfi-127-104 ~check-srfi-127-105
~check-srfi-127-106 ~check-srfi-127-107 ~check-srfi-127-108 ~check-srfi-127-109 ~check-srfi-127-110)

  (import (scheme base)
          (srfi srfi-127)
          (letloop check))

  ;; Make-generator for tests cloned from SRFI 121
  (define (make-generator . args)
    (lambda () (if (null? args)
                   (eof-object)
                   (let ((next (car args)))
                     (set! args (cdr args))
                     next))))

  ;; Make-lseq creates an lseq, like list, but guarantees the use of a generator
  (define (make-lseq . args) (generator->lseq (apply make-generator args)))

  (define one23 (make-lseq 1 2 3))

  (define ~check-srfi-127-001
    (check 1 (car one23)))

  (define ~check-srfi-127-002
    (check (procedure? (cdr one23))))

  (define ~check-srfi-127-003
    (check '(1 2 3) (lseq-realize one23)))

  (define ~check-srfi-127-004
    (check (lseq? '())))

  (define ~check-srfi-127-005
    (check (lseq? '(1 2 3))))

  (define ~check-srfi-127-006
    (check (lseq? (make-lseq 1 2 3))))

  (define ~check-srfi-127-007
    (check (lseq? (cons 'x (lambda () 'x)))))

  (define ~check-srfi-127-008
    (check (lseq=? = '() '())))

  (define ~check-srfi-127-009
    (check (lseq=? = '(1 2 3) '(1 2 3))))

  (define ~check-srfi-127-010
    (check (lseq=? = (make-lseq 1 2 3)
                   (make-lseq 1 2 3))))

  (define ~check-srfi-127-011
    (check (lseq=? = (make-lseq 1 2 3) '(1 2 3))))

  (define ~check-srfi-127-012
    (~check-srfi-127-raise (lseq-car (make-generator))))

  (define ~check-srfi-127-013
    (check 1 (lseq-car (make-lseq 1 2 3))))

  (define ~check-srfi-127-014
    (check 1 (lseq-car '(1 2 3))))

  (define ~check-srfi-127-015
    (~check-srfi-127-raise (lseq-car 2)))

  (define ~check-srfi-127-016
    (~check-srfi-127-raise (lseq-first (make-generator))))

  (define ~check-srfi-127-017
    (check 1 (lseq-first (make-lseq 1 2 3))))

  (define ~check-srfi-127-018
    (check 1 (lseq-first '(1 2 3))))

  (define ~check-srfi-127-019
    (~check-srfi-127-raise (lseq-first 2)))

  (define ~check-srfi-127-020
    (~check-srfi-127-raise (lseq-cdr (make-generator))))

  (define ~check-srfi-127-021
    (check 2 (lseq-cdr '(1 . 2))))

  (define ~check-srfi-127-022
    (check 2 (lseq-car (lseq-cdr '(1 2 3)))))

  (define ~check-srfi-127-023
    (check 2 (lseq-car (lseq-cdr (make-lseq 1 2 3)))))

  (define ~check-srfi-127-024
    (~check-srfi-127-raise (lseq-rest (make-generator))))

  (define ~check-srfi-127-025
    (check 2 (lseq-rest '(1 . 2))))

  (define ~check-srfi-127-026
    (check 2 (lseq-car (lseq-rest '(1 2 3)))))

  (define ~check-srfi-127-027
    (check 2 (lseq-car (lseq-rest (make-lseq 1 2 3)))))

  (define ~check-srfi-127-028
    (~check-srfi-127-raise (lseq-rest 2)))

  (define ~check-srfi-127-029
    (~check-srfi-127-raise (lseq-ref '() 0)))

  (define ~check-srfi-127-030
    (check 1 (lseq-ref '(1) 0)))

  (define ~check-srfi-127-031
    (check 2 (lseq-ref '(1 2) 1)))

  (define ~check-srfi-127-032
    (~check-srfi-127-raise (lseq-ref (make-lseq) 0)))

  (define ~check-srfi-127-033
    (check 1 (lseq-ref (make-lseq 1) 0)))

  (define ~check-srfi-127-034
    (check 1 (lseq-ref (make-lseq 1 2) 0)))

  (define ~check-srfi-127-035
    (check 2 (lseq-ref (make-lseq 1 2) 1)))

  (define ~check-srfi-127-036
    (~check-srfi-127-raise (lseq-take '() 1)))

  (define ~check-srfi-127-037
    (~check-srfi-127-raise (lseq-take (make-lseq) 1)))

  (define ~check-srfi-127-038
     ; test laziness
    (check (procedure? (cdr (lseq-take '(1 2 3 4 5) 3)))))

  (define ~check-srfi-127-039
    (check '(1 2 3) (lseq-realize (lseq-take '(1 2 3 4 5) 3))))

  (define ~check-srfi-127-040
    (~check-srfi-127-raise (lseq-drop '() 1)))

  (define ~check-srfi-127-041
    (~check-srfi-127-raise (lseq-drop (make-lseq 1) 2)))

  (define ~check-srfi-127-042
    (check '(3 4 5) (lseq-realize (lseq-drop '(1 2 3 4 5) 2))))

  (define ~check-srfi-127-043
    (check '(3 4 5) (lseq-realize (lseq-drop (make-lseq 1 2 3 4 5) 2))))

  (define ~check-srfi-127-044
    (check '() (lseq-realize '())))

  (define ~check-srfi-127-045
    (check '(1 2 3) (lseq-realize '(1 2 3))))

  (define ~check-srfi-127-046
    (check '() (lseq-realize (make-lseq))))

  (define ~check-srfi-127-047
    (check '(1 2 3) (lseq-realize (make-lseq 1 2 3))))

  (define g (lseq->generator '(1 2 3)))

  (define ~check-srfi-127-048 (check 1 (g)))

  (define ~check-srfi-127-049 (check 2 (g)))

  (define ~check-srfi-127-050 (check 3 (g)))
  (define ~check-srfi-127-051 (check (eof-object? (g))))

  (define g1 (lseq->generator (make-lseq 1 2 3)))

  (define ~check-srfi-127-052
    (check 1 (g1)))

  (define ~check-srfi-127-053
    (check 2 (g1)))

  (define ~check-srfi-127-054
    (check 3 (g1)))

  (define ~check-srfi-127-055
    (check (eof-object? (g))))

  (define ~check-srfi-127-056
    (check 0 (lseq-length '())))

  (define ~check-srfi-127-057
    (check 3 (lseq-length '(1 2 3))))

  (define ~check-srfi-127-058
    (check 3 (lseq-length (make-lseq 1 2 3))))

  (define ~check-srfi-127-059
    (check '(1 2 3 a b c) (lseq-realize (lseq-append '(1 2 3) '(a b c)))))

  (define one23abc (lseq-append (make-lseq 1 2 3) (make-lseq 'a 'b 'c)))

  (define ~check-srfi-127-060
    (check (procedure? (cdr one23abc))))

  (define ~check-srfi-127-061
    (check (lseq-realize one23abc)))

  (define one2345 (make-lseq 1 2 3 4 5))
  (define oddeven (make-lseq 'odd 'even 'odd 'even 'odd 'even 'odd 'even))

  (define ~check-srfi-127-062
    (check '((one 1 odd) (two 2 even) (three 3 odd))
           (lseq-realize (lseq-zip '(one two three) one2345 oddeven))))

  (define ~check-srfi-127-063
    (check '() (lseq-map - '())))

  (define ~check-srfi-127-064
    (check '(-1 -2 -3) (lseq-realize (lseq-map - '(1 2 3)))))

  (define ~check-srfi-127-065
    (check '(-1 -2 -3) (lseq-realize (lseq-map - (make-lseq 1 2 3)))))

  (define ~check-srfi-127-066
    (check (procedure? (cdr (lseq-map - '(1 2 3))))))

  (define output '())
  (define out! (lambda (x) (set! output (cons x output))))

  (define ~check-srfi-127-068
    (check output (begin (lseq-for-each out! '()) '())))

  (define ~check-srfi-127-069
    (check output (begin (lseq-for-each out! '(a b c)) '(c b a))))

  (define ~check-srfi-127-070
    (check output (begin (lseq-for-each out! (make-lseq 1 2 3)) '(3 2 1 c b a))))

  (define ~check-srfi-127-071
    (check '() (lseq-filter odd? '())))

  (define odds (lseq-filter odd? '(1 2 3 4 5)))

  (define ~check-srfi-127-072
    (check (procedure? (cdr odds))))

  (define ~check-srfi-127-073
    (check '(1 3 5) (lseq-realize odds)))

  (define ~check-srfi-127-074
    (check '(1 3 5) (lseq-realize (lseq-filter odd? (make-lseq 1 2 3 4 5)))))

  (define ~check-srfi-127-075
    (check '() (lseq-remove even? '())))

  (define odds1 (lseq-remove even? '(1 2 3 4 5)))

  (define ~check-srfi-127-076
    (check (procedure? (cdr odds1))))

  (define ~check-srfi-127-077
    (check '(1 3 5) (lseq-realize odds1)))

  (define ~check-srfi-127-078
    (check '(1 3 5) (lseq-realize (lseq-remove even? (make-lseq 1 2 3 4 5)))))

  (define ~check-srfi-127-079
    (check 4 (lseq-find even? '(3 1 4 1 5 9 2 6))))

  (define ~check-srfi-127-080
    (check 4 (lseq-find even? (make-lseq 3 1 4 1 5 9 2 6))))

  (define ~check-srfi-127-081
    (check #f (lseq-find negative? (make-lseq 1 2 3 4 5))))

  (define ~check-srfi-127-082
    (check '(-8 -5 0 0) (lseq-realize (lseq-find-tail even? '(3 1 37 -8 -5 0 0)))))

  (define ~check-srfi-127-083
    (check '(-8 -5 0 0) (lseq-realize (lseq-find-tail even?
                                                      (make-lseq 3 1 37 -8 -5 0 0)))))

  (define ~check-srfi-127-084
    (check #f (lseq-find-tail even? '())))

  (define ~check-srfi-127-085
    (check #f (lseq-find-tail negative? (make-lseq 1 2 3 4 5))))

  (define ~check-srfi-127-086
    (check '(2 18) (lseq-realize (lseq-take-while even? '(2 18 3 10 22 9)))))

  (define ~check-srfi-127-087
    (check '(2 18) (lseq-realize (lseq-take-while even?
                                                  (make-lseq 2 18 3 10 22 9)))))

  (define ~check-srfi-127-088
    (check '(2 18) (lseq-realize (lseq-take-while even?
                                                  (make-lseq 2 18 3 10 22 9)))))

  (define ~check-srfi-127-089
    (check '(3 10 22 9) (lseq-drop-while even? '(2 18 3 10 22 9))))

  (define ~check-srfi-127-090
    (check '(3 10 22 9) (lseq-realize (lseq-drop-while even?
                                                       (make-lseq 2 18 3 10 22 9)))))

  (define ~check-srfi-127-091
    (check #t (lseq-any integer? '(a 3 b 2.7))))

  (define ~check-srfi-127-092
    (check #t (lseq-any integer? (make-lseq 'a 3 'b 2.7))))

  (define ~check-srfi-127-093
    (check #f (lseq-any integer? '(a 3.1 b 2.7))))

  (define ~check-srfi-127-094
    (check #f (lseq-any integer? (make-lseq 'a 3.1 'b 2.7))))

  (define ~check-srfi-127-095
    (check #t (lseq-any < '(3 1 4 1 5) '(2 7 1 8 2))))

  (define (factorial n)
    (cond
     ((< n 0) #f)
     ((= n 0) 1)
     (else (* n (factorial (- n 1))))))

  (define ~check-srfi-127-096
    (check 6 (lseq-any factorial '(-1 -2 3 4))))

  (define ~check-srfi-127-097
    (check 6 (lseq-any factorial (make-lseq -1 -2 3 4))))

  (define ~check-srfi-127-098
    (check 24 (lseq-every factorial '(1 2 3 4))))

  (define ~check-srfi-127-099
    (check 24 (lseq-every factorial (make-lseq 1 2 3 4))))

  (define ~check-srfi-127-100
    (check 2 (lseq-index even? '(3 1 4 1 5 9))))

  (define ~check-srfi-127-101
    (check 1 (lseq-index < '(3 1 4 1 5 9 2 5 6) '(2 7 1 8 2))))

  (define ~check-srfi-127-102
    (check #f (lseq-index = '(3 1 4 1 5 9 2 5 6) '(2 7 1 8 2))))

  (define ~check-srfi-127-103
    (check '(a b c) (lseq-realize (lseq-memq 'a '(a b c)))))

  (define ~check-srfi-127-104
    (check '(a b c) (lseq-realize (lseq-memq 'a (make-lseq 'a 'b 'c)))))

  (define ~check-srfi-127-105
    (check #f (lseq-memq 'a (make-lseq 'b 'c 'd))))

  (define ~check-srfi-127-106
    (check #f (lseq-memq (list 'a) '(b c d))))

  (define ~check-srfi-127-107
    (check #f (lseq-memq (list 'a) (make-lseq 'b 'c 'd))))

  (define ~check-srfi-127-108
    (check '(101 102) (lseq-realize (lseq-memv 101 (make-lseq 100 101 102)))))

  (define ~check-srfi-127-109
    (check '((a) c) (lseq-realize (lseq-member (list 'a) (make-lseq 'b '(a) 'c)))))

  (define ~check-srfi-127-110
    (check '(2 3) (lseq-realize (lseq-member 2.0 (make-lseq 1 2 3) =)))))

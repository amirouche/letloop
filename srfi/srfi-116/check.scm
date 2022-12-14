(library (srfi srfi-116 check)

  (export check-000 check-001 check-002 check-003 check-004 check-005
check-006 check-007 check-008 check-009 check-010 check-011 check-012
check-013 check-014 check-015 check-016 check-017 check-018 check-019
check-020 check-021 check-022 check-023 check-024 check-025 check-026
check-027 check-028 check-029 check-030 check-031 check-032 check-033
check-034 check-035 check-036 check-037 check-038 check-039 check-040
check-041 check-042 check-043 check-044 check-045 check-046 check-047
check-048 check-049 check-050 check-051 check-052 check-053 check-054
check-055 check-056 check-057 check-058 check-059 check-060 check-061
check-062 check-063 check-064 check-065 check-066 check-067 check-068
check-069 check-070 check-071 check-072 check-073 check-074 check-075
check-076 check-077 check-078 check-079 check-080 check-081 check-082
check-083 check-084 check-085 check-086 check-087 check-088 check-089
check-090 check-091 check-092 check-093 check-094 check-095 check-096
check-097 check-098 check-099 check-100 check-101 check-102 check-103
check-104 check-105 check-106 check-107 check-108 check-109 check-110
check-111 check-112 check-113 check-114 check-115 check-116 check-117
check-118 check-119 check-120 check-121 check-122 check-123 check-124
check-125 check-126 check-127 check-128 check-129 check-130 check-131
check-132 check-133 check-134 check-135 check-136 check-137 #;check-138
#;check-139 check-140 check-141 check-142 #;check-143 check-144 check-145
check-146 check-147 check-148 check-149 check-150 check-151 check-152
check-153 check-154 #;check-155 #;check-156 check-157 check-158 check-159
check-160 check-161 check-162 check-163 check-164 check-165 check-166
check-167 check-168 check-169 check-170 check-171 check-172 check-173
check-174 check-175 check-176 check-177 check-178 check-179 check-180
check-181 check-182 check-183 check-184 check-185 check-186 check-187
check-188 check-189 check-190 check-191 check-192 check-193 check-194
check-195 check-196 check-197 check-198)
  (import (scheme base)
          (srfi srfi-116)
          (check))

  (begin

    (define abc (ilist 'a 'b 'c))

    (define check-000
      (check 'a (icar abc)))

    (define check-001
      (check 'b (icadr abc)))

    (define check-002
      (check 'c (icaddr abc)))

    (define check-003
      (check ilist= (ipair 2 1) (xipair 1 2)))

    (define abc-dot-d (ipair* 'a 'b 'c 'd))

    (define check-004
      (check 'd (icdddr abc-dot-d)))

    (define check-005
      (check ilist= (iq c c c c) (make-ilist 4 'c)))

    (define check-006
      (check ilist= (iq 0 1 2 3) (ilist-tabulate 4 values)))

    (define check-007
      (check ilist= (iq 0 1 2 3 4) (iiota 5)))

    (define abc-copy (ilist-copy abc))

    (define check-008
      (check ilist= abc abc-copy))

    (define check-009
      (check (not (eq? abc abc-copy))))

    (define check-010
      (check (ipair? (ipair 1 2))))

    (define check-011
      (check (proper-ilist? '())))

    (define check-012
      (check (proper-ilist? (iq 1 2 3))))

    (define check-013
      (check (ilist? '())))

    (define check-014
      (check (ilist? (iq 1 2 3))))

    (define check-015
      (check (dotted-ilist? (ipair 1 2))))

    (define check-016
      (check (dotted-ilist? 2)))

    (define check-017
      (check (null-ilist? '())))

    (define check-018
      (check (not (null-ilist? (iq 1 2 3)))))

    (define check-019
      (check-raise (null-ilist? 'a)))

    (define check-020
      (check (not-ipair? 'a)))

    (define check-021
      (check (not (not-ipair? (ipair 'a 'b)))))

    (define check-022
      (check (ilist= = (iq 1 2 3) (iq 1 2 3))))

    (define check-023
      (check (ilist= = (iq 1 2 3) (iq 1 2 3) (iq 1 2 3))))

    (define check-024
      (check (not (ilist= = (iq 1 2 3 4) (iq 1 2 3)))))

    (define check-025
      (check (not (ilist= = (iq 1 2 3) (iq 1 2 3 4)))))

    (define check-026
      (check (ilist= = (iq 1 2 3) (iq 1 2 3))))

    (define check-027
      (check (not (ilist= = (iq 1 2 3) (iq 1 2 3 4) (iq 1 2 3 4)))))

    (define check-028
      (check (not (ilist= = (iq 1 2 3) (iq 1 2 3) (iq 1 2 3 4)))))

    (define ab (ipair 'a 'b))
    (define cd (ipair 'c 'd))
    (define ef (ipair 'e 'f))
    (define gh (ipair 'g 'h))
    (define abcd (ipair ab cd))
    (define efgh (ipair ef gh))
    (define abcdefgh (ipair abcd efgh))
    (define ij (ipair 'i 'j))
    (define kl (ipair 'k 'l))
    (define mn (ipair 'm 'n))
    (define op (ipair 'o 'p))
    (define ijkl (ipair ij kl))
    (define mnop (ipair mn op))
    (define ijklmnop (ipair ijkl mnop))
    (define abcdefghijklmnop (ipair abcdefgh ijklmnop))

    (define check-029
      (check 'a (icaar abcd)))

    (define check-030
      (check 'b (icdar abcd)))

    (define check-031
      (check 'c (icadr abcd)))

    (define check-032
      (check 'd (icddr abcd)))

    (define check-033
      (check 'a (icaaar abcdefgh)))

    (define check-034
      (check 'b (icdaar abcdefgh)))

    (define check-035
      (check 'c (icadar abcdefgh)))

    (define check-036
      (check 'd (icddar abcdefgh)))

    (define check-037
      (check 'e (icaadr abcdefgh)))

    (define check-038
      (check 'f (icdadr abcdefgh)))

    (define check-039
      (check 'g (icaddr abcdefgh)))

    (define check-040
      (check 'h (icdddr abcdefgh)))

    (define check-041
      (check 'a (icaaaar abcdefghijklmnop)))

    (define check-042
      (check 'b (icdaaar abcdefghijklmnop)))

    (define check-043
      (check 'c (icadaar abcdefghijklmnop)))

    (define check-044
      (check 'd (icddaar abcdefghijklmnop)))

    (define check-045
      (check 'e (icaadar abcdefghijklmnop)))

    (define check-046
      (check 'f (icdadar abcdefghijklmnop)))

    (define check-047
      (check 'g (icaddar abcdefghijklmnop)))

    (define check-048
      (check 'h (icdddar abcdefghijklmnop)))

    (define check-049
      (check 'i (icaaadr abcdefghijklmnop)))

    (define check-050
      (check 'j (icdaadr abcdefghijklmnop)))

    (define check-051
      (check 'k (icadadr abcdefghijklmnop)))

    (define check-052
      (check 'l (icddadr abcdefghijklmnop)))

    (define check-053
      (check 'm (icaaddr abcdefghijklmnop)))

    (define check-054
      (check 'n (icdaddr abcdefghijklmnop)))

    (define check-055
      (check 'o (icadddr abcdefghijklmnop)))

    (define check-056
      (check 'p (icddddr abcdefghijklmnop)))

    (define check-057
      (check 'c (ilist-ref (iq a b c d) 2)))

    (define ten (ilist 1 2 3 4 5 6 7 8 9 10))

    (define check-058
      (check 1 (ifirst ten)))

    (define check-059
      (check 2 (isecond ten)))

    (define check-060
      (check 3 (ithird ten)))

    (define check-061
      (check 4 (ifourth ten)))

    (define check-062
      (check 5 (ififth ten)))

    (define check-063
      (check 6 (isixth ten)))

    (define check-064
      (check 7 (iseventh ten)))

    (define check-065
      (check 8 (ieighth ten)))

    (define check-066
      (check 9 (ininth ten)))

    (define check-067
      (check 10 (itenth ten)))

    (define check-068
      (check-raise (ilist-ref '() 2)))

    (define check-069
      (check '(1 2) (call-with-values (lambda () (icar+icdr (ipair 1 2))) list)))

    (define abcde (iq a b c d e))

    (define dotted (ipair 1 (ipair 2 (ipair 3 'd))))

    (define check-070
      (check ilist= (iq a b) (itake abcde 2)))

    (define check-071
      (check ilist= (iq c d e) (idrop abcde 2)))

    (define check-072
      (check ilist= (iq c d e) (ilist-tail abcde 2)))

    (define check-073
      (check ilist= (iq 1 2) (itake dotted 2)))

    (define check-074
      (check ilist= (ipair 3 'd) (idrop dotted 2)))

    (define check-075
      (check ilist= (ipair 3 'd) (ilist-tail dotted 2)))

    (define check-076
      (check 'd (idrop dotted 3)))

    (define check-077
      (check 'd (ilist-tail dotted 3)))

    (define check-078
      (check ilist= abcde (iappend (itake abcde 4) (idrop abcde 4))))

    (define check-079
      (check ilist= (iq d e) (itake-right abcde 2)))

    (define check-080
      (check ilist= (iq a b c) (idrop-right abcde 2)))

    (define check-081
      (check ilist= (ipair 2 (ipair 3 'd)) (itake-right dotted 2)))

    (define check-082
      (check ilist= (iq 1) (idrop-right dotted 2)))

    (define check-083
      (check 'd (itake-right dotted 0)))

    (define check-084
      (check ilist= (iq 1 2 3) (idrop-right dotted 0)))

    (define check-085
      (check ilist= abcde (call-with-values (lambda () (isplit-at abcde 3)) iappend)))

    (define check-086
      (check 'c (ilast (iq a b c))))

    (define check-087
      (check ilist= (iq c) (last-ipair (iq a b c))))

    (define check-088
      (check 0 (ilength '())))

    (define check-089
      (check 3 (ilength (iq 1 2 3))))

    (define check-090
      (check ilist= (iq x y) (iappend (iq x) (iq y))))

    (define check-091
      (check ilist= (iq a b c d) (iappend (iq a b) (iq c d))))

    (define check-092
      (check ilist= (iq a) (iappend '() (iq a))))

    (define check-093
      (check ilist= (iq x y) (iappend (iq x y))))

    (define check-094
      (check '() (iappend)))

    (define check-095
      (check ilist= (iq a b c d) (iconcatenate (iq (a b) (c d)))))

    (define check-096
      (check ilist= (iq c b a) (ireverse (iq a b c))))

    (define check-097
      (check ilist= (iq (e (f)) d (b c) a) (ireverse (iq a (b c) d (e (f))))))

    (define check-098
      (check ilist= (ipair 2 (ipair 1 'd)) (iappend-reverse (iq 1 2) 'd)))

    (define check-099
      (check ilist=
             (iq (one 1 odd) (two 2 even) (three 3 odd))
             (izip (iq one two three) (iq 1 2 3) (iq odd even odd))))

    (define check-100
      (check ilist= (iq (1) (2) (3)) (izip (iq 1 2 3))))

    (define check-101
      (check ilist= (iq 1 2 3) (iunzip1 (iq (1) (2) (3)))))

    (define check-102
      (check ilist= (iq (1 2 3) (one two three))
             (call-with-values
                 (lambda () (iunzip2 (iq (1 one) (2 two) (3 three))))
               ilist)))

    (define check-103
      (check ilist= (iq (1 2 3) (one two three) (a b c))
             (call-with-values
                 (lambda () (iunzip3 (iq (1 one a) (2 two b) (3 three c))))
               ilist)))

    (define check-104
      (check ilist= (iq (1 2 3) (one two three) (a b c) (4 5 6))
             (call-with-values
                 (lambda () (iunzip4 (iq (1 one a 4) (2 two b 5) (3 three c 6))))
               ilist)))

    (define check-105
      (check ilist= (iq (1 2 3) (one two three) (a b c) (4 5 6) (#t #f #t))
             (call-with-values
                 (lambda () (iunzip5 (iq (1 one a 4 #t) (2 two b 5 #f) (3 three c 6 #t))))
               ilist)))

    (define check-106
      (check 3 (icount even? (iq 3 1 4 1 5 9 2 5 6))))

    (define check-107
      (check 3 (icount < (iq 1 2 4 8) (iq 2 4 6 8 10 12 14 16))))

    ;; We have to be careful to test both single-list and multiple-list
    ;; code paths, as they are different in this implementation.

    (define lis (iq 1 2 3))

    (define check-108
      (check 6 (ifold + 0 lis)))

    (define check-109
      (check ilist= (iq 3 2 1) (ifold ipair '() lis)))

    (define check-110
      (check 2 (ifold
                (lambda (x count) (if (symbol? x) (+ count 1) count))
                0
                (iq a 0 b))))

    (define check-111
      (check 4 (ifold
                (lambda (s max-len) (max max-len (string-length s)))
                0
                (iq "ab" "abcd" "abc"))))

    (define check-112
      (check 32 (ifold
                 (lambda (a b ans) (+ (* a b) ans))
                 0
                 (iq 1 2 3)
                 (iq 4 5 6))))

    (define (z x y ans) (ipair (ilist x y) ans))

    (define check-113
      (check ilist= (iq (b d) (a c))
             (ifold z '() (iq a b) (iq c d))))

    (define check-114
      (check ilist= lis (ifold-right ipair '() lis)))

    (define check-115
      (check ilist= (iq 0 2 4) (ifold-right
                         (lambda (x l) (if (even? x) (ipair x l) l))
                         '()
                         (iq 0 1 2 3 4))))

    (define check-116
      (check ilist= (iq (a c) (b d))
             (ifold-right z '() (iq a b) (iq c d))))

    (define check-117
      (check ilist= (iq (c) (b c) (a b c))
             (ipair-fold ipair '() (iq a b c))))

    (define check-118
      (check ilist= (iq ((b) (d)) ((a b) (c d)))
             (ipair-fold z '() (iq a b) (iq c d))))

    (define check-119
      (check ilist= (iq (a b c) (b c) (c))
             (ipair-fold-right ipair '() (iq a b c))))

    (define check-120
      (check ilist= (iq ((a b) (c d)) ((b) (d)))
             (ipair-fold-right z '() (iq a b) (iq c d))))

    (define check-121
      (check 5 (ireduce max 0 (iq 1 3 5 4 2 0))))

    (define check-122
      (check 1 (ireduce - 0 (iq 1 2))))

    (define check-123
      (check -1 (ireduce-right - 0 (iq 1 2))))

    (define squares (iq 1 4 9 16 25 36 49 64 81 100))

    (define check-124
      (check ilist= squares
             (iunfold (lambda (x) (> x 10))
                      (lambda (x) (* x x))
                      (lambda (x) (+ x 1))
                      1)))

    (define check-125
      (check ilist= squares
             (iunfold-right zero?
                            (lambda (x) (* x x))
                            (lambda (x) (- x 1))
                            10)))

    (define check-126
      (check ilist= (iq 1 2 3) (iunfold null-ilist? icar icdr (iq 1 2 3))))

    (define check-127
      (check ilist= (iq 3 2 1) (iunfold-right null-ilist? icar icdr (iq 1 2 3))))

    (define check-128
      (check ilist= (iq 1 2 3 4)
             (iunfold null-ilist? icar icdr (iq 1 2) (lambda (x) (iq 3 4)))))

    (define check-129
      (check ilist= (iq b e h) (imap icadr (iq (a b) (d e) (g h)))))

    (define check-130
      (check ilist= (iq b e h) (imap-in-order icadr (iq (a b) (d e) (g h)))))

    (define check-131
      (check ilist= (iq 5 7 9) (imap + (iq 1 2 3) (iq 4 5 6))))

    (define check-132
      (check ilist= (iq 5 7 9) (imap-in-order + (iq 1 2 3) (iq 4 5 6))))

    (define z1 (let ((count 0)) (lambda (ignored) (set! count (+ count 1)) count)))

    (define check-133
      (check ilist= (iq 1 2) (imap-in-order z1 (iq a b))))

    (define check-134
      (check '#(0 1 4 9 16)
             (let ((v (make-vector 5)))
               (ifor-each (lambda (i)
                            (vector-set! v i (* i i)))
                          (iq 0 1 2 3 4))
               v)))

    (define check-135
      (check '#(5 7 9 11 13)
             (let ((v (make-vector 5)))
               (ifor-each (lambda (i j)
                            (vector-set! v i (+ i j)))
                       (iq 0 1 2 3 4)
                       (iq 5 6 7 8 9))
               v)))

    (define check-136
      (check ilist= (iq 1 -1 3 -3 8 -8)
             (iappend-map (lambda (x) (ilist x (- x))) (iq 1 3 8))))

    (define check-137
      (check ilist= (iq 1 4 2 5 3 6)
             (iappend-map ilist (iq 1 2 3) (iq 4 5 6))))

    (define check-138
      (check (make-ilist (iq 0 1 2 3 4) (iq 1 2 3 4) (iq 2 3 4) (iq 3 4) (iq 4))
             (let ((v (make-vector 5)))
               (ipair-for-each (lambda (lis) (vector-set! v (icar lis) lis)) (iq 0 1 2 3 4))
               v)))

    (define check-139
      (check (vector (iq 5 6 7 8 9) (iq 6 7 8 9) (iq 7 8 9) (iq 8 9) (iq 9))
             (let ((v (make-vector 5)))
               (ipair-for-each (lambda (i j) (vector-set! v (icar i) j))
                               (iq 0 1 2 3 4)
                               (iq 5 6 7 8 9))
               v)))

    (define check-140
      (check ilist= (iq 1 9 49)
             (ifilter-map (lambda (x) (and (number? x) (* x x))) (iq a 1 b 3 c 7))))

    (define check-141
      (check ilist= (iq 5 7 9)
             (ifilter-map
              (lambda (x y) (and (number? x) (number? y) (+ x y)))
              (iq 1 a 2 b 3 4)
              (iq 4 0 5 y 6 z1))))

    (define check-142
      (check ilist= (iq 0 8 8 -4) (ifilter even? (iq 0 7 8 8 43 -4))))

    (define check-143
      (check (list (iq one four five) (iq 2 3 6))
             (call-with-values
                 (lambda () (ipartition symbol? (iq one 2 3 four five 6)))
               list)))

    (define check-144
      (check ilist= (iq 7 43) (iremove even? (iq 0 7 8 8 43 -4))))

    (define check-145
      (check 2 (ifind even? (iq 1 2 3))))

    (define check-146
      (check #t (iany even? (iq 1 2 3))))

    (define check-147
      (check #f (ifind even? (iq 1 7 3))))

    (define check-148
      (check #f (iany  even? (iq 1 7 3))))

    (define check-149
      (check-raise (ifind even? (ipair 1 (ipair 3 'x)))))

    (define check-150
      (check-raise (iany  even? (ipair 1 (ipair 3 'x)))))

    (define check-151
      (check 4 (ifind even? (iq 3 1 4 1 5 9))))

    (define check-152
      (check ilist= (iq -8 -5 0 0) (ifind-tail even? (iq 3 1 37 -8 -5 0 0))))

    (define check-153
      (check ilist= (iq 2 18) (itake-while even? (iq 2 18 3 10 22 9))))

    (define check-154
      (check ilist= (iq 3 10 22 9) (idrop-while even? (iq 2 18 3 10 22 9))))

    (define check-155
      (check (list (iq 2 18) (iq 3 10 22 9))
             (call-with-values
                 (lambda () (ispan even? (iq 2 18 3 10 22 9)))
               list)))

    (define check-156
      (check (list (iq 3 1) (iq 4 1 5 9))
             (call-with-values
                 (lambda () (ibreak even? (iq 3 1 4 1 5 9)))
               list)))

    (define check-157
      (check #t (iany integer? (iq a 3 b 2.7))))

    (define check-158
      (check #f (iany integer? (iq a 3.1 b 2.7))))

    (define check-159
      (check #t (iany < (iq 3 1 4 1 5) (iq 2 7 1 8 2))))

    (define check-160
      (check #t (ievery integer? (iq 1 2 3 4 5))))

    (define check-161
      (check #f (ievery integer? (iq 1 2 3 4.5 5))))

    (define check-162
      (check #t (ievery (lambda (a b) (< a b)) (iq 1 2 3) (iq 4 5 6))))

    (define check-163
      (check 2 (ilist-index even? (iq 3 1 4 1 5 9))))

    (define check-164
      (check 1 (ilist-index < (iq 3 1 4 1 5 9 2 5 6) (iq 2 7 1 8 2))))

    (define check-165
      (check #f (ilist-index = (iq 3 1 4 1 5 9 2 5 6) (iq 2 7 1 8 2))))

    (define check-166
      (check ilist= (iq a b c) (imemq 'a (iq a b c))))

    (define check-167
      (check ilist= (iq b c) (imemq 'b (iq a b c))))

    (define check-168
      (check #f (imemq 'a (iq b c d))))

    (define check-169
      (check #f (imemq (ilist 'a) (iq b (a) c))))

    (define check-170
      (check ilist= (iq (a) c) (imember (ilist 'a) (iq b (a) c))))

    (define check-171
      (check ilist= (iq 101 102) (imemv 101 (iq 100 101 102))))

    (define check-172
      (check ilist= (iq 1 2 4 5) (idelete 3 (iq 1 2 3 4 5))))

    (define check-173
      (check ilist= (iq 3 4 5) (idelete 5 (iq 3 4 5 6 7) <)))

    (define check-174
      (check ilist= (iq a b c z1) (idelete-duplicates (iq a b a c a b c z1))))

    (define e (iq (a 1) (b 2) (c 3)))

    (define check-175
      (check ilist= (iq a 1) (iassq 'a e)))

    (define check-176
      (check ilist= (iq b 2) (iassq 'b e)))

    (define check-177
      (check #f (iassq 'd e)))

    (define check-178
      (check #f (iassq (ilist 'a) (iq ((a)) ((b)) ((c))))))

    (define check-179
      (check ilist= (iq (a)) (iassoc (ilist 'a) (iq ((a)) ((b)) ((c))))))

    (define e2 (iq (2 3) (5 7) (11 13)))

    (define check-180
      (check ilist= (iq 5 7) (iassv 5 e2)))

    (define check-181
      (check ilist= (iq 11 13) (iassoc 5 e2 <)))

    (define check-182
      (check ilist= (ipair (iq 1 1) e2) (ialist-cons 1 (ilist 1) e2)))

    (define check-183
      (check ilist= (iq (2 3) (11 13)) (ialist-delete 5 e2)))

    (define check-184
      (check ilist= (iq (2 3) (5 7)) (ialist-delete 5 e2 <)))

    (define check-185
      (check ilist= (ipair 1 3) (replace-icar (ipair 2 3) 1)))

    (define check-186
      (check ilist= (ipair 1 3) (replace-icdr (ipair 1 2) 3)))

    (define check-187
      (check ilist= (ipair 1 2) (pair->ipair '(1 . 2))))

    (define check-188
      (check '(1 . 2) (ipair->pair (ipair 1 2))))

    (define check-189
      (check ilist= (iq 1 2 3) (list->ilist '(1 2 3))))

    (define check-190
      (check '(1 2 3) (ilist->list (iq 1 2 3))))

    (define check-191
      (check ilist= (ipair 1 (ipair 2 3)) (list->ilist '(1 2 . 3))))

    (define check-192
      (check '(1 2 . 3) (ilist->list (ipair 1 (ipair 2 3)))))

    (define check-193
      (check ilist= (ipair (ipair 1 2) (ipair 3 4)) (tree->itree '((1 . 2) . (3 . 4)))))

    (define check-194
      (check '((1 . 2) . (3 . 4)) (itree->tree (ipair (ipair 1 2) (ipair 3 4)))))

    (define check-195
      (check ilist= (ipair (ipair 1 2) (ipair 3 4)) (gtree->itree (cons (ipair 1 2) (ipair 3 4)))))

    (define check-196
      (check '((1 . 2) . (3 . 4)) (gtree->tree (cons (ipair 1 2) (ipair 3 4)))))

    (define check-197
      (check 6 (iapply + (iq 1 2 3))))

    (define check-198
      (check 15 (iapply + 1 2 (iq 3 4 5))))

    ))

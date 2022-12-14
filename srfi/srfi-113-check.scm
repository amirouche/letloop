(library (srfi srfi-113-check)

  (export ~check-srfi-113-000 ~check-srfi-113-001 ~check-srfi-113-002 ~check-srfi-113-003 ~check-srfi-113-004 ~check-srfi-113-005
~check-srfi-113-006 ~check-srfi-113-007 ~check-srfi-113-008 ~check-srfi-113-009 ~check-srfi-113-010 ~check-srfi-113-011 ~check-srfi-113-012
~check-srfi-113-013 ~check-srfi-113-014 ~check-srfi-113-015 ~check-srfi-113-016 ~check-srfi-113-017 ~check-srfi-113-018 ~check-srfi-113-019
~check-srfi-113-020 ~check-srfi-113-021 ~check-srfi-113-022 ~check-srfi-113-023 ~check-srfi-113-024 ~check-srfi-113-025 ~check-srfi-113-026
~check-srfi-113-027 ~check-srfi-113-028 ~check-srfi-113-029 ~check-srfi-113-030 ~check-srfi-113-031 ~check-srfi-113-032 ~check-srfi-113-033
~check-srfi-113-034 ~check-srfi-113-035 ~check-srfi-113-036 ~check-srfi-113-037 ~check-srfi-113-038 ~check-srfi-113-039 ~check-srfi-113-040
~check-srfi-113-041 ~check-srfi-113-042 ~check-srfi-113-043 ~check-srfi-113-044 ~check-srfi-113-045 ~check-srfi-113-046 ~check-srfi-113-047
~check-srfi-113-048 ~check-srfi-113-049 ~check-srfi-113-050 ~check-srfi-113-051 ~check-srfi-113-052 ~check-srfi-113-053 ~check-srfi-113-054
~check-srfi-113-055 ~check-srfi-113-056 ~check-srfi-113-057 ~check-srfi-113-058 ~check-srfi-113-059 ~check-srfi-113-060 ~check-srfi-113-061
~check-srfi-113-062 ~check-srfi-113-063 ~check-srfi-113-064 ~check-srfi-113-065 ~check-srfi-113-066 ~check-srfi-113-067 ~check-srfi-113-068
~check-srfi-113-069 ~check-srfi-113-070 ~check-srfi-113-071 ~check-srfi-113-072 ~check-srfi-113-073 ~check-srfi-113-074 ~check-srfi-113-075
~check-srfi-113-076 ~check-srfi-113-077 ~check-srfi-113-078 ~check-srfi-113-079 ~check-srfi-113-080 ~check-srfi-113-081 ~check-srfi-113-082
~check-srfi-113-083 ~check-srfi-113-084 ~check-srfi-113-085 ~check-srfi-113-086 ~check-srfi-113-087 ~check-srfi-113-088 ~check-srfi-113-089
~check-srfi-113-090 ~check-srfi-113-091 ~check-srfi-113-092 ~check-srfi-113-093 ~check-srfi-113-094 ~check-srfi-113-095 ~check-srfi-113-096
~check-srfi-113-097 ~check-srfi-113-098 ~check-srfi-113-099 ~check-srfi-113-100 ~check-srfi-113-101 ~check-srfi-113-102 ~check-srfi-113-103
~check-srfi-113-104 ~check-srfi-113-105 ~check-srfi-113-106 ~check-srfi-113-107 ~check-srfi-113-108 ~check-srfi-113-109 ~check-srfi-113-110
~check-srfi-113-111 ~check-srfi-113-112 ~check-srfi-113-113 ~check-srfi-113-114 ~check-srfi-113-115 ~check-srfi-113-116 ~check-srfi-113-117
~check-srfi-113-118 ~check-srfi-113-119 ~check-srfi-113-120 ~check-srfi-113-121 ~check-srfi-113-122 ~check-srfi-113-123 ~check-srfi-113-124
~check-srfi-113-125 ~check-srfi-113-126 ~check-srfi-113-127 ~check-srfi-113-128 ~check-srfi-113-129 ~check-srfi-113-130 ~check-srfi-113-131
~check-srfi-113-132 ~check-srfi-113-133 ~check-srfi-113-134 ~check-srfi-113-135 ~check-srfi-113-136 ~check-srfi-113-137 ~check-srfi-113-138
~check-srfi-113-139 ~check-srfi-113-140 ~check-srfi-113-141 ~check-srfi-113-142 ~check-srfi-113-143 ~check-srfi-113-144 ~check-srfi-113-145
~check-srfi-113-146 ~check-srfi-113-147 ~check-srfi-113-148 ~check-srfi-113-149 ~check-srfi-113-150 ~check-srfi-113-151 ~check-srfi-113-152
~check-srfi-113-153 ~check-srfi-113-154 ~check-srfi-113-155 ~check-srfi-113-156 ~check-srfi-113-157 ~check-srfi-113-158 ~check-srfi-113-159
~check-srfi-113-160 ~check-srfi-113-161 ~check-srfi-113-162 ~check-srfi-113-163 ~check-srfi-113-164 ~check-srfi-113-165 ~check-srfi-113-166
~check-srfi-113-167 ~check-srfi-113-168 ~check-srfi-113-169 ~check-srfi-113-170 ~check-srfi-113-171 ~check-srfi-113-172 ~check-srfi-113-173
~check-srfi-113-174 ~check-srfi-113-175 ~check-srfi-113-176 ~check-srfi-113-177 ~check-srfi-113-178 ~check-srfi-113-179 ~check-srfi-113-180
~check-srfi-113-181 ~check-srfi-113-182 ~check-srfi-113-183 ~check-srfi-113-184 ~check-srfi-113-185 ~check-srfi-113-186 ~check-srfi-113-187
~check-srfi-113-188 ~check-srfi-113-189 ~check-srfi-113-190 ~check-srfi-113-191 ~check-srfi-113-192 ~check-srfi-113-193 ~check-srfi-113-194
~check-srfi-113-195 ~check-srfi-113-196 ~check-srfi-113-197 ~check-srfi-113-198 ~check-srfi-113-199 ~check-srfi-113-200 ~check-srfi-113-201
~check-srfi-113-202 ~check-srfi-113-203 ~check-srfi-113-204 ~check-srfi-113-205 ~check-srfi-113-206 ~check-srfi-113-207 ~check-srfi-113-208
~check-srfi-113-209 ~check-srfi-113-210 ~check-srfi-113-211 ~check-srfi-113-212 ~check-srfi-113-213 ~check-srfi-113-214 ~check-srfi-113-215
~check-srfi-113-216 ~check-srfi-113-217 ~check-srfi-113-218 ~check-srfi-113-219 ~check-srfi-113-220 ~check-srfi-113-221 ~check-srfi-113-222
~check-srfi-113-223 ~check-srfi-113-224 ~check-srfi-113-225 ~check-srfi-113-226 ~check-srfi-113-227 ~check-srfi-113-228 ~check-srfi-113-229
~check-srfi-113-230 ~check-srfi-113-231 ~check-srfi-113-232 ~check-srfi-113-233 ~check-srfi-113-234 ~check-srfi-113-235 ~check-srfi-113-236
~check-srfi-113-237 ~check-srfi-113-238 ~check-srfi-113-239 ~check-srfi-113-240 ~check-srfi-113-241 ~check-srfi-113-242 ~check-srfi-113-243
~check-srfi-113-244 ~check-srfi-113-245 ~check-srfi-113-246 ~check-srfi-113-247 ~check-srfi-113-248 ~check-srfi-113-249 ~check-srfi-113-250
~check-srfi-113-251 ~check-srfi-113-252 ~check-srfi-113-253 ~check-srfi-113-254 ~check-srfi-113-255 ~check-srfi-113-256 ~check-srfi-113-257
~check-srfi-113-258 ~check-srfi-113-259 ~check-srfi-113-260 ~check-srfi-113-261 ~check-srfi-113-262 ~check-srfi-113-263 ~check-srfi-113-264
~check-srfi-113-265 ~check-srfi-113-266 ~check-srfi-113-267 ~check-srfi-113-268 ~check-srfi-113-269 ~check-srfi-113-270 ~check-srfi-113-271
~check-srfi-113-272 ~check-srfi-113-273 ~check-srfi-113-274 ~check-srfi-113-275 ~check-srfi-113-276 ~check-srfi-113-277 ~check-srfi-113-278
~check-srfi-113-279 ~check-srfi-113-280 ~check-srfi-113-281)

  (import (scheme base)
          (scheme char)
          (scheme complex)
          (srfi srfi-113)
          (srfi srfi-128)
          (letloop check))

  ;; Below are some default comparators provided by SRFI-114,
  ;; but not SRFI-128, which this SRFI has transitioned to
  ;; depend on. See the rationale for SRFI-128 as to why it is
  ;; preferred in usage compared to SRFI-114.

  ;; Most if not all of this code is taken from SRFI-114

  (define (make-comparison=/< = <)
    (lambda (a b)
      (cond
       ((= a b) 0)
       ((< a b) -1)
       (else 1))))

  ;; Comparison procedure for real numbers only
  (define (real-comparison a b)
    (cond
     ((< a b) -1)
     ((> a b) 1)
     (else 0)))

  ;; Comparison procedure for non-real numbers.
  (define (complex-comparison a b)
    (let ((real-result (real-comparison (real-part a) (real-part b))))
      (if (= real-result 0)
          (real-comparison (imag-part a) (imag-part b))
          real-result)))

  (define number-comparator
    (make-comparator number? = complex-comparison number-hash))

  (define char-comparison (make-comparison=/< char=? char<?))

  (define char-comparator
    (make-comparator char? char=? char-comparison char-hash))

  ;; Makes a hash function that works vectorwise
  (define limit (expt 2 20))

  (define (make-vectorwise-hash hash length ref)
    (lambda (obj)
      (let loop ((index (- (length obj) 1)) (result 5381))
        (if (= index 0)
            result
            (let* ((prod (modulo (* result 33) limit))
                   (sum (modulo (+ prod (hash (ref obj index))) limit)))
              (loop (- index 1) sum))))))

  (define string-comparison (make-comparison=/< string=? string<?))

  (define string-ci-comparison (make-comparison=/< string-ci=? string-ci<?))

  (define string-comparator
    (make-comparator string? string=? string-comparison string-hash))

  (define string-ci-comparator
    (make-comparator string? string-ci=? string-ci-comparison string-ci-hash))

  (define eq-comparator
    (make-comparator
     #t
     eq?
     #f
     default-hash))

  (define eqv-comparator
    (make-comparator
     #t
     eqv?
     #f
     default-hash))

  (define equal-comparator
    (make-comparator
     #t
     equal?
     #f
     default-hash))


  (define (big x) (> x 5))


  (define nums (set number-comparator))

  (define syms (set eq-comparator 'a 'b 'c 'd))

  (define nums2 (set-copy nums))

  (define syms2 (set-copy syms))

  (define esyms (set eq-comparator))
  (define ~check-srfi-113-000
    (check (set-empty? esyms)))

  (define total 0)

  (define ~check-srfi-113-001
    (check (set? nums)))

  (define ~check-srfi-113-002
    (check (set? syms)))

  (define ~check-srfi-113-003
    (check (set? nums2)))

  (define ~check-srfi-113-004
    (check (set? syms2)))

  (define ~check-srfi-113-005
    (check (not (set? 'a))))

  (define ~check-srfi-113-006
    (check 4
           (begin (set-adjoin! nums 2)
                  (set-adjoin! nums 3)
                  (set-adjoin! nums 4)
                  (set-adjoin! nums 4)
                  (set-size (set-adjoin nums 5)))))
  (define ~check-srfi-113-007
    (check 3 (set-size nums)))

  (define ~check-srfi-113-008
    (check 3 (set-size (set-delete syms 'd))))

  (define ~check-srfi-113-009
    (check 2 (set-size (set-delete-all syms '(c d)))))

  (define ~check-srfi-113-010
    (check 4 (set-size syms)))

  (define ~check-srfi-113-011
    (check 4 (begin (set-adjoin! syms 'e 'f) (set-size (set-delete-all! syms '(e f))))))

  (define ~check-srfi-113-012
    (check 0 (set-size nums2)))

  (define ~check-srfi-113-013
    (check 4 (set-size syms2)))

  (define ~check-srfi-113-014
    (check 2 (begin (set-delete! nums 2) (set-size nums))))

  (define ~check-srfi-113-015
    (check 2 (begin (set-delete! nums 1)
                    (set-size nums))))

  (define ~check-srfi-113-016
    (check (begin (set! nums2 (set-map number-comparator (lambda (x) (* 10 x)) nums))
                  (set-contains? nums2 30))))

  (define ~check-srfi-113-017
    (check (not (set-contains? nums2 3))))

  (define ~check-srfi-113-018
    (check 70 (begin   (set-for-each (lambda (x) (set! total (+ total x))) nums2)
                       total)))

  (define ~check-srfi-113-019
    (check 10 (set-fold + 3 nums)))

  (define ~check-srfi-113-020
    (check
     (begin
       (set! nums (set eqv-comparator 10 20 30 40 50))

       (set=? nums (set-unfold
                    (lambda (i) (= i 0))
                    (lambda (i) (* i 10))
                    (lambda (i) (- i 1))
                    5
                    eqv-comparator)))))

  (define ~check-srfi-113-021
    (check '(a) (set->list (set eq-comparator 'a))))

  (define ~check-srfi-113-022
    (check 2 (begin
               (set! syms2 (list->set eq-comparator '(e f)))
               (set-size syms2))))

  (define ~check-srfi-113-023
    (check (set-contains? syms2 'e)))

  (define ~check-srfi-113-024
    (check (set-contains? syms2 'f)))

  (define ~check-srfi-113-025
    (check 4 (begin
               (list->set! syms2 '(a b))
               (set-size syms2))))

  (define yam (set char-comparator #\y #\a #\m))

  (define (failure/insert insert ignore)
    (insert 1))

  (define (failure/ignore insert ignore)
    (ignore 2))

  (define (success/update element update remove)
    (update #\b 3))

  (define (success/remove element update remove)
    (remove 4))

  (define yam! (set char-comparator #\y #\a #\m #\!))

  (define bam (set char-comparator #\b #\a #\m))

  (define ym (set char-comparator #\y #\m))

  (define-values (set1 obj1)
    (set-search! (set-copy yam) #\! failure/insert error))

  (define ~check-srfi-113-026
    (check (set=? yam! set1)))

  (define ~check-srfi-113-027
    (check 1 obj1))

  (define-values (set2 obj2)
    (set-search! (set-copy yam) #\! failure/ignore error))

  (define ~check-srfi-113-028
    (check (set=? yam set2)))

  (define ~check-srfi-113-029
    (check 2 obj2))

  (define-values (set3 obj3)
    (set-search! (set-copy yam) #\y error success/update))

  (define ~check-srfi-113-030
    (check (set=? bam set3)))

  (define ~check-srfi-113-031
    (check 3 obj3))

  (define-values (set4 obj4)
    (set-search! (set-copy yam) #\a error success/remove))

  (define ~check-srfi-113-032
    (check (set=? ym set4)))

  (define ~check-srfi-113-033
    (check 4 obj4))

  (define set2-bis (set number-comparator 1 2))
  (define other-set2 (set number-comparator 1 2))
  (define set3-bis (set number-comparator 1 2 3))
  (define set4-bis (set number-comparator 1 2 3 4))
  (define sety (set number-comparator 1 2 4 5))
  (define setx (set number-comparator 10 20 30 40))

  (define ~check-srfi-113-034
    (check (set=? set2-bis other-set2)))

  (define ~check-srfi-113-035
    (check (not (set=? set2-bis set3-bis))))

  (define ~check-srfi-113-036
    (check (not (set=? set2-bis set3-bis other-set2))))

  (define ~check-srfi-113-037
    (check (set<? set2-bis set3-bis set4-bis)))

  (define ~check-srfi-113-038
    (check (not (set<? set2-bis other-set2))))

  (define ~check-srfi-113-039
    (check (set<=? set2-bis other-set2 set3-bis)))

  (define ~check-srfi-113-040
    (check (not (set<=? set2-bis set3-bis other-set2))))

  (define ~check-srfi-113-041
    (check (set>? set4-bis set3-bis set2-bis)))

  (define ~check-srfi-113-042
    (check (not (set>? set2-bis other-set2))))

  (define ~check-srfi-113-043
    (check (set>=? set3-bis other-set2 set2-bis)))

  (define ~check-srfi-113-044
    (check (not (set>=? other-set2 set3-bis set2-bis))))

  (define ~check-srfi-113-045
    (check (not (set<? set2-bis other-set2))))

  (define ~check-srfi-113-046
    (check (not (set<? set2-bis setx))))

  (define ~check-srfi-113-047
    (check (not (set<=? set2-bis setx))))

  (define ~check-srfi-113-048
    (check (not (set>? set2-bis setx))))

  (define ~check-srfi-113-049
    (check (not (set>=? set2-bis setx))))

  (define ~check-srfi-113-050
    (check (not (set<?  set3-bis sety))))

  (define ~check-srfi-113-051
    (check (not (set<=? set3-bis sety))))

  (define ~check-srfi-113-052
    (check (not (set>?  set3-bis sety))))

  (define ~check-srfi-113-053
    (check (not (set>=? set3-bis sety))))

  (define abcd (set eq-comparator 'a 'b 'c 'd))
  (define efgh (set eq-comparator 'e 'f 'g 'h))
  (define abgh (set eq-comparator 'a 'b 'g 'h))
  (define other-abcd (set eq-comparator 'a 'b 'c 'd))
  (define other-efgh (set eq-comparator 'e 'f 'g 'h))
  (define other-abgh (set eq-comparator 'a 'b 'g 'h))
  (define all (set eq-comparator 'a 'b 'c 'd 'e 'f 'g 'h))
  (define none (set eq-comparator))
  (define ab (set eq-comparator 'a 'b))
  (define cd (set eq-comparator 'c 'd))
  (define ef (set eq-comparator 'e 'f))
  (define gh (set eq-comparator 'g 'h))
  (define cdgh (set eq-comparator 'c 'd 'g 'h))
  (define abcdgh (set eq-comparator 'a 'b 'c 'd 'g 'h))
  (define abefgh (set eq-comparator 'a 'b 'e 'f 'g 'h))

  (define ~check-srfi-113-054
    (check (set-disjoint? abcd efgh)))

  (define ~check-srfi-113-055
    (check (not (set-disjoint? abcd ab))))

  (define ~check-srfi-113-056
    (check set=? abcd (set-union abcd)))

  (define ~check-srfi-113-057
    (check set=? all (set-union abcd efgh)))

  (define ~check-srfi-113-058
    (check set=? abcdgh (set-union abcd abgh)))

  (define ~check-srfi-113-059
    (check set=? abefgh (set-union efgh abgh)))


  (define efgh2 (set-copy efgh))

  (define ~check-srfi-113-060
    (check set=? efgh (begin (set-union! efgh2) efgh2)))

  (define ~check-srfi-113-061
    (check set=? abefgh (begin (set-union! efgh2 abgh) efgh2)))

  (define ~check-srfi-113-062
    (check set=? abcd (set-intersection abcd)))

  (define ~check-srfi-113-063
    (check set=? none (set-intersection abcd efgh)))

  (define abcd2 (set-copy abcd))

  (define ~check-srfi-113-064
    (check set=?
           abcd
           (begin
             (set-intersection! abcd2)
             abcd2)))
  (define ~check-srfi-113-065
    (check set=? none (begin (set-intersection! abcd2 efgh) abcd2)))

  (define ~check-srfi-113-066
    (check set=? ab (set-intersection abcd abgh)))

  (define ~check-srfi-113-067
    (check set=? ab (set-intersection abgh abcd)))

  (define ~check-srfi-113-068
    (check set=? abcd (set-difference abcd)))

  (define ~check-srfi-113-069
    (check set=? cd (set-difference abcd ab)))

  (define ~check-srfi-113-070
    (check set=? abcd (set-difference abcd gh)))

  (define ~check-srfi-113-071
    (check set=? none (set-difference abcd abcd)))


  (define abcd3 (set-copy abcd))

  (define ~check-srfi-113-072
    (check set=?
           abcd
           (begin
             (set-difference! abcd3)
             abcd3)))

  (define ~check-srfi-113-073
    (check set=? none (begin (set-difference! abcd3 abcd)
                             abcd3)))

  (define ~check-srfi-113-074
    (check set=? cdgh (set-xor abcd abgh)))

  (define ~check-srfi-113-075
    (check set=? all (set-xor abcd efgh)))

  (define ~check-srfi-113-076
    (check set=? none (set-xor abcd other-abcd)))

  (define abcd4 (set-copy abcd))
  (define ~check-srfi-113-077
    (check set=? none (set-xor! abcd4 other-abcd)))

  (define ~check-srfi-113-078
    (check set=? other-abcd abcd))

  (define ~check-srfi-113-079
    (check set=? other-efgh efgh))

  (define ~check-srfi-113-080
    (check set=? other-abgh abgh))

  (define nums3 (set number-comparator 1 2 3))
  (define syms3 (set eq-comparator 'a 'b 'c))

  (define ~check-srfi-113-081
    (~check-srfi-113-raise (set=? nums3 syms3)))

  (define ~check-srfi-113-082
    (~check-srfi-113-raise (set<? nums3 syms3)))

  (define ~check-srfi-113-083
    (~check-srfi-113-raise (set<=? nums3 syms3)))

  (define ~check-srfi-113-084
    (~check-srfi-113-raise (set>? nums3 syms3)))

  (define ~check-srfi-113-085
    (~check-srfi-113-raise (set>=? nums3 syms3)))

  (define ~check-srfi-113-086
    (~check-srfi-113-raise (set-union nums3 syms3)))

  (define ~check-srfi-113-087
    (~check-srfi-113-raise (set-intersection nums3 syms3)))

  (define ~check-srfi-113-088
    (~check-srfi-113-raise (set-difference nums3 syms3)))

  (define ~check-srfi-113-089
    (~check-srfi-113-raise (set-xor nums3 syms3)))

  (define ~check-srfi-113-090
    (~check-srfi-113-raise (set-union! nums3 syms3)))

  (define ~check-srfi-113-091
    (~check-srfi-113-raise (set-intersection! nums3 syms3)))

  (define ~check-srfi-113-092
    (~check-srfi-113-raise (set-difference! nums3 syms3)))

  (define ~check-srfi-113-093
    (~check-srfi-113-raise (set-xor! nums3 syms3)))

  (define whole (set eqv-comparator 1 2 3 4 5 6 7 8 9 10))
  (define whole2 (set-copy whole))
  (define whole3 (set-copy whole))
  (define whole4 (set-copy whole))
  (define bottom (set eqv-comparator 1 2 3 4 5))
  (define top (set eqv-comparator 6 7 8 9 10))
  (define-values (topx bottomx)
    (set-partition big whole))

  (define ~check-srfi-113-094
    (check set=? top (begin
                       (set-partition! big whole4)
                       (set-filter big whole))))

  (define ~check-srfi-113-095
    (check set=? bottom (set-remove big whole)))

  (define ~check-srfi-113-096
    (check (begin
             (set-filter! big whole2)
             (not (set-contains? whole2 1)))))

  (define ~check-srfi-113-097
    (check (begin
             (set-remove! big whole3)
             (not (set-contains? whole3 10)))))

  (define ~check-srfi-113-098
    (check set=? top topx))

  (define ~check-srfi-113-099
    (check set=? bottom bottomx))

  (define ~check-srfi-113-100
    (check set=? top whole4))

  (define ~check-srfi-113-101
    (check 5 (set-count big whole)))

  (define hetero (set eqv-comparator 1 2 'a 3 4))
  (define homo (set eqv-comparator 1 2 3 4 5))

  (define ~check-srfi-113-102
    (check 'a (set-find symbol? hetero (lambda () (error "wrong")))))

  (define ~check-srfi-113-103
    (~check-srfi-113-raise  (set-find symbol? homo (lambda () (error "wrong")))))

  (define ~check-srfi-113-104
    (check (set-any? symbol? hetero)))

  (define ~check-srfi-113-105
    (check (set-any? number? hetero)))

  (define ~check-srfi-113-106
    (check (not (set-every? symbol? hetero))))

  (define ~check-srfi-113-107
    (check (not (set-every? number? hetero))))

  (define ~check-srfi-113-108
    (check (not (set-any? symbol? homo))))

  (define ~check-srfi-113-109
    (check (set-every? number? homo)))

  (define bucket (set string-ci-comparator "abc" "def"))

  (define ~check-srfi-113-110
    (check string-ci-comparator (set-element-comparator bucket)))

  (define ~check-srfi-113-111
    (check (set-contains? bucket "abc")))

  (define ~check-srfi-113-112
    (check (set-contains? bucket "ABC")))

  (define ~check-srfi-113-113
    (check "def" (set-member bucket "DEF" "fqz")))

  (define ~check-srfi-113-114
    (check "fqz" (set-member bucket "lmn" "fqz")))

  (define nums4 (set number-comparator 1 2 3))

  (define nums42 (set-replace nums4 2.0))

  (define ~check-srfi-113-115
    (check (set-any? inexact? nums42)))

  (define ~check-srfi-113-116
    (check (begin (set-replace! nums4 2.0)
                  (set-any? inexact? nums4))))

  (define sos
    (set set-comparator
         (set equal-comparator '(2 . 1) '(1 . 1) '(0 . 2) '(0 . 0))
         (set equal-comparator '(2 . 1) '(1 . 1) '(0 . 0) '(0 . 2))))

  (define ~check-srfi-113-117
    (check 1 (set-size sos)))

  (define nums5 (bag number-comparator))
  (define syms-bis (bag eq-comparator 'a 'b 'c 'd))
  (define nums52 (bag-copy nums5))
  (define syms2-bis (bag-copy syms-bis))
  (define esyms-bis (bag eq-comparator))

  (define ~check-srfi-113-118
    (check (bag-empty? esyms-bis)))

  (define total-bis 0)

  (define ~check-srfi-113-119
    (check (bag? nums5)))

  (define ~check-srfi-113-120
    (check (bag? syms-bis)))

  (define ~check-srfi-113-121
    (check (bag? nums52)))

  (define ~check-srfi-113-122
    (check (bag? syms2-bis)))

  (define ~check-srfi-113-123
    (check (not (bag? 'a))))

  (define ~check-srfi-113-124
    (check 4 (begin
               (bag-adjoin! nums5 2)
               (bag-adjoin! nums5 3)
               (bag-adjoin! nums5 4)

               (bag-size (bag-adjoin nums5 5)))))

  (define ~check-srfi-113-125
    (check 3 (bag-size nums5)))

  (define ~check-srfi-113-126
    (check 3 (bag-size (bag-delete syms-bis 'd))))

  (define ~check-srfi-113-127
    (check 2 (bag-size (bag-delete-all syms-bis '(c d)))))

  (define ~check-srfi-113-128
    (check 4 (bag-size syms-bis)))

  (define ~check-srfi-113-129
    (check 4 (begin (bag-adjoin! syms-bis 'e 'f)
                    (bag-size (bag-delete-all! syms-bis '(e f))))))

  (define ~check-srfi-113-130
    (check 3 (bag-size nums5)))

  (define ~check-srfi-113-131
    (check 3 (begin (bag-delete! nums5 1) (bag-size nums5))))

  (define ~check-srfi-113-132
    (check (begin   (set! nums52 (bag-map number-comparator (lambda (x) (* 10 x)) nums5))
                    (bag-contains? nums52 30))))

  (define ~check-srfi-113-133
    (check (not (bag-contains? nums52 3))))

  (define ~check-srfi-113-134
    (check 90 (begin (bag-for-each (lambda (x) (set! total-bis (+ total-bis x))) nums52)
                     total-bis)))
  (define ~check-srfi-113-135
    (check 12 (bag-fold + 3 nums5)))

  (define ~check-srfi-113-136
    (check
     (begin
       (set! nums5 (bag eqv-comparator 10 20 30 40 50))
       (bag=? nums5 (bag-unfold
                     (lambda (i) (= i 0))
                     (lambda (i) (* i 10))
                     (lambda (i) (- i 1))
                     5
                     eqv-comparator)))))

  (define ~check-srfi-113-137
    (check '(a) (bag->list (bag eq-comparator 'a))))

  (define ~check-srfi-113-138
    (check 2 (begin (set! syms2-bis (list->bag eq-comparator '(e f))) (bag-size syms2-bis))))

  (define ~check-srfi-113-139
    (check (bag-contains? syms2-bis 'e)))

  (define ~check-srfi-113-140
    (check (bag-contains? syms2-bis 'f)))

  (define ~check-srfi-113-141
    (check 4 (begin (list->bag! syms2-bis '(e f))
                    (bag-size syms2-bis))))

  (define yam2 (bag char-comparator #\y #\a #\m))

  (define (failure/insert/bis insert ignore)
    (insert 1))

  (define (failure/ignore/bis insert ignore)
    (ignore 2))

  (define (success/update/bis element update remove)
    (update #\b 3))

  (define (success/remove/bis element update remove)
    (remove 4))

  (define yam2! (bag char-comparator #\y #\a #\m #\!))

  (define bam2 (bag char-comparator #\b #\a #\m))

  (define ym-bis (bag char-comparator #\y #\m))

  (define-values (bag1 obj1-bis)
    (bag-search! (bag-copy yam2) #\! failure/insert/bis error))

  (define ~check-srfi-113-142
    (check (bag=? yam2! bag1)))

  (define ~check-srfi-113-143
    (check 1 obj1-bis))

  (define-values (bag2 obj2-bis)
    (bag-search! (bag-copy yam2) #\! failure/ignore/bis error))

  (define ~check-srfi-113-144
    (check (bag=? yam2 bag2)))

  (define ~check-srfi-113-145
    (check 2 obj2-bis))

  (define-values (bag3 obj3-bis)
    (bag-search! (bag-copy yam2) #\y error success/update/bis))

  (define ~check-srfi-113-146
    (check (bag=? bam2 bag3)))

  (define ~check-srfi-113-147
    (check 3 obj3-bis))

  (define-values (bag4 obj4-bis)
    (bag-search! (bag-copy yam2) #\a error success/remove/bis))

  (define ~check-srfi-113-148
    (check (bag=? ym-bis bag4)))

  (define ~check-srfi-113-149
    (check 4 obj4-bis))

  (define mybag (bag eqv-comparator 1 1 1 1 1 2 2))

  (define ~check-srfi-113-150
    (check 5 (bag-element-count mybag 1)))

  (define ~check-srfi-113-151
    (check 0 (bag-element-count mybag 3)))

  (define bag2-bis (bag number-comparator 1 2))
  (define other-bag2 (bag number-comparator 1 2))
  (define bag3-bis (bag number-comparator 1 2 3))
  (define bag4-bis (bag number-comparator 1 2 3 4))
  (define bagx (bag number-comparator 10 20 30 40))
  (define bagy (bag number-comparator 10 20 20 30 40))

  (define ~check-srfi-113-152
    (check (bag=? bag2-bis other-bag2)))

  (define ~check-srfi-113-153
    (check (not (bag=? bag2-bis bag3-bis))))

  (define ~check-srfi-113-154
    (check (not (bag=? bag2-bis bag3-bis other-bag2))))

  (define ~check-srfi-113-155
    (check (bag<? bag2-bis bag3-bis bag4-bis)))

  (define ~check-srfi-113-156
    (check (not (bag<? bag2-bis other-bag2))))

  (define ~check-srfi-113-157
    (check (bag<=? bag2-bis other-bag2 bag3-bis)))

  (define ~check-srfi-113-158
    (check (not (bag<=? bag2-bis bag3-bis other-bag2))))

  (define ~check-srfi-113-159
    (check (bag>? bag4-bis bag3-bis bag2-bis)))

  (define ~check-srfi-113-160
    (check (not (bag>? bag2-bis other-bag2))))

  (define ~check-srfi-113-161
    (check (bag>=? bag3-bis other-bag2 bag2-bis)))

  (define ~check-srfi-113-162
    (check (not (bag>=? other-bag2 bag3-bis bag2-bis))))

  (define ~check-srfi-113-163
    (check (not (bag<? bag2-bis other-bag2))))

  (define ~check-srfi-113-164
    (check (bag<=? bagx bagy)))

  (define ~check-srfi-113-165
    (check (not (bag<=? bagy bagx))))

  (define ~check-srfi-113-166
    (check (bag<? bagx bagy)))

  (define ~check-srfi-113-167
    (check (not (bag<? bagy bagx))))

  (define ~check-srfi-113-168
    (check (bag>=? bagy bagx)))

  (define ~check-srfi-113-169
    (check (not (bag>=? bagx bagy))))

  (define ~check-srfi-113-170
    (check (bag>? bagy bagx)))

  (define ~check-srfi-113-171
    (check (not (bag>? bagx bagy))))

  (define one (bag eqv-comparator 10))

  (define two (bag eqv-comparator 10 10))

  (define ~check-srfi-113-172
    (check (not (bag=? one two))))

  (define ~check-srfi-113-173
    (check (bag<? one two)))

  (define ~check-srfi-113-174
    (check (not (bag>? one two))))

  (define ~check-srfi-113-175
    (check (bag<=? one two)))

  (define ~check-srfi-113-176
    (check (not (bag>? one two))))

  (define ~check-srfi-113-177
    (check (bag=? two two)))

  (define ~check-srfi-113-178
    (check (not (bag<? two two))))

  (define ~check-srfi-113-179
    (check (not (bag>? two two))))

  (define ~check-srfi-113-180
    (check (bag<=? two two)))

  (define ~check-srfi-113-181
    (check (bag>=? two two)))

  (define ~check-srfi-113-182
    (check '((10 . 2))
           (let ((result '()))
             (bag-for-each-unique
              (lambda (x y) (set! result (cons (cons x y) result)))
              two)
             result)))

  (define ~check-srfi-113-183
    (check 25 (bag-fold + 5 two)))

  (define ~check-srfi-113-184
    (check 12 (bag-fold-unique (lambda (k n r) (+ k n r)) 0 two)))

  (define bag-abcd (bag eq-comparator 'a 'b 'c 'd))
  (define bag-efgh (bag eq-comparator 'e 'f 'g 'h))
  (define bag-abgh (bag eq-comparator 'a 'b 'g 'h))
  (define bag-other-abcd (bag eq-comparator 'a 'b 'c 'd))
  (define bag-other-efgh (bag eq-comparator 'e 'f 'g 'h))
  (define bag-other-abgh (bag eq-comparator 'a 'b 'g 'h))
  (define bag-all (bag eq-comparator 'a 'b 'c 'd 'e 'f 'g 'h))
  (define bag-none (bag eq-comparator))
  (define bag-ab (bag eq-comparator 'a 'b))
  (define bag-cd (bag eq-comparator 'c 'd))
  (define bag-ef (bag eq-comparator 'e 'f))
  (define bag-gh (bag eq-comparator 'g 'h))
  (define bag-cdgh (bag eq-comparator 'c 'd 'g 'h))
  (define bag-abcdgh (bag eq-comparator 'a 'b 'c 'd 'g 'h))
  (define bag-abefgh (bag eq-comparator 'a 'b 'e 'f 'g 'h))

  (define ~check-srfi-113-185
    (check (bag-disjoint? bag-abcd bag-efgh)))

  (define ~check-srfi-113-186
    (check (not (bag-disjoint? bag-abcd bag-ab))))

  (define ~check-srfi-113-187
    (check bag=? bag-abcd (bag-union bag-abcd)))

  (define ~check-srfi-113-188
    (check bag=? bag-all (bag-union bag-abcd bag-efgh)))

  (define ~check-srfi-113-189
    (check bag=? bag-abcdgh (bag-union bag-abcd bag-abgh)))

  (define ~check-srfi-113-190
    (check bag=? bag-abefgh (bag-union bag-efgh bag-abgh)))


  (define bag-efgh2-bis (bag-copy bag-efgh))

  (define ~check-srfi-113-191
    (check bag=? bag-efgh (begin (bag-union! bag-efgh2-bis)
                                 bag-efgh2-bis)))

  (define ~check-srfi-113-192
    (check bag=? bag-abefgh (begin (bag-union! bag-efgh2-bis bag-abgh) bag-efgh2-bis)))

  (define ~check-srfi-113-193
    (check bag=? bag-abcd (bag-intersection bag-abcd)))

  (define ~check-srfi-113-194
    (check bag=? bag-none (bag-intersection bag-abcd bag-efgh)))

  (define bag-abcd2-bis (bag-copy bag-abcd))

  (define ~check-srfi-113-195
    (check bag=? bag-abcd (begin (bag-intersection! bag-abcd2-bis) bag-abcd2-bis)))

  (define ~check-srfi-113-196
    (check bag=? bag-none (begin (bag-intersection! bag-abcd2-bis bag-efgh) bag-abcd2-bis)))

  (define ~check-srfi-113-197
    (check bag=? bag-ab (bag-intersection bag-abcd bag-abgh)))

  (define ~check-srfi-113-198
    (check bag=? bag-ab (bag-intersection bag-abgh bag-abcd)))

  (define ~check-srfi-113-199
    (check bag=? bag-abcd (bag-difference bag-abcd)))

  (define ~check-srfi-113-200
    (check bag=? bag-cd (bag-difference bag-abcd bag-ab)))

  (define ~check-srfi-113-201
    (check bag=? bag-abcd (bag-difference bag-abcd bag-gh)))

  (define ~check-srfi-113-202
    (check bag=? bag-none (bag-difference bag-abcd bag-abcd)))

  (define bag-abcd3-bis (bag-copy bag-abcd))

  (define ~check-srfi-113-203
    (check bag=? bag-abcd (begin (bag-difference! bag-abcd3-bis) bag-abcd3-bis)))

  (define ~check-srfi-113-204
    (check bag=? bag-none (begin (bag-difference! bag-abcd3-bis bag-abcd) bag-abcd3-bis)))

  (define ~check-srfi-113-205
    (check bag=? bag-cdgh (bag-xor bag-abcd bag-abgh)))

  (define ~check-srfi-113-206
    (check bag=? bag-all (bag-xor bag-abcd bag-efgh)))

  (define ~check-srfi-113-207
    (check bag=? bag-none (bag-xor bag-abcd bag-other-abcd)))

  (define bag-abcd4-bis (bag-copy bag-abcd))

  (define ~check-srfi-113-208
    (check bag=? bag-none (bag-xor! bag-abcd4-bis bag-other-abcd)))

  (define bag-abab (bag eq-comparator 'a 'b 'a 'b))

  (define ~check-srfi-113-209
    (check bag=? bag-ab (bag-sum bag-ab)))

  (define bag-ab2 (bag-copy bag-ab))

  (define ~check-srfi-113-210
    (check bag=? bag-ab (bag-sum! bag-ab2)))

  (define ~check-srfi-113-211
    (check bag=? bag-abab (bag-sum! bag-ab2 bag-ab)))

  (define ~check-srfi-113-212
    (check bag=? bag-abab bag-ab2))

  (define ~check-srfi-113-213
    (check bag=? bag-abab (bag-product 2 bag-ab)))

  (define bag-ab3 (bag-copy bag-ab))

  (define ~check-srfi-113-214
    (check bag=? bag-abab (begin (bag-product! 2 bag-ab3) bag-ab3)))

  (define ~check-srfi-113-215
    (check bag=? bag-other-abcd bag-abcd))

  (define ~check-srfi-113-216
    (check bag=? bag-other-abcd bag-abcd))

  (define ~check-srfi-113-217
    (check bag=? bag-other-efgh bag-efgh))

  (define ~check-srfi-113-218
    (check bag=? bag-other-abgh bag-abgh))

  (define bag-nums (bag number-comparator 1 2 3))

  (define bag-syms (bag eq-comparator 'a 'b 'c))

  (define ~check-srfi-113-219
    (~check-srfi-113-raise (bag=? bag-nums bag-syms)))

  (define ~check-srfi-113-220
    (~check-srfi-113-raise (bag<? bag-nums bag-syms)))

  (define ~check-srfi-113-221
    (~check-srfi-113-raise (bag<=? bag-nums bag-syms)))

  (define ~check-srfi-113-222
    (~check-srfi-113-raise (bag>? bag-nums bag-syms)))

  (define ~check-srfi-113-223
    (~check-srfi-113-raise (bag>=? bag-nums bag-syms)))

  (define ~check-srfi-113-224
    (~check-srfi-113-raise (bag-union bag-nums bag-syms)))

  (define ~check-srfi-113-225
    (~check-srfi-113-raise (bag-intersection bag-nums bag-syms)))

  (define ~check-srfi-113-226
    (~check-srfi-113-raise (bag-difference bag-nums bag-syms)))

  (define ~check-srfi-113-227
    (~check-srfi-113-raise (bag-xor bag-nums bag-syms)))

  (define ~check-srfi-113-228
    (~check-srfi-113-raise (bag-union! bag-nums bag-syms)))

  (define ~check-srfi-113-229
    (~check-srfi-113-raise (bag-intersection! bag-nums bag-syms)))

  (define ~check-srfi-113-230
    (~check-srfi-113-raise (bag-difference! bag-nums bag-syms)))

  (define bag-whole (bag eqv-comparator 1 2 3 4 5 6 7 8 9 10))
  (define bag-whole2 (bag-copy bag-whole))
  (define bag-whole3 (bag-copy bag-whole))
  (define bag-whole4 (bag-copy bag-whole))
  (define bag-bottom (bag eqv-comparator 1 2 3 4 5))
  (define bag-top (bag eqv-comparator 6 7 8 9 10))

  (define-values (topx-bis bottomx-bis)
    (bag-partition big bag-whole))

  (define ~check-srfi-113-231
    (check bag=? bag-top (begin (bag-partition! big bag-whole4) (bag-filter big bag-whole))))

  (define ~check-srfi-113-232
    (check bag=? bag-bottom (bag-remove big bag-whole)))

  (define ~check-srfi-113-233
    (check (begin (bag-filter! big bag-whole2) (not (bag-contains? bag-whole2 1)))))

  (define ~check-srfi-113-234
    (check (begin
             (bag-remove! big bag-whole3)
             (not (bag-contains? bag-whole3 10)))))

  (define ~check-srfi-113-235
    (check bag=? bag-top topx-bis))

  (define ~check-srfi-113-236
    (check bag=? bag-bottom bottomx-bis))

  (define ~check-srfi-113-237
    (check bag=? bag-top bag-whole4))

  (define ~check-srfi-113-238
    (check 5 (bag-count big bag-whole)))

  (define hetero-bis (bag eqv-comparator 1 2 'a 3 4))
  (define homo-bis (bag eqv-comparator 1 2 3 4 5))

  (define ~check-srfi-113-239
    (check 'a (bag-find symbol? hetero-bis (lambda () (error "wrong")))))

  (define ~check-srfi-113-240
    (~check-srfi-113-raise  (bag-find symbol? homo-bis (lambda () (error "wrong")))))

  (define ~check-srfi-113-241
    (check (bag-any? symbol? hetero-bis)))

  (define ~check-srfi-113-242
    (check (bag-any? number? hetero-bis)))

  (define ~check-srfi-113-243
    (check (not (bag-every? symbol? hetero-bis))))

  (define ~check-srfi-113-244
    (check (not (bag-every? number? hetero-bis))))

  (define ~check-srfi-113-245
    (check (not (bag-any? symbol? homo-bis))))

  (define ~check-srfi-113-246
    (check (bag-every? number? homo-bis)))

  (define bag-bucket (bag string-ci-comparator "abc" "def"))

  (define ~check-srfi-113-247
    (check string-ci-comparator (bag-element-comparator bag-bucket)))

  (define ~check-srfi-113-248
    (check (bag-contains? bag-bucket "abc")))

  (define ~check-srfi-113-249
    (check (bag-contains? bag-bucket "ABC")))

  (define ~check-srfi-113-250
    (check "def" (bag-member bag-bucket "DEF" "fqz")))

  (define ~check-srfi-113-251
    (check "fqz" (bag-member bag-bucket "lmn" "fqz")))

  (define ter-nums (bag number-comparator 1 2 3))

  (define ter-nums2 (bag-replace ter-nums 2.0))

  (define ~check-srfi-113-252
    (check (bag-any? inexact? ter-nums2)))

  (define ~check-srfi-113-253
    (check (begin (bag-replace! ter-nums 2.0) (bag-any? inexact? ter-nums))))

  (define bob
    (bag bag-comparator
         (bag eqv-comparator 1 2)
         (bag eqv-comparator 1 2)))

  (define ~check-srfi-113-254
    (check 2 (bag-size bob)))

  (define mybag-bis (bag number-comparator 1 2))

  (define ~check-srfi-113-255
    (check 2 (bag-size mybag-bis)))

  (define ~check-srfi-113-256
    (check 3 (begin
               (bag-adjoin! mybag-bis 1)
               (bag-size mybag-bis))))

  (define ~check-srfi-113-257
    (check 2 (bag-unique-size mybag-bis)))

  (define ~check-srfi-113-258
    (check 2 (begin
                 (bag-delete! mybag-bis 2)
                 (bag-delete! mybag-bis 2)
                 (bag-size mybag-bis))))

  (define ~check-srfi-113-259
    (check 5 (begin
               (bag-increment! mybag-bis 1 3)
               (bag-size mybag-bis))))

  (define ~check-srfi-113-260
    (check (bag-decrement! mybag-bis 1 2)))

  (define ~check-srfi-113-261
    (check 3 (bag-size mybag-bis)))

  (define ~check-srfi-113-262
    (check 0 (begin
               (bag-decrement! mybag-bis 1 5)
               (bag-size mybag-bis))))

  (define multi (bag eqv-comparator 1 2 2 3 3 3))
  (define single (bag eqv-comparator 1 2 3))
  (define singleset (set eqv-comparator 1 2 3))
  (define minibag (bag eqv-comparator 'a 'a))
  (define alist '((a . 2)))

  (define ~check-srfi-113-263
    (check alist (bag->alist minibag)))

  (define ~check-srfi-113-264
    (check (bag=? minibag (alist->bag eqv-comparator alist))))

  (define ~check-srfi-113-265
    (check (set=? singleset (bag->set single))))

  (define ~check-srfi-113-266
    (check (set=? singleset (bag->set multi))))

  (define ~check-srfi-113-267
    (check (bag=? single (set->bag singleset))))

  (define ~check-srfi-113-268
    (check (not (bag=? multi (set->bag singleset)))))

  (define ~check-srfi-113-269
    (check (begin (set->bag! minibag singleset)
                  (bag-contains? minibag 1))))

  (define abb (bag eq-comparator 'a 'b 'b))

  (define aab (bag eq-comparator 'a 'a 'b))

  (define total-ter (bag-sum abb aab))

  (define ~check-srfi-113-270
    (check 3 (bag-count (lambda (x) (eqv? x 'a)) total-ter)))

  (define ~check-srfi-113-271
    (check 3 (bag-count (lambda (x) (eqv? x 'b)) total-ter)))

  (define ~check-srfi-113-272
    (check 12 (bag-size (bag-product 2 total-ter))))

  (define bag1-bis (bag eqv-comparator 1))

  (define ~check-srfi-113-273
    (check 2 (begin (bag-sum! bag1-bis bag1-bis) (bag-size bag1-bis))))

  (define ~check-srfi-113-274
    (check 4 (begin (bag-product! 2 bag1-bis)
                    (bag-size bag1-bis))))

  (define a (set number-comparator 1 2 3))
  (define b (set number-comparator 1 2 4))
  (define aa (bag number-comparator 1 2 3))
  (define bb (bag number-comparator 1 2 4))

  (define ~check-srfi-113-275
    (check (not (=? set-comparator a b))))

  (define ~check-srfi-113-276
    (check (=? set-comparator a (set-copy a))))

  (define ~check-srfi-113-277
    (~check-srfi-113-raise (<? set-comparator a b)))

  (define ~check-srfi-113-278
    (check (not (=? bag-comparator aa bb))))

  (define ~check-srfi-113-279
    (check (=? bag-comparator aa (bag-copy aa))))

  (define ~check-srfi-113-280
    (~check-srfi-113-raise (<? bag-comparator aa bb)))

  (define ~check-srfi-113-281
    (check (not (=? (make-default-comparator) a aa))))

  )

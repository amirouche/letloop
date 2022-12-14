;; This is a regression testing suite for the SRFI-14 char-set
;; library.  Olin Shivers
(library (srfi srfi-14 check)
  (export check-00 check-01 check-02 check-03 check-04 check-05
check-06 check-07 check-08 check-09 check-10 check-11 check-12
check-13 check-14 check-15 check-16 check-17 check-18 check-19
check-20 check-21 check-22 check-23 check-24 check-25 check-26
check-27 check-28 check-29 check-30 check-31 check-32 check-33
check-34 check-35 check-36 check-37 check-38 check-39 check-40
check-41 check-42 check-43 check-44 check-45 check-46 check-47
check-49 check-50 check-51 check-52 check-53 check-54 check-55
check-56 check-57 check-58 check-59 check-60 check-61 check-62
check-63 check-64 check-65 check-66 check-67 check-68 )
  (import (scheme base)
          (scheme char)
          (check)
          (srfi srfi-14))

  (begin

    (define (vowel? c) (member c '(#\a #\e #\i #\o #\u)))

    (define check-00
      (check #f (char-set? 5)))

    (define check-01
      (check #t (char-set? (char-set #\a #\e #\i #\o #\u))))

    (define check-02
      (check #t (char-set=)))

    (define check-03
      (check #t (char-set= (char-set))))

    (define check-04
      (check #t
             (char-set= (char-set #\a #\e #\i #\o #\u)
                        (string->char-set "ioeauaiii"))))

    (define check-05
      (check #f
             (char-set= (char-set #\e #\i #\o #\u)
                        (string->char-set "ioeauaiii"))))

    (define check-06
      (check #t (char-set<=)))

    (define check-07
      (check #t (char-set<= (char-set))))

    (define check-08
      (check #t
             (char-set<= (char-set #\a #\e #\i #\o #\u)
                         (string->char-set "ioeauaiii"))))

    (define check-09
      (check #t
             (char-set<= (char-set #\e #\i #\o #\u)
                         (string->char-set "ioeauaiii"))))

    (define check-10
      (check #t
             (<= 0 (char-set-hash char-set:graphic 100) 99)))

    (define check-11
      (check #t
             (= 4 (char-set-fold (lambda (c i) (+ i 1)) 0
                                 (char-set #\e #\i #\o #\u #\e #\e)))))

    (define check-12
      (check #t
             (char-set<= (string->char-set "eiaou2468013579999")
                         (char-set-unfold null? car cdr '(#\a #\e #\i #\o #\u #\u #\u)
                                          char-set:digit))))
    (define check-13
      (check #t
             (char-set= (string->char-set "eiaou246801357999")
                        (char-set-unfold! null? car cdr '(#\a #\e #\i #\o #\u)
                                          (string->char-set "0123456789")))))

    (define check-14
      (check #f
             (char-set= (string->char-set "eiaou246801357")
                        (char-set-unfold! null? car cdr '(#\a #\e #\i #\o #\u)
                                          (string->char-set "0123456789")))))

    (define check-15
      (check #t
             (let ((cs (string->char-set "0123456789")))
               (char-set-for-each (lambda (c) (set! cs (char-set-delete cs c)))
                                  (string->char-set "02468000"))
               (char-set= cs (string->char-set "97531")))))

    (define check-16
      (check #f
             (let ((cs (string->char-set "0123456789")))
               (char-set-for-each (lambda (c) (set! cs (char-set-delete cs c)))
                                  (string->char-set "02468"))
               (char-set= cs (string->char-set "7531")))))

    (define check-17
      (check #t
             (char-set= (char-set-map char-upcase (string->char-set "aeiou"))
                        (string->char-set "IOUAEEEE"))))

    (define check-18
      (check #f
             (char-set= (char-set-map char-upcase (string->char-set "aeiou"))
                        (string->char-set "OUAEEEE"))))

    (define check-19
      (check #t
             (char-set= (char-set-copy (string->char-set "aeiou"))
                        (string->char-set "aeiou"))))

    (define check-20
      (check #t
             (char-set= (char-set #\x #\y) (string->char-set "xy"))))

    (define check-21
      (check #t
             (not (char-set= (char-set #\x #\y #\z) (string->char-set "xy")))))

    (define check-22
      (check #t
             (char-set= (string->char-set "xy") (list->char-set '(#\x #\y)))))

    (define check-23
      (check #t
             (not (char-set= (string->char-set "axy") (list->char-set '(#\x #\y))))))

    (define check-24
      (check #t
             (char-set= (string->char-set "xy12345")
                        (list->char-set '(#\x #\y) (string->char-set "12345")))))

    (define check-25
      (check #t
             (not (char-set= (string->char-set "y12345")
                             (list->char-set '(#\x #\y) (string->char-set "12345"))))))

    (define check-26
      (check #t
             (char-set= (string->char-set "xy12345")
                        (list->char-set! '(#\x #\y) (string->char-set "12345")))))

    (define check-27
      (check #t
             (not (char-set= (string->char-set "y12345")
                             (list->char-set! '(#\x #\y) (string->char-set "12345"))))))

    (define check-28
      (check #t
             (char-set= (string->char-set "aeiou12345")
                        (char-set-filter vowel? char-set:ascii (string->char-set "12345")))))

    (define check-29
      (check #t
             (not (char-set= (string->char-set "aeou12345")
                             (char-set-filter vowel? char-set:ascii (string->char-set "12345"))))))

    (define check-30
      (check #t
             (char-set= (string->char-set "aeiou12345")
                        (char-set-filter! vowel? char-set:ascii (string->char-set "12345")))))

    (define check-31
      (check #t
             (not (char-set= (string->char-set "aeou12345")
                             (char-set-filter! vowel? char-set:ascii (string->char-set "12345"))))))

    (define check-32
      (check #t
             (char-set= (string->char-set "abcdef12345")
                        (ucs-range->char-set 97 103 #t (string->char-set "12345")))))

    (define check-33
      (check #t
             (not (char-set= (string->char-set "abcef12345")
                             (ucs-range->char-set 97 103 #t (string->char-set "12345"))))))

    (define check-34
      (check #t
             (char-set= (string->char-set "abcdef12345")
                        (ucs-range->char-set! 97 103 #t (string->char-set "12345")))))

    (define check-35
      (check #t
             (not (char-set= (string->char-set "abcef12345")
                             (ucs-range->char-set! 97 103 #t (string->char-set "12345"))))))


    (define check-36
      (check #t
             (char-set= (->char-set #\x)
                        (->char-set "x")
                        (->char-set (char-set #\x)))))

    (define check-37
      (check #t
             (not (char-set= (->char-set #\x)
                             (->char-set "y")
                             (->char-set (char-set #\x))))))

    (define check-38
      (check #t
             (= 10 (char-set-size (char-set-intersection char-set:ascii char-set:digit)))))

    (define check-39
      (check #t
             (= 5 (char-set-count vowel? char-set:ascii))))

    (define check-40
      (check #t
             (equal? '(#\x) (char-set->list (char-set #\x)))))

    (define check-41
      (check #t
             (not (equal? '(#\X) (char-set->list (char-set #\x))))))

    (define check-42
      (check #t
             (equal? "x" (char-set->string (char-set #\x)))))

    (define check-43
      (check #t
             (not (equal? "X" (char-set->string (char-set #\x))))))

    (define check-44
      (check #t
             (char-set-contains? (->char-set "xyz") #\x)))

    (define check-45
      (check #t
             (not (char-set-contains? (->char-set "xyz") #\a))))

    (define check-46
      (check #t
             (char-set-every char-lower-case? (->char-set "abcd"))))

    (define check-47
      (check #t
             (not (char-set-every char-lower-case? (->char-set "abcD")))))

    (define check-48
      (check #t
             (char-set-any char-lower-case? (->char-set "abcd"))))

    (define check-49
      (check #t
             (not (char-set-any char-lower-case? (->char-set "ABCD")))))

    (define check-50
      (check #t
             (char-set= (->char-set "ABCD")
                        (let ((cs (->char-set "abcd")))
                          (let lp ((cur (char-set-cursor cs)) (ans '()))
                            (if (end-of-char-set? cur) (list->char-set ans)
                                (lp (char-set-cursor-next cs cur)
                                    (cons (char-upcase (char-set-ref cs cur)) ans))))))))

    (define check-51
      (check #t
             (char-set= (char-set-adjoin (->char-set "123") #\x #\a)
                        (->char-set "123xa"))))

    (define check-52
      (check #t
             (not (char-set= (char-set-adjoin (->char-set "123") #\x #\a)
                             (->char-set "123x")))))

    (define check-53
      (check #t
             (char-set= (char-set-adjoin! (->char-set "123") #\x #\a)
                        (->char-set "123xa"))))

    (define check-54
      (check #t
             (not (char-set= (char-set-adjoin! (->char-set "123") #\x #\a)
                             (->char-set "123x")))))

    (define check-55
      (check #t
             (char-set= (char-set-delete (->char-set "123") #\2 #\a #\2)
                        (->char-set "13"))))

    (define check-56
      (check #t
             (not (char-set= (char-set-delete (->char-set "123") #\2 #\a #\2)
                             (->char-set "13a")))))

    (define check-57
      (check #t
             (char-set= (char-set-delete! (->char-set "123") #\2 #\a #\2)
                        (->char-set "13"))))

    (define check-58
      (check #t
             (not (char-set= (char-set-delete! (->char-set "123") #\2 #\a #\2)
                             (->char-set "13a")))))

    (define check-59
      (check #t
             (char-set= (char-set-intersection char-set:hex-digit (char-set-complement char-set:digit))
                        (->char-set "abcdefABCDEF"))))

    (define check-60
      (check #t
             (char-set= (char-set-intersection! (char-set-complement! (->char-set "0123456789"))
                                                char-set:hex-digit)
                        (->char-set "abcdefABCDEF"))))

    (define check-61
      (check #t
             (char-set= (char-set-union char-set:hex-digit
                                        (->char-set "abcdefghijkl"))
                        (->char-set "abcdefABCDEFghijkl0123456789"))))

    (define check-62
      (check #t
             (char-set= (char-set-union! (->char-set "abcdefghijkl")
                                         char-set:hex-digit)
                        (->char-set "abcdefABCDEFghijkl0123456789"))))

    (define check-63
      (check #t
             (char-set= (char-set-difference (->char-set "abcdefghijklmn")
                                             char-set:hex-digit)
                        (->char-set "ghijklmn"))))

    (define check-64
      (check #t
             (char-set= (char-set-difference! (->char-set "abcdefghijklmn")
                                              char-set:hex-digit)
                        (->char-set "ghijklmn"))))

    (define check-65
      (check #t
             (char-set= (char-set-xor (->char-set "0123456789")
                                      char-set:hex-digit)
                        (->char-set "abcdefABCDEF"))))

    (define check-66
      (check #t
             (char-set= (char-set-xor! (->char-set "0123456789")
                                       char-set:hex-digit)
                        (->char-set "abcdefABCDEF"))))

    (define check-67
      (check #t
             (call-with-values (lambda ()
                                 (char-set-diff+intersection char-set:hex-digit
                                                             char-set:letter))
               (lambda (d i)
                 (and (char-set= d (->char-set "0123456789"))
                      (char-set= i (->char-set "abcdefABCDEF")))))))

    (define check-68
      (check #t
             (call-with-values (lambda ()
                                 (char-set-diff+intersection!
                                  (char-set-copy char-set:hex-digit)
                                  (char-set-copy char-set:letter)))
               (lambda (d i)
                 (and (char-set= d (->char-set "0123456789"))
                      (char-set= i (->char-set "abcdefABCDEF")))))))

  ))

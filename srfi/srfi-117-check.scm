(library (srfi srfi-117-check)

  (export ~check-srfi-117-000 ~check-srfi-117-001 ~check-srfi-117-002 ~check-srfi-117-003 ~check-srfi-117-004 ~check-srfi-117-005
~check-srfi-117-006 ~check-srfi-117-007 ~check-srfi-117-008 ~check-srfi-117-009 ~check-srfi-117-010 ~check-srfi-117-011 #;~check-srfi-117-012
~check-srfi-117-013 ~check-srfi-117-014 ~check-srfi-117-015 #;~check-srfi-117-016 ~check-srfi-117-017 ~check-srfi-117-018 ~check-srfi-117-019
~check-srfi-117-020 ~check-srfi-117-021 ~check-srfi-117-022 ~check-srfi-117-023 ~check-srfi-117-024 ~check-srfi-117-025 #;~check-srfi-117-026
~check-srfi-117-027 ~check-srfi-117-028 ~check-srfi-117-029 ~check-srfi-117-030 ~check-srfi-117-031 ~check-srfi-117-032 ~check-srfi-117-033)

  (import (scheme base)
          (srfi srfi-117)
          (letloop check))

  (define ~check-srfi-117-000
    (check '(1 1 1) (list-queue-list (make-list-queue '(1 1 1)))))

  (define ~check-srfi-117-001
    (check '(1 2 3) (list-queue-list (list-queue 1 2 3))))

  (define x1bis (list 1 2 3))

  (define x2 (make-list-queue x1bis (cddr x1bis)))

  (define ~check-srfi-117-002
    (check 3 (list-queue-back x2)))

  (define y (list-queue 4 5))

  (define ~check-srfi-117-003
    (check (list-queue? y)))

  (define z (list-queue-append (list-queue 1 2 3) (list-queue 4 5)))

  (define ~check-srfi-117-004
    (check '(1 2 3 4 5) (list-queue-list
                         (list-queue-append (list-queue 1 2 3) (list-queue 4 5)))))

  (define z2 (list-queue-append! (list-queue 1 2 3) (list-queue-copy y)))

  (define ~check-srfi-117-005
    (check '(1 2 3 4 5) (list-queue-list z2)))

  (define ~check-srfi-117-006
    (check 1 (list-queue-front
              (list-queue-append (list-queue 1 2 3) (list-queue 4 5)))))

  (define ~check-srfi-117-007
    (check 5 (list-queue-back
              (list-queue-append (list-queue 1 2 3) (list-queue 4 5)))))

  (define y-008 (list-queue 4 5))
  (define t0 (list-queue-remove-front! y-008))

  (define ~check-srfi-117-008
    (check '(5) (list-queue-list y-008)))

  (define t1 (list-queue-remove-back! y))
  (define t1.bis (list-queue-remove-back! y))

  (define ~check-srfi-117-009
    (check (list-queue-empty? y)))

  (define ~check-srfi-117-010
    (~check-srfi-117-raise (list-queue-remove-front! y)))

  (define ~check-srfi-117-011
    (~check-srfi-117-raise (list-queue-remove-back! y)))

  (define ~check-srfi-117-012
    (check '(1 2 3 4 5) (list-queue-list z)))

  (define ~check-srfi-117-013
    (check '(1 2 3 4 5) (list-queue-remove-all! z2)))

  (define ~check-srfi-117-014
    (check (list-queue-empty? z2)))

  (define t2 (list-queue-remove-all! z))

  (define t3 (list-queue-add-front! z 1))

  (define t4 (list-queue-add-front! z 0))

  (define t5 (list-queue-add-back! z 2))

  (define t6 (list-queue-add-back! z 3))

  (define ~check-srfi-117-015
    (check '(0 1 2 3) (list-queue-list z)))

  (define a (list-queue 1 2 3))

  (define b (list-queue-copy a))

  ;; (define ~check-srfi-117-016
  ;;   (check '(1 2 3) (list-queue-list b)))

  (define t7 (list-queue-add-front! b 0))

  (define ~check-srfi-117-017
    (check '(1 2 3) (list-queue-list a)))

  (define ~check-srfi-117-018
    (check 4 (length (list-queue-list b))))

  (define c (list-queue-concatenate (list a b)))

  (define ~check-srfi-117-019
    (check '(1 2 3 0 1 2 3) (list-queue-list c)))

  (define r (list-queue 1 2 3))

  (define s (list-queue-map (lambda (x) (* x 10)) r))

  (define ~check-srfi-117-020
    (check '(10 20 30) (list-queue-list s)))

  (define t8 (list-queue-map! (lambda (x) (+ x 1)) r))

  (define ~check-srfi-117-021
    (check '(2 3 4) (list-queue-list r)))

  (define sum 0)

  (define t9 (list-queue-for-each (lambda (x) (set! sum (+ sum x))) s))

  (define ~check-srfi-117-022
    (check 60 sum))

  (define n (list-queue 5 6))

  (define t10
    (list-queue-set-list! n (list 1 2)))

  (define ~check-srfi-117-023
    (check '(1 2) (list-queue-list n)))

  (define d (list 1 2 3))

  (define e (cddr d))

  (define f (make-list-queue d e))

  (define-values (dx ex) (list-queue-first-last f))

  (define ~check-srfi-117-024
    (check (eq? d dx)))

  (define ~check-srfi-117-025
    (check (eq? e ex)))

  (define ~check-srfi-117-026
    (check '(1 2 3) (list-queue-list f)))

  (define t11 (list-queue-add-front! f 0))
  (define t12 (list-queue-add-back! f 4))

  (define ~check-srfi-117-027 (check '(0 1 2 3 4) (list-queue-list f)))

  (define g (make-list-queue d e))

  (define ~check-srfi-117-028 (check '(1 2 3 4) (list-queue-list g)))

  (define h (list-queue 5 6))

  (define t13 (list-queue-set-list! h d e))

  (define ~check-srfi-117-029
    (check '(1 2 3 4) (list-queue-list h)))

  (define (double x) (* x 2))
  (define (done? x) (> x 3))
  (define (add1 x) (+ x 1))
  (define x3 (list-queue-unfold done? double add1 0))

  (define ~check-srfi-117-030
    (check '(0 2 4 6) (list-queue-list x3)))

  (define ybis (list-queue-unfold-right done? double add1 0))

  (define ~check-srfi-117-031
    (check '(6 4 2 0) (list-queue-list ybis)))

  (define x0 (list-queue 8))
  (define x1ter (list-queue-unfold done? double add1 0 x0))

  (define ~check-srfi-117-032
    (check '(0 2 4 6 8) (list-queue-list x1ter)))

  (define y0 (list-queue 8))
  (define y1 (list-queue-unfold-right done? double add1 0 y0))

  (define ~check-srfi-117-033
    (check '(8 6 4 2 0) (list-queue-list y1))))

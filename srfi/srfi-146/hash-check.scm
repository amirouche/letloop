;; Copyright (C) Marc Nieper-Wißkirchen (2016, 2017).  All Rights
;; Reserved.

;; Permission is hereby granted, free of charge, to any person
;; obtaining a copy of this software and associated documentation
;; files (the "Software"), to deal in the Software without
;; restriction, including without limitation the rights to use, copy,
;; modify, merge, publish, distribute, sublicense, and/or sell copies
;; of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.
(library (srfi srfi-146 hash-check)
  (export ~check-srfi-146-hash-000 ~check-srfi-146-hash-001 ~check-srfi-146-hash-002 ~check-srfi-146-hash-003 ~check-srfi-146-hash-004 ~check-srfi-146-hash-005
~check-srfi-146-hash-006 ~check-srfi-146-hash-007 ~check-srfi-146-hash-008 ~check-srfi-146-hash-009 ~check-srfi-146-hash-010 ~check-srfi-146-hash-011 ~check-srfi-146-hash-012
~check-srfi-146-hash-013 ~check-srfi-146-hash-014 ~check-srfi-146-hash-015 ~check-srfi-146-hash-016 ~check-srfi-146-hash-017 ~check-srfi-146-hash-018 ~check-srfi-146-hash-019
~check-srfi-146-hash-020 ~check-srfi-146-hash-021 ~check-srfi-146-hash-022 ~check-srfi-146-hash-023 ~check-srfi-146-hash-024 ~check-srfi-146-hash-025 ~check-srfi-146-hash-026
~check-srfi-146-hash-027 ~check-srfi-146-hash-028 ~check-srfi-146-hash-029 ~check-srfi-146-hash-030 ~check-srfi-146-hash-031 ~check-srfi-146-hash-032 ~check-srfi-146-hash-033
~check-srfi-146-hash-034 ~check-srfi-146-hash-035 ~check-srfi-146-hash-036 ~check-srfi-146-hash-037 ~check-srfi-146-hash-038 ~check-srfi-146-hash-039 ~check-srfi-146-hash-040
~check-srfi-146-hash-041 ~check-srfi-146-hash-042 ~check-srfi-146-hash-043 ~check-srfi-146-hash-044 ~check-srfi-146-hash-045 ~check-srfi-146-hash-046 ~check-srfi-146-hash-047
~check-srfi-146-hash-048 ~check-srfi-146-hash-049 ~check-srfi-146-hash-050 ~check-srfi-146-hash-051 ~check-srfi-146-hash-052 ~check-srfi-146-hash-053 ~check-srfi-146-hash-054
~check-srfi-146-hash-055 ~check-srfi-146-hash-056 ~check-srfi-146-hash-057 ~check-srfi-146-hash-058 ~check-srfi-146-hash-059 ~check-srfi-146-hash-060 ~check-srfi-146-hash-061
~check-srfi-146-hash-062 ~check-srfi-146-hash-063 ~check-srfi-146-hash-064 ~check-srfi-146-hash-065 ~check-srfi-146-hash-066 ~check-srfi-146-hash-067 ~check-srfi-146-hash-068
~check-srfi-146-hash-069 ~check-srfi-146-hash-070 ~check-srfi-146-hash-071 ~check-srfi-146-hash-072 ~check-srfi-146-hash-073 ~check-srfi-146-hash-074)

  (import (scheme base)
          (letloop check)
	  (srfi srfi-1)
	  (srfi srfi-8)
	  (srfi srfi-128)
	  (srfi srfi-146 hash))

  (define comparator (make-default-comparator))

  ;; SRFI 146: Hashmaps

  ;; Predicates
  (define hashmap0 (hashmap comparator))
  (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap2 (hashmap comparator 'c 1 'd 2 'e 3))
  (define hashmap3 (hashmap comparator 'd 1 'e 2 'f 3))

  (define ~check-srfi-146-hash-000
    (check #t
	  (hashmap? (hashmap comparator))))

  (define ~check-srfi-146-hash-001
    (check #t
	  (not (hashmap? (list 1 2 3)))))

  (define ~check-srfi-146-hash-002
    (check #t
	  (hashmap-empty? hashmap0)))

  (define ~check-srfi-146-hash-003
    (check #t
	  (not (hashmap-empty? hashmap1))))

  (define ~check-srfi-146-hash-004
    (check #t
	  (hashmap-contains? hashmap1 'b)))

  (define ~check-srfi-146-hash-005
    (check #t
          (not (hashmap-contains? hashmap1 '2))))

  (define ~check-srfi-146-hash-006
    (check #t
          (hashmap-disjoint? hashmap1 hashmap3)))

  (define ~check-srfi-146-hash-007
    (check #t
          (not (hashmap-disjoint? hashmap1 hashmap2))))

  ;; Accessors
  (define hashmap11 (hashmap comparator 'a 1 'b 2 'c 3))

  (define ~check-srfi-146-hash-008
    (check
     2
     (hashmap-ref hashmap11 'b)))

  (define ~check-srfi-146-hash-009
    (check
     42
     (hashmap-ref hashmap11 'd (lambda () 42))))

  ;; TODO: convert to a check
  ;; (~check-srfi-146-hash-error "hashmap-ref: key not found/without failure"
  ;;             (hashmap-ref hashmap1 'd))

  (define ~check-srfi-146-hash-010
    (check
     (* 2 2)
     (hashmap-ref hashmap11 'b (lambda () #f) (lambda (x) (* x x)))))

  (define ~check-srfi-146-hash-011
    (check
     3
     (hashmap-ref/default hashmap11 'c 42)))

  (define ~check-srfi-146-hash-012
    (check
     42
     (hashmap-ref/default hashmap11 'd 42)))

  (define ~check-srfi-146-hash-013
    (check
     comparator
     (hashmap-key-comparator hashmap11)))

  ;; Updaters
  (define hashmap21 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap22 (hashmap-set hashmap21 'c 4 'd 4 'd 5))
  (define hashmap23 (hashmap-update hashmap21 'b (lambda (x) (* x x))))
  (define hashmap24 (hashmap-update/default hashmap21 'd (lambda (x) (* x x)) 4))
  (define hashmap25 (hashmap-adjoin hashmap21 'c 4 'd 4 'd 5))
  (define hashmap20 (hashmap comparator))

  (define ~check-srfi-146-hash-014
    (check
     3
     (hashmap-ref hashmap25 'c)))

  (define ~check-srfi-146-hash-015
    (check
     4
     (hashmap-ref hashmap25 'd)))

  (define ~check-srfi-146-hash-016
    (check
     4
     (hashmap-ref hashmap22 'c)))

  (define ~check-srfi-146-hash-017
    (check
     5
     (hashmap-ref hashmap22 'd)))

  (define ~check-srfi-146-hash-018
    (check
     #f
     (hashmap-ref/default (hashmap-replace hashmap21 'd 4) 'd #f)))

  (define ~check-srfi-146-hash-019
    (check
     6
     (hashmap-ref (hashmap-replace hashmap21 'c 6) 'c)))

  (define ~check-srfi-146-hash-020
    (check
     42
     (hashmap-ref/default (hashmap-delete hashmap21 'b) 'b 42)))

  (define ~check-srfi-146-hash-021
    (check
     42
     (hashmap-ref/default (hashmap-delete-all hashmap21 '(a b)) 'b 42)))

  (define ~check-srfi-146-hash-022
    (check
     (list hashmap21 2)
     (receive result
	 (hashmap-intern hashmap21 'b (lambda () (error "should not have been invoked")))
       result)))

  (define ~check-srfi-146-hash-023
    (check
     (list 42 42)
     (receive (hashmap value)
	 (hashmap-intern hashmap21 'd (lambda () 42))
       (list value (hashmap-ref hashmap 'd)))))

  (define ~check-srfi-146-hash-024
    (check
     4
     (hashmap-ref hashmap23 'b)))

  (define ~check-srfi-146-hash-025
    (check
     16
     (hashmap-ref hashmap24 'd)))

  (define ~check-srfi-146-hash-026
    (check
     'empty
     (hashmap-pop hashmap20 (lambda () 'empty))))

  ;; TODO: convert to a check
  ;; (~check-srfi-146-hash-assert "hashmap-pop: non-empty hashmap"
  ;;   (member
  ;;    (receive (hashmap key value)
  ;;        (hashmap-pop hashmap1)
  ;;      (list (hashmap-size hashmap) key value))
  ;;    '((2 a 1) (2 b 2) (2 c 3)))))

  ;; The whole hashmap
  (define hashmap30 (hashmap comparator))
  (define hashmap31 (hashmap comparator 'a 1 'b 2 'c 3))

  (define ~check-srfi-146-hash-027
    (check
     0
     (hashmap-size hashmap30)))

  (define ~check-srfi-146-hash-028
    (check
     3
     (hashmap-size hashmap31)))

  (define ~check-srfi-146-hash-029
    (check
     (list 'b 2)
     (receive result
	 (hashmap-find (lambda (key value)
			 (and (eq? key 'b)
			      (= value 2)))
		       hashmap31
		       (lambda () (error "should not have been called")))
       result)))

  (define ~check-srfi-146-hash-030
    (check
     (list 42)
     (receive result
	 (hashmap-find (lambda (key value)
			 (eq? key 'd))
		       hashmap31
		       (lambda ()
			 42))
       result)))

  (define ~check-srfi-146-hash-031
    (check
     2
     (hashmap-count (lambda (key value)
		      (>= value 2))
		    hashmap31)))

  (define ~check-srfi-146-hash-032
    (check #t
          (hashmap-any? (lambda (key value)
		          (= value 3))
		        hashmap31)))

  (define ~check-srfi-146-hash-033
    (check #t
          (not (hashmap-any? (lambda (key value)
			       (= value 4))
			     hashmap31))))

  (define ~check-srfi-146-hash-034
    (check #t
          (hashmap-every? (lambda (key value)
		            (<= value 3))
		          hashmap31)))

  (define ~check-srfi-146-hash-035
    (check #t
	  (not (hashmap-every? (lambda (key value)
			         (<= value 2))
			       hashmap31))))

  (define ~check-srfi-146-hash-036
    (check
     3
     (length (hashmap-keys hashmap31))))

  (define ~check-srfi-146-hash-037
    (check
     6
     (fold + 0 (hashmap-values hashmap31))))

  (define ~check-srfi-146-hash-038
    (check
     (list 3 6)
     (receive (keys values)
	 (hashmap-entries hashmap31)
       (list (length keys) (fold + 0 values)))))

  ;; Hashmap and folding
  (define hashmap41 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap42 (hashmap-map (lambda (key value)
				   (values (symbol->string key)
					   (* 10 value)))
			         comparator
			         hashmap41))

  (define ~check-srfi-146-hash-039
    (check
     20
     (hashmap-ref hashmap42 "b")))

  (define ~check-srfi-146-hash-040
    (check
     6
     (let ((counter 0))
       (hashmap-for-each (lambda (key value)
			   (set! counter (+ counter value)))
			 hashmap41)
       counter)))

  (define ~check-srfi-146-hash-041
    (check
     6
     (hashmap-fold (lambda (key value acc)
		     (+ value acc))
		   0
		   hashmap41)))

  (define ~check-srfi-146-hash-042
    (check
     (+ (* 1 1) (* 2 2) (* 3 3))
     (fold + 0 (hashmap-map->list (lambda (key value)
				    (* value value))
				  hashmap41))))

  (define ~check-srfi-146-hash-043
    (check
     2
     (hashmap-size (hashmap-filter (lambda (key value)
				     (<= value 2))
				   hashmap41))))

  (define ~check-srfi-146-hash-044
    (check
     1
     (hashmap-size (hashmap-remove (lambda (key value)
				     (<= value 2))
				   hashmap41))))

  (define ~check-srfi-146-hash-045
    (check
     (list 1 2)
     (receive result
	 (hashmap-partition (lambda (key value)
			      (eq? 'b key))
			    hashmap41)
       (map hashmap-size result))))

  ;; Copying and conversion
  (define hashmap51 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap52 (alist->hashmap comparator '((a . 1) (b . 2) (c . 3))))
  (define hashmap53 (alist->hashmap! (hashmap-copy hashmap51) '((d . 4) '(c . 5))))

  (define ~check-srfi-146-hash-046
    (check
     3
     (hashmap-size (hashmap-copy hashmap51))))

  (define ~check-srfi-146-hash-047
    (check
     comparator
     (hashmap-key-comparator (hashmap-copy hashmap51))))

  (define ~check-srfi-146-hash-048
    (check
     (cons 'b 2)
     (assq 'b (hashmap->alist hashmap51))))

  (define ~check-srfi-146-hash-049
    (check
     2
     (hashmap-ref hashmap52 'b)))

  (define ~check-srfi-146-hash-050
    (check
     4
     (hashmap-ref hashmap53 'd)))

  (define ~check-srfi-146-hash-051
    (check
     3
     (hashmap-ref hashmap53 'c)))

  ;; Subhashmaps

  (define hashmap61 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap62 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap63 (hashmap comparator 'a 1 'c 3))
  (define hashmap64 (hashmap comparator 'a 1 'c 3 'd 4))
  (define hashmap65 (hashmap comparator 'a 1 'b 2 'c 6))
  (define hashmap66 (hashmap (make-comparator (comparator-type-test-predicate comparator)
					      (comparator-equality-predicate comparator)
					      (comparator-ordering-predicate comparator)
					      (comparator-hash-function comparator))
			     'a 1 'b 2 'c 3))

  (define ~check-srfi-146-hash-052
    (check #t
          (hashmap=? comparator hashmap61 hashmap62)))

  (define ~check-srfi-146-hash-053
    (check #t
          (not (hashmap=? comparator hashmap61 hashmap64))))

  (define ~check-srfi-146-hash-054
    (check #t
          (not (hashmap=? comparator hashmap61 hashmap66))))

  (define ~check-srfi-146-hash-055
    (check #t
          (hashmap<? comparator hashmap63 hashmap61)))

  (define ~check-srfi-146-hash-056
    (check #t
          (not (hashmap<? comparator hashmap63 hashmap61 hashmap62))))

  (define ~check-srfi-146-hash-057
    (check #t
          (hashmap>? comparator hashmap62 hashmap63)))

  (define ~check-srfi-146-hash-058
    (check #t
          (not (hashmap>? comparator hashmap61 hashmap62 hashmap63))))

  (define ~check-srfi-146-hash-059
    (check #t
          (hashmap<=? comparator hashmap63 hashmap62 hashmap61)))

  (define ~check-srfi-146-hash-060
    (check #t
          (not (hashmap<=? comparator hashmap63 hashmap65))))

  (define ~check-srfi-146-hash-061
    (check #t
          (not (hashmap<=? comparator hashmap62 hashmap64))))

  (define ~check-srfi-146-hash-062
    (check #t
          (hashmap>=? comparator hashmap64 hashmap63)))

  (define ~check-srfi-146-hash-063
    (check #t
          (not (hashmap>=? comparator hashmap65 hashmap63))))

  ;; Set theory operations
  (define hashmap71 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap72 (hashmap comparator 'a 1 'b 2 'd 4))
  (define hashmap73 (hashmap comparator 'a 1 'b 2))
  (define hashmap74 (hashmap comparator 'a 1 'b 2 'c 4))
  (define hashmap75 (hashmap comparator 'a 1 'c 3))
  (define hashmap76 (hashmap comparator 'd 4 'e 5 'f 6))

  (define ~check-srfi-146-hash-064
    (check
     4
     (hashmap-ref (hashmap-union hashmap71 hashmap72) 'd)))

  (define ~check-srfi-146-hash-065
    (check
     3
     (hashmap-ref (hashmap-union hashmap71 hashmap74) 'c)))

  (define ~check-srfi-146-hash-066
    (check
     6
     (hashmap-size (hashmap-union hashmap71 hashmap72 hashmap76))))

  (define ~check-srfi-146-hash-067
    (check
     3
     (hashmap-ref (hashmap-intersection hashmap71 hashmap74) 'c)))

  (define ~check-srfi-146-hash-068
    (check
     42
     (hashmap-ref/default (hashmap-intersection hashmap71 hashmap75) 'b 42)))

  (define ~check-srfi-146-hash-069
    (check
     2
     (hashmap-size (hashmap-difference hashmap72 hashmap76))))

  (define ~check-srfi-146-hash-070
    (check
     4
     (hashmap-size (hashmap-xor hashmap72 hashmap76))))

  ;; Comparators

  (define hashmap81 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap82 (hashmap comparator 'a 1 'b 2 'c 3))
  (define hashmap83 (hashmap comparator 'a 1 'b 2))
  (define hashmap84 (hashmap comparator 'a 1 'b 2 'c 4))
  (define hashmap85 (hashmap comparator 'a 1 'c 3))
  (define hashmap80 (hashmap comparator
			     hashmap81 "a"
			     hashmap82 "b"
			     hashmap83 "c"
			     hashmap84 "d"
			     hashmap85 "e"))

  (define ~check-srfi-146-hash-071
    (check #t
          (comparator? hashmap-comparator)))

  (define ~check-srfi-146-hash-072
    (check
     (list "a" "a" "c" "d" "e")
     (list (hashmap-ref hashmap80 hashmap81)
	   (hashmap-ref hashmap80 hashmap82)
	   (hashmap-ref hashmap80 hashmap83)
	   (hashmap-ref hashmap80 hashmap84)
	   (hashmap-ref hashmap80 hashmap85)
	   )))

  ;; Ordering comparators
  (define ~check-srfi-146-hash-073
    (check #t
          (=? comparator hashmap81 hashmap82)))

  (define ~check-srfi-146-hash-074
    (check #t
          (not (=? comparator hashmap81 hashmap84)))))

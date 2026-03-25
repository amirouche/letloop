;; Copyright © 2023 Amirouche A. BOUBEKKI <amirouche at hyper dev>
(library (letloop aql lbst)

  (export make-lbst
          lbst?
          lbst-set
          lbst-ref
          lbst-delete
          lbst-length
          lbst-start
          lbst-end
          lbst-next
          lbst-previous
          lbst-key
          lbst-value
          lbst-bytes
          lbst-empty?
          call-with-lbst
          lbst-right
          lbst-left
          lbst-fold
          #;lbst-write

          lbst->alist
          alist->lbst

          ~check-lbst-000
          ~check-lbst-000-set-false
          ~check-lbst-000-set-not-bytevector
          ~check-lbst-001
          ~check-lbst-002
          ~check-lbst-003
          ~check-lbst-004
          ~check-lbst-005
          ~check-lbst-006
          ~check-lbst-007
          ~check-lbst-008
          ~check-lbst-009
          ~check-lbst-009-bis
          ~check-lbst-009-ter
          ~check-lbst-010
          ~check-lbst-011
          ~check-lbst-012
          ~check-lbst-013
          ~check-lbst-013/random
          ~check-lbst-014/random
          ~check-lbst-015/random
          ~check-lbst-016/random
          ~check-lbst-017/random
          ~check-lbst-019/random
          ;; ~check-lbst-020
          ;; ~check-lbst-021
          ;; ~check-lbst-022
          ;; ~check-lbst-022/random
          ;; ~check-lbst-024
          )

  (import (chezscheme)
          (letloop r999)
          (letloop match)
          (letloop byter)
          (letloop aql shims))

  ;; SRFI-1 helpers (formerly from (scheme list))
  (define (fold proc seed lst)
    (if (null? lst)
        seed
        (fold proc (proc (car lst) seed) (cdr lst))))

  (define (take-while pred lst)
    (if (or (null? lst) (not (pred (car lst))))
        '()
        (cons (car lst) (take-while pred (cdr lst)))))

  (define (drop-while pred lst)
    (if (or (null? lst) (not (pred (car lst))))
        lst
        (drop-while pred (cdr lst))))

  (include "letloop/aql/lbst.body.scm")
  (include "letloop/aql/lbst.check.scm")

  )

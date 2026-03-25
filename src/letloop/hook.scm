;; SRFI-173: Hooks
;; https://srfi.schemers.org/srfi-173/srfi-173.html
(library (letloop hook)

  (export make-hook
          hook?
          hook-arity
          hook-add!
          hook-delete!
          hook-reset!
          hook-run
          hook->list
          list->hook
          list->hook!)

  (import (chezscheme))

  (define-record-type (<hook> %make-hook hook?)
    (fields (mutable procs hook-procs hook-procs!)
            (immutable arity hook-arity)))

  (define (make-hook arity)
    (%make-hook '() arity))

  (define (list->hook arity lst)
    (%make-hook lst arity))

  (define (list->hook! hook lst)
    (hook-procs! hook lst))

  (define (hook-add! hook proc)
    (let ((procs (hook-procs hook)))
      (hook-procs! hook (cons proc procs))))

  (define (hook-delete! hook proc)
    (let loop ((procs (hook-procs hook))
               (out '()))
      (unless (null? procs)
        (if (eq? proc (car procs))
            (hook-procs! hook (append (cdr procs) out))
            (loop (cdr procs) (cons (car procs) out))))))

  (define (hook-reset! hook)
    (hook-procs! hook '()))

  (define (hook->list hook)
    (hook-procs hook))

  (define (hook-run hook . args)
    (assert (= (length args) (hook-arity hook)))
    (for-each (lambda (proc) (apply proc args)) (hook-procs hook))))

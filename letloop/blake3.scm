#!chezscheme
(library (letloop blake3)
  (export blake3 make-blake3 blake3-update! blake3-finalize!)
  (import (chezscheme))

  (define libblake3 (load-shared-object "libblake3.so"))

  (define-syntax define-syntax-rule
    (syntax-rules ()
      ((define-syntax-rule (keyword args ...) body)
       (define-syntax keyword
         (syntax-rules ()
           ((keyword args ...) body))))))

  (define (bytevector->pointer bv)
    (#%$object-address bv (+ (foreign-sizeof 'void*) 1)))

  (define-syntax-rule (foreign-procedure* return ptr args ...)
    (foreign-procedure ptr (args ...) return))

  (define blake3-hasher-init
    (let ((func (foreign-procedure* void "blake3_hasher_init" void*)))
      (lambda (hasher)
        (func hasher))))

  (define (make-blake3)
    (define bv (make-bytevector 1912)) ;; sizeof blake3_hasher
    (blake3-hasher-init (bytevector->pointer bv))
    (bytevector->pointer bv))

  (define blake3-update!
    (let ((func (foreign-procedure* void "blake3_hasher_update" void* void* size_t)))
      (lambda (hasher bytevector)
        (func hasher
              (bytevector->pointer bytevector)
              (bytevector-length bytevector)))))

  (define blake3-finalize!
    (let ((func (foreign-procedure* void "blake3_hasher_finalize" void* void* size_t)))
      (lambda (hasher)
        (define bytevector (make-bytevector 32))
        (func hasher (bytevector->pointer bytevector) 32)
        bytevector)))

  (define (blake3 bytevector)
    (define hasher (make-blake3))
    (blake3-update! hasher bytevector)
    (blake3-finalize! hasher)))

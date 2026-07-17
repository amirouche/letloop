#!chezscheme
(library (letloop blake3)
  (export blake3 make-blake3 blake3-update! blake3-finalize blake3-close!
          ~check-blake3-000
          ~check-blake3-001)

  (import (chezscheme) (letloop cffi))

  (define-shared-object libblake3 "libblake3.so" "libblake3.so.1")

  (define-syntax define-syntax-rule
    (syntax-rules ()
      ((define-syntax-rule (keyword args ...) body)
       (define-syntax keyword
         (syntax-rules ()
           ((keyword args ...) body))))))

  (define-syntax-rule (foreign-procedure* return ptr args ...)
    (lazy-foreign-procedure libblake3 ptr (args ...) return))

  (define blake3-hasher-init
    (let ((func (foreign-procedure* void "blake3_hasher_init" void*)))
      (lambda (hasher)
        (func hasher))))

  ;; sizeof(blake3_hasher) is 1912 as of BLAKE3 1.x; allocate headroom
  ;; so a larger struct in a future release does not overflow.
  (define blake3-hasher-size 2048)

  ;; The hasher lives outside the Scheme heap: the moving GC neither
  ;; relocates nor reclaims it, so its address stays valid between
  ;; calls. Call blake3-close! when done with a make-blake3 hasher.
  (define (make-blake3)
    (define hasher (foreign-alloc blake3-hasher-size))
    (blake3-hasher-init hasher)
    hasher)

  (define (blake3-close! hasher)
    (foreign-free hasher))

  (define blake3-update!
    (let ((func (foreign-procedure* void "blake3_hasher_update" void* void* size_t)))
      (lambda (hasher bytevector)
        (with-lock (list bytevector)
          (func hasher
                (bytevector-pointer bytevector)
                (bytevector-length bytevector))))))

  (define blake3-finalize
    (let ((func (foreign-procedure* void "blake3_hasher_finalize" void* void* size_t)))
      (lambda (hasher length)
        (define bytevector (make-bytevector length))
        (with-lock (list bytevector)
          (func hasher (bytevector-pointer bytevector) length))
        bytevector)))

  (define blake3
    (lambda (bytevector)
      (define hasher (make-blake3))
      (blake3-update! hasher bytevector)
      (let ((digest (blake3-finalize hasher 32)))
        (blake3-close! hasher)
        digest)))

  (define ~check-blake3-000
    (lambda ()
      (check-skip-unless libblake3
      (assert (bytevector=? (blake3 (string->utf8 "azul dunith"))
                            (bytevector 147 96 202 209 250 91 234 79 148 175 155 40 42 42 163 180 23 60 5 78 248 205 93 236 132 217 22 253 234 98 73 27))))))

  (define ~check-blake3-001
    (lambda ()
      (check-skip-unless libblake3
      (let ((blake3 (make-blake3)))
        ;; the hasher must survive garbage collections between calls
        (collect (collect-maximum-generation))
        (blake3-update! blake3 (string->utf8 "azul dunith"))
        (collect (collect-maximum-generation))
        (assert (bytevector=? (blake3-finalize blake3 16)
                              (bytevector 147 96 202 209 250 91 234 79 148 175 155 40 42 42 163 180)))
        (blake3-close! blake3)
        #t))))

  (define bytevector-random
    (lambda (n)
      (u8-list->bytevector (map (lambda _ (random 256)) (iota n)))))

  )

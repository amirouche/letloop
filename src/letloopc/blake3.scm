#!chezscheme
(library (letloopc blake3)
  (export blake3 make-blake3 blake3-update! blake3-finalize
          ~check-blake3-000
          ~check-blake3-001
          ~check-blake3-cross-0
          ~check-blake3-cross-1
          ~check-blake3-cross-2)

  (import (chezscheme)
          (prefix (letloop blake3) pure:))

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

  (define blake3-finalize
    (let ((func (foreign-procedure* void "blake3_hasher_finalize" void* void* size_t)))
      (lambda (hasher length)
        (define bytevector (make-bytevector length))
        (func hasher (bytevector->pointer bytevector) length)
        bytevector)))

  (define blake3
    (lambda (bytevector)
      (define hasher (make-blake3))
      (blake3-update! hasher bytevector)
      (blake3-finalize hasher 32)))

  (define ~check-blake3-000
    (lambda ()
      (assert (bytevector=? (blake3 (string->utf8 "azul dunith"))
                            (bytevector 147 96 202 209 250 91 234 79 148 175 155 40 42 42 163 180 23 60 5 78 248 205 93 236 132 217 22 253 234 98 73 27)))))

  (define ~check-blake3-001
    (lambda ()
      (let ((blake3 (make-blake3)))
        (blake3-update! blake3 (string->utf8 "azul dunith"))
        (assert (bytevector=? (blake3-finalize blake3 16)
                              (bytevector 147 96 202 209 250 91 234 79 148 175 155 40 42 42 163 180))))))

  (define bytevector-random
    (lambda (n)
      (u8-list->bytevector (map (lambda _ (random 256)) (iota n)))))

  ;; Cross-verify: one-shot hash, small input
  (define ~check-blake3-cross-0
    (lambda ()
      (random-seed 42)
      (let ((input (bytevector-random 64)))
        (assert (bytevector=? (blake3 input)
                              (pure:blake3 input))))))

  ;; Cross-verify: one-shot hash, large input (>1 chunk = 1024 bytes)
  (define ~check-blake3-cross-1
    (lambda ()
      (random-seed 7)
      (let ((input (bytevector-random 2048)))
        (assert (bytevector=? (blake3 input)
                              (pure:blake3 input))))))

  ;; Cross-verify: incremental update and variable output length
  (define ~check-blake3-cross-2
    (lambda ()
      (random-seed 99)
      (let ((part1 (bytevector-random 100))
            (part2 (bytevector-random 200)))
        ;; Incremental FFI
        (let ((h (make-blake3)))
          (blake3-update! h part1)
          (blake3-update! h part2)
          (let ((ffi-result (blake3-finalize h 64)))
            ;; Incremental pure
            (let ((hp (pure:make-blake3)))
              (pure:blake3-update! hp part1)
              (pure:blake3-update! hp part2)
              (let ((pure-result (pure:blake3-finalize hp 64)))
                (assert (bytevector=? ffi-result pure-result)))))))))

  )

#!chezscheme
(library (letloop blake3)
  (export blake3 make-blake3 blake3-update! blake3-finalize blake3-close!
          ~check-blake3-000
          ~check-blake3-001
          ~check-blake3-002/c-agrees-with-scheme)

  (import (chezscheme) (letloop cffi)
          (prefix (letloop blake3 scheme) scheme:))

  (define-shared-object libblake3 "libblake3.so" "libblake3.so.1")

  (define-syntax define-syntax-rule
    (syntax-rules ()
      ((define-syntax-rule (keyword args ...) body)
       (define-syntax keyword
         (syntax-rules ()
           ((keyword args ...) body))))))

  (define-syntax-rule (foreign-procedure* return ptr args ...)
    (lazy-foreign-procedure libblake3 ptr (args ...) return))

  (define c-hasher-init
    (let ((func (foreign-procedure* void "blake3_hasher_init" void*)))
      (lambda (hasher)
        (func hasher))))

  ;; sizeof(blake3_hasher) is 1912 as of BLAKE3 1.x; allocate headroom
  ;; so a larger struct in a future release does not overflow.
  (define blake3-hasher-size 2048)

  ;; The hasher lives outside the Scheme heap: the moving GC neither
  ;; relocates nor reclaims it, so its address stays valid between
  ;; calls. Call blake3-close! when done with a make-blake3 hasher.
  (define (c-make-blake3)
    (define hasher (foreign-alloc blake3-hasher-size))
    (c-hasher-init hasher)
    hasher)

  (define (c-close! hasher)
    (foreign-free hasher))

  (define c-update!
    (let ((func (foreign-procedure* void "blake3_hasher_update" void* void* size_t)))
      (lambda (hasher bytevector)
        (with-lock (list bytevector)
          (func hasher
                (bytevector-pointer bytevector)
                (bytevector-length bytevector))))))

  (define c-finalize
    (let ((func (foreign-procedure* void "blake3_hasher_finalize" void* void* size_t)))
      (lambda (hasher length)
        (define bytevector (make-bytevector length))
        (with-lock (list bytevector)
          (func hasher (bytevector-pointer bytevector) length))
        bytevector)))

  ;; Which implementation to use, decided once and then fixed for the
  ;; process. It has to be fixed: a hasher from one path is an opaque
  ;; foreign pointer and from the other an ordinary Scheme object, so
  ;; whatever made it must also update and finalize it.
  ;;
  ;; Decided by trying, not by asking whether the shared object can be
  ;; dlopen'd: on a statically linked letloop the symbols are
  ;; registered by letloop-main.c and work while no dlopen ever could.
  ;; The Scheme implementation is the floor, so a missing or broken
  ;; libblake3 costs speed and nothing else -- which is what keeps
  ;; hashing, and so the whole store, from depending on a package the
  ;; store would have to have built.
  (define c-usable?
    (let ((state 'unknown))
      (lambda ()
        (when (eq? state 'unknown)
          (set! state
                (guard (ex (#t #f))
                  (let ((hasher (c-make-blake3)))
                    (c-update! hasher (string->utf8 "probe"))
                    (c-finalize hasher 8)
                    (c-close! hasher)
                    #t))))
        state)))

  (define (make-blake3)
    (if (c-usable?) (c-make-blake3) (scheme:make-blake3)))

  (define (blake3-close! hasher)
    (if (c-usable?) (c-close! hasher) (scheme:blake3-close! hasher)))

  (define (blake3-update! hasher bytevector)
    (if (c-usable?)
        (c-update! hasher bytevector)
        (scheme:blake3-update! hasher bytevector)))

  (define (blake3-finalize hasher length)
    (if (c-usable?)
        (c-finalize hasher length)
        (scheme:blake3-finalize hasher length)))

  (define blake3
    (lambda (bytevector)
      (define hasher (make-blake3))
      (blake3-update! hasher bytevector)
      (let ((digest (blake3-finalize hasher 32)))
        (blake3-close! hasher)
        digest)))

  ;; No skip guard any more: hashing works with or without libblake3,
  ;; because the Scheme implementation is the floor. If this fails, both
  ;; paths are wrong.
  (define ~check-blake3-000
    (lambda ()
      (assert (bytevector=? (blake3 (string->utf8 "azul dunith"))
                            (bytevector 147 96 202 209 250 91 234 79 148 175 155 40 42 42 163 180 23 60 5 78 248 205 93 236 132 217 22 253 234 98 73 27)))))

  (define ~check-blake3-001
    (lambda ()
      (let ((blake3 (make-blake3)))
        ;; the hasher must survive garbage collections between calls
        (collect (collect-maximum-generation))
        (blake3-update! blake3 (string->utf8 "azul dunith"))
        (collect (collect-maximum-generation))
        (assert (bytevector=? (blake3-finalize blake3 16)
                              (bytevector 147 96 202 209 250 91 234 79 148 175 155 40 42 42 163 180)))
        (blake3-close! blake3)
        #t)))

  ;; The two implementations must agree, on data neither was written
  ;; against. Only meaningful where the shared object is present --
  ;; without it both sides of the comparison are the same code.
  (define ~check-blake3-002/c-agrees-with-scheme
    (lambda ()
      (if (not (c-usable?))
          (begin (display "** SKIP: libblake3 unavailable, nothing to cross-check\n") #t)
          (let loop ((n 0))
            (if (fx=? n 16)
                #t
                (let ((input (bytevector-random (* n 997))))
                  (let ((from-c (let ((h (c-make-blake3)))
                                  (c-update! h input)
                                  (let ((d (c-finalize h 32))) (c-close! h) d)))
                        (from-scheme (scheme:blake3 input)))
                    (assert (bytevector=? from-c from-scheme))
                    (loop (fx+ n 1)))))))))

  (define bytevector-random
    (lambda (n)
      (u8-list->bytevector (map (lambda _ (random 256)) (iota n)))))

  )

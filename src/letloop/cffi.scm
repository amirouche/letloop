#!chezscheme
(library (letloop cffi)
  (export call-with-errno with-errno with-lock strerror bytevector-pointer
          define-shared-object lazy-foreign-procedure shared-object-available?
          check-skip-unless)
  (import (chezscheme))

  ;; (define-shared-object libfoo "libfoo.so.1" "libfoo.so") defines
  ;; LIBFOO as a memoized thunk that dlopens the first candidate that
  ;; loads, or raises a &error naming every candidate tried. Nothing is
  ;; loaded until the thunk is called, so merely importing a binding
  ;; library does not require the shared object to be installed.
  (define-syntax define-shared-object
    (syntax-rules ()
      ((_ name soname ...)
       (define name
         (let ((loaded #f))
           (lambda ()
             (unless loaded
               (set! loaded
                     (or (guard (c (#t #f)) (load-shared-object soname) 'soname)
                         ...
                         (error 'name "cannot dlopen shared object, tried" soname ...))))
             loaded))))))

  ;; Like foreign-procedure, except the shared object is dlopen'd, and
  ;; the foreign symbol resolved, on first call instead of at library
  ;; load. SHARED-OBJECT is a thunk defined with define-shared-object.
  ;; Optional calling conventions (__collect_safe ...) go between the
  ;; shared object and the symbol name.
  (define-syntax lazy-foreign-procedure
    (lambda (stx)
      (syntax-case stx ()
        ((_ shared-object conv ... name (type ...) result)
         (string? (syntax->datum #'name))
         (with-syntax (((arg ...) (generate-temporaries #'(type ...))))
           #'(let ((func #f))
               (lambda (arg ...)
                 (unless func
                   (shared-object)
                   (set! func (foreign-procedure conv ... name (type ...) result)))
                 (func arg ...))))))))

  (define (shared-object-available? shared-object)
    (guard (c (#t #f)) (shared-object) #t))

  ;; For ~check-* procedures over optional shared objects: run BODY, or
  ;; print a SKIP note and pass when the shared object is unavailable.
  (define-syntax check-skip-unless
    (syntax-rules ()
      ((_ shared-object body ...)
       (if (shared-object-available? shared-object)
           (begin body ...)
           (begin
             (display "** SKIP: missing shared object for ")
             (display 'shared-object)
             (newline)
             ;; the check runner counts void or #f as FAILED
             #t)))))

  (define-syntax call-with-errno
    (syntax-rules ()
      ((_ thunk proc)
       (let ((out #f)
             (errno #f))

         ;; Chez GC must be disabled or it could stomp on errno.
         ;;
         ;; See:
         ;;
         ;;   https://github.com/cisco/ChezScheme/issues/550
         ;;
         (with-interrupts-disabled
          (set! out (thunk))
          (set! errno (#%$errno)))
         (proc out errno)))))
  
  (define-syntax with-errno
    (syntax-rules ()
      ((_ e)
       (let ((out #f)
             (errno #f))
         ;; Chez GC must be disabled or it could stomp on errno.
         ;;
         ;; See:
         ;;
         ;;   https://github.com/cisco/ChezScheme/issues/550
         ;;
         (with-interrupts-disabled
          (set! out e)
          (set! errno (#%$errno)))
         (proc out errno)))))

  (define-syntax with-lock
    (syntax-rules ()
      ((_ objects body ...)
       (let ((objects* objects))
         (for-each lock-object objects*)
         (call-with-values (lambda () body ...)
           (lambda out
             (for-each unlock-object objects*)
             (apply values out)))))))

  (define (bytevector-pointer bv)
    ;; TODO: understand what the + 1 increment does
    (#%$object-address bv (+ (foreign-sizeof 'void*) 1)))

  (define stdlib (load-shared-object #f))

  (define strerror
    (let ((func (foreign-procedure "strerror" (int) string)))
      (lambda (code)
        (func code))))
  )

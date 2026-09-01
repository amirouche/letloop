#!chezscheme
(library (letloop cffi)
  (export call-with-errno with-errno with-lock strerror bytevector-pointer
          define-shared-object lazy-foreign-procedure shared-object-available?
          check-skip-unless ensure-self-loaded!)
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
  ;;
  ;; Tries a bare foreign-procedure lookup before ever calling
  ;; shared-object: on a statically-linked letloop, dlopen cannot work
  ;; at all (see src/letloop/store/README.md's Issues section) -- not
  ;; even a NAMED dlopen of a real .so file, confirmed empirically
  ;; against musl ("Dynamic loading not supported"). letloop-main.c
  ;; pre-registers the symbols a static build needs via Sforeign_symbol
  ;; (independent of dlopen), so the plain lookup already succeeds
  ;; there and shared-object is never reached. On a dynamic build,
  ;; where nothing is pre-registered for an optional library's own
  ;; symbols, the plain lookup fails cleanly and falls back to
  ;; dlopen'ing shared-object exactly as before.
  (define-syntax lazy-foreign-procedure
    (lambda (stx)
      (syntax-case stx ()
        ((_ shared-object conv ... name (type ...) result)
         (string? (syntax->datum #'name))
         (with-syntax (((arg ...) (generate-temporaries #'(type ...))))
           #'(let ((func #f))
               (lambda (arg ...)
                 (unless func
                   (set! func (guard (ex (#t (shared-object)
                                             (foreign-procedure conv ... name (type ...) result)))
                                (foreign-procedure conv ... name (type ...) result))))
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
         (dynamic-wind
           (lambda () (for-each lock-object objects*))
           (lambda () body ...)
           (lambda () (for-each unlock-object objects*)))))))

  (define (bytevector-pointer bv)
    ;; TODO: understand what the + 1 increment does
    (#%$object-address bv (+ (foreign-sizeof 'void*) 1)))

  ;; (load-shared-object #f) -- dlopen(NULL, ...), "hand me the main
  ;; program's own handle" -- is how nearly every (foreign-procedure
  ;; ...) call in this codebase reaches ordinary libc functions: this
  ;; is the one eager, unconditional call (cffi.scm is imported almost
  ;; everywhere) that every OTHER file's bare foreign-procedure calls,
  ;; with no load-shared-object of their own, ride on as a
  ;; process-wide side effect. There is no dynamic linker to service
  ;; dlopen(NULL, ...) in a statically-linked binary, so it fails
  ;; there, and Chez's own error-formatting code for that failure
  ;; crashes on the NULL path it was given (see
  ;; src/letloop/store/README.md's Issues section for the full trace).
  ;;
  ;; letloop_self_dlopen_safe is always registered by letloop-main.c's
  ;; CUSTOM_INIT hook (via Sforeign_symbol, independent of dlopen), and
  ;; reports whether dlopen(NULL, ...) actually works in THIS process --
  ;; probed once in C, before any Scheme runs, so this never has to
  ;; risk the crash to find out. Not found at all (guard below) means
  ;; a plain `scheme`/`petite` with no letloop-main.c registration --
  ;; e.g. the child process `letloop compile` spawns to do the actual
  ;; compilation -- which is always dynamically linked, hence safe.
  ;; When it IS registered and says unsafe, load-shared-object is
  ;; skipped, and everything that used to ride on this call instead
  ;; needs its own entry in letloop-main.c's small, hand-audited
  ;; registration table.
  (define ensure-self-loaded!
    (let ((done #f))
      (lambda ()
        (unless done
          (set! done #t)
          (let ((unsafe? (guard (ex (#t #f))
                            (fx=? ((foreign-procedure "letloop_self_dlopen_safe" () int)) 0))))
            (unless unsafe?
              (load-shared-object #f)))))))

  (define strerror
    (let ((func (foreign-procedure "strerror" (int) string)))
      (lambda (code)
        (func code))))

  (ensure-self-loaded!)
  )

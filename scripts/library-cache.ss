#!chezscheme
;; Compile every library under a source tree in one pass, so that each of
;; them ends up with both a .so and a .wpo.
;;
;;   scheme --script scripts/library-cache.ss SOURCE OBJECT OPTIMIZE-LEVEL
;;
;; This is what lets `letloop compile` fold letloop's own libraries into
;; a user program. compile-whole-program needs a .wpo for every library
;; it folds; a boot image carries only final code, no .wpo, so the
;; sources ship alongside letloop with a .wpo each.
;;
;; The cache is per optimize level, and OBJECT is expected to name a
;; directory per level: a .wpo compiled at one level does not carry the
;; code the next one wants. Measured on the HTTP benchmark, folding out
;; of a level 0 cache into a level 3 program gave 401k req/s against
;; 456k for a level 3 cache -- the entire benefit, silently forfeited.
;;
;; It also has to be one pass: .wpo files from separate compilations do
;; not agree, and mixing them fails with "does not define expected
;; compilation instance of library".
;;
;; Run it with upstream scheme, never with letloop: a library that is
;; already defined in the process shadows its own source and is never
;; recompiled, so no .wpo would be written for it.
(import (chezscheme))

(define ftw
  (lambda (directory)
    (let loop ((paths (map (lambda (x) (string-append directory "/" x))
                           (directory-list directory)))
               (out '()))
      (if (null? paths)
          out
          (if (file-directory? (car paths))
              (loop (append (ftw (car paths)) (cdr paths)) out)
              (loop (cdr paths) (cons (car paths) out)))))))

(define string-suffix?
  (lambda (suffix string)
    (let ((n (string-length suffix))
          (m (string-length string)))
      (and (fx<= n m)
           (string=? suffix (substring string (fx- m n) m))))))

(define library?
  (lambda (filepath)
    (any (lambda (extension) (string-suffix? (car extension) filepath))
         (library-extensions))))

(define any
  (lambda (predicate? objects)
    (and (pair? objects)
         (or (predicate? (car objects))
             (any predicate? (cdr objects))))))

(define library-name
  ;; The name in (library (name ...) ...), or #f for anything else: the
  ;; tree also holds include fragments such as NAME.check.scm.
  (lambda (filepath)
    (and (library? filepath)
         (guard (ex (else #f))
           (let ((sexp (call-with-input-file filepath read)))
             (and (pair? sexp)
                  (eq? (car sexp) 'library)
                  (pair? (cdr sexp))
                  (list? (cadr sexp))
                  (cadr sexp)))))))

(define arguments
  (let ((arguments (command-line-arguments)))
    (unless (fx= (length arguments) 3)
      (display "usage: scheme --script scripts/library-cache.ss SOURCE OBJECT OPTIMIZE-LEVEL\n"
               (current-error-port))
      (exit 1))
    arguments))

(define directory (car arguments))
(define object (cadr arguments))
(define level (string->number (caddr arguments)))

(unless (and level (<= 0 level 3))
  (format (current-error-port) "not an optimize level: ~a\n" (caddr arguments))
  (exit 1))

(library-directories (list (cons directory object)))
(source-directories (list directory))

(optimize-level level)
(generate-wpo-files #t)
(compile-imported-libraries #t)
(generate-inspector-information #f)
(generate-interrupt-trap #f)

(let loop ((filepaths (ftw directory))
           (cached '())
           (skipped '()))
  (if (null? filepaths)
      (begin
        (format #t "* Cached ~a libraries at optimize-level ~a under ~a\n"
                (length cached) level object)
        (unless (null? skipped)
          ;; Not fatal: a library that fails to compile here simply has no
          ;; .wpo, and `letloop compile` reports it by name when a program
          ;; imports it.
          (format #t "* Could not compile ~a libraries, they will not fold:\n" (length skipped))
          (for-each (lambda (x) (format #t "** ~s\n" (car x))) (reverse skipped)))
        (flush-output-port)
        (exit 0))
      (let ((name (library-name (car filepaths))))
        (if (not name)
            (loop (cdr filepaths) cached skipped)
            ;; Chez raises compile-time warnings as continuable
            ;; conditions, so a guard here would unwind and write off a
            ;; library that merely warns. Hand warnings back to the
            ;; default handler, which prints them and carries on.
            (call/1cc
             (lambda (k)
               (with-exception-handler
                   (lambda (ex)
                     (if (warning? ex)
                         (raise-continuable ex)
                         (k (loop (cdr filepaths)
                                  cached
                                  (cons (cons name ex) skipped)))))
                 (lambda ()
                   (eval '#t (environment name))
                   (loop (cdr filepaths) (cons name cached) skipped)))))))))

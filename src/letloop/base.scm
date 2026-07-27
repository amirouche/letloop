#!chezscheme
(library (letloop base)
  (export letloop-main letloop-compile letloop-exec letloop-repl letloop-check letloop-review)
  (import (chezscheme) (letloop match) (letloop cli base) (letloop root) (letloop review)
          (only (letloop http server) transparent))

  (define pk
    (lambda args
      (when (getenv "LETLOOP_DEBUG")
        (display ";; " (current-error-port))
        (write args (current-error-port))
        (newline (current-error-port))
        (flush-output-port (current-error-port)))
      (car (reverse args))))

  (meta define (pk* . args)
        (display ";;; " (current-error-port))
        (write args (current-error-port))
        (newline (current-error-port))
        (flush-output-port (current-error-port))
        (car (reverse args)))

  (meta define read-string
        (lambda (p)
          (let loop ([x (read-char p)]
                     [out '()])
            (if (eof-object? x)
                (begin (close-input-port p)
                       (list->string (reverse out)))
                (loop (read-char p)
                      (cons x out))))))

  (meta define (run/output command)
        (call-with-values (lambda ()
                            (open-process-ports command 'line (current-transcoder)))
          (lambda (stdin stdout stderr pid)
            (read-string stdout))))

  (define (make-filepath filepath)
    (cond
     ((string=? filepath ".") (current-directory))
     ((char=? (string-ref filepath 0) #\/) filepath)
     (else (string-append (current-directory) "/" filepath))))

  (meta define basename
        (lambda (string)
          (let loop ((index (string-length string)))
            (if (char=? (string-ref string (- index 1)) #\/)
                (substring string index (string-length string))
                (loop (- index 1))))))

  (meta define dirname
        (lambda (out)
          (substring out 0 (- (string-length out)
                              (string-length (basename out))))))

  (meta define scheme-binarypath
        (lambda ()
          (let* ((out (if (getenv "SCHEME")
                          (string-append (dirname (getenv "SCHEME"))
                                         "/"
                                         (run/output (format #f "readlink -n ~a" (getenv "SCHEME"))))
                          (run/output "readlink -n /proc/self/exe"))))
            (dirname out))))

  (meta define binarypath->scheme-home
        (lambda (scheme what)
          (format #f "~a/~a" scheme what)))

  #;(meta define binarypath->scheme-home
        (lambda (scheme what)
          (call/cc
           (lambda (k)
             (for-each
              (lambda (path)
                (call-with-values (lambda () (scheme-version-number))
                  (lambda args
                    (let* ((version (let loop ((args args)
                                               (out '()))
                                      (if (null? args)
                                          (apply string-append (reverse (cdr out)))
                                          (loop (cdr args)
                                                (cons* "."
                                                       (number->string (car args))
                                                       out)))))
                           (prefix (run/output (format #f "realpath $(ls -d ~a/../lib/csv~a*) | tr -d '\n'" path version))))
                      (let ((out (format #f "~a/~a/~a" prefix (machine-type) what)))
                        (when (file-exists? out)
                          (k out)))))))
              (list scheme "/usr/local/bin/" "/usr/bin/"))))))

  (define-syntax include-chez-file
    (lambda (x)
      (syntax-case x ()
        [(k filename)
         (let* ([fn (datum filename)]
                [fn (binarypath->scheme-home (scheme-binarypath) fn)])
           (with-syntax ([exp (get-bytevector-all (open-file-input-port fn))])
             #'exp))])))

  (define filepath->bytevector
    (lambda (filepath)
      (define port (open-file-input-port filepath))
      (define out (get-bytevector-all port))
      (close-port port)
      out))

  (define-syntax include-filename-as-string
    (lambda (x)
      (syntax-case x ()
        [(k filename)
         (let ([fn (datum filename)])
           (with-syntax ([exp (read-string (open-input-file fn))])
             #'exp))])))

  (define (string-join strings)
    (let loop ((strings strings)
               (out '()))
      (if (null? strings)
          (apply string-append (reverse out))
          (loop (cdr strings) (cons* " " (car strings) out)))))

  (define letloop-usage.md (include-filename-as-string "./src/letloop-usage.md"))

  ;; Include git commit

  (define-syntax include-git-describe
    (lambda (x)
      (syntax-case x ()
        ((k)
         (with-syntax ([exp (run/output "git describe --always --tags --dirty")])
           #'exp)))))

  (define-syntax include-scheme-version
    (lambda (x)
      (syntax-case x ()
        ((k)
         (with-syntax ((exp (scheme-version))
                       (pre-release (scheme-pre-release)))
           (if #'pre-release
               (string-append #'exp "-pre-release-" (number->string #'pre-release))
               #'exp))))))

  (define letloop-scheme-version (include-scheme-version))

  (define-syntax include-git-branch
    (lambda (x)
      (syntax-case x ()
        [(k)
         (let ([fn (datum filename)])
           (with-syntax ([exp (run/output "git branch --show-current")])
             #'exp))])))

  (define-syntax include-git-head
    (lambda (x)
      (syntax-case x ()
        [(k)
         (let ([fn (datum filename)])
           (with-syntax ((exp (run/output "git rev-parse --short HEAD")))
             #'exp))])))

  ;; Include some files

  (define letloop-tag (let ((describe (include-git-describe))
                           (branch (include-git-branch)))
                        (if (and (fxzero? (string-length describe))
                                 (fxzero? (string-length branch)))
                            (include-git-head)
                            (string-append (if (string=? branch "")
                                               ;; when the action checkout a tag,
                                               ;; according to git there is no branch
                                               "main"
                                               (substring branch 0 (fx- (string-length branch) 1)))
                                           "-"
                                           (substring describe 0 (fx- (string-length describe) 1))))))

  (define-syntax include-date
    (lambda (x)
      (syntax-case x ()
        [(k)
         (let ([fn (datum filename)])
           (with-syntax ([exp (run/output "date +\"%Y-%m-%dT%H:%M:%S%z\"")])
             #'exp))])))

  (define scheme-binarypath*
    ;; it is redefined to avoid the scary:
    ;;
    ;;   Exception: attempt to reference out-of-phase identifier
    ;;   scheme-binarypath.
    ;;
    ;; It is only used when preparing a letloop release, when
    ;; letloop-compile is executed with upstream scheme, hence no
    ;; petite.boot, scheme.boot, letloop.boot symbols were
    ;; registred. See the procedure petite.boot-fallback, the file
    ;; letloop-main.c
    (lambda ()

      (define read-string
        (lambda (p)
          (let loop ([x (read-char p)]
                     [out '()])
            (if (eof-object? x)
                (begin (close-input-port p)
                       (list->string (reverse out)))
                (loop (read-char p)
                      (cons x out))))))

      (define basename
        (lambda (string)
          (let loop ((index (string-length string)))
            (if (char=? (string-ref string (- index 1)) #\/)
                (substring string index (string-length string))
                (loop (- index 1))))))

      (define dirname
        (lambda (out)
          (substring out 0 (- (string-length out)
                              (string-length (basename out))))))

      (define (run/output command)
        (call-with-values (lambda ()
                            (open-process-ports command 'line (current-transcoder)))
          (lambda (stdin stdout stderr pid)
            (read-string stdout))))

      (let* ((out (if (getenv "SCHEME")
                      (string-append (dirname (getenv "SCHEME"))
                                     "/"
                                     (run/output (format #f "readlink -n ~a" (getenv "SCHEME"))))
                      (run/output "readlink -n /proc/self/exe"))))
        (dirname out))))

  (define LETLOOP_DEBUG (getenv "LETLOOP_DEBUG"))

  (define dev!
    (lambda (active?)
      (when active?
        (compile-profile 'source)
        (optimize-level 0)
        (debug-level 3))
      (import-notify active?)
      (generate-allocation-counts active?)
      (generate-covin-files active?)
      (generate-inspector-information active?)
      (generate-instruction-counts active?)
      (generate-interrupt-trap active?)
      (generate-procedure-source-information active?)
      (generate-profile-forms active?)
      (debug-on-exception active?)))

  (define disable-garbage-collector!
    (lambda (active?)
      (when active?
        (collect-request-handler void))))

  (define (maybe-display-errors-then-exit errors)
    (let ((errors (errors (eof-object))))
      (unless (null? errors)
        (display "* Ooops :|")
        (newline)
        (for-each (lambda (x) (display "** ") (display x) (newline)) (reverse errors))
        (exit 1))))

  (define and=> (lambda (v proc) (and v (proc v))))

  (define (string-suffix? s1 s2)

    (define (%string-suffix-length s1 start1 end1 s2 start2 end2)
      (let* ((delta (min (- end1 start1) (- end2 start2)))
             (start1 (- end1 delta)))

        (if (and (eq? s1 s2) (= end1 end2))		; EQ fast path
            delta
            (let lp ((i (- end1 1)) (j (- end2 1)))	; Regular path
              (if (or (< i start1)
                      (not (char=? (string-ref s1 i)
                                   (string-ref s2 j))))
                  (- (- end1 i) 1)
                  (lp (- i 1) (- j 1)))))))

    (define (%string-suffix? s1 start1 end1 s2 start2 end2)
      (let ((len1 (- end1 start1)))
        (and (<= len1 (- end2 start2))	; Quick check
             (= len1 (%string-suffix-length s1 start1 end1
                                            s2 start2 end2)))))
    (let ((start1 0)
          (end1 (string-length s1))
          (start2 0)
          (end2 (string-length s2)))

      (%string-suffix? s1 start1 end1 s2 start2 end2)))

  (define any
    (lambda (p? os)
      (memq #t (map p? os))))

  (define maybe-library?
    (lambda (filepath)
      (any (lambda (x) (string-suffix? x filepath))
           (map car (library-extensions)))))

  (define display-condition!
    (lambda (procedure ex)
      (format (current-error-port) "Procedure ~a: " procedure)
      (display-condition ex)
      (newline (current-error-port))))

  (define call-with-warnings-ignored
    ;; Chez raises compile-time warnings as continuable conditions, so a
    ;; guard around a compile catches them, unwinds, and writes off a
    ;; library that merely warns -- which silently drops it from the boot
    ;; image. Hand warnings back to the default handler, which prints
    ;; them and carries on, and escape only for a serious condition.
    (lambda (thunk failure)
      (call/1cc
       (lambda (k)
         (with-exception-handler
             (lambda (ex)
               (if (warning? ex)
                   (raise-continuable ex)
                   (k (failure ex))))
           thunk)))))

  (define maybe-library-name
    (lambda (filename)
      (pk '*maybe-library-name filename)
      (if (not (maybe-library? filename))
          #f
          (and=> (guard (ex (else #f))
                   (call-with-input-file filename read))
                 (lambda (sexp) (and=> (match sexp
                                         ((library (,name ...) ,body ...) name)
                                         (,_ #f))
                                       (lambda (name)
                                         (call-with-warnings-ignored
                                          (lambda ()
                                            (pk '***environmnet name)
                                            (and (eval '#t (environment name)) name))
                                          (lambda (ex)
                                            (display-condition! '**maybe-library-name ex)
                                            #f)))))))))

  (define extract-library-name
    (lambda (import-spec)
      (match import-spec
        ((for ,lib-ref ,_ ...) (extract-library-name lib-ref))
        ((only ,lib-ref ,_ ...) (extract-library-name lib-ref))
        ((except ,lib-ref ,_ ...) (extract-library-name lib-ref))
        ((prefix ,lib-ref ,_) (extract-library-name lib-ref))
        ((rename ,lib-ref ,_ ...) (extract-library-name lib-ref))
        ((,name ...) name)
        (,_ #f))))

  (define library-imports
    (lambda (filename)
      (guard (ex (else '()))
        (call-with-input-file filename
          (lambda (port)
            (let ((sexp (read port)))
              (match sexp
                ((library (,_ ...) (export ,_ ...) (import ,imports ...) ,_ ...)
                 (filter pair? (map extract-library-name imports)))
                (,_ '()))))))))

  (define topological-sort-libraries
    (lambda (discovered)
      ;; discovered: list of (root . filepath) pairs
      ;; Returns list sorted in dependency-first order (leaves first)
      (let* ((entries
              (let loop ((disc discovered) (out '()))
                (if (null? disc)
                    (reverse out)
                    (let ((name (maybe-library-name (cdr (car disc)))))
                      (if name
                          (loop (cdr disc) (cons (cons name (car disc)) out))
                          (loop (cdr disc) out))))))
             ;; entries: list of (library-name root . filepath)
             (known-names (map car entries))
             ;; Build deps map: for each entry, compute local deps
             (deps-map
              (map (lambda (entry)
                     (let* ((name (car entry))
                            (filepath (cddr entry))
                            (imports (library-imports filepath))
                            (local-deps (filter (lambda (imp)
                                                  (member imp known-names))
                                                imports)))
                       (cons name local-deps)))
                   entries)))
        ;; DFS topological sort
        (let ((visited '())
              (result '()))
          (define visit
            (lambda (name)
              (unless (member name visited)
                (set! visited (cons name visited))
                (let ((dep-entry (assoc name deps-map)))
                  (when dep-entry
                    (for-each visit (cdr dep-entry))))
                (set! result (cons name result)))))
          (for-each (lambda (entry) (visit (car entry))) entries)
          ;; result has last-visited first; reverse for dependency-first order
          (let ((sorted-names (reverse result)))
            (map (lambda (name)
                   (cdr (assoc name entries)))
                 sorted-names))))))

  (define ftw
    (lambda (directory)
      (let loop ((paths (map (lambda (x) (string-append directory "/" x)) (directory-list directory)))
                 (out '()))
        (if (null? paths)
            out
            (if (file-directory? (car paths))
                (loop (append (ftw (car paths)) (cdr paths))
                      out)
                (loop (cdr paths) (cons (car paths) out)))))))

  (define (guess string)
    (cond
     ((file-directory? string) (values 'directory (make-filepath string)))
     ((file-exists? string)
      (values 'file (make-filepath string)))
     ;; the first char is a dot, the associated path is neither a file
     ;; or directory, hence it is prolly an extension... breaks when the
     ;; user made a typo in a file or directory name.
     ((char=? (string-ref string 0) #\.)
      (values 'extension string))
     (else (values 'unknown string))))

  (define (make-temporary-directory prefix)

    (define stdlib (load-shared-object #f))

    (define mkdtemp
      (foreign-procedure "mkdtemp" (string) string))

    (let ((input (string-append prefix "-XXXXXX")))
      (mkdtemp input)))

  (define timestamp
    (lambda ()
      (number->string (time-second (current-time)))))

  (define make-accumulator
    (lambda ()
      (let ((out '()))
        (lambda (object)
          (if (eof-object? object)
              out
              (set! out (cons object out)))))))

  (define letloop-program.c (include-filename-as-string "./src/letloop-program.c"))
  (define scheme.h (include-chez-file "scheme.h"))
  (define kernel.o (include-chez-file "kernel.o"))

  (define basename-without-extension
    (lambda (filename)
      (let loop ((index (string-length filename)))
        (if (char=? (string-ref filename (- index 1)) #\.)
            (substring filename 0 (- index 1))
            (loop (- index 1))))))

  (define letloop-discover-libraries
    (lambda ()
      (define root+filepaths (apply append (map (lambda (root) (map (lambda (f) (cons (car root) f)) (ftw (car root))))
                                                (library-directories))))
      (filter (lambda (root+filepath) (maybe-library-name (pk 'discover (cdr root+filepath)))) root+filepaths)))

  (define make-char-predicate
    (lambda (char)
      (lambda (object)
        (char=? char object))))

  (define .so
    (lambda (x)
      (string-append (basename-without-extension x) ".so")))

  (define maybe-compile-file*
    (lambda (f)
      (call-with-warnings-ignored
       (lambda () (maybe-compile-file f))
       (lambda (ex) (display-condition! 'maybe-compile-file* ex) (void)))))

  (define (system* command)
    (unless (fxzero? (system command))
      (error 'letloop "System command failed" command)))

  (define import-procedure?
    (lambda (library-name main)
      (guard (ex (else (display-condition! 'import-procedure? ex) #f))
        (procedure? (eval main (environment library-name))))))

  (define .wpo
    (lambda (x)
      (string-append (basename-without-extension x) ".wpo")))

  ;; Runtime counterparts of the meta helpers near the top of this
  ;; library: those only exist at expand time, and scheme-binarypath*
  ;; keeps private copies to stay clear of out-of-phase identifiers.

  (define basename*
    (lambda (filepath)
      (let loop ((index (string-length filepath)))
        (cond
         ((fxzero? index) filepath)
         ((char=? (string-ref filepath (fx- index 1)) #\/)
          (substring filepath index (string-length filepath)))
         (else (loop (fx- index 1)))))))

  (define dirname*
    (lambda (filepath)
      (substring filepath 0 (fx- (string-length filepath)
                                 (string-length (basename* filepath))))))

  (define string-prefix?
    (lambda (x y)
      (let ((n (string-length x)))
        (and (fx<= n (string-length y))
             (let loop ((index 0))
               (or (fx= index n)
                   (and (char=? (string-ref x index) (string-ref y index))
                        (loop (fx+ index 1)))))))))

  (define directory-list*
    (lambda (directory)
      (guard (ex (else '()))
        (directory-list directory))))

  (define executable-path
    ;; The real path of the running binary.
    ;;
    ;; This cannot be shelled out to: /proc/self/exe resolves against
    ;; whichever process reads it, so `readlink /proc/self/exe` in a
    ;; subprocess dutifully reports the subprocess.
    (let ((cached #f))
      (lambda ()
        (unless cached
          (set! cached
                (guard (ex (else #f))
                  (let* ((stdlib (load-shared-object #f))
                         (readlink (foreign-procedure "readlink" (string u8* uptr) iptr))
                         (buffer (make-bytevector 4096))
                         (count (readlink "/proc/self/exe" buffer (bytevector-length buffer))))
                    (and (fx> count 0)
                         (let ((out (make-bytevector count)))
                           (bytevector-copy! buffer 0 out 0 count)
                           (utf8->string out)))))))
        cached)))

  (define executable-directory
    ;; The directory holding the running binary, with a trailing slash.
    (lambda ()
      (and=> (executable-path) dirname*)))

  (define boot-directory
    ;; Where petite.boot and scheme.boot are installed. Chez looks for
    ;; boot files in %x:%x/../lib/csv%v/%m:%x/../../boot/%m, where %x is
    ;; the directory of the executable, but it never tells anyone which
    ;; one it picked. letloop has to name them itself, because it passes
    ;; them to the pristine child with -b.
    (lambda ()
      (define machine (symbol->string (machine-type)))
      (define csv
        (lambda (lib)
          (map (lambda (x) (string-append lib x "/" machine "/"))
               (filter (lambda (x) (string-prefix? "csv" x))
                       (directory-list* lib)))))
      (define candidates
        (let ((exe (or (executable-directory) ""))
              (scheme (guard (ex (else "")) (scheme-binarypath*))))
          (filter (lambda (x) (not (fxzero? (string-length x))))
                  (append (let ((given (getenv "LETLOOP_BOOT_DIRECTORY")))
                            (if given (list (string-append given "/")) '()))
                          (list exe scheme)
                          (csv (string-append exe "../lib/"))
                          (csv (string-append exe "../../lib/"))
                          (list (string-append exe "../../boot/" machine "/"))))))
      (let loop ((candidates candidates))
        (cond
         ((null? candidates) #f)
         ((and (file-exists? (string-append (car candidates) "petite.boot"))
               (file-exists? (string-append (car candidates) "scheme.boot")))
          (car candidates))
         (else (loop (cdr candidates)))))))

  (define letloop-library-directory
    ;; Where letloop's own sources are installed, $LETLOOP_PREFIX/lib/letloop,
    ;; holding src/ and the per-optimize-level object caches under obj/.
    ;;
    ;; A user program can only fold a (letloop ...) library into itself if
    ;; that library's .wpo is at hand, and a boot image carries none, so
    ;; the sources ship. Returns #f when letloop was never installed, in
    ;; which case the source tree has to be named on the command line.
    (lambda ()
      (define candidates
        (let ((exe (or (executable-directory) "")))
          (append (let ((prefix (getenv "LETLOOP_PREFIX")))
                    (if prefix (list (string-append prefix "/lib/letloop")) '()))
                  (map (lambda (up) (string-append exe up "lib/letloop"))
                       (list "" "../" "../../" "../../../")))))
      (let loop ((candidates candidates))
        (cond
         ((null? candidates) #f)
         ((file-directory? (string-append (car candidates) "/src")) (car candidates))
         (else (loop (cdr candidates)))))))

  (define writable-directory?
    (lambda (directory)
      (guard (ex (else #f))
        (let ((probe (string-append directory "/.letloop-probe")))
          (call-with-port (open-file-output-port probe (file-options replace))
            (lambda (port) (put-u8 port 108)))
          (delete-file probe)
          #t))))

  (define read-library-name
    ;; The name in (library (name ...) ...), read without importing the
    ;; library. maybe-library-name validates by importing, which the
    ;; amalgamating path must not do: it deliberately leaves every
    ;; library out of this process so the child can compile them.
    (lambda (filename)
      (and (maybe-library? filename)
           (and=> (guard (ex (else #f))
                    (call-with-input-file filename read))
                  (lambda (sexp)
                    (match sexp
                      ((library (,name ...) ,body ...) name)
                      (,_ #f)))))))

  (define letloop-compile
    (lambda (arguments)

      (define temporary-directory
        (let ()
          (system* "mkdir -p /tmp/letloop/")
          (let ((out (make-temporary-directory "/tmp/letloop/compile")))
            (system* (format #f "mkdir -p ~a" out))
            out)))

      (define pointer->bytevector
        (lambda (pointer length)
          ;; Copy a memory region starting at POINTER of LENGTH into a
          ;; bytevector.
          (let ((out (make-bytevector length)))
            (let loop ((index length))
              (unless (fxzero? index)
                (let ((index (fx- index 1)))
                  (bytevector-u8-set! out index (foreign-ref 'unsigned-8 pointer index))
                  (loop index))))
            out)))

      (define boot-file
        ;; Used when no C host registered the boot images as symbols,
        ;; which is the case both when bootstrapping with upstream scheme
        ;; and when letloop is installed as a boot file next to them.
        (lambda (name)
          (bytevector->u8-list
           (get-bytevector-all
            (open-file-input-port
             (string-append (or (boot-directory)
                                (string-append (scheme-binarypath*) "/"))
                            name))))))

      (define petite.boot-fallback (lambda () (boot-file "petite.boot")))

      (define scheme.boot-fallback (lambda () (boot-file "scheme.boot")))

      ;; Read on demand: several megabytes each, and a build that only
      ;; produces a boot file never needs them.

      (define petite.boot
        (lambda ()
          (guard (ex (else (petite.boot-fallback)))
            (let ((boot-size (foreign-entry "petite-boot-size"))
                  (boot (foreign-entry "petite-boot")))
              (bytevector->u8-list (pointer->bytevector boot boot-size))))))

      (define scheme.boot
        (lambda ()
          (guard (ex (else (scheme.boot-fallback)))
            (let ((boot-size (foreign-entry "scheme-boot-size"))
                  (boot (foreign-entry "scheme-boot")))
              (bytevector->u8-list (pointer->bytevector boot boot-size))))))

      (define letloop.boot
        ;; The boot image holding letloop's own libraries, so that a
        ;; program built with --visible-libraries can still import them at
        ;; run time. It comes from the C host that registered it as a
        ;; symbol, or -- now that letloop ships as a boot file itself --
        ;; from disk, next to petite.boot.
        (lambda ()
          (or (guard (ex (else #f))
                (let* ((boot-size (foreign-entry "letloop-boot-size"))
                       (boot (foreign-entry "letloop-boot"))
                       (out (bytevector->u8-list (pointer->bytevector boot boot-size))))
                  (and (pair? out) out)))
              (guard (ex (else '()))
                (boot-file "letloop.boot")))))

      ;; parse ARGUMENTS, and set the following variables:

      (define extensions '())
      (define directories '())
      (define main #f)
      (define library.scm #f)
      (define dev? #f)
      (define disable-garbage-collector? #f)
      (define optimize-level* 0)
      (define optimize-level-given? #f)
      (define visible-libraries? #f)
      (define boot #f)
      (define extra '())
      (define sorted-discovered #f)

      (define errors (make-accumulator))

      (define program.scm (string-append temporary-directory "/program.scm"))
      (define build.scm (string-append temporary-directory "/build.scm"))
      (define whole.so (string-append temporary-directory "/whole.so"))
      (define program.boot (string-append temporary-directory "/program.boot"))

      (define massage-standalone!
        (lambda (standalone)
          (unless (null? standalone)
            (call-with-values (lambda () (guess (car standalone)))
              (lambda (type string*)
                (case type
                  (directory (set! directories (cons string* directories)))
                  (extension (set! extensions (cons string* extensions)))
                  (file (set! library.scm string*))
                  (unknown (set! main string*)))))
            (massage-standalone! (cdr standalone)))))

      (define massage-keywords!
        (lambda (keywords)
          (unless (null? keywords)
            (let ((keyword (car keywords)))
              (cond
               ((and (eq? (car keyword) '--dev) (not (string? (cdr keyword))))
                (set! dev? #t))
               ((and (eq? (car keyword) '--disable-garbage-collector) (not (string? (cdr keyword))))
                (set! disable-garbage-collector? #t))
               ((and (eq? (car keyword) '--visible-libraries) (not (string? (cdr keyword))))
                (set! visible-libraries? #t))
               ((and (eq? (car keyword) '--boot) (string? (cdr keyword)))
                (set! boot (cdr keyword)))
               ((and (eq? (car keyword) '--optimize-level)
                     (string->number (cdr keyword))
                     (<= 0 (string->number (cdr keyword)) 3))
                (set! optimize-level-given? #t)
                (set! optimize-level* (string->number (cdr keyword))))
               (else (errors (format #f "Dubious keyword: ~a" (car keyword))))))
            (massage-keywords! (cdr keywords)))))

      (define build-boot-file/visible-libraries
        ;; What letloop has always done: compile every library found under
        ;; the given directories, then concatenate the objects into a boot
        ;; file. The libraries stay importable at run time, which letloop
        ;; itself needs for exec, repl and check. The price is that every
        ;; library is its own compilation unit, so no call between two of
        ;; them can ever be inlined.
        (lambda ()

          (unless (null? directories)
            ;; XXX: override existing library directories, in particular the current
            ;; directory.
            (library-directories directories)
            (source-directories directories))

          (optimize-level optimize-level*)

          (unless (null? extensions)
            (library-extensions (append extensions (library-extensions))))

          (dev! dev?)
          (disable-garbage-collector! disable-garbage-collector?)

          (generate-wpo-files #t)
          (compile-imported-libraries #f)

          (set! sorted-discovered (topological-sort-libraries (letloop-discover-libraries)))
          (for-each maybe-compile-file* (map cdr sorted-discovered))

          (unless (and (pk 'main main)
                       (pk 'library.scm (maybe-library-name (pk 'mylibrary library.scm)))
                       (pk 'import? (import-procedure? (maybe-library-name (pk 'import library.scm))
                                                       (string->symbol main))))
            (format #t "There is something wrong!")
            (flush-output-port)
            (exit 1))

          (call-with-output-file program.scm
            (lambda (port)
              (write '(suppress-greeting #t) port)
              (write `(import ,(pk library.scm (maybe-library-name library.scm))) port)
              (when disable-garbage-collector?
                (write '(collect-request-handler void) port))
              (write `(scheme-start ,(string->symbol main)) port)) 'truncate)
          (maybe-compile-file program.scm)

          (apply make-boot-file
                 program.boot
                 (list "scheme" "petite")
                 (append (filter file-exists? (map .so (map cdr sorted-discovered)))
                         (list (.so program.scm))))))

      (define build-boot-file/whole-program
        ;; Compile the program and every library it imports as one
        ;; compilation unit, so that calls across library boundaries can
        ;; be inlined.
        ;;
        ;; This cannot happen in this process. A library that is already
        ;; defined here shadows its own source, so it is never recompiled
        ;; and no .wpo file is produced for it -- and every (letloop ...)
        ;; library is already defined, they arrive with the boot image.
        ;; compile-whole-program then has nothing to fold, and it does not
        ;; complain: it reports the libraries it gave up on through its
        ;; return value and carries on. That is what silently produced an
        ;; unamalgamated binary before. So: re-exec ourselves with only
        ;; petite.boot and scheme.boot registered, and make the child
        ;; treat a non-empty return value as fatal.
        (lambda ()

          (define library-name
            (or (read-library-name library.scm)
                (begin
                  (format (current-error-port)
                          "* Ooops :|\n** Not a library: ~a\n" library.scm)
                  (exit 1))))

          (define letloop-src
            (and=> (letloop-library-directory)
                   (lambda (x) (string-append x "/src"))))

          (define letloop-obj
            ;; Objects and .wpo files are cached per optimize level,
            ;; because a .wpo compiled at one level does not carry the
            ;; code the next one wants: folding letloop's libraries out
            ;; of a level 0 cache into a level 3 program measured
            ;; 401k req/s against 456k for a level 3 cache -- the whole
            ;; benefit of amalgamating, silently forfeited.
            (and=> (letloop-library-directory)
                   (lambda (x)
                     (let ((out (format #f "~a/obj/~a" x optimize-level*)))
                       (system* (format #f "mkdir -p ~a" out))
                       (if (writable-directory? out)
                           out
                           ;; A prefix nobody may write to: compile into
                           ;; the build directory instead, correct but
                           ;; paid for on every build.
                           (let ((out (string-append temporary-directory "/obj")))
                             (system* (format #f "mkdir -p ~a" out))
                             out))))))

          (define forms
            `(,@(if (null? directories)
                    ;; Leave Chez's defaults, which include the current
                    ;; directory.
                    '()
                    ;; XXX: as elsewhere, the given directories replace
                    ;; them outright.
                    `((library-directories ',directories)
                      (source-directories ',directories)))
              ,@(if (and letloop-src (not (member letloop-src directories)))
                    ;; Last, so that a source tree passed on the command
                    ;; line wins over the sources letloop ships.
                    `((library-directories (append (library-directories)
                                                   (list (cons ,letloop-src ,letloop-obj))))
                      (source-directories (append (source-directories) (list ,letloop-src))))
                    '())
              ,@(if (null? extensions)
                    '()
                    `((library-extensions (append ',extensions (library-extensions)))))
              (optimize-level ,optimize-level*)
              (generate-wpo-files #t)
              (compile-imported-libraries #t)
              ;; The release settings dev! applies when it is handed #f;
              ;; the child never runs dev! itself.
              (generate-inspector-information ,dev?)
              (generate-interrupt-trap ,dev?)
              (generate-procedure-source-information ,dev?)
              (generate-allocation-counts ,dev?)
              (generate-instruction-counts ,dev?)
              ,@(if dev? '((compile-profile 'source) (debug-level 3)) '())
              (compile-program ,program.scm)
              (unless (file-exists? ,(.wpo program.scm))
                (errorf 'letloop "compile-program wrote no .wpo file: ~a" ,(.wpo program.scm)))
              (let ((left (compile-whole-program ,(.wpo program.scm) ,whole.so #f)))
                (unless (null? left)
                  (errorf 'letloop
                          (string-append
                           "these libraries were left out of the program: ~s.~%"
                           "compile-whole-program needs a .wpo file next to every library it folds, "
                           "and a boot image does not carry one. Pass the directory holding their "
                           "sources, or reinstall letloop so that its own sources and .wpo files "
                           "are available.")
                          left)))
              (make-boot-file ,program.boot '("scheme" "petite") ,whole.so)))

          (define exe (or (executable-path)
                          (begin
                            (format (current-error-port)
                                    "* Ooops :|\n** Cannot read /proc/self/exe, needed to spawn the compiler.\n")
                            (exit 1))))

          (define boot-directory*
            (or (boot-directory)
                (begin
                  (format (current-error-port)
                          "* Ooops :|\n** Cannot find petite.boot and scheme.boot near ~a.\n" exe)
                  (format (current-error-port)
                          "** Set LETLOOP_BOOT_DIRECTORY, or compile with --visible-libraries.\n")
                  (exit 1))))

          (when (foreign-entry? "petite-boot")
            ;; A letloop whose boot images are linked into a C program:
            ;; its main registers them and ignores -b, so it cannot give
            ;; the child an empty library environment.
            (format (current-error-port)
                    "* Ooops :|\n** This letloop cannot compile whole programs: its boot images are\n")
            (format (current-error-port)
                    "** linked into the executable. Reinstall it with `make letloop`, or\n")
            (format (current-error-port)
                    "** compile with --visible-libraries.\n")
            (exit 1))

          (call-with-output-file program.scm
            (lambda (port)
              ;; A real top-level program, import first:
              ;; compile-whole-program rejects loose top-level forms.
              (display "#!chezscheme\n" port)
              (for-each (lambda (form) (pretty-print form port))
                        `((import (chezscheme) ,library-name)
                          (suppress-greeting #t)
                          ,@(if disable-garbage-collector?
                                '((collect-request-handler void))
                                '())
                          (scheme-start ,(string->symbol main)))))
            'truncate)

          (call-with-output-file build.scm
            (lambda (port)
              (display "#!chezscheme\n" port)
              (pretty-print
               `(guard (ex (else (display "* Ooops :|\n" (current-error-port))
                                 (display "** " (current-error-port))
                                 (display-condition ex (current-error-port))
                                 (newline (current-error-port))
                                 ;; The condition names the generated
                                 ;; program, which means nothing to
                                 ;; anyone on its own.
                                 (format (current-error-port)
                                         "** while compiling ~s of ~a, starting at ~s\n"
                                         ',library-name ,library.scm ',(string->symbol main))
                                 (flush-output-port (current-error-port))
                                 (exit 1)))
                  ,@forms)
               port)
              (pretty-print '(exit 0) port))
            'truncate)

          (system*
           (pk (format #f "~a -b ~apetite.boot -b ~ascheme.boot --quiet --script ~a"
                       exe boot-directory* boot-directory* build.scm)))))

      (define link-executable!
        (lambda (letloop.boot*)
          (call-with-output-file (string-append temporary-directory "/my-letloop-program.c")
            (lambda (port)
              (format port letloop-program.c
                      (petite.boot)
                      (scheme.boot)
                      letloop.boot*
                      (bytevector->u8-list
                       (get-bytevector-all (open-file-input-port program.boot)))))
            'truncate)

          (let loop ((todo (list
                            (cons kernel.o "/kernel.o")
                            (cons scheme.h "/scheme.h"))))
            (unless (null? todo)
              (call-with-port (open-file-output-port
                               (string-append temporary-directory (cdar todo))
                               (file-options replace))
                (lambda (port)
                  (put-bytevector port (caar todo))))
              (loop (cdr todo))))

          (system*
           (pk
            (format #f "cc -I ~a/ -march=native ~a/my-letloop-program.c ~a/kernel.o -o a.out -ldl -lm -luuid -lpthread ~a"
                    temporary-directory temporary-directory temporary-directory
                    (string-join extra))))
          (display "Produced: ./a.out\n")))

      (call-with-values (lambda () (cli-read arguments))
        (lambda (keywords standalone extra*)
          (massage-standalone! standalone)
          (massage-keywords! keywords)
          (set! extra extra*)))

      (unless main
        (errors "The procedure to start is missing, e.g: letloop compile my-library.scm main"))

      (unless library.scm
        (errors "The library to compile is missing, e.g: letloop compile my-library.scm main"))

      (when (and dev? optimize-level-given?)
        (errors "--dev sets its own optimize level, it cannot be combined with --optimize-level"))

      (maybe-display-errors-then-exit errors)

      (if visible-libraries?
          (build-boot-file/visible-libraries)
          (build-boot-file/whole-program))

      (if boot
          (begin
            (call-with-port (open-file-output-port boot (file-options replace))
              (lambda (port)
                (put-bytevector port
                                (get-bytevector-all (open-file-input-port program.boot)))))
            (format #t "Produced: ~a\n" boot)
            ;; A boot image needs no C compiler, and an amalgamated one
            ;; runs as it stands. Chez starts the boot file that goes by
            ;; the name of the executable, so a copy or hardlink of the
            ;; scheme binary is the whole program -- which is how letloop
            ;; itself is installed.
            (let ((name (basename-without-extension (basename* boot))))
              (format #t "Start it by naming the scheme binary ~a, beside ~a, petite.boot and scheme.boot~%"
                      name (basename* boot))))
          (link-executable! (if visible-libraries? (letloop.boot) '())))))

  (define letloop-compile* (lambda () (letloop-compile (command-line-arguments))))

  (define (letloop-exec arguments)

    ;; parse ARGUMENTS, and set the following variables:

    (define extensions '())
    (define directories '())
    (define dev? #f)
    (define disable-garbage-collector? #f)
    (define optimize-level* 0)
    (define extra '())
    (define program.scm #f)
    (define library.scm #f)
    (define main #f)

    (define errors (make-accumulator))

    (define massage-standalone!
      (lambda (standalone)
        (unless (null? standalone)
          (call-with-values (lambda () (guess (car standalone)))
            (lambda (type string*)
              (case type
                (directory (set! directories (cons string* directories)))
                (extension (set! extensions (cons string* extensions)))
                (file (if library.scm
                          (errors (format #f "Already registred a library to execute, maybe remove: ~a" (car standalone)))
                          (set! library.scm string*)))
                (unknown (if main
                             (errors (format #f "Already registred a main procedure, maybe remove: ~a" (car standalone)))
                             (set! main string*))))))
          (massage-standalone! (cdr standalone)))))

    (define massage-keywords!
      (lambda (keywords)
        (unless (null? keywords)
          (let ((keyword (car keywords)))
            (cond
             ((and (eq? (car keyword) '--dev) (not (string? (cdr keyword))))
              (set! dev? #t))
             ((and (eq? (car keyword) '--disable-garbage-collector) (not (string? (cdr keyword))))
              (set! disable-garbage-collector? #t))
             ((and (eq? (car keyword) '--optimize-level)
                   (string->number (cdr keyword))
                   (<= 0 (string->number (cdr keyword)) 3))
              (set! optimize-level* (string->number (cdr keyword))))
             (else (errors (format #f "Dubious keyword: ~a" (car keyword))))))
          (massage-keywords! (cdr keywords)))))

    (call-with-values (lambda () (cli-read arguments))
      (lambda (keywords standalone extra*)
        (massage-standalone! standalone)
        (massage-keywords! keywords)
        (set! extra extra*)))

    (maybe-display-errors-then-exit errors)

    (unless (null? directories)
      (library-directories directories)
      (source-directories directories))

    (when optimize-level*
      (optimize-level optimize-level*))

    (unless (null? extensions)
      (library-extensions (append extensions (library-extensions))))

    (dev! dev?)
    (disable-garbage-collector! disable-garbage-collector?)

    (dynamic-wind
        (lambda () (void))
        (lambda () (let ((exp (cons (string->symbol main) extra))
                         (env (environment (maybe-library-name library.scm))))
                     (pk 'to 'exec exp env)
                     (eval exp env)))
        (lambda ()
          (when dev?
            (profile-dump-html)))))

  (define (letloop-http-serve arguments)

    ;; letloop http serve [--port=PORT] [DIRECTORY ...] LIBRARY.SCM
    ;;
    ;; LIBRARY.SCM must export three procedures:
    ;;   (application) → app state, called once
    ;;   (context app client req) → per-connection state
    ;;   (dispatch app state method path params req)
    ;;     → (values status (body . content-type) extra-headers)

    (define extensions '())
    (define directories '())
    (define library.scm #f)
    (define port-number 8080)

    (define errors (make-accumulator))

    (define massage-standalone!
      (lambda (standalone)
        (unless (null? standalone)
          (call-with-values (lambda () (guess (car standalone)))
            (lambda (type string*)
              (case type
                (directory (set! directories (cons string* directories)))
                (extension (set! extensions (cons string* extensions)))
                (file (if library.scm
                          (errors (format #f "Already registred a library to serve, maybe remove: ~a" (car standalone)))
                          (set! library.scm string*)))
                (unknown (errors (format #f "Dubious argument: ~a" (car standalone)))))))
          (massage-standalone! (cdr standalone)))))

    (define massage-keywords!
      (lambda (keywords)
        (unless (null? keywords)
          (let ((keyword (car keywords)))
            (cond
             ((and (eq? (car keyword) '--port)
                   (string? (cdr keyword))
                   (string->number (cdr keyword))
                   (<= 1 (string->number (cdr keyword)) 65535))
              (set! port-number (string->number (cdr keyword))))
             (else (errors (format #f "Dubious keyword: ~a" (car keyword))))))
          (massage-keywords! (cdr keywords)))))

    (call-with-values (lambda () (cli-read arguments))
      (lambda (keywords standalone extra*)
        (massage-standalone! standalone)
        (massage-keywords! keywords)
        (unless (null? extra*)
          (errors (format #f "No extra arguments expected after --, maybe remove: ~a" extra*)))))

    (unless library.scm
      (errors "The library to serve is missing, e.g: letloop http serve my-web-library.scm"))

    (maybe-display-errors-then-exit errors)

    (unless (null? directories)
      (library-directories directories)
      (source-directories directories))

    (unless (null? extensions)
      (library-extensions (append extensions (library-extensions))))

    (let* ((library-name (maybe-library-name library.scm))
           (exports (eval `(library-exports ',library-name) (environment '(chezscheme)))))
      (for-each
       (lambda (procedure)
         (unless (memq procedure exports)
           (errors (format #f "Library ~a does not export the procedure: ~a" library-name procedure))))
       '(application context dispatch))
      (maybe-display-errors-then-exit errors)
      (let ((env (environment library-name)))
        (transparent port-number
                     (eval 'application env)
                     (eval 'context env)
                     (eval 'dispatch env)))))

  (define (letloop-http arguments)
    (if (null? arguments)
        (begin
          (display "Choose: serve.\nAs of yet, only: letloop http serve [--port=PORT] [DIRECTORY ...] LIBRARY.SCM\n")
          (exit 1))
        (case (string->symbol (car arguments))
          ((serve) (letloop-http-serve (cdr arguments)))
          (else (display "A typo? Almost, try: letloop http serve ...\n") (exit 1)))))

  (define letloop-check
    (lambda (arguments)

      (define errors (make-accumulator))

      (define fail-fast? #f)
      (define dry-run? #f)
      (define disable-garbage-collector? #f)
      (define extensions '())
      (define directories '())
      (define files '())
      (define alloweds '())

      (define massage-keywords!
        (lambda (keywords)
          (unless (null? keywords)
            (case (caar keywords)
              (--fail-fast (set! fail-fast? #t))
              (--dry-run (set! dry-run? #t))
              (--disable-garbage-collector (set! disable-garbage-collector? #t))
              (else (errors (format #f "Unknown keywords: ~a" (caar keywords))))))))

      (define massage-standalone!
        (lambda (standalone)
          (unless (null? standalone)
            (call-with-values (lambda () (guess (car standalone)))
              (lambda (type string*)
                (case type
                  (directory (set! directories (cons string* directories)))
                  (extension (set! extensions (cons string* extensions)))
                  (file (set! files (cons string* files)))
                  (unknown (errors (format #f "Unknown flying object: ~a" (car standalone)))))))
            (massage-standalone! (cdr standalone)))))

      (define (maybe-library-exports library-name)
        (guard (ex (else (display-condition! 'maybe-library-exports ex) #f))
          (eval `(library-exports ',library-name) (environment '(chezscheme) library-name))))

      (define maybe-read-library
        (lambda (file)
          (pk 'maybe-read-library file)
          (let ((sexp (guard (ex (else #f))
                        (call-with-input-file file read))))
            (if (not sexp)
                (begin
                  (pk 'maybe-read-library "File is unreadable as Scheme file" file)
                  '())
                (if (and (pair? sexp)
                         (eq? (car sexp) 'library)
                         (pair? (cdr sexp))
                         (pair? (cadr sexp)))
                    (let ((exports (maybe-library-exports (cadr sexp))))
                      (if exports
                          (begin
                            (pk 'maybe-read-library "valid" file
                                (reverse (map (lambda (x) (cons (cadr sexp) x)) exports))))
                          (begin
                            (pk 'maybe-read-library "no interesting exports")
                            '())))
                    ;; Oops!
                    (begin
                      (pk 'maybe-read-library "not a valid scheme library file" file)
                      '()))))))

      (define string-prefix?
        (lambda (x y)
          (let ([n (string-length x)])
            (and (fx<= n (string-length y))
                 (let prefix? ([i 0])
                   (or (fx= i n)
                       (and (char=? (string-ref x i) (string-ref y i))
                            (prefix? (fx+ i 1)))))))))
      (define allow?
        (lambda (x)
          ;; Does it look like a check procedure
          (and (string-prefix? "~check-" (symbol->string (cdr x)))
               (or (null? alloweds)
                   (member (cdr x) alloweds)
                   (member (car x) alloweds)))))

      (define discover
        (lambda (directories)
          (define files (apply append (map ftw directories)))
          (filter allow? (apply append (map maybe-read-library files)))))

      (define uniquify
        (lambda (objects)
          (let loop ((objects objects)
                     (out '()))
            (if (null? objects)
                (map car out)
                (if (assoc (car objects) out)
                    (loop (cdr objects) out)
                    (loop (cdr objects)
                          (cons (cons (car objects) #t) out)))))))

      (define build-check-program
        (lambda (spec fail-fast?)
          ;; TODO: add prefix to import, and rename procedures
          (define libraries (pk 'libraries (reverse (uniquify (map car spec)))))
          (define procedures (map cdr spec))

          (pk 'program
              `(begin
                 (define errored? #f)

                 (define display-condition!
                   (lambda (procedure ex)
                     (format (current-error-port) "Procedure ~a: " procedure)
                     (display-condition ex)
                     (newline (current-error-port))))
                 
                 (display "* Will run tests from the following libraries:\n")
                 (for-each
                  (lambda (x)
                    (format #t "** ~a\n" x)) ',libraries)

                 (newline)
                 (let loop ((thunks (list ,@procedures)))
                   (unless (null? thunks)
                     (format #t "* Checking `~a`:\n" (car thunks))
                     (guard (ex (else
                                 (if (condition? ex)
                                     (display-condition! 'check ex)
                                     (write ex))
                                 (display "\n** ERROR!\n")
                                 (if ,fail-fast?
                                     (begin (newline)
                                            (exit 1))
                                     (begin (newline)
                                            (set! errored? #t)))))
                       (let ((out ((car thunks))))
                         (if (and (not (eq? out (void)))
                                  out)
                             (begin
                               (display "** SUCCESS\n"))
                             (begin
                               (display "** FAILED\n")
                               (if ,fail-fast?
                                   (begin (newline)
                                          (exit 1))
                                   (set! errored? #t))))))
                     (loop (cdr thunks))))
                 (newline)
                 (when errored? (exit 1))))))

      (call-with-values (lambda () (cli-read arguments))
        (lambda (keywords standalone extra)
          (massage-keywords! keywords)
          (massage-standalone! standalone)
          ;; TODO: Moar error handling
          (set! alloweds (map (lambda (x) (read (open-input-string x))) extra))))

      (compile-profile 'source)
      (disable-garbage-collector! disable-garbage-collector?)

      (maybe-display-errors-then-exit errors)

      (library-directories directories)
      (source-directories directories)

      (unless (null? extensions)
        (library-extensions extensions))

      (system* "mkdir -p /tmp/letloop")
      (let* ((temporary-directory (pk 'tmp
                                      (make-temporary-directory
                                       (string-append "/tmp/letloop/check-"
                                                      (timestamp)))))
             (check (string-append temporary-directory "/check.scm"))
             (checks (or (and (not (null? files))
                              (filter allow?
                                      (apply append
                                             (map maybe-read-library
                                                  files))))
                         (discover directories)))
             (program (build-check-program checks fail-fast?)))

        (when (null? checks)
          (format #t "* Error, no checks found!\n")
          (exit 2))

        (if dry-run?
            (let ((libraries (pk 'libraries (reverse (uniquify (map car checks)))))
                  (thunks (map cdr checks)))

              (format #t "* Dry run from the following libraries:\n\n")
              (for-each
               (lambda (x)
                 (format #t "** ~a\n" x)) libraries)
              (format #t "* Dry checks:\n\n")
              (for-each
               (lambda (thunk)
                 (format #t "** Dry checking `~a`:\n" (car thunks)))
               thunks))

            (begin
              ;; Change directory to TEMPORARY-DIRECTORY to produce
              ;; the profile dump along the CHECK file.
              (current-directory temporary-directory)

              (dynamic-wind
                  (lambda () (void))
                  (lambda () (eval program (copy-environment (apply environment '(chezscheme)
                                                                    (reverse (uniquify (map car checks))))
                                                             #t)))
                  (lambda ()
                    ;; profile-dump-html may fail if there is no temporary directory
                    (guard (ex (else (void)))
                      (profile-dump-html)
                      (format (current-output-port) "* Coverage profile can be found at: ~a/profile.html\n" temporary-directory)))))))))

  (define letloop-main
    (lambda args

      (pk 'args args)

      (when (null? args)
        (letloop-usage)
        (exit 0))

      (case (string->symbol (car args))
        ((check) (letloop-check (cdr args)))
        ((compile) (letloop-compile (cdr args)))
        ((exec) (letloop-exec (cdr args)))
        ((http) (letloop-http (cdr args)))
        ((repl) (letloop-repl (cdr args)))
        ((root) (letloop-root (cdr args)))
        ;; ((desktop) (letloop-desktop (cdr args)))
        ((review) (letloop-review (cdr args)))
        (else (letloop-usage) (exit 1)))))

  (define ftw*
    (lambda (directory)
      (let loop ((paths (map (lambda (x) (string-append directory "/" x)) (directory-list directory)))
                 (out '()))
        (if (null? paths)
            out
            (if (file-directory? (car paths))
                (loop (append (ftw* (car paths)) (cdr paths))
                      (cons (car paths) out))
                (loop (cdr paths) out))))))

  (define (display-usage usage)
    (display usage)
    (newline)
    (write `(scheme ,letloop-scheme-version))
    (newline)
    (write `(tag ,letloop-tag))
    (newline)
    (write `(homepage "https://codeberg.org/amirouche/letloop"))
    (newline))

  (define letloop-usage
    (lambda ()
      (display-usage letloop-usage.md)))

  (define list-index
    (lambda (predicate? objects)
      (let loop ((index 0)
                 (objects objects))
        (if (null? objects)
            #f
            (if (predicate? (car objects))
                index
                (loop (fx+ index 1) (cdr objects)))))))

  (define ref
    (lambda (alist key default)
      (if (null? alist)
          default
          (if (equal? (caar alist) key)
              (cdar alist)
              (ref (cdr alist) key default)))))

  (define (letloop-repl arguments)

    ;; parse ARGUMENTS, and set the following variables:

    (define extensions '())
    (define directories '())
    (define dev? #f)
    (define disable-garbage-collector? #f)
    (define optimize-level* 0)
    (define extra '())

    (define errors (make-accumulator))

    (define massage-standalone!
      (lambda (standalone)
        (unless (null? standalone)
          (call-with-values (lambda () (guess (car standalone)))
            (lambda (type string*)
              (case type
                (directory (set! directories (cons string* directories)))
                (extension (set! extensions (cons string* extensions)))
                (file (errors (format #f "Does not support files: ~a" (car standalone))))
                (unknown (errors (format #f "Directory does not exists: ~a" (car standalone)))))))
          (massage-standalone! (cdr standalone)))))

    (define massage-keywords!
      (lambda (keywords)
        (unless (null? keywords)
          (let ((keyword (car keywords)))
            (cond
             ((and (eq? (car keyword) '--dev) (not (string? (cdr keyword))))
              (set! dev? #t))
             ((and (eq? (car keyword) '--disable-garbage-collector) (not (string? (cdr keyword))))
              (set! disable-garbage-collector? #t))
             ((and (eq? (car keyword) '--optimize-level)
                   (string->number (cdr keyword))
                   (<= 0 (string->number (cdr keyword)) 3))
              (set! optimize-level* (string->number (cdr keyword))))
             (else (errors (format #f "Dubious keyword: ~a" (car keyword))))))
          (massage-keywords! (cdr keywords)))))

    (call-with-values (lambda () (cli-read arguments))
      (lambda (keywords standalone extra*)
        (massage-standalone! standalone)
        (massage-keywords! keywords)
        (set! extra extra*)))

    (unless (null? extra)
      (errors (format #f "No support for extra arguments: ~a" extra)))

    (maybe-display-errors-then-exit errors)

    (unless (null? directories)
      (library-directories (append directories (library-directories)))
      (source-directories (append directories (source-directories))))

    (when optimize-level*
      (optimize-level optimize-level*))

    (unless (null? extensions)
      (library-extensions extensions))

    (dev! dev?)
    (disable-garbage-collector! disable-garbage-collector?)

    (let loop ()
      (display "\033[32m#;letloop #;\033[m ")
      (let ((expr (read)))
        (unless (eof-object? expr)
          (call-with-values
              (lambda ()
                (guard (ex
                        ((condition? ex)
                         (display "\033[31m;; raised condition:\033[m ")
                         (display-condition! 'repl ex)
                         (newline))
                        (else
                         (display "\033[31m;; raised:\033[m ")
                         (write ex)
                         (newline)))
                  (eval expr)))
            (lambda args
              (unless (null? args)
                (for-each (lambda (x)
                            (unless (eq? x (void))
                              (display "\033[34m#;\033[m ")
                              (write x)
                              (newline)))
                          args))
              (loop))))))))

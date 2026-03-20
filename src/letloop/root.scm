(library (letloop root)

  (export letloop-root
          root-available-print
          root-create
          root-exec)

  (import (chezscheme)
          (letloop cffi)
          (letloop environment)
          (letloop generator)
          (letloop html base)
          (letloop root base)
          (letloop sxpath)
          (letloop www))

   ;; helpers

   (define pk
     (lambda args
       (when #t #;(environment-variable-ref "LETLOOP_DEBUG_ROOT")
         (display ";; " (current-error-port))
         (write args (current-error-port))
         (newline (current-error-port)))
       (car (reverse args))))

   (define stdlib (load-shared-object #f))

   (define root-temporary-directory
     (lambda (prefix)

       (define mkdtemp
         (foreign-procedure "mkdtemp" (string) string))

       (system* #f #f "mkdir -p $(dirname ~s)" prefix)

       (let ((input (string-append prefix "-XXXXXX")))
         (mkdtemp input))))

   (define call-with-env
     (lambda (env thunk)

       (define unsetenv
         (let ((func (foreign-procedure "unsetenv" (string) int)))
           (lambda (string)
             (func string))))

       ;; backup variables before overriding
       (define original (environment-variables))

       (if (not env)
           (thunk)
           ;; override!
           (begin
             (let loop ((env env))
               (unless (null? env)
                 (putenv (symbol->string (caar env)) (cdar env))
                 (loop (cdr env))))
             ;; call thunk
             (call-with-values thunk
               (lambda args
                 (let loop ((env env))
                   (if (null? env)
                       ;; bring back original variables
                       (let loop ((original original))
                         (unless (null? original)
                           (putenv (caar original) (cdar original))
                           (loop (cdr original))))
                       (begin
                         ;; unset variables from ENV
                         (unsetenv (symbol->string (caar env)))
                         (loop (cdr env)))))
                 (apply values args)))))))

   ;; call-raw-execve always returns (values ret errno).
   ;; Prefer __atomic __errno (Chez 10+); fall back to a manual errno read on Chez 9.x.
   (define call-raw-execve
     (guard (exn [#t
                  (let ([f (foreign-procedure "execve" (string uptr uptr) int)])
                    (lambda (path argv envp)
                      (call-with-errno (lambda () (f path argv envp)) values)))])
       (eval '(foreign-procedure __atomic __errno "execve" (string uptr uptr) int))))

   (define execve!
     (let ([raw call-raw-execve])
       (lambda (pathname . argv-strings)
         (define i (pk 'execve! pathname argv-strings))
         (define (make-c-string s)
           (let* ([bv  (string->utf8 s)]
                  [out (make-bytevector (+ (bytevector-length bv) 1) 0)])
             (bytevector-copy! bv 0 out 0 (bytevector-length bv))
             out))
         (let* ([c-strings (map make-c-string argv-strings)]
                [n         (length c-strings)]
                [ptr-size  (foreign-sizeof 'void*)]
                [argv      (foreign-alloc (* (+ n 1) ptr-size))]
                [envp      (foreign-ref 'uptr (foreign-entry "environ") 0)])
           (with-lock c-strings
             (let loop ([i 0] [ss c-strings])
               (unless (null? ss)
                 (foreign-set! 'uptr argv (* i ptr-size)
                               (bytevector-pointer (car ss)))
                 (loop (+ i 1) (cdr ss))))
             (foreign-set! 'uptr argv (* n ptr-size) 0)
             (let-values ([(ret errno) (raw pathname argv envp)])
               (foreign-free argv)
               (when (= ret -1)
                 (format (current-error-port) "execve: ~a\n" (strerror errno))
                 (exit 1))))))))

   (define system*
     (lambda (directory env command . variables)
       (define command* (apply format #f command variables))
       (pk 'system* directory env command variables)
       ;; TODO: check directory exists
       (unless (or (not directory)
                   (and
                    (file-exists? directory)
                    (file-directory? directory)))
         (error 'root "directory not found" directory))
       (unless (call-with-env env (lambda ()
                                    (if directory
                                        (parameterize ((current-directory directory))
                                          (zero? (system (pk 'system command*))))
                                        (zero? (system (pk 'system command*))))))
         (error 'system* "non-zero exit code" directory env command*))))

   (define URL_IMAGES_INDEX "https://images.linuxcontainers.org/images/")

   ;; template url
   (define url_rootfs "{URL}{distribution}/{release}/{arch}/default/{build}/rootfs.tar.xz")

   #!chezscheme
   (define sxpath-index-distributions
     (sxpath '(// a @ href *text*)))

   (define root-index-hrefs
     (lambda (url)
       (call-with-values (lambda () (www-request 'GET url '() (bytevector)))
         (lambda (code headers body)
           (if (= code 200)
               ;; cdr will remove parent directory aka. ../
               (cdr (sxpath-index-distributions (html-read (utf8->string body))))
               (begin
                 (format #t "There is a typo or upstream rootfs server is not responding?\n")
                 (exit 1)))))))

   (define root-distribution-hrefs
     (lambda ()
       (root-index-hrefs URL_IMAGES_INDEX)))

   (define root-distribution-version-hrefs
     (lambda (distribution-href)
       (root-index-hrefs (string-append URL_IMAGES_INDEX distribution-href))))

   (define root-distribution-version-machine-hrefs
     (lambda (distribution-href version-href)
       (root-index-hrefs (string-append URL_IMAGES_INDEX distribution-href version-href))))

   (define root-distribution-version-machine-latest-build
     (lambda (distribution-href version-href machine-href)

       (define and=>
         (lambda (x p)
           (if (null? x) x (p x))))

       (and=> (reverse (root-index-hrefs (string-append URL_IMAGES_INDEX
                                                        ;; there might be duplicated slash
                                                        distribution-href "/"
                                                        version-href "/"
                                                        machine-href "/"
                                                        "default/")))
              car)))

   (define root-available-generator
     (lambda ()

       (define rstrip/
         (lambda (x)
           (substring x 0 (- (string-length x) 1))))

       (make-coroutine-generator
        (lambda (yield)
          (for-each
           (lambda (distribution)
             (for-each
              (lambda (version)
                (for-each
                 (lambda (machine)
                   (yield (list (rstrip/ distribution)
                                (rstrip/ version)
                                (rstrip/ machine))))
                 (root-distribution-version-machine-hrefs distribution version)))
              (root-distribution-version-hrefs distribution)))
           (root-distribution-hrefs))))))

   (define root-available-print
     (lambda ()
       (generator-for-each (lambda (x) (apply format #t "~a ~a ~a\n" x)) (root-available-generator))))

   (define basename
     (lambda (string)
       (let loop ((index (string-length string)))
         (if (char=? (string-ref string (- index 1)) #\/)
             (substring string index (string-length string))
             (loop (- index 1))))))

   (define root-create
     (lambda (distribution version machine directory)

       (define build (root-distribution-version-machine-latest-build distribution
                                                                     version
                                                                     machine))
       (define rootfs.tar.xz (string-append URL_IMAGES_INDEX
                                            distribution "/"
                                            version "/"
                                            machine "/"
                                            "default" "/"
                                            build
                                            "rootfs.tar.xz"))
       (define SHA256SUMS (string-append URL_IMAGES_INDEX
                                         distribution "/"
                                         version "/"
                                         machine "/"
                                         "default" "/"
                                         build
                                         "SHA256SUMS"))

       (and (system* directory '() "wget ~a" rootfs.tar.xz)
            (system* directory '() "wget ~a" SHA256SUMS)
            (system* directory '() "fgrep rootfs.tar.xz SHA256SUMS | sha256sum -c -")
            (system* directory '() "tar xf rootfs.tar.xz")
            ;; TODO: rm machine-id is a legacy trick inherited from
            ;; systemd-nspawn, is it still useful?
            (system* directory '() "rm -f etc/resolv.conf etc/machine-id")
            (system* directory '() "echo ~a > etc/hostname" (basename directory))
            (format #t "echo root filesystem available @ ~a\n" directory))))

   (define string-join
     (lambda (strings delimiter)
       (pk 'string-join strings delimiter)
       (let loop ((out (list delimiter))
                  (strings strings))
         (if (null? strings)
             (apply string-append (pk 'string-join (reverse out)))
             (loop (cons* delimiter (car strings) out)
                   (cdr strings))))))

   (define root-exec
     (lambda (directory target-directory command)

       (define target-directory* (pk (or target-directory "/")))

       (pk 'directory directory 'target-directory target-directory 'command command)
       
       (system* directory #f "cp /etc/resolv.conf ~a/etc/resolv.conf" directory)
       (system* directory #f "mkdir -p ~a/mnt/host" directory)
       (apply execve! "/usr/bin/bwrap"
              "--die-with-parent" "--as-pid-1" "--clearenv"
             "--setenv" "PATH" "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
             "--setenv" "HOME" "/root"
             "--setenv" "USER" "root"
              "--unshare-uts" "--unshare-ipc" "--unshare-pid" "--unshare-cgroup"
              "--share-net"
              "--cap-add" "ALL"
              "--uid" "0" "--gid" "0"
              "--tmpfs" "/tmp/"
              "--dev-bind" directory "/"
              "--proc" "/proc"
              "--dev" "/dev"
              "--ro-bind" "/sys" "/sys"
              "--bind" (current-directory) "/mnt/host"
              "--chdir" target-directory*
              "--hostname" (basename directory)
              "--"
              command)))

   (define letloop-root
     (lambda (args)
       (if (null? (pk 'args args))
           (begin (display "Choose: available / create / exec.\nYou can do it!\n")
                  (exit 1))
           (case (string->symbol (car args))
             ((available) (root-available-print))
             ((create) (apply root-create (cdr args)))
             ((exec) (root-exec (cadr args) (caddr args) (cddr (cddr args))))
             (else (display "A typo? Almost, try again...!\n")
                   (exit 1))))))

   )

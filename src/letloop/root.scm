(library (letloop root)

  (export letloop-root
          root-available-print
          root-create
          root-exec)

  (import (chezscheme)
          (letloop environment)
          (letloop generator)
          (letloop html base)          
          (letloop root base)
          (letloop sxpath)
          (letloop www))

   ;; helpers

   (define pk
     (lambda args
       (when (environment-variable-ref "LETLOOP_DEBUG_ROOT")
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

   (define system?
     (lambda (command)
       (zero? (system command))))

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
                                          (system? command*))
                                        (system? command*))))
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
     (lambda (directory target-directory command . variables)

       (define target-directory* (pk (or target-directory "/")))

       (pk 'directory directory 'target-directory target-directory 'command command 'variables variables)
       
       (system* directory #f "cp /etc/resolv.conf ~a/etc/resolv.conf" directory)
       (system* directory #f "mkdir -p ~a/mnt/host" directory)
       (system* #f
                #f
                "bwrap --die-with-parent --as-pid-1 --clearenv --unshare-uts --unshare-ipc --unshare-pid --unshare-cgroup  --share-net  --cap-add ALL --uid 0 --gid 0 --tmpfs /tmp/ --dev-bind ~a / --proc /proc --dev /dev --ro-bind /sys /sys --bind ~a /mnt/host --chdir ~a --hostname ~a -- ~a"
                directory
                (current-directory)
                target-directory*
                (basename directory)
                (apply format #f command variables))))

   (define letloop-root
     (lambda (args)
       (if (null? args)
           (begin (display "Choose: available / create / exec.\nYou can do it!\n")
                  (exit 1))
           (case (string->symbol (car args))
             ((available) (root-available-print))
             ((create) (apply root-create (cdr args)))
             ((exec) (root-exec (cadr args) (caddr args) (string-join (cddr (cddr args)) " ")))
             (else (display "A typo? Almost, try again...!\n")
                   (exit 1))))))

   )

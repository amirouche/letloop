;; The fixture rootfs is a directory of symlinks pointing at the
;; host's own top-level directories (/usr, /bin, ...) -- this
;; exercises the real bwrap mechanics (per-entry read-only binds,
;; namespace isolation, network denial) without needing any cached
;; Alpine/musl rootfs on hand; a real derivation build supplies its
;; own toolchain rootfs instead.
(define (sandbox-check-fixture-rootfs! rootfs)
  (for-each
   (lambda (name)
     (when (file-exists? (string-append "/" name))
       (system! (format #f "ln -s ~a ~a"
                         (shell-single-quote (string-append "/" name))
                         (shell-single-quote (string-append rootfs "/" name))))))
   '("usr" "bin" "sbin" "lib" "lib64" "etc")))

(define ~check-sandbox-000
  (lambda ()
    (if (not (bwrap-available?))
        (begin (display "** SKIP: /usr/bin/bwrap not found\n") #t)
        (guard (ex (#t (display "** SKIP: bwrap sandbox unavailable in this environment\n") #t))
          (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
          (system! "mkdir -p /tmp/letloop/")
          (let* ((rootfs (mkdtemp "/tmp/letloop/sandbox-check-rootfs-XXXXXX"))
                 (scratch (mkdtemp "/tmp/letloop/sandbox-check-scratch-XXXXXX")))
            (sandbox-check-fixture-rootfs! rootfs)
            (system! (format #f "mkdir -p ~a" (shell-single-quote (string-append scratch "/out"))))
            (call-with-output-file (string-append scratch "/build.sh")
              (lambda (port) (display "echo ok > /build/out/ok\n" port)))
            (sandbox-build! rootfs scratch '())
            (let ((content (call-with-port (open-file-input-port (string-append scratch "/out/ok"))
                              get-bytevector-all)))
              (string=? (utf8->string content) "ok\n")))))))

(define-syntax check-skip-unless-blake3
  (syntax-rules ()
    ((_ body ...)
     (guard (ex (#t (display "** SKIP: blake3 unavailable\n") #t))
       body ...))))

(define (hash-check-write-file! path content)
  (when (file-exists? path) (delete-file path))
  (call-with-output-file path (lambda (port) (display content port))))

(define (hash-check-fixture directory)
  (system! (format #f "rm -rf ~a && mkdir -p ~a/sub"
                    (shell-single-quote directory)
                    (shell-single-quote directory)))
  (hash-check-write-file! (string-append directory "/a.txt") "hello")
  (hash-check-write-file! (string-append directory "/sub/b.txt") "world")
  (system! (format #f "chmod +x ~a" (shell-single-quote (string-append directory "/a.txt")))))

;; hashing the same directory twice is deterministic
(define ~check-hash-000
  (lambda ()
    (check-skip-unless-blake3
     (let ((directory "/tmp/letloop/hash-check-000"))
       (hash-check-fixture directory)
       (string=? (store-hash-directory directory) (store-hash-directory directory))))))

;; an mtime-only change leaves the digest unchanged
(define ~check-hash-001
  (lambda ()
    (check-skip-unless-blake3
     (let* ((directory "/tmp/letloop/hash-check-001")
            (ignore (hash-check-fixture directory))
            (before (store-hash-directory directory))
            (ignore (system! (format #f "touch -d '2000-01-01' ~a"
                                      (shell-single-quote (string-append directory "/a.txt")))))
            (after (store-hash-directory directory)))
       (string=? before after)))))

;; a one-byte content change changes the digest
(define ~check-hash-002
  (lambda ()
    (check-skip-unless-blake3
     (let* ((directory "/tmp/letloop/hash-check-002")
            (ignore (hash-check-fixture directory))
            (before (store-hash-directory directory))
            (ignore (hash-check-write-file! (string-append directory "/a.txt") "HELLO"))
            (after (store-hash-directory directory)))
       (not (string=? before after))))))

;; renaming a file changes the digest
(define ~check-hash-003
  (lambda ()
    (check-skip-unless-blake3
     (let* ((directory "/tmp/letloop/hash-check-003")
            (ignore (hash-check-fixture directory))
            (before (store-hash-directory directory))
            (ignore (system! (format #f "mv ~a ~a"
                                      (shell-single-quote (string-append directory "/a.txt"))
                                      (shell-single-quote (string-append directory "/a-renamed.txt")))))
            (after (store-hash-directory directory)))
       (not (string=? before after))))))

;; a tree containing symlinks hashes at all, and does so
;; deterministically -- the bootstrap rootfs is mostly symlinks
(define ~check-hash-004/symlinks
  (lambda ()
    (check-skip-unless-blake3
     (let ((directory "/tmp/letloop/hash-check-004"))
       (hash-check-fixture directory)
       (system! (format #f "ln -s a.txt ~a" (shell-single-quote (string-append directory "/link"))))
       ;; an absolute link pointing outside the tree: normal for
       ;; /bin/sh -> /bin/busybox, and must not be followed
       (system! (format #f "ln -s /nonexistent/elsewhere ~a"
                         (shell-single-quote (string-append directory "/dangling"))))
       (string=? (store-hash-directory directory) (store-hash-directory directory))))))

;; retargeting a symlink changes the digest, even though no file
;; content changed -- the target string is what gets hashed
(define ~check-hash-005/symlink-target-matters
  (lambda ()
    (check-skip-unless-blake3
     (let* ((directory "/tmp/letloop/hash-check-005")
            (link (string-append directory "/link"))
            (ignore (hash-check-fixture directory))
            (ignore (system! (format #f "ln -s a.txt ~a" (shell-single-quote link))))
            (before (store-hash-directory directory))
            (ignore (system! (format #f "rm ~a && ln -s sub/b.txt ~a"
                                      (shell-single-quote link)
                                      (shell-single-quote link))))
            (after (store-hash-directory directory)))
       (not (string=? before after))))))

;; a symlink to a file and a copy of that file are not the same tree
(define ~check-hash-006/symlink-is-not-its-target
  (lambda ()
    (check-skip-unless-blake3
     (let* ((directory "/tmp/letloop/hash-check-006")
            (entry (string-append directory "/entry"))
            (ignore (hash-check-fixture directory))
            (ignore (system! (format #f "ln -s a.txt ~a" (shell-single-quote entry))))
            (as-link (store-hash-directory directory))
            (ignore (system! (format #f "rm ~a && cp ~a ~a"
                                      (shell-single-quote entry)
                                      (shell-single-quote (string-append directory "/a.txt"))
                                      (shell-single-quote entry))))
            (as-copy (store-hash-directory directory)))
       (not (string=? as-link as-copy))))))

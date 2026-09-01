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

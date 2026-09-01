;; Deterministic BLAKE3 content-hashing of a directory tree, for
;; addressing a store path by the content of its own build output.
;;
;; Only file content and the owner-execute bit are hashed, plus
;; directory structure -- not mtime/uid/gid/other mode bits -- so the
;; digest is stable across `touch`/re-checkout while still sensitive
;; to anything that could change program behavior. Symlinks, device
;; nodes, FIFOs and sockets are rejected: there is no lstat/readlink
;; primitive in this codebase yet, and supporting them is out of
;; scope for now.

(define (shell-single-quote unquoted)
  (string-append
   "'"
   (apply string-append
          (map (lambda (char)
                 (if (char=? char #\')
                     "'\\''"
                     (string char)))
               (string->list unquoted)))
   "'"))

(define (system! command)
  (unless (zero? (system command))
    (error 'system! "command failed" command)))

(define (read-all-lines port)
  (let loop ((out '()))
    (let ((line (get-line port)))
      (if (eof-object? line)
          (reverse out)
          (loop (cons line out))))))

(define (string-index-from string char start)
  (let loop ((i start))
    (cond
     ((fx>= i (string-length string)) #f)
     ((char=? (string-ref string i) char) i)
     (else (loop (fx+ i 1))))))

;; "f 644 some/path" -> (#\f "644" "some/path"); split at the first
;; two spaces only, so a space embedded in the path itself is kept.
(define (parse-manifest-line line)
  (let* ((space1 (or (string-index-from line #\space 0)
                      (error 'directory-manifest "malformed find output line" line)))
         (space2 (or (string-index-from line #\space (fx+ space1 1))
                      (error 'directory-manifest "malformed find output line" line))))
    (list (string-ref line 0)
          (substring line (fx+ space1 1) space2)
          (substring line (fx+ space2 1) (string-length line)))))

(define (check-manifest-entry-type! entry)
  (unless (memv (car entry) '(#\f #\d))
    (error 'directory-manifest
           "unsupported filesystem entry (only regular files and directories are supported)"
           entry))
  entry)

;; -> sorted list of (type mode relative-path), type is #\f or #\d.
(define (directory-manifest directory)
  (define mkdtemp (foreign-procedure "mkdtemp" (string) string))
  (system! "mkdir -p /tmp/letloop/")
  (let* ((scratch (mkdtemp "/tmp/letloop/hash-XXXXXX"))
         (listing-path (string-append scratch "/listing")))
    (system! (format #f "cd ~a && find . -mindepth 1 -printf '%y %m %P\\n' > ~a"
                      (shell-single-quote directory)
                      (shell-single-quote listing-path)))
    (let ((lines (call-with-input-file listing-path read-all-lines)))
      (system! (format #f "rm -rf ~a" (shell-single-quote scratch)))
      (sort (lambda (a b) (string<? (caddr a) (caddr b)))
            (map check-manifest-entry-type! (map parse-manifest-line lines))))))

(define hex-digits "0123456789abcdef")

(define (bytevector->hex-string bv)
  (let* ((n (bytevector-length bv))
         (out (make-string (* 2 n))))
    (let loop ((i 0))
      (unless (fx= i n)
        (let ((byte (bytevector-u8-ref bv i)))
          (string-set! out (* 2 i) (string-ref hex-digits (fxarithmetic-shift-right byte 4)))
          (string-set! out (+ (* 2 i) 1) (string-ref hex-digits (fxand byte #xf))))
        (loop (fx+ i 1))))
    out))

;; owner-execute bit only, e.g. "755" -> #t, "644" -> #f
(define (mode-executable? mode-string)
  (not (fxzero? (fxand (string->number mode-string 8) #o100))))

(define (update-directory-entry! hasher relative-path)
  (blake3-update! hasher (string->utf8 (string-append "d " relative-path "\n"))))

(define (update-file-entry! hasher directory relative-path mode)
  (define content
    (let ((bv (call-with-port (open-file-input-port (string-append directory "/" relative-path))
                get-bytevector-all)))
      (if (eof-object? bv) (bytevector) bv)))
  (define flag (if (mode-executable? mode) "x" "-"))
  (blake3-update! hasher (string->utf8 (format #f "f ~a ~a ~a\n" flag relative-path (bytevector-length content))))
  (blake3-update! hasher content)
  (blake3-update! hasher (string->utf8 "\n")))

;; -> 64-char lowercase hex BLAKE3 digest of DIRECTORY's content.
(define (store-hash-directory directory)
  (define hasher (make-blake3))
  (for-each
   (lambda (entry)
     (let ((type (car entry)) (mode (cadr entry)) (relative-path (caddr entry)))
       (case type
         ((#\d) (update-directory-entry! hasher relative-path))
         ((#\f) (update-file-entry! hasher directory relative-path mode)))))
   (directory-manifest directory))
  (let ((digest (blake3-finalize hasher 32)))
    (blake3-close! hasher)
    (bytevector->hex-string digest)))

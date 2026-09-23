;; Deterministic BLAKE3 content-hashing of a directory tree, for
;; addressing a store path by the content of its own build output.
;;
;; Only file content and the owner-execute bit are hashed, plus
;; directory structure and symlink targets -- not mtime/uid/gid/other
;; mode bits -- so the digest is stable across `touch`/re-checkout
;; while still sensitive to anything that could change program
;; behavior.
;;
;; A symlink is hashed as its own target string, never followed: two
;; trees differing only in where a link points must hash differently,
;; and following would both duplicate the target's content and break
;; on links pointing outside the tree (which is normal -- /bin/sh ->
;; /bin/busybox is an absolute link). Symlinks matter here because the
;; bootstrap rootfs is built out of them: busybox installs one applet
;; link per command, and a toolchain has cc -> gcc and friends.
;;
;; Device nodes, FIFOs and sockets are still rejected -- nothing a
;; build ought to be producing as its output, and each would need its
;; own encoding to hash meaningfully.
;;
;; The tree is walked in Scheme. It used to shell out to
;; `find -printf`, which is a GNU extension BusyBox does not have --
;; so the store could not run inside the minimal rootfs it builds,
;; which is a poor property for a package manager that builds its own
;; environment. Nothing here spawns a process now.

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

(define readlink*
  ;; No readlink in Chez, and the manifest needs one: a symlink hashes
  ;; as its target string. PATH_MAX is 4096 on Linux; a truncated
  ;; result would silently change the digest, so a full buffer is
  ;; treated as an error rather than accepted.
  (let ((func (foreign-procedure "readlink" (string u8* uptr) iptr)))
    (lambda (path)
      (let* ((size 4096)
             (buffer (make-bytevector size))
             (n (func path buffer size)))
        (when (fx<? n 0)
          (error 'directory-manifest "cannot read symlink" path))
        (when (fx=? n size)
          (error 'directory-manifest "symlink target longer than PATH_MAX" path))
        (let ((out (make-bytevector n)))
          (bytevector-copy! buffer 0 out 0 n)
          (utf8->string out))))))

;; -> (type mode relative-path target), where type is 'file,
;; 'directory or 'symlink, mode is the integer st_mode, and target is
;; the link's target for a symlink and #f otherwise.
;;
;; Walked in Scheme rather than shelled out to `find -printf`, which is
;; a GNU extension: BusyBox find does not have it, so the store could
;; not run inside the minimal rootfs it builds. Doing it here also
;; drops two subprocesses per hash and the text parsing that went with
;; them -- the old manifest had to run find twice, since neither a path
;; nor a symlink target can be delimited unambiguously by spaces.
;;
;; Every predicate is asked not to follow symlinks: a link to a
;; directory is a link, not a directory, and must never be descended
;; into. A dangling link is fine and stays a link.
(define (directory-entries directory)
  (let walk ((prefix "") (path directory) (out '()))
    (fold-left
     (lambda (out name)
       (let* ((relative (if (string=? prefix "") name (string-append prefix "/" name)))
              (full (string-append path "/" name))
              (mode (get-mode full #f)))
         (cond
          ((file-symbolic-link? full)
           (cons (list 'symlink mode relative (readlink* full)) out))
          ((file-directory? full #f)
           (walk relative full (cons (list 'directory mode relative #f) out)))
          ((file-regular? full #f)
           (cons (list 'file mode relative #f) out))
          (else
           (error 'directory-manifest
                  "unsupported filesystem entry (only regular files, directories and symlinks are supported)"
                  full)))))
     out
     (directory-list path))))

;; -> the entries sorted by relative path, so the digest does not
;; depend on the order the filesystem happened to hand them back.
(define (directory-manifest directory)
  (sort (lambda (a b) (string<? (caddr a) (caddr b)))
        (directory-entries directory)))

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

;; owner-execute bit only, from the integer st_mode: not the whole
;; mode, and never mtime/uid/gid, so the digest is stable across a
;; touch or a re-checkout while still moving when a file gains or
;; loses the bit that changes how it behaves.
(define (mode-executable? mode)
  (not (fxzero? (fxand mode #o100))))

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

;; The target is hashed with an explicit length, like a file's content,
;; so no target string can be confused with the entry that follows it.
(define (update-symlink-entry! hasher relative-path target)
  (let ((encoded (string->utf8 target)))
    (blake3-update! hasher
                    (string->utf8 (format #f "l ~a ~a\n" relative-path (bytevector-length encoded))))
    (blake3-update! hasher encoded)
    (blake3-update! hasher (string->utf8 "\n"))))

;; -> 64-char lowercase hex BLAKE3 digest of DIRECTORY's content.
(define (store-hash-directory directory)
  (define hasher (make-blake3))
  (for-each
   (lambda (entry)
     (let ((type (car entry))
           (mode (cadr entry))
           (relative-path (caddr entry))
           (target (cadddr entry)))
       (case type
         ((directory) (update-directory-entry! hasher relative-path))
         ((file) (update-file-entry! hasher directory relative-path mode))
         ((symlink) (update-symlink-entry! hasher relative-path target)))))
   (directory-manifest directory))
  (let ((digest (blake3-finalize hasher 32)))
    (blake3-close! hasher)
    (bytevector->hex-string digest)))

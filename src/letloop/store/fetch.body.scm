;; Host-side fetch-then-verify for a derivation's fixed-output inputs
;; (e.g. a source tarball): downloads URL, BLAKE3-hashes the body, and
;; requires it to match EXPECTED-HASH-HEX before writing anything to
;; DESTINATION-PATH. This runs on the host, not inside the build
;; sandbox -- a fixed-output fetch's reproducibility guarantee is the
;; hash check itself, not network isolation, so there is no purity
;; reason to sandbox it, and it sidesteps needing any network tooling
;; inside a minimal, network-off build rootfs.

(define (fetch-verify! name url expected-hash-hex destination-path)
  (call-with-values (lambda () (www-request 'GET url '() (bytevector)))
    (lambda (code headers body)
      (unless (= code 200)
        (error 'fetch-verify! "fetch failed" name url code))
      (let ((actual-hash-hex (bytevector->hex-string (blake3 body))))
        (unless (string-ci=? actual-hash-hex expected-hash-hex)
          (error 'fetch-verify!
                 "hash mismatch"
                 name url
                 (list 'expected expected-hash-hex 'actual actual-hash-hex)))
        (call-with-port (open-file-output-port destination-path (file-options replace))
          (lambda (port) (put-bytevector port body)))))))

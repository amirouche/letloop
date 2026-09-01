;; Host-side fetch-then-verify for a derivation's fixed-output inputs
;; (e.g. a source tarball): downloads URL, BLAKE3-hashes the body, and
;; requires it to match EXPECTED-HASH-HEX before writing anything to
;; DESTINATION-PATH. This runs on the host, not inside the build
;; sandbox -- a fixed-output fetch's reproducibility guarantee is the
;; hash check itself, not network isolation, so there is no purity
;; reason to sandbox it, and it sidesteps needing any network tooling
;; inside a minimal, network-off build rootfs.

;; Some upstreams -- ftp.gnu.org among them -- answer 403 to a request
;; carrying no User-Agent at all, which is what www-request sends when
;; given no headers. Identifying ourselves is both what those servers
;; want and the polite thing to do when fetching from a volunteer
;; mirror.
(define fetch-user-agent '((user-agent . "letloop-store/1")))

(define (fetch-verify! name url expected-hash-hex destination-path)
  (call-with-values (lambda () (www-request 'GET url fetch-user-agent (bytevector)))
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

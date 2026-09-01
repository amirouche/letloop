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

;; www-request does not follow redirects, and the places releases
;; actually live do redirect: a GitHub release asset is a 302 to a
;; signed, expiring URL on another host, and most mirror front-ends
;; behave the same way. Following them here rather than in www-request
;; keeps that change contained to the fetcher that needs it.
;;
;; Redirects are safe to follow blindly precisely because the result is
;; hash-checked: wherever the bytes come from, they are either the
;; bytes that were pinned or the fetch fails. The hop limit only stops
;; a redirect loop from spinning forever.
(define fetch-redirect-limit 5)

(define (fetch-following-redirects name url)
  (let loop ((url url) (hops 0))
    (when (fx> hops fetch-redirect-limit)
      (error 'fetch-verify! "too many redirects" name url))
    (call-with-values (lambda () (www-request 'GET url fetch-user-agent (bytevector)))
      (lambda (code headers body)
        (cond
         ((= code 200) body)
         ((memv code '(301 302 303 307 308))
          (let ((location (assq 'location headers)))
            (unless location
              (error 'fetch-verify! "redirect without a location" name url code))
            (loop (cdr location) (fx+ hops 1))))
         (else
          (error 'fetch-verify! "fetch failed" name url code)))))))

(define (fetch-verify! name url expected-hash-hex destination-path)
  (let* ((body (fetch-following-redirects name url))
         (actual-hash-hex (bytevector->hex-string (blake3 body))))
    (unless (string-ci=? actual-hash-hex expected-hash-hex)
      (error 'fetch-verify!
             "hash mismatch"
             name url
             (list 'expected expected-hash-hex 'actual actual-hash-hex)))
    (call-with-port (open-file-output-port destination-path (file-options replace))
      (lambda (port) (put-bytevector port body)))))

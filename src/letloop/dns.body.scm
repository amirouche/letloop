;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Async DNS A-record resolver over the io_uring loop from (letloop
;; liburing low). Must run inside a loop coroutine (loop-spawn):
;; resolution yields via loop-abort while the UDP exchange is in
;; flight. Extracted from examples/picotransparenturing.scm.

(define bytevector-append
  (lambda bvs
    (let* ((total (apply fx+ (map bytevector-length bvs)))
           (out (make-bytevector total)))
      (let loop ((bvs bvs) (offset 0))
        (if (null? bvs)
            out
            (let ((bv (car bvs)))
              (bytevector-copy! bv 0 out offset (bytevector-length bv))
              (loop (cdr bvs) (fx+ offset (bytevector-length bv)))))))))

(define %dns-nameserver #f)

;; hostname → #(a b c d expiry-jiffy); avoids a full DNS round-trip on
;; every request to the same host.
;;
;; Expiry comes from the A record's OWN TTL (%dns-rr-ttl), not a flat
;; assumption -- a 60s constant here both ignored records that ask to
;; be held far longer and overrode ones that ask to be refreshed
;; sooner. The bounds below exist because the cache is the only thing
;; standing between a burst of connection setups and a resolve per
;; connection: a TTL of 0 (legal, and what some load balancers send)
;; would mean never caching at all, which is precisely the stampede
;; that fills the io_uring submission queue. So a floor keeps a
;; pathological TTL from disabling the cache, and a ceiling keeps a
;; very long one from pinning a stale address for hours.
(define %dns-cache (make-hashtable string-hash string=?))
(define %dns-cache-ttl-minimum-seconds 5)
(define %dns-cache-ttl-maximum-seconds 3600)

(define %dns-cache-expiry
  (lambda (ttl-seconds)
    (let ((bounded (cond
                     ((not (and (integer? ttl-seconds) (>= ttl-seconds 0)))
                      %dns-cache-ttl-minimum-seconds)
                     ((< ttl-seconds %dns-cache-ttl-minimum-seconds)
                      %dns-cache-ttl-minimum-seconds)
                     ((> ttl-seconds %dns-cache-ttl-maximum-seconds)
                      %dns-cache-ttl-maximum-seconds)
                     (else ttl-seconds))))
      (+ (jiffy-current) (* bounded (expt 10 9))))))

;; a linked timeout cancels the DNS recv when the nameserver never
;; answers, instead of hanging the coroutine forever
(define %dns-recv-timeout-seconds 5)
(define %dns-recv-timeout-ts #f)

(define %dns-read-resolv-conf
  (lambda ()
    (guard (ex (else "8.8.8.8"))
      (let ((lines (call-with-input-file "/etc/resolv.conf"
                     (lambda (port)
                       (let loop ((out '()))
                         (let ((line (get-line port)))
                           (if (eof-object? line)
                               (reverse out)
                               (loop (cons line out)))))))))
        (let find ((lines lines))
          (if (null? lines)
              "8.8.8.8"
              (let ((line (car lines)))
                (if (and (> (string-length line) 11)
                         (string=? "nameserver " (substring line 0 11)))
                    (let ((ns (substring line 11 (string-length line))))
                      ;; Trim trailing whitespace
                      (let trim ((s ns))
                        (if (and (> (string-length s) 0)
                                 (char<=? (string-ref s (- (string-length s) 1)) #\space))
                            (trim (substring s 0 (- (string-length s) 1)))
                            s)))
                    (find (cdr lines))))))))))

(define %dns-get-nameserver
  (lambda ()
    (unless %dns-nameserver
      (set! %dns-nameserver (%dns-read-resolv-conf)))
    %dns-nameserver))

(define %dns-encode-name
  (lambda (hostname)
    ;; "example.com" → #vu8(7 101 120 97 109 112 108 101 3 99 111 109 0)
    ;; A single trailing dot ("example.com.") is stripped; every label
    ;; must be 1 to 63 bytes, as per RFC 1035.
    (let* ((hostname (let ((len (string-length hostname)))
                       (if (and (fx>? len 0)
                                (char=? (string-ref hostname (fx- len 1)) #\.))
                           (substring hostname 0 (fx- len 1))
                           hostname)))
           (parts (let split ((chars (string->list hostname))
                              (current '())
                              (out '()))
                    (cond
                      ((null? chars)
                       (reverse (cons (list->string (reverse current)) out)))
                      ((char=? (car chars) #\.)
                       (split (cdr chars) '()
                              (cons (list->string (reverse current)) out)))
                      (else
                       (split (cdr chars) (cons (car chars) current) out))))))
      (let ((bvs (map (lambda (part)
                        (let ((bv (string->utf8 part)))
                          (when (fxzero? (bytevector-length bv))
                            (error 'dns "Empty label in hostname" hostname))
                          (when (fx>? (bytevector-length bv) 63)
                            (error 'dns "Label longer than 63 bytes" part))
                          (let ((out (make-bytevector (+ 1 (bytevector-length bv)))))
                            (bytevector-u8-set! out 0 (bytevector-length bv))
                            (bytevector-copy! bv 0 out 1 (bytevector-length bv))
                            out)))
                      parts)))
        (apply bytevector-append (append bvs (list (bytevector 0))))))))

(define %dns-build-query
  (lambda (hostname id)
    (let* ((id-hi (fxsrl id 8))
           (id-lo (fxlogand id #xFF))
           (header (bytevector id-hi id-lo
                               1 0    ;; QR=0, OPCODE=0, RD=1
                               0 1    ;; QDCOUNT=1
                               0 0    ;; ANCOUNT=0
                               0 0    ;; NSCOUNT=0
                               0 0))  ;; ARCOUNT=0
           (name (%dns-encode-name hostname))
           (qtype (bytevector 0 1))   ;; A record
           (qclass (bytevector 0 1))) ;; IN class
      (bytevector-append header name qtype qclass))))

;; RR wire layout after the name: TYPE(2) CLASS(2) TTL(4) RDLENGTH(2)
;; RDATA. TTL is the record's own lifetime in seconds, big-endian at
;; offset 4 -- read it rather than assuming one.
(define %dns-rr-ttl
  (lambda (bv rr-pos)
    (+ (* 16777216 (bytevector-u8-ref bv (+ rr-pos 4)))
       (* 65536 (bytevector-u8-ref bv (+ rr-pos 5)))
       (* 256 (bytevector-u8-ref bv (+ rr-pos 6)))
       (bytevector-u8-ref bv (+ rr-pos 7)))))

(define %dns-parse-response
  (lambda (bv id)
    ;; Returns (a b c d ttl-seconds) for IPv4 or #f on failure. ID is
    ;; the query identifier the response must echo back.
    (guard (ex (else #f))
      (when (< (bytevector-length bv) 12)
        (error 'dns "Response too short"))
      ;; Check the response ID matches the query ID
      (unless (= id (+ (* 256 (bytevector-u8-ref bv 0))
                       (bytevector-u8-ref bv 1)))
        (error 'dns "Response ID mismatch"))
      (let ((flags (bytevector-u8-ref bv 2)))
        ;; Check QR=1 (response)
        (unless (not (fxzero? (fxlogand flags #x80)))
          (error 'dns "Not a response"))
        ;; Check TC=0 (no TCP fallback implemented)
        (unless (fxzero? (fxlogand flags #x02))
          (error 'dns "Response truncated")))
      ;; Check RCODE=0
      (let ((rcode (fxlogand (bytevector-u8-ref bv 3) #x0F)))
        (unless (fxzero? rcode)
          (error 'dns "DNS error" rcode)))
      ;; ANCOUNT
      (let ((ancount (+ (* 256 (bytevector-u8-ref bv 6))
                        (bytevector-u8-ref bv 7))))
        (when (fxzero? ancount)
          (error 'dns "No answers"))
        ;; Skip question section
        (let skip-question ((pos 12))
          (let ((b (bytevector-u8-ref bv pos)))
            (cond
              ((fxzero? b)
               ;; Past null terminator + QTYPE(2) + QCLASS(2)
               (let parse-answers ((pos (+ pos 5)) (i 0))
                 (if (fx>=? i ancount)
                     (error 'dns "No A record found")
                     ;; Skip name (may be compressed), find where RR fields start
                     (let skip-name ((pos pos))
                       (let ((b (bytevector-u8-ref bv pos)))
                         (cond
                           ;; Compression pointer — 2 bytes total, then RR fields
                           ((not (fxzero? (fxlogand b #xC0)))
                            (let* ((rr-pos (+ pos 2))
                                   (rtype (+ (* 256 (bytevector-u8-ref bv rr-pos))
                                             (bytevector-u8-ref bv (+ rr-pos 1))))
                                   (rdlen (+ (* 256 (bytevector-u8-ref bv (+ rr-pos 8)))
                                             (bytevector-u8-ref bv (+ rr-pos 9))))
                                   (rdata-pos (+ rr-pos 10)))
                              (if (and (= rtype 1) (= rdlen 4))
                                  (list (bytevector-u8-ref bv rdata-pos)
                                        (bytevector-u8-ref bv (+ rdata-pos 1))
                                        (bytevector-u8-ref bv (+ rdata-pos 2))
                                        (bytevector-u8-ref bv (+ rdata-pos 3))
                                        (%dns-rr-ttl bv rr-pos))
                                  (parse-answers (+ rdata-pos rdlen) (+ i 1)))))
                           ;; Null terminator — end of name, RR fields follow
                           ((fxzero? b)
                            (let* ((rr-pos (+ pos 1))
                                   (rtype (+ (* 256 (bytevector-u8-ref bv rr-pos))
                                             (bytevector-u8-ref bv (+ rr-pos 1))))
                                   (rdlen (+ (* 256 (bytevector-u8-ref bv (+ rr-pos 8)))
                                             (bytevector-u8-ref bv (+ rr-pos 9))))
                                   (rdata-pos (+ rr-pos 10)))
                              (if (and (= rtype 1) (= rdlen 4))
                                  (list (bytevector-u8-ref bv rdata-pos)
                                        (bytevector-u8-ref bv (+ rdata-pos 1))
                                        (bytevector-u8-ref bv (+ rdata-pos 2))
                                        (bytevector-u8-ref bv (+ rdata-pos 3))
                                        (%dns-rr-ttl bv rr-pos))
                                  (parse-answers (+ rdata-pos rdlen) (+ i 1)))))
                           ;; Normal label — skip length byte + label bytes
                           (else
                            (skip-name (+ pos 1 b)))))))))
              ;; Compression pointer in question
              ((not (fxzero? (fxlogand b #xC0)))
               (skip-question (+ pos 2)))
              (else
               (skip-question (+ pos 1 b))))))))))

(define %dns-ip-string?
  (lambda (s)
    (let ((len (string-length s)))
      (and (> len 0)
           (let loop ((i 0))
             (if (fx>=? i len)
                 #t
                 (let ((c (string-ref s i)))
                   (if (or (char<=? #\0 c #\9) (char=? c #\.))
                       (loop (fx+ i 1))
                       #f))))))))

(define %dns-parse-ip
  (lambda (s)
    (let ((parts (let split ((chars (string->list s))
                             (current '())
                             (out '()))
                   (cond
                     ((null? chars)
                      (reverse (cons (string->number (list->string (reverse current))) out)))
                     ((char=? (car chars) #\.)
                      (split (cdr chars) '()
                             (cons (string->number (list->string (reverse current))) out)))
                     (else
                      (split (cdr chars) (cons (car chars) current) out))))))
      (values (car parts) (cadr parts) (caddr parts) (cadddr parts)))))

(define dns-resolve-a
  (lambda (hostname port)
    ;; Returns (values addr-ptr addrlen); the caller foreign-frees
    ;; addr-ptr. Must run inside a loop coroutine unless HOSTNAME is
    ;; already a dotted IPv4 literal or cached.
    (if (%dns-ip-string? hostname)
        ;; Already an IP address
        (call-with-values (lambda () (%dns-parse-ip hostname))
          (lambda (a b c d)
            (make-sockaddr-in a b c d port)))
        (let ((cached (hashtable-ref %dns-cache hostname #f)))
          (if (and cached (< (jiffy-current) (vector-ref cached 4)))
              (make-sockaddr-in (vector-ref cached 0)
                                (vector-ref cached 1)
                                (vector-ref cached 2)
                                (vector-ref cached 3)
                                port)
              (%dns-resolve-a/network hostname port))))))

(define %dns-resolve-a/network
  (lambda (hostname port)
    ;; DNS lookup via io_uring
    (let* ((ns (%dns-get-nameserver))
               (query-id (random 65536))
               (udp-fd (loop-socket-new 2 2 0)))  ;; AF_INET, SOCK_DGRAM
          (unless udp-fd (error 'dns-resolve-a "UDP socket failed"))
          (loop-nonblock! udp-fd)
          ;; Connect UDP socket to nameserver:53
          (call-with-values (lambda () (%dns-parse-ip ns))
            (lambda (a b c d)
              (call-with-values (lambda () (make-sockaddr-in a b c d 53))
                (lambda (ns-addr ns-addrlen)
                  (let* ((sqe (loop-get-sqe (loop-ring (loop-current))))
                         (id (loop-alloc-id!)))
                    (io-uring-prep-connect sqe udp-fd ns-addr ns-addrlen)
                    (io-uring-sqe-set-data64 sqe id)
                    (let ((res (loop-abort
                                 (lambda (k)
                                   (hashtable-set! (loop-handlers (loop-current)) id k)))))
                      (foreign-free ns-addr)
                      (when (fx<? res 0)
                        (loop-close udp-fd)
                        (error 'dns-resolve-a "UDP connect failed" (strerror (fx- 0 res))))))))))
          ;; Build and send DNS query
          (let ((query (%dns-build-query hostname query-id)))
            (lock-object query)
            (let* ((sqe (loop-get-sqe (loop-ring (loop-current))))
                   (id (loop-alloc-id!)))
              (io-uring-prep-send sqe udp-fd (bytevector-pointer query) (bytevector-length query) 0)
              (io-uring-sqe-set-data64 sqe id)
              (let ((res (loop-abort
                           (lambda (k)
                             (hashtable-set! (loop-handlers (loop-current)) id k)))))
                (unlock-object query)
                (when (fx<? res 0)
                  (loop-close udp-fd)
                  (error 'dns-resolve-a "DNS send failed")))))
          ;; Receive DNS response
          (let ((buf (make-bytevector 512)))
            (lock-object buf)
            ;; IOSQE-IO-LINK requires the recv SQE and its timeout to be
            ;; CONSECUTIVE in the submission queue, so both are reserved
            ;; here BEFORE either is prepped. loop-get-sqe submits on a
            ;; full queue before retrying, and a submit between the two
            ;; would flush the recv on its own and break the link --
            ;; hence reserve-then-prep rather than a per-site
            ;; substitution. Reserving in order also keeps them adjacent:
            ;; the second call cannot submit, because the first already
            ;; guaranteed a slot and nothing else preps in between.
            (let* ((ring (loop-ring (loop-current)))
                   (sqe (loop-get-sqe ring))
                   (tsqe (loop-get-sqe ring))
                   (id (loop-alloc-id!)))
              (io-uring-prep-recv sqe udp-fd (bytevector-pointer buf) 512 0)
              (io-uring-sqe-set-data64 sqe id)
              ;; arm a linked timeout: on expiry the recv completes with
              ;; -ECANCELED and the error path below runs
              (io-uring-sqe-set-flags sqe IOSQE-IO-LINK)
              (unless %dns-recv-timeout-ts
                (set! %dns-recv-timeout-ts
                      (make-timespec %dns-recv-timeout-seconds 0)))
              (begin
                (io-uring-prep-link-timeout
                 tsqe (ftype-pointer-address %dns-recv-timeout-ts) 0)
                (io-uring-sqe-set-data64 tsqe (loop-alloc-id!)))
              (let ((res (loop-abort
                           (lambda (k)
                             (hashtable-set! (loop-handlers (loop-current)) id k)))))
                (unlock-object buf)
                (loop-close udp-fd)
                (when (fx<=? res 0)
                  (error 'dns-resolve-a "DNS recv failed"))
                (let* ((response (subbytevector buf 0 res))
                       (parsed (%dns-parse-response response query-id)))
                  (unless parsed
                    (error 'dns-resolve-a "resolution failed" hostname))
                  (hashtable-set! %dns-cache hostname
                                  (vector (car parsed) (cadr parsed)
                                          (caddr parsed) (cadddr parsed)
                                          ;; the record's own TTL, bounded
                                          (%dns-cache-expiry (car (cddddr parsed)))))
                  (make-sockaddr-in (car parsed) (cadr parsed)
                                    (caddr parsed) (cadddr parsed)
                                    port))))))))

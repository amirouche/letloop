;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Network-free checks: packet encode/parse against fixed bytevectors.
;; dns-resolve-a's io_uring path needs a live loop + nameserver and is
;; exercised by the http server integration scripts.

(define ~check-dns-000
  (lambda ()
    ;; QNAME encoding; a trailing-dot FQDN encodes the same, labels
    ;; longer than 63 bytes and empty labels raise.
    (check #t (and (equal? (bytevector 7 101 120 97 109 112 108 101 3 99 111 109 0)
                           (%dns-encode-name "example.com"))
                   (equal? (%dns-encode-name "example.com")
                           (%dns-encode-name "example.com."))
                   (guard (ex (else #t))
                     (%dns-encode-name (string-append (make-string 64 #\a) ".com"))
                     #f)
                   (guard (ex (else #t))
                     (%dns-encode-name "example..com")
                     #f)))))

(define ~check-dns-001
  (lambda ()
    ;; Query layout: 12-byte header, id, RD=1, QDCOUNT=1, name, A/IN tail.
    (let ((query (%dns-build-query "example.com" #x2A2B)))
      (check #t (and (= (bytevector-length query) (+ 12 13 2 2))
                     (= #x2A (bytevector-u8-ref query 0))  ;; id
                     (= #x2B (bytevector-u8-ref query 1))
                     (= 1 (bytevector-u8-ref query 2))   ;; RD
                     (= 0 (bytevector-u8-ref query 3))
                     (= 1 (bytevector-u8-ref query 5))   ;; QDCOUNT
                     (= 7 (bytevector-u8-ref query 12))  ;; name follows
                     ;; QTYPE=A QCLASS=IN
                     (equal? '(0 1 0 1)
                             (map (lambda (i) (bytevector-u8-ref query i))
                                  (list (- (bytevector-length query) 4)
                                        (- (bytevector-length query) 3)
                                        (- (bytevector-length query) 2)
                                        (- (bytevector-length query) 1)))))))))

(define %dns-check-response
  ;; Response for example.com with one compressed-name A answer
  ;; 93.184.216.34 (crafted, matches what a real resolver returns).
  (bytevector
   0 42                                  ;; id
   #x81 #x80                             ;; QR=1 RD RA, RCODE=0
   0 1                                   ;; QDCOUNT
   0 1                                   ;; ANCOUNT
   0 0 0 0                               ;; NSCOUNT ARCOUNT
   ;; question: example.com A IN
   7 101 120 97 109 112 108 101 3 99 111 109 0
   0 1 0 1
   ;; answer: pointer to offset 12, A IN, ttl, rdlength 4, rdata
   #xC0 #x0C
   0 1 0 1
   0 0 1 44
   0 4
   93 184 216 34))

(define ~check-dns-002
  (lambda ()
    ;; Address AND the record's own TTL -- the fixture's answer carries
    ;; 0 0 1 44 = 300s, which the cache now honours instead of assuming
    ;; a flat 60.
    (check '(93 184 216 34 300) (%dns-parse-response %dns-check-response 42))))

(define ~check-dns-005
  (lambda ()
    ;; %dns-cache-expiry bounds the record's TTL before trusting it.
    ;; A TTL of 0 is legal on the wire and would otherwise mean "never
    ;; cache", i.e. one DNS round trip per connection -- the stampede
    ;; that fills the io_uring submission queue. Clamped up to the
    ;; floor. An absurd TTL is clamped down so a stale address cannot
    ;; be pinned for days.
    (let* ((second (expt 10 9))
           (floor-ns (* %dns-cache-ttl-minimum-seconds second))
           (ceil-ns (* %dns-cache-ttl-maximum-seconds second))
           (near (lambda (expiry want-ns)
                   ;; expiry is now + bounded; allow a generous slack
                   ;; so a slow check host cannot make this flaky.
                   (let ((delta (- expiry (jiffy-current))))
                     (and (> delta (- want-ns second))
                          (<= delta (+ want-ns second)))))))
      (check #t (and (near (%dns-cache-expiry 0) floor-ns)
                     (near (%dns-cache-expiry 1) floor-ns)
                     (near (%dns-cache-expiry 300) (* 300 second))
                     (near (%dns-cache-expiry 999999) ceil-ns)
                     ;; a malformed TTL degrades to the floor rather
                     ;; than raising or caching forever
                     (near (%dns-cache-expiry #f) floor-ns))))))

(define ~check-dns-003
  (lambda ()
    ;; RCODE=3 (NXDOMAIN) yields #f, as do a truncated packet, a
    ;; response whose ID does not echo the query ID, and a response
    ;; with the TC (truncation) bit set.
    (let ((nxdomain (bytevector-copy %dns-check-response))
          (wrong-id (bytevector-copy %dns-check-response))
          (tc-set (bytevector-copy %dns-check-response)))
      (bytevector-u8-set! nxdomain 3 #x83)
      (bytevector-u8-set! wrong-id 1 43)
      (bytevector-u8-set! tc-set 2 #x83)  ;; QR=1 RD TC
      (check #t (and (not (%dns-parse-response nxdomain 42))
                     (not (%dns-parse-response (bytevector 0 1 2) 42))
                     (not (%dns-parse-response wrong-id 42))
                     (not (%dns-parse-response tc-set 42)))))))

(define ~check-dns-004
  (lambda ()
    ;; Dotted IPv4 literals skip DNS entirely, even without a loop.
    (check #t (and (%dns-ip-string? "127.0.0.1")
                   (not (%dns-ip-string? "example.com"))
                   (call-with-values (lambda () (%dns-parse-ip "10.20.30.40"))
                     (lambda (a b c d)
                       (equal? '(10 20 30 40) (list a b c d))))
                   (call-with-values (lambda () (dns-resolve-a "127.0.0.1" 8080))
                     (lambda (addr addrlen)
                       (foreign-free addr)
                       (fx>? addrlen 0)))))))

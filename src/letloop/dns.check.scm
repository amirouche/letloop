;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Network-free checks: packet encode/parse against fixed bytevectors.
;; dns-resolve-a's io_uring path needs a live loop + nameserver and is
;; exercised by the http server integration scripts.

(define ~check-dns-000
  (lambda ()
    ;; QNAME encoding
    (check (bytevector 7 101 120 97 109 112 108 101 3 99 111 109 0)
           (%dns-encode-name "example.com"))))

(define ~check-dns-001
  (lambda ()
    ;; Query layout: 12-byte header, RD=1, QDCOUNT=1, name, A/IN tail.
    (let ((query (%dns-build-query "example.com")))
      (check #t (and (= (bytevector-length query) (+ 12 13 2 2))
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
    (call-with-values (lambda () (%dns-parse-response %dns-check-response))
      (lambda (a b c d)
        (check '(93 184 216 34) (list a b c d))))))

(define ~check-dns-003
  (lambda ()
    ;; RCODE=3 (NXDOMAIN) yields #f, as does a truncated packet.
    (let ((nxdomain (bytevector-copy %dns-check-response)))
      (bytevector-u8-set! nxdomain 3 #x83)
      (check #t (and (not (%dns-parse-response nxdomain))
                     (not (%dns-parse-response (bytevector 0 1 2))))))))

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

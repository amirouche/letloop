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
    (let ((parts (let split ((chars (string->list hostname))
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
                          (let ((out (make-bytevector (+ 1 (bytevector-length bv)))))
                            (bytevector-u8-set! out 0 (bytevector-length bv))
                            (bytevector-copy! bv 0 out 1 (bytevector-length bv))
                            out)))
                      parts)))
        (apply bytevector-append (append bvs (list (bytevector 0))))))))

(define %dns-build-query
  (lambda (hostname)
    (let* ((id-hi (random 256))
           (id-lo (random 256))
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

(define %dns-parse-response
  (lambda (bv)
    ;; Returns (values a b c d) for IPv4 or #f on failure
    (guard (ex (else #f))
      (when (< (bytevector-length bv) 12)
        (error 'dns "Response too short"))
      ;; Check QR=1 (response)
      (let ((flags (bytevector-u8-ref bv 2)))
        (unless (not (fxzero? (fxlogand flags #x80)))
          (error 'dns "Not a response")))
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
                                  (values (bytevector-u8-ref bv rdata-pos)
                                          (bytevector-u8-ref bv (+ rdata-pos 1))
                                          (bytevector-u8-ref bv (+ rdata-pos 2))
                                          (bytevector-u8-ref bv (+ rdata-pos 3)))
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
                                  (values (bytevector-u8-ref bv rdata-pos)
                                          (bytevector-u8-ref bv (+ rdata-pos 1))
                                          (bytevector-u8-ref bv (+ rdata-pos 2))
                                          (bytevector-u8-ref bv (+ rdata-pos 3)))
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
    ;; already a dotted IPv4 literal.
    (if (%dns-ip-string? hostname)
        ;; Already an IP address
        (call-with-values (lambda () (%dns-parse-ip hostname))
          (lambda (a b c d)
            (make-sockaddr-in a b c d port)))
        ;; DNS lookup via io_uring
        (let* ((ns (%dns-get-nameserver))
               (udp-fd (loop-socket-new 2 2 0)))  ;; AF_INET, SOCK_DGRAM
          (unless udp-fd (error 'dns-resolve-a "UDP socket failed"))
          (loop-nonblock! udp-fd)
          ;; Connect UDP socket to nameserver:53
          (call-with-values (lambda () (%dns-parse-ip ns))
            (lambda (a b c d)
              (call-with-values (lambda () (make-sockaddr-in a b c d 53))
                (lambda (ns-addr ns-addrlen)
                  (let* ((sqe (io-uring-get-sqe (loop-ring (loop-current))))
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
          (let ((query (%dns-build-query hostname)))
            (lock-object query)
            (let* ((sqe (io-uring-get-sqe (loop-ring (loop-current))))
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
            (let* ((sqe (io-uring-get-sqe (loop-ring (loop-current))))
                   (id (loop-alloc-id!)))
              (io-uring-prep-recv sqe udp-fd (bytevector-pointer buf) 512 0)
              (io-uring-sqe-set-data64 sqe id)
              (let ((res (loop-abort
                           (lambda (k)
                             (hashtable-set! (loop-handlers (loop-current)) id k)))))
                (unlock-object buf)
                (loop-close udp-fd)
                (when (fx<=? res 0)
                  (error 'dns-resolve-a "DNS recv failed"))
                (let ((response (subbytevector buf 0 res)))
                  (call-with-values (lambda () (%dns-parse-response response))
                    (lambda (a b c d)
                      (make-sockaddr-in a b c d port)))))))))))

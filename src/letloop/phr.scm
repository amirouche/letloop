#!chezscheme
;; Pure-Scheme port of picohttpparser (https://github.com/h2o/picohttpparser)
;;
;; Derived from the picohttpparser algorithm:
;;
;;   Copyright (c) 2009-2014 Kazuho Oku, Tokuhiro Matsuno, Daisuke Murase,
;;                           Shigeo Mitsunari
;;
;;   Permission is hereby granted, free of charge, to any person obtaining
;;   a copy of this software and associated documentation files (the
;;   "Software"), to deal in the Software without restriction, including
;;   without limitation the rights to use, copy, modify, merge, publish,
;;   distribute, sublicense, and/or sell copies of the Software, and to
;;   permit persons to whom the Software is furnished to do so, subject to
;;   the following conditions:
;;
;;   The above copyright notice and this permission notice shall be
;;   included in all copies or substantial portions of the Software.
;;
;;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;;   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;;   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;;   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;;   SOFTWARE.
;;
;; Drop-in replacement for (letloop picohttpparser): same procedure names,
;; same result representation, and the same output-buffer layout as
;; picohttpparser_wrapper.c. Parsing never leaves Scheme: no shared object,
;; no foreign call, no bytevector locking.
;;
;; Output buffer layout (all offsets relative to the input bytevector):
;;
;;   Request                          Response
;;   [0..7]   method_offset (u64)     [0..3]   status (s32)
;;   [8..15]  method_len (u64)        [4..7]   minor_version (s32)
;;   [16..23] path_offset (u64)       [8..15]  msg_offset (u64)
;;   [24..31] path_len (u64)          [16..23] msg_len (u64)
;;   [32..35] minor_version (s32)     [24..31] num_headers (u64)
;;   [40..47] num_headers (u64)       [32..]   header slots
;;   [48..]   header slots
;;
;;   Each header slot is 32 bytes:
;;   [+0..+7] name_offset, [+8..+15] name_len,
;;   [+16..+23] value_offset, [+24..+31] value_len
;;   (name_len = 0 encodes a continuation line, i.e. obsolete folding)
(library (letloop phr)
  (export phr-parse-request
          phr-request?
          phr-request-bytes-consumed
          phr-request-method
          phr-request-path
          phr-request-minor-version
          phr-request-header-count
          phr-request-header-name
          phr-request-header-value
          phr-request-header-ref
          phr-parse-response
          phr-response?
          phr-response-bytes-consumed
          phr-response-status
          phr-response-minor-version
          phr-response-message
          phr-response-header-count
          phr-response-header-name
          phr-response-header-value
          phr-response-header-ref
          ~check-phr-000
          ~check-phr-001
          ~check-phr-002
          ~check-phr-003
          ~check-phr-004
          ~check-phr-005
          ~check-phr-006
          ~check-phr-007
          ~check-phr-008
          ~check-phr-009)

  (import (chezscheme))

  ;; Maximum headers per request/response
  (define %phr-max-headers 100)

  ;; Output buffer size: 48 bytes header + 32 bytes per header slot
  (define %request-out-size (fx+ 48 (fx* %phr-max-headers 32)))

  ;; Response output buffer: 32 bytes header + 32 bytes per header slot
  (define %response-out-size (fx+ 32 (fx* %phr-max-headers 32)))

  (define %native (native-endianness))

  (define %error -1)
  (define %incomplete -2)

  (define %CR 13)
  (define %LF 10)
  (define %SP 32)
  (define %HTAB 9)
  (define %COLON 58)

  ;; RFC 7230 tchar table, same as picohttpparser's token_char_map
  (define %token-char
    (let ((bv (make-bytevector 256 0)))
      (define mark!
        (lambda (c)
          (bytevector-u8-set! bv (char->integer c) 1)))
      (for-each mark! (string->list "!#$%&'*+-.^_`|~"))
      (let loop ((c (char->integer #\0)))
        (when (fx<=? c (char->integer #\9))
          (bytevector-u8-set! bv c 1)
          (loop (fx+ c 1))))
      (let loop ((c (char->integer #\A)))
        (when (fx<=? c (char->integer #\Z))
          (bytevector-u8-set! bv c 1)
          (loop (fx+ c 1))))
      (let loop ((c (char->integer #\a)))
        (when (fx<=? c (char->integer #\z))
          (bytevector-u8-set! bv c 1)
          (loop (fx+ c 1))))
      bv))

  ;; ADVANCE_TOKEN: scan until SP; bytes < 0x20 and 0x7F are rejected,
  ;; bytes >= 0x80 are accepted. Returns the index of the terminating SP.
  (define %advance-token
    (lambda (buf len idx)
      (let loop ((i idx))
        (if (fx=? i len)
            %incomplete
            (let ((b (bytevector-u8-ref buf i)))
              (cond
               ((fx=? b %SP) i)
               ((or (fx<? b 32) (fx=? b 127)) %error)
               (else (loop (fx+ i 1)))))))))

  ;; do { ++buf; CHECK_EOF(); } while (*buf == ' ')
  (define %skip-spaces
    (lambda (buf len idx)
      (let loop ((i (fx+ idx 1)))
        (if (fx=? i len)
            %incomplete
            (if (fx=? (bytevector-u8-ref buf i) %SP)
                (loop (fx+ i 1))
                i)))))

  ;; parse_token with next_char = ':' — header field name.
  ;; Caller guarantees idx < len. Returns the index of the colon.
  (define %token-until-colon
    (lambda (buf len idx)
      (let loop ((i idx))
        (let ((b (bytevector-u8-ref buf i)))
          (cond
           ((fx=? b %COLON) i)
           ((fxzero? (bytevector-u8-ref %token-char b)) %error)
           (else
            (let ((next (fx+ i 1)))
              (if (fx=? next len)
                  %incomplete
                  (loop next)))))))))

  ;; get_token_to_eol: scan a field value (or response message) up to CR/LF.
  ;; HTAB, 0x20..0x7E and >= 0x80 are accepted; other control bytes are an
  ;; error. Writes value offset/length into OUT at OFF-POS/LEN-POS and
  ;; returns the index just after the line terminator.
  (define %token-to-eol
    (lambda (buf len idx out off-pos len-pos)
      (define found!
        (lambda (end next)
          (bytevector-u64-set! out off-pos idx %native)
          (bytevector-u64-set! out len-pos (fx- end idx) %native)
          next))
      (let loop ((i idx))
        (if (fx=? i len)
            %incomplete
            (let ((b (bytevector-u8-ref buf i)))
              (cond
               ((and (fx>=? b 32) (fx<=? b 126)) (loop (fx+ i 1)))
               ((fx=? b %CR)
                (let ((next (fx+ i 1)))
                  (cond
                   ((fx=? next len) %incomplete)
                   ((fx=? (bytevector-u8-ref buf next) %LF)
                    (found! i (fx+ i 2)))
                   (else %error))))
               ((fx=? b %LF)
                (found! i (fx+ i 1)))
               ((or (fx=? b %HTAB) (fx>? b 127)) (loop (fx+ i 1)))
               (else %error)))))))

  ;; Remove trailing SPs and HTABs from the value stored in SLOT.
  (define %trim-trailing!
    (lambda (out slot buf)
      (let ((voff (bytevector-u64-ref out (fx+ slot 16) %native)))
        (let loop ((l (bytevector-u64-ref out (fx+ slot 24) %native)))
          (if (and (fx>? l 0)
                   (let ((c (bytevector-u8-ref buf (fx+ voff (fx- l 1)))))
                     (or (fx=? c %SP) (fx=? c %HTAB))))
              (loop (fx- l 1))
              (bytevector-u64-set! out (fx+ slot 24) l %native))))))

  ;; parse_headers: header slots go to OUT at HBASE, count at COUNT-POS.
  ;; Returns the index just past the terminating empty line.
  (define %parse-headers
    (lambda (buf len idx out hbase count-pos max-headers)

      ;; parse the value of slot for header N starting at J, then loop
      (define value!
        (lambda (j n slot continue)
          (let ((r (%token-to-eol buf len j out (fx+ slot 16) (fx+ slot 24))))
            (if (fx<? r 0)
                r
                (begin
                  (%trim-trailing! out slot buf)
                  (continue r (fx+ n 1)))))))

      (let loop ((i idx) (n 0))
        (if (fx=? i len)
            %incomplete
            (let ((b (bytevector-u8-ref buf i))
                  (slot (fx+ hbase (fx* n 32))))
              (cond
               ((fx=? b %CR)
                (let ((next (fx+ i 1)))
                  (cond
                   ((fx=? next len) %incomplete)
                   ((fx=? (bytevector-u8-ref buf next) %LF)
                    (bytevector-u64-set! out count-pos n %native)
                    (fx+ i 2))
                   (else %error))))
               ((fx=? b %LF)
                (bytevector-u64-set! out count-pos n %native)
                (fx+ i 1))
               ((fx=? n max-headers) %error)
               ((and (fx>? n 0) (or (fx=? b %SP) (fx=? b %HTAB)))
                ;; obsolete line folding: continuation line, no name;
                ;; the value keeps its leading whitespace
                (bytevector-u64-set! out slot 0 %native)
                (bytevector-u64-set! out (fx+ slot 8) 0 %native)
                (value! i n slot loop))
               (else
                (let ((colon (%token-until-colon buf len i)))
                  (cond
                   ((fx<? colon 0) colon)
                   ((fx=? colon i) %error) ;; empty field name
                   (else
                    (bytevector-u64-set! out slot i %native)
                    (bytevector-u64-set! out (fx+ slot 8) (fx- colon i) %native)
                    ;; skip ':' then leading SPs and HTABs
                    (let skip ((j (fx+ colon 1)))
                      (cond
                       ((fx=? j len) %incomplete)
                       ((let ((c (bytevector-u8-ref buf j)))
                          (or (fx=? c %SP) (fx=? c %HTAB)))
                        (skip (fx+ j 1)))
                       (else (value! j n slot loop))))))))))))))

  ;; parse_http_version: expects "HTTP/1." followed by one digit, and wants
  ;; at least one more byte after the version to be present.
  (define %parse-http-version
    (lambda (buf len idx out minor-pos)
      (if (fx<? (fx- len idx) 9)
          %incomplete
          (if (and (fx=? (bytevector-u8-ref buf idx) (char->integer #\H))
                   (fx=? (bytevector-u8-ref buf (fx+ idx 1)) (char->integer #\T))
                   (fx=? (bytevector-u8-ref buf (fx+ idx 2)) (char->integer #\T))
                   (fx=? (bytevector-u8-ref buf (fx+ idx 3)) (char->integer #\P))
                   (fx=? (bytevector-u8-ref buf (fx+ idx 4)) (char->integer #\/))
                   (fx=? (bytevector-u8-ref buf (fx+ idx 5)) (char->integer #\1))
                   (fx=? (bytevector-u8-ref buf (fx+ idx 6)) (char->integer #\.)))
              (let ((d (bytevector-u8-ref buf (fx+ idx 7))))
                (if (and (fx>=? d 48) (fx<=? d 57))
                    (begin
                      (bytevector-s32-set! out minor-pos (fx- d 48) %native)
                      (fx+ idx 8))
                    %error))
              %error))))

  ;; is_complete: quick scan for the end of the header section, used when
  ;; last_len != 0 to bail out early on incomplete input.
  (define %is-complete
    (lambda (buf len last-len)
      (let loop ((i (if (fx<? last-len 3) 0 (fx- last-len 3)))
                 (cnt 0))
        (if (fx=? i len)
            %incomplete
            (let ((b (bytevector-u8-ref buf i)))
              (cond
               ((fx=? b %CR)
                (let ((next (fx+ i 1)))
                  (cond
                   ((fx=? next len) %incomplete)
                   ((fx=? (bytevector-u8-ref buf next) %LF)
                    (if (fx=? cnt 1)
                        (fx+ i 2)
                        (loop (fx+ i 2) (fx+ cnt 1))))
                   (else %error))))
               ((fx=? b %LF)
                (if (fx=? cnt 1)
                    (fx+ i 1)
                    (loop (fx+ i 1) (fx+ cnt 1))))
               (else (loop (fx+ i 1) 0))))))))

  ;; phr_parse_request: returns bytes consumed (> 0), %error or %incomplete.
  (define %parse-request!
    (lambda (buf len out max-headers)

      (define version+eol
        (lambda (k)
          (let ((v (%parse-http-version buf len k out 32)))
            (if (fx<? v 0)
                v
                (let ((b (bytevector-u8-ref buf v)))
                  (cond
                   ((fx=? b %CR)
                    (let ((next (fx+ v 1)))
                      (cond
                       ((fx=? next len) %incomplete)
                       ((fx=? (bytevector-u8-ref buf next) %LF)
                        (%parse-headers buf len (fx+ v 2) out 48 40 max-headers))
                       (else %error))))
                   ((fx=? b %LF)
                    (%parse-headers buf len (fx+ v 1) out 48 40 max-headers))
                   (else %error)))))))

      (define request-line
        (lambda (i)
          (let ((sp (%advance-token buf len i)))
            (if (fx<? sp 0)
                sp
                (let ((j (%skip-spaces buf len sp)))
                  (if (fx<? j 0)
                      j
                      (let ((sp2 (%advance-token buf len j)))
                        (if (fx<? sp2 0)
                            sp2
                            (let ((k (%skip-spaces buf len sp2)))
                              (cond
                               ((fx<? k 0) k)
                               ;; empty method or path
                               ((or (fx=? sp i) (fx=? sp2 j)) %error)
                               (else
                                (bytevector-u64-set! out 0 i %native)
                                (bytevector-u64-set! out 8 (fx- sp i) %native)
                                (bytevector-u64-set! out 16 j %native)
                                (bytevector-u64-set! out 24 (fx- sp2 j) %native)
                                (version+eol k))))))))))))

      ;; skip first empty line (some clients add CRLF after POST content)
      (define skip-empty-line
        (lambda ()
          (let ((b (bytevector-u8-ref buf 0)))
            (cond
             ((fx=? b %CR)
              (cond
               ((fx=? len 1) %incomplete)
               ((fx=? (bytevector-u8-ref buf 1) %LF) 2)
               (else %error)))
             ((fx=? b %LF) 1)
             (else 0)))))

      (if (fxzero? len)
          %incomplete
          (let ((i (skip-empty-line)))
            (cond
             ((fx<? i 0) i)
             ((fx=? i len) %incomplete)
             (else (request-line i)))))))

  ;; phr_parse_response: returns bytes consumed (> 0), %error or %incomplete.
  (define %parse-response!
    (lambda (buf len out max-headers)

      (define headers
        (lambda (r)
          (%parse-headers buf len r out 32 24 max-headers)))

      ;; message starts right after the 3-digit status and includes the
      ;; preceding space, which is then stripped
      (define message
        (lambda (i)
          (let ((r (%token-to-eol buf len i out 8 16)))
            (if (fx<? r 0)
                r
                (let ((moff (bytevector-u64-ref out 8 %native))
                      (mlen (bytevector-u64-ref out 16 %native)))
                  (cond
                   ((fxzero? mlen) (headers r))
                   ((fx=? (bytevector-u8-ref buf moff) %SP)
                    (let trim ((o moff) (l mlen))
                      (if (and (fx>? l 0)
                               (fx=? (bytevector-u8-ref buf o) %SP))
                          (trim (fx+ o 1) (fx- l 1))
                          (begin
                            (bytevector-u64-set! out 8 o %native)
                            (bytevector-u64-set! out 16 l %native)
                            (headers r)))))
                   ;; garbage found after status code
                   (else %error)))))))

      (define status
        (lambda (i)
          ;; we want at least [:digit:][:digit:][:digit:]<other char>
          (if (fx<? (fx- len i) 4)
              %incomplete
              (let ((d0 (fx- (bytevector-u8-ref buf i) 48))
                    (d1 (fx- (bytevector-u8-ref buf (fx+ i 1)) 48))
                    (d2 (fx- (bytevector-u8-ref buf (fx+ i 2)) 48)))
                (if (and (fx<=? 0 d0 9) (fx<=? 0 d1 9) (fx<=? 0 d2 9))
                    (begin
                      (bytevector-s32-set! out 0
                                           (fx+ (fx* d0 100) (fx* d1 10) d2)
                                           %native)
                      (message (fx+ i 3)))
                    %error)))))

      (let ((v (%parse-http-version buf len 0 out 4)))
        (cond
         ((fx<? v 0) v)
         ((not (fx=? (bytevector-u8-ref buf v) %SP)) %error)
         (else
          (let ((i (%skip-spaces buf len v)))
            (if (fx<? i 0)
                i
                (status i))))))))

  ;; ---- Public API, identical to (letloop picohttpparser) ----

  (define %parse
    (lambda (buf rest parse! out-size tag)
      (let ((max-headers (if (and (pair? rest) (pair? (cdr rest)))
                             (fxmin (cadr rest) %phr-max-headers)
                             %phr-max-headers))
            (last-len (if (pair? rest) (car rest) 0))
            (len (bytevector-length buf)))
        (let ((quick (if (fxzero? last-len)
                         0
                         (%is-complete buf len last-len))))
          (if (fx<? quick 0)
              (if (fx=? quick %incomplete) 'incomplete #f)
              (let ((out (make-bytevector out-size 0)))
                (let ((ret (parse! buf len out max-headers)))
                  (cond
                   ((fx>? ret 0) (vector tag buf out ret))
                   ((fx=? ret %incomplete) 'incomplete)
                   (else #f)))))))))

  (define phr-parse-request
    (lambda (buf . rest)
      (%parse buf rest %parse-request! %request-out-size 'phr-request)))

  (define phr-parse-response
    (lambda (buf . rest)
      (%parse buf rest %parse-response! %response-out-size 'phr-response)))

  (define phr-request?
    (lambda (x)
      (and (vector? x)
           (fx=? (vector-length x) 4)
           (eq? (vector-ref x 0) 'phr-request))))

  (define phr-response?
    (lambda (x)
      (and (vector? x)
           (fx=? (vector-length x) 4)
           (eq? (vector-ref x 0) 'phr-response))))

  (define %subbytevector
    (lambda (bv start end)
      (let ((out (make-bytevector (fx- end start))))
        (bytevector-copy! bv start out 0 (fx- end start))
        out)))

  (define %phr-buf (lambda (req) (vector-ref req 1)))
  (define %phr-out (lambda (req) (vector-ref req 2)))

  (define phr-request-bytes-consumed
    (lambda (req)
      (vector-ref req 3)))

  ;; Lazy accessor: extracts method string from buffer only when called
  (define phr-request-method
    (lambda (req)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((offset (bytevector-u64-ref out 0 %native))
              (len (bytevector-u64-ref out 8 %native)))
          (utf8->string (%subbytevector buf offset (fx+ offset len)))))))

  ;; Lazy accessor: extracts path string from buffer only when called
  (define phr-request-path
    (lambda (req)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((offset (bytevector-u64-ref out 16 %native))
              (len (bytevector-u64-ref out 24 %native)))
          (utf8->string (%subbytevector buf offset (fx+ offset len)))))))

  (define phr-request-minor-version
    (lambda (req)
      (bytevector-s32-ref (%phr-out req) 32 %native)))

  (define phr-request-header-count
    (lambda (req)
      (bytevector-u64-ref (%phr-out req) 40 %native)))

  ;; Lazy accessor: extracts a single header name by index
  (define phr-request-header-name
    (lambda (req index)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((base (fx+ 48 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out base %native))
                (len (bytevector-u64-ref out (fx+ base 8) %native)))
            (if (fxzero? len)
                #f
                (utf8->string (%subbytevector buf offset (fx+ offset len)))))))))

  ;; Lazy accessor: extracts a single header value by index
  (define phr-request-header-value
    (lambda (req index)
      (let ((out (%phr-out req))
            (buf (%phr-buf req)))
        (let ((base (fx+ 48 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out (fx+ base 16) %native))
                (len (bytevector-u64-ref out (fx+ base 24) %native)))
            (utf8->string (%subbytevector buf offset (fx+ offset len))))))))

  ;; Lazy lookup: find header value by name (case-insensitive)
  (define phr-request-header-ref
    (lambda (req name)
      (let ((count (phr-request-header-count req))
            (target (string-downcase name)))
        (let loop ((i 0))
          (if (fx>=? i count)
              #f
              (let ((hdr-name (phr-request-header-name req i)))
                (if (and hdr-name (string-ci=? hdr-name target))
                    (phr-request-header-value req i)
                    (loop (fx+ i 1)))))))))

  (define phr-response-bytes-consumed
    (lambda (resp)
      (vector-ref resp 3)))

  (define phr-response-status
    (lambda (resp)
      (bytevector-s32-ref (%phr-out resp) 0 %native)))

  (define phr-response-minor-version
    (lambda (resp)
      (bytevector-s32-ref (%phr-out resp) 4 %native)))

  ;; Lazy accessor: extracts response message from buffer only when called
  (define phr-response-message
    (lambda (resp)
      (let ((out (%phr-out resp))
            (buf (%phr-buf resp)))
        (let ((offset (bytevector-u64-ref out 8 %native))
              (len (bytevector-u64-ref out 16 %native)))
          (if (fxzero? len)
              ""
              (utf8->string (%subbytevector buf offset (fx+ offset len))))))))

  (define phr-response-header-count
    (lambda (resp)
      (bytevector-u64-ref (%phr-out resp) 24 %native)))

  ;; Lazy accessor: extracts a single header name by index
  (define phr-response-header-name
    (lambda (resp index)
      (let ((out (%phr-out resp))
            (buf (%phr-buf resp)))
        (let ((base (fx+ 32 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out base %native))
                (len (bytevector-u64-ref out (fx+ base 8) %native)))
            (if (fxzero? len)
                #f
                (utf8->string (%subbytevector buf offset (fx+ offset len)))))))))

  ;; Lazy accessor: extracts a single header value by index
  (define phr-response-header-value
    (lambda (resp index)
      (let ((out (%phr-out resp))
            (buf (%phr-buf resp)))
        (let ((base (fx+ 32 (fx* index 32))))
          (let ((offset (bytevector-u64-ref out (fx+ base 16) %native))
                (len (bytevector-u64-ref out (fx+ base 24) %native)))
            (utf8->string (%subbytevector buf offset (fx+ offset len))))))))

  ;; Lazy lookup: find header value by name (case-insensitive)
  (define phr-response-header-ref
    (lambda (resp name)
      (let ((count (phr-response-header-count resp))
            (target (string-downcase name)))
        (let loop ((i 0))
          (if (fx>=? i count)
              #f
              (let ((hdr-name (phr-response-header-name resp i)))
                (if (and hdr-name (string-ci=? hdr-name target))
                    (phr-response-header-value resp i)
                    (loop (fx+ i 1)))))))))

  ;; ---- Tests ----

  ;; Basic GET request parsing
  (define ~check-phr-000
    (lambda ()
      (let* ((raw "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-method req) "GET"))
        (assert (string=? (phr-request-path req) "/"))
        (assert (fx=? (phr-request-minor-version req) 1))
        (assert (fx=? (phr-request-header-count req) 1))
        (assert (string-ci=? (phr-request-header-name req 0) "Host"))
        (assert (string=? (phr-request-header-value req 0) "example.com")))))

  ;; Multiple headers, lazy individual access
  (define ~check-phr-001
    (lambda ()
      (let* ((raw (string-append
                   "POST /api/data HTTP/1.1\r\n"
                   "Host: example.com\r\n"
                   "Content-Type: application/json\r\n"
                   "Content-Length: 13\r\n"
                   "X-Custom: hello\r\n"
                   "\r\n"))
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-method req) "POST"))
        (assert (string=? (phr-request-path req) "/api/data"))
        (assert (fx=? (phr-request-header-count req) 4))
        (assert (string=? (phr-request-header-ref req "Content-Type") "application/json"))
        (assert (string=? (phr-request-header-ref req "x-custom") "hello"))
        (assert (not (phr-request-header-ref req "nonexistent"))))))

  ;; Incomplete request returns 'incomplete
  (define ~check-phr-002
    (lambda ()
      (let* ((raw "GET / HTTP/1.1\r\nHost: ex")
             (buf (string->utf8 raw)))
        (assert (eq? (phr-parse-request buf) 'incomplete)))))

  ;; Bytes consumed is correct
  (define ~check-phr-003
    (lambda ()
      (let* ((raw "GET /hello HTTP/1.0\r\n\r\nextra body data")
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-path req) "/hello"))
        (assert (fx=? (phr-request-minor-version req) 0))
        (assert (fx=? (phr-request-bytes-consumed req)
                      (string-length "GET /hello HTTP/1.0\r\n\r\n"))))))

  ;; Response parsing
  (define ~check-phr-004
    (lambda ()
      (let* ((raw (string-append
                   "HTTP/1.1 200 OK\r\n"
                   "Content-Type: text/html\r\n"
                   "Content-Length: 5\r\n"
                   "\r\n"))
             (buf (string->utf8 raw))
             (resp (phr-parse-response buf)))
        (assert (phr-response? resp))
        (assert (fx=? (phr-response-status resp) 200))
        (assert (fx=? (phr-response-minor-version resp) 1))
        (assert (string=? (phr-response-message resp) "OK"))
        (assert (fx=? (phr-response-header-count resp) 2))
        (assert (string=? (phr-response-header-ref resp "Content-Type") "text/html"))
        (assert (string=? (phr-response-header-ref resp "content-length") "5")))))

  ;; Obsolete line folding: continuation recorded as a nameless header
  (define ~check-phr-005
    (lambda ()
      (let* ((raw (string-append
                   "GET / HTTP/1.1\r\n"
                   "X-Multi: first\r\n"
                   "  continued\r\n"
                   "Host: example.com\r\n"
                   "\r\n"))
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (fx=? (phr-request-header-count req) 3))
        (assert (string=? (phr-request-header-value req 0) "first"))
        (assert (not (phr-request-header-name req 1)))
        ;; picohttpparser keeps the folded line's leading whitespace
        (assert (string=? (phr-request-header-value req 1) "  continued"))
        (assert (string=? (phr-request-header-ref req "host") "example.com")))))

  ;; Trailing whitespace in values is trimmed, empty values are allowed
  (define ~check-phr-006
    (lambda ()
      (let* ((raw (string-append
                   "GET / HTTP/1.1\r\n"
                   "X-Padded:   value  \t \r\n"
                   "X-Empty:\r\n"
                   "\r\n"))
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-header-ref req "x-padded") "value"))
        (assert (string=? (phr-request-header-ref req "x-empty") "")))))

  ;; Lone LF line endings are accepted, like picohttpparser
  (define ~check-phr-007
    (lambda ()
      (let* ((raw "GET /lf HTTP/1.1\nHost: example.com\n\n")
             (buf (string->utf8 raw))
             (req (phr-parse-request buf)))
        (assert (phr-request? req))
        (assert (string=? (phr-request-path req) "/lf"))
        (assert (fx=? (phr-request-bytes-consumed req) (string-length raw)))
        (assert (string=? (phr-request-header-ref req "host") "example.com")))))

  ;; Malformed input is rejected: bad version, garbage after status
  (define ~check-phr-008
    (lambda ()
      (assert (not (phr-parse-request (string->utf8 "GET / HTTP/2.0\r\n\r\n"))))
      (assert (not (phr-parse-request (string->utf8 "GET / FTP/1.1\r\n\r\n"))))
      (assert (not (phr-parse-request (string->utf8 " / HTTP/1.1\r\n\r\n"))))
      (assert (not (phr-parse-response (string->utf8 "HTTP/1.1 200X\r\n\r\n"))))
      (assert (not (phr-parse-response (string->utf8 "HTTP/1.1 abc OK\r\n\r\n"))))))

  ;; last-len fast path: growing buffer stays 'incomplete until terminator
  (define ~check-phr-009
    (lambda ()
      (let* ((raw "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
             (full (string->utf8 raw))
             (part (%subbytevector full 0 20)))
        (assert (eq? (phr-parse-request part) 'incomplete))
        (assert (eq? (phr-parse-request (%subbytevector full 0 30) 20)
                     'incomplete))
        (let ((req (phr-parse-request full 30)))
          (assert (phr-request? req))
          (assert (fx=? (phr-request-bytes-consumed req)
                        (bytevector-length full)))))))

  )

;; Copyright © 2026 Amirouche A. BOUBEKKI <amirouche at hyper dev>
;;
;; Included at the tail of the library; discovered by `make check` via
;; the ~check- exports.

;; ---- Tests ----

(define (~check-sha256-empty)
  (assert (string=? (sha256-hex #vu8())
                    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")))

(define (~check-sha256-abc)
  (assert (string=? (sha256-hex (string->utf8 "abc"))
                    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")))

(define (~check-sha256-two-blocks)
  ;; 56-byte message: exercises the padding boundary and a second block
  (assert (string=? (sha256-hex (string->utf8 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
                    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")))

(define (~check-sha256-million-a)
  (assert (string=? (sha256-hex (make-bytevector 1000000 97))
                    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")))

(define (~check-hmac-sha256-rfc4231-case-1)
  (assert (string=? (hmac-sha256-hex (make-bytevector 20 #x0b)
                                     (string->utf8 "Hi There"))
                    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")))

(define (~check-hmac-sha256-rfc4231-case-2)
  (assert (string=? (hmac-sha256-hex (string->utf8 "Jefe")
                                     (string->utf8 "what do ya want for nothing?"))
                    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")))

(define (~check-hmac-sha256-long-key)
  ;; RFC 4231 case 6: 131-byte key forces the key-hashing path
  (assert (string=? (hmac-sha256-hex (make-bytevector 131 #xaa)
                                     (string->utf8 "Test Using Larger Than Block-Size Key - Hash Key First"))
                    "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")))

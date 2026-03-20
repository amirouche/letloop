;;
;; WARNING: This is hand-rolled cryptography. It has NOT been
;; independently audited. Use at your own risk. Do NOT use in
;; production systems without a thorough security review by a
;; qualified cryptographer.
;;

(library (letloop srp)
  (export PARAMETER-2048
          make-srp-client-verifier
          make-srp-server
          make-srp-client
          srp-client-A
          srp-server-A!
          srp-server-B
          srp-client-B!
          srp-server-K
          srp-server-M2
          srp-server-check-M1?
          srp-client-K
          srp-client-M1
          srp-client-check-M2?
          ~check-srp-000
          ~check-srp-rfc5054)
  (import (chezscheme)
          (letloop bytevector)
          (letloop sodium)
          (letloop r999))

  ;; The SRP Authentication and Key Exchange System
  ;;
  ;; ref: https://datatracker.ietf.org/doc/html/rfc5054
  ;; ref: https://datatracker.ietf.org/doc/html/rfc2945
  ;; ref: http://srp.stanford.edu/doc.html
  ;;
  ;; Hash function: SHA-256 via libsodium (modern replacement for
  ;; SHA-1 specified in RFC 5054, per section 3.4 guidance)
  ;;
  ;; TODO: Use unicode NFKD normalization to avoid problems because of
  ;; the input method

  ;; RFC 5054 section 2.1: "Conversion between integers and
  ;; byte-strings assumes the most significant bytes are stored first"
  ;; NOTE: despite the names, these functions are big-endian.
  (define ->bytevector integer->bytevector-little-endian)
  (define ->integer bytevector-little-endian->integer)

  (define-record-type* <srp-value>
    (make-srp-value~ name proc)
    srp-value?
    (name srp-value-name)
    (proc srp-value-proc))

  (define make-srp-value
    (lambda (name length)
      (let ((bytevector #f)
            (integer #f)
            (frozen #f)
            (length length))
        (make-srp-value~
         name
         (lambda (message type . object)
           (case message
             (ref (case type
                    (name name)
                    (integer (or (and frozen integer)
                                 (error 'srp "value not set" name)))
                    (bytevector (or (and frozen bytevector)
                                    (error 'srp "value not set" name)))
                    (else (error 'srp "unknown ref type" type))))
             (set (case type
                    (integer (or (and frozen
                                      (error 'srp
                                             "value frozen"
                                             name))
                                 (begin
                                   (set! frozen #t)
                                   (set! integer (car object))
                                   (set! bytevector (->bytevector (car object) length)))))
                    (bytevector (or (and frozen
                                         (error 'srp
                                                "value frozen"
                                                name))
                                    (begin
                                      (set! frozen #t)
                                      (set! integer (->integer (car object)))
                                      (set! bytevector (car object)))))
                    (else (error 'srp "unknown set type" type))))
             (else (error 'srp "unknown message" message))))))))

  (define srp-value-integer
    (lambda (v)
      ((srp-value-proc v) 'ref 'integer)))

  (define srp-value-bytevector
    (lambda (v)
      ((srp-value-proc v) 'ref 'bytevector)))

  (define srp-value-integer!
    (lambda (v value)
      ((srp-value-proc v) 'set 'integer value)))

  (define srp-value-bytevector!
    (lambda (v value)
      ((srp-value-proc v) 'set 'bytevector value)))

  (define bytevector->srp-value
    (lambda (name bytevector)
      (define out (make-srp-value name (bytevector-length bytevector)))
      (srp-value-bytevector! out bytevector)
      out))

  ;; RFC 5054 Appendix A: 2048-bit group parameter N

  (define SRP-N-2048
    (bytevector 172 107 219 65 50 74 154 155 241 102 222 94 19 137 88 47 175 114 182 101 25 135 238 7 252 49 146 148 61 181 96 80 163 115 41 203 180 160 153 237 129 147 224 117 119 103 161 61 213 35 18 171 75 3 49 13 205 127 72 169 218 4 253 80 232 8 57 105 237 183 103 176 207 96 149 23 154 22 58 179 102 26 5 251 213 250 170 232 41 24 169 150 47 11 147 184 85 249 121 147 236 151 94 234 168 13 116 10 219 244 255 116 115 89 208 65 213 195 62 167 29 40 30 68 107 20 119 59 202 151 180 58 35 251 128 22 118 189 32 122 67 108 100 129 241 210 185 7 135 23 70 26 91 157 50 230 136 248 119 72 84 69 35 181 36 176 213 125 94 167 122 39 117 210 236 250 3 44 251 219 245 47 179 120 97 96 39 144 4 229 122 230 175 135 78 115 3 206 83 41 156 204 4 28 123 195 8 216 42 86 152 243 168 208 195 130 113 174 53 248 233 219 251 182 148 181 200 3 216 159 122 228 53 222 35 109 82 95 84 117 155 101 227 114 252 214 142 242 15 167 17 31 158 74 255 115))

  (define-record-type* <srp-parameter>
    (make-srp-parameter generator byte-count N)
    srp-parameter
    (generator srp-parameter-generator)
    (byte-count srp-parameter-byte-count)
    (N srp-parameter-N))

  (define PARAMETER-2048
    (let ((length (/ 2048 8))) ;; 256 bytes
      (make-srp-parameter
       (let ((generator (make-srp-value 'generator 256)))
         (srp-value-integer! generator 2)
         generator)
       length
       (let ((N (make-srp-value 'N-2048 256)))
         (srp-value-bytevector! N SRP-N-2048)
         N))))

  ;; RFC 5054 section 2.4: x = H(s | H(I | ":" | P))
  (define srp-compute-x
    (lambda (salt identity password)
      (define colon (bytevector 58))
      (define inner (crypto-hash-sha256
                     (bytevector-append
                      (srp-value-bytevector identity)
                      colon
                      (srp-value-bytevector password))))
      (define hash (crypto-hash-sha256
                    (bytevector-append
                     (srp-value-bytevector salt)
                     inner)))
      (define x (make-srp-value 'x 32))
      (srp-value-bytevector! x hash)
      x))

  (define make-srp-client-verifier
    (lambda (parameter salt~ identity~ password~)
      (define salt (bytevector->srp-value 'salt salt~))
      (define identity (bytevector->srp-value 'identity identity~))
      (define password (bytevector->srp-value 'password password~))

      (define verifier (make-srp-value 'verifier (srp-parameter-byte-count parameter)))
      (srp-value-integer! verifier
                        (expt-mod
                         (srp-value-integer
                          (srp-parameter-generator parameter))
                         (srp-value-integer
                          (srp-compute-x salt identity password))
                         (srp-value-integer
                          (srp-parameter-N parameter))))
      (srp-value-bytevector verifier)))

  ;; RFC 5054 section 2.6: k = H(N | PAD(g))
  ;; PAD(g) is already 256 bytes since generator is stored with
  ;; byte-count matching N.
  (define srp-compute-k
    (lambda (parameter)
      (define k (make-srp-value 'k 32))
      (srp-value-bytevector! k
       (crypto-hash-sha256
        (bytevector-append
         (srp-value-bytevector (srp-parameter-N parameter))
         (srp-value-bytevector (srp-parameter-generator parameter)))))
      k))

  ;; RFC 5054 section 2.5.3: B = k*v + g^b % N
  (define srp-compute-B
    (lambda (parameter k v b)
      (define generator (srp-parameter-generator parameter))
      (define N (srp-parameter-N parameter))
      (define B (make-srp-value 'B 256))
      (srp-value-integer! B (modulo (+ (* (srp-value-integer k)
                                      (srp-value-integer v))
                                     (expt-mod (srp-value-integer generator)
                                               (srp-value-integer b)
                                               (srp-value-integer N)))
                                  (srp-value-integer N)))
      B))

  ;; RFC 5054 section 2.5.4: A = g^a % N
  (define srp-compute-A
    (lambda (parameter a)
      (define A (make-srp-value 'A 256))
      (define generator (srp-parameter-generator parameter))
      (define N (srp-parameter-N parameter))
      (define ignore
        (unless (<= 256 (bitwise-bit-count (srp-value-integer a)))
          (error 'srp "secret key has insufficient entropy" (bitwise-bit-count (srp-value-integer a)))))

      (srp-value-integer! A
                        (expt-mod (srp-value-integer generator)
                                  (srp-value-integer a)
                                  (srp-value-integer N)))
      A))

  ;; RFC 5054 section 2.6: u = H(PAD(A) | PAD(B))
  ;; A and B are already 256 bytes (= byte-count of N).
  (define srp-compute-u
    (lambda (A B)
      (define u (make-srp-value 'u 32))
      (srp-value-bytevector! u
       (crypto-hash-sha256
        (bytevector-append
         (srp-value-bytevector A)
         (srp-value-bytevector B))))
      u))

  ;; RFC 5054 section 2.6 client:
  ;; S = (B - (k * g^x)) ^ (a + (u * x)) % N
  (define srp-client-compute-S
    (lambda (parameter k x a B u)
      (define N (srp-parameter-N parameter))
      (define g (srp-parameter-generator parameter))
      (define client-S (make-srp-value 'S 256))

      (define ignore
        (unless (< 0
                   (srp-value-integer B)
                   (srp-value-integer (srp-parameter-N parameter)))
          (error 'srp "B must be between 1 and N - 1" B)))

      (srp-value-integer! client-S
                        (expt-mod (mod (- (srp-value-integer B)
                                          (* (srp-value-integer k)
                                             (expt-mod (srp-value-integer g)
                                                       (srp-value-integer x)
                                                       (srp-value-integer N))))
                                       (srp-value-integer N))
                                  (+ (srp-value-integer a)
                                     (* (srp-value-integer u)
                                        (srp-value-integer x)))
                                  (srp-value-integer N)))
      client-S))

  ;; RFC 5054 section 2.6 server:
  ;; S = (A * v^u) ^ b % N
  (define srp-server-compute-S
    (lambda (parameter v A b u)
      (define N (srp-parameter-N parameter))
      (define server-S (make-srp-value 'S 256))

      (unless (< 0 (srp-value-integer A) (srp-value-integer (srp-parameter-N parameter)))
        (error 'srp "A must be between 1 and N - 1" A))

      (srp-value-integer! server-S
                        (expt-mod (* (srp-value-integer A)
                                     (expt-mod (srp-value-integer v)
                                               (srp-value-integer u)
                                               (srp-value-integer N)))
                                  (srp-value-integer b)
                                  (srp-value-integer N)))
      server-S))

  ;; K = H(S)
  (define srp-compute-K
    (lambda (S)
      (define K (make-srp-value 'K 32))
      (srp-value-bytevector! K (crypto-hash-sha256 (srp-value-bytevector S)))
      K))

  ;; RFC 2945: M1 = H(H(N) XOR H(g) | H(I) | s | A | B | K)
  (define srp-compute-M1
    (lambda (who parameter I s A B K)

      (define N (srp-parameter-N parameter))
      (define g (srp-parameter-generator parameter))

      ;; H(N) XOR H(g)
      (define hN-xor-hg
        (->bytevector
         (bitwise-xor
          (->integer (crypto-hash-sha256 (srp-value-bytevector N)))
          (->integer (crypto-hash-sha256 (srp-value-bytevector g))))
         32))

      (define M1 (make-srp-value (cons who 'M1) 32))

      (srp-value-bytevector! M1
       (crypto-hash-sha256
        (bytevector-append
         hN-xor-hg
         (crypto-hash-sha256 (srp-value-bytevector I))
         (srp-value-bytevector s)
         (srp-value-bytevector A)
         (srp-value-bytevector B)
         (srp-value-bytevector K))))
      M1))

  ;; RFC 2945: M2 = H(A | M1 | K)
  (define srp-compute-M2
    (lambda (who parameter A M K)
      (define M2 (make-srp-value (cons who 'M2) 32))
      (srp-value-bytevector! M2
       (crypto-hash-sha256
        (bytevector-append
         (srp-value-bytevector A)
         (srp-value-bytevector M)
         (srp-value-bytevector K))))
      M2))

  ;; Constant-time comparison via libsodium
  (define srp-bytevector=?
    (lambda (a b)
      (and (fx=? (bytevector-length a) (bytevector-length b))
           (sodium-memcmp a b))))

  (define-record-type* <srp-client>
    (make-srp-client~ parameter salt identity k x a A B K M1 M2)
    srp-client?
    (parameter srp-client-parameter)
    (salt srp-client-salt)
    (identity srp-client-identity)
    (k srp-client-k)
    (x srp-client-x)
    (a srp-client-a)
    (A srp-client-A~)
    (B srp-client-B srp-client-B!!)
    ;; K aka session key
    (K srp-client-K~ srp-client-K!)
    (M1 srp-client-M1~ srp-client-M1!)
    (M2 srp-client-M2 srp-client-M2!))

  (define srp-client-A
    (lambda (client)
      (srp-value-bytevector (srp-client-A~ client))))

  (define (client-debug client)
    (list (list 'client 'K (srp-value-bytevector (srp-client-K~ client)))
          (list 'client 'M1 (srp-value-bytevector (srp-client-M1~ client)))
          (list 'client 'M2 (srp-value-bytevector (srp-client-M2 client)))))

  (define make-random-srp-value
    (lambda (name length)
      (define out (make-srp-value name length))
      (srp-value-bytevector! out (randombytes-buf length))
      out))

  (define make-srp-client
    (lambda (parameter secret~ salt~ identity~ password~)
      (define secret (bytevector->srp-value 'client-server secret~))
      (define salt (bytevector->srp-value 'salt salt~))
      (define identity (bytevector->srp-value 'identity identity~))
      (define password (bytevector->srp-value 'password password~))

      (make-srp-client~ parameter
                            salt
                            identity
                            (srp-compute-k parameter)
                            (srp-compute-x salt
                                               identity
                                               password)
                            secret ;; aka. a
                            (srp-compute-A parameter secret)
                            #f
                            #f
                            #f
                            #f)))

  (define srp-client-B!
    (lambda (client B~)
      (define B (bytevector->srp-value 'client-B B~))
      (define parameter (srp-client-parameter client))

      ;; safeguard: B mod N must not be zero
      (define ignore
        (unless (not (= 0
                        (mod (srp-value-integer B)
                             (srp-value-integer
                              (srp-parameter-N parameter)))))
          (error 'srp "B mod N is zero")))

      (define u (srp-compute-u (srp-client-A~ client) B))

      (define ignore2 (unless (not (= 0 (srp-value-integer u)))
                        (error 'srp "u must not be zero")))

      (define S
        (srp-client-compute-S
         parameter
         (srp-client-k client)
         (srp-client-x client)
         (srp-client-a client)
         B
         u))

      (srp-client-B!! client B)
      (srp-client-K! client (srp-compute-K S))
      (srp-client-M1! client
                          (srp-compute-M1 'client
                                              parameter
                                              (srp-client-identity client)
                                              (srp-client-salt client)
                                              (srp-client-A~ client)
                                              B
                                              (srp-client-K~ client)))
      (srp-client-M2! client
                          (srp-compute-M2 'client parameter
                                              (srp-client-A~ client)
                                              (srp-client-M1~ client)
                                              (srp-client-K~ client)))))

  (define srp-client-check-M2?
    (lambda (client server-M2~)
      (define server-M2 (bytevector->srp-value 'server-M2 server-M2~))

      (srp-bytevector=?
       (srp-value-bytevector (srp-client-M2 client))
       (srp-value-bytevector server-M2))))

  (define-record-type* <srp-server>
    (make-srp-server% parameter salt identity v b k B K M1 M2)
    srp-server?
    (parameter srp-server-parameter)
    (salt srp-server-salt)
    (identity srp-server-identity)
    (v srp-server-v)
    (b srp-server-b)
    (k srp-server-k)
    (B srp-server-B~ srp-server-B!)
    (K srp-server-K~ srp-server-K!)
    (M1 srp-server-M1 srp-server-M1!)
    (M2 srp-server-M2~ srp-server-M2!))

  (define srp-server-B
    (lambda (server)
      (srp-value-bytevector (srp-server-B~ server))))

  (define (server-debug server)
    (list (list 'server 'K (srp-value-bytevector (srp-server-K~ server)))
          (list 'server 'M1 (srp-value-bytevector (srp-server-M1 server)))
          (list 'server 'M2 (srp-value-bytevector (srp-server-M2~ server)))))

  (define srp-server-M2
    (lambda (server)
      (srp-value-bytevector (srp-server-M2~ server))))

  (define srp-client-M1
    (lambda (client)
      (srp-value-bytevector (srp-client-M1~ client))))

  (define make-srp-server
    (lambda (parameter secret~ salt~ identity~ verifier~)
      (define secret (bytevector->srp-value 'server-secret secret~))
      (define salt (bytevector->srp-value 'salt salt~))
      (define identity (bytevector->srp-value 'identity identity~))
      (define verifier (bytevector->srp-value 'verifier verifier~))

      (make-srp-server% parameter
                            salt
                            identity
                            verifier
                            secret
                            (srp-compute-k parameter)
                            #f
                            #f
                            #f
                            #f)))

  (define srp-server-A!
    (lambda (server A~)
      (define A (bytevector->srp-value 'A A~))
      (define parameter (srp-server-parameter server))

      ;; safeguard: A mod N must not be zero
      (define ignore
        (unless (not (= 0
                        (mod (srp-value-integer A)
                             (srp-value-integer
                              (srp-parameter-N parameter)))))
          (error 'srp "A mod N is zero")))

      (define B (srp-compute-B parameter
                                   (srp-compute-k parameter)
                                   (srp-server-v server)
                                   (srp-server-b server)))

      (define u (srp-compute-u A B))

      ;; u must not be zero
      (define ignore2
        (unless (not (= 0 (srp-value-integer u)))
          (error 'srp "u must not be zero")))

      (define S
        (srp-server-compute-S parameter
                                  (srp-server-v server)
                                  A
                                  (srp-server-b server)
                                  u))

      (srp-server-B! server B)
      (srp-server-K! server (srp-compute-K S))

      (srp-server-M1! server (srp-compute-M1
                                  'server
                                  parameter
                                  (srp-server-identity server)
                                  (srp-server-salt server)
                                  A
                                  (srp-server-B~ server)
                                  (srp-server-K~ server)))
      (srp-server-M2! server
                          (srp-compute-M2 'server parameter
                                              A
                                              (srp-server-M1 server)
                                              (srp-server-K~ server)))))

  (define srp-server-K
    (lambda (server)
      (srp-value-bytevector (srp-server-K~ server))))

  (define srp-client-K
    (lambda (client)
      (srp-value-bytevector (srp-client-K~ client))))

  (define srp-server-check-M1?
    (lambda (server client-M1~)
      (define client-M1 (bytevector->srp-value 'client-M1 client-M1~))

      (srp-bytevector=?
       (srp-value-bytevector (srp-server-M1 server))
       (srp-value-bytevector client-M1))))

  ;; apply

  (define ~check-srp-000
    (lambda ()
      (define _init (sodium-init))
      (define salt (randombytes-buf 25))
      (define identity (randombytes-buf 25))
      (define password (randombytes-buf 25))

      ;; The client compute an identifier based on salt, identity, and
      ;; password.
      (define verifier (make-srp-client-verifier PARAMETER-2048
                                                     salt
                                                     identity
                                                     password))

      ;; the server knows only about salt, identity, and verifier.
      (define server
        (make-srp-server PARAMETER-2048
                             (randombytes-buf 1536)
                             salt
                             identity
                             verifier))

      ;; Client knows about salt, identity, and password.
      (define client
        (make-srp-client PARAMETER-2048
                             (randombytes-buf 1536)
                             salt
                             identity
                             password))

      (srp-server-A! server
                         (srp-client-A client))

      (srp-client-B! client
                         (srp-server-B server))

      ;; (for-each pk (server-debug server))
      ;; (for-each pk (client-debug client))


      (and
       ;; client, and server know about K
       (equal? (srp-server-K server)
               (srp-client-K client))
       ;; client and server can verify that the other side knows about
       ;; the same K.

       ;; Server must verify the client proof of K first.
       (srp-server-check-M1? server (srp-client-M1 client))

       ;; The Client must also verify the server proof
       (srp-client-check-M2? client (srp-server-M2 server)))))

  ;; RFC 5054 Appendix B test vectors.
  ;; The vectors use SHA-1 for k, x, u. We inject those values
  ;; directly to verify the algebraic operations (expt-mod,
  ;; modular arithmetic) are correct independently of hash choice.

  (define hex->bytevector
    (lambda (str)
      (define clean
        (list->string
         (filter (lambda (c) (not (char=? c #\space)))
                 (string->list str))))
      (define len (div (string-length clean) 2))
      (define out (make-bytevector len))
      (let loop ((i 0))
        (when (< i len)
          (bytevector-u8-set! out i
            (string->number (substring clean (* i 2) (+ (* i 2) 2)) 16))
          (loop (+ i 1))))
      out))

  (define ~check-srp-rfc5054
    (lambda ()
      ;; 1024-bit group from RFC 5054 Appendix A, g = 2
      (define N-bytes
        (hex->bytevector
         "EEAF0AB9ADB38DD69C33F80AFA8FC5E86072618775FF3C0B9EA2314C9C256576D674DF7496EA81D3383B4813D692C6E0E0D5D8E250B98BE48E495C1D6089DAD15DC7D7B46154D6B6CE8EF4AD69B15D4982559B297BCF1885C529F566660E57EC68EDBC3C05726CC02FD4CBF4976EAA9AFD5138FE8376435B9FC61D2FC0EB06E3"))
      (define N (->integer N-bytes))
      (define g 2)
      (define byte-count 128)

      ;; SHA-1 derived values from RFC test vectors
      (define k (->integer (hex->bytevector "7556AA045AEF2CDD07ABAF0F665C3E818913186F")))
      (define x (->integer (hex->bytevector "94B7555AABE9127CC58CCF4993DB6CF84D16C124")))
      (define u (->integer (hex->bytevector "CE38B9593487DA98554ED47D70A7AE5F462EF019")))

      ;; Private keys
      (define a (->integer (hex->bytevector "60975527035CF2AD1989806F0407210BC81EDC04E2762A56AFD529DDDA2D4393")))
      (define b (->integer (hex->bytevector "E487CB59D31AC550471E81F00F6928E01DDA08E974A004F49E61F5D105284D20")))

      ;; Expected results
      (define v-expected
        (hex->bytevector
         "7E273DE8696FFC4F4E337D05B4B375BEB0DDE1569E8FA00A9886D8129BADA1F1822223CA1A605B530E379BA4729FDC59F105B4787E5186F5C671085A1447B52A48CF1970B4FB6F8400BBF4CEBFBB168152E08AB5EA53D15C1AFF87B2B9DA6E04E058AD51CC72BFC9033B564E26480D78E955A5E29E7AB245DB2BE315E2099AFB"))
      (define A-expected
        (hex->bytevector
         "61D5E490F6F1B79547B0704C436F523DD0E560F0C64115BB72557EC44352E8903211C04692272D8B2D1A5358A2CF1B6E0BFCF99F921530EC8E39356179EAE45E42BA92AEACED825171E1E8B9AF6D9C03E1327F44BE087EF06530E69F66615261EEF54073CA11CF5858F0EDFDFE15EFEAB349EF5D76988A3672FAC47B0769447B"))
      (define B-expected
        (hex->bytevector
         "BD0C61512C692C0CB6D041FA01BB152D4916A1E77AF46AE105393011BAF38964DC46A0670DD125B95A981652236F99D9B681CBF87837EC996C6DA04453728610D0C6DDB58B318885D7D82C7F8DEB75CE7BD4FBAA37089E6F9C6059F388838E7A00030B331EB76840910440B1B27AAEAEEB4012B7D7665238A8E3FB004B117B58"))
      (define S-expected
        (hex->bytevector
         "B0DC82BABCF30674AE450C0287745E7990A3381F63B387AAF271A10D233861E359B48220F7C4693C9AE12B0A6F67809F0876E2D013800D6C41BB59B6D5979B5C00A172B4A2A5903A0BDCAF8A709585EB2AFAFA8F3499B200210DCC1F10EB33943CD67FC88A2F39A4BE5BEC4EC0A3212DC346D7E474B29EDE8A469FFECA686E5A"))

      ;; v = g^x % N
      (define v-computed (->bytevector (expt-mod g x N) byte-count))
      (define _a1 (assert (equal? v-computed v-expected)))

      ;; A = g^a % N
      (define A-computed (->bytevector (expt-mod g a N) byte-count))
      (define _a2 (assert (equal? A-computed A-expected)))

      ;; B = k*v + g^b % N
      (define v-int (->integer v-expected))
      (define B-computed
        (->bytevector (modulo (+ (* k v-int) (expt-mod g b N)) N) byte-count))
      (define _a3 (assert (equal? B-computed B-expected)))

      ;; Client premaster secret: S = (B - k*g^x) ^ (a + u*x) % N
      (define B-int (->integer B-expected))
      (define S-client
        (->bytevector
         (expt-mod (mod (- B-int (* k (expt-mod g x N))) N)
                   (+ a (* u x))
                   N)
         byte-count))
      (define _a4 (assert (equal? S-client S-expected)))

      ;; Server premaster secret: S = (A * v^u) ^ b % N
      (define A-int (->integer A-expected))
      (define S-server
        (->bytevector
         (expt-mod (* A-int (expt-mod v-int u N))
                   b
                   N)
         byte-count))
      (define _a5 (assert (equal? S-server S-expected)))

      ;; Client and server must agree
      (define _a6 (assert (equal? S-client S-server)))

      #t))

)

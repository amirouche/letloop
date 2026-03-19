(library (letloop srp)
  (export make-srp-client-verifier
          make-srp-server
          make-srp-client
          srp-server-A!
          srp-client-B!
          srp-server-K
          srp-server-M2
          srp-server-check-M1?
          srp-client-K
          srp-client-M1
          srp-client-check-M2?
          ~check-srp-000)
  (import (chezscheme)
          (letloop bytevector)
          (letloop blake3)
          (letloop argon2)
          (letloop r999))

  ;; The SRP Authentication and Key Exchange System
  ;;
  ;; ref: https://tools.ietf.org/html/rfc2945
  ;; ref: http://srp.stanford.edu/doc.html
  ;; ref: https://en.wikipedia.org/wiki/Secure_Remote_Password_protocol
  ;;
  ;; TODO: Use unicode NFKD normalization to avoid problems because of
  ;; the input method

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

  (define srp-compute-x
    (lambda (salt identity password)
      (define ip (argon2id
                  (srp-value-bytevector salt)
                  (bytevector-append (srp-value-bytevector identity) (srp-value-bytevector password))))
      (define x (make-srp-value 'x (bytevector-length ip)))
      (srp-value-bytevector! x ip)
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

  (define srp-compute-k
    (lambda (parameter)
      (define k (make-srp-value 'k 32))
      (define hasher (make-blake3))
      (blake3-update! hasher
                      (srp-value-bytevector
                       (srp-parameter-N parameter)))
      (blake3-update! hasher
                      (srp-value-bytevector
                       (srp-parameter-generator parameter)))
      (srp-value-bytevector! k (blake3-finalize hasher 32))
      k))

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

  (define srp-compute-A
    (lambda (parameter a)
      (define A (make-srp-value 'A 256))
      (define generator (srp-parameter-generator parameter))
      (define N (srp-parameter-N parameter))
      (unless (<= 256 (bitwise-bit-count (srp-value-integer a)))
        (error 'srp "secret key has insufficient entropy" (bitwise-bit-count (srp-value-integer a))))
      (srp-value-integer! A
                        (expt-mod (srp-value-integer generator)
                                  (srp-value-integer a)
                                  (srp-value-integer N)))
      A))

  (define srp-compute-u
    (lambda (A B)
      (define u (make-srp-value 'u 32))
      (define hasher (make-blake3))
      (blake3-update! hasher (srp-value-bytevector A))
      (blake3-update! hasher (srp-value-bytevector B))
      (srp-value-bytevector! u (blake3-finalize hasher 32))
      u))

  (define srp-client-compute-S
    (lambda (parameter k x a B u)
      (define N (srp-parameter-N parameter))
      (define g (srp-parameter-generator parameter))
      (define client-S (make-srp-value 'S 256))

      (unless (< 0
                 (srp-value-integer B)
                 (srp-value-integer (srp-parameter-N parameter)))
        (error 'srp "B must be between 1 and N - 1" B))

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

  (define srp-compute-K
    (lambda (S)
      (define K (make-srp-value 'K 32))
      (srp-value-bytevector! K (blake3 (srp-value-bytevector S)))
      K))

  (define srp-compute-M1
    (lambda (who parameter I s A B K)

      (define magic
        (lambda ()
          (define N (srp-parameter-N parameter))
          (define g (srp-parameter-generator parameter))
          (blake3
           (->bytevector
            (bitwise-xor
             (->integer (blake3 (srp-value-bytevector N)))
             (->integer (blake3 (srp-value-bytevector g))))
            32))))

      (define hasher (make-blake3))
      (define M1 (make-srp-value (cons who 'M1) 32))

      (blake3-update! hasher (magic))
      (blake3-update! hasher (blake3 (srp-value-bytevector I)))
      (blake3-update! hasher (srp-value-bytevector s))
      (blake3-update! hasher (srp-value-bytevector A))
      (blake3-update! hasher (srp-value-bytevector B))
      (blake3-update! hasher (srp-value-bytevector K))
      (srp-value-bytevector! M1 (blake3-finalize hasher 32))
      M1))

  (define srp-compute-M2
    (lambda (who parameter A M K)
      (define hasher (make-blake3))
      (define M2 (make-srp-value (cons who 'M2) 32))
      (blake3-update! hasher (srp-value-bytevector A))
      (blake3-update! hasher (srp-value-bytevector M))
      (blake3-update! hasher (srp-value-bytevector K))
      (srp-value-bytevector! M2 (blake3-finalize hasher 32))
      M2))

  (define srp-bytevector=?
    (lambda (bytevector other)
      ;; constant-time comparison
      (if (not (fx=? (bytevector-length bytevector)
                     (bytevector-length other)))
          #f
          (let loop ((index 0)
                     (acc 0))
            (if (fx=? index (bytevector-length bytevector))
                (fxzero? acc)
                (loop (fx+ index 1)
                      (fxior acc
                             (fxxor (bytevector-u8-ref bytevector index)
                                    (bytevector-u8-ref other index)))))))))

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
      (srp-value-bytevector! out (bytevector-random length))
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
      (unless (not (= 0
                      (mod (srp-value-integer B)
                           (srp-value-integer
                            (srp-parameter-N parameter)))))
        (error 'srp "B mod N is zero"))

      (define u (srp-compute-u (srp-client-A~ client) B))

      (unless (not (= 0 (srp-value-integer u)))
        (error 'srp "u must not be zero"))

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
      (unless (not (= 0
                      (mod (srp-value-integer A)
                           (srp-value-integer
                            (srp-parameter-N parameter)))))
        (error 'srp "A mod N is zero"))

      (define B (srp-compute-B parameter
                                   (srp-compute-k parameter)
                                   (srp-server-v server)
                                   (srp-server-b server)))

      (define u (srp-compute-u A B))

      ;; u must not be zero
      (unless (not (= 0 (srp-value-integer u)))
        (error 'srp "u must not be zero"))

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
      (define salt (srp-value-bytevector (make-random-srp-value 'salt 25)))
      (define identity (srp-value-bytevector (make-random-srp-value 'identity 25)))
      (define password (srp-value-bytevector (make-random-srp-value 'password 25)))

      ;; The client compute an identifier based on salt, identity, and
      ;; password.
      (define verifier (make-srp-client-verifier PARAMETER-2048
                                                     salt
                                                     identity
                                                     password))

      ;; the server knows only about salt, identity, and verifier.
      (define server
        (make-srp-server PARAMETER-2048
                             (srp-value-bytevector (make-random-srp-value 'server-secret 1536))
                             salt
                             identity
                             verifier))

      ;; Client knows about salt, identity, and password.
      (define client
        (make-srp-client PARAMETER-2048
                             (srp-value-bytevector (make-random-srp-value 'client-secret 1536))
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

)

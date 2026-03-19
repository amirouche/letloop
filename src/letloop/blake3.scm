#!chezscheme
(library (letloop blake3)
  (export blake3 make-blake3 blake3-update! blake3-finalize
          ~check-blake3-000
          ~check-blake3-001
          ~check-blake3-002)

  (import (chezscheme))

  ;; ===== Constants =====

  (define OUT-LEN 32)
  (define KEY-LEN 32)
  (define BLOCK-LEN 64)
  (define CHUNK-LEN 1024)

  (define CHUNK-START (ash 1 0))
  (define CHUNK-END   (ash 1 1))
  (define PARENT      (ash 1 2))
  (define ROOT        (ash 1 3))

  (define IV
    (vector #x6A09E667 #xBB67AE85 #x3C6EF372 #xA54FF53A
            #x510E527F #x9B05688C #x1F83D9AB #x5BE0CD19))

  (define MSG-PERMUTATION
    (vector 2 6 3 10 7 0 4 13 1 11 12 5 9 14 15 8))

  (define u32-mask #xFFFFFFFF)

  (define (u32 x) (logand x u32-mask))

  (define (u32+ a b) (u32 (+ a b)))

  (define (rotr32 w c)
    (u32 (logior (ash w (- c)) (ash w (- 32 c)))))

  ;; ===== Compression Function =====

  (define (g! state a b c d mx my)
    (vector-set! state a (u32+ (u32+ (vector-ref state a) (vector-ref state b)) mx))
    (vector-set! state d (rotr32 (logxor (vector-ref state d) (vector-ref state a)) 16))
    (vector-set! state c (u32+ (vector-ref state c) (vector-ref state d)))
    (vector-set! state b (rotr32 (logxor (vector-ref state b) (vector-ref state c)) 12))
    (vector-set! state a (u32+ (u32+ (vector-ref state a) (vector-ref state b)) my))
    (vector-set! state d (rotr32 (logxor (vector-ref state d) (vector-ref state a)) 8))
    (vector-set! state c (u32+ (vector-ref state c) (vector-ref state d)))
    (vector-set! state b (rotr32 (logxor (vector-ref state b) (vector-ref state c)) 7)))

  (define (blake3-round! state m)
    ;; Columns
    (g! state 0 4  8 12 (vector-ref m 0)  (vector-ref m 1))
    (g! state 1 5  9 13 (vector-ref m 2)  (vector-ref m 3))
    (g! state 2 6 10 14 (vector-ref m 4)  (vector-ref m 5))
    (g! state 3 7 11 15 (vector-ref m 6)  (vector-ref m 7))
    ;; Diagonals
    (g! state 0 5 10 15 (vector-ref m 8)  (vector-ref m 9))
    (g! state 1 6 11 12 (vector-ref m 10) (vector-ref m 11))
    (g! state 2 7  8 13 (vector-ref m 12) (vector-ref m 13))
    (g! state 3 4  9 14 (vector-ref m 14) (vector-ref m 15)))

  (define (permute! m)
    (let ((tmp (make-vector 16)))
      (do ((i 0 (fx+ i 1))) ((fx= i 16))
        (vector-set! tmp i (vector-ref m (vector-ref MSG-PERMUTATION i))))
      (do ((i 0 (fx+ i 1))) ((fx= i 16))
        (vector-set! m i (vector-ref tmp i)))))

  (define (compress chaining-value block-words counter block-len flags)
    (let ((counter-low (u32 counter))
          (counter-high (u32 (ash counter -32)))
          (state (make-vector 16)))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! state i (vector-ref chaining-value i)))
      (vector-set! state 8  (vector-ref IV 0))
      (vector-set! state 9  (vector-ref IV 1))
      (vector-set! state 10 (vector-ref IV 2))
      (vector-set! state 11 (vector-ref IV 3))
      (vector-set! state 12 counter-low)
      (vector-set! state 13 counter-high)
      (vector-set! state 14 block-len)
      (vector-set! state 15 flags)
      (let ((m (vector-copy block-words)))
        (blake3-round! state m)
        (permute! m)
        (blake3-round! state m)
        (permute! m)
        (blake3-round! state m)
        (permute! m)
        (blake3-round! state m)
        (permute! m)
        (blake3-round! state m)
        (permute! m)
        (blake3-round! state m)
        (permute! m)
        (blake3-round! state m))
      ;; Finalize
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! state i (logxor (vector-ref state i)
                                     (vector-ref state (fx+ i 8))))
        (vector-set! state (fx+ i 8) (logxor (vector-ref state (fx+ i 8))
                                             (vector-ref chaining-value i))))
      state))

  (define (first-8-words cv)
    (let ((out (make-vector 8)))
      (do ((i 0 (fx+ i 1))) ((fx= i 8) out)
        (vector-set! out i (vector-ref cv i)))))

  (define (words-from-bytes bv offset count)
    (let ((words (make-vector count 0)))
      (do ((i 0 (fx+ i 1))) ((fx= i count) words)
        (vector-set! words i
                     (bytevector-u32-ref bv (fx+ offset (fx* i 4))
                                         (endianness little))))))

  ;; ===== Output =====

  ;; output is a vector: #(input-chaining-value block-words counter block-len flags)

  (define (make-output icv bw counter blen flags)
    (vector icv bw counter blen flags))

  (define (output-chaining-value out)
    (first-8-words (compress (vector-ref out 0)
                             (vector-ref out 1)
                             (vector-ref out 2)
                             (vector-ref out 3)
                             (vector-ref out 4))))

  (define (output-root-bytes out out-bv out-len)
    (let ((output-block-counter 0)
          (pos 0))
      (let loop ((pos 0) (ctr 0))
        (when (< pos out-len)
          (let* ((words (compress (vector-ref out 0)
                                  (vector-ref out 1)
                                  ctr
                                  (vector-ref out 3)
                                  (logior (vector-ref out 4) ROOT)))
                 (available (min (- out-len pos) (* 2 OUT-LEN))))
            ;; Write words to output as little-endian bytes
            (let word-loop ((wi 0) (bp pos))
              (when (and (< wi 16) (< bp (+ pos available)))
                (let* ((word (vector-ref words wi))
                       (bytes-left (- (+ pos available) bp))
                       (to-write (min 4 bytes-left)))
                  (when (>= to-write 1)
                    (bytevector-u8-set! out-bv bp (logand word #xFF)))
                  (when (>= to-write 2)
                    (bytevector-u8-set! out-bv (+ bp 1) (logand (ash word -8) #xFF)))
                  (when (>= to-write 3)
                    (bytevector-u8-set! out-bv (+ bp 2) (logand (ash word -16) #xFF)))
                  (when (>= to-write 4)
                    (bytevector-u8-set! out-bv (+ bp 3) (logand (ash word -24) #xFF)))
                  (word-loop (fx+ wi 1) (+ bp to-write)))))
            (loop (+ pos available) (+ ctr 1)))))))

  ;; ===== Chunk State =====

  ;; chunk-state is a vector:
  ;; #(chaining-value chunk-counter block block-len blocks-compressed flags)

  (define (make-chunk-state key-words chunk-counter flags)
    (vector (vector-copy key-words)
            chunk-counter
            (make-bytevector BLOCK-LEN 0)
            0    ;; block-len
            0    ;; blocks-compressed
            flags))

  (define (chunk-state-len cs)
    (+ (* BLOCK-LEN (vector-ref cs 4)) (vector-ref cs 3)))

  (define (chunk-state-start-flag cs)
    (if (= (vector-ref cs 4) 0) CHUNK-START 0))

  (define (chunk-state-update! cs input in-offset in-len)
    (let loop ((off in-offset) (remaining in-len))
      (when (> remaining 0)
        (let ((block-len (vector-ref cs 3)))
          ;; If block buffer is full, compress it
          (when (= block-len BLOCK-LEN)
            (let ((block-words (words-from-bytes (vector-ref cs 2) 0 16)))
              (vector-set! cs 0
                           (first-8-words
                            (compress (vector-ref cs 0)
                                      block-words
                                      (vector-ref cs 1) ;; chunk-counter
                                      BLOCK-LEN
                                      (logior (vector-ref cs 5) (chunk-state-start-flag cs)))))
              (vector-set! cs 4 (+ (vector-ref cs 4) 1)) ;; blocks-compressed++
              (bytevector-fill! (vector-ref cs 2) 0)
              (vector-set! cs 3 0)))
          (let* ((block-len (vector-ref cs 3))
                 (want (- BLOCK-LEN block-len))
                 (take (min want remaining)))
            (bytevector-copy! input off (vector-ref cs 2) block-len take)
            (vector-set! cs 3 (+ block-len take))
            (loop (+ off take) (- remaining take)))))))

  (define (chunk-state-output cs)
    (let ((block-words (words-from-bytes (vector-ref cs 2) 0 16)))
      (make-output (vector-ref cs 0)
                   block-words
                   (vector-ref cs 1)  ;; chunk-counter
                   (vector-ref cs 3)  ;; block-len
                   (logior (vector-ref cs 5)
                           (chunk-state-start-flag cs)
                           CHUNK-END))))

  ;; ===== Parent Node =====

  (define (parent-output left-cv right-cv key-words flags)
    (let ((block-words (make-vector 16 0)))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! block-words i (vector-ref left-cv i)))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! block-words (fx+ i 8) (vector-ref right-cv i)))
      (make-output key-words block-words 0 BLOCK-LEN (logior PARENT flags))))

  (define (parent-cv left-cv right-cv key-words flags)
    (output-chaining-value (parent-output left-cv right-cv key-words flags)))

  ;; ===== Hasher =====

  ;; hasher is a vector: #(chunk-state key-words cv-stack cv-stack-len flags)

  (define (make-blake3)
    (vector (make-chunk-state IV 0 0)
            (vector-copy IV)
            (make-vector 54 #f)  ;; cv-stack, each entry is a vector of 8 u32
            0                    ;; cv-stack-len
            0))                  ;; flags

  (define (hasher-push-stack! h cv)
    (let ((len (vector-ref h 3)))
      (vector-set! (vector-ref h 2) len cv)
      (vector-set! h 3 (+ len 1))))

  (define (hasher-pop-stack! h)
    (let ((len (- (vector-ref h 3) 1)))
      (vector-set! h 3 len)
      (vector-ref (vector-ref h 2) len)))

  (define (add-chunk-chaining-value! h new-cv total-chunks)
    (let loop ((cv new-cv) (tc total-chunks))
      (if (= (logand tc 1) 0)
          (loop (parent-cv (hasher-pop-stack! h) cv
                           (vector-ref h 1) (vector-ref h 4))
                (ash tc -1))
          (hasher-push-stack! h cv))))

  (define (blake3-update! hasher input)
    (let ((input-len (bytevector-length input)))
      (let loop ((off 0) (remaining input-len))
        (when (> remaining 0)
          (let ((cs (vector-ref hasher 0)))
            ;; If current chunk is complete, finalize it and start a new one
            (when (= (chunk-state-len cs) CHUNK-LEN)
              (let ((chunk-cv (output-chaining-value (chunk-state-output cs)))
                    (total-chunks (+ (vector-ref cs 1) 1)))
                (add-chunk-chaining-value! hasher chunk-cv total-chunks)
                (vector-set! hasher 0
                             (make-chunk-state (vector-ref hasher 1)
                                               total-chunks
                                               (vector-ref hasher 4)))))
            (let* ((cs (vector-ref hasher 0))
                   (want (- CHUNK-LEN (chunk-state-len cs)))
                   (take (min want remaining)))
              (chunk-state-update! cs input off take)
              (loop (+ off take) (- remaining take))))))))

  (define (blake3-finalize hasher length)
    (let* ((cs (vector-ref hasher 0))
           (output (chunk-state-output cs))
           (result (make-bytevector length 0)))
      (let loop ((out output)
                 (remaining (vector-ref hasher 3)))
        (if (> remaining 0)
            (let ((remaining (- remaining 1)))
              (loop (parent-output (vector-ref (vector-ref hasher 2) remaining)
                                   (output-chaining-value out)
                                   (vector-ref hasher 1)
                                   (vector-ref hasher 4))
                    remaining))
            (output-root-bytes out result length)))
      result))

  (define blake3
    (lambda (bytevector)
      (let ((hasher (make-blake3)))
        (blake3-update! hasher bytevector)
        (blake3-finalize hasher 32))))

  ;; ===== Tests =====

  ;; Same test vectors as the FFI version
  (define ~check-blake3-000
    (lambda ()
      (assert (bytevector=? (blake3 (string->utf8 "azul dunith"))
                            (bytevector 147 96 202 209 250 91 234 79
                                        148 175 155 40 42 42 163 180
                                        23 60 5 78 248 205 93 236
                                        132 217 22 253 234 98 73 27)))))

  (define ~check-blake3-001
    (lambda ()
      (let ((hasher (make-blake3)))
        (blake3-update! hasher (string->utf8 "azul dunith"))
        (assert (bytevector=? (blake3-finalize hasher 16)
                              (bytevector 147 96 202 209 250 91 234 79
                                          148 175 155 40 42 42 163 180))))))

  ;; Test against official test vector: empty input
  (define ~check-blake3-002
    (lambda ()
      (define (hex->bytevector hex)
        (let* ((len (div (string-length hex) 2))
               (bv (make-bytevector len)))
          (do ((i 0 (+ i 1))) ((= i len) bv)
            (bytevector-u8-set! bv i
                                (string->number
                                 (substring hex (* i 2) (+ (* i 2) 2))
                                 16)))))
      (let ((expected (hex->bytevector "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")))
        (assert (bytevector=? (blake3 (make-bytevector 0))
                              expected)))))

  ) ;; end library

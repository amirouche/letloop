#!chezscheme
;; BLAKE3 in Scheme, with no shared object behind it.
;;
;; It exists so that hashing is never a dependency: (letloop store)
;; hashes every output, so a letloop that cannot hash cannot run the
;; store, and requiring libblake3 to be built and statically linked
;; first made the package manager depend on a package. This is the
;; floor (letloop blake3) falls back to -- and what the store itself
;; imports directly, rather than through that dispatch: the store's
;; own correctness should not turn on whether a particular binary's
;; static blake3 registration happened to work. Named "scheme" rather
;; than "pure" so the contrast with (letloop blake3) reads as
;; implementation language, not purity.
;;
;; It is about 128x slower than the C implementation -- roughly
;; 20 MB/s against 2.5 GB/s, measured on 5 MB -- which is why
;; (letloop blake3) prefers the shared object when there is one, for
;; everything except the store. Both produce identical digests; that
;; is checked, against the same vectors and against each other.
;;
;; Recovered from e3cc037^, which replaced it with the C bindings.
(library (letloop blake3 scheme)
  (export blake3 make-blake3 blake3-update! blake3-finalize blake3-close!
          ~check-blake3-scheme-000
          ~check-blake3-scheme-001
          ~check-blake3-scheme-002)

  (import (chezscheme))

  ;; ===== Constants =====

  (define OUT-LEN 32)
  (define BLOCK-LEN 64)
  (define CHUNK-LEN 1024)

  (define CHUNK-START 1)
  (define CHUNK-END   2)
  (define PARENT      4)
  (define ROOT        8)

  (define IV
    (vector #x6A09E667 #xBB67AE85 #x3C6EF372 #xA54FF53A
            #x510E527F #x9B05688C #x1F83D9AB #x5BE0CD19))

  (define MSG-PERMUTATION
    (vector 2 6 3 10 7 0 4 13 1 11 12 5 9 14 15 8))

  ;; ===== Fixnum 32-bit Arithmetic =====
  ;; All BLAKE3 values are 32-bit, which fit in Chez's 61-bit fixnums.
  ;; Using fx operations compiles to single machine instructions.

  (define u32-mask #xFFFFFFFF)

  (define (u32+ a b) (fxlogand (fx+ a b) u32-mask))

  ;; Safe for BLAKE3 rotation amounts (7, 8, 12, 16):
  ;; max left shift is 25, so max value is (2^32-1)*2^25 = 2^57-2^25 < 2^60
  (define (rotr32 w c)
    (let ((w w))
      (fxlogand (fxlogior (fxsrl w c) (fxsll w (fx- 32 c))) u32-mask)))

  ;; ===== Compression Function =====

  (define (g! state a b c d mx my)
    (vector-set! state a (u32+ (u32+ (vector-ref state a) (vector-ref state b)) mx))
    (vector-set! state d (rotr32 (fxlogxor (vector-ref state d) (vector-ref state a)) 16))
    (vector-set! state c (u32+ (vector-ref state c) (vector-ref state d)))
    (vector-set! state b (rotr32 (fxlogxor (vector-ref state b) (vector-ref state c)) 12))
    (vector-set! state a (u32+ (u32+ (vector-ref state a) (vector-ref state b)) my))
    (vector-set! state d (rotr32 (fxlogxor (vector-ref state d) (vector-ref state a)) 8))
    (vector-set! state c (u32+ (vector-ref state c) (vector-ref state d)))
    (vector-set! state b (rotr32 (fxlogxor (vector-ref state b) (vector-ref state c)) 7)))

  (define (blake3-round! state m)
    (g! state 0 4  8 12 (vector-ref m 0)  (vector-ref m 1))
    (g! state 1 5  9 13 (vector-ref m 2)  (vector-ref m 3))
    (g! state 2 6 10 14 (vector-ref m 4)  (vector-ref m 5))
    (g! state 3 7 11 15 (vector-ref m 6)  (vector-ref m 7))
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
    ;; counter is u64, split into two u32 fixnums
    (let ((counter-low (logand counter u32-mask))
          (counter-high (logand (ash counter -32) u32-mask))
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
        (vector-set! state i (fxlogxor (vector-ref state i)
                                       (vector-ref state (fx+ i 8))))
        (vector-set! state (fx+ i 8) (fxlogxor (vector-ref state (fx+ i 8))
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

  (define (make-output icv bw counter blen flags)
    (vector icv bw counter blen flags))

  (define (output-chaining-value out)
    (first-8-words (compress (vector-ref out 0)
                             (vector-ref out 1)
                             (vector-ref out 2)
                             (vector-ref out 3)
                             (vector-ref out 4))))

  (define (output-root-bytes out out-bv out-len)
    (let loop ((pos 0) (ctr 0))
      (when (fx< pos out-len)
        (let* ((words (compress (vector-ref out 0)
                                (vector-ref out 1)
                                ctr
                                (vector-ref out 3)
                                (fxlogior (vector-ref out 4) ROOT)))
               (available (fxmin (fx- out-len pos) (fx* 2 OUT-LEN))))
          (let word-loop ((wi 0) (bp pos))
            (when (and (fx< wi 16) (fx< bp (fx+ pos available)))
              (let* ((word (vector-ref words wi))
                     (bytes-left (fx- (fx+ pos available) bp))
                     (to-write (fxmin 4 bytes-left)))
                (when (fx>= to-write 1)
                  (bytevector-u8-set! out-bv bp (fxlogand word #xFF)))
                (when (fx>= to-write 2)
                  (bytevector-u8-set! out-bv (fx+ bp 1) (fxlogand (fxsrl word 8) #xFF)))
                (when (fx>= to-write 3)
                  (bytevector-u8-set! out-bv (fx+ bp 2) (fxlogand (fxsrl word 16) #xFF)))
                (when (fx>= to-write 4)
                  (bytevector-u8-set! out-bv (fx+ bp 3) (fxlogand (fxsrl word 24) #xFF)))
                (word-loop (fx+ wi 1) (fx+ bp to-write)))))
          (loop (fx+ pos available) (fx+ ctr 1))))))

  ;; ===== Chunk State =====

  ;; #(chaining-value chunk-counter block block-len blocks-compressed flags)

  (define (make-chunk-state key-words chunk-counter flags)
    (vector (vector-copy key-words)
            chunk-counter
            (make-bytevector BLOCK-LEN 0)
            0 0 flags))

  (define (chunk-state-len cs)
    (fx+ (fx* BLOCK-LEN (vector-ref cs 4)) (vector-ref cs 3)))

  (define (chunk-state-start-flag cs)
    (if (fx= (vector-ref cs 4) 0) CHUNK-START 0))

  (define (chunk-state-update! cs input in-offset in-len)
    (let loop ((off in-offset) (remaining in-len))
      (when (fx> remaining 0)
        (let ((block-len (vector-ref cs 3)))
          (when (fx= block-len BLOCK-LEN)
            (let ((block-words (words-from-bytes (vector-ref cs 2) 0 16)))
              (vector-set! cs 0
                           (first-8-words
                            (compress (vector-ref cs 0)
                                      block-words
                                      (vector-ref cs 1)
                                      BLOCK-LEN
                                      (fxlogior (vector-ref cs 5) (chunk-state-start-flag cs)))))
              (vector-set! cs 4 (fx+ (vector-ref cs 4) 1))
              (bytevector-fill! (vector-ref cs 2) 0)
              (vector-set! cs 3 0)))
          (let* ((block-len (vector-ref cs 3))
                 (want (fx- BLOCK-LEN block-len))
                 (take (fxmin want remaining)))
            (bytevector-copy! input off (vector-ref cs 2) block-len take)
            (vector-set! cs 3 (fx+ block-len take))
            (loop (fx+ off take) (fx- remaining take)))))))

  (define (chunk-state-output cs)
    (let ((block-words (words-from-bytes (vector-ref cs 2) 0 16)))
      (make-output (vector-ref cs 0)
                   block-words
                   (vector-ref cs 1)
                   (vector-ref cs 3)
                   (fxlogior (vector-ref cs 5)
                             (chunk-state-start-flag cs)
                             CHUNK-END))))

  ;; ===== Parent Node =====

  (define (parent-output left-cv right-cv key-words flags)
    (let ((block-words (make-vector 16 0)))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! block-words i (vector-ref left-cv i)))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! block-words (fx+ i 8) (vector-ref right-cv i)))
      (make-output key-words block-words 0 BLOCK-LEN (fxlogior PARENT flags))))

  (define (parent-cv left-cv right-cv key-words flags)
    (output-chaining-value (parent-output left-cv right-cv key-words flags)))

  ;; ===== Hasher =====

  ;; #(chunk-state key-words cv-stack cv-stack-len flags)

  (define (make-blake3)
    (vector (make-chunk-state IV 0 0)
            (vector-copy IV)
            (make-vector 54 #f)
            0
            0))

  (define (hasher-push-stack! h cv)
    (let ((len (vector-ref h 3)))
      (vector-set! (vector-ref h 2) len cv)
      (vector-set! h 3 (fx+ len 1))))

  (define (hasher-pop-stack! h)
    (let ((len (fx- (vector-ref h 3) 1)))
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
        (when (fx> remaining 0)
          (let ((cs (vector-ref hasher 0)))
            (when (fx= (chunk-state-len cs) CHUNK-LEN)
              (let ((chunk-cv (output-chaining-value (chunk-state-output cs)))
                    (total-chunks (+ (vector-ref cs 1) 1)))
                (add-chunk-chaining-value! hasher chunk-cv total-chunks)
                (vector-set! hasher 0
                             (make-chunk-state (vector-ref hasher 1)
                                               total-chunks
                                               (vector-ref hasher 4)))))
            (let* ((cs (vector-ref hasher 0))
                   (want (fx- CHUNK-LEN (chunk-state-len cs)))
                   (take (fxmin want remaining)))
              (chunk-state-update! cs input off take)
              (loop (fx+ off take) (fx- remaining take))))))))

  ;; API parity with the C bindings, where the hasher is
  ;; foreign-alloc'd and must be freed. This one is an ordinary
  ;; Scheme object, so there is nothing to release.
  (define (blake3-close! hasher) (values))

  (define (blake3-finalize hasher length)
    (let* ((cs (vector-ref hasher 0))
           (output (chunk-state-output cs))
           (result (make-bytevector length 0)))
      (let loop ((out output)
                 (remaining (vector-ref hasher 3)))
        (if (fx> remaining 0)
            (let ((remaining (fx- remaining 1)))
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

  (define ~check-blake3-scheme-000
    (lambda ()
      (assert (bytevector=? (blake3 (string->utf8 "azul dunith"))
                            (bytevector 147 96 202 209 250 91 234 79
                                        148 175 155 40 42 42 163 180
                                        23 60 5 78 248 205 93 236
                                        132 217 22 253 234 98 73 27)))))

  (define ~check-blake3-scheme-001
    (lambda ()
      (let ((hasher (make-blake3)))
        (blake3-update! hasher (string->utf8 "azul dunith"))
        (assert (bytevector=? (blake3-finalize hasher 16)
                              (bytevector 147 96 202 209 250 91 234 79
                                          148 175 155 40 42 42 163 180))))))

  (define ~check-blake3-scheme-002
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

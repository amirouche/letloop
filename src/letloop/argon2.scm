#!chezscheme
(library (letloop argon2)
  (export argon2id argon2id-encode argon2id-verify
          argon2id-t-cost argon2id-m-cost argon2id-parallelism
          ~check-argon2-0)
  (import (chezscheme))

  ;; ===== Layer 1: 64-bit Arithmetic Helpers =====
  ;; Used only by blake2b (Layer 2), NOT in the hot argon2 core.

  (define u64-mask #xFFFFFFFFFFFFFFFF)
  (define u32-mask #xFFFFFFFF)

  (define (u64 x) (logand x u64-mask))
  (define (u32 x) (logand x u32-mask))

  (define (rotr64 w c)
    (u64 (logior (ash w (- c)) (ash w (- 64 c)))))

  (define (store32! bv offset val)
    (bytevector-u32-set! bv offset (u32 val) (endianness little)))

  (define (load32 bv offset)
    (bytevector-u32-ref bv offset (endianness little)))

  (define (store64! bv offset val)
    (bytevector-u64-set! bv offset (u64 val) (endianness little)))

  (define (load64 bv offset)
    (bytevector-u64-ref bv offset (endianness little)))

  ;; ===== Layer 2: Blake2b =====
  ;; Unchanged — not in the hot loop, called only at init and finalization.

  (define BLAKE2B-BLOCKBYTES 128)
  (define BLAKE2B-OUTBYTES 64)

  (define blake2b-IV
    (vector #x6a09e667f3bcc908 #xbb67ae8584caa73b
            #x3c6ef372fe94f82b #xa54ff53a5f1d36f1
            #x510e527fade682d1 #x9b05688c2b3e6c1f
            #x1f83d9abfb41bd6b #x5be0cd19137e2179))

  (define blake2b-sigma
    (vector
     (vector  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15)
     (vector 14 10  4  8  9 15 13  6  1 12  0  2 11  7  5  3)
     (vector 11  8 12  0  5  2 15 13 10 14  3  6  7  1  9  4)
     (vector  7  9  3  1 13 12 11 14  2  6  5 10  4  0 15  8)
     (vector  9  0  5  7  2  4 10 15 14  1 11 12  6  8  3 13)
     (vector  2 12  6 10  0 11  8  3  4 13  7  5 15 14  1  9)
     (vector 12  5  1 15 14 13  4 10  0  7  6  3  9  2  8 11)
     (vector 13 11  7 14 12  1  3  9  5  0 15  4  8  6  2 10)
     (vector  6 15 14  9 11  3  0  8 12  2 13  7  1  4 10  5)
     (vector 10  2  8  4  7  6  1  5 15 11  9 14  3 12 13  0)
     (vector  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15)
     (vector 14 10  4  8  9 15 13  6  1 12  0  2 11  7  5  3)))

  (define-record-type blake2b-state
    (fields (mutable h)
            (mutable t0) (mutable t1)
            (mutable f0) (mutable f1)
            (mutable buf)
            (mutable buflen)
            (mutable outlen)))

  (define (make-blake2b)
    (make-blake2b-state
     (make-vector 8 0) 0 0 0 0
     (make-bytevector BLAKE2B-BLOCKBYTES 0) 0 0))

  (define (blake2b-init! S outlen)
    (let ((h (blake2b-state-h S)))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! h i (vector-ref blake2b-IV i)))
      (vector-set! h 0 (logxor (vector-ref h 0)
                                (logior outlen #x01010000))))
    (blake2b-state-t0-set! S 0)
    (blake2b-state-t1-set! S 0)
    (blake2b-state-f0-set! S 0)
    (blake2b-state-f1-set! S 0)
    (bytevector-fill! (blake2b-state-buf S) 0)
    (blake2b-state-buflen-set! S 0)
    (blake2b-state-outlen-set! S outlen))

  (define (blake2b-increment-counter! S inc)
    (let* ((t0 (u64 (+ (blake2b-state-t0 S) inc))))
      (blake2b-state-t0-set! S t0)
      (when (< t0 (u64 inc))
        (blake2b-state-t1-set! S (u64 (+ (blake2b-state-t1 S) 1))))))

  (define (blake2b-set-lastblock! S)
    (blake2b-state-f0-set! S u64-mask))

  (define (blake2b-G! v ai bi ci di msg0 msg1)
    (vector-set! v ai (u64 (+ (vector-ref v ai) (vector-ref v bi) msg0)))
    (vector-set! v di (rotr64 (logxor (vector-ref v di) (vector-ref v ai)) 32))
    (vector-set! v ci (u64 (+ (vector-ref v ci) (vector-ref v di))))
    (vector-set! v bi (rotr64 (logxor (vector-ref v bi) (vector-ref v ci)) 24))
    (vector-set! v ai (u64 (+ (vector-ref v ai) (vector-ref v bi) msg1)))
    (vector-set! v di (rotr64 (logxor (vector-ref v di) (vector-ref v ai)) 16))
    (vector-set! v ci (u64 (+ (vector-ref v ci) (vector-ref v di))))
    (vector-set! v bi (rotr64 (logxor (vector-ref v bi) (vector-ref v ci)) 63)))

  (define (blake2b-compress! S block-bv block-offset)
    (let ((m (make-vector 16 0))
          (v (make-vector 16 0))
          (h (blake2b-state-h S)))
      (do ((i 0 (fx+ i 1))) ((fx= i 16))
        (vector-set! m i (bytevector-u64-ref block-bv (fx+ block-offset (fx* i 8))
                                             (endianness little))))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! v i (vector-ref h i)))
      (vector-set! v 8  (vector-ref blake2b-IV 0))
      (vector-set! v 9  (vector-ref blake2b-IV 1))
      (vector-set! v 10 (vector-ref blake2b-IV 2))
      (vector-set! v 11 (vector-ref blake2b-IV 3))
      (vector-set! v 12 (logxor (vector-ref blake2b-IV 4) (blake2b-state-t0 S)))
      (vector-set! v 13 (logxor (vector-ref blake2b-IV 5) (blake2b-state-t1 S)))
      (vector-set! v 14 (logxor (vector-ref blake2b-IV 6) (blake2b-state-f0 S)))
      (vector-set! v 15 (logxor (vector-ref blake2b-IV 7) (blake2b-state-f1 S)))
      (do ((r 0 (fx+ r 1))) ((fx= r 12))
        (let ((s (vector-ref blake2b-sigma r)))
          (blake2b-G! v 0 4  8 12 (vector-ref m (vector-ref s  0)) (vector-ref m (vector-ref s  1)))
          (blake2b-G! v 1 5  9 13 (vector-ref m (vector-ref s  2)) (vector-ref m (vector-ref s  3)))
          (blake2b-G! v 2 6 10 14 (vector-ref m (vector-ref s  4)) (vector-ref m (vector-ref s  5)))
          (blake2b-G! v 3 7 11 15 (vector-ref m (vector-ref s  6)) (vector-ref m (vector-ref s  7)))
          (blake2b-G! v 0 5 10 15 (vector-ref m (vector-ref s  8)) (vector-ref m (vector-ref s  9)))
          (blake2b-G! v 1 6 11 12 (vector-ref m (vector-ref s 10)) (vector-ref m (vector-ref s 11)))
          (blake2b-G! v 2 7  8 13 (vector-ref m (vector-ref s 12)) (vector-ref m (vector-ref s 13)))
          (blake2b-G! v 3 4  9 14 (vector-ref m (vector-ref s 14)) (vector-ref m (vector-ref s 15)))))
      (do ((i 0 (fx+ i 1))) ((fx= i 8))
        (vector-set! h i (logxor (vector-ref h i)
                                  (logxor (vector-ref v i) (vector-ref v (fx+ i 8))))))))

  (define (blake2b-update! S in in-offset inlen)
    (when (> inlen 0)
      (let ((buf (blake2b-state-buf S))
            (buflen (blake2b-state-buflen S)))
        (if (> (+ buflen inlen) BLAKE2B-BLOCKBYTES)
            (let ((fill (- BLAKE2B-BLOCKBYTES buflen)))
              (bytevector-copy! in in-offset buf buflen fill)
              (blake2b-increment-counter! S BLAKE2B-BLOCKBYTES)
              (blake2b-compress! S buf 0)
              (blake2b-state-buflen-set! S 0)
              (let loop ((pin (+ in-offset fill))
                         (remaining (- inlen fill)))
                (if (> remaining BLAKE2B-BLOCKBYTES)
                    (begin
                      (blake2b-increment-counter! S BLAKE2B-BLOCKBYTES)
                      (blake2b-compress! S in pin)
                      (loop (+ pin BLAKE2B-BLOCKBYTES) (- remaining BLAKE2B-BLOCKBYTES)))
                    (begin
                      (bytevector-copy! in pin buf 0 remaining)
                      (blake2b-state-buflen-set! S remaining)))))
            (begin
              (bytevector-copy! in in-offset buf buflen inlen)
              (blake2b-state-buflen-set! S (+ buflen inlen)))))))

  (define (blake2b-final! S out)
    (let ((buflen (blake2b-state-buflen S))
          (buf (blake2b-state-buf S))
          (outlen (blake2b-state-outlen S)))
      (blake2b-increment-counter! S buflen)
      (blake2b-set-lastblock! S)
      (do ((i buflen (fx+ i 1))) ((fx= i BLAKE2B-BLOCKBYTES))
        (bytevector-u8-set! buf i 0))
      (blake2b-compress! S buf 0)
      (let ((buffer (make-bytevector BLAKE2B-OUTBYTES 0)))
        (do ((i 0 (fx+ i 1))) ((fx= i 8))
          (store64! buffer (fx* i 8) (vector-ref (blake2b-state-h S) i)))
        (bytevector-copy! buffer 0 out 0 outlen))))

  (define (blake2b out outlen in inlen)
    (let ((S (make-blake2b)))
      (blake2b-init! S outlen)
      (blake2b-update! S in 0 inlen)
      (blake2b-final! S out)))

  (define (blake2b-long out outlen in inlen)
    (let ((outlen-bytes (make-bytevector 4 0)))
      (store32! outlen-bytes 0 outlen)
      (if (<= outlen BLAKE2B-OUTBYTES)
          (let ((S (make-blake2b)))
            (blake2b-init! S outlen)
            (blake2b-update! S outlen-bytes 0 4)
            (blake2b-update! S in 0 inlen)
            (blake2b-final! S out))
          (let ((out-buffer (make-bytevector BLAKE2B-OUTBYTES 0)))
            (let ((S (make-blake2b)))
              (blake2b-init! S BLAKE2B-OUTBYTES)
              (blake2b-update! S outlen-bytes 0 4)
              (blake2b-update! S in 0 inlen)
              (blake2b-final! S out-buffer))
            (bytevector-copy! out-buffer 0 out 0 (/ BLAKE2B-OUTBYTES 2))
            (let loop ((out-offset (/ BLAKE2B-OUTBYTES 2))
                       (toproduce (- outlen (/ BLAKE2B-OUTBYTES 2))))
              (if (> toproduce BLAKE2B-OUTBYTES)
                  (let ((in-buffer (bytevector-copy out-buffer)))
                    (blake2b out-buffer BLAKE2B-OUTBYTES in-buffer BLAKE2B-OUTBYTES)
                    (bytevector-copy! out-buffer 0 out out-offset (/ BLAKE2B-OUTBYTES 2))
                    (loop (+ out-offset (/ BLAKE2B-OUTBYTES 2))
                          (- toproduce (/ BLAKE2B-OUTBYTES 2))))
                  (let ((in-buffer (bytevector-copy out-buffer)))
                    (blake2b out-buffer toproduce in-buffer BLAKE2B-OUTBYTES)
                    (bytevector-copy! out-buffer 0 out out-offset toproduce))))))))

  ;; ===== Layer 3: Argon2 Core (OPTIMIZED) =====
  ;; Blocks are flat bytevectors (1024 bytes). All hot-loop arithmetic
  ;; uses 32-bit fixnum halves — zero bignum allocation.

  (define ARGON2-BLOCK-SIZE 1024)
  (define ARGON2-QWORDS-IN-BLOCK 128)
  (define ARGON2-SYNC-POINTS 4)
  (define ARGON2-ADDRESSES-IN-BLOCK 128)
  (define ARGON2-PREHASH-DIGEST-LENGTH 64)
  (define ARGON2-PREHASH-SEED-LENGTH 72)
  (define ARGON2-VERSION-13 #x13)
  (define ARGON2-TYPE-ID 2)

  ;; Block: flat bytevector of 1024 bytes (128 u64 values in little-endian)
  (define (make-block) (make-bytevector ARGON2-BLOCK-SIZE 0))

  (define (copy-block! dst src)
    (bytevector-copy! src 0 dst 0 ARGON2-BLOCK-SIZE))

  ;; XOR at u32 level to stay in fixnums (256 iterations, no bignums)
  (define (xor-block! dst src)
    (do ((i 0 (fx+ i 4))) ((fx= i ARGON2-BLOCK-SIZE))
      (bytevector-u32-set! dst i
        (fxlogxor (bytevector-u32-ref dst i (endianness little))
                  (bytevector-u32-ref src i (endianness little)))
        (endianness little))))

  (define (block->bytevector blk)
    (bytevector-copy blk))

  (define (bytevector->block! blk bv)
    (bytevector-copy! bv 0 blk 0 ARGON2-BLOCK-SIZE))

  ;; --- 32-bit split fBlaMka ---
  ;; fBlaMka(x, y) = (x + y + 2*(x_lo32 * y_lo32)) mod 2^64
  ;; All intermediates fit in 61-bit fixnums (verified: max ~2^34).
  (define (fBlaMka32 x0 x1 y0 y1)
    ;; x = (x0=lo32, x1=hi32), y = (y0=lo32, y1=hi32)
    ;; Multiply x0*y0 using 16-bit halves to stay in fixnums
    (let* ((xl0 (fxlogand x0 #xFFFF))
           (xl1 (fxsrl x0 16))
           (yl0 (fxlogand y0 #xFFFF))
           (yl1 (fxsrl y0 16))
           (p00 (fx* xl0 yl0))
           (p01 (fx* xl0 yl1))
           (p10 (fx* xl1 yl0))
           (p11 (fx* xl1 yl1))
           ;; Combine partial products into lo32/hi32 of x0*y0
           (mid (fx+ p01 p10))
           (lo-sum (fx+ p00 (fxsll (fxlogand mid #xFFFF) 16)))
           (prod-lo (fxlogand lo-sum #xFFFFFFFF))
           (carry (fx+ (fxsrl lo-sum 32) (fxsrl mid 16)))
           (prod-hi (fxlogand (fx+ p11 carry) #xFFFFFFFF))
           ;; 2 * prod
           (two-lo (fxlogand (fxsll prod-lo 1) #xFFFFFFFF))
           (two-carry (fxsrl prod-lo 31))
           (two-hi (fxlogand (fx+ (fxsll prod-hi 1) two-carry) #xFFFFFFFF))
           ;; result = x + y + 2*prod
           (sum-lo (fx+ x0 (fx+ y0 two-lo)))
           (r-lo (fxlogand sum-lo #xFFFFFFFF))
           (carry-out (fxsrl sum-lo 32))
           (sum-hi (fx+ x1 (fx+ y1 (fx+ two-hi carry-out))))
           (r-hi (fxlogand sum-hi #xFFFFFFFF)))
      (values r-lo r-hi)))

  ;; --- Argon2 G mixing function (bytevector blocks, 32-bit split) ---
  ;; Indices are element indices (0-127); byte offsets computed internally.
  ;; Rotation amounts: 32 (swap), 24, 16, 63 (rotl 1).
  ;; All left shifts ≤ 25 bits on u32 values, max result < 2^57 < 2^60 (fixnum).
  (define (argon2-G! v ai bi ci di)
    (let ((ao (fx* ai 8)) (bo (fx* bi 8)) (co (fx* ci 8)) (do2 (fx* di 8)))
      (let ((a0 (bytevector-u32-ref v ao (endianness little)))
            (a1 (bytevector-u32-ref v (fx+ ao 4) (endianness little)))
            (b0 (bytevector-u32-ref v bo (endianness little)))
            (b1 (bytevector-u32-ref v (fx+ bo 4) (endianness little)))
            (c0 (bytevector-u32-ref v co (endianness little)))
            (c1 (bytevector-u32-ref v (fx+ co 4) (endianness little)))
            (d0 (bytevector-u32-ref v do2 (endianness little)))
            (d1 (bytevector-u32-ref v (fx+ do2 4) (endianness little))))
        ;; 1. a = fBlaMka(a, b)
        (let-values (((a0 a1) (fBlaMka32 a0 a1 b0 b1)))
          ;; 2. d = rotr64(d^a, 32) = swap halves of (d XOR a)
          (let ((d0 (fxlogxor d1 a1)) (d1 (fxlogxor d0 a0)))
            ;; 3. c = fBlaMka(c, d)
            (let-values (((c0 c1) (fBlaMka32 c0 c1 d0 d1)))
              ;; 4. b = rotr64(b^c, 24)
              (let ((t0 (fxlogxor b0 c0)) (t1 (fxlogxor b1 c1)))
                (let ((b0 (fxlogand (fxlogior (fxsrl t0 24) (fxsll t1 8)) #xFFFFFFFF))
                      (b1 (fxlogand (fxlogior (fxsrl t1 24) (fxsll t0 8)) #xFFFFFFFF)))
                  ;; 5. a = fBlaMka(a, b)
                  (let-values (((a0 a1) (fBlaMka32 a0 a1 b0 b1)))
                    ;; 6. d = rotr64(d^a, 16)
                    (let ((t0 (fxlogxor d0 a0)) (t1 (fxlogxor d1 a1)))
                      (let ((d0 (fxlogand (fxlogior (fxsrl t0 16) (fxsll t1 16)) #xFFFFFFFF))
                            (d1 (fxlogand (fxlogior (fxsrl t1 16) (fxsll t0 16)) #xFFFFFFFF)))
                        ;; 7. c = fBlaMka(c, d)
                        (let-values (((c0 c1) (fBlaMka32 c0 c1 d0 d1)))
                          ;; 8. b = rotr64(b^c, 63) = rotl64(b^c, 1)
                          (let ((t0 (fxlogxor b0 c0)) (t1 (fxlogxor b1 c1)))
                            (let ((b0 (fxlogand (fxlogior (fxsll t0 1) (fxsrl t1 31)) #xFFFFFFFF))
                                  (b1 (fxlogand (fxlogior (fxsll t1 1) (fxsrl t0 31)) #xFFFFFFFF)))
                              ;; Store results
                              (bytevector-u32-set! v ao a0 (endianness little))
                              (bytevector-u32-set! v (fx+ ao 4) a1 (endianness little))
                              (bytevector-u32-set! v bo b0 (endianness little))
                              (bytevector-u32-set! v (fx+ bo 4) b1 (endianness little))
                              (bytevector-u32-set! v co c0 (endianness little))
                              (bytevector-u32-set! v (fx+ co 4) c1 (endianness little))
                              (bytevector-u32-set! v do2 d0 (endianness little))
                              (bytevector-u32-set! v (fx+ do2 4) d1 (endianness little))))))))))))))))

  ;; BLAKE2_ROUND_NOMSG: 8 G calls on 16 words (columns then diagonals)
  (define (blake2-round-nomsg! v i0 i1 i2 i3 i4 i5 i6 i7 i8 i9 i10 i11 i12 i13 i14 i15)
    (argon2-G! v i0 i4 i8  i12)
    (argon2-G! v i1 i5 i9  i13)
    (argon2-G! v i2 i6 i10 i14)
    (argon2-G! v i3 i7 i11 i15)
    (argon2-G! v i0 i5 i10 i15)
    (argon2-G! v i1 i6 i11 i12)
    (argon2-G! v i2 i7 i8  i13)
    (argon2-G! v i3 i4 i9  i14))

  ;; fill-block: core block-filling function
  (define (fill-block! prev-block ref-block next-block with-xor blockR block-tmp)
    (copy-block! blockR ref-block)
    (xor-block! blockR prev-block)
    (copy-block! block-tmp blockR)
    (when with-xor
      (xor-block! block-tmp next-block))
    ;; Column rounds: 8 groups of 16 consecutive words
    (do ((i 0 (fx+ i 1))) ((fx= i 8))
      (let ((b (fx* 16 i)))
        (blake2-round-nomsg! blockR
          (fx+ b 0)  (fx+ b 1)  (fx+ b 2)  (fx+ b 3)
          (fx+ b 4)  (fx+ b 5)  (fx+ b 6)  (fx+ b 7)
          (fx+ b 8)  (fx+ b 9)  (fx+ b 10) (fx+ b 11)
          (fx+ b 12) (fx+ b 13) (fx+ b 14) (fx+ b 15))))
    ;; Row rounds: 8 groups with stride-16 indexing
    (do ((i 0 (fx+ i 1))) ((fx= i 8))
      (let ((b (fx* 2 i)))
        (blake2-round-nomsg! blockR
          b        (fx+ b 1)   (fx+ b 16)  (fx+ b 17)
          (fx+ b 32) (fx+ b 33) (fx+ b 48) (fx+ b 49)
          (fx+ b 64) (fx+ b 65) (fx+ b 80) (fx+ b 81)
          (fx+ b 96) (fx+ b 97) (fx+ b 112) (fx+ b 113))))
    (copy-block! next-block block-tmp)
    (xor-block! next-block blockR))

  ;; Generate pseudo-random addresses for data-independent mode
  (define (next-addresses! address-block input-block zero-block blockR block-tmp)
    ;; Increment element 6 (byte offset 48) — always a small fixnum
    (let ((val (bytevector-u64-ref input-block 48 (endianness little))))
      (bytevector-u64-set! input-block 48 (fx+ val 1) (endianness little)))
    (fill-block! zero-block input-block address-block #f blockR block-tmp)
    (fill-block! zero-block address-block address-block #f blockR block-tmp))

  ;; Compute reference block index with skewed distribution
  (define (index-alpha segment-length lane-length lanes pass slice index pseudo-rand same-lane)
    (let* ((reference-area-size
            (cond
             ((= pass 0)
              (cond
               ((= slice 0)
                (- index 1))
               (same-lane
                (- (+ (* slice segment-length) index) 1))
               (else
                (- (* slice segment-length) (if (= index 0) 1 0)))))
             (else
              (if same-lane
                  (- (+ lane-length (- segment-length) index) 1)
                  (- (+ lane-length (- segment-length)) (if (= index 0) 1 0))))))
           ;; Map pseudo_rand to 0..reference_area_size-1
           (relative-position (u32 pseudo-rand))
           (relative-position (ash (* relative-position relative-position) -32))
           (relative-position (- reference-area-size 1
                                 (ash (* reference-area-size relative-position) -32)))
           ;; Start position
           (start-position
            (if (not (= pass 0))
                (if (= slice (- ARGON2-SYNC-POINTS 1))
                    0
                    (* (+ slice 1) segment-length))
                0)))
      (mod (+ start-position relative-position) lane-length)))

  ;; Fill one segment of memory
  (define (fill-segment! memory memory-blocks segment-length lane-length lanes passes pass lane slice)
    (let* ((data-independent (and (= pass 0) (< slice 2)))
           (zero-block (and data-independent (make-block)))
           (input-block (and data-independent (make-block)))
           (address-block (and data-independent (make-block)))
           (blockR (make-block))
           (block-tmp (make-block))
           (starting-index (if (and (= pass 0) (= slice 0)) 2 0)))
      ;; Set up input block for data-independent addressing
      (when data-independent
        (bytevector-u64-set! input-block 0 pass (endianness little))
        (bytevector-u64-set! input-block 8 lane (endianness little))
        (bytevector-u64-set! input-block 16 slice (endianness little))
        (bytevector-u64-set! input-block 24 memory-blocks (endianness little))
        (bytevector-u64-set! input-block 32 passes (endianness little))
        (bytevector-u64-set! input-block 40 ARGON2-TYPE-ID (endianness little)))
      ;; Generate first address block if pass=0, slice=0
      (when (and (= pass 0) (= slice 0) data-independent)
        (next-addresses! address-block input-block zero-block blockR block-tmp))
      ;; Main loop
      (do ((i starting-index (+ i 1)))
          ((= i segment-length))
        (let* ((curr-offset (+ (* lane lane-length) (* slice segment-length) i))
               (prev-offset (if (= (mod curr-offset lane-length) 0)
                                (+ curr-offset lane-length -1)
                                (- curr-offset 1))))
          ;; Generate new addresses if needed
          (when (and data-independent (= (mod i ARGON2-ADDRESSES-IN-BLOCK) 0))
            (next-addresses! address-block input-block zero-block blockR block-tmp))
          ;; Read pseudo-rand as two u32 halves (no bignums)
          (let* ((pr-blk (if data-independent
                             address-block
                             (vector-ref memory prev-offset)))
                 (pr-off (if data-independent (fx* (mod i ARGON2-ADDRESSES-IN-BLOCK) 8) 0))
                 (pseudo-rand-lo (bytevector-u32-ref pr-blk pr-off (endianness little)))
                 (pseudo-rand-hi (bytevector-u32-ref pr-blk (fx+ pr-off 4) (endianness little)))
                 (ref-lane (mod pseudo-rand-hi lanes))
                 (ref-lane (if (and (= pass 0) (= slice 0)) lane ref-lane))
                 (ref-index (index-alpha segment-length lane-length lanes
                                        pass slice i
                                        pseudo-rand-lo
                                        (= ref-lane lane)))
                 (ref-block (vector-ref memory (+ (* ref-lane lane-length) ref-index)))
                 (prev-block (vector-ref memory prev-offset))
                 (curr-block (vector-ref memory curr-offset))
                 (with-xor (> pass 0)))
            (fill-block! prev-block ref-block curr-block with-xor blockR block-tmp))))))

  ;; Hash all parameters to produce initial 64-byte digest
  (define (initial-hash lanes outlen m-cost t-cost password salt)
    (let ((S (make-blake2b))
          (value (make-bytevector 4 0)))
      (blake2b-init! S ARGON2-PREHASH-DIGEST-LENGTH)
      (store32! value 0 lanes)
      (blake2b-update! S value 0 4)
      (store32! value 0 outlen)
      (blake2b-update! S value 0 4)
      (store32! value 0 m-cost)
      (blake2b-update! S value 0 4)
      (store32! value 0 t-cost)
      (blake2b-update! S value 0 4)
      (store32! value 0 ARGON2-VERSION-13)
      (blake2b-update! S value 0 4)
      (store32! value 0 ARGON2-TYPE-ID)
      (blake2b-update! S value 0 4)
      (store32! value 0 (bytevector-length password))
      (blake2b-update! S value 0 4)
      (when (> (bytevector-length password) 0)
        (blake2b-update! S password 0 (bytevector-length password)))
      (store32! value 0 (bytevector-length salt))
      (blake2b-update! S value 0 4)
      (when (> (bytevector-length salt) 0)
        (blake2b-update! S salt 0 (bytevector-length salt)))
      (store32! value 0 0)
      (blake2b-update! S value 0 4)
      (store32! value 0 0)
      (blake2b-update! S value 0 4)
      (let ((blockhash (make-bytevector ARGON2-PREHASH-SEED-LENGTH 0)))
        (blake2b-final! S blockhash)
        blockhash)))

  ;; Generate first 2 blocks per lane via blake2b-long
  (define (fill-first-blocks! blockhash memory lane-length lanes)
    (let ((blockhash-bytes (make-bytevector ARGON2-BLOCK-SIZE 0)))
      (do ((l 0 (+ l 1))) ((= l lanes))
        (store32! blockhash ARGON2-PREHASH-DIGEST-LENGTH 0)
        (store32! blockhash (+ ARGON2-PREHASH-DIGEST-LENGTH 4) l)
        (blake2b-long blockhash-bytes ARGON2-BLOCK-SIZE blockhash ARGON2-PREHASH-SEED-LENGTH)
        (bytevector->block! (vector-ref memory (+ (* l lane-length) 0)) blockhash-bytes)
        (store32! blockhash ARGON2-PREHASH-DIGEST-LENGTH 1)
        (blake2b-long blockhash-bytes ARGON2-BLOCK-SIZE blockhash ARGON2-PREHASH-SEED-LENGTH)
        (bytevector->block! (vector-ref memory (+ (* l lane-length) 1)) blockhash-bytes))))

  ;; Main Argon2 pipeline
  (define (argon2-ctx t-cost m-cost parallelism password salt outlen)
    (let* ((memory-blocks (max m-cost (* 2 ARGON2-SYNC-POINTS parallelism)))
           (segment-length (quotient memory-blocks (* parallelism ARGON2-SYNC-POINTS)))
           (memory-blocks (* segment-length parallelism ARGON2-SYNC-POINTS))
           (lane-length (* segment-length ARGON2-SYNC-POINTS))
           (memory (let ((mem (make-vector memory-blocks)))
                     (do ((i 0 (+ i 1))) ((= i memory-blocks) mem)
                       (vector-set! mem i (make-block))))))
      (let ((blockhash (initial-hash parallelism outlen m-cost t-cost password salt)))
        (fill-first-blocks! blockhash memory lane-length parallelism)
        (do ((pass 0 (+ pass 1))) ((= pass t-cost))
          (do ((slice 0 (+ slice 1))) ((= slice ARGON2-SYNC-POINTS))
            (do ((lane 0 (+ lane 1))) ((= lane parallelism))
              (fill-segment! memory memory-blocks segment-length lane-length
                            parallelism t-cost pass lane slice))))
        (let ((final-block (make-block)))
          (copy-block! final-block (vector-ref memory (- lane-length 1)))
          (do ((l 1 (+ l 1))) ((= l parallelism))
            (xor-block! final-block
                        (vector-ref memory (+ (* l lane-length) (- lane-length 1)))))
          (let ((final-bytes (block->bytevector final-block))
                (out (make-bytevector outlen 0)))
            (blake2b-long out outlen final-bytes ARGON2-BLOCK-SIZE)
            out)))))

  ;; ===== Layer 4: Encoding/Decoding =====

  (define b64-chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

  (define (b64-encode bv)
    (let* ((len (bytevector-length bv))
           (olen (+ (* (quotient len 3) 4)
                    (case (mod len 3) ((1) 2) ((2) 3) (else 0))))
           (out (make-string olen)))
      (let loop ((i 0) (j 0) (acc 0) (acc-len 0))
        (if (< i len)
            (let ((acc (+ (ash acc 8) (bytevector-u8-ref bv i)))
                  (acc-len (+ acc-len 8)))
              (let inner ((acc acc) (acc-len acc-len) (j j))
                (if (>= acc-len 6)
                    (let ((acc-len (- acc-len 6)))
                      (string-set! out j (string-ref b64-chars (logand (ash acc (- acc-len)) #x3F)))
                      (inner acc acc-len (+ j 1)))
                    (loop (+ i 1) j acc acc-len))))
            (when (> acc-len 0)
              (string-set! out j (string-ref b64-chars (logand (ash acc (- 6 acc-len)) #x3F))))))
      out))

  (define (b64-decode str)
    (define (char->b64 c)
      (cond
       ((and (char>=? c #\A) (char<=? c #\Z)) (- (char->integer c) (char->integer #\A)))
       ((and (char>=? c #\a) (char<=? c #\z)) (+ 26 (- (char->integer c) (char->integer #\a))))
       ((and (char>=? c #\0) (char<=? c #\9)) (+ 52 (- (char->integer c) (char->integer #\0))))
       ((char=? c #\+) 62)
       ((char=? c #\/) 63)
       (else #f)))
    (let* ((slen (string-length str))
           (out-len (let loop ((i 0) (acc-len 0) (len 0))
                      (if (= i slen) len
                          (let ((d (char->b64 (string-ref str i))))
                            (if d
                                (let ((acc-len (+ acc-len 6)))
                                  (if (>= acc-len 8)
                                      (loop (+ i 1) (- acc-len 8) (+ len 1))
                                      (loop (+ i 1) acc-len len)))
                                len)))))
           (result (make-bytevector out-len 0)))
      (let loop ((i 0) (j 0) (acc 0) (acc-len 0))
        (when (< i slen)
          (let ((d (char->b64 (string-ref str i))))
            (when d
              (let ((acc (+ (ash acc 6) d))
                    (acc-len (+ acc-len 6)))
                (if (>= acc-len 8)
                    (let ((acc-len (- acc-len 8)))
                      (bytevector-u8-set! result j (logand (ash acc (- acc-len)) #xFF))
                      (loop (+ i 1) (+ j 1) acc acc-len))
                    (loop (+ i 1) j acc acc-len)))))))
      result))

  (define (string-split str sep)
    (let loop ((start 0) (i 0) (acc '()))
      (cond
       ((= i (string-length str))
        (reverse (cons (substring str start i) acc)))
       ((char=? (string-ref str i) sep)
        (loop (+ i 1) (+ i 1) (cons (substring str start i) acc)))
       (else
        (loop start (+ i 1) acc)))))

  (define (encode-string salt hash t-cost m-cost parallelism)
    (let* ((str (string-append
                 "$argon2id$v=19"
                 "$m=" (number->string m-cost)
                 ",t=" (number->string t-cost)
                 ",p=" (number->string parallelism)
                 "$" (b64-encode salt)
                 "$" (b64-encode hash)))
           (bv (string->bytevector str (make-transcoder (utf-8-codec))))
           (result (make-bytevector (+ (bytevector-length bv) 1) 0)))
      (bytevector-copy! bv 0 result 0 (bytevector-length bv))
      result))

  (define (decode-string encoded)
    (let* ((str (if (bytevector? encoded)
                    (bytevector->string encoded (make-transcoder (utf-8-codec)))
                    encoded))
           (str (let loop ((s str))
                  (if (and (> (string-length s) 0)
                           (char=? (string-ref s (- (string-length s) 1)) #\nul))
                      (loop (substring s 0 (- (string-length s) 1)))
                      s)))
           (parts (string-split str #\$)))
      (let* ((version-str (list-ref parts 2))
             (version (string->number (substring version-str 2 (string-length version-str))))
             (params-parts (string-split (list-ref parts 3) #\,))
             (m-cost (string->number (substring (list-ref params-parts 0) 2
                                                (string-length (list-ref params-parts 0)))))
             (t-cost (string->number (substring (list-ref params-parts 1) 2
                                                (string-length (list-ref params-parts 1)))))
             (parallelism (string->number (substring (list-ref params-parts 2) 2
                                                     (string-length (list-ref params-parts 2)))))
             (salt (b64-decode (list-ref parts 4)))
             (hash (b64-decode (list-ref parts 5))))
        (values t-cost m-cost parallelism version salt hash))))

  ;; ===== Layer 5: Public API =====

  ;; OWASP 2024 second choice: t=2, m=19456 (19MB), p=1
  ;; Good balance of security and performance for single-core deployments.
  ;; argon2id-verify reads params from the encoded string, so changing
  ;; defaults does not break verification of existing hashes.
  (define argon2id-t-cost 2)
  (define argon2id-m-cost 19456)
  (define argon2id-parallelism 1)

  (define argon2id
    (lambda (salt password . args)
      (let ((t-cost (if (and (pair? args) (car args)) (car args) argon2id-t-cost))
            (m-cost (if (and (pair? args) (pair? (cdr args)) (cadr args)) (cadr args) argon2id-m-cost))
            (parallelism (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)) (caddr args)) (caddr args) argon2id-parallelism)))
        (argon2-ctx t-cost m-cost parallelism password salt 32))))

  (define argon2id-encode
    (lambda (salt password . args)
      (let* ((t-cost (if (and (pair? args) (car args)) (car args) argon2id-t-cost))
             (m-cost (if (and (pair? args) (pair? (cdr args)) (cadr args)) (cadr args) argon2id-m-cost))
             (parallelism (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)) (caddr args)) (caddr args) argon2id-parallelism))
             (hash-length 32)
             (hash (argon2-ctx t-cost m-cost parallelism password salt hash-length)))
        (encode-string salt hash t-cost m-cost parallelism))))

  (define argon2id-verify
    (lambda (encoded password)
      (call-with-values
       (lambda () (decode-string encoded))
       (lambda (t-cost m-cost parallelism version salt expected-hash)
         (let ((computed-hash (argon2-ctx t-cost m-cost parallelism password salt
                                         (bytevector-length expected-hash))))
           ;; Constant-time comparison
           (let loop ((i 0) (d 0))
             (if (= i (bytevector-length expected-hash))
                 (= d 0)
                 (loop (+ i 1)
                       (logior d (logxor (bytevector-u8-ref computed-hash i)
                                        (bytevector-u8-ref expected-hash i)))))))))))

  (define ~check-argon2-0
    (lambda ()
      (define bytevector-random
        (lambda (n)
          (u8-list->bytevector (map (lambda _ (random 256)) (iota n)))))
      (define salt (bytevector-random 256))
      (define password (bytevector-random 256))
      (assert (argon2id-verify (argon2id-encode salt password) password))))

  ) ;; end library

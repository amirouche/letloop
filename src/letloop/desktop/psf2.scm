;; PSF2 (PC Screen Font v2) reader.
;;
;; Format reference: linux/Documentation/admin-guide/console-codes.rst,
;; or kbd's `psf.h`. The header is 32 bytes; bitmap data follows; an
;; optional Unicode mapping table at the end describes which codepoints
;; map to which glyph index.
;;
;;   struct psf2_header {
;;     u32 magic;       // 0x864ab572 (bytes 0x72 0xb5 0x4a 0x86)
;;     u32 version;     // 0
;;     u32 headersize;  // 32
;;     u32 flags;       // bit 0 = has unicode table
;;     u32 length;      // number of glyphs
;;     u32 charsize;    // bytes per glyph (= height * ceil(width/8))
;;     u32 height;      // pixel height
;;     u32 width;       // pixel width
;;   };
;;
;; Bitmap pixels are MSB-first within each byte; rows are padded to a
;; whole number of bytes.
;;
;; Unicode table: for each glyph index i (0..length-1), a sequence of
;; UTF-8-encoded codepoints terminated by 0xFF. 0xFE separates ligature
;; sequences (multiple codepoints that map to the same glyph). Both
;; 0xFE and 0xFF are illegal in well-formed UTF-8 so they round-trip as
;; pure separators.
(library (letloop desktop psf2)
  (export
   psf2-load
   psf2?
   psf2-glyph-width
   psf2-glyph-height
   psf2-glyph-count
   psf2-glyph-bytes-per-row
   psf2-charsize
   psf2-bitmaps
   psf2-glyph-index
   psf2-glyph-bitmap
   psf2-codepoints)
  (import (chezscheme))

  ;; ----------------------------------------------------------------
  ;; Record
  ;; ----------------------------------------------------------------

  (define-record-type psf2
    (fields
     glyph-width        ; u32 — pixels
     glyph-height       ; u32 — pixels
     glyph-count        ; u32 — number of glyphs
     charsize           ; u32 — bytes per glyph
     bytes-per-row      ; u32 — ceil(width/8)
     bitmaps            ; bytevector — glyph-count * charsize bytes
     codepoint-table))  ; eq? hashtable, integer codepoint → glyph index

  (define (psf2-glyph-bytes-per-row p) (psf2-bytes-per-row p))

  ;; ----------------------------------------------------------------
  ;; Loading
  ;; ----------------------------------------------------------------

  (define PSF2_MAGIC0 #x72)
  (define PSF2_MAGIC1 #xb5)
  (define PSF2_MAGIC2 #x4a)
  (define PSF2_MAGIC3 #x86)
  (define PSF2_HAS_UNICODE_TABLE #x01)

  (define (u32-le bv off)
    (bitwise-ior
     (bytevector-u8-ref bv off)
     (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 1))  8)
     (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 2)) 16)
     (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 3)) 24)))

  (define (psf2-load bv)
    (let ((len (bytevector-length bv)))
      (when (< len 32)
        (error 'psf2-load "input too short for PSF2 header" len)))
    (unless (and (= (bytevector-u8-ref bv 0) PSF2_MAGIC0)
                 (= (bytevector-u8-ref bv 1) PSF2_MAGIC1)
                 (= (bytevector-u8-ref bv 2) PSF2_MAGIC2)
                 (= (bytevector-u8-ref bv 3) PSF2_MAGIC3))
      (error 'psf2-load "bad PSF2 magic"
             (list (bytevector-u8-ref bv 0)
                   (bytevector-u8-ref bv 1)
                   (bytevector-u8-ref bv 2)
                   (bytevector-u8-ref bv 3))))
    (let* ((version    (u32-le bv 4))
           (headersize (u32-le bv 8))
           (flags      (u32-le bv 12))
           (length     (u32-le bv 16))
           (charsize   (u32-le bv 20))
           (height     (u32-le bv 24))
           (width      (u32-le bv 28)))
      (unless (zero? version)
        (error 'psf2-load "unsupported PSF2 version" version))
      (unless (>= headersize 32)
        (error 'psf2-load "PSF2 headersize too small" headersize))
      (let* ((bytes-per-row (quotient (+ width 7) 8))
             (expected-charsize (* height bytes-per-row)))
        (unless (= charsize expected-charsize)
          (error 'psf2-load
                 "PSF2 charsize doesn't match width/height"
                 charsize expected-charsize)))
      (let* ((bitmaps-start headersize)
             (bitmaps-len (* length charsize))
             (bitmaps-end (+ bitmaps-start bitmaps-len)))
        (when (> bitmaps-end (bytevector-length bv))
          (error 'psf2-load "PSF2 bitmap data truncated"
                 bitmaps-end (bytevector-length bv)))
        (let* ((bitmaps (subbytevector bv bitmaps-start bitmaps-end))
               (table (make-eq-hashtable)))
          (when (not (zero? (bitwise-and flags PSF2_HAS_UNICODE_TABLE)))
            (parse-unicode-table! bv bitmaps-end length table))
          (make-psf2
           width height length charsize
           (quotient (+ width 7) 8)
           bitmaps
           table)))))

  (define (subbytevector bv start end)
    (let* ((n  (- end start))
           (r  (make-bytevector n)))
      (bytevector-copy! bv start r 0 n)
      r))

  ;; ----------------------------------------------------------------
  ;; Unicode table parsing
  ;; ----------------------------------------------------------------
  ;;
  ;; For each glyph i:
  ;;   sequence (UTF-8 codepoints) [0xFE sequence ...]* 0xFF
  ;;
  ;; A "sequence" in the simple case is a single UTF-8 codepoint, which
  ;; means "this glyph renders this codepoint". A 0xFE-separated tail
  ;; would be a ligature (multiple codepoints rendered as this glyph).
  ;; We index single-codepoint sequences only — first one wins.

  (define (parse-unicode-table! bv start glyph-count table)
    (let ((end (bytevector-length bv)))
      (let loop ((p start) (i 0))
        (cond
         ((= i glyph-count)
          ;; Trailing bytes after the last 0xFF are tolerated; some
          ;; tools pad. Just return.
          (void))
         ((>= p end)
          (error 'psf2-load
                 "Unicode table truncated before all glyphs"
                 i glyph-count))
         (else
          (let-values (((next-p) (parse-glyph-entry! bv p end i table)))
            (loop next-p (+ i 1))))))))

  ;; Parse one glyph's Unicode entry (sequences separated by 0xFE,
  ;; terminated by 0xFF). Records (codepoint → glyph-index) only for
  ;; the first sequence, and only if it's a single codepoint.
  (define (parse-glyph-entry! bv p end glyph-index table)
    ;; first-seq? is #t while we're in the very first sequence; we map
    ;; only single-codepoint first sequences, since multi-codepoint
    ;; ones are ligatures we can't address with `(get-char)` anyway.
    (let loop ((p p) (first-seq? #t) (codepoint-count 0) (last-cp #f))
      (when (>= p end)
        (error 'psf2-load "Unicode entry runs past end" glyph-index))
      (let ((b (bytevector-u8-ref bv p)))
        (cond
         ((= b #xFF)
          ;; End of this glyph's table entry.
          (when (and first-seq? (= codepoint-count 1) last-cp)
            (unless (hashtable-contains? table last-cp)
              (hashtable-set! table last-cp glyph-index)))
          (+ p 1))
         ((= b #xFE)
          ;; Sequence separator — finalize first sequence if applicable.
          (when (and first-seq? (= codepoint-count 1) last-cp)
            (unless (hashtable-contains? table last-cp)
              (hashtable-set! table last-cp glyph-index)))
          (loop (+ p 1) #f 0 #f))
         (else
          ;; Decode one UTF-8 codepoint.
          (let-values (((cp np) (decode-utf8 bv p end)))
            (loop np first-seq? (+ codepoint-count 1) cp)))))))

  (define (decode-utf8 bv p end)
    (let ((b (bytevector-u8-ref bv p)))
      (cond
       ;; 1-byte: 0xxxxxxx
       ((< b #x80)
        (values b (+ p 1)))
       ;; 2-byte: 110xxxxx 10xxxxxx
       ((= (bitwise-and b #xE0) #xC0)
        (when (>= (+ p 1) end) (error 'decode-utf8 "truncated 2-byte"))
        (values (bitwise-ior
                 (bitwise-arithmetic-shift-left (bitwise-and b #x1F) 6)
                 (bitwise-and (bytevector-u8-ref bv (+ p 1)) #x3F))
                (+ p 2)))
       ;; 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
       ((= (bitwise-and b #xF0) #xE0)
        (when (>= (+ p 2) end) (error 'decode-utf8 "truncated 3-byte"))
        (values (bitwise-ior
                 (bitwise-arithmetic-shift-left (bitwise-and b #x0F) 12)
                 (bitwise-arithmetic-shift-left
                  (bitwise-and (bytevector-u8-ref bv (+ p 1)) #x3F) 6)
                 (bitwise-and (bytevector-u8-ref bv (+ p 2)) #x3F))
                (+ p 3)))
       ;; 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
       ((= (bitwise-and b #xF8) #xF0)
        (when (>= (+ p 3) end) (error 'decode-utf8 "truncated 4-byte"))
        (values (bitwise-ior
                 (bitwise-arithmetic-shift-left (bitwise-and b #x07) 18)
                 (bitwise-arithmetic-shift-left
                  (bitwise-and (bytevector-u8-ref bv (+ p 1)) #x3F) 12)
                 (bitwise-arithmetic-shift-left
                  (bitwise-and (bytevector-u8-ref bv (+ p 2)) #x3F) 6)
                 (bitwise-and (bytevector-u8-ref bv (+ p 3)) #x3F))
                (+ p 4)))
       (else
        (error 'decode-utf8 "invalid leading byte" b)))))

  ;; ----------------------------------------------------------------
  ;; Lookup helpers
  ;; ----------------------------------------------------------------

  (define (psf2-glyph-index p codepoint)
    (hashtable-ref (psf2-codepoint-table p) codepoint #f))

  ;; Returns a fresh bytevector — caller may mutate it without
  ;; corrupting the loaded font.
  (define (psf2-glyph-bitmap p index)
    (when (or (negative? index) (>= index (psf2-glyph-count p)))
      (error 'psf2-glyph-bitmap "index out of range"
             index (psf2-glyph-count p)))
    (let* ((sz   (psf2-charsize p))
           (off  (* index sz))
           (out  (make-bytevector sz)))
      (bytevector-copy! (psf2-bitmaps p) off out 0 sz)
      out))

  (define (psf2-codepoints p)
    (vector->list (hashtable-keys (psf2-codepoint-table p)))))

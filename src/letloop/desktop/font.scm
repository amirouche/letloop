;; Atlas builder for PSF2 fonts.
;;
;; Given a parsed PSF2 font and a list of codepoints, produces a
;; single-channel (R8) atlas image laid out as a regular grid plus a
;; codepoint → glyph-info map. Each glyph-info knows its pixel rect in
;; the atlas (used at upload time) and its float UV rect (used by the
;; vertex shader to sample).
;;
;; Layout choice: plain grid. PSF2 glyphs are all the same size, so a
;; rectangle-packing algorithm would be wasted complexity. We pick the
;; column count so the resulting atlas is roughly square, which keeps
;; memory locality reasonable and avoids hitting platform texture
;; size limits (most ICDs cap 2D images at 8K — you'd need 100k+
;; glyphs to overflow).
(library (letloop desktop font)
  (export
   font-build
   font?
   font-atlas-width
   font-atlas-height
   font-atlas-pixels
   font-glyph-width
   font-glyph-height
   font-glyph-info
   font-codepoints
   glyph-info?
   glyph-info-px-x
   glyph-info-px-y
   glyph-info-uv-x
   glyph-info-uv-y
   glyph-info-uv-w
   glyph-info-uv-h)
  (import
   (chezscheme)
   (letloop desktop psf2))

  (define-record-type font
    (fields
     atlas-width        ; pixels
     atlas-height       ; pixels
     atlas-pixels       ; bytevector of width*height bytes (R8)
     glyph-width        ; pixels per glyph cell (= psf2 glyph-width)
     glyph-height       ; pixels per glyph cell
     glyph-info-table)) ; codepoint → glyph-info

  (define-record-type glyph-info
    (fields
     px-x px-y         ; integer pixel offset of this glyph's cell in the atlas
     uv-x uv-y         ; float — top-left UV in [0,1]
     uv-w uv-h))       ; float — UV size (= 1/cols, 1/rows)

  (define (font-glyph-info f cp)
    (hashtable-ref (font-glyph-info-table f) cp #f))

  (define (font-codepoints f)
    (vector->list (hashtable-keys (font-glyph-info-table f))))

  ;; ----------------------------------------------------------------
  ;; Builder
  ;; ----------------------------------------------------------------

  (define (font-build psf codepoints)
    ;; Filter out codepoints with no matching glyph; preserve input
    ;; order so the caller can predict layout for diagnostics.
    (define present
      (filter (lambda (cp) (psf2-glyph-index psf cp)) codepoints))
    (when (null? present)
      (error 'font-build "no requested codepoints have glyphs in this font"))
    (let* ((gw    (psf2-glyph-width  psf))
           (gh    (psf2-glyph-height psf))
           (n     (length present))
           ;; Aim for ~square atlas: cols = ceil(sqrt(n*gh/gw)), so that
           ;; cols*gw and rows*gh come out near-equal.
           (cols  (max 1 (exact (ceiling
                                 (sqrt (max 1 (/ (* n gh) gw)))))))
           (rows  (exact (ceiling (/ n cols))))
           (aw    (* cols gw))
           (ah    (* rows gh))
           (atlas (make-bytevector (* aw ah) 0))
           (table (make-eq-hashtable))
           (uv-w  (/ 1.0 cols))
           (uv-h  (/ 1.0 rows)))
      (let loop ((cps present) (i 0))
        (cond
         ((null? cps)
          (make-font aw ah atlas gw gh table))
         (else
          (let* ((cp    (car cps))
                 (gidx  (psf2-glyph-index psf cp))
                 (col   (remainder i cols))
                 (row   (quotient i cols))
                 (px-x  (* col gw))
                 (px-y  (* row gh)))
            (blit-glyph! psf gidx atlas aw px-x px-y)
            (hashtable-set! table cp
                            (make-glyph-info
                             px-x px-y
                             (* col uv-w)
                             (* row uv-h)
                             uv-w uv-h))
            (loop (cdr cps) (+ i 1))))))))

  ;; Blit one PSF2 glyph (MSB-first packed bits) into the R8 atlas at
  ;; (dst-x, dst-y). Set bits become 0xFF, unset stay 0x00 (atlas was
  ;; zero-initialised, so we only write the set ones).
  (define (blit-glyph! psf gidx atlas atlas-width dst-x dst-y)
    (let* ((gw    (psf2-glyph-width  psf))
           (gh    (psf2-glyph-height psf))
           (bpr   (psf2-glyph-bytes-per-row psf))
           (bv    (psf2-bitmaps psf))
           (gbase (* gidx (psf2-charsize psf))))
      (do ((row 0 (+ row 1)))
          ((= row gh))
        (let ((row-base (+ gbase (* row bpr))))
          (do ((col 0 (+ col 1)))
              ((= col gw))
            (let* ((byte (bytevector-u8-ref bv (+ row-base (quotient col 8))))
                   (bit  (bitwise-and byte
                                      (bitwise-arithmetic-shift-left
                                       1 (- 7 (remainder col 8))))))
              (unless (zero? bit)
                (bytevector-u8-set!
                 atlas
                 (+ (* (+ dst-y row) atlas-width)
                    (+ dst-x col))
                 #xFF)))))))))

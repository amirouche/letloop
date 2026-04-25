#!chezscheme
;; (letloop tea width) — column width of a Unicode codepoint.
;;
;; Returns:
;;   -1  control character (cannot be displayed in a cell)
;;    0  zero-width / combining mark
;;    1  normal "narrow" character
;;    2  East Asian Wide or Fullwidth (occupies two cells)
;;
;; Tables are the standard Markus Kuhn wcwidth(3) ranges (public domain),
;; covering Unicode 5.0 — sufficient for terminal use; rare extensions and
;; emoji nuances can be refined in stage 5.
;;
;; Stored as flat fxvectors [start1 end1 start2 end2 ...] so binary search
;; is one allocation-free pass over a contiguous block.
(library (letloop tea width)
  (export
   codepoint-width
   codepoint-control?
   codepoint-combining?
   codepoint-wide?)
  (import (chezscheme))

  ;; ----- range search -----------------------------------------------------

  (define (in-ranges? cp ranges)
    ;; Binary search over a flat [s0 e0 s1 e1 ...] fxvector.
    (let ((n (fxvector-length ranges)))
      (let loop ((lo 0) (hi (fxsrl n 1)))
        (cond
         ((fx>=? lo hi) #f)
         (else
          (let* ((mid (fxsrl (fx+ lo hi) 1))
                 (s   (fxvector-ref ranges (fx* mid 2)))
                 (e   (fxvector-ref ranges (fx+ (fx* mid 2) 1))))
            (cond
             ((fx<? cp s) (loop lo mid))
             ((fx>? cp e) (loop (fx+ mid 1) hi))
             (else        #t))))))))

  ;; ----- combining-mark ranges --------------------------------------------
  ;;
  ;; Markus Kuhn's mk_wcwidth combining table (Unicode 5.0 era).

  (define combining-ranges
    (fxvector
     #x0300 #x036F  #x0483 #x0486  #x0488 #x0489  #x0591 #x05BD
     #x05BF #x05BF  #x05C1 #x05C2  #x05C4 #x05C5  #x05C7 #x05C7
     #x0600 #x0603  #x0610 #x0615  #x064B #x065E  #x0670 #x0670
     #x06D6 #x06E4  #x06E7 #x06E8  #x06EA #x06ED  #x070F #x070F
     #x0711 #x0711  #x0730 #x074A  #x07A6 #x07B0  #x07EB #x07F3
     #x0901 #x0902  #x093C #x093C  #x0941 #x0948  #x094D #x094D
     #x0951 #x0954  #x0962 #x0963  #x0981 #x0981  #x09BC #x09BC
     #x09C1 #x09C4  #x09CD #x09CD  #x09E2 #x09E3  #x0A01 #x0A02
     #x0A3C #x0A3C  #x0A41 #x0A42  #x0A47 #x0A48  #x0A4B #x0A4D
     #x0A70 #x0A71  #x0A81 #x0A82  #x0ABC #x0ABC  #x0AC1 #x0AC5
     #x0AC7 #x0AC8  #x0ACD #x0ACD  #x0AE2 #x0AE3  #x0B01 #x0B01
     #x0B3C #x0B3C  #x0B3F #x0B3F  #x0B41 #x0B43  #x0B4D #x0B4D
     #x0B56 #x0B56  #x0B82 #x0B82  #x0BC0 #x0BC0  #x0BCD #x0BCD
     #x0C3E #x0C40  #x0C46 #x0C48  #x0C4A #x0C4D  #x0C55 #x0C56
     #x0CBC #x0CBC  #x0CBF #x0CBF  #x0CC6 #x0CC6  #x0CCC #x0CCD
     #x0CE2 #x0CE3  #x0D41 #x0D43  #x0D4D #x0D4D  #x0DCA #x0DCA
     #x0DD2 #x0DD4  #x0DD6 #x0DD6  #x0E31 #x0E31  #x0E34 #x0E3A
     #x0E47 #x0E4E  #x0EB1 #x0EB1  #x0EB4 #x0EB9  #x0EBB #x0EBC
     #x0EC8 #x0ECD  #x0F18 #x0F19  #x0F35 #x0F35  #x0F37 #x0F37
     #x0F39 #x0F39  #x0F71 #x0F7E  #x0F80 #x0F84  #x0F86 #x0F87
     #x0F90 #x0F97  #x0F99 #x0FBC  #x0FC6 #x0FC6  #x102D #x1030
     #x1032 #x1032  #x1036 #x1037  #x1039 #x1039  #x1058 #x1059
     #x1160 #x11FF  #x135F #x135F  #x1712 #x1714  #x1732 #x1734
     #x1752 #x1753  #x1772 #x1773  #x17B4 #x17B5  #x17B7 #x17BD
     #x17C6 #x17C6  #x17C9 #x17D3  #x17DD #x17DD  #x180B #x180D
     #x18A9 #x18A9  #x1920 #x1922  #x1927 #x1928  #x1932 #x1932
     #x1939 #x193B  #x1A17 #x1A18  #x1B00 #x1B03  #x1B34 #x1B34
     #x1B36 #x1B3A  #x1B3C #x1B3C  #x1B42 #x1B42  #x1B6B #x1B73
     #x1DC0 #x1DCA  #x1DFE #x1DFF  #x200B #x200F  #x202A #x202E
     #x2060 #x2063  #x206A #x206F  #x20D0 #x20EF  #x302A #x302F
     #x3099 #x309A  #xA806 #xA806  #xA80B #xA80B  #xA825 #xA826
     #xFB1E #xFB1E  #xFE00 #xFE0F  #xFE20 #xFE23  #xFEFF #xFEFF
     #xFFF9 #xFFFB  #x10A01 #x10A03  #x10A05 #x10A06  #x10A0C #x10A0F
     #x10A38 #x10A3A  #x10A3F #x10A3F
     #x1D167 #x1D169  #x1D173 #x1D182  #x1D185 #x1D18B
     #x1D1AA #x1D1AD  #x1D242 #x1D244
     #xE0001 #xE0001  #xE0020 #xE007F  #xE0100 #xE01EF))

  ;; ----- wide ranges -------------------------------------------------------
  ;;
  ;; East Asian Wide + Fullwidth + emoji that real terminals render as 2
  ;; cells.  Conservative — rare ranges (e.g. some private-use blocks) are
  ;; not included, matching termbox2's behavior.

  (define wide-ranges
    (fxvector
     #x1100  #x115F           ; Hangul Jamo init consonants
     #x2329  #x232A           ; angle brackets
     #x2E80  #x303E           ; CJK radicals/symbols
     #x3041  #x33FF           ; Hiragana/Katakana/CJK
     #x3400  #x4DBF           ; CJK Unified Ideographs Ext A
     #x4E00  #x9FFF           ; CJK Unified Ideographs
     #xA000  #xA4CF           ; Yi syllables
     #xAC00  #xD7A3           ; Hangul Syllables
     #xF900  #xFAFF           ; CJK compatibility ideographs
     #xFE30  #xFE4F           ; CJK compatibility forms
     #xFF00  #xFF60           ; fullwidth ASCII
     #xFFE0  #xFFE6           ; fullwidth signs
     #x1F300 #x1F64F          ; emoji symbols + emoticons
     #x1F900 #x1F9FF          ; supplemental symbols and pictographs
     #x20000 #x2FFFD          ; CJK Ext B–F
     #x30000 #x3FFFD))        ; CJK Ext G+

  ;; ----- predicates --------------------------------------------------------

  (define (codepoint-control? cp)
    (or (fx<? cp #x20)
        (and (fx>=? cp #x7F) (fx<? cp #xA0))))

  (define (codepoint-combining? cp)
    (and (fx>=? cp #x0300) (in-ranges? cp combining-ranges)))

  (define (codepoint-wide? cp)
    (and (fx>=? cp #x1100) (in-ranges? cp wide-ranges)))

  (define (codepoint-width cp)
    (cond
     ((codepoint-control?   cp) -1)
     ((codepoint-combining? cp)  0)
     ((codepoint-wide?      cp)  2)
     (else                       1)))
  )

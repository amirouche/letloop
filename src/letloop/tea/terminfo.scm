#!chezscheme
;; (letloop tea terminfo) — minimal parser for /usr/share/terminfo binary
;; files.  Used as a last-resort cap-set source when $TERM doesn't match any
;; built-in table.
;;
;; Binary format (from term(5)):
;;   header (12 bytes):
;;     u16 magic         0x011A (legacy) or 0x021E (extended numbers)
;;     u16 names-size
;;     u16 bool-count
;;     u16 num-count
;;     u16 str-offset-count
;;     u16 str-table-size
;;   names section:     names-size bytes (NUL-terminated, |-separated aliases)
;;   bool section:      bool-count bytes
;;   (alignment padding so num-section starts on an even byte)
;;   num section:       num-count * 2 bytes (legacy) or 4 bytes (extended)
;;   str-offset section: str-offset-count * 2 bytes (signed; -1 = absent)
;;   str-table:         str-table-size bytes (NUL-terminated strings)
;;
;; Every offset is little-endian.  We pull a curated subset of strings — the
;; ones termbox2 actually uses — by their well-known index in the
;; ncurses/terminfo string table.
(library (letloop tea terminfo)
  (export
   load-terminfo
   terminfo-paths
   terminfo-cap-set

   ~check-terminfo-paths-include-system
   ~check-terminfo-load-xterm
   ~check-terminfo-load-missing
   ~check-terminfo-xterm-has-altscreen
   ~check-terminfo-xterm-input-keys
   ~check-terminfo-as-fallback)
  (import (chezscheme)
          (letloop tea caps))

  ;; ----- ncurses string-cap indices ---------------------------------------
  ;;
  ;; From /usr/include/term.h (boolean and numeric sections skipped — we
  ;; only need strings).  The indices here have been verified against
  ;; /usr/share/terminfo/x/xterm: for example, str[5] is clear_screen, str
  ;; offsets read for that index resolve to "\e[H\e[2J".

  (define IDX-CLEAR-SCREEN   5)
  (define IDX-CIVIS         13)   ; cursor invisible
  (define IDX-CNORM         16)   ; cursor normal
  (define IDX-SMCUP         28)   ; enter ca mode (alt screen)
  (define IDX-RMCUP         40)   ; exit ca mode
  (define IDX-SGR0          39)   ; reset attributes
  (define IDX-SMKX          89)   ; keypad on
  (define IDX-RMKX          88)   ; keypad off
  (define IDX-KEY-UP        87)   ; arrow-up
  (define IDX-KEY-DOWN      61)
  (define IDX-KEY-LEFT      79)
  (define IDX-KEY-RIGHT     83)
  (define IDX-KEY-HOME      76)
  (define IDX-KEY-END       164)  ; kend
  (define IDX-KEY-IC        77)   ; key_ic = insert
  (define IDX-KEY-DC        59)   ; key_dc = delete
  (define IDX-KEY-NPAGE     81)   ; pg-down
  (define IDX-KEY-PPAGE     82)   ; pg-up
  (define IDX-KEY-F1        66)
  (define IDX-KEY-F2        68)
  (define IDX-KEY-F3        69)
  (define IDX-KEY-F4        70)
  (define IDX-KEY-F5        71)
  (define IDX-KEY-F6        72)
  (define IDX-KEY-F7        73)
  (define IDX-KEY-F8        74)
  (define IDX-KEY-F9        75)
  (define IDX-KEY-F10       67)
  (define IDX-KEY-F11       216)
  (define IDX-KEY-F12       217)

  (define INPUT-KEY-MAP
    `((,IDX-KEY-UP    . arrow-up)
      (,IDX-KEY-DOWN  . arrow-down)
      (,IDX-KEY-LEFT  . arrow-left)
      (,IDX-KEY-RIGHT . arrow-right)
      (,IDX-KEY-HOME  . home)
      (,IDX-KEY-END   . end)
      (,IDX-KEY-IC    . insert)
      (,IDX-KEY-DC    . delete)
      (,IDX-KEY-NPAGE . pg-down)
      (,IDX-KEY-PPAGE . pg-up)
      (,IDX-KEY-F1    . f1)
      (,IDX-KEY-F2    . f2)
      (,IDX-KEY-F3    . f3)
      (,IDX-KEY-F4    . f4)
      (,IDX-KEY-F5    . f5)
      (,IDX-KEY-F6    . f6)
      (,IDX-KEY-F7    . f7)
      (,IDX-KEY-F8    . f8)
      (,IDX-KEY-F9    . f9)
      (,IDX-KEY-F10   . f10)
      (,IDX-KEY-F11   . f11)
      (,IDX-KEY-F12   . f12)))

  ;; ----- search paths ------------------------------------------------------

  (define (terminfo-paths)
    (let* ((env-dirs (getenv "TERMINFO_DIRS"))
           (env-one  (getenv "TERMINFO"))
           (home     (getenv "HOME")))
      (filter (lambda (s) (and s (fx>? (string-length s) 0)))
              (append
               (if env-one  (list env-one) '())
               (if env-dirs (split-colon-paths env-dirs) '())
               (if home (list (string-append home "/.terminfo")) '())
               '("/etc/terminfo"
                 "/lib/terminfo"
                 "/usr/share/terminfo")))))

  (define (split-colon-paths s)
    (let loop ((i 0) (start 0) (acc '()))
      (cond
       ((fx>=? i (string-length s))
        (reverse (cons (substring s start i) acc)))
       ((char=? (string-ref s i) #\:)
        (loop (fx+ i 1) (fx+ i 1) (cons (substring s start i) acc)))
       (else (loop (fx+ i 1) start acc)))))

  (define (terminfo-find-file name)
    (let loop ((dirs (terminfo-paths)))
      (cond
       ((null? dirs) #f)
       (else
        (let* ((dir (car dirs))
               (first (string (string-ref name 0)))
               (path  (string-append dir "/" first "/" name)))
          (if (file-exists? path) path (loop (cdr dirs))))))))

  ;; ----- binary read helpers -----------------------------------------------

  (define (read-u8 p) (get-u8 p))

  (define (read-u16le p)
    ;; let*, not let: the initializers each consume a byte, and the order
    ;; a plain let evaluates them in is unspecified. Chez happened to
    ;; pick the one this wants, until (compile-profile 'source) changed
    ;; its mind and byte-swapped every 16-bit read in the file -- which
    ;; showed up as a terminal with no capabilities at all, since
    ;; build-cap-set takes the name from its argument rather than from
    ;; the parse and so still looked healthy.
    (let* ((lo (get-u8 p)) (hi (get-u8 p)))
      (cond
       ((or (eof-object? lo) (eof-object? hi)) #f)
       (else (fxior lo (fxsll hi 8))))))

  (define (read-i16le p)
    (let ((u (read-u16le p)))
      (cond
       ((not u) #f)
       ((fx>=? u #x8000) (fx- u #x10000))
       (else u))))

  (define (read-bytes p n)
    (let ((bv (make-bytevector n)))
      (let loop ((i 0))
        (cond
         ((fx=? i n) bv)
         (else
          (let ((b (get-u8 p)))
            (cond
             ((eof-object? b) #f)
             (else (bytevector-u8-set! bv i b) (loop (fx+ i 1))))))))))

  (define (skip-bytes p n)
    (let loop ((i 0))
      (when (fx<? i n) (get-u8 p) (loop (fx+ i 1)))))

  ;; ----- parse -------------------------------------------------------------

  (define (load-terminfo name)
    (let ((path (terminfo-find-file name)))
      (and path
           (call-with-port (open-file-input-port path)
             (lambda (p) (parse-terminfo p name))))))

  (define (parse-terminfo p name)
    (let* ((magic     (read-u16le p))
           (extended? (eqv? magic #x021E))
           (legacy?   (eqv? magic #x011A)))
      (cond
       ((not (or extended? legacy?)) #f)
       (else
        (let* ((names-size  (read-u16le p))
               (bool-count  (read-u16le p))
               (num-count   (read-u16le p))
               (offs-count  (read-u16le p))
               (str-size    (read-u16le p))
               (names       (read-bytes p names-size)))
          ;; bools
          (skip-bytes p bool-count)
          ;; alignment to even byte
          (let* ((bool-end (fx+ 12 names-size bool-count))
                 (pad (fxand bool-end 1)))
            (skip-bytes p pad))
          ;; numbers
          (skip-bytes p (fx* num-count (if extended? 4 2)))
          ;; string offsets
          (let ((offsets (make-vector offs-count -1)))
            (let loop ((i 0))
              (when (fx<? i offs-count)
                (vector-set! offsets i (read-i16le p))
                (loop (fx+ i 1))))
            ;; string table
            (let ((table (read-bytes p str-size)))
              (and table (build-cap-set name offsets table)))))))))

  (define (string-at table off)
    ;; Read NUL-terminated string starting at offset off.
    (cond
     ((or (fx<? off 0) (fx>=? off (bytevector-length table))) #f)
     (else
      (let loop ((i off))
        (cond
         ((fx>=? i (bytevector-length table)) #f)
         ((fx=? (bytevector-u8-ref table i) 0)
          (let* ((n  (fx- i off))
                 (bv (make-bytevector n)))
            (bytevector-copy! table off bv 0 n)
            (utf8->string bv)))
         (else (loop (fx+ i 1))))))))

  (define (cap-string-at offsets table idx)
    (cond
     ((fx>=? idx (vector-length offsets)) #f)
     (else
      (let ((off (vector-ref offsets idx)))
        (and (fx>=? off 0) (string-at table off))))))

  (define (build-cap-set name offsets table)
    (let* ((smcup (or (cap-string-at offsets table IDX-SMCUP) ""))
           (rmcup (or (cap-string-at offsets table IDX-RMCUP) ""))
           (civis (or (cap-string-at offsets table IDX-CIVIS) ""))
           (cnorm (or (cap-string-at offsets table IDX-CNORM) ""))
           (clear (or (cap-string-at offsets table IDX-CLEAR-SCREEN) ""))
           (sgr0  (or (cap-string-at offsets table IDX-SGR0) ""))
           (smkx  (or (cap-string-at offsets table IDX-SMKX) ""))
           (rmkx  (or (cap-string-at offsets table IDX-RMKX) ""))
           (init  (string-append smcup civis clear))
           (down  (string-append sgr0 cnorm rmcup))
           (input
            (let collect ((m INPUT-KEY-MAP) (acc '()))
              (cond
               ((null? m) (reverse acc))
               (else
                (let* ((idx  (caar m))
                       (sym  (cdar m))
                       (s    (cap-string-at offsets table idx)))
                  (collect (cdr m)
                           (if s (cons (cons s sym) acc) acc))))))))
      (make-cap-set name init down smkx rmkx input)))

  ;; ----- public lookup ----------------------------------------------------

  (define (terminfo-cap-set term)
    (and term (load-terminfo term)))

  (include "letloop/tea/terminfo.check.scm")
  )

#!chezscheme
(library (letloop review)
  (export letloop-review)
  (import (chezscheme)
          (letloop r999)
          (letloop termbox))

  ;; ---- String Utilities ----

  (define (string-search-forward pat str start)
    (let ((plen (string-length pat))
          (slen (string-length str)))
      (let loop ((i start))
        (cond
         ((fx>? (fx+ i plen) slen) #f)
         ((string=? pat (substring str i (fx+ i plen))) i)
         (else (loop (fx+ i 1)))))))

  (define (string-trim-right str)
    (let loop ((i (fx- (string-length str) 1)))
      (if (or (fx<? i 0) (not (char-whitespace? (string-ref str i))))
          (substring str 0 (fx+ i 1))
          (loop (fx- i 1)))))

  (define (string-trim-left str)
    (let ((len (string-length str)))
      (let loop ((i 0))
        (if (or (fx>=? i len) (not (char-whitespace? (string-ref str i))))
            (substring str i len)
            (loop (fx+ i 1))))))

  (define (string-prefix? prefix str)
    (let ((pl (string-length prefix))
          (sl (string-length str)))
      (and (fx<=? pl sl)
           (string=? prefix (substring str 0 pl)))))

  (define (string-suffix? suffix str)
    (let ((sl (string-length suffix))
          (tl (string-length str)))
      (and (fx<=? sl tl)
           (string=? suffix (substring str (fx- tl sl) tl)))))

  (define (string-wrap str max-w)
    (if (fx<=? max-w 0) (list str)
        (let ((len (string-length str)))
          (if (fx<=? len max-w)
              (list str)
              (let loop ((start 0) (acc '()))
                (if (fx>=? start len)
                    (reverse acc)
                    (let ((end (fxmin (fx+ start max-w) len)))
                      (loop end (cons (substring str start end) acc)))))))))

  (define (cursor-visual-pos text cursor max-w)
    (if (fx<=? max-w 0) (cons 0 cursor)
        (let ((len (string-length text)))
          (let loop ((start 0) (line 0))
            (let ((end (fxmin (fx+ start max-w) len)))
              (if (fx>=? end len)
                  (let ((col (fx- cursor start)))
                    (if (fx>=? col max-w)
                        (cons (fx+ line 1) 0)
                        (cons line col)))
                  (if (fx<? cursor end)
                      (cons line (fx- cursor start))
                      (loop end (fx+ line 1)))))))))

  ;; ---- Constants ----

  (define TREE-WIDTH 26)
  (define INPUT-MAX-LINES 5)

  ;; ---- Global State ----

  (define *mode* 'file-pane)
  (define *roots* '())

  (define *tree-entries* '#())
  (define *tree-cursor* 0)
  (define *tree-scroll* 0)

  (define *current-file* #f)
  (define *file-lines* '#())
  (define *file-highlights* '#())
  (define *file-kind* 'none)
  (define *folded* '())
  (define *fold-ends* '#())
  (define *content-cursor* 0)
  (define *content-scroll* 0)

  (define *annotations* (make-hashtable equal-hash equal?))
  (define *resolved*    (make-hashtable equal-hash equal?))
  (define *expanded-dirs* (make-hashtable equal-hash equal?))



  (define *input-buffer* "")
  (define *input-cursor* 0)
  (define *input-target-line* 0)
  (define *kill-ring* "")

  ;; ---- Tree Entry Record ----

  (define-record-type* <tree-entry>
    (make-tree-entry path name is-dir depth)
    tree-entry?
    (path     tree-entry-path)
    (name     tree-entry-name)
    (is-dir   tree-entry-is-dir)
    (depth    tree-entry-depth))

  (define (make-entry path name is-dir depth)
    (make-tree-entry path name is-dir depth))

  (define (entry-expanded? e)
    (and (tree-entry-is-dir e)
         (hashtable-ref *expanded-dirs* (tree-entry-path e) #f)))

  (define (toggle-entry-expand! e)
    (when (tree-entry-is-dir e)
      (let ((path (tree-entry-path e)))
        (if (hashtable-ref *expanded-dirs* path #f)
            (hashtable-delete! *expanded-dirs* path)
            (hashtable-set! *expanded-dirs* path #t)))))

  ;; ---- File System Walking ----

  (define (supported-file? name)
    (or (string-suffix? ".scm" name)
        (string-suffix? ".md" name)
        (string-suffix? ".txt" name)))

  (define (list-dir path)
    (sort string<? (directory-list path)))

  (define (build-entries-for path depth)
    (let ((entries (list-dir path)))
      (let loop ((names entries) (acc '()))
        (if (null? names)
            (reverse acc)
            (let* ((name (car names))
                   (full (string-append path "/" name))
                   (is-dir (file-directory? full)))
              (if (or is-dir (supported-file? name))
                  (loop (cdr names)
                        (cons (make-entry full name is-dir depth) acc))
                  (loop (cdr names) acc)))))))

  (define (build-tree-entries!)
    (let loop ((roots *roots*) (acc '()))
      (if (null? roots)
          (set! *tree-entries* (list->vector (reverse acc)))
          (let ((root (car roots)))
            (let inner ((entries (build-entries-for root 0)) (acc acc))
              (if (null? entries)
                  (loop (cdr roots) acc)
                  (let ((e (car entries)))
                    (if (and (tree-entry-is-dir e) (entry-expanded? e))
                        (inner (append (build-entries-for (tree-entry-path e)
                                                          (fx+ (tree-entry-depth e) 1))
                                       (cdr entries))
                               (cons e acc))
                        (inner (cdr entries) (cons e acc))))))))))

  ;; ---- Annotation Count ----

  (define (annotation-count-for path)
    (let ((count 0))
      (vector-for-each
       (lambda (k)
         (when (string=? (car k) path) (set! count (fx+ count 1))))
       (hashtable-keys *annotations*))
      count))

  ;; ---- Syntax Highlighting ----

  (define *scm-keywords*
    '("define" "lambda" "let" "let*" "letrec" "letrec*" "if" "cond" "case"
      "begin" "when" "unless" "and" "or" "not" "do" "define-syntax" "syntax-rules"
      "import" "export" "library" "define-record-type" "values" "call-with-values"
      "set!" "quote" "quasiquote" "unquote" "unquote-splicing" "delay" "force"
      "with-exception-handler" "raise" "guard" "parameterize" "define-values"))

  (define *rainbow-colors*
    (vector TB-RED TB-YELLOW TB-GREEN TB-CYAN TB-BLUE TB-MAGENTA))

  (define (rainbow-color depth)
    (vector-ref *rainbow-colors* (fxmod (fxmax depth 0) 6)))

  (define (tokenize-scm-line str depth-in in-str-in)
    (let ((len (string-length str))
          (spans '())
          (tok-start 0)
          (depth depth-in)
          (in-str in-str-in))
      (define (flush-tok end fg)
        (when (fx<? tok-start end)
          (set! spans (cons (list (substring str tok-start end) fg) spans))
          (set! tok-start end)))
      (let loop ((i 0))
        (if (fx>=? i len)
            (begin
              (if in-str (flush-tok i TB-GREEN) (flush-tok i TB-DEFAULT))
              (values (reverse spans) depth in-str))
            (let ((ch (string-ref str i)))
              (cond
               (in-str
                (cond
                 ((char=? ch #\\) (loop (fx+ i 2)))
                 ((char=? ch #\")
                  (flush-tok (fx+ i 1) TB-GREEN)
                  (set! in-str #f)
                  (set! tok-start (fx+ i 1))
                  (loop (fx+ i 1)))
                 (else (loop (fx+ i 1)))))
               ((char=? ch #\;)
                (flush-tok i TB-DEFAULT)
                (set! spans (cons (list (substring str i len) TB-GREEN) spans))
                (values (reverse spans) depth in-str))
               ((char=? ch #\")
                (flush-tok i TB-DEFAULT)
                (set! in-str #t)
                (set! tok-start i)
                (loop (fx+ i 1)))
               ((or (char=? ch #\() (char=? ch #\[))
                (flush-tok i TB-DEFAULT)
                (set! spans (cons (list (string ch) (rainbow-color depth)) spans))
                (set! depth (fx+ depth 1))
                (set! tok-start (fx+ i 1))
                (loop (fx+ i 1)))
               ((or (char=? ch #\)) (char=? ch #\]))
                (flush-tok i TB-DEFAULT)
                (set! depth (fx- depth 1))
                (set! spans (cons (list (string ch) (rainbow-color (fxmax depth 0))) spans))
                (set! tok-start (fx+ i 1))
                (loop (fx+ i 1)))
               ((char-whitespace? ch)
                (loop (fx+ i 1)))
               (else
                (let word-end ((j (fx+ i 1)))
                  (if (or (fx>=? j len)
                          (let ((c (string-ref str j)))
                            (or (char-whitespace? c)
                                (char=? c #\() (char=? c #\))
                                (char=? c #\[) (char=? c #\])
                                (char=? c #\;) (char=? c #\"))))
                      (let ((word (substring str tok-start j)))
                        (if (member word *scm-keywords*)
                            (begin
                              (flush-tok tok-start TB-DEFAULT)
                              (set! spans (cons (list word TB-YELLOW) spans))
                              (set! tok-start j))
                            (let ((fg (if (string->number word) TB-MAGENTA TB-DEFAULT)))
                              (flush-tok tok-start TB-DEFAULT)
                              (set! spans (cons (list word fg) spans))
                              (set! tok-start j)))
                        (loop j))
                      (word-end (fx+ j 1)))))))))))

  (define (tokenize-md-line str in-scheme-fence depth-in in-str-in)
    (cond
     ((and (not in-scheme-fence) (string-prefix? "```scheme" str))
      (values (list (list str TB-CYAN)) #t depth-in in-str-in))
     ((and in-scheme-fence (string-prefix? "```" str))
      (values (list (list str TB-CYAN)) #f 0 #f))
     (in-scheme-fence
      (let-values (((spans d s) (tokenize-scm-line str depth-in in-str-in)))
        (values spans #t d s)))
     ((string-prefix? "### " str) (values (list (list str TB-BLUE)) #f 0 #f))
     ((string-prefix? "## " str)  (values (list (list str TB-BLUE)) #f 0 #f))
     ((string-prefix? "# " str)   (values (list (list str TB-CYAN)) #f 0 #f))
     (else (values (list (list str TB-DEFAULT)) #f 0 #f))))

  ;; ---- Fold Boundary Computation ----

  (define (compute-fold-ends-scm lines)
    (let* ((n (vector-length lines))
           (ends (make-vector n -1)))
      (let loop ((i 0))
        (when (fx<? i n)
          (let* ((line (vector-ref lines i))
                 (trimmed (string-trim-left line)))
            (when (or (string-prefix? "(define " trimmed)
                      (string-prefix? "(define-syntax " trimmed)
                      (string-prefix? "(define-record-type " trimmed))
              (let scan ((j i) (open 0) (in-str #f) (found #f))
                (when (and (fx<? j n) (not found))
                  (let ((s (vector-ref lines j))
                        (o-init (if (fx=? j i) 0 open)))
                    (let char-loop ((k 0) (o o-init) (in-s in-str))
                      (cond
                       ((fx>=? k (string-length s))
                        (scan (fx+ j 1) o in-s #f))
                       (in-s
                        (let ((ch (string-ref s k)))
                          (cond
                           ((char=? ch #\\) (char-loop (fx+ k 2) o #t))
                           ((char=? ch #\") (char-loop (fx+ k 1) o #f))
                           (else (char-loop (fx+ k 1) o #t)))))
                       (else
                        (let ((ch (string-ref s k)))
                          (cond
                           ((char=? ch #\;) (scan (fx+ j 1) o #f #f))
                           ((char=? ch #\") (char-loop (fx+ k 1) o #t))
                           ((char=? ch #\() (char-loop (fx+ k 1) (fx+ o 1) #f))
                           ((char=? ch #\))
                            (let ((o2 (fx- o 1)))
                              (if (fx=? o2 0)
                                  (begin (vector-set! ends i j) (scan j o2 #f #t))
                                  (char-loop (fx+ k 1) o2 #f))))
                           (else (char-loop (fx+ k 1) o #f))))))))))))
          (loop (fx+ i 1))))
      ends))

  (define (compute-fold-ends-md lines)
    (let* ((n (vector-length lines))
           (ends (make-vector n -1)))
      (let loop ((i 0))
        (when (fx<? i n)
          (let ((line (vector-ref lines i)))
            (when (string-prefix? "## " line)
              (let scan ((j (fx+ i 1)))
                (if (fx>=? j n)
                    (vector-set! ends i (fx- n 1))
                    (let ((s (vector-ref lines j)))
                      (if (and (string-prefix? "#" s) (not (string-prefix? "### " s)))
                          (vector-set! ends i (fx- j 1))
                          (scan (fx+ j 1))))))))
          (loop (fx+ i 1))))
      ends))

  ;; ---- File Loading ----

  (define (file-kind path)
    (cond
     ((string-suffix? ".scm" path) 'scm)
     ((string-suffix? ".md" path)  'md)
     ((string-suffix? ".txt" path) 'txt)
     (else 'none)))

  (define (read-file-lines path)
    (let ((port (open-input-file path)))
      (let loop ((lines '()))
        (let ((line (get-line port)))
          (if (eof-object? line)
              (begin (close-input-port port) (list->vector (reverse lines)))
              (loop (cons line lines)))))))

  (define (compute-highlights lines kind)
    (let* ((n (vector-length lines))
           (hl (make-vector n '())))
      (cond
       ((eq? kind 'scm)
        (let loop ((i 0) (depth 0) (in-str #f))
          (when (fx<? i n)
            (let-values (((spans d s) (tokenize-scm-line (vector-ref lines i) depth in-str)))
              (vector-set! hl i spans)
              (loop (fx+ i 1) d s)))))
       ((eq? kind 'md)
        (let loop ((i 0) (in-fence #f) (depth 0) (in-str #f))
          (when (fx<? i n)
            (let-values (((spans fence d s) (tokenize-md-line (vector-ref lines i) in-fence depth in-str)))
              (vector-set! hl i spans)
              (loop (fx+ i 1) fence d s)))))
       (else
        (let loop ((i 0))
          (when (fx<? i n)
            (vector-set! hl i (list (list (vector-ref lines i) TB-DEFAULT)))
            (loop (fx+ i 1))))))
      hl))

  (define (load-file! path)
    (set! *current-file* path)
    (set! *file-kind* (file-kind path))
    (set! *file-lines* (read-file-lines path))
    (set! *file-highlights* (compute-highlights *file-lines* *file-kind*))
    (set! *fold-ends*
          (cond
           ((eq? *file-kind* 'scm) (compute-fold-ends-scm *file-lines*))
           ((eq? *file-kind* 'md)  (compute-fold-ends-md *file-lines*))
           (else (make-vector (vector-length *file-lines*) -1))))
    (set! *folded* '())
    (set! *content-cursor* 0)
    (set! *content-scroll* 0))

  ;; ---- Visual Row Computation ----

  (define (visual-rows-from start count)
    (let* ((n (vector-length *file-lines*))
           (path *current-file*)
           (rows '())
           (added 0)
           (i start))
      (let loop ()
        (when (and (fx<? i n) (fx<? added count))
          (cond
           ((and (not (null? *folded*)) (memv i *folded*))
            (set! rows (cons (cons 'fold-placeholder i) rows))
            (set! added (fx+ added 1))
            (let ((end (vector-ref *fold-ends* i)))
              (set! i (if (fx>? end i) (fx+ end 1) (fx+ i 1)))))
           (else
            (set! rows (cons (cons 'line i) rows))
            (set! added (fx+ added 1))
            (when (and path (fx<? added count)
                       (hashtable-ref *annotations* (cons path i) #f))
              (set! rows (cons (cons 'annotation i) rows))
              (set! added (fx+ added 1)))
            (set! i (fx+ i 1))))
          (loop)))
      (reverse rows)))

  ;; ---- REVIEW.md I/O ----

  (define (normalize-path path)
    (if (string-prefix? "./" path)
        (substring path 2 (string-length path))
        path))

  (define (save-annotations!)
    (let ((tmp ".REVIEW.md.tmp"))
      (with-output-to-file tmp
        (lambda ()
          (display "# Review: ")
          (display (date-and-time))
          (newline) (newline)
          (let ((by-file (make-hashtable equal-hash equal?)))
            (vector-for-each
             (lambda (k)
               (let ((file (car k)) (line (cdr k))
                     (text (hashtable-ref *annotations* k "")))
                 (hashtable-set! by-file file
                                 (cons (cons line text) (hashtable-ref by-file file '())))))
             (hashtable-keys *annotations*))
            (vector-for-each
             (lambda (file)
               (display "## ") (display file) (newline) (newline)
               (for-each
                (lambda (e)
                  (let ((k (cons file (car e))))
                    (display "- ")
                    (when (hashtable-ref *resolved* k #f)
                      (display "[x] "))
                    (display "**Line ")
                    (display (fx+ (car e) 1))
                    (display "**: ")
                    (display (cdr e))
                    (newline)))
                (sort (lambda (a b) (fx<? (car a) (car b)))
                      (filter pair? (hashtable-ref by-file file '()))))
               (newline))
             (hashtable-keys by-file))))
        'replace)
      (system (string-append "mv -f " tmp " REVIEW.md"))))

  (define (load-annotations!)
    (when (file-exists? "REVIEW.md")
      (let ((port (open-input-file "REVIEW.md")))
        (let loop ((current-file #f))
          (let ((line (get-line port)))
            (unless (eof-object? line)
              (cond
               ((string-prefix? "## " line)
                (loop (string-trim-right (substring line 3 (string-length line)))))
               ((and current-file (string-prefix? "- " line))
                (let* ((rest (substring line 2 (string-length line)))
                       (resolved? (string-prefix? "[x] " rest))
                       (rest2 (if resolved?
                                  (substring rest 4 (string-length rest))
                                  rest)))
                  (when (string-prefix? "**Line " rest2)
                    (let* ((s (substring rest2 7 (string-length rest2)))
                           (colon (string-search-forward "**: " s 0)))
                      (when colon
                        (let ((n (string->number (substring s 0 colon)))
                              (text (substring s (fx+ colon 4) (string-length s))))
                          (when n
                            (let ((k (cons current-file (fx- n 1))))
                              (hashtable-set! *annotations* k text)
                              (when resolved?
                                (hashtable-set! *resolved* k #t))))))))
                  (loop current-file)))
               (else (loop current-file))))))
        (close-input-port port))))

  ;; ---- Input Editing ----

  (define (input-insert! c)
    (let* ((buf *input-buffer*) (cur *input-cursor*))
      (set! *input-buffer*
            (string-append (substring buf 0 cur) (string c)
                           (substring buf cur (string-length buf))))
      (set! *input-cursor* (fx+ cur 1))))

  (define (input-delete-before!)
    (let* ((buf *input-buffer*) (cur *input-cursor*))
      (when (fx>? cur 0)
        (set! *input-buffer*
              (string-append (substring buf 0 (fx- cur 1))
                             (substring buf cur (string-length buf))))
        (set! *input-cursor* (fx- cur 1)))))

  (define (input-delete-at!)
    (let* ((buf *input-buffer*) (cur *input-cursor*) (len (string-length buf)))
      (when (fx<? cur len)
        (set! *input-buffer*
              (string-append (substring buf 0 cur)
                             (substring buf (fx+ cur 1) len))))))

  (define (input-move-left!)
    (when (fx>? *input-cursor* 0)
      (set! *input-cursor* (fx- *input-cursor* 1))))

  (define (input-move-right!)
    (when (fx<? *input-cursor* (string-length *input-buffer*))
      (set! *input-cursor* (fx+ *input-cursor* 1))))

  (define (input-beginning-of-line!) (set! *input-cursor* 0))

  (define (input-end-of-line!)
    (set! *input-cursor* (string-length *input-buffer*)))

  (define (input-kill-to-eol!)
    (set! *kill-ring* (substring *input-buffer* *input-cursor* (string-length *input-buffer*)))
    (set! *input-buffer* (substring *input-buffer* 0 *input-cursor*)))

  (define (input-kill-word-back!)
    (let* ((buf *input-buffer*) (cur *input-cursor*))
      (when (fx>? cur 0)
        (let skip-sp ((i (fx- cur 1)))
          (cond
           ((fx<? i 0)
            (set! *kill-ring* (substring buf 0 cur))
            (set! *input-buffer* (substring buf cur (string-length buf)))
            (set! *input-cursor* 0))
           ((char=? (string-ref buf i) #\space) (skip-sp (fx- i 1)))
           (else
            (let skip-wd ((i i))
              (cond
               ((fx<? i 0)
                (set! *kill-ring* (substring buf 0 cur))
                (set! *input-buffer* (substring buf cur (string-length buf)))
                (set! *input-cursor* 0))
               ((char=? (string-ref buf i) #\space)
                (let ((nc (fx+ i 1)))
                  (set! *kill-ring* (substring buf nc cur))
                  (set! *input-buffer*
                        (string-append (substring buf 0 nc)
                                       (substring buf cur (string-length buf))))
                  (set! *input-cursor* nc)))
               (else (skip-wd (fx- i 1)))))))))))

  (define (input-word-left!)
    (let* ((buf *input-buffer*) (cur *input-cursor*))
      (let skip-sp ((i (fx- cur 1)))
        (cond
         ((fx<? i 0) (set! *input-cursor* 0))
         ((char=? (string-ref buf i) #\space) (skip-sp (fx- i 1)))
         (else
          (let skip-wd ((i i))
            (cond
             ((fx<? i 0) (set! *input-cursor* 0))
             ((char=? (string-ref buf i) #\space) (set! *input-cursor* (fx+ i 1)))
             (else (skip-wd (fx- i 1))))))))))

  (define (input-word-right!)
    (let* ((buf *input-buffer*) (len (string-length buf)) (cur *input-cursor*))
      (let skip-wd ((i cur))
        (cond
         ((fx>=? i len) (set! *input-cursor* len))
         ((char=? (string-ref buf i) #\space)
          (let skip-sp ((j i))
            (cond
             ((fx>=? j len) (set! *input-cursor* len))
             ((not (char=? (string-ref buf j) #\space)) (set! *input-cursor* j))
             (else (skip-sp (fx+ j 1))))))
         (else (skip-wd (fx+ i 1)))))))

  (define (input-yank!)
    (let* ((buf *input-buffer*) (cur *input-cursor*) (kr *kill-ring*))
      (when (fx>? (string-length kr) 0)
        (set! *input-buffer*
              (string-append (substring buf 0 cur) kr
                             (substring buf cur (string-length buf))))
        (set! *input-cursor* (fx+ cur (string-length kr))))))

  ;; ---- Rendering ----

  (define (input-mode?)
    (or (eq? *mode* 'annotating) (eq? *mode* 'editing)))

  (define (content-pane-height)
    (fx- (tb-height) 2
         (if (input-mode?) INPUT-MAX-LINES 0)))

  (define (render-spans! x y spans max-x bg)
    (let loop ((spans spans) (cx x))
      (when (and (pair? spans) (fx<? cx max-x))
        (let* ((span (car spans))
               (text (car span))
               (fg   (cadr span))
               (len  (string-length text))
               (avail (fx- max-x cx)))
          (if (fx<=? len avail)
              (begin (tb-print cx y fg bg text)
                     (loop (cdr spans) (fx+ cx len)))
              (begin (tb-print cx y fg bg (substring text 0 avail))
                     (loop '() max-x)))))))

  (define (render-file-pane!)
    (let* ((h (tb-height))
           (content-h (fx- h 2))
           (n (vector-length *tree-entries*)))
      (tb-print 0 0 TB-CYAN TB-DEFAULT "FILES                    ")
      (let loop ((row 0))
        (when (fx<? row content-h)
          (let ((idx (fx+ *tree-scroll* row)))
            (if (fx>=? idx n)
                (tb-print 0 (fx+ row 1) TB-DEFAULT TB-DEFAULT
                          (make-string TREE-WIDTH #\space))
                (let* ((e (vector-ref *tree-entries* idx))
                       (depth (tree-entry-depth e))
                       (name (tree-entry-name e))
                       (is-dir (tree-entry-is-dir e))
                       (ac (annotation-count-for (tree-entry-path e)))
                       (prefix (make-string (fx* depth 2) #\space))
                       (marker (if is-dir (if (entry-expanded? e) "v " "> ") "  "))
                       (suffix (if (fx>? ac 0)
                                   (string-append " [" (number->string ac) "]") ""))
                       (display-str (string-append prefix marker name suffix))
                       (cursor? (fx=? idx *tree-cursor*))
                       (fg (if cursor? TB-WHITE TB-DEFAULT))
                       (bg (if cursor? TB-BLUE TB-DEFAULT))
                       (padded (let ((l (string-length display-str)))
                                 (if (fx<? l TREE-WIDTH)
                                     (string-append display-str
                                                    (make-string (fx- TREE-WIDTH l) #\space))
                                     (substring display-str 0 TREE-WIDTH)))))
                  (tb-print 0 (fx+ row 1) fg bg padded))))
          (loop (fx+ row 1))))))

  (define (render-content-pane!)
    (let* ((w (tb-width))
           (h (tb-height))
           (content-h (content-pane-height))
           (cx TREE-WIDTH)
           (cw (fx- w TREE-WIDTH)))
      (let loop ((r 0))
        (when (fx<? r h)
          (tb-set-cell (fx- TREE-WIDTH 1) r (char->integer #\|) TB-DEFAULT TB-DEFAULT)
          (loop (fx+ r 1))))
      (if (not *current-file*)
          (tb-print cx 1 TB-DEFAULT TB-DEFAULT "  (no file open)")
          (let* ((n (vector-length *file-lines*))
                 (gutter (fx+ (string-length (number->string n)) 2))
                 (rows (visual-rows-from *content-scroll* content-h))
                 (display-name (normalize-path *current-file*))
                 (total-str (string-append display-name "  line "
                                           (number->string (fx+ *content-cursor* 1))
                                           "/" (number->string n))))
            (tb-print cx 0 TB-CYAN TB-DEFAULT
                      (let ((l (string-length total-str)))
                        (if (fx<? l cw)
                            (string-append total-str (make-string (fx- cw l) #\space))
                            (substring total-str 0 cw))))
            (let row-loop ((rows rows) (row 1))
              (when (and (pair? rows) (fx<? row (fx+ content-h 1)))
                (let* ((vrow (car rows))
                       (kind (car vrow))
                       (line-num (cdr vrow)))
                  (cond
                   ((eq? kind 'annotation)
                    (let* ((k (cons *current-file* line-num))
                           (text (hashtable-ref *annotations* k ""))
                           (resolved? (hashtable-ref *resolved* k #f))
                           (ann-prefix (if resolved? "  ✓ " "  ↳ "))
                           (ann-fg (if resolved? TB-GREEN TB-YELLOW))
                           (ann-prefix-len (string-length ann-prefix))
                           (max-w (fxmax (fx- cw ann-prefix-len) 1))
                           (wrapped (string-wrap text max-w))
                           (new-row
                            (let emit ((wls wrapped) (r row))
                              (if (or (null? wls) (fx>=? r (fx+ content-h 1)))
                                  r
                                  (let* ((s (string-append ann-prefix (car wls)))
                                         (padded (let ((l (string-length s)))
                                                   (if (fx<? l cw)
                                                       (string-append s (make-string (fx- cw l) #\space))
                                                       (substring s 0 cw)))))
                                    (tb-print cx r ann-fg TB-DEFAULT padded)
                                    (emit (cdr wls) (fx+ r 1)))))))
                      (row-loop (cdr rows) new-row)))
                   ((eq? kind 'fold-placeholder)
                    (let* ((line (vector-ref *file-lines* line-num))
                           (num-s (number->string (fx+ line-num 1)))
                           (pad (fx- (fx- gutter 2) (string-length num-s)))
                           (num-str (string-append (make-string pad #\space) num-s ": "))
                           (trunc (if (fx>? (string-length line) 30)
                                      (substring line 0 30) line))
                           (s (string-append num-str trunc " ..."))
                           (cursor? (fx=? line-num *content-cursor*))
                           (fg (if cursor? TB-WHITE TB-DEFAULT))
                           (bg (if cursor? TB-YELLOW TB-DEFAULT))
                           (padded (let ((l (string-length s)))
                                     (if (fx<? l cw)
                                         (string-append s (make-string (fx- cw l) #\space))
                                         (substring s 0 cw)))))
                      (tb-print cx row fg bg padded)
                      (row-loop (cdr rows) (fx+ row 1))))
                   (else
                    (let* ((num-s (number->string (fx+ line-num 1)))
                           (pad (fx- (fx- gutter 2) (string-length num-s)))
                           (num-str (string-append (make-string pad #\space) num-s ": "))
                           (gutter-w (string-length num-str))
                           (cursor? (fx=? line-num *content-cursor*))
                           (spans (vector-ref *file-highlights* line-num))
                           (fg (if cursor? TB-WHITE TB-DEFAULT))
                           (bg (if cursor? TB-YELLOW TB-DEFAULT))
                           (text (vector-ref *file-lines* line-num))
                           (text-len (string-length text))
                           (avail (fxmax (fx- cw gutter-w) 1))
                           (cont-prefix (make-string gutter-w #\space))
                           (new-row
                            (let emit ((chunk-idx 0) (off 0) (r row))
                              (if (or (fx>=? r (fx+ content-h 1))
                                      (and (fx>? chunk-idx 0) (fx>=? off text-len)))
                                  r
                                  (let* ((chunk-end (fxmin (fx+ off avail) text-len))
                                         (pfx (if (fx=? chunk-idx 0) num-str cont-prefix)))
                                    (tb-print cx r fg bg (make-string cw #\space))
                                    (tb-print cx r fg bg pfx)
                                    (if (fx=? chunk-idx 0)
                                        (render-spans!
                                         (fx+ cx gutter-w) r
                                         spans
                                         (fx+ cx cw)
                                         bg)
                                        (tb-print (fx+ cx gutter-w) r
                                                  (if cursor? fg TB-DEFAULT) bg
                                                  (substring text off chunk-end)))
                                    (if (fx>=? chunk-end text-len)
                                        (fx+ r 1)
                                        (emit (fx+ chunk-idx 1) chunk-end (fx+ r 1))))))))
                      (row-loop (cdr rows) new-row)))))))))))

  (define (render-input-area!)
    (let* ((w (tb-width))
           (h (tb-height))
           (prompt (if (eq? *mode* 'annotating) "[+] " "[~] "))
           (prompt-len (string-length prompt))
           (avail (fxmax (fx- w prompt-len) 1))
           (buf *input-buffer*)
           (cur *input-cursor*)
           (wrapped (string-wrap buf avail))
           (vpos (cursor-visual-pos buf cur avail))
           (vline (car vpos))
           (vcol (cdr vpos))
           (total-lines (length wrapped))
           (scroll (fxmax 0 (fxmin (fx- vline (fx- INPUT-MAX-LINES 1))
                                   (fxmax 0 (fx- total-lines INPUT-MAX-LINES)))))
           (start-row (fx- h 1 INPUT-MAX-LINES)))
      (let line-loop ((i 0))
        (when (fx<? i INPUT-MAX-LINES)
          (let* ((y (fx+ start-row i))
                 (wl-idx (fx+ scroll i))
                 (line-text (if (fx<? wl-idx total-lines)
                                (list-ref wrapped wl-idx) ""))
                 (is-cursor-row? (fx=? wl-idx vline))
                 (line-prefix (if (fx=? i 0) prompt (make-string prompt-len #\space)))
                 (full-line (string-append line-prefix line-text))
                 (padded (let ((l (string-length full-line)))
                           (if (fx<? l w)
                               (string-append full-line (make-string (fx- w l) #\space))
                               (substring full-line 0 w)))))
            (tb-print 0 y TB-BLACK TB-YELLOW padded)
            (when is-cursor-row?
              (let ((cursor-x (fx+ prompt-len vcol)))
                (when (fx<? cursor-x w)
                  (let ((c (if (fx<? vcol (string-length line-text))
                               (char->integer (string-ref line-text vcol))
                               (char->integer #\space))))
                    (tb-set-cell cursor-x y c TB-YELLOW TB-BLACK))))))
          (line-loop (fx+ i 1))))))

  (define (render-status-bar!)
    (let* ((w (tb-width))
           (h (tb-height))
           (y (fx- h 1)))
      (cond
       ((input-mode?)
        (let* ((bar "  ↵ commit  C-j newline  Esc cancel  C-a/e home/end  C-b/f move  C-k kill  C-w del-word  C-y yank")
               (padded (let ((l (string-length bar)))
                         (if (fx<? l w)
                             (string-append bar (make-string (fx- w l) #\space))
                             (substring bar 0 w)))))
          (tb-print 0 y TB-DEFAULT TB-DEFAULT padded)))
       ((eq? *mode* 'file-pane)
        (let* ((n (vector-length *tree-entries*))
               (path-str (if (and (fx>? n 0) (fx<? *tree-cursor* n))
                             (normalize-path
                              (tree-entry-path (vector-ref *tree-entries* *tree-cursor*)))
                             ""))
               (bar (if (string=? path-str "")
                        "[↑↓]move [Enter]open/close [Tab]switch [q]uit"
                        (string-append path-str
                                       "  [↑↓]move [Enter]open/close [Tab]switch [q]uit")))
               (padded (let ((l (string-length bar)))
                         (if (fx<? l w)
                             (string-append bar (make-string (fx- w l) #\space))
                             (substring bar 0 w)))))
          (tb-print 0 y TB-BLACK TB-WHITE padded)))
       (else
        (let* ((bar "[j/k]move [Tab]switch [a]nnotate [e]dit [d]el [r]esolve [n/N]next [z]fold [q]uit")
               (padded (let ((l (string-length bar)))
                         (if (fx<? l w)
                             (string-append bar (make-string (fx- w l) #\space))
                             (substring bar 0 w)))))
          (tb-print 0 y TB-BLACK TB-WHITE padded))))))

  (define (render!)
    (tb-clear)
    (render-file-pane!)
    (render-content-pane!)
    (when (input-mode?) (render-input-area!))
    (render-status-bar!)
    (tb-present))

  ;; ---- Cursor / Scroll Helpers ----

  (define (clamp n lo hi) (max lo (min hi n)))

  (define (tree-move-cursor! delta)
    (let ((n (vector-length *tree-entries*)))
      (when (fx>? n 0)
        (set! *tree-cursor* (clamp (fx+ *tree-cursor* delta) 0 (fx- n 1)))
        (let ((h (fx- (tb-height) 2)))
          (when (fx<? *tree-cursor* *tree-scroll*)
            (set! *tree-scroll* *tree-cursor*))
          (when (fx>=? *tree-cursor* (fx+ *tree-scroll* h))
            (set! *tree-scroll* (fx- *tree-cursor* (fx- h 1))))))))

  (define (folded-range-at line)
    (let loop ((folds *folded*))
      (if (null? folds)
          #f
          (let* ((fs (car folds))
                 (fe (vector-ref *fold-ends* fs)))
            (if (and (fx>? line fs) (fx<=? line fe))
                (cons fs fe)
                (loop (cdr folds)))))))

  (define (skip-folds! dir)
    (let ((n (vector-length *file-lines*)))
      (let loop ()
        (let ((range (folded-range-at *content-cursor*)))
          (when range
            (let ((next (if (fx>? dir 0)
                            (let ((fe+1 (fx+ (cdr range) 1)))
                              (if (fx>=? fe+1 n) (car range) fe+1))
                            (car range))))
              (when (not (fx=? next *content-cursor*))
                (set! *content-cursor* next)
                (loop))))))))

  ;; Count visual rows from line `from` up to (not including) line `to`,
  ;; treating each folded define as 1 row.
  (define (visual-distance from to)
    (let loop ((i from) (rows 0))
      (cond
       ((fx>=? i to) rows)
       ((and (memv i *folded*) (fx>? (vector-ref *fold-ends* i) i))
        (loop (fx+ (vector-ref *fold-ends* i) 1) (fx+ rows 1)))
       (else (loop (fx+ i 1) (fx+ rows 1))))))

  ;; Walk backward from `cursor` to find scroll s such that cursor sits at
  ;; visual row h-1 from s.  Never returns a line inside a fold body.
  (define (scroll-for-bottom cursor h)
    (let loop ((i cursor) (rows 0))
      (cond
       ((fx<=? i 0) 0)
       ((fx>=? rows (fx- h 1))
        (let ((range (folded-range-at i)))
          (if range (car range) i)))
       (else
        (let ((range (folded-range-at (fx- i 1))))
          (if range
              (loop (car range) (fx+ rows 1))
              (loop (fx- i 1) (fx+ rows 1))))))))

  (define (content-move-cursor! delta)
    (let ((n (vector-length *file-lines*)))
      (when (fx>? n 0)
        (set! *content-cursor* (clamp (fx+ *content-cursor* delta) 0 (fx- n 1)))
        (skip-folds! delta)
        (snap-scroll-out-of-folds!)
        (let ((h (fx- (tb-height) 2)))
          (when (fx<? *content-cursor* *content-scroll*)
            (set! *content-scroll* *content-cursor*))
          (when (fx>=? (visual-distance *content-scroll* *content-cursor*) h)
            (set! *content-scroll* (scroll-for-bottom *content-cursor* h))
            (snap-scroll-out-of-folds!))))))

  ;; ---- Folding ----

  (define (snap-scroll-out-of-folds!)
    (let loop ()
      (let ((range (folded-range-at *content-scroll*)))
        (when range
          (set! *content-scroll* (car range))
          (loop)))))

  (define (toggle-fold!)
    (let* ((line *content-cursor*)
           (end (vector-ref *fold-ends* line)))
      (when (fx>? end line)
        (if (memv line *folded*)
            (set! *folded* (filter (lambda (x) (not (fx=? x line))) *folded*))
            (set! *folded* (cons line *folded*)))
        (snap-scroll-out-of-folds!))))

  ;; ---- Annotation Helpers ----

  (define (current-annotation)
    (and *current-file*
         (hashtable-ref *annotations* (cons *current-file* *content-cursor*) #f)))

  (define (commit-annotation! text)
    (when *current-file*
      (if (string=? text "")
          (hashtable-delete! *annotations* (cons *current-file* *content-cursor*))
          (hashtable-set! *annotations* (cons *current-file* *content-cursor*) text))
      (save-annotations!)))

  (define (delete-annotation!)
    (when *current-file*
      (let ((k (cons *current-file* *content-cursor*)))
        (hashtable-delete! *annotations* k)
        (hashtable-delete! *resolved* k))
      (save-annotations!)))

  (define (toggle-resolved!)
    (when (current-annotation)
      (let ((k (cons *current-file* *content-cursor*)))
        (if (hashtable-ref *resolved* k #f)
            (hashtable-delete! *resolved* k)
            (hashtable-set! *resolved* k #t))
        (save-annotations!))))

  ;; ---- Next/Prev Annotated Line ----

  (define (annotated-lines-for-file)
    (let ((file *current-file*) (lines '()))
      (vector-for-each
       (lambda (k)
         (when (and file (string=? (car k) file))
           (set! lines (cons (cdr k) lines))))
       (hashtable-keys *annotations*))
      (sort fx<? lines)))

  (define (jump-to-next-annotation! dir)
    (let* ((cursor *content-cursor*)
           (lines (annotated-lines-for-file)))
      (when (pair? lines)
        (let ((target (if (fx>? dir 0)
                          (let loop ((ls lines))
                            (cond ((null? ls) (car lines))
                                  ((fx>? (car ls) cursor) (car ls))
                                  (else (loop (cdr ls)))))
                          (let loop ((ls (reverse lines)))
                            (cond ((null? ls) (car (reverse lines)))
                                  ((fx<? (car ls) cursor) (car ls))
                                  (else (loop (cdr ls))))))))
          (set! *content-cursor* target)
          (set! *content-scroll* (max 0 (fx- target 5)))))))

  ;; ---- Event Handling ----

  (define (handle-key-file-pane key ch)
    (cond
     ((fx=? key TB-KEY-ARROW-DOWN) (tree-move-cursor! 1))
     ((fx=? key TB-KEY-ARROW-UP)   (tree-move-cursor! -1))
     ((or (fx=? key TB-KEY-ENTER) (fx=? ch 13))
      (let ((n (vector-length *tree-entries*)))
        (when (fx>? n 0)
          (let ((e (vector-ref *tree-entries* *tree-cursor*)))
            (if (tree-entry-is-dir e)
                (begin (toggle-entry-expand! e) (build-tree-entries!))
                (begin (load-file! (tree-entry-path e)) (set! *mode* 'content-pane)))))))
     ((fx=? key TB-KEY-TAB) (set! *mode* 'content-pane))
     ((fx=? ch (char->integer #\q)) (tb-shutdown) (exit))))

  (define (handle-key-content-pane key ch)
    (cond
     ((or (fx=? key TB-KEY-ARROW-DOWN) (fx=? ch (char->integer #\j))) (content-move-cursor! 1))
     ((or (fx=? key TB-KEY-ARROW-UP)   (fx=? ch (char->integer #\k))) (content-move-cursor! -1))
     ((fx=? key TB-KEY-PGDN) (content-move-cursor! (content-pane-height)))
     ((fx=? key TB-KEY-PGUP) (content-move-cursor! (fx- (content-pane-height))))
     ((fx=? key TB-KEY-TAB) (set! *mode* 'file-pane))
     ((fx=? ch (char->integer #\a))
      (set! *mode* 'annotating)
      (set! *input-buffer* "")
      (set! *input-cursor* 0)
      (set! *input-target-line* *content-cursor*))
     ((fx=? ch (char->integer #\e))
      (let ((ann (current-annotation)))
        (when ann
          (set! *mode* 'editing)
          (set! *input-buffer* ann)
          (set! *input-cursor* (string-length ann))
          (set! *input-target-line* *content-cursor*))))
     ((fx=? ch (char->integer #\d)) (delete-annotation!))
     ((fx=? ch (char->integer #\r)) (toggle-resolved!))
     ((fx=? ch (char->integer #\n)) (jump-to-next-annotation! 1))
     ((fx=? ch (char->integer #\N)) (jump-to-next-annotation! -1))
     ((fx=? ch (char->integer #\z)) (toggle-fold!))
     ((fx=? ch (char->integer #\q)) (tb-shutdown) (exit))))


  (define (handle-key-input key ch mod)
    (cond
     ;; Commit: Enter (key=13)
     ((fx=? key TB-KEY-ENTER)
      (let ((text (string-trim-right *input-buffer*)))
        (set! *content-cursor* *input-target-line*)
        (commit-annotation! text)
        (set! *mode* 'content-pane)
        (set! *input-buffer* "")
        (set! *input-cursor* 0)))
     ;; C-j: insert newline
     ((fx=? key 10) (input-insert! #\newline))
     ;; Cancel: Esc
     ((fx=? key TB-KEY-ESC)
      (set! *mode* 'content-pane)
      (set! *input-buffer* "")
      (set! *input-cursor* 0))
     ;; Backspace
     ((or (fx=? key TB-KEY-BACKSPACE) (fx=? key TB-KEY-BACKSPACE2))
      (input-delete-before!))
     ;; C-a: beginning
     ((fx=? key 1) (input-beginning-of-line!))
     ;; C-b: back char
     ((fx=? key 2) (input-move-left!))
     ;; C-d: delete at cursor
     ((fx=? key 4) (input-delete-at!))
     ;; C-e: end
     ((fx=? key 5) (input-end-of-line!))
     ;; C-f: forward char
     ((fx=? key 6) (input-move-right!))
     ;; C-k: kill to end
     ((fx=? key 11) (input-kill-to-eol!))
     ;; C-w: kill word backward
     ((fx=? key 23) (input-kill-word-back!))
     ;; C-y: yank
     ((fx=? key 25) (input-yank!))
     ;; Left arrow: char left, or word left if ctrl-mod
     ((fx=? key TB-KEY-ARROW-LEFT)
      (if (fx=? mod 2) (input-word-left!) (input-move-left!)))
     ;; Right arrow: char right, or word right if ctrl-mod
     ((fx=? key TB-KEY-ARROW-RIGHT)
      (if (fx=? mod 2) (input-word-right!) (input-move-right!)))
     ;; Printable character
     ((fx>? ch 31) (input-insert! (integer->char ch)))))

  ;; ---- Main Event Loop ----

  (define (event-loop)
    (let loop ()
      (render!)
      (let ((ret (tb-poll)))
        (when (fx>=? ret 0)
          (let ((type (tb-ev-type))
                (key  (tb-ev-key))
                (ch   (tb-ev-ch))
                (mod  (tb-ev-mod)))
            (cond
             ((fx=? type TB-EVENT-RESIZE) #f)
             ((fx=? type TB-EVENT-KEY)
              (cond
               ((eq? *mode* 'file-pane)    (handle-key-file-pane key ch))
               ((eq? *mode* 'content-pane) (handle-key-content-pane key ch))
               ((input-mode?)              (handle-key-input key ch mod))))))))
      (loop)))

  ;; ---- Entry Point ----

  (define (letloop-review args)
    (let ((dirs (if (null? args) (list ".") args)))
      (set! *roots*
            (map (lambda (d)
                   (if (string-suffix? "/" d)
                       (substring d 0 (fx- (string-length d) 1))
                       d))
                 dirs))
      (load-annotations!)
      (build-tree-entries!)
      (set! *mode* 'file-pane)
      (set! *tree-cursor* 0)
      (set! *tree-scroll* 0)
      (tb-init)
      (event-loop)))

  )

#!chezscheme
(library (binink cli base)

  (export cli-write cli-read
          ~check-cli-00
          ~check-cli-01
          ~check-cli-02)
  (import (chezscheme))

  (define pk
    (lambda args
      (display ";; ")
      (write args)
      (newline)
      (car (reverse args))))

  (define (cli-read arguments)

    (define and=>
      (lambda (a p)
        (if a (p a) #f)))

    (define list-index
      (lambda (p o*)
        (and=> (find (lambda (io) (p (cdr io))) (map cons (iota (length o*)) o*))
               car)))

    (define keyword/value
      (lambda (string)
        (define index (list-index (lambda (x) (char=? x #\=)) (string->list string)))
        (if (not index)
            (values (string->symbol string) #t)
            (values (string->symbol (substring string 0 index)) (substring string (fx+ index 1) (string-length string))))))

    (let loop ((arguments arguments)
               (keywords '())
               (standalone '()))
      (if (null? arguments)
          (begin
            (values (reverse keywords) (reverse standalone) '()))
          (let ((head (car arguments)))
            (cond
             ((string=? head "--")
              (values (reverse keywords) (reverse standalone) (cdr arguments)))
             ((char=? (string-ref head 0) #\-)
              (call-with-values (lambda () (keyword/value head))
                (lambda (key value)
                  (loop (cdr arguments) (cons (cons key value) keywords) standalone))))
             (else (loop (cdr arguments) keywords (cons head standalone))))))))

  (define ~check-cli-00
    (lambda ()
      (call-with-values (lambda ()
                          (cli-read '("--foo=bar"
                                      "--qux"
                                      "-vvv"
                                      "positional"
                                      "arguments"
                                      "--"
                                      "olive"
                                      "extra")))
        (lambda args
          (equal? args (list '((--foo . "bar") (--qux . #t) (-vvv . #t))
                             '("positional" "arguments")
                             '("olive" "extra")))))))

  (define ~check-cli-01
    (lambda ()
      (call-with-values (lambda ()
                          (cli-read '("--foo=bar"
                                      "--qux"
                                      "-vvv"
                                      "positional"
                                      "arguments")))
        (lambda args
          (equal? args (list '((--foo . "bar") (--qux . #t) (-vvv . #t))
                             '("positional" "arguments")
                             '()))))))

  (define cli-write
    (lambda (keywords standalone extra)
      (define keywords* (fold-left
                         (lambda (a k)
                           (cond
                            ((not (cdr k)) a)
                            ((eq? (cdr k) #t) (cons (symbol->string (car k)) a))
                            ((number? (cdr k))
                             (cons (string-append (symbol->string (car k))
                                           "="
                                           (number->string (cdr k)))
                                   a))
                            ((symbol? (cdr k))
                             (cons (string-append (symbol->string (car k))
                                           "="
                                           (symbol->string (cdr k)))
                                   a))
                            ((string? (cdr k))
                             (cons (string-append (symbol->string (car k))
                                           "="
                                           (cdr k))
                                   a))))
                         '()
                         keywords))
      (append keywords* standalone (list "--") extra)))

  (define ~check-cli-02
    (lambda ()
      (equal? (cli-write '((--echo . tango))
                         '("alpha" "bravo")
                         '("extra" "arg0" "arg1"))
              (list "--echo=tango" "alpha" "bravo" "--" "extra" "arg0" "arg1")))))

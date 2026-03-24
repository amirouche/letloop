#!chezscheme
(library (letloop markdown)
  (export markdown->html
          markdown->sxml)

  (import (chezscheme)
          (letloop html htmlprag))

  (define libcmark.so (load-shared-object "libcmark.so"))

  (define %free (foreign-procedure "free" (void*) void))

  (define %cmark-markdown-to-html
    (foreign-procedure "cmark_markdown_to_html" (string size_t int) void*))

  (define (pointer->string ptr)
    (let loop ([i 0])
      (let ([b (foreign-ref 'unsigned-8 ptr i)])
        (if (fx= b 0)
            (let ([bv (make-bytevector i)])
              (do ([j 0 (fx+ j 1)])
                  ((fx= j i) (utf8->string bv))
                (bytevector-u8-set! bv j (foreign-ref 'unsigned-8 ptr j))))
            (loop (fx+ i 1))))))

  (define (markdown->html text)
    (let* ([bv (string->utf8 text)]
           [ptr (%cmark-markdown-to-html text (bytevector-length bv) 0)]
           [result (pointer->string ptr)])
      (%free ptr)
      result))

  (define (markdown->sxml text)
    (html->sxml (markdown->html text)))

  )

# `(import (binink cli base))`

How to work with command line arguments.

## `(cli-read arguments)`

Return multiple values in order:

- keywords such as `--help`, `-h`, `-vvv` or `--trace=verbose` as an
  association;
- standalone positional arguments in order of appeareance as a list of
  strings;
- extra arguments, that is anything after two dashes `--` are returned
  as a list of strings;

Example:

```scheme
(call-with-values (lambda ()
                    (cli-read (list "--trace=verbose" "--pretty"
                                    "olive" "oil"
                                    "--" "drink")))
  (lambda (keywords arguments extra)
    (assert (equal? keywords '((--trace . "verbose") (--pretty . #t))))
    (assert (equal? arguments ("olive" "oil")))
    (assert (equal? extra '("drink")))))
```

## `(cli-write keywords arguments extra)`

Produce a list of strings reversing the operation of `cli-read`:

Example:

```scheme
(equal? (cli-write (list '((--trace . "verbose") (--pretty . #t))
                         '("olive" "oil")
                         '("drink")))
        (list "--trace=verbose" "--pretty" "olive" "oil" "--" "drink"))
```

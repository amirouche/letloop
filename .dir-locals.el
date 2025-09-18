;; The 'nil' configuration applies to all modes.
((scheme-mode . ((indent-tabs-mode . nil)
                 (tab-width . 2)
                 (eval . (progn
                           (put 'with-lock 'scheme-indent-function 1)
                           (put 'guard 'scheme-indent-function 1)
                           (put 'call-with-errno 'scheme-indent-function 1)
                           (put 'with-mutex 'scheme-indent-function 1)
                           (put 'match 'scheme-indent-function 1))))))

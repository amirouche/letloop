#!chezscheme
(library (letloop termbox)
  (export tb-init tb-shutdown tb-width tb-height
          tb-clear tb-present tb-print tb-set-cell
          tb-poll tb-ev-type tb-ev-mod tb-ev-key tb-ev-ch
          tb-ev-w tb-ev-h
          TB-EVENT-KEY TB-EVENT-RESIZE
          TB-KEY-ESC TB-KEY-ENTER TB-KEY-BACKSPACE TB-KEY-BACKSPACE2 TB-KEY-TAB
          TB-KEY-ARROW-UP TB-KEY-ARROW-DOWN TB-KEY-ARROW-LEFT TB-KEY-ARROW-RIGHT
          TB-KEY-PGUP TB-KEY-PGDN
          TB-DEFAULT TB-BLACK TB-RED TB-GREEN TB-YELLOW TB-BLUE TB-MAGENTA TB-CYAN TB-WHITE)
  (import (chezscheme))

  (define _lib (load-shared-object "libtermbox2.so"))

  (define tb-init     (foreign-procedure "tb_wrap_init"     () int))
  (define tb-shutdown (foreign-procedure "tb_wrap_shutdown" () int))
  (define tb-width    (foreign-procedure "tb_wrap_width"    () int))
  (define tb-height   (foreign-procedure "tb_wrap_height"   () int))
  (define tb-clear    (foreign-procedure "tb_wrap_clear"    () int))
  (define tb-present  (foreign-procedure "tb_wrap_present"  () int))
  (define tb-print    (foreign-procedure "tb_wrap_print" (int int unsigned-32 unsigned-32 string) int))
  (define tb-set-cell (foreign-procedure "tb_wrap_set_cell" (int int unsigned-32 unsigned-32 unsigned-32) int))
  (define tb-poll     (foreign-procedure "tb_wrap_poll"  () int))
  (define tb-ev-type  (foreign-procedure "tb_ev_type"    () int))
  (define tb-ev-mod   (foreign-procedure "tb_ev_mod"     () int))
  (define tb-ev-key   (foreign-procedure "tb_ev_key"     () int))
  (define tb-ev-ch    (foreign-procedure "tb_ev_ch"      () int))
  (define tb-ev-w     (foreign-procedure "tb_ev_w"       () int))
  (define tb-ev-h     (foreign-procedure "tb_ev_h"       () int))

  ;; Event types
  (define TB-EVENT-KEY    1)
  (define TB-EVENT-RESIZE 2)

  ;; Special keys (termbox2 values)
  (define TB-KEY-ESC         27)
  (define TB-KEY-ENTER       13)
  (define TB-KEY-BACKSPACE   127)   ; DEL / backspace2
  (define TB-KEY-BACKSPACE2  8)     ; Ctrl-H
  (define TB-KEY-TAB         9)
  (define TB-KEY-ARROW-UP    65517)   ; 0xffff - 18
  (define TB-KEY-ARROW-DOWN  65516)   ; 0xffff - 19
  (define TB-KEY-ARROW-LEFT  65515)   ; 0xffff - 20
  (define TB-KEY-ARROW-RIGHT 65514)   ; 0xffff - 21
  (define TB-KEY-PGUP        65519)   ; 0xffff - 16
  (define TB-KEY-PGDN        65518)   ; 0xffff - 17

  ;; Colors
  (define TB-DEFAULT  0)
  (define TB-BLACK    1)
  (define TB-RED      2)
  (define TB-GREEN    3)
  (define TB-YELLOW   4)
  (define TB-BLUE     5)
  (define TB-MAGENTA  6)
  (define TB-CYAN     7)
  (define TB-WHITE    8)

  )

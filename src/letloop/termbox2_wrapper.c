#define TB_IMPL
#include "termbox2.h"

static struct tb_event _ev;

int tb_wrap_init(void)     { int r = tb_init(); tb_set_output_mode(TB_OUTPUT_NORMAL); return r; }
int tb_wrap_shutdown(void) { return tb_shutdown(); }
int tb_wrap_width(void)    { return tb_width(); }
int tb_wrap_height(void)   { return tb_height(); }
int tb_wrap_clear(void)    { return tb_clear(); }
int tb_wrap_present(void)  { return tb_present(); }

int tb_wrap_print(int x, int y, unsigned int fg, unsigned int bg, const char *str) {
    return tb_print(x, y, (uintattr_t)fg, (uintattr_t)bg, str);
}

int tb_wrap_set_cell(int x, int y, unsigned int ch, unsigned int fg, unsigned int bg) {
    return tb_set_cell(x, y, ch, (uintattr_t)fg, (uintattr_t)bg);
}

int tb_wrap_poll(void)  { return tb_poll_event(&_ev); }
int tb_ev_type(void)    { return (int)_ev.type; }
int tb_ev_mod(void)     { return (int)_ev.mod; }
int tb_ev_key(void)     { return (int)_ev.key; }
int tb_ev_ch(void)      { return (int)_ev.ch; }
int tb_ev_w(void)       { return (int)_ev.w; }
int tb_ev_h(void)       { return (int)_ev.h; }

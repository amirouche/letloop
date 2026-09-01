/* A C static library for checks/staticlib/base.scm to call into, to
 * exercise `letloop compile`'s archive linking. Deliberately trivial:
 * what is under test is the linking and symbol registration, not the
 * arithmetic. */
#include <stdio.h>

int letloop_check_add(int a, int b) { return a + b; }

void letloop_check_hello(void) { printf("hello from a static library\n"); }

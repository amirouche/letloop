#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string.h>
#include <sys/types.h>

#include "scheme.h"


const char petite_boot[] = {~{0x~x,~}};
const char scheme_boot[] = {~{0x~x,~}};
const char letloop_boot[] = {~{0x~x,~}};
const char program_boot[] = {~{0x~x,~}};

void custom_init(void) {
  Sregister_symbol("petite-boot", (void*) petite_boot);
  Sregister_symbol("petite-boot-size", (void*) sizeof(petite_boot));
  Sregister_symbol("scheme-boot", (void*) scheme_boot);
  Sregister_symbol("scheme-boot-size", (void*) sizeof(scheme_boot));
  Sregister_symbol("letloop-boot", (void*) letloop_boot);
  Sregister_symbol("letloop-boot-size", (void*) sizeof(letloop_boot));
}

int main(int argc, const char **argv) {
  Sscheme_init(0);
  Sregister_boot_file_bytes("petite", (void *) petite_boot, sizeof(petite_boot));
  Sregister_boot_file_bytes("scheme", (void *) scheme_boot, sizeof(scheme_boot));
  Sregister_boot_file_bytes("letloop", (void *) letloop_boot, sizeof(letloop_boot));
  if (sizeof(program_boot) != 0)
    Sregister_boot_file_bytes("program", (void *) program_boot, sizeof(program_boot));
  Sbuild_heap(NULL, custom_init);
  return Sscheme_start(argc, argv);
}

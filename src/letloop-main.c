/* letloop's C host.
 *
 * It exists to do two things Chez's own c/main.c will not.
 *
 * First, it does NOT parse the command line. c/main.c reads argv before
 * any Scheme runs and claims --help, --version, -b/--boot,
 * --optimize-level, --libdirs and a dozen more, at any position on the
 * line -- so a letloop that is the scheme binary under another name can
 * never see those arguments. Here argc and argv reach Sscheme_start
 * untouched, and every flag arrives at letloop-main.
 *
 * Second, it can carry its own boot image, appended to the executable.
 * That is what makes `letloop compile` produce a single self-contained
 * file without a C compiler: it copies this binary and concatenates a
 * standalone boot file and a trailer onto it. Bytes past the end of an
 * ELF image are ignored by the loader, so the result still runs.
 *
 * The layout, at the very end of the file:
 *
 *     [ boot image ][ 8-byte little-endian length ][ 8-byte magic ]
 *
 * With no trailer -- which is how letloop itself is installed -- the
 * binary falls back to Sbuild_heap(argv[0]), which loads <name>.boot
 * where <name> is the last component of argv[0]. So one binary serves
 * both roles: named letloop it runs letloop.boot, and with a payload
 * appended it runs that instead.
 */

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "scheme.h"

#define LETLOOP_MAGIC "LETLOOP\1"
#define LETLOOP_MAGIC_SIZE 8
#define LETLOOP_TRAILER_SIZE 16 /* length + magic */

/* Find the appended boot image, if there is one. Returns a pointer to
   its bytes and sets *size, or returns NULL.
 *
 * The file is mapped rather than read: reading it cost a 3.3MB malloc
 * and memcpy on every single start, which measured ~0.8ms against the
 * separate-boot-file arrangement this replaces -- 3% of a 27ms startup.
 * mmap hands Sregister_boot_file_bytes a pointer into the page cache
 * instead, and the pages the boot loader never touches are never read.
 * The whole file is mapped because mmap offsets must be page-aligned
 * and the payload begins wherever the host binary happens to end; the
 * mapping is deliberately never unmapped, since Chez keeps the pointer.
 */
static void *appended_boot(const char *path, iptr *size) {
  int fd;
  struct stat info;
  unsigned char *base;
  unsigned long long length = 0;
  int i;

  if (path == NULL) return NULL;
  if ((fd = open(path, O_RDONLY)) < 0) return NULL;

  if (fstat(fd, &info) != 0 || info.st_size <= LETLOOP_TRAILER_SIZE) {
    close(fd);
    return NULL;
  }

  base = mmap(NULL, (size_t)info.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd); /* the mapping keeps its own reference */
  if (base == MAP_FAILED) return NULL;

  if (memcmp(base + info.st_size - LETLOOP_MAGIC_SIZE,
             LETLOOP_MAGIC, LETLOOP_MAGIC_SIZE) != 0) {
    munmap(base, (size_t)info.st_size);
    return NULL;
  }

  for (i = 7; i >= 0; i--)
    length = (length << 8) | base[info.st_size - LETLOOP_TRAILER_SIZE + i];

  if (length == 0
      || length > (unsigned long long)info.st_size - LETLOOP_TRAILER_SIZE) {
    munmap(base, (size_t)info.st_size);
    return NULL;
  }

  *size = (iptr)length;
  return base + info.st_size - LETLOOP_TRAILER_SIZE - length;
}

int main(int argc, const char *argv[]) {
  void *boot;
  iptr size = 0;
  int status;

  Sscheme_init(0);

  /* /proc/self/exe rather than argv[0]: argv[0] is whatever the caller
     put there, and a program invoked through PATH or a symlink would
     otherwise fail to find itself. */
  if ((boot = appended_boot("/proc/self/exe", &size)) == NULL)
    boot = appended_boot(argv[0], &size);

  if (boot != NULL) {
    Sregister_boot_file_bytes("program", boot, size);
    Sbuild_heap(NULL, 0);
  } else {
    Sbuild_heap(argv[0], 0);
  }

  status = Sscheme_start(argc, argv);
  Sscheme_deinit();

  exit(status);
}

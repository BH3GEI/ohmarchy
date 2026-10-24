// sparsecp SRC DST: copy a disk image, leaving all-zero 1 MiB blocks as holes
// (the host's toybox cp and dd write every byte: a 64 GB image with 28 GB used
// would become 64 GB). Built static by install.sh; used by reset.sh.
#define _FILE_OFFSET_BITS 64
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: sparsecp SRC DST\n");
        return 2;
    }
    int in = open(argv[1], O_RDONLY);
    int out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (in < 0 || out < 0) {
        perror("open");
        return 1;
    }
    enum { BS = 1 << 20 };
    static char buf[BS], zero[BS];
    off_t pos = 0;
    for (;;) {
        ssize_t n = 0;
        while (n < BS) {  // a full block, or what is left
            ssize_t r = read(in, buf + n, BS - n);
            if (r < 0) {
                perror("read");
                return 1;
            }
            if (r == 0) {
                break;
            }
            n += r;
        }
        if (n == 0) {
            break;
        }
        if (memcmp(buf, zero, n) != 0) {
            if (pwrite(out, buf, n, pos) != n) {
                perror("write");
                return 1;
            }
        }
        pos += n;
    }
    if (ftruncate(out, pos) != 0 || fsync(out) != 0) {  // the size, holes at the end included
        perror("ftruncate");
        return 1;
    }
    return 0;
}

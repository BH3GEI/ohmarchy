#!/usr/bin/env python3
# Copy a byte range of a (sparse) disk image to a new sparse file, e.g. one
# partition out of a raw disk, without reading or writing the holes.
#   slice.py SRC OFFSET SIZE DST
import errno, os, sys
src, off, size, dst = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
CH = 4 << 20
fi = os.open(src, os.O_RDONLY)
fo = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
os.ftruncate(fo, size)
end, pos, data = off + size, off, 0
zero = bytes(CH)
seek_ok = hasattr(os, "SEEK_DATA")
while pos < end:
    if seek_ok:
        try:
            pos = os.lseek(fi, pos, os.SEEK_DATA)
            hole = os.lseek(fi, pos, os.SEEK_HOLE)
        except OSError as e:
            if e.errno == errno.ENXIO: break          # no data after pos
            seek_ok, hole = False, end
        if pos >= end: break
    else:
        hole = end
    stop = min(hole, end)
    while pos < stop:
        n = min(CH, stop - pos)
        b = os.pread(fi, n, pos)
        if b != zero[:len(b)]:
            os.pwrite(fo, b, pos - off); data += len(b)
        pos += n
os.close(fo)
print(f"copied {data >> 20} MiB of data, seek_data={seek_ok}")

/*
 * sparsecp SRC DST: copy a disk image to a block device or file, skipping its
 * holes and all-zero blocks, so a 64 GiB image with 9 GiB of data moves 9 GiB.
 * SRC "-" is stdin (zero blocks still skipped). For a regular SRC the holes
 * are found with SEEK_DATA/SEEK_HOLE (works over virtiofs) and never read.
 * DST is not zeroed where SRC has holes: use it on a fresh disk (铠大师's new
 * vm.qcow2 reads as zeros there).
 *
 * No libc, so it runs in any initramfs (here Debian's d-i one) on aarch64:
 *   clang --target=aarch64-linux-gnu -O2 -ffreestanding -fno-stack-protector \
 *     -nostdlib -static -fuse-ld=lld -o sparsecp sparsecp.c
 */
typedef long i64;
typedef unsigned long u64;

#define SYS_openat 56
#define SYS_close 57
#define SYS_lseek 62
#define SYS_read 63
#define SYS_write 64
#define SYS_pread64 67
#define SYS_pwrite64 68
#define SYS_fsync 82
#define SYS_exit 93
#define AT_FDCWD -100
#define O_RDONLY 0
#define O_WRONLY 1
#define SEEK_DATA 3
#define SEEK_HOLE 4
#define ENXIO 6

static i64 sys(i64 n, i64 a, i64 b, i64 c, i64 d)
{
	register i64 x8 __asm__("x8") = n;
	register i64 x0 __asm__("x0") = a;
	register i64 x1 __asm__("x1") = b;
	register i64 x2 __asm__("x2") = c;
	register i64 x3 __asm__("x3") = d;
	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}

static u64 slen(const char *s) { u64 n = 0; while (s[n]) n++; return n; }
static void say(const char *s) { sys(SYS_write, 2, (i64)s, slen(s), 0); }
static void num(u64 v)
{
	char b[24]; int i = 23; b[i] = 0;
	do { b[--i] = '0' + v % 10; v /= 10; } while (v);
	say(b + i);
}
static __attribute__((noreturn)) void die(const char *s) { say("sparsecp: "); say(s); say("\n"); sys(SYS_exit, 1, 0, 0, 0); __builtin_unreachable(); }

#define CH (4UL << 20)
static unsigned char buf[CH] __attribute__((aligned(4096)));

static int zero(const unsigned char *p, u64 n)
{
	const u64 *q = (const u64 *)p;
	for (u64 i = 0; i < n / 8; i++) if (q[i]) return 0;
	for (u64 i = n & ~7UL; i < n; i++) if (p[i]) return 0;
	return 1;
}

static u64 data, total;

/* write [off, off+n) of buf unless it is all zero */
static void put(int out, u64 off, u64 n)
{
	if (zero(buf, n)) return;
	for (u64 done = 0; done < n;) {
		i64 w = sys(SYS_pwrite64, out, (i64)(buf + done), n - done, off + done);
		if (w <= 0) die("write failed");
		done += w;
	}
	data += n;
}

static void progress(u64 off)
{
	if ((off >> 30) != ((off - CH) >> 30)) { say("sparsecp: "); num(off >> 30); say(" GiB, "); num(data >> 20); say(" MiB data\n"); }
}

__attribute__((used)) void main2(int argc, char **argv)
{
	if (argc != 3) die("usage: sparsecp SRC|- DST");
	int in = argv[1][0] == '-' && !argv[1][1] ? 0 : (int)sys(SYS_openat, AT_FDCWD, (i64)argv[1], O_RDONLY, 0);
	int out = (int)sys(SYS_openat, AT_FDCWD, (i64)argv[2], O_WRONLY, 0);
	if (in < 0) die("cannot open SRC");
	if (out < 0) die("cannot open DST");
	i64 end = in ? sys(SYS_lseek, in, 0, 2 /* SEEK_END */, 0) : -1;
	if (in && end > 0) {
		u64 pos = 0;
		while ((i64)pos < end) {
			i64 d = sys(SYS_lseek, in, pos, SEEK_DATA, 0);
			if (d == -ENXIO) break;
			if (d < 0) { d = pos; }            /* no SEEK_DATA: read everything */
			i64 h = sys(SYS_lseek, in, d, SEEK_HOLE, 0);
			if (h < 0) h = end;
			for (pos = d; (i64)pos < h;) {
				u64 n = (u64)(h - pos) < CH ? (u64)(h - pos) : CH;
				i64 r = sys(SYS_pread64, in, (i64)buf, n, pos);
				if (r <= 0) die("read failed");
				put(out, pos, r);
				pos += r; total = pos;
				progress(pos);
			}
		}
		total = end;
	} else {
		u64 pos = 0;
		for (;;) {
			u64 n = 0;
			while (n < CH) {       /* fill a whole chunk from the pipe */
				i64 r = sys(SYS_read, in, (i64)(buf + n), CH - n, 0);
				if (r < 0) die("read failed");
				if (r == 0) break;
				n += r;
			}
			if (!n) break;
			put(out, pos, n);
			pos += n; total = pos;
			progress(pos);
			if (n < CH) break;
		}
	}
	if (sys(SYS_fsync, out, 0, 0, 0) < 0) die("fsync failed");
	say("sparsecp: done, "); num(total); say(" bytes, "); num(data); say(" bytes of data written\n");
	sys(SYS_exit, 0, 0, 0, 0);
}

__attribute__((naked, noreturn)) void _start(void)
{
	__asm__ volatile(
		"ldr x0, [sp]\n"
		"add x1, sp, #8\n"
		"bl main2\n");
}

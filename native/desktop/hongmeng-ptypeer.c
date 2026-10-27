// Preloaded in the sandbox: HongMeng has no devpts, and the node of a new pty's slave
// appears only in the host's /dev/pts, which the sandbox does not get. Programs that
// open the slave by its name (foot, script, tmux) then fail with ENOENT. When opening
// "/dev/pts/N" fails so, return the slave of this process's own master N instead
// (TIOCGPTPEER on the /dev/ptmx fd it holds), and let ttyname name a slave that has
// no node. Nothing outside the process's own ptys becomes reachable.
// Such a slave is an anonymous inode on HongMeng (no name, device 0:0, no TIOCGPTN),
// so its name is kept: per fd in this process, and in OHMARCHY_TTY for the program a
// terminal starts on it. Programs reach slaves two ways: by name (foot), or through
// glibc's openpty/forkpty (script, tmux), which use TIOCGPTPEER themselves; both are
// covered here.
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <pty.h>
#include <sys/stat.h>
#include <utmp.h>
#include <unistd.h>

#ifndef TIOCGPTPEER
#define TIOCGPTPEER _IO('T', 0x41)
#endif

// OHMARCHY_PTY_DEBUG=1 (stderr) or =/path (appended): say what is done here
static void debug(const char *fmt, ...)
{
	const char *d = getenv("OHMARCHY_PTY_DEBUG");
	if (d == NULL || *d == '\0')
		return;
	FILE *f = d[0] == '/' ? fopen(d, "a") : stderr;
	if (f == NULL)
		return;
	va_list a;
	va_start(a, fmt);
	fprintf(f, "ptypeer[%d]: ", (int)getpid());
	vfprintf(f, fmt, a);
	va_end(a);
	if (f != stderr)
		fclose(f);
}
#define DEBUG(...) debug(__VA_ARGS__)
#define REAL(name) static __typeof__(name) *real; if (!real) real = dlsym(RTLD_NEXT, #name)

// pty number of "/dev/pts/N", or -1
static int pts_number(const char *path)
{
	unsigned n;
	char end;
	if (path == NULL || sscanf(path, "/dev/pts/%u%c", &n, &end) != 1)
		return -1;
	return (int)n;
}

// masters from posix_openpt here, with the pid that opened them (forks inherit the
// table); /proc/self/fd is the fallback for masters opened otherwise
static struct { int fd, pid; } masters[16];  // fd + 1
// foot's child unlocks the master, closes it, then opens the slave by name: by then
// there is no master to ask. So a forked child closing a master keeps its slave
// first, until the open asks for it (by pty number)
static struct { int n, fd; } kept[4];  // fd + 1

int posix_openpt(int flags)
{
	REAL(posix_openpt);
	int m = real(flags);
	for (int i = 0; m >= 0 && i < 16; i++)
		if (masters[i].fd == 0 || masters[i].fd == m + 1) {
			masters[i].fd = m + 1;
			masters[i].pid = getpid();
			break;
		}
	return m;
}

int close(int fd)
{
	REAL(close);
	for (int i = 0; fd >= 0 && i < 16; i++) {
		if (masters[i].fd != fd + 1)
			continue;
		masters[i].fd = 0;
		unsigned n;
		if (masters[i].pid != getpid() && ioctl(fd, TIOCGPTN, &n) == 0)
			for (int k = 0; k < 4; k++)
				if (kept[k].fd == 0) {
					int s = ioctl(fd, TIOCGPTPEER, O_RDWR | O_NOCTTY | O_CLOEXEC);
					if (s >= 0) {
						kept[k].n = (int)n;
						kept[k].fd = s + 1;
					}
					DEBUG("master fd %d (pty %u) closed in a child: kept slave %d\n", fd, n, s);
					break;
				}
		break;
	}
	return real(fd);
}

// a slave fd as a plain open of its name with flags would have left it
static int as_opened(int s, int flags)
{
	fcntl(s, F_SETFD, (flags & O_CLOEXEC) ? FD_CLOEXEC : 0);
	// a session leader opening a tty without O_NOCTTY gets it as controlling tty
	if (!(flags & O_NOCTTY) && getsid(0) == getpid())
		ioctl(s, TIOCSCTTY, 0);
	return s;
}

static int peer_from(int fd, int n, int flags)
{
	unsigned m;
	if (ioctl(fd, TIOCGPTN, &m) != 0 || (int)m != n)
		return -1;
	// HongMeng refuses the peer unless O_NOCTTY
	int r = ioctl(fd, TIOCGPTPEER, (flags & (O_ACCMODE | O_CLOEXEC | O_NONBLOCK)) | O_NOCTTY);
	DEBUG("peer of fd %d (pty %d): %d (errno %d)\n", fd, n, r, r < 0 ? errno : 0);
	return r < 0 ? r : as_opened(r, flags);
}

// the slave of this process's master with pty number n, opened with flags; -1 if none
static int peer_of(int n, int flags)
{
	for (int k = 0; k < 4; k++)
		if (kept[k].fd > 0 && kept[k].n == n) {
			int s = kept[k].fd - 1;
			kept[k].fd = 0;
			DEBUG("pty %d: the kept slave %d\n", n, s);
			return as_opened(s, flags);
		}
	for (int i = 0; i < 16; i++) {
		int r;
		if (masters[i].fd > 0 && (r = peer_from(masters[i].fd - 1, n, flags)) >= 0)
			return r;
	}
	DIR *d = opendir("/proc/self/fd");
	if (d == NULL)
		return -1;
	int r = -1;
	struct dirent *e;
	while (r < 0 && (e = readdir(d)) != NULL) {
		int fd = atoi(e->d_name);
		if (e->d_name[0] < '0' || e->d_name[0] > '9' || fd == dirfd(d))
			continue;
		char link[64], target[64];
		snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
		ssize_t len = readlink(link, target, sizeof target - 1);
		if (len < 4)
			continue;
		target[len] = '\0';
		if (strcmp(target + len - 4, "ptmx") != 0)
			continue;
		r = peer_from(fd, n, flags);
	}
	closedir(d);
	return r;
}

static int names[256];  // fd -> pty number + 1, for the slaves opened here

static void remember(int slave, int n)
{
	char path[32];
	if (slave >= 0 && slave < (int)(sizeof names / sizeof names[0]))
		names[slave] = n + 1;
	snprintf(path, sizeof path, "/dev/pts/%d", n);
	setenv("OHMARCHY_TTY", path, 1);  // for what is started on it next
}

static int fallback(const char *path, int flags, int r)
{
	int n;
	if (r >= 0 || errno != ENOENT || (n = pts_number(path)) < 0)
		return r;
	DEBUG("%s: ENOENT, looking for its master (flags %#x)\n", path, flags);
	int s = peer_of(n, flags);
	if (s < 0) {
		errno = ENOENT;
		return -1;
	}
	remember(s, n);
	return s;
}


int open(const char *path, int flags, ...)
{
	mode_t mode = 0;
	if (flags & (O_CREAT | O_TMPFILE)) {
		va_list a;
		va_start(a, flags);
		mode = va_arg(a, mode_t);
		va_end(a);
	}
	REAL(open);
	return fallback(path, flags, real(path, flags, mode));
}

int open64(const char *path, int flags, ...)
{
	mode_t mode = 0;
	if (flags & (O_CREAT | O_TMPFILE)) {
		va_list a;
		va_start(a, flags);
		mode = va_arg(a, mode_t);
		va_end(a);
	}
	REAL(open64);
	return fallback(path, flags, real(path, flags, mode));
}

int openat(int dir, const char *path, int flags, ...)
{
	mode_t mode = 0;
	if (flags & (O_CREAT | O_TMPFILE)) {
		va_list a;
		va_start(a, flags);
		mode = va_arg(a, mode_t);
		va_end(a);
	}
	REAL(openat);
	return fallback(path, flags, real(dir, path, flags, mode));
}

int openat64(int dir, const char *path, int flags, ...)
{
	mode_t mode = 0;
	if (flags & (O_CREAT | O_TMPFILE)) {
		va_list a;
		va_start(a, flags);
		mode = va_arg(a, mode_t);
		va_end(a);
	}
	REAL(openat64);
	return fallback(path, flags, real(dir, path, flags, mode));
}

// _FORTIFY_SOURCE builds call these for opens without O_CREAT
int __open_2(const char *path, int flags)
{
	REAL(__open_2);
	return fallback(path, flags, real(path, flags));
}

int __open64_2(const char *path, int flags)
{
	REAL(__open64_2);
	return fallback(path, flags, real(path, flags));
}

// a pty slave without a node: its name from the table above, or for the standard fds
// from OHMARCHY_TTY (the slave the terminal gave this program)
static int slave_name(int fd, char *buf, size_t len)
{
	if (!isatty(fd))
		return -1;
	if (fd >= 0 && fd < (int)(sizeof names / sizeof names[0]) && names[fd] > 0)
		return snprintf(buf, len, "/dev/pts/%d", names[fd] - 1) < (int)len ? 0 : -1;
	const char *t = getenv("OHMARCHY_TTY");
	if (fd <= 2 && t != NULL && pts_number(t) >= 0)
		return snprintf(buf, len, "%s", t) < (int)len ? 0 : -1;
	return -1;
}

int ttyname_r(int fd, char *buf, size_t len)
{
	REAL(ttyname_r);
	int r = real(fd, buf, len);
	if (r == 0 || slave_name(fd, buf, len) != 0)
		return r;
	return 0;
}

char *ttyname(int fd)
{
	static char name[32];
	REAL(ttyname);
	char *r = real(fd);
	if (r != NULL || slave_name(fd, name, sizeof name) != 0)
		return r;
	return name;
}

int openpty(int *master, int *slave, char *name, const struct termios *t, const struct winsize *w)
{
	REAL(openpty);
	int r = real(master, slave, name, t, w);
	unsigned n;
	if (r == 0 && ioctl(*master, TIOCGPTN, &n) == 0)
		remember(*slave, (int)n);
	return r;
}

// glibc's own forkpty calls its openpty directly, past the one above
pid_t forkpty(int *master, char *name, const struct termios *t, const struct winsize *w)
{
	int m, s;
	if (openpty(&m, &s, name, t, w) != 0)
		return -1;
	pid_t p = fork();
	if (p < 0) {
		close(m);
		close(s);
		return -1;
	}
	if (p == 0) {
		close(m);
		if (login_tty(s) != 0)
			_exit(1);
		return 0;
	}
	*master = m;
	close(s);
	return p;
}

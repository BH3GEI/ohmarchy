// An extra layer, not needed: HongMeng keeps abstract names per network namespace
// (2026-10-28), so the sandbox's own network namespace is the boundary once its
// processes join it (README: Network). Written when they were thought shared:
// Preloaded in the sandbox (/etc/ld.so.preload): abstract Unix socket names are not
// per network namespace on HongMeng, so the sandbox's processes could connect to the
// host's (abstract-sockets-ohdev.md). This refuses, with EACCES, connect(), sendto()
// and sendmsg() to an abstract name unless
//   - it starts with "ohmsbx-" (the sandbox's own names, shared with its app), or
//   - it starts with a prefix the sandbox's policy allows (abstract_allow in
//     policy.conf; the launcher writes them, one per line, to /run/ohm-abstract-allow),
//     or
//   - a process in the sandbox bound it (bind() here records each abstract name it
//     binds in /run/ohm-abstract, the sandbox's own tmpfs), as X11 and others do.
// File-path Unix sockets and network sockets are not touched.
// A transition until the sandbox has a MAC domain of its own, not a boundary: it sees
// only calls made through libc's symbols, so statically linked programs and direct
// system calls pass, and root inside can remove it. It keeps ordinary programs from
// reaching the host's abstract sockets.
// OHMARCHY_FENCE_DEBUG=1: say on stderr what is refused.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define REGISTRY "/run/ohm-abstract"
#define ALLOW "/run/ohm-abstract-allow"
#define OWN "ohmsbx-"
#define REAL(name) static __typeof__(name) *real; if (!real) real = dlsym(RTLD_NEXT, #name)

static const size_t off = offsetof(struct sockaddr_un, sun_path);

// the abstract name in addr (without the leading NUL) and its length; 0 if not one
static size_t abstract_name(const struct sockaddr *addr, socklen_t len, const char **name)
{
    const struct sockaddr_un *u = (const struct sockaddr_un *)addr;
    if (addr == NULL || len <= off + 1 || addr->sa_family != AF_UNIX || u->sun_path[0] != '\0')
        return 0;
    *name = u->sun_path + 1;
    return len - off - 1;
}

// the registry file for a name: its bytes in hex (names may hold '/' and NULs)
static int registry_path(const char *name, size_t n, char *buf, size_t size)
{
    if (sizeof REGISTRY + 1 + 2 * n > size)
        return -1;
    char *p = buf + sprintf(buf, "%s/", REGISTRY);
    for (size_t i = 0; i < n; i++)
        p += sprintf(p, "%02x", (unsigned char)name[i]);
    return 0;
}

static int has_prefix(const char *name, size_t n, const char *p, size_t pn)
{
    return pn > 0 && n >= pn && memcmp(name, p, pn) == 0;
}

// a prefix from the policy's list
static int policy_allows(const char *name, size_t n)
{
    FILE *f = fopen(ALLOW, "re");
    if (f == NULL)
        return 0;
    char line[128];
    int ok = 0;
    while (!ok && fgets(line, sizeof line, f) != NULL) {
        line[strcspn(line, "\n")] = '\0';
        ok = has_prefix(name, n, line, strlen(line));
    }
    fclose(f);
    return ok;
}

static int allowed(const char *name, size_t n)
{
    if (has_prefix(name, n, OWN, sizeof OWN - 1) || policy_allows(name, n))
        return 1;
    char path[sizeof REGISTRY + 2 + 2 * 108];
    return registry_path(name, n, path, sizeof path) == 0 && access(path, F_OK) == 0;
}

static int refuse(const char *what, const char *name, size_t n)
{
    const char *d = getenv("OHMARCHY_FENCE_DEBUG");
    if (d != NULL && *d != '\0')
        fprintf(stderr, "ohm-abstract-fence: %s to @%.*s refused\n", what, (int)n, name);
    errno = EACCES;
    return -1;
}

int bind(int fd, const struct sockaddr *addr, socklen_t len)
{
    REAL(bind);
    int r = real(fd, addr, len);
    // record abstract names bound here, autobound ones included (address length of
    // just the family: the kernel picks a name, read back with getsockname)
    if (r != 0 || addr == NULL || addr->sa_family != AF_UNIX)
        return r;
    const char *name;
    size_t n = abstract_name(addr, len, &name);
    struct sockaddr_un got;
    if (n == 0 && len == sizeof(sa_family_t)) {
        socklen_t gl = sizeof got;
        if (getsockname(fd, (struct sockaddr *)&got, &gl) == 0)
            n = abstract_name((struct sockaddr *)&got, gl, &name);
    }
    char path[sizeof REGISTRY + 2 + 2 * 108];
    if (n > 0 && registry_path(name, n, path, sizeof path) == 0) {
        int e = errno;
        int f = open(path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
        if (f >= 0)
            close(f);
        errno = e;
    }
    return r;
}

int connect(int fd, const struct sockaddr *addr, socklen_t len)
{
    REAL(connect);
    const char *name;
    size_t n = abstract_name(addr, len, &name);
    if (n > 0 && !allowed(name, n))
        return refuse("connect", name, n);
    return real(fd, addr, len);
}

ssize_t sendto(int fd, const void *buf, size_t size, int flags, const struct sockaddr *addr, socklen_t len)
{
    REAL(sendto);
    const char *name;
    size_t n = abstract_name(addr, len, &name);
    if (n > 0 && !allowed(name, n))
        return refuse("sendto", name, n);
    return real(fd, buf, size, flags, addr, len);
}

ssize_t sendmsg(int fd, const struct msghdr *m, int flags)
{
    REAL(sendmsg);
    const char *name;
    size_t n = m == NULL ? 0 : abstract_name(m->msg_name, m->msg_namelen, &name);
    if (n > 0 && !allowed(name, n))
        return refuse("sendmsg", name, n);
    return real(fd, m, flags);
}

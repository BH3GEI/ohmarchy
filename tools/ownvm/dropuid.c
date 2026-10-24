/*
 * dropuid UID GID PROG ARGS...: run PROG as UID/GID with no supplementary
 * groups, no capabilities (setuid from root to non-root clears them) and
 * umask 022.
 * For route I's virtiofsd: HongMeng refuses PR_SET_KEEPCAPS, which util-linux
 * setpriv always calls, so setpriv cannot do this there.
 *   $NDK/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$NDK/sysroot -O2 \
 *     -o dropuid dropuid.c
 */
#define _GNU_SOURCE
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc < 4) { fprintf(stderr, "usage: dropuid UID GID PROG ARGS...\n"); return 2; }
	uid_t u = (uid_t)atoi(argv[1]);
	gid_t g = (gid_t)atoi(argv[2]);
	if (setgroups(0, NULL) || setresgid(g, g, g) || setresuid(u, u, u)) { perror("dropuid"); return 1; }
	if (getuid() != u || geteuid() != u || setuid(0) == 0) { fprintf(stderr, "dropuid: still privileged\n"); return 1; }
	prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
	umask(022);  /* HongMeng's root shells start with 007; files in the share would be 0660 */
	execv(argv[3], argv + 3);
	perror("dropuid: exec");
	return 127;
}

// SysV IPC on the HongMeng kernel: message queues, semaphores, shared memory.
// Each part runs in its own child with a 5 s alarm, so a hang is reported as
// HANG instead of blocking the test. Prints one line per part: name, result, detail.
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/msg.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/wait.h>
#include <unistd.h>

struct msg {
    long type;
    char text[32];
};

static int msg_test(void)
{
    int q = msgget(IPC_PRIVATE, IPC_CREAT | 0600);
    if (q < 0) { printf("msgget failed: %s\n", strerror(errno)); return 1; }
    struct msg m = {1, "ping"}, r = {0};
    int rc = 1;
    // same process: send then receive
    if (msgsnd(q, &m, sizeof(m.text), 0) < 0) {
        printf("msgsnd failed: %s\n", strerror(errno));
    } else if (msgrcv(q, &r, sizeof(r.text), 1, 0) < 0) {
        printf("msgrcv failed: %s\n", strerror(errno));
    } else {
        // across processes: the child sends after the parent blocks in msgrcv
        pid_t c = fork();
        if (c == 0) {
            usleep(200000);
            struct msg m2 = {2, "pong"};
            _exit(msgsnd(q, &m2, sizeof(m2.text), 0) < 0);
        }
        rc = msgrcv(q, &r, sizeof(r.text), 2, 0) < 0 || strcmp(r.text, "pong") != 0;
        waitpid(c, NULL, 0);
        if (rc) printf("cross-process msgrcv failed: %s\n", strerror(errno));
    }
    msgctl(q, IPC_RMID, NULL);
    return rc;
}

static int sem_test(void)
{
    int s = semget(IPC_PRIVATE, 1, IPC_CREAT | 0600);
    if (s < 0) { printf("semget failed: %s\n", strerror(errno)); return 1; }
    int rc = 1;
    if (semctl(s, 0, SETVAL, 0) < 0) {
        printf("semctl SETVAL failed: %s\n", strerror(errno));
    } else {
        pid_t c = fork();
        if (c == 0) {
            usleep(200000);
            struct sembuf up = {0, 1, 0};
            _exit(semop(s, &up, 1) < 0);
        }
        struct sembuf down = {0, -1, 0};  // blocks until the child posts
        rc = semop(s, &down, 1) < 0;
        waitpid(c, NULL, 0);
        if (rc) printf("semop failed: %s\n", strerror(errno));
    }
    semctl(s, 0, IPC_RMID);
    return rc;
}

static int shm_test(void)
{
    int id = shmget(IPC_PRIVATE, 4096, IPC_CREAT | 0600);
    if (id < 0) { printf("shmget failed: %s\n", strerror(errno)); return 1; }
    char *p = shmat(id, NULL, 0);
    int rc = 1;
    if (p == (void *)-1) {
        printf("shmat failed: %s\n", strerror(errno));
    } else {
        pid_t c = fork();
        if (c == 0) {
            strcpy(p, "shared");
            _exit(0);
        }
        waitpid(c, NULL, 0);
        rc = strcmp(p, "shared") != 0;
        if (rc) printf("child write not visible\n");
        shmdt(p);
    }
    shmctl(id, IPC_RMID, NULL);
    return rc;
}

static void run(const char *name, int (*fn)(void))
{
    fflush(stdout);
    pid_t c = fork();
    if (c == 0) {
        alarm(5);
        _exit(fn());
    }
    int st;
    waitpid(c, &st, 0);
    if (WIFSIGNALED(st) && WTERMSIG(st) == SIGALRM)
        printf("%s\tHANG\tno progress in 5 s\n", name);
    else if (WIFEXITED(st) && WEXITSTATUS(st) == 0)
        printf("%s\tOK\n", name);
    else
        printf("%s\tFAIL\n", name);
}

int main(void)
{
    run("sysv-msg", msg_test);
    run("sysv-sem", sem_test);
    run("sysv-shm", shm_test);
    return 0;
}

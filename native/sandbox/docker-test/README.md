# docker-test：原生沙箱里的 Docker（测试版）

验证 3：dockerd 能不能锁在一个目录里，直接跑在 HongMeng 内核上。**这里的补丁和开关全部只用于测试，不是正式的隔离方案。** 每个开关默认都是关闭的，只有 start.sh 会把它们打开。需要鸿蒙侧修的内核问题见 [handover.zh-CN.md](../../../docs/handover.zh-CN.md) 3(a) 第 8–14 条和第 16–23 条，以及兼容性表里线程级 CLONE_FS 那一行。

## 现状（2026-10-28，ohdev，HarmonyOS 7.0.0.115，HongMeng 1.11.13.0）

三个里程碑都已跑通：

1. `docker run --rm --cap-drop MKNOD --network none hello-world`：打出 "Hello from Docker!"。
2. `docker run --rm --cap-drop MKNOD --network none alpine:3.22 sh -c ...`：sh 能用。容器有自己的 pid ns（ps 只看到自己）、只有 lo 的 net ns；caps 是 Docker 默认那套去掉 MKNOD，mknod 被拒；/proc/sys 只读；/proc/keys、/proc/asound 等被盖住。
3. 带网络的服务（`NET=pasta`，见下）：`nginx:alpine` 跑在沙箱自己的 net namespace 里，另一个容器能访问到它；容器能上外网（从 TUNA 拉到了文件）；宿主上没有这个监听；宿主上只监听 127.0.0.1 的服务，容器用 127.0.0.1 或宿主的局域网地址都连不上。

每一步前后宿主的 mountinfo 里都没有沙箱的挂载。

dockerd 和 containerd 在独立的 mount ns 里（unshare -m 加 pivot_root），根目录只看得到 `/data/local/ohm-docker-test/root`。不改 iptables（`--iptables=false --bridge=none`）。容器用 `--network none`，或者用 `--network host`；后者共享的是 dockerd 所在的网络：

- `NET=pasta`（推荐）：dockerd 在自己的 net namespace 里，经 pasta（passt.top，原生沙箱的那份编译，`tools/passt`，必须用 `tools/pasta` 这个名字运行）接出去。出站走宿主 socket，不往里转发任何端口，宿主的 127.0.0.1 不可达。
- 不设 NET：dockerd 和 `--network host` 的容器共享宿主网络，能连宿主的 127.0.0.1。只适合最早的功能测试。

已知限制：

- 没有 tty（`-t` 不可用）。
- 没有资源限制，`docker pause`/`docker stats` 用不了。
- 存储只能用 vfs，每层都是整份拷贝。
- nginx 要加 `master_process off`（handover 3(a) 第 23 条）。

## 用法

```sh
# 在 ohdev 上（root）：搭目录（只读地从路线 D 的会话拷 docker 及依赖库；DRY=1 只打印）
sh setup.sh
# 编出来的 containerd、dockerd、runc 替换 root/usr/bin/ 下的同名文件（原来的改名为 *.arch）
NET=pasta sh start.sh
p=$(cat /data/local/ohm-docker-test/dockerd.pid)
nsenter -t $p -m -- /usr/bin/docker -H unix:///run/docker.sock run --rm --cap-drop MKNOD --network none hello-world
sh stop.sh   # 只停 dockerd.pid 和 pasta.pid 里记的进程
```

容器一律要 `--cap-drop MKNOD`，不许用 `--privileged`、`--device`，也不许用 `-v` 挂宿主路径（沙箱里也看不到宿主路径）。

## 文件

| 文件 | 作用 |
|---|---|
| containerd-v2.4.2.diff, moby-docker-v29.9.2.diff, runc-v1.5.2.diff | 补丁，打在对应 tag 上 |
| build.sh | 拉源码、打补丁、交叉编译（Mac：Go、git，runc 还要 aarch64-linux-musl-gcc） |
| setup.sh | 在 ohdev 上建 `/data/local/ohm-docker-test/root`，写 daemon.json。`DRY=1` 时只打印不执行 |
| start.sh / stop.sh | 启动 dockerd（独立 mount ns，`NET=pasta` 时再加独立 net ns 和 pasta）/ 停止 |

本目录不放二进制。

## 开关：关掉或绕过了什么

沙箱的外层边界（独立 mount ns、pivot_root、精简的 /dev，`NET=pasta` 时还有独立 net ns）一处都没放松。下面这些削弱的都是容器这一层，所以这个测试版只能证明功能可行。

| 开关（默认关） | 在哪 | 为什么要 | 关掉或绕过了什么，隔离弱在哪 |
|---|---|---|---|
| `OHM_NO_DEVICES_CGROUP=1` | dockerd | HongMeng 没有 devices cgroup，dockerd 拒绝启动 | 容器能打开哪些设备不再受 cgroup 限制。容器里的 root 只要能 mknod，就能造出宿主的块设备直接读写磁盘。现在靠 `--cap-drop MKNOD`、禁止 `--privileged`/`--device`、沙箱自己的 /dev 兜底 |
| `OHM_CHROOT_REEXEC=1` | dockerd（go-archive） | HongMeng 上一个线程 chroot 会改掉整个进程的根 | 无：解压、打包、apply-layer 改在 re-exec 出来的子进程里 chroot，隔离强度不变 |
| `OHM_NO_CGROUPS=1` | runc | cgroup 层级不按 Linux 的方式暴露，runc 找不到 | 容器完全不进 cgroup：没有内存、CPU、pids 限制，一个容器能耗尽整个沙箱的资源，也没有 pause 和 stats |
| `OHM_KEYRING_BEST_EFFORT=1` | runc | session keyring 返回 EINVAL | 容器之间不分 keyring，一个容器能看到另一个容器存进 keyring 的密钥 |
| `OHM_SKIP_FS=devpts,mqueue` | runc | 这两种文件系统挂不上新实例（ENODEV） | 容器里没有 tty 和 POSIX 消息队列。只是少了功能，不放松隔离（没有把宿主的 /dev/pts 拿进来） |
| `OHM_NO_MOUNT_SOURCE_THREAD=1` | runc | 线程 setns 会把整个 runc 带进容器的 mount ns | 不支持 idmapped 挂载（本来就没有 user ns），不放松隔离 |
| `OHM_KEEPCAPS_BEST_EFFORT=1` | runc | `PR_SET_KEEPCAPS` 一律 EPERM | 指定非 root 用户的容器会比要求的少一些 caps，这个方向更紧，不放松隔离 |
| `"seccomp-profile": "unconfined"` | daemon.json；runc 不带 seccomp 编译 | 内核没有 seccomp | 没有系统调用过滤：容器里的 root 能直接调 keyctl、bpf、perf_event_open 等，内核的攻击面整个暴露给容器，只剩 caps 和沙箱外层约束 |
| `OHM_NO_OPENAT2=1` | runc（pathrs-lite） | 早期绕 openat2 的 EXDEV | 现在用不上，start.sh 不开。打开时改走 O_PATH 解析 |

另外几处补丁只修差异，不削弱，也没有开关：

- uname：release 报成 `6.6.0-hongmeng`，三个程序都打。
- /proc/self 是绝对链接：读链接拿 pid/tid 路径。
- SEQPACKET 探包长：改用真缓冲区 peek。
- cap_last_cap 不存在：改用 `PR_CAPBSET_READ` 探测。
- maskedPaths 的 tmpfs 不认 nr_blocks/nr_inodes：去掉参数，仍以只读 tmpfs 盖住目录。

runc init 启动时环境是空的，所以 runc 父进程会把所有 `OHM_*` 开关显式传给 init。

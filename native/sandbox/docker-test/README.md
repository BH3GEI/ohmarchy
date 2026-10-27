# docker-test：原生沙箱里的 Docker（测试版）

验证 3：dockerd 能不能锁在一个目录里，直接跑在 HongMeng 内核上。**这里的补丁和开关全部只用于测试，不能当正式方案。** 每个开关默认都是关闭的，只有 start.sh 会把它们打开。结论和需要鸿蒙侧修的内核问题见 [handover.zh-CN.md](../../../docs/handover.zh-CN.md) 3(a) 第 8 到 14 条，以及兼容性表里线程级 CLONE_FS 那一行。

## 现状（2026-10-28，ohdev，HarmonyOS 7.0.0.115，HongMeng 1.11.13.0）

- dockerd 和 containerd 在独立的 mount ns 里起来（unshare -m 加 pivot_root），根目录只看得到 `/data/local/ohm-docker-test/root`，宿主 mountinfo 前后一致。不改 iptables（`--iptables=false --bridge=none`），容器只用 host 网络。
- `docker info` 正常，镜像能拉（vfs 驱动；overlay 叠在 hmfs 上报 EINVAL）。
- **卡在 runc 的容器 init**：`error during container init: procReady not received`，hello-world 还没跑起来。原因没有查下去，因为再查就要深挖 runc init 的内部机制，超出了只绕过"不影响外层边界"的东西这条线。要等鸿蒙修了 handover 里那几个内核问题再接着做。

## 文件

| 文件 | 作用 |
|---|---|
| containerd-v2.4.2.diff, moby-docker-v29.9.2.diff, runc-v1.5.2.diff | 补丁，打在对应 tag 上 |
| build.sh | 拉源码、打补丁、交叉编译（Mac：Go、git，runc 还要 aarch64-linux-musl-gcc） |
| setup.sh | 在 ohdev 上建 `/data/local/ohm-docker-test/root`：从路线 D 的会话里只读地拷出 docker 及其依赖库。`DRY=1` 时只打印不执行 |
| start.sh / stop.sh | 启动 dockerd（独立 mount ns）/ 停止（只停 dockerd.pid 里记的那个进程） |

编出来的二进制要替换掉 `root/usr/bin/` 下的 containerd、dockerd、runc（原来的改名为 `*.arch` 保留）。本目录不放二进制。

## 补丁和开关

| 补丁 | 开关 | 作用 | 削弱了什么 |
|---|---|---|---|
| x/sys/unix.Uname（三个程序都打） | 无，检测到 HongMeng 才生效 | release 报成 `6.6.0-hongmeng`（Go 自己发 uname，路线 D 的 libhongmeng-uname.so 管不到） | 无 |
| dockerd daemon.go | `OHM_NO_DEVICES_CGROUP=1` | 没有 devices cgroup 也启动 | 容器的设备访问不再受限，只能靠 `--cap-drop MKNOD`、禁止 `--privileged`/`--device` 和沙箱独立的 /dev 兜底 |
| go-archive chrootarchive | `OHM_CHROOT_REEXEC=1` | 解压、打包、apply-layer 改在 re-exec 出来的子进程里 chroot（HongMeng 上在一个线程里 chroot，会影响整个进程） | 无（隔离强度和原来一样） |
| runc cgroups manager | `OHM_NO_CGROUPS=1` | 容器完全不进 cgroup | 没有资源限制，没有 pause 和 stats |
| runc pathrs-lite procfs | 无，检测到 `/proc/self` 是绝对链接才生效 | 直接用具体的 pid/tid 路径 | 无 |
| runc pathrs-lite openat2 | `OHM_NO_OPENAT2=1`（已不需要，start.sh 不开） | 改用 O_PATH 解析 | 不开就不削弱 |
| runc keyring | `OHM_KEYRING_BEST_EFFORT=1` | session keyring 返回 EINVAL 时当成不支持（runc 对 ENOSYS 本来就这样处理） | 容器之间的 keyring 不隔离 |
| runc 构建 | 无 | 静态编译，不带 seccomp | 容器没有 seccomp 过滤 |

沙箱的外层边界（独立 mount ns、pivot_root、精简的 /dev）没有放松。削弱的都是容器这一层，所以这个测试版只能证明功能可行。

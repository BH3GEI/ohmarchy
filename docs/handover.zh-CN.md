# ohmarchy 交接文档

截至 2026-10-27（北京时间）。仓库：github.com/BH3GEI/ohmarchy，分支 main。文中提交号均在 main 上，路径相对仓库根目录。本文只记录事实，细节见各处链接的文档。时间未注明时区的均为北京时间。

## 1. 总览

### 1.1 目标

在鸿蒙（HarmonyOS）电脑上运行 Omarchy（Arch Linux ARM 加 Hyprland 桌面）。要求有三点：

- 能现场演示；
- 有对外公开、不需要 root 的安装方式；
- 全部步骤能从仓库文档复现。

### 1.2 能演示什么

演示约 10 分钟，按以下顺序，因为同一时刻只能有一台虚拟机在跑（README.zh-CN.md "推荐的演示"；操作手册 docs/demo-operator.zh-CN.md）：

1. **D 原生桌面**，约 80 秒。打开鸿蒙 app "Omarchy (native)"，桌面以 120 Hz 显示：Hyprland、Omarchy 顶栏、终端 fastfetch、切工作区、Firefox、文件管理器。
2. **I 在原生终端里用 Docker**。第一次执行 `docker` 时后台虚拟机自动启动，约 27 秒出结果，用完约 40 秒后自动关机（5d505a3）。
3. **C 鸿融**，约 3–4 分钟。Omarchy 盘作为鸿融自己的虚拟机开机进桌面，鸿融卡片显示"运行中"，用鸿融的"关机"按钮关机。
4. **B OSEasy**，约 4 分钟。从"没有虚拟机"开始：建虚拟机，用安装 ISO 写盘，首次开机设密码，进桌面。

### 1.3 测试机

| 名称 | 硬件 | 系统 | 现状 |
|---|---|---|---|
| ohdev | HUAWEI MateBook 14 HM740（MNT-W72C），麒麟 X90，20 线程，32 GB，马良 916 GPU，2880x1920，最高 120 Hz | HarmonyOS 7.0.0.115（OpenHarmony-7.0.0.120），HongMeng 内核 1.11.13.0 | 唯一在用的测试机和演示机 |
| ohdev2 | MOR-W52（MOR-M1），麒麟 9020，研发版 | HarmonyOS 7.0.0.32 | 2026-10-27 出事故，修复后已拔下，ssh 已删除，不再使用（第 5.3 节） |

### 1.4 各路线现状

| 路线 | 内容 | 现状 | 要 root | 能否演示 |
|---|---|---|---|---|
| B OSEasy | 整个 Omarchy 系统跑在 OSEasy 虚拟机 app（com.oseasy1.ohvm 3.1.1.7）里，内核 7.2.12 加打补丁的 vmwgfx，用安装 ISO 写盘 | 能用。公开版是 GitHub release 草稿（未公开）；内核 1.2 的新 ISO 正在回归 | 不要 | 能 |
| C 鸿融 | 整个 Omarchy 系统作为华为鸿融（com.huawei.medivh 1.1.1.103）的虚拟机运行，virgl GPU | 能用。内核 1.2 的盘 10-27 在 ohdev 上验证通过 | 导入不要；换盘要 | 能 |
| D 原生 | Arch 加 Omarchy 直接跑在 HongMeng 内核上，桌面显示在鸿蒙 app 里，120 Hz，马良 GPU | 能用，已验收 | 要 | 能 |
| 原生沙箱（新方案） | 原生内核；Linux 锁在自己的目录和网络里，像 app 一样开、关、重置；有数的 root 小助手；Docker 在里面跑；隐私数据由 app 申请 | v1 能用（10-28 ohdev）：app "Omarchy (sandbox)"、独立 mount/pid/ipc/uts/net 命名空间、一键安装和卸载。只算测试机级别的隔离：抽象 socket 与主机共享、SELinux 域还是 `su`、Docker 未接入 | 小助手要 root | 能（可选第 4 段，未完整彩排） |
| I 自建后台虚拟机 | root 直接在 /dev/hmv 上起 StratoVirt，无界面，给 D 提供 Docker | 能用 | 要 | 能，与 D 一起 |
| J app 沙箱内原生 | Linux 程序编成 .so 签进 HAP，fork 加 dlopen 运行 | busybox 已在真机跑通；Hyprland 已编好，真机试了 4 轮，尚未出第一帧 | 不要 | 不能 |
| E 裸机／U 盘 | 不要鸿蒙，Linux 直接在硬件上启动 | 全内存 U 盘已做好，尚未在机器上启动成功 | — | 不能 |
| A、F、G、H、K、L | 其他探索 | 已有结论或暂停（README.zh-CN.md "三、其它探索"） | — | 不能 |

### 1.5 各路线说明

**B OSEasy**（docs/oseasy-whole-os.md、docs/oseasy-install.md）

- **原理。** OSEasy 把虚拟机交给系统服务 vm_manager，在 HMV（华为自研 hypervisor）上启动 StratoVirt。显卡是 svga-pci（VMware SVGA II，寄存器走 MMIO）。我们的 vmwgfx-oseasy 驱动加了这些支持：
  - MMIO 寄存器、screen object 显示、120 Hz 定时 vblank；
  - 1 ms 轮询 fence（060fc92）；
  - GEM_CLOSE 修复（90cb7d2）；
  - 命令缓冲头延迟 5 ms 回收（a145d58）；
  - 翻页看门狗（61e5998）；
  - 初始化竞争修复（36cfb9d）。
- **GPU 长测。** 4 小时 24 分钟无故障。
- **最近一次完整验证。** 2026-10-27，ohdev，按新用户首次流程：约 91 秒出现设密码界面，进桌面后壁纸和顶栏正常，客户机报 2100x1511@120（bff38a1、39f1bb9）。壁纸和顶栏原先是黑的，修复见 b129b02。
- **发布。**
  - 草稿：GitHub release `b-20261027`，资产 omarchy-oseasy-b-20261027.iso，2006917120 字节，已上传，未公开，公开要等 Yao 决定。发布脚本在 tools/release/。
  - 新 ISO：2032457728 字节，换成内核 7.2.12-1.2，正在 ohdev 上回归，通过后加入草稿。
- **已知问题。**
  - 生命周期：关机后 OSEasy 只给"再次安装"，点了会清空磁盘，所以系统不能保留状态；外层一直显示"正在安装 Windows 11…"。
  - 窗口：固定大小的浮动窗口，不能全屏。
  - 刷新率：屏幕上 60 Hz，因为 OSEasy 从不向系统请求 120 Hz。
  - 共享文件夹：Linux 下读不了（virtiofsd 报 ENODEV）。
  - 声音：没有，ivshmem-scream 没有 Linux 驱动。
  - 误报：会弹出"install.wim 损坏"，必须点"确定"，点"取消"会删掉虚拟机。
  - 授权：OSEasy 每台设备只能试用一次。
- **磁盘持久化。** 10-25 曾定为不实现兼容的 Linux guest agent（f10fa48，docs/oseasy-whole-os.md）。10-27 Yao 要求攻关磁盘持久化，方针改为实现最小的兼容 agent。协议已逆向：virtio-serial 加 protobuf RPC，握手为 Handshake{connectionMode, clientName, authString}，调用为 Call{callID, methodID, parameters, async}（1b616c1，docs/oseasy-agent-protocol.md）。docs/oseasy-whole-os.md 中的旧方针待更新。

**C 鸿融**（docs/hongrong-whole-os.md、docs/internal/hongrong-team-brief.md）

- **原理。** 鸿融也在 HMV 上跑 StratoVirt，给 Linux 虚拟机的显卡是 vhost-user-gpu（virgl），宿主经 zink 跑在马良 GPU 上。
- **盘的来源。** 用的是 B 的同一份公开镜像，由 hongrong/pure/make-qcow2.sh 转成 qcow2。有两种方式放进鸿融：
  - "本地文件"导入，不需要 root；
  - 用 root 换进已有虚拟机（hrswap.sh），演示用这种（docs/demo-operator.zh-CN.md 第 2 段，e596929）。
- **首次开机。** 桌面上弹出设密码终端，设完后从鸿融光盘装增强服务（vm-agent），鸿融卡片显示"运行中"，"关机"可用（e0e0b7b、9306e34、cf91ba0）。
- **显示。** 虚拟机内 2160x1440@119.98，EDID 由 initramfs 里的 modprobe 钩子交给 virtio-gpu（0368f84）。
- **2026-10-27 验证。** ohdev，内核 7.2.12-1.2，盘 omarchy-b-v3-os1.qcow2：
  - 开机 40 秒进桌面；
  - `extended_features`=N，所有 virtio 设备由 virtio-pci 接管；
  - 119.98 Hz；增强服务"运行中"；"关机"约 20 秒完成。
  - sudo 和锁屏解锁：2026-10-28 已验证，测试方知道密码。
- **已知问题。**
  - 全屏呈现：2026-10-25 测得鸿融全屏是 60 帧/秒，新镜像未复测。
  - GPU：只有 OpenGL，没有 Vulkan，没有 resource_blob。
  - 鸿融何时给 virgl、何时给 2D 显卡，规律未查清。
  - 一次只能放一台虚拟机。
  - 应用市场会自动更新鸿融，需关闭自动更新。
  - **HarmonyOS 7.0.0.32 上鸿融不能用**（第 3(b) 节）。
- **ohdev 上的现状。**
  - 鸿融里是 v3 演示盘，已关机；密码 2026-10-28 已验证，测试方知道密码。
  - Yao 的主盘保留为同目录下的 vm.qcow2.imported（36412063744 字节），未改动。
  - 另备一张未开过机的 v3b 盘：/data/local/vmtest/omarchy-b-v3b-os1.qcow2。

**D 原生**（docs/native-chroot.md、docs/native-desktop.md、docs/acceptance.md）

- **原理。**
  - Arch Linux ARM 装在 64 GB 稀疏 ext4 镜像里（/data/local/archtest/arch.img）。root 用 `unshare -m -p` 加 chroot 进入（native/arch.sh），桌面用户 builder，uid 60000。
  - Hyprland 0.56.2 和 aquamarine 0.15.1 打了补丁，画面经 headless 后端送进鸿蒙 app 的 XComponent 窗口。
  - GPU 渲染在 app 进程里，用系统自带的 libvirglrenderer（zink 加马良 GPU）。
  - 声音走 OHAudio；输入用 fcitx5 拼音。
- **验收数字（2026-10-24/25，ohdev）。**
  - 切工作区 119 帧；es2gears 屏幕上 117–120 帧。
  - 冷启动约 8 秒。
  - 78 个 app 中 74 个 3 秒内打开，P95 1.13 秒。
  - 24 小时长测通过。
  - 开机自启经真实重启验证（305f15b）；关掉 app 再打开约 6 秒桌面回来（6c3b296）。
- **键盘。** Alt+Shift 代替 Super 键（ad71991），已编译签名，未装机，未用实体键盘验证。
- **已知问题。**
  - 没有 systemd（NetworkManager、蓝牙、打印、电源菜单不可用）。
  - 没有摄像头、背光调节、U 盘。
  - Chromium 只能加 `--no-sandbox`（内核不共享 CLONE_FS），默认浏览器改为 Firefox（caee075、6448809）。
  - broker 和会话初始化只能留在宽松的 SELinux `su` 域。
  - 松开 Windows 键会弹出鸿蒙开始菜单。
- **系统库依赖。** app 打包时从设备上拷贝系统的 libvirglrenderer。ohdev2（麒麟 9020，7.0.0.32）上那份库版本不同，上屏时崩溃；对应的修改未提交。

**原生沙箱（新方案）**（native/sandbox/README.md、native/sandbox/abstract-sockets-ohdev.md）

- **方向（已定）。** 原生内核；Linux 锁在自己的目录里；默认全禁，只放行允许清单；一个调用有数、受控的 root 小助手；Docker 在里面跑；访问隐私数据要通过 app 申请。设计文档 docs/native-sandbox.md 尚未提交。
- **v1 已做到（2026-10-28，ohdev，和 D 的演示版并排跑，D 全程未受影响）。**
  - 和 D 完全分开：app com.ohmarchy.sandbox（"Omarchy (sandbox)"，粉色图标）、目录 /data/local/ohm-sandbox、自己的 64 GB 镜像和 loop 设备、socket 前缀 `ohmsbx`。
  - 关进去的方式：`unshare -m -p -i -u -n` 加 pivot_root，镜像就是整个文件系统，主机的 /storage、/system 在里面不存在；/dev 是只放几个节点的 tmpfs；/proc/sys、/sys 只读；能力边界集去掉 mknod、sys_admin、模块、raw I/O、MAC、net_admin 等（CapBnd b18cecff；HongMeng 拒绝 PR_SET_KEEPCAPS，用自写的 ohm-capdrop）。
  - 网络：独立 net namespace，主机上的 pasta（passt.top，打了 HongMeng 补丁）把沙箱的 TCP/UDP/ICMP 经主机 socket 发出去。不往里转发端口，不动主机的路由和防火墙。主机的 127.0.0.1 已经连不上（10-28 上屏实测）；pacman、https 正常。
  - 像 app 一样：双击启动 Linux 和桌面（约 16–19 秒），关掉 app 就停；"Reset Linux"（图标菜单）先确认，再恢复到安装时的快照（约 33 秒）；全屏，Ctrl+Alt+Esc 最小化。键盘、鼠标、声音、马良 GPU 跟 D 一样；终端靠 pty 垫片（HongMeng 没有 devpts）。
  - root 小助手 ohm-sandboxd：只接受这个 app 的 uid（SO_PEERCRED），只认 start、stop、reset、status 四个固定命令，客户端发来的任何内容都进不了命令行。
  - 安装和卸载：native/sandbox/install.sh、uninstall.sh，从电脑上一条命令完成，前后核对 D 和系统没变。/data 以外只写一个文件 /system/etc/init/ohm-sandboxd.cfg（开机起小助手），10-28 经批准写入并回读一致。
- **已知缺口（在这些解决之前，只算测试机级别的隔离，不能当作对外的安全承诺）。**
  - 抽象 Unix socket 与主机共享：HongMeng 不按 net namespace 隔离抽象名字，沙箱仍能连到主机上所有在监听的抽象 socket，其中有 wpa_supplicant 的控制接口和 TEE 守护进程 teecd（清单见 abstract-sockets-ohdev.md，未做任何实测）。诉求见第 3(a) 节第 15 条。
  - SELinux 域还是宽松的 `su`：ohdev 不接受运行时加载策略，自己的域要靠鸿蒙（第 3(b) 节第 1 条）。
  - Docker 还没接进沙箱（I 线在做；HongMeng 缺的东西见第 3(a) 节第 8–14 条）。
  - 开机自起小助手：cfg 已写入，但 init 只在开机时读，要等下次真重启才能验证；在那之前机器重启后要手动 `ohm-sandbox serve`。
  - 换网络后要 `ohm-sandbox net` 重连；只有 IPv4。
- 允许清单（10-27 只读调查，H 线）：ohdev 是 developer 版（const.debuggable=1），SELinux 全局 enforcing，策略为 CIL，源码和 secilc、checkpolicy、chcon 等工具在机器上，/sys/fs/selinux/load 对 root 可写。可行做法是运行时加载一个只新增类型和规则的模块（新域只能读写自己的目录），不改 /system，重启即恢复。hmmac 是第二层 MAC，没有可操作的接口，但不妨碍更严的 SELinux 新域。运行时加载是否被接受已做初步实测（2026-10-27，H 线）：把导出的现有策略（/sys/fs/selinux/policy，3299594 字节）原样写回 /sys/fs/selinux/load 两次均被拒——第一次 rc=1，第二次 errno=EINVAL，写入 0 字节、内核策略未变、系统无损（Enforcing、策略大小不变，bm/hidumper/ssh/hdc 全部正常，死人开关每次都在 300 秒内手动撤销、从未触发）。当时 su 为 permissive 且具备 CAP_MAC_ADMIN，失败时无任何 SELinux/hmmac 拒绝记录。故**原样回灌不通**。随后的 step-2 实测（2026-10-27）已定论：开机实际加载的是 /vendor/etc/selinux/prebuild_sepolicy/developer_policy（3299594 字节，与 live 一致；policy.31 是 3269901 字节的非 developer 版，用它会丢 developer 规则，不用）。把**这份开机原版**原样写回 /sys/fs/selinux/load 仍是 EINVAL、0 字节——连内核开机时自己接受的同一份二进制都回灌不了，排除了格式问题，**证明鸿蒙内核在开机后硬禁止再加载任何策略**。因此运行时加载我们自己的 SELinux 域在本机不可行（step-2b 不做），且运行时没有任何回灌恢复、只能重启（两次 step-2 测试均零改动、系统无损、无需恢复）。后续结论（10-28）：ohdev 的内核不接受运行时加载策略，v1 改用命名空间、pivot_root 和去能力，小助手留在 `su` 域（见上面"已知缺口"）。
- **Docker（10-27，I 线）。**此前 I 线的 Docker 跑在 StratoVirt 虚拟机里，dockerd 直接跑在 HongMeng 内核上是第一次尝试。已查实有 overlayfs 和 mnt、pid、net、ipc、uts 命名空间，没有 user 和 cgroup 命名空间，只能 rootful；cgroup 只有一套层级，文件名为 v2 风格，mountinfo 不写子系统名，runc 可能识别不了。v1 先不接 cgroup、不改 iptables、容器用 host 网络（10-27 时沙箱能连宿主 127.0.0.1；10-28 沙箱有了自己的 net namespace，这个口子已补上，Docker 接入时网络要重新设计）。
- 本文第 3(b) 节里与小助手、MAC 规则、允许清单相关的请求，以该文档定稿为准。

**I 自建后台虚拟机**（docs/vm-own.md）

- **原理。** tools/ownvm/ohmarchy-vm 以 root 直接在 /dev/hmv 上启动系统自带的 StratoVirt：默认 6 个 vCPU、12 GiB（48eee76），virtio 磁盘、网卡、vsock、balloon，无界面；磁盘用 C 的开发者镜像。
- **网络。** 宿主的策略路由会把发往虚拟机的包从 Wi-Fi 送出，脚本在开关机时自己加删两条规则（5b36f9d）。
- **给 D 用的 Docker。**
  - D 的 docker 通过 root 守护进程 ohmarchy-docker-gate 连接，只接受 uid 60000（caecc94、df0f0da）。
  - 第一次连接时虚拟机自动启动，空闲 30 秒后自动关闭（5687442）；关机卡死已修（063390d、2d68b77）。
  - 鸿融或 OSEasy 占着 HMV 时，docker 报错会写明是哪个 app，并发一条鸿蒙通知（4303a96）。
  - 个人目录经上游 virtiofsd 1.14.0 共享，以 uid 60000、无特权运行，新文件 0644（2235eaf）。
  - x86 镜像经 qemu-user 可以运行，较慢。
- **数字。**
  - 启动后 5–10 秒可用；冷启动跑 hello-world 17–21 秒。
  - 空闲时宿主只占约 1.2 GiB；balloon 能把内存还给宿主（a2b6d0f）。
  - 演示脚本 tests/demo/i.sh 91 秒全部通过（f62265a）。
- **已知问题。**
  - 不上屏：跨进程拿不到 app 的窗口，vtest 方案在资源编号或共享内存上受阻，2026-10-24 决定保持无界面。
  - 从宿主经 `ohmarchy-vm ssh` 跑 docker 时输出可能挂住，从 D 的终端用不会。
  - 开机自启服务有意不装。
- **关于 7.0.0.32。** I 的磁盘内核是 7.2.12-1.1，在 7.0.0.32 上会遇到 feature select 问题，要先换成 1.2。这一点是推断，未实测。

**J app 沙箱内原生**（docs/no-root-routes.md）

- **沙箱探针结论。** 不用 root 的 app 只能运行签进 HAP 的代码，而且只能用 dlopen：
  - 没有可写可执行内存，XPM 报 "jit set mem violated"；
  - 不能 exec 沙箱里或 HAP 里的程序；
  - 可以 fork。
- **busybox 原型。** 2026-10-25 在真机跑通（cf02298、5e53376），已集成进 D 的显示 app，默认关闭（9d4000c、9a6539d）。
- **Hyprland 全家按鸿蒙 musl 重编。** Hyprland 0.56.2 已链接成 libhyprland.so（845dc1b、8d30450），HAP 库包 17 个库、69.7 MB。
  - 10-26 真机试了 4 轮，前几轮的阻塞已逐一修掉：dma_heap 分配（86d2ece、3c0a48a）、socket 路径过长（4d1d5ee）。
  - 第 4 轮拿到 GL 上下文，但 vtest 协议版本不够。已按 v3 重编（4d3bafb），尚未上机。
- **优先级。** 自 10-26 起降为后台研究。README 中"还没上真机"的说法已过时。

**E 裸机／U 盘**（docs/route-e.md：8c58a22、4e94fd7、93f6784、efb270e）

- **ohdev 的启动状态。** 固件是 UEFI；HVB 处于 unlocked/orange，允许自定义镜像。固件传的是设备树，不是 ACPI。
- **驱动。** 设备树分析显示，主线 Linux 在麒麟 X90 上几乎只能驱动 arch timer 和 UEFI GOP 帧缓冲；USB、PCIe/NVMe、I2C 输入、串口都没有主线驱动。
- **HongMeng 的 Linux 驱动不能复用。** 它们是微内核上的用户态驱动（libdh-linux 6.6.127），麒麟 X90 的驱动源码也未公开。
- **全内存 U 盘已做好**（tools/routee/build-ram-usb.sh）：GRUB 加通用 7.3 内核，把 B 的整个根目录作为 initrd 读进内存，开机后在帧缓冲上打印驱动报告，再用软件渲染起 Hyprland。
- **尚未启动成功。** 2026-10-27 的尝试中，开机按 F12 没有反应。

**其他路线**（README.zh-CN.md）

- A：鸿蒙自带的 Linux 引擎，只能跑终端工具。
- F：DevEco 模拟器里的 Aetherium，纯软件，很慢。
- G：铠大师，每台虚拟机都只是一次"安装会话"，已结束（docs/vm-kaidashi.md）。
- H：真机上的 Aetherium，拿不到可执行内存，已结束（docs/device-aetherium.md，81cb74d、5a6b00a）。
- K：QEMU 解释模式，只是想法。
- L：ArkWeb 里的 v86，2026-10-25 暂停。

## 待决定事项

以下事项需要 Yao 决定，文中相关各节只写事实：

1. B 是否公开发布，以及时间（第 2 节第 5 条）。
2. 第 3 节各项诉求中，哪些、以什么形式、向哪个团队提出。
3. 上游提交（ALARM、LKML）是否发出（第 2 节第 13 条）。
4. 原生沙箱方案的优先级，以及在 ohdev 上做运行时策略加载测试的范围（1.5 节）。

## 2. 我们还要做什么

按优先级排列。工作量为估计值；"—"表示目前无法估计。

| # | 事项 | 完成标准 | 工作量 | 负责线 |
|---|---|---|---|---|
| 1 | B：内核 1.2 新 ISO 在 ohdev 上回归 | 进桌面，壁纸、顶栏、120 Hz 正常，`extended_features`=N，有截图；随后加入 release 草稿，旧 ISO 保留 | 0.5 小时 | B |
| 2 | 原生沙箱设计文档 docs/native-sandbox.md | 边界清单逐条写明判定依据和测试位置；附给华为的一页说明和小助手接口；已提交 | — | D |
| 3 | 演示准备 | 按 docs/demo-operator.zh-CN.md "准备"一节逐项打勾，包括：v3 盘的密码 2026-10-28 已验证，测试方知道密码；Alt+Shift 代替 Super 用实体键盘走一遍 | 1–2 小时 | C、D |
| 4 | C：补测 sudo 和锁屏解锁 | 2026-10-28 已验证（v3 盘，测试方知道密码），sudo 和锁屏解锁都通过，有截图 | 已完成 | C |
| 5 | B 公开发布 | 补齐还缺的 14 个 GPL/LGPL 包的源码，重新生成 package-sources，替换草稿的附件和说明（说明里写着"补齐后才公开"）；Yao 本人检查后公开 | 2 小时（不含决策） | I（release）、B |
| 6 | 文档对齐 | 更新过时内容：docs/oseasy-whole-os.md 里"不做 guest agent"的旧方针、README 里的 ISO 大小和刷新率说法、hongrong-whole-os.md 的 Known limits（增强服务、内核 1.2）、README 的 J 行；修正 oseasy-vendor-request.md 的通道描述（virtio-serial 加 protobuf）和重复的节号 | 2–3 小时 | B、C、J |
| 7 | 遗留脚本进仓库 | hrswap.sh、按块并行压缩的 zchunks.sh、ohdev 上的运行脚本纳入仓库 | 1 小时 | C |
| 8 | 构建能力不再只依赖 ohdev | 在另一台机器（或刷机后的 ohdev）上从仓库完整重编内核包并重建镜像。内核完整编译约 25 分钟 | 0.5–1 天 | C |
| 9 | 现场检查 | 用耳朵听声音；电源键熄屏亮屏 20 次；切换 Wi-Fi；电池功耗 5 种状态各 30 分钟；实体触控板三指手势（README "需要有人在现场做的事"） | 半天，需要有人在机器前 | D |
| 10 | B 磁盘持久化 | 实现最小的兼容 Linux agent，关机后 OSEasy 显示"开机"并能进入已装系统 | — | B |
| 11 | J 第 5 轮真机运行 | 显示 app 窗口里出现 Hyprland 第一帧 | — | J |
| 12 | E 在机器上启动 U 盘 | 帧缓冲上出现驱动报告，可以拍照 | 取决于固件启动键 | E |
| 13 | 上游提交 | ALARM PR 和 LKML 补丁（hongrong/kernel/upstream/，059009b）发出。需要 Yao 批准，DCO 必须是 Yao 本人的 | 每项约 1 小时，另加评审往返 | C |

## 3. 需要鸿蒙侧做什么

每条写明：为什么需要、影响哪条路线、不给的话我们的退路。

### 3(a) 希望合入鸿蒙的修复

1. **HMV：未分配的 AArch64 ID 寄存器按架构读出 0。**
   - 为什么：Linux 6.9 起启动时会读 ID_AA64PFR2_EL1 等寄存器，HMV 把 vCPU 卡死，上游新内核在鸿融、OSEasy 里都启动不了。
   - 复现：docs/hmv-idreg-report.md（中文问题报告，可直接转交，尚未发出）。
   - 影响：B、C、I。
   - 退路：内核补丁 0002，加启动参数 `arm64.hmv_idreg_quirk`，每次升级内核都要带上。
2. **旧版 StratoVirt（HarmonyOS 7.0.0.32）的 virtio feature select 问题。**
   - 为什么：Linux 7.2 读写 128 位特征时会用到 feature select 2，旧版 StratoVirt 报错，HMV 随即让 vCPU 致命出错，虚拟机在启动 0.76 秒时挂死。7.0.0.115 没有此问题。
   - 请求：virtio-pci common config 遇到不认识的 feature select 时忽略或返回 0；HMV 不因设备 MMIO 写失败就杀掉 vCPU。
   - 复现：在 7.0.0.32 的 OSEasy 里用 7.2.12-1.1 内核启动，vmlog 依次出现 "Invalid features select 0x2"、"Failed to mmio write addr 80020c00c"、"VCPUHmv 3 emulate error"（docs/vm-api.md，176b99b、7b6eb92）。
   - 影响：老系统上的 B 和 C。
   - 退路：内核补丁 0003（139aa77），默认只用 64 位特征。
3. **GIC ITS 报告 32 位事件号。**
   - 为什么：Linux 修复 5a9d62555e71 之前的内核，所有 MSI 中断申请都失败，vsock 不通，增强服务连不上。鸿融认证的 UOS、麒麟内核也受影响（docs/internal/hongrong-team-brief.md 2.1）。
   - 复现：装 5a9d62555e71 之前的内核，所有 MSI 中断申请失败、vsock 不通、增强服务连不上（详见 hongrong-team-brief.md 2.1）。
   - 影响：C，以及用户自带的内核。
   - 退路：内核补丁 0001。
4. **HongMeng 内核的兼容性问题**（复现见 docs/native-chroot.md 的 quirks 表）。

   | 问题 | 现象 | 退路 |
   |---|---|---|
   | `clone(CLONE_FS)` 不共享根目录和当前目录 | Chromium 的沙箱关不住自己 | 默认浏览器改为 Firefox |
   | `unshare(CLONE_FS\|CLONE_NEWNS)` 后 chroot，同一进程所有线程的根目录都跟着变（单个线程本应各自独立） | dockerd 解压镜像层时整个进程被关进层目录，层注册失败，DNS 退回 `[::1]:53`；复现：tools/docker-sandbox/chrootprobe | 测试版 dockerd 用 `OHM_CHROOT_REEXEC=1`，在子进程里 chroot |
   | `splice` | 从已读空的管道读，返回 EPIPE 而不是 0 | preload 垫片 |
   | `statx(fd, "", AT_EMPTY_PATH)` | 返回 EFAULT | preload 垫片 |
   | `msgrcv` | 阻塞后不被 `msgsnd` 唤醒，fakeroot 卡住 | preload 垫片，改为轮询 |
   | `/proc/PID/cmdline` | 进程恰在退出时读，可能无限自旋 | 一律加超时 |
   | toybox `mount -o loop` | 报 EFAULT；loop 设备只有 loop0 有节点；devpts 没有 ptmx | 手工 losetup、mknod |
   | `clone(CLONE_FILES)` 不共享文件表 | 子进程打开的 fd 父进程看不到，pasta 进不了沙箱的 netns（netlink EBADF） | pasta 补丁：改用线程做 setns（线程共享文件表，setns 只影响本线程） |
   | `close_range(CLOSE_RANGE_UNSHARE)`、tmpfs 的 `nr_inodes`/`nr_blocks` | 返回 EOPNOTSUPP、EINVAL | pasta 补丁：去掉这两个参数重试 |

   - 影响：D 和原生沙箱。
5. **vm_manager 启动 virtiofsd 时带 `--passthrough-fs`，或公开 share 注册协议。**
   - 为什么：OSEasy 的共享文件夹在 Linux 客户机里读不了（客户机报 `virtio-fs: response too short (0)`，宿主报 ENODEV）。
   - 复现：在 OSEasy 的 Linux 客户机里挂载共享盘，客户机 dmesg 报 `virtio-fs: response too short (0)`，宿主 virtiofsd 报 ENODEV。
   - 影响：B。
   - 退路：没有可持久化的存储，只能靠虚拟机内重启保留数据。
6. **系统自带的 virtiofsd 1.13.0 权限问题。**
   - 现象：新建文件强制为 0660、目录为 0771，并且忽略 chmod。
   - 复现：tools/ownvm/umask-test.sh。
   - 影响：I（以及鸿融的共享文件夹）。
   - 退路：用上游 virtiofsd 1.14.0。
7. **SDK 头文件冲突。** OHOS 的 `linux/socket.h` 无条件定义 `sockaddr_storage`，和 musl 冲突；`dma-buf.h` 缺 sync-file ioctl。
   - 为什么：按 OHOS musl 交叉编译 J 的 Hyprland 全家时，uapi 的 `linux/socket.h` 与 musl 的 `sys/socket.h` 重定义 `sockaddr_storage`，且 `dma-buf.h` 缺 `DMA_BUF_IOCTL_SYNC`，编译失败。
   - 复现：用 OHOS NDK sysroot 编 glib/aquamarine，报 `sockaddr_storage` 重定义、`DMA_BUF_IOCTL_SYNC` 未定义。
   - 影响：J。
   - 退路：device/userspace/uapi-fix 和 shim/。
8. **`uname` 的 release 字段改报 Linux 格式的版本号**，例如 `6.6.0-hongmeng`（sysname 仍可报 HarmonyOS）。
   - 为什么：HongMeng 报的是 `HongMeng Kernel 1.11.13.0`，Linux 程序普遍按 `主版本.次版本` 解析，解析不了就出错。C 程序可以靠路线 D 预加载的 libhongmeng-uname.so 改写，Go 程序却自己发系统调用，预加载对它们无效；personality(UNAME26) 在 HongMeng 上也不生效。containerd 2.4.2 一启动就 panic（`failed to check kernel version: failed to parse kernel version "HongMeng Kernel 1.11.13.0": expected integer`），dockerd 也报 fsverity 检查失败。
   - 复现：在 ohdev 的 root shell 里运行任意 Go 程序调用 `syscall.Uname`，看 Release 字段；或者在路线 D 的会话里直接运行 `/usr/bin/containerd`。
   - 影响：原生沙箱（Docker），以及所有用 Go 写、检查内核版本的工具。
   - 退路：给 vendored 的 `golang.org/x/sys/unix.Uname` 打补丁（把 release 改成 6.6.0-hongmeng），然后重新编译 containerd 和 dockerd。每次 Docker 升级都要重做。
9. **提供 devices cgroup，或者 cgroup2 加 BPF 设备过滤。**
   - 为什么：Docker 靠 devices cgroup 限制 root 容器能打开哪些设备，没有它，容器里可以 mknod 出宿主的块设备，进而直接读写整块磁盘。HongMeng 只有一套 cgroup 层级（同一个设备号 0:10，挂在 /dev/memcg、/dev/pids、/dev/cpuset 等处），文件名是 v2 风格，mountinfo 里也没有写子系统名，而且没有 devices 子系统。dockerd 因此拒绝启动，报 `Devices cgroup isn't mounted`。
   - 复现：在 ohdev 上 `cat /proc/self/cgroup`（freezer、pids、cpuset、memory、cpu、load、iolimit、workingset、dummy，没有 devices），以及 `grep cgroup /proc/self/mountinfo`。
   - 影响：原生沙箱（Docker）。
   - 退路：测试版 dockerd 里加一个默认关闭的开关 `OHM_NO_DEVICES_CGROUP=1` 跳过检查，同时所有容器都 `--cap-drop MKNOD`，禁止 `--privileged` 和 `--device`，沙箱的 /dev 用独立 tmpfs。这些只够做功能测试，不能当正式方案。正式方案在等鸿蒙提供 devices cgroup，或者由 MAC 禁止容器域打开块设备和字符设备（并入新域设计）。
10. **cgroup 层级按 Linux 的方式暴露出来。**
   - 为什么：runc 在 mountinfo 里找不到 cgroup 挂载，就拒绝创建容器（`no cgroup mount found in mountinfo`）。即使找到了，HongMeng 的单一层级里也没有 devices，memory、cpu 的文件名又是 v2 风格，所以容器既限不了资源，也拦不住设备访问。
   - 复现：同第 9 条（`/proc/self/cgroup`、`grep cgroup /proc/self/mountinfo`）。
   - 影响：原生沙箱（Docker）。没有这个，容器就没有内存、CPU、pids 限制，`docker pause` 和 `docker stats` 也都用不了。
   - 退路：测试版 runc 加开关 `OHM_NO_CGROUPS=1`（默认关闭，测试用），让容器完全不进 cgroup。资源只能靠沙箱外层整体限制。
11. **`/proc/self` 和 `/proc/thread-self` 改成相对链接**（Linux 上是 `<pid>`、`<pid>/task/<tid>`）。
   - 为什么：HongMeng 上它们指向绝对路径（`/proc/53802`）。runc 用 openat2(RESOLVE_BENEATH|RESOLVE_NO_XDEV) 安全地打开 /proc 下的文件，遇到绝对链接会被判成越界，返回 EXDEV（`unsafe procfs detected: openat2 /proc/thread-self/fd/: invalid cross-device link`）；换成不用 openat2 的退路，又报 `possible breakout detected: cannot jump to / in procfs resolver`。
   - 复现：`readlink /proc/self`、`readlink /proc/thread-self`。
   - 影响：原生沙箱（Docker），以及所有用 filepath-securejoin/pathrs-lite 的程序（runc、containerd 等）。
   - 退路：测试版 runc 检测到绝对链接时，直接用具体的 pid/tid 路径（vendored pathrs-lite 的补丁）。
12. **memfd 的 `F_GET_SEALS` 和新的挂载 API `fsopen("overlay")`。**
   - 为什么：runc 为了防 CVE-2019-5736（容器改写宿主上的 runc），要么用 memfd 加 seal 封住自身，要么用 overlay 封住；这两样在 HongMeng 上分别返回 EINVAL 和 ENOSYS。runc 最后退到"复制一份临时文件"，还能用；crun 没有这个退路，直接报 `Failed to re-execute libcrun via memory file descriptor`。
   - 复现：`runc --debug run` 的日志（`F_GET_SEALS on /proc/self/exe failed: invalid argument`、`fsopen overlay: function not implemented`）。
   - 影响：原生沙箱（Docker 的运行时只能用 runc，用不了 crun）。
   - 退路：用 runc。
13. **overlayfs 能叠在 hmfs 上。**
   - 为什么：Docker 的 overlay2 驱动在 /data（hmfs）上挂 overlay，返回 EINVAL。
   - 复现：dockerd 日志 `failed to mount overlay: invalid argument`。
   - 影响：只能用 vfs 驱动，每一层都是整份拷贝，镜像占盘大、拉取慢。
   - 退路：vfs 驱动。
14. **`keyctl(KEYCTL_JOIN_SESSION_KEYRING)` 返回 EINVAL。**
   - 为什么：runc 给每个容器建一个独立的 session keyring，HongMeng 上这一步失败（runc 只把 ENOSYS 当"不支持"放过去，EINVAL 不放过）。
   - 影响：原生沙箱。容器之间 keyring 不隔离（只影响容器与容器之间，不影响沙箱外层边界）。
   - 退路：测试版 runc 把 EINVAL 和 ENOSYS 一样对待（测试用）。
15. **抽象 Unix socket 按 net namespace 隔离**（Linux 本来就是这样：抽象名字属于创建它的 socket 所在的网络命名空间）。
   - 为什么：HongMeng 上抽象名字全局共享。沙箱有了自己的 net namespace 之后，TCP/UDP 已经碰不到主机的 127.0.0.1，可主机上所有在监听的抽象 socket 仍然连得上，其中有鸿蒙自己的服务：wpa_supplicant 的控制接口（`@/data/service/el1/public/wifi/sockets/wpa/wlan0`，wpa_host）、TEE 客户端守护进程（`@tc_ns_socket`，teecd）、hiview（`@DUBAI_BUFFERED_LOG`）、hdcd（`@ohjpid-control`）。清单、属主和风险评估见 native/sandbox/abstract-sockets-ohdev.md（2026-10-28 ohdev）。
   - 复现：`unshare -n` 起一个进程，在里面绑定抽象名字；主机上的进程照样能连上（10-28 在 ohdev 上用沙箱实测）。
   - 影响：原生沙箱，以及所有靠 net namespace 隔离的容器（Docker）。
   - 退路：没有对等的退路。只能靠服务自己检查对端（SO_PEERCRED、SELinux）。
   - 缓解（2026-10-28）：当前实际缓解是 D 的 **B 方案——libc 层出站过滤**（ohm-abstract-fence）：沙箱里的进程只能连自己绑定的和 `ohmsbx-` 开头的抽象名，其余返回 EACCES；它拦不住静态程序和直接发系统调用的程序，**只防误连、不是安全边界**。原计划的两条内核级边界都不成立：(1) 我们自己的 SELinux MAC 域——运行时加载已于 2026-10-27 证伪（连开机原版 developer_policy 都 EINVAL，见 3(b) 第 1 条），只有鸿蒙把它签进系统策略才成立；(2) **C 方案（seccomp + ptrace supervisor 的内核级自主出站拦截）——评估后暂不实现**（会明显拖累桌面性能，且目前的 residual 并非已证实的漏洞），仅作文档记录的可选加固、设计从略、未实现。根治仍需鸿蒙按 netns 隔离抽象 socket，或把我们的策略模块签进系统。

Docker 测试版现在一共有这几个绕过开关，都默认关闭、只用于测试：`OHM_NO_DEVICES_CGROUP`（dockerd）、`OHM_CHROOT_REEXEC`（dockerd，对应上表线程级 CLONE_FS 那一行）、`OHM_NO_CGROUPS`（runc），以及 uname、/proc 链接、keyring 三处补丁。沙箱的外层边界（独立 mount ns、pivot_root、精简的 /dev）一处都没放松。削弱的是容器这一层：cgroup 和 keyring 只影响容器之间的隔离；devices cgroup 和 seccomp（测试版 runc 是静态编译的，没带 seccomp）原本还保护着内核和宿主不被容器触碰，现在只靠 `--cap-drop MKNOD`、禁止 `--privileged`/`--device` 和沙箱外层兜底。所以这个测试版只能证明功能可行，不能当安全方案。

### 3(b) 希望允许或放开的

1. **原生沙箱的小助手作为系统服务，并配专用 MAC（SELinux）规则。**
   - 为什么：现在 root 的 broker 和会话初始化只能留在宽松的 `su` 域，也切不到更窄的域。新方案需要一个受控、可审计的 root 小助手。
   - 影响：D、原生沙箱。
   - 现状：**运行时加载已被证伪**（2026-10-27 实测，见 1.5 节）——连开机加载的原版 developer_policy（3299594 字节）原样回灌都返回 EINVAL（step-1 rc=1、step-2a EINVAL，均 0 字节、系统无损），鸿蒙内核在开机后硬禁止再加载任何策略，我们无法自行装入新域，运行时也没有任何回灌恢复、只能重启。因此唯一出路是**请鸿蒙把我们的策略模块签进系统策略/OTA**，并把小助手作为签名的系统服务预置。模块设计已拟（新域只读写自己的目录 + Docker 放行清单 + 禁止对沙箱外 connectto/sendto），可随诉求交付。
   - 退路：继续以 root 运行，实际工作降到 uid 60000，socket 用 SO_PEERCRED 只认显示 app。
   - 具体形式以 docs/native-sandbox.md 为准。
2. **应用白名单与签名。**
   - 为什么：原生桌面 app 现在用 SDK 测试密钥加绑定本机 UDID 的调试 profile 签名，只能在研发机上装；正式分发需要 AppGallery Connect 证书，以及允许它和小助手通信的白名单。
   - 影响：D、原生沙箱。
   - 退路：只在研发机上用测试签名安装。
3. **"运行自己目录里的代码"的权限。**
   - 为什么：XPM 只允许 app 运行签进 HAP 的 .so，不能 exec 自己目录里的程序，不能有可写可执行内存，所以运行时不能用 pacman 装软件。
   - 请求：为这类 app 放宽 XPM，或给一种专门的签名或权限。
   - 影响：原生沙箱、D 去 root、J、H、K。
   - 退路：J，整套重编成签名的 .so，移植量大，运行时不能装软件。
4. **内核能力：user namespace、cgroup v2、进程间共享 CLONE_FS。**
   - 为什么：沙箱、容器、systemd、Chromium 沙箱都要用。
   - 影响：D、原生沙箱（Docker 在里面跑）。
   - 退路：root 加 chroot，Docker 放在 I 的虚拟机里，浏览器用 Firefox。
5. **OSEasy 正式支持 Linux 客户机**（docs/oseasy-vendor-request.md）。
   - 请求：
     - 正常的"开机／关机"，"再次安装"前不清空磁盘；
     - Linux 版 guest agent，或公开协议，或明确允许第三方实现；
     - 窗口可全屏、可缩放，尺寸变化时下发给客户机；
     - 原生支持 120 Hz，并由 OSEasy 向系统请求高刷新率；
     - 支持更大的 ISO 或"导入磁盘镜像"入口。
   - 为什么：现在装好的系统一关机就丢，只能固定窗口、60 Hz。
   - 影响：B。
   - 退路：每次重装（约 1.5 分钟）；ISO 压在 2 GiB 以下；120 Hz 只在客户机内部。
   - 进展：尚未与厂商实际联系，只有需求文档。
6. **虚拟化白名单。**
   - 鸿融：HarmonyOS 7.0.0.32 的 libvm_manager.z.so 只认硬编码的 14 个 appIdentifier，其中有 OSEasy、铠大师，没有鸿融（6917612137513552427），导入停在 0% 且界面不报错；7.0.0.115 改为检查 MANAGE_VM（docs/vm-api.md，e653362、036212c）。
     - 请求：把鸿融加入老版本白名单，或老版本改用 MANAGE_VM；应用市场不把鸿融分发到它用不了的系统。
     - 影响：老系统上的 C。
     - 退路：老系统上只走 B，或升级系统。
   - 第三方：@hms:virtService.vmManager 要求 MANAGE_VM（system_basic 级），且调用方必须在写死的伙伴白名单里，调试签名的 app 只拿到 201 Permission denied（docs/vm-api.md）。
     - 影响：I、H、自研虚拟机 app。
     - 退路：root 直接调 /dev/hmv（I）。
   - 多实例：鸿融、OSEasy、Docker 后台虚拟机共用 HMV，第二台会被拒（401 "Not support vm multi-instance"）。
     - 请求：允许多实例，或允许排队。
     - 影响：演示和日常同时使用。
     - 退路：严格串行。
7. **固件 USB 启动和 Secure Boot。**
   - 为什么：路线 E 需要从 U 盘启动未签名的 GRUB。10-27 开机按 F12 没有反应，可用的启动键和 Secure Boot 开关状态未知。
   - 影响：E。
   - 退路：放弃 E。即使能启动，麒麟 X90 也没有主线驱动，上限是"帧缓冲上出画面"。
8. **Super 键。**
   - 为什么：松开 Windows 键必定弹出鸿蒙开始菜单，Omarchy 的快捷键体系依赖 Super。
   - 请求：允许全屏 app 截获 Super 键，或提供关闭开始菜单的开关。
   - 影响：D。
   - 退路：Alt+Shift 代替（ad71991）。
9. **把 /dev/dma_heap 开放给 app，或明确 /dev/system_heap2 可供 app 使用。**
   - 影响：J、D。
   - 退路：依次尝试 system_heap2、memfd。
10. **跨进程使用窗口。**
    - 为什么：`OH_NativeWindow_CreateNativeWindowFromSurfaceId` 只在本进程有效，别的进程无法往 app 的窗口里画。
    - 影响：I 无法借 D 的窗口上屏。
    - 退路：I 保持无界面。

### 3(c) 需要提供的信息和资源

1. **各 HarmonyOS 版本的虚拟化差异对照表。**
   - 内容：vm_manager 鉴权方式（白名单还是 MANAGE_VM）、StratoVirt 版本，以及 feature select 等已知差异。
   - 用途：在公开文档里写明最低系统版本（B、C）。
2. **鸿融的显卡和显示规则。**
   - 内容：何时给 vhost-user-gpu（virgl）、何时给 2D virtio-gpu；全屏呈现能否达到 120 Hz。
   - 用途：C 的性能和刷新率说明。
3. **鸿融增强服务对非 deb 发行版的支持方式和协议。** 现在是从鸿融光盘取 deb 装进 Arch（hongrong/pure/install-vm-agent.sh）。用途：C。
4. **OSEasy guest agent 协议细节，以及授权条款。**
   - 协议：帧头格式、串口名对应关系、握手和鉴权。
   - 授权：试用和授权条款能否用于公开分发。
   - 用途：B。
5. **libvirglrenderer 的接口说明。**
   - 内容：不同 SoC 和版本之间的差异（上屏、取窗口）。目前已知 ohdev2（麒麟 9020）那份与 ohdev 不同。
   - 用途：D、原生沙箱、J。
6. **HMV 的 ioctl ABI 文档**（0xAE 魔数、自定命令号）。用途：自写加速器，属于 H、I 的选项。
7. **麒麟 X90 的 Linux 驱动 GPL 源码，或 BSP。** 用途：E。
8. **测试机。** 一台研发版机器长期可用：root shell，/system 为可写 overlay，接受测试签名。最好另有一台老版本系统的机器用于回归。

## 4. 以后要维护的地方

### 4.1 我们自己的补丁和分叉

- **内核** linux-aarch64 7.2.12，当前 pkgrel 1.2（hongrong/kernel/pkgbuild/ 和 hongrong/kernel/patches/），B、C、I 共用。

  | 补丁 | 内容 | 删除条件 |
  |---|---|---|
  | 0001 | gic-v3-its nvecs，回移自上游 5a9d62555e71 | Arch 内核自带以后 |
  | 0002 | `arm64.hmv_idreg_quirk`（184779d、05db94b） | HMV 修好以后 |
  | 0003 | virtio-pci 默认只用 feature select 0/1（139aa77） | 旧版 StratoVirt 退役以后 |

  跟 ALARM 升级时要重做四处改动：pkgrel、TUNA 源、hmv-*.patch、去掉 chromebook 包。
- **vmwgfx-oseasy**：driver/vmwgfx-oseasy-7.2/，相对 Linux 7.2.12 的补丁是 hvm-oseasy-vs-linux-7.2.patch，由 oseasy/vmwgfx-7.2/build.sh 打包。它是树外模块，**内核每改一次版本号（包括 pkgrel）都要重编**，vermagic 必须一致，否则 B 黑屏。
- **镜像定制**：
  - hongrong/pure/firstboot/：设密码、growroot、EDID 钩子、ohmarchy-svga.sh（b129b02）；
  - hongrong/edid/omarchy-120.bin；
  - 精简包列表（TRIM_PKGS、SLIM，31e78f6）。
- **原生桌面**：
  - native/desktop/patches/ 下的 aquamarine-0.15.1-hongmeng.patch 和 hyprland-0.56.2-hongmeng.patch；
  - native/app/vtest-inapp.patch；
  - app 自带的 hwf_kits.c（替身 libhwf_kits.z.so）；
  - native/vtest/vtest-broker.c。
- **HongMeng 垫片**：
  - /etc/ld.so.preload 里的 splice 垫片；
  - native/desktop/hongmeng-{statx,msgrcv,uname}.c；
  - native/desktop/shims/（uwsm-app、systemd-run 等替身）。
- **J**：
  - device/userspace/patches/（Hyprland、aquamarine 的 musl 构建补丁，去掉 SVG 支持的补丁）；
  - device/userspace/shim/、uapi-fix/。
  - 工具链是 clang 23 加自编 libc++（libc++_ohm.so.1）。
- **I**：
  - tools/ownvm/（ohmarchy-vm、docker gate、dropuid、prep-disk.sh）；
  - 上游 virtiofsd 1.14.0 的静态编译（build-virtiofsd.sh）。
- **root ssh**：device/oh-ssh/（ohsshd、ohtoken 的 Go 源码，按原程序重写，35387ab、977c4b9）。

### 4.2 依赖特定鸿蒙版本或行为的地方

- **vm_manager 鉴权**：7.0.0.32 用白名单，7.0.0.115 用 MANAGE_VM。鸿融能否使用取决于此。
- **StratoVirt 对 feature select 的处理**：7.0.0.32 只接受 0/1，必须用内核 1.2。
- **HMV 对 ID 寄存器的处理**：需要 0002。
- **鸿融的导入校验**：qcow2 必须一开始就按 256 GiB 创建；头部 256 字节且 os_type=1；不支持压缩簇。
- **鸿融换盘依赖**：vm_manager 目录结构、属主 7700、SELinux 标签 ohsw_file。
- **鸿融增强服务的安装方式**：光盘卷标、deb 路径；它会改写 logind.conf，我们用 drop-in 补救。
- **OSEasy 的界面流程**：只收 ISO、"再次安装"清盘、窗口 Mode 102、install.wim 误报，以及界面坐标。
- **原生桌面依赖的系统行为**：
  - /dev/system_heap2 权限 666；
  - 普通 app 能连 `su` 域的 socket、能收 dmabuf；
  - app 从设备拷贝系统的 libvirglrenderer，版本不同会崩；
  - /system 为可写 overlay；
  - 研发机接受测试签名；
  - 截屏和 uitest 借用 hdcd 的 token。
- **系统组件版本**：鸿融 1.1.1.103（应用市场会自动换版本）；OSEasy 3.1.1.7。
- **网络**：客户机地址 172.16.100.2/24，网桥没有 DHCP。

### 4.3 构建和发布流水线

1. **内核**：在 ohdev 的 Arch 环境里，用 hongrong/kernel/pkgbuild 执行 makepkg。
   - 完整编译约 25 分钟，增量约 3 分钟。
   - 产物是 linux-aarch64 和 headers 两个包，再用 oseasy/vmwgfx-7.2/build.sh 编 vmwgfx-oseasy。
2. **镜像**：hongrong/pure/build-disk.sh 从零生成文件树（NOPASS=1 等）。
3. **小盘和 zst**：hongrong/pure/repack-disk.sh 生成 12 GiB 小盘和 zst。
   - KERNEL_PKGS、VMWGFX_KO 可以只换内核（139aa77）。
   - zstd 只能用 -T2（295d141）。
4. **B 的 ISO**：`oseasy/probe/build.sh OUTDIR 内核包 vmwgfx包`，镜像由 PROBE_IMGZST 指定，在 Arch 容器里构建。
   - 默认启动项找到已装系统就 chainload 盘上的 GRUB（7d0105f）。
   - El Torito 不放内核，以压到 2 GiB 以下（2563b62）。
5. **C 的 qcow2**：hongrong/pure/make-qcow2.sh。
6. **发布**：tools/release/（release.sh、upload-on-host.sh、gpl-sources.sh、sums.sh），单个文件不超过 2 GiB；GitHub release 草稿 b-20261027。
7. **原生桌面**：
   - native/install.sh 一键安装，从零约 30 分钟；
   - native/reset.sh 约 56 秒恢复干净镜像；
   - native/app/build.sh 加 sign/sign.sh 构建和签名显示 app。
8. **当前产物位置（ohdev）**：
   - /data/local/vmtest/work/out-full/omarchy-small.img.zst（1800558660 字节，内核 1.2），上一版保留为 omarchy-small-v2.img.zst；
   - /data/local/vmtest/work/k12/（内核 1.2 包和 vmwgfx）；
   - /data/local/vmtest/work/iso-out/（ISO）。
9. **不在仓库里的东西**：
   - ohdev 上的 hrswap.sh、zchunks.sh、run-repack.sh 等运行脚本，以及 B 的 probe-src 工作副本（与 7d0105f 一致）；
   - Mac 上的 OSEasy agent 逆向产物 ~/oseasy-work/oetool-re/，有意不入库；
   - J 的 HAP 库包（gitignore，可以重新生成；需要大小写敏感的 APFS 卷）。

### 4.4 从零复现的入口

- **总入口**：README.zh-CN.md "快速开始"、docs/README.md（按路线分好的文档索引）。
- **B**：docs/oseasy-install.md（用户安装）、docs/oseasy-whole-os.md（每次运行的记录）、docs/oseasy-agent-protocol.md。
- **C**：docs/hongrong-whole-os.md（Developer image、Toward Omarchy's own kernel）、hongrong/kernel/pkgbuild/README.md。
- **D**：docs/native-chroot.md、docs/native-desktop.md、native/install.sh。
- **I**：docs/vm-own.md、tools/ownvm/。
- **J**：docs/no-root-routes.md、device/userspace/build-stage*.sh。
- **E**：docs/route-e.md、tools/routee/build-ram-usb.sh。
- **演示**：docs/demo-operator.zh-CN.md、docs/demo.md、tests/demo/{d,i,b}.sh。
- **root ssh**：device/oh-ssh/（从零搭建的步骤在其中）。

## 5. 机器、仓库地图、事故记录和规矩

### 5.1 机器

- **ohdev**：见第 1.3 节。
  - 访问：root ssh，经隧道，地址略。
  - 鸿融里是 C 的 v3 演示盘，Yao 的主盘保留为 vm.qcow2.imported。
  - Arch 环境在 /data/local/archtest/。注意：宿主重启后，Arch 会话里的 /mnt/vmtest 绑定会丢失，要重新 bind。
- **ohdev2**：已停用，见第 5.3 节。我们放在 /data/local 下的文件、ssh 服务和开机配置已于 10-27 删除；OSEasy 里的虚拟机和 Download 里的两个镜像文件按 Yao 的意思保留。
- **Mac**：会话运行环境。J 的离线构建需要大小写敏感的 APFS 卷。
- **magicbook**：Windows 机，带 hdc，USB 连接测试机时用作备用通道；存有 ohdev2 修复前的备份。

### 5.2 仓库地图

| 目录 | 内容 |
|---|---|
| oseasy/ | B：安装 ISO（probe/）、虚拟机内工具、驱动打包（vmwgfx-7.2/）、vote120、运行记录 |
| driver/ | vmwgfx-oseasy-7.2（当前）、vmwgfx-oseasy（Debian 6.1 版）、efidrm |
| hongrong/ | C：deepin 共存方案、pure/（build-disk、repack-disk、make-qcow2、firstboot/）、edid/、kernel/（PKGBUILD、补丁、上游草稿） |
| native/ | D：arch.sh、omarchy 启动器、安装和重置、desktop/（补丁、垫片）、app/（显示 app）、vtest/、boot/；J 的 jloader/、xpmprobe/ |
| tools/ownvm/ | I |
| tools/routee/ | E |
| tools/release/ | 发布脚本 |
| device/ | H 的签名和探针，J 的 userspace/，oh-ssh/ |
| tools/kaidashi/、emulator/、webemu/、linux-engine/ | G、F、L、A |
| tests/ | D 的验收测试、演示脚本 |
| docs/ | 全部文档；索引 docs/README.md；对外材料 docs/hmv-idreg-report.md、docs/oseasy-vendor-request.md、docs/internal/hongrong-team-brief.md |

### 5.3 事故记录

1. **ohdev2 无法启动（2026-10-27）。**
   - 原因：19:38:29，一条本应只读的检查命令以带引号的 ssh 一行命令发出，远端 shell 丢掉了引号，`->` 变成了写重定向。经 /system/lib64/libc.so 这个符号链接，动态加载器 /system/lib/ld-musl-aarch64.so.1 被覆盖成 10 字节。
   - 后果：下次开机所有动态链接程序都起不来（E_HM_NOEXEC），ueventd 没有运行，/data 无法挂载，机器进入 eRecovery。
   - 19:40–19:48 那台反复出错的虚拟机：pid 54451，是 OSEasy 在 stratovirt 31012 被按 PID 杀掉后自动重拉的。它只是触发了那次重启，不是无法启动的原因。早先"系统更新导致"的说法已撤回。
   - 修复：被覆盖的文件只在 /system 叠加层的上层 ext4 里。在副本上用 debugfs 删掉它，核对后写回 6 个 4 KiB 块，原版加载器重新露出来；同时删除了我们加的两个开机配置。/data 未改动；修复前对叠加层做了备份。
   - 来源：docs/vm-api.md 中的更正（d9c3371、e4a8929）。
   - 此后该机停用。
2. **ohdev OOM 重启（2026-10-27 08:38）。** repack 用 `zstd -T0 --ultra -22 --long=31`，宿主内存耗尽（HM_PANIC_OOM，见 /data/log/bbox/history.log）。已改为 -T2（295d141）。
3. **按进程名杀进程（2026-10-27）。** 一次按名字匹配批量杀 curl，打断了其他线在 ohdev2 上的拷贝，没有数据损失。
4. **杀 stratovirt 触发自动重拉（2026-10-27，ohdev2）。** 见第 1 条。由此定下停虚拟机的规程（e4a8929）。
5. **大文件拷贝倒退（2026-10-27）。** `curl -C - --retry` 在连接重置后重试时回到最初的断点，截断已拷部分。改为外层循环每次重新启动 `curl -C -`。另外，Python SimpleHTTP 不支持 Range，无法续传。
6. **压缩块被截断（2026-10-27）。** zstd 被来源不明的 "Real-time signal 2" 杀掉；`bash -c` 执行的函数没继承 pipefail，残缺的块被当成完成。改为每块解压核对字节数后才改名。HongMeng 上 cat 拼接超过 2 GiB 的输出报 EOVERFLOW，改用 dd。
7. **其他早期事故（2026-10-24，I 线）。** 都已当场处理：
   - 按名字杀 virtiofsd，误杀了 OSEasy 正在用的那个（系统随即重启了它）；
   - Omarchy 盘曾放进"文档"目录，有被云同步传走的风险，已立即删除；
   - 虚拟机的 sudo 密码曾写进 ohdev 上的文件，已删除，改为只经环境变量传递。
8. **密钥曾出现在会话输出中（2026-10-26）。** shell 展开把密钥打印到了会话里，没有写入任何文件。此后提交前一律 grep 检查。
9. **"黑屏"的多种原因（B）。** 依次查明过以下几种，要逐一排除：
   - 空闲进入屏保或关屏；
   - vmwgfx Oops（36cfb9d）；
   - Quickshell 在 SVGA3D 上画黑（b129b02）；
   - sudoers 文件排序导致规则失效（cf91ba0）；
   - vmlog 是累积的，读到了旧的 Oops。

### 5.4 规矩

**远程操作**
- 远程命令一律写成脚本经 `sh -s` 发送，不用带引号的一行命令；只读检查的输出里出现 "can't create" 立即停下。
- ssh 一律加硬超时（macOS 上用 `perl -e 'alarm N; exec @ARGV'`）。
- 读 /proc/PID/cmdline 加超时；toybox grep 要用多个 `-e`。

**进程和虚拟机**
- 只按自己记录的确切 PID 杀进程，不按名字杀。锁文件机制已于 10-25 取消。
- 同一时刻只能跑一台虚拟机：起虚拟机前先 `pidof stratovirt`。
- 停 OSEasy 或鸿融的虚拟机，按顺序：
  1. 先在 app 里关机；
  2. 关不了就 `aa force-stop` 对应 app；
  3. 最后才按 PID 杀 stratovirt，并确认没有新的 stratovirt 出现。
- 不要拿另一台机器的系统库来替换本机的。

**数据**
- 覆盖前先备份。
- 拷贝核对用 cp 的退出码和文件大小，不用 sha256（Yao 的要求）。
- 宿主上 zstd 只用 -T2。

**屏幕**
- 截图确认前台窗口后再输入。
- 占用屏幕前先通知正在使用屏幕的会话。
- Yao 在机器前操作时，各线不停手、不让屏、不关他开的窗口；被挡住就报给监督。

**安全**
- 密码、密钥、token、relay 地址、隧道域名，不写进仓库、日志、公开镜像和记忆；测试密码只经环境变量或 stdin 传递。
- 提交前 grep 密钥。
- AI 中转的密钥只放在 ohdev 的 /data/local/secrets/ai.env。

**git**
- 只用 main 一个分支，推送前 `pull --rebase`。
- 不 force push，不改写历史。
- 只提交自己的文件，不用 `git add -A`。

**审批**
- 以下事项必须 Yao 本人同意，其他会话或监督的转述不算：
  - 对外提交上游、联系华为或厂商；
  - 登录、付费、同意条款；
  - 公开发布；
  - 刷机、清除数据这类不可逆操作；
  - 删除未核验的备份。
- DCO 签名必须是 Yao 本人的。

**长任务**
- 在预计结束时间直接查日志、进程和产物，不依赖后台等待脚本。
- 宿主重启后先恢复 Arch 会话里的绑定再继续。

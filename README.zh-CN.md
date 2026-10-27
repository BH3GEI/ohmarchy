# ohmarchy：在鸿蒙电脑上跑 Omarchy

[English](README.md) | 中文

目标：让 [Omarchy](https://omarchy.org)（DHH 做的 Arch Linux + Hyprland 桌面）在鸿蒙（HarmonyOS）电脑上跑起来。测试机 `ohdev` 是一台 HUAWEI MateBook 14 HM740：麒麟 X90（20 线程、32 GB 内存）、马良 916 GPU、2880x1920 屏幕（最高 120Hz），系统 HarmonyOS 7.0.0.115，内核是鸿蒙自己的 HongMeng 内核 1.11.13.0。最早在 MateBook Fold（HarmonyOS 7.0）上开始，用的是 [riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image) 的 AArch64 版 Omarchy。

一句话总结现在的结果：

- **B OSEasy（第三方 Windows 虚拟机 app）**：从零安装到桌面约 3 分钟，靠打过补丁的 `vmwgfx` 显卡驱动拿到 GPU 3D（修了三个问题，外加一个看门狗），带 GPU 负载连续 4 小时 24 分钟没出错。屏幕上 60Hz。
- **C 鸿融（华为自己的 Linux 虚拟机 app）**：做好的 Omarchy 磁盘镜像（打了补丁的 7.2.12 内核）用鸿融自己的界面就能导入，不要 root。有 virgl 3D（glmark2 596 分）和 Docker；虚拟机里按 120Hz 画，鸿融只按 60Hz 显示。
- **D 原生，不用虚拟机**：Arch Linux ARM 和 Omarchy 4.0.6 直接当普通进程跑在鸿蒙内核上，Omarchy 的 Hyprland 桌面显示在一个鸿蒙 app 窗口里，120Hz，用马良 GPU 画。切工作区屏幕上 119 帧，冷启动约 8 秒，78 个 app 里 74 个 3 秒内打开，24 小时长测通过。需要宿主机 root。
- **I 自建虚拟机给 D 当后台**：给原生桌面补上 Docker 和完整的 Linux 内核。系统虚拟化层上跑一台没有界面的 Omarchy 虚拟机，D 的 `docker` 通过 ssh 用它；从 caecc94 起，第一次用 `docker` 时它会自己启动。需要 root。
- **确认走不通的路**：不用 root 的话，app 既用不了虚拟化层（华为写死了一个合作伙伴白名单），也拿不到可执行内存（XPM 代码完整性保护）。所以不用 root 的路只有两个虚拟机 app（B、C），以及还在做的 J：把 Linux 程序编成 `.so` 签进 app 里。

## 路线一览（树）

```
鸿蒙电脑上的 Omarchy
├─ 一、虚拟机 app 即插即用（不用 root）
│   ├─ B  OSEasy        ★ 公开发布走这条
│   ├─ C  鸿融           内部成果（鸿融 app 还没公开发布）
│   └─ G  铠大师         已结束：Linux 只能活在一次"安装会话"里
├─ 二、原生：直接跑在鸿蒙内核上（效果最好）
│   ├─ D  原生桌面            要 root；120Hz；演示的主角
│   ├─ I  自建后台虚拟机       要 root；给 D 提供 Docker
│   └─ J  在 app 沙箱里原生跑  不用 root；Hyprland 已编好，正在上真机
└─ 三、其它探索（已有结论或备选）
    ├─ A  鸿蒙 Linux 引擎              只有终端工具
    ├─ F  DevEco 模拟器里的 Aetherium  不需要真机；很慢
    ├─ H  真机上的 Aetherium           走不通：拿不到可执行内存
    ├─ K  QEMU 解释模式                只是个想法
    ├─ L  鸿蒙浏览器内核里的 Linux     暂停
    └─ E  裸机                         没开始
```

第一条线是把 Omarchy 装进虚拟机 app 里跑，不用 root（对外公开发布走 OSEasy）；第二条线是直接跑在鸿蒙内核上，效果最好，但 D 和 I 在鸿蒙放开[对内对接](#对内对接给鸿蒙各团队)里列的那几样之前要 root；第三条线是其它试过的路。所有文档按同一棵树列在 [docs/README.md](docs/README.md)。

## 现状一览

| 路线 | 是什么 | 状态 | 最好的数字 | 要 root 吗 | 能演示吗 |
|---|---|---|---|---|---|
| **一、虚拟机 app（不用 root）** | | | | | |
| **B** OSEasy 虚拟机 | 完整 Omarchy 系统跑在 OSEasy 里，7.2.12 内核，打补丁的 `vmwgfx`；镜像打包在安装盘里 | 能用，有限制（屏幕 60Hz；固定大小的窗口，不能全屏；关机后什么都不保留） | 公开安装盘 1.855 GiB；从安装盘写盘 231 秒，约 4 分钟进桌面；虚拟机里 2100x1511、120Hz；GPU 长测 4 小时 24 分钟零故障 | 不要 | 能，约 4 分钟 |
| **C** 鸿融虚拟机 | 完整 Omarchy 系统跑在华为的 Linux 虚拟机 app 里，virgl GPU | 能用，有限制（屏幕 60Hz） | 导入不到 1 分钟（9.6 GB）；glmark2 596；Docker；30 分钟长测 | 不要 | 能，3 分 41 秒 |
| **G** 铠大师虚拟机 | Omarchy 磁盘跑在 sanway 的 Windows 虚拟机 app 里 | 已结束，走不通 | 7.2.12 能启动，但每台虚拟机都只是"安装会话"，一关机就被删 | 不要 | 不演示 |
| **二、原生：直接跑在鸿蒙内核上** | | | | | |
| **D** 原生 | Arch + Omarchy 在鸿蒙内核上的 chroot 里跑，Hyprland 由鸿蒙 app 显示 | 能用 | 切工作区 119 帧，es2gears 屏幕上 117-120 帧；冷启动约 8 秒；78 个 app 74 个 3 秒内打开，P95 1.13 秒；24 小时长测 | 要 | 能，约 80 秒 |
| **I** 自建虚拟机 | root 直接在 `/dev/hmv` 上起 StratoVirt，没有界面；给 D 当 Docker 后台，用到时才启动 | 能用 | 虚拟机 5-10 秒起来；空闲占宿主约 1.2 GiB；balloon 6 秒左右还回 3 GiB；演示 91 秒 | 要 | 能，和 D 一起 |
| **J** app 沙箱里的 Linux | Linux 程序编成 `.so` 签进 HAP，用 fork + dlopen 运行 | 原型能跑（busybox）；Hyprland 0.56.2 已经用鸿蒙 musl 编出来了，还没上真机 | busybox `sh` 已在 D 的显示 app 里跑；Hyprland 能链接上自己编的整套库（845dc1b） | 不要 | 不演示 |
| **三、其它探索** | | | | | |
| **A** Linux 引擎 | 鸿蒙自带的 Linux 容器里跑 Omarchy 的 neovim 配置和命令行工具，每个工具一个鸿蒙窗口 | 能用，有限制（只有终端工具，没有 Hyprland 桌面） | | 不要 | 不演示 |
| **F** DevEco 模拟器里的 Aetherium | 在 Mac 上的鸿蒙 PC 模拟器里，用 app 里的 QEMU 纯软件模拟 | 能用，有限制（纯软件，很慢） | 首次开机配置 14-50 分钟 | 不要（不需要真机） | 不演示 |
| **H** 真机上的 Aetherium | F 那个 QEMU app 放到真机上 | 已结束，走不通 | QEMU 在 `tcg_region_init` 直接退出（拿不到可执行内存） | 不要 | 不演示 |
| **K** QEMU 解释模式（TCI） | QEMU 的解释器，不需要可执行内存 | 没开始（只是想法，已降低优先级） | | 不要 | 不演示 |
| **L** 鸿蒙浏览器内核里的 Linux | app 里的 ArkWeb 网页跑 v86（把 x86 翻译成 WebAssembly 执行），里面是 Arch Linux 32 | 2026-10-25 决定暂停，从没在真机上跑过 | 电脑上的 Chrome：约 32 秒进 root 命令行 | 不要 | 不演示 |
| **E** 裸机 | 不要鸿蒙，Linux 直接装在硬件上 | 没开始 | | | 不演示 |

<!-- progress:start -->
## 进展（每小时更新；最近一次：2026-10-27 07:29 PDT）

现在：最优先的是**新原生方案**：Omarchy 像鸿蒙应用一样安装和启动，直接跑在鸿蒙内核上（不走虚拟机），锁死在自己的目录里，里面能跑 Docker。现在能演示的原生版不动，新方案另起一份做。第二台测试机已经修好、拔掉，不再使用。

| 路线 | 正在做 | 最新结果 |
|---|---|---|
| D. 原生（新方案） | 在第一台上并行做三项验证，只在命令行里做：能不能加我们自己的允许清单（H）；Docker 锁在一个目录里还能不能跑（a4）；里面的 root 是不是真出不了目录（D，等 H 的结果）。D 同时写设计文档，定小助手和应用怎么配合 | **方案已定**：一个职责固定的 root 小助手（把 Linux 启动在自己的目录里、给 Docker 隔房间）；应用负责图标、全屏、画面、键盘鼠标；里面是完整的 Arch，能用 `pacman`、能当管理员；两道锁：Linux 只看得到自己的目录，加一张默认全禁的允许清单，别的什么都碰不了；相册、剪贴板这些隐私数据留在外面，要用就通过应用申请，鸿蒙照常弹窗。和演示版完全分开：新的应用名、新的目录、不设开机自启 |
| D. 原生（演示版） | 不动；Alt+Shift 等屏幕空出来再上机 | **Alt+Shift 代替 Super**（ad71991）：Super+X 改按 Alt+Shift+X，要 Super+Shift 或 Super+Alt 就再加按另一个 Shift 或 Alt；右 Alt 恢复成普通 Alt；Alt+Shift+Tab 仍是切换窗口。还没在实体键盘上试 |
| B. OSEasy | 在第一台上用新安装盘做回归安装；检查完就关机，把虚拟机名额让出来 | 新安装盘 2,032,457,728 字节，内核 7.2.12-1.2。**磁盘持久化**：从 OSEasy 的 Windows 版助手程序里解出了消息格式（握手和远程调用），够写一个最小的 Linux 版助手 |
| 发布 | 补 GPL 源码 | 缺的 14 个包已下到 10 个，还有 5 个上游源码在找。回归通过后把新安装盘放进草稿，在那之前旧的不动 |
| E. 裸机 | 等负责人试开机按键 | 没有变化 |
| 第二台机器 | 已修好、已拔掉，不再使用 | 能正常开机；`/data` 没动；我们的 ssh 服务和开机配置已删掉 |

交接：正在起草明天讨论用的文档（我们还要做什么、鸿蒙需要合入或放开什么、以后要维护哪些地方）。
<!-- progress:end -->

试过哪些路、为什么走不通：[docs/findings.md](docs/findings.md)（英文）。

## 对内对接（给鸿蒙各团队）

这么多路线，归结起来就是两条线，每条线要找的团队不一样。

### 线一：希望虚拟机 app 做的事

**线一：在虚拟机 app 里即插即用（B OSEasy、C 鸿融）。** 用户从应用市场装一个虚拟机 app，导入我们的镜像就能用，不用 root，现在就能做到。离完美还差的都在这两个 app 自己身上：它们都不向系统申请高刷新率，所以屏幕停在 60Hz；OSEasy 的流程是按 Windows 设计的（Linux 虚拟机没有"开机"按钮，"再次安装"会清空硬盘，所以我们正在把系统放进 OSEasy 共享文件夹里的一个 ext4 镜像文件，由安装盘直接从它启动，约 10 秒进桌面，状态也能保留）；鸿融要在虚拟机里装它的增强服务，才能正常显示"运行中"、正常关机。对外发布正在准备：安装不用 root、镜像放到 GitHub Releases、写给普通用户的说明。

- **鸿融团队**（[docs/internal/hongrong-team-brief.md](docs/internal/hongrong-team-brief.md)）：全屏虚拟机按虚拟机自己的刷新率（或屏幕的 120Hz）显示，别卡在 60Hz；增强服务在任何发行版上都能装，不依赖 dpkg；把"本地文件"导入对 qcow2 的要求（os_type 那个字节）写成文档；别整个重写 `logind.conf`，改用 drop-in；没装增强服务时卡片也显示真实状态、普通关机走 ACPI 电源键；把 HMV 的 ID 寄存器和 ITS 问题转给相关团队。
- **OSEasy 厂商**（[docs/oseasy-vendor-request.md](docs/oseasy-vendor-request.md)）：给 Linux 虚拟机正常的开机、关机（"再次安装"前别清空磁盘）；提供 Linux 版客户端代理，或者公开代理协议；提供 120Hz 的显示模式；共享文件夹保留文件属主和权限；可选：能直接导入现成的磁盘镜像。

### 线二：原生要鸿蒙提供什么

**线二：原生（D，加上 I 当 Docker 后台）。** 效果最好：120Hz、直接用马良 GPU、78 个 app 有 74 个 3 秒内打开、原生终端里直接用 Docker。但要 root。要做到"应用市场装一个 app，打开就是 Omarchy 桌面"，需要鸿蒙提供这些：

| 需要鸿蒙提供的 | 为什么 | 我们现在怎么绕 |
|---|---|---|
| **允许 app 运行自带的 Linux 程序**（为这种情况放宽 XPM，或者给一种专门的签名或权限） | 现在 app 只能运行签进安装包的代码 | J：把整套软件重新编成签名的程序库塞进 app。能跑，但移植工作量大，运行时也不能用 `pacman` 装软件 |
| **内核功能：user namespace、cgroup v2、进程间共享 `CLONE_FS`** | 沙箱、容器、Chromium 的沙箱都要用 | 用 root 起 chroot；Docker 放在 I 的虚拟机里；浏览器改用 Firefox |
| **开放虚拟机接口**（`MANAGE_VM` 现在是写死的 8 个 app 的白名单） | I 的后台虚拟机要用 | 用 root 直接调 `/dev/hmv` |
| **修 HMV 的两个问题**（不认识的 ID 寄存器会卡死 vCPU；ITS 事件号） | 新版 Linux 内核在 HMV 上会卡死 | 内核里打补丁；报告见 [docs/hmv-idreg-report.md](docs/hmv-idreg-report.md) |

只要有了前两项，D 就能不用 root、以现在的性能跑起来。

## 推荐的演示（约 10 分钟）

具体步骤和点击坐标在 [docs/demo.md](docs/demo.md)；`tests/demo/{d,i,b}.sh` 可以远程自动跑同样的步骤。虚拟化层同一时间只能跑一台虚拟机，所以下面这个顺序是为了让虚拟机一台一台干净地交接。

| # | 内容 | 展示什么 | 时间（彩排实测） |
|---|---|---|---|
| 1 | **D 原生桌面**（[demo.md D](docs/demo.md#d-omarchy-natively-on-harmonyos)） | 宿主上 `omarchy desktop start`，然后打开"Omarchy (native)"：Hyprland 和 Omarchy 顶栏、foot 终端里跑 fastfetch（Arch 跑在鸿蒙内核上）、切工作区 119 帧、Firefox、Omarchy 菜单、文件管理器 | 全程 80 秒（635265e） |
| 2 | **I 在原生终端里用 Docker**（[demo.md I](docs/demo.md#i-docker-on-the-native-desktop)） | 宿主上 `ohmarchy-vm start`，然后在 D 的终端里 `docker run hello-world`，再跑一个挂载个人目录的 compose 服务；生成的文件是 0644、归桌面用户所有；最后 `ohmarchy-vm stop` | 91 秒，全部 PASS（f62265a） |
| 3 | **C 鸿融**（[demo.md C2](docs/demo.md#c-omarchy-in-鸿融)） | Yao 的主虚拟机：从鸿融开机、登录、终端 + fastfetch、Chromium 打开 omarchy.org、切工作区；**用鸿融的界面关机** | 3 分 41 秒（6df8c0d） |
| 4 | **B OSEasy**（[demo.md B](docs/demo.md#b-omarchy-in-oseasy)） | 从"没有虚拟机"开始：在 OSEasy 里建虚拟机，安装程序写入 Omarchy，重启后 6 秒进 Hyprland；es2gears、切工作区、开 app（foot 0.08 秒、nautilus 0.6 秒、chromium 0.8 秒） | 约 3 分钟，另加约 1 分钟准备（73afc8e） |

D 加 I 一共约 3 分钟，C 约 4 分钟，B 约 4 分钟，合计 10 到 11 分钟。C 也可以换成 C1：用鸿融界面导入开发者镜像，约 6 分钟。但鸿融 1.1.1.103 只能放一台虚拟机，所以 C1 要先把 Yao 的主虚拟机备份并删掉。

其他路线为什么不演示：A 只有第三方启动器里的终端工具，不是 Omarchy 桌面；E 没开始；F 只在模拟器里跑，第一次进桌面要 14-50 分钟；G、H 已确认走不通；J 目前只有 busybox；K 没开始；L 暂停了，也从没上过真机。

台上亲手操作的人看这份：[docs/demo-operator.zh-CN.md](docs/demo-operator.zh-CN.md)（English: [docs/demo-operator.md](docs/demo-operator.md)）。

## 一、虚拟机 app 即插即用（不用 root）

### 路线 B：OSEasy 虚拟机里的完整系统

**原理**：OSEasy虚拟机（`com.oseasy1.ohvm` 3.1.1.7，应用市场下载）本来是跑 Windows on ARM 的。它自己不带虚拟机程序（VMM），而是把虚拟机配置交给系统的 `@ohos.virtualization` 接口，由系统服务 `vm_manager` 在鸿蒙的虚拟化层（HMV，Huawei 自研的 hypervisor）上启动 StratoVirt（华为的虚拟机程序）：`accel=hmv`，6 个 vCPU，8 GB，UEFI 启动。

显卡是 `svga-pci`，一块 VMware SVGA II（`15ad:0405`），寄存器走 16 字节的 **MMIO**（内存映射，不是 I/O 端口），256 MiB 显存，2 MiB FIFO。宿主这边的实现照的是 VirtualBox 的 VMSVGA：SVGA3D/VGPU10 命令转成 D3D11，再经 DXVK 转成 Vulkan，在马良 GPU 上画，最后用 mailbox 交换链显示到 app 的窗口里。输入是 USB 键盘、绘图板和 virtio 多点触控。网络是 `172.16.100.1/24` 的网桥，带 NAT，没有 DHCP，虚拟机地址是 `172.16.100.2`。声音设备是 `ivshmem-scream`，Linux 没有它的驱动。

```
虚拟机里：Hyprland → Mesa SVGA3D（GLES 3.0）→ vmwgfx-oseasy → svga-pci
宿主上：  StratoVirt 的 SVGA 后端 → D3D11（DXVK）→ Vulkan（马良）→ OSEasy 的窗口
```

**内核**：在 Fold 上 6.5 以后的内核都会早早卡死，所以最早的流程用 Debian 的 6.1 内核。后来查明原因是 HMV 的 ID 寄存器问题（见下面"共性发现"）。Omarchy 自己的 `linux-aarch64` 7.2.12-1.1 加上 `arm64.hmv_idreg_quirk` 就能在 OSEasy 里启动，鸿融里也一样。

**驱动 `driver/vmwgfx-oseasy-7.2/`**：在 Linux 7.2.12 的 vmwgfx 上加了 HMV 支持（[补丁](driver/vmwgfx-oseasy-7.2/hvm-oseasy-vs-linux-7.2.patch)），用 `oseasy/vmwgfx-7.2/build.sh` 打成 pacman 包。原版 vmwgfx 认为寄存器在 I/O 端口上，直接失败。加的东西：

- 模块参数：`hvm_mmio=1` 走 MMIO 寄存器；`hvm_display=2` 用 screen object（宿主不接受 screen target）；`msg_enabled=0` 关掉 VMware 后门通信；`hvm_refresh=120` 加上定时器模拟的 vblank（`hvm_vblank`），因为设备没有 EDID（显示器参数）。
- HVM 下不注册光标平面：设备报告的光标最大尺寸是 0，凡是碰到光标的原子提交都会失败。
- 画到屏幕之前先把整块表面上传一次，但只针对 GPU 没写过、只被 CPU 写过的缓冲区；不然 CPU 写的画面显示成黑的。
- **修复 1：每 1 毫秒轮询一次 fence**（`hvm_irq_poll_us`，默认 1000）。fence 就是"GPU 这一帧画完了"的信号。vmwgfx 靠中断来发这个信号，这块设备实际上不发中断，于是非阻塞提交可能永远等不到 fence，Hyprland 卡在 `isPageFlipPending true`。现在用定时器干中断该干的活。
- **修复 2：`GEM_CLOSE` 关 TTM 句柄**。Hyprland 0.56 收到客户端的 dma-buf（GPU 缓冲区共享句柄）时，会先 `drmPrimeFDToHandle` 再 `drmCloseBufferHandle` 检查一遍。vmwgfx 给的是 TTM 句柄，`GEM_CLOSE` 不认，返回 `EINVAL`，于是 Hyprland 拒收所有用 GPU 画的客户端（es2gears 画不出来，nautilus 窗口出不来）。现在 ioctl 外面包了一层，把失败的 `GEM_CLOSE` 换成 `ttm_ref_object_base_unref()`。2 x 2000 轮泄漏检查，干净。
- **修复 3：命令缓冲区头晚一点再回收**（`VMW_CMDBUF_RETIRE_US`，5 毫秒）。GPU 长测分别在 38 和 51 分钟卡死。用 netconsole（内核日志走网络发出来）抓到：`dma_pool_alloc` 里崩溃，空闲链表指针被改坏，改坏的位置正好是设备会写的 `SVGACBHeader.errorOffset`。推断是：有了轮询，系统一看到 `COMPLETED` 就把头还回池子，而设备可能还没写完最后一笔。现在完成的头先放 5 毫秒再还，并记录有没有"迟到的写入"。原因是从崩溃现场推出来的，没有直接抓到：5 毫秒和 50 毫秒的检测窗口都没抓到过迟到写入。
- **翻页看门狗**（`hvm_flip_watchdog_us`，默认 50 毫秒）：如果一次翻页的 vblank 事件已经准备好、却一直没送到，1 毫秒轮询顺手把它补上，并计数。真机上一次都没触发过，包括以前会诱发卡死的 `AQ_TRACE` 场景。留着当保险（61e5998）。

**怎么把磁盘装进去**：这个版本的 OSEasy 建虚拟机只收 ISO。所以 `PROBE_DEFAULT=4 oseasy/probe/build.sh` 做了一张安装 ISO，默认启动项（安装模式）在 `172.16.100.2:5003` 上等着，收到 zstd 压缩的 Omarchy 磁盘流（`omarchy-pure.img.zst`，64 GiB 的镜像压成 3.35 GB）后用 `dd conv=sparse` 写盘，再装上 `vmwgfx-oseasy`，在目标系统里跑 `depmod` 和 `mkinitcpio`。宿主上用 root 推这个流（`oseasy/push-disk.sh`）。重装一次 131-147 秒；彩排时写盘实测 61 秒。

**实测数字**（MateBook 14，2026-10-24/25，细节见文档）：

| | 结果 |
|---|---|
| 虚拟机里的帧率 | 120 帧（kmsgl、modetest、Hyprland + es2gears） |
| 宿主窗口收到的帧 | 每秒 120 帧（`dxvk-submit` 线程的提交数） |
| 屏幕上 | 60 帧；切工作区 60 帧 |
| glmark2-es2-wayland 1280x720 | 1083 分（swap interval 0，在 GEM_CLOSE 修复之前测的） |
| 虚拟机重启后进 Hyprland | 6-7 秒；虚拟机里热重启 3 次全过（21-22 秒） |
| 打开 app（出第一个窗口） | foot 0.07-0.08 秒、nautilus 0.60-0.90 秒、chromium 0.81-1.17 秒、obsidian 0.66 秒 |
| GPU 负载长测（两个 es2gears + 切工作区） | 77 分钟（5 毫秒）+ 3 小时 07 分钟（50 毫秒）：没有崩溃，迟到写入 0 次 |
| OSEasy app 冷启动 | 1.1-1.9 秒 |

**限制和原因**：

- **屏幕只有 60Hz**：鸿蒙只在某个可见窗口主动"要" 120Hz 时才把屏幕调到 120Hz，而 OSEasy 从来不要（它的 ArkTS 和原生代码里都没有设置帧率的调用）。我们做了个只要 120Hz 的小窗口（`oseasy/vote120`，`com.ohmarchy.vote120`），但它只有在拿到焦点时才算数；而且多一个图层会让系统合成器从显示硬件合成改成 GPU 合成，反而只有每秒 35-51 帧。所以从 OSEasy 外面拿不到 120Hz。
- 不是 Windows 的虚拟机一关机 OSEasy 就忘了，只给"再次安装"，所以演示要从"没有虚拟机"开始。我们决定不去冒充 OSEasy 的 Linux 客户端代理，因为那等于绕过商业软件自己的安装检查。
- OSEasy 每台设备只能试用一次，之后要买；每个 app 只能有一台虚拟机，整个系统同时也只能跑一台。
- 诊断时开了 `AQ_TRACE=1`，大约 160 帧后就会卡住：日志太多把丢翻页事件的时间窗口拉大了。已经从 `boot-diag.sh` 里去掉。

详见 [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md)（从 Fold 上的第一次到第十五次，每一次都有记录）。

### 路线 C：鸿融虚拟机里的完整系统

**原理**：鸿融（`com.huawei.medivh`，现在是 1.1.1.103）是华为自己的 Linux 虚拟机 app。它也是在 HMV 上跑 StratoVirt，但给 Linux 虚拟机的显卡是 `vhost-user-gpu-pci,virgl=true`。后端是系统自带的 `vhost-device-gpu`（rust-vmm 0.2.0），它调用系统里移植到鸿蒙的 virglrenderer，经 Mesa 的 zink（把 OpenGL 翻译成 Vulkan）跑在马良的 Vulkan 驱动上，再通过 `libhwf_kits.z.so` 显示到鸿融的窗口里。没有 Venus，所以虚拟机里没有 Vulkan；没有 blob 资源，所以每帧要拷贝；Hyprland 最后用的是 GLES 3.0。网络也是 `172.16.100.0/24` 网桥、NAT、无 DHCP。另外还有 virtio 声卡、vsock（客户机工具用）、virtiofs（共享"文档"文件夹）和 balloon。

**两种磁盘**：

1. **Yao 的主虚拟机**：鸿融里装的 deepin 25，Arch Linux ARM + Omarchy 放在 deepin 数据分区的 `/arch` 目录里，借 deepin 的 6.6.143 内核启动，靠一个 `subroot` initcpio 钩子切换根目录（`hongrong/10-bootstrap-arch.sh`、`20-install-omarchy.sh`）。这是最早跑通的桌面，也是演示 C2 用的那台。
2. **开发者镜像**：纯 Omarchy 4.0.6，没有 deepin。用 `hongrong/pure/build-disk.sh` 从零做（在宿主上 D 的 Arch 环境里跑），再用 `hongrong/pure/make-qcow2.sh` 转格式：GPT 分区，512 MiB 的 EFI 分区（GRUB 放在可移动介质路径），ext4 根分区，qcow2 虚拟大小 256 GiB（实际数据 9.6 GB）。内核是 Arch 的 `linux-aarch64` 7.2.12-1.1 加两个补丁（`hongrong/kernel/patches/`），作为 pacman 包装上：
   - `0001`：上游的 `5a9d62555e71`。宿主的 GIC ITS（中断控制器）报告 32 位事件号，`its_create_device()` 把中断向量数算成了 0，所有 MSI 中断申请都失败，vsock 收不到中断。
   - `0002`：`arm64.hmv_idreg_quirk`，把 Linux 6.8 以后才开始读的那些 ID 寄存器当成 0，不去真读。HMV 读到 `ID_AA64PFR2_EL1` 时会把 vCPU 卡死（见共性发现）。

**导入问题怎么解决的**：鸿融拒收我们试过的所有 qcow2。看它的日志才知道，`vm_manager` 会跑 `stratovirt-img get DISK os_type`，类型是 0 就拒绝。os_type 是 StratoVirt 的 256 字节 qcow2 v3 文件头的最后一个字节（偏移 255）：qemu-img 做的是 0，鸿融自己的盘是 1。`hongrong/pure/qcow2-stratovirt-header.py` 现在写成 1（c9ddc15），`omarchy-dev-7.2.12-os1.qcow2` 就能在 本地文件 → 开始安装 里导入了，导完虚拟机自己启动，不到一分钟出现登录界面（341225c）。

**120Hz**：鸿融后端给的 EDID 只有 60Hz。`hongrong/edid/mkedid.py` 做了一个 2160x1440@120 的 EDID，用 `drm.edid_firmware` 加载。如果把 120Hz 标成"首选"，virtio-gpu 的 `mode_valid` 发现它和宿主画面尺寸差超过 16 像素就会删掉它；不标首选，虚拟机里就是 `2160x1440@119.98`。但鸿融全屏显示虚拟机时还是 **60Hz**，而且把别的窗口拿到前面，鸿融就退出全屏。这是鸿融那边的事。

**实测数字**：

| | 结果 |
|---|---|
| 渲染器 | `virgl (zink Vulkan 1.2 (Maleoon 916))`，Mesa 26.2.5 |
| glmark2-es2-wayland 全屏 | 596 分 |
| 屏幕上 | 60 帧（es2gears 和切工作区 59-60），虚拟机里 114-120 |
| Docker | 29.9.2，overlayfs，cgroup v2：hello-world、postgres、带 nginx 的 compose（走镜像加速） |
| 启动 | 开发者镜像：冷启动 + 3 次热重启全过；6 个 vCPU 跑满 30 分钟，没出问题 |
| 导入 | 9.6 GB，不到 1 分钟 |
| 打开 app（主虚拟机，非首次） | foot 0.08-0.13 秒、nautilus 0.62 秒、chromium 0.80-0.86 秒、obsidian 1.16-1.30 秒 |
| 演示 C2 | 3 分 41 秒 |

**限制**：屏幕 60Hz；鸿融 1.1.1.103 只能放一台虚拟机，系统同时也只能跑一台；应用市场会自己更新鸿融（曾把 1.3.1.80 换成 1.1.1.103），要关掉自动更新；在 deepin 那套里从虚拟机内部热重启偶尔会卡（重启后 virgl 设备的 MMIO 访问被卡住），应该关机后从鸿融重新开机；鸿融的客户机工具只认 UOS 和麒麟；用 `loginctl terminate-session` 注销会让鸿融陷入登录界面循环，从鸿融里重启虚拟机就好。

详见 [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md)（英文），给华为的问题报告：[docs/hmv-idreg-report.md](docs/hmv-idreg-report.md)（中文）。

### 路线 G：铠大师虚拟机（已结束）

铠大师（`com.sanway.ecoengine` 3.5.8.14）和 OSEasy 用的是同一个 `vm_manager` 和 `svga-pci`。它检查"必须是 Windows 11 24H2"时只读 WIM 文件里的 XML，所以塞一个 2.5 KB 的假 `sources/install.wim`（`tools/kaidashi/make-fake-wim.sh`、`wrap-iso.sh`），任何 UEFI 的 ISO 都能过；安全启动是关的，7.2.12 补丁内核能启动。但向导启动的每台虚拟机都是一个**安装会话**：按 `libvm_manager.z.so` 里的逻辑，只有铠大师自己的 Windows 客户端服务报告"装好了"才算成功，否则一关机或一关窗口，app 就把虚拟机删了。安装会话的网卡还没有 MAC 地址和收发线程，只能发不能收。要想留住 Omarchy 虚拟机，就得冒充它的 Windows 服务，超出范围；而且就算做到也不比 B 强（同样的显卡，60Hz）。2026-10-24 结束。详见 [docs/vm-kaidashi.md](docs/vm-kaidashi.md)。

## 二、原生：直接跑在鸿蒙内核上（效果最好）

### 路线 D：直接跑在鸿蒙内核上

#### chroot 环境

鸿蒙内核实现了足够多的 Linux 系统调用（syscall，程序向内核要服务的接口），没改过的 Arch Linux ARM 程序可以直接跑：线程、futex、epoll、eventfd、timerfd、signalfd、inotify、带封印的 memfd、io_uring、ptrace（gdb、strace）、大块稀疏 mmap、伪终端、网络都正常；内存页 4K。Arch 的根目录放在一个 64 GB 的稀疏 ext4 镜像里（`/data/local/archtest/arch.img`），因为 `/data` 是 hmfs，挂载时禁止了设备文件和 setuid。`native/arch.sh` 用 `losetup` 挂上镜像，进入一个私有的 **mount + pid 命名空间**（`unshare -m -p`，相当于一个隔离的小世界），里面 1 号进程是 catatonit，然后 `chroot`（把根目录换成这个镜像）。`bin/omarchy` 用 `nsenter` 进去，再用 coreutils 的 `chroot --userspec` 切用户。网络和宿主共用。桌面用户叫 `builder`，uid 60000，因为鸿蒙把 10000 以下的 uid 大都占了。

Omarchy 4.0.6 从它签过名的 AArch64 软件源安装，约 900 个包；宿主连不上 GitHub，要走代理。`omarchy-apply-system` 不跑，因为它会把 ufw 防火墙规则装进鸿蒙的内核。

碰到的鸿蒙内核差异，以及 `native/` 里的对策：

| 差异 | 对策 |
|---|---|
| 没有 user、cgroup 命名空间，只有 cgroup v1 | systemd 当不了 1 号进程，没有免 root 容器；root 用 `unshare -m -p`；给 `systemd-cat`、`uwsm-app`、`systemd-run --user` 做了替身 |
| 没有 Landlock | pacman.conf 里 `DisableSandbox` |
| loop 设备只有 `loop0` 在 `/dev` 下有节点；toybox `mount -o loop` 报 EFAULT | 手动对 `/dev/block/loopN` 用 `losetup` |
| devpts 没有 `ptmx`；设备节点不能 bind 挂载 | tmpfs 的 `/dev` 加 `mknod`，借用宿主的 `/dev/pts` |
| 管道读空后 `splice()` 返回 EPIPE 而不是 0（coreutils 的 `cat` 退出码 1） | `ld.so.preload` 预加载一个小库 |
| `statx(fd, "", AT_EMPTY_PATH)` 返回 EFAULT（GTK 程序、glycin） | `hongmeng-statx.c` 预加载 |
| 已经阻塞的 `msgrcv` 不会被后来的 `msgsnd` 唤醒（fakeroot、makepkg 卡住） | `hongmeng-msgrcv.c` 预加载，改成轮询 |
| 不允许 `PR_SET_KEEPCAPS`（setpriv 失败） | 用 `chroot --userspec` |
| `uname` 报 HarmonyOS/HongMeng（cmake 不认） | `hongmeng-uname.c` |
| **`clone(CLONE_FS)` 不共享根目录和当前目录** | Chromium 的 setuid 沙箱关不住自己的 zygote 进程，只能 `--no-sandbox`；默认浏览器换成 Firefox（它的 seccomp-bpf 沙箱能用），网页 app 也用 Firefox 开 |
| **SELinux：root 的 `su` 域是宽松模式，而且切不到更窄的域**（写 `/proc/self/attr/exec` 被拒） | broker 和会话初始化只能留在 `su` 域；能降权的活都用 uid 60000 做 |
| g++ 16.1 编 aquamarine/Hyprland 会崩（编译器内部错误） | 用 clang 编 |

#### 桌面

```
鸿蒙 app "Omarchy (native)"（native/app）            Arch chroot（路线 D）
  XComponent 窗口 <── 直接显示 GPU 画好的帧 ──┐      Hyprland 0.56.2（打补丁）+ Omarchy 外壳
  app 里的 vtest + 系统 libvirglrenderer       │        GL：Mesa virpipe → /tmp/.virgl_test
    → zink → Vulkan → 马良 GPU            <────┴───────  （vtest-broker 以 root 运行，把连接转交给 app）
  键盘/鼠标/触摸/输入法 ── 16 字节消息 ──>  @ohmarchy-display（aquamarine 的 headless 后端）
  OHAudio 快速模式      <── PCM 音频 ────   @ohmarchy-audio（PipeWire 的 "HarmonyOS" 输出）
```

- **没有 DRM 显卡设备**：`native/desktop/patches/aquamarine-0.15.1-hongmeng.patch` 加了一个 dma-heap 显存分配器（`/dev/system_heap2`，权限 666），以及一个 headless（无屏幕）后端，通过抽象 socket `@ohmarchy-display` 把画面送出去、把输入收进来。`hyprland-0.56.2-hongmeng.patch` 让 Hyprland 在无窗口的 EGL 上画（`EGL_PLATFORM_SURFACELESS_MESA`）并回读画面，还加了一个"出帧标记"：每画完一帧，往一个 7x3 的小纹理里拷一个像素（`HYPRLAND_READBACK_PRESENT`）。
- **GPU 路径**：渲染器跑在 app 里面：上游的 vtest（`native/app/vtest-inapp.patch`）调用设备自带的 `libvirglrenderer.so.1`，也就是鸿融虚拟机用的同一个库，由 `gpu-prep.sh` 打进 HAP。`NEED_OPENGL=1` 让系统 EGL 加载 Mesa 的 zink，跑在马良的 Vulkan 驱动上。chroot 里 Mesa 的 virpipe 连 `/tmp/.virgl_test`，`native/vtest/vtest-broker.c`（宿主上的 root 进程）把连接转交给 app，而且只给 app 的 uid（用 SO_PEERCRED 验身份）。app 在命令流里看到出帧标记，就用 `virgl_renderer_ohos_present` 把这一帧直接显示到窗口里：不拷贝，也不等垂直同步。这个库通过 `libhwf_kits.z.so` 拿窗口，所以 app 自带一个同名的 `hwf_kits.c`，返回自己 XComponent 的窗口。
- **120Hz**：屏幕平时是 60Hz。app 调 `OH_NativeXComponent_SetExpectedFrameRateRange({60,120,120})` 要 120Hz，一秒没有新帧就降到 10Hz（app 空闲时的 CPU 占用从约 14% 降到 1.9%）。输出模式设成 `@120`。
- **GPU 客户端**：普通 app 默认用 CPU 画（llvmpipe），因为系统的 virglrenderer 不接受 Qt Quick 的部分命令。`ohmarchy-gpu APP` 让一个 app 用 GPU 画：它回读画面时在 GPU 上拷进一个快照，Hyprland 上传纹理时直接用这个快照；`libohzc` 让 Mesa 不在 CPU 上拷那些没变的部分。
- **声音**：PipeWire 都播到一个叫 "HarmonyOS" 的输出，`ohmarchy-audio-relay` 通过 `@ohmarchy-audio` 只给 app 的 uid；app 用 `OH_AudioRenderer` 快速模式播放（48 kHz，5 毫秒一次回调）。
- **输入**：鼠标位置、按键、滚轮、evdev 键码送进 aquamarine 的 headless 设备。fcitx5 拼音能用（Ctrl+Space 切换）；用鸿蒙自己的输入法（`ohime`，`OHMARCHY_IME=harmony`）已经做好，还没在屏幕上验证。
- **签名**：这台研究用的机器接受用 SDK 里 OpenHarmony 测试密钥签名、绑定本机 UDID 的调试 profile 的 HAP（`native/app/sign/sign.sh`），root 用 `bm install` 安装。

#### 验收结果（[docs/acceptance.md](docs/acceptance.md)）

| 项目 | 结果 |
|---|---|
| A1 每个 app 3 秒内打开 | 78 个里 74 个通过，0 个失败，3 个不支持（没有摄像头；systemd 用户服务），1 个跳过；中位数 0.58 秒，P95 1.13 秒 |
| A2 核心操作 | 6/6：LibreOffice 和 Neovim 读写文件、剪贴板、中文输入、声音、文件选择框 |
| A3 声音 | 静音后第一声中位 101 毫秒（最多 133），连续播放时 72 毫秒；音画差在 100 毫秒内；-12 dBFS 的测试音到输出端是 -12.0 dBFS。还没人用耳朵听过 |
| B 冷启动 | 约 8 秒（会话 2.0 秒 + 桌面 5.7-6.1 秒） |
| B 切工作区 | 119.4 帧（目标 ≥ 110） |
| B es2gears 屏幕帧率 | 原生 117-120 帧，鸿融虚拟机 60 帧，CPU 花费差不多（分别多 8.4 和 8.9 个百分点） |
| B 空闲 | 桌面占 0.5% 个核，app 1.9%，内存 1.0 GB |
| C 稳定性 | 开关 app 100 轮（内存 +0.1%）；24 小时长测：每小时一次共 25 次，23 次正常（失败的 2 次是我们自己停了桌面），内存不涨；Hyprland 关屏开屏 20/20；app 切后台再切回 20/20；鸿蒙熄屏亮屏 20/20；断网、断 DNS 后 0.1 秒内恢复 |
| D 恢复 | 从零全新安装约 30 分钟；`reset.sh` 56 秒恢复到干净镜像；`check-upgrade.sh`；一键打包日志 |
| E 安全 | 桌面以普通用户运行；sudo 要密码；没有 TCP 监听端口；GPU 和声音 socket 只给 app 的 uid；Firefox 有沙箱。还开着的：手动启动的 Chromium（CLONE_FS 问题）、`su` 域 |

**限制**：没有 systemd 服务（NetworkManager、蓝牙、打印、Wi-Fi/蓝牙小部件、电源菜单都不行）；没有摄像头、麦克风、亮度调节、U 盘；自己跑不了 Docker（这正是路线 I 补上的）；关掉 app 会断掉 Hyprland 的 GPU 连接，重开 app 后要重启桌面；截图读的是已经不再更新的 CPU 副本；开机自启服务（`native/boot/`）装好了，但还没通过真正重启验证。各 app 的情况见 [docs/native-compat.md](docs/native-compat.md)。

详见 [docs/native-chroot.md](docs/native-chroot.md)、[docs/native-desktop.md](docs/native-desktop.md)（英文）。

### 路线 I：自建虚拟机

**原理**：`tools/ownvm/ohmarchy-vm` 以 root 身份直接在 `/dev/hmv` 上启动系统自带的 StratoVirt，不经过任何虚拟机 app：6 个 vCPU，8 GiB，virtio 磁盘，virtio 网卡（自己的 tap `ohmvm0`，带收发线程），vsock，以及 `virtio-balloon-pci,deflate-on-oom=true,free-page-reporting=true`（balloon 就是把虚拟机里没用的内存还给宿主）。GPU 可选（`OVM_GPU=1` 加上 `vhost-device-gpu`，`virgl=true`）。磁盘 `omarchy-own.img` 就是路线 C 的开发者镜像，加上不标首选的 120Hz EDID，用 `debugfs` 离线改好（`tools/ownvm/prep-disk.sh`）。

- **网络**：宿主的策略路由会把发往 `172.16.100.2` 的包从 Wi-Fi 送出去，所以启动时加两条规则（`pref 10500` 走 main 表，`pref 10501` 从 tap 进来的走 2009 表），关机时删掉。
- **给 D 用的 Docker**：`guest-provision.sh` 开启 Docker、配置镜像加速，加一条只允许关机和重启的 sudo 规则；dockerd 不在 TCP 上开放。D 的 docker 命令一开始用 context `ohmarchy` = `ssh://yao@172.16.100.2`（桌面用户自己的密钥，虚拟机的主机密钥事先固定好）。从 caecc94 起，context 改成 `unix:///tmp/.ohmarchy-docker.sock`，由 `tools/ownvm/ohmarchy-docker-gate.c` 提供。这是一个 root 后台程序，`omarchy desktop start` 时和 GPU broker 一起启动，只接受 uid 60000（SO_PEERCRED）。第一次有人连它时它先把虚拟机开起来，然后把每个连接转给虚拟机里的 `docker system dial-stdio`；它自己开的虚拟机空闲 3 分钟、又没有容器在跑，就自动关掉；鸿融或 OSEasy 正开着虚拟机时，它直接回一句说明原因的错误。这样桌面用户用 Docker 就不需要 root 命令行了。开机自启虚拟机的服务（`ohmarchy-vm.cfg`）继续不装，好把虚拟化层留给鸿融和 OSEasy。
- **共享个人目录**：D 的 `/home/builder` 在虚拟机里出现在同一个路径，所以挂载目录（bind mount）照常能用。共享用的是 virtiofs，加 `--translate-uid`，让虚拟机里的 root 写出来的文件在宿主上属于 60000。virtiofsd 以 uid 60000、无任何特权、`NoNewPrivs` 运行（靠 `tools/ownvm/dropuid.c`，因为 setpriv 在鸿蒙上用不了）。必须用 `--sandbox none`，StratoVirt 给鸿融起 virtiofsd 时也是这样。鸿蒙自带的 virtiofsd 1.13.0 会把每个文件都强制设成 0660、还无视 chmod，所以现在默认用**上游 virtiofsd 1.14.0**（用 musl 静态编译，`tools/ownvm/build-virtiofsd.sh`）：文件 0644，目录 0755，chmod 正常（2235eaf）。
- 有别的 StratoVirt 在跑时它拒绝启动：鸿融用同一个网段，HMV 也只能跑一台。

**实测**：启动后 5-10 秒能 ssh 进去；网络、DNS、HTTPS、pacman 都正常；开 GPU 时虚拟机里是 `2160x1440@120`，virgl 跑在马良 GPU 上；Docker 29.9.2，hello-world（从 D 跑 1.2 秒）、compose、端口映射都行；8 GiB 的虚拟机空闲时宿主只占约 1.17 GiB：在虚拟机里写 3 GiB 再删掉，宿主内存从 4109 MiB 约 6 秒回到 1161 MiB；关机（在虚拟机里面关）约 10 秒。演示脚本 `i.sh`：91 秒全部 PASS。

**没做的**：把这台虚拟机的桌面显示在 D 的 app 里（"远程 virgl"）。传输是通的（虚拟机里的 virpipe 走 TCP → broker → app），但用 vtest 协议版本 0 时，虚拟机的资源编号会和 Hyprland 在同一个渲染器里撞车；版本 3 要传共享内存的文件描述符，过不了 TCP。别的进程也没法往 app 的窗口里画（`OH_NativeWindow_CreateNativeWindowFromSurfaceId` 只在本进程有效）。2026-10-24 决定：I 保持无界面。另外，从宿主上用 `ohmarchy-vm ssh` 跑 `docker`，输出走 ssh 回来时可能挂住；从 D 的终端用不会。

详见 [docs/vm-own.md](docs/vm-own.md)。

### 路线 J：app 沙箱里的 Linux（不用 root）

**沙箱允许什么**：用一个探针 app（`native/xpmprobe`）把普通调试 app 能运行新代码的办法都试了一遍：

| 办法 | 结果 |
|---|---|
| 匿名的可读写可执行内存、先写再 `mprotect` 加执行、memfd 双重映射 | 不行：没有 `ALLOW_WRITABLE_CODE_MEMORY` 权限，XPM 报 "jit set mem violated" |
| `execve` 沙箱里没签名的程序 | 不行，`EACCES` |
| `execve` 打包在 HAP `libs/` 里的程序 | 不行：装出来是 0644，`EACCES` |
| `dlopen` 沙箱里没签名的 `.so` | 不行 |
| `execve` 系统自带的已签名程序 | 可以 |
| `dlopen` 签进 HAP 的 `.so` | 可以 |

也就是说，不用 root 的 app 只能运行打包时签进 HAP 的代码，而且只能用 `dlopen`。不能即时编译（JIT），不能运行时用 pacman 装东西，不能 exec 新程序；`fork` 是允许的。

**原型**：busybox 1.36.1 编成 `libbusybox.so`（`device/jloader/build-busybox.sh`，鸿蒙 clang/musl，命令都在进程内执行）；加载器 fork 出子进程，`dlopen` 它再调用 `main`。管道、`$$`、后台任务、命令替换、循环都能用（`native/jloader`）。现在它已经跑在 D 的显示 app 里：`native/app/entry/src/main/cpp/jl/bbload.cpp` 在 `start()` 时 fork 出一个单线程的"孵化"进程，并关掉继承来的所有文件描述符；默认关闭（9d4000c、9a6539d）。

**为鸿蒙 musl 重新编 Hyprland 全家**：D 的程序是按 glibc 编的，加载不进 app 的 musl 进程。不光是符号版本对不上，glibc 和 musl 在线程指针指向的线程控制块（TCB）布局也不一样。所以要针对鸿蒙的 musl 重新编，去掉 LLVM、Xwayland、libinput，目标约 25-40 MiB（D 那套是 272 MiB）。`device/userspace/`：

| 步骤 | 内容 | 状态 |
|---|---|---|
| 0 | 工具链：鸿蒙 SDK 的 clang 15 太老，编不了 C++26；用上游 clang 23 + 为 musl 编的 libc++ | 完成 |
| 1 | libffi、pixman、libdrm、libxkbcommon、wayland 1.23.1 | 完成（543a223） |
| 2 | Mesa 24.3.4，只要 virgl、不要 LLVM：约 16 MiB，带 vtest 通道 | 完成（c6ff963） |
| 3 | 一个共享的 C++ 运行库 `libc++_ohm.so.1`（1.9 MiB，改了名避免和系统的冲突），hyprutils 2.6 MiB、hyprlang 0.3 MiB；接下来是 C 的支撑库（cairo、pango、glib、字体），然后 aquamarine 和带 D 补丁、内置鸿蒙内核补丁的 Hyprland。Hyprland 0.56.2 现在已经能编译链接（去掉符号后 18 MiB），下一步是通过 D 的 app 在真机上加载 | 编好了（3da87ce、6065767、845dc1b），还没上真机 |

详见 [docs/no-root-routes.md](docs/no-root-routes.md)。

## 三、其它探索（已有结论或备选）

### 路线 A：鸿蒙 Linux 引擎里跑 Omarchy 的工具

**原理**：鸿蒙电脑自带一个官方的 Linux 引擎（融合开发引擎），其实是一个 openEuler 容器，只有终端没有图形界面。应用市场里有个第三方启动器"融合开发图像引擎"（`com.mikannqaq.developer.linuxEngine`），它往容器里装一个 X11 转接层，把每个 Linux 程序显示成一个单独的鸿蒙窗口。容器看到的 GPU 叫"Virtio-GPU Venus"。

**做了什么**：`linux-engine/install-omarchy-nvim.sh` 和 `install-omarchy-cli.sh` 装上 Omarchy 的 neovim 配置，以及 neovim、fastfetch、btop、lazygit 的静态 ARM64 版本（openEuler 没有 neovim 包）。GitHub 下载失败时自动换 `gh-proxy.com` 镜像重试；Omarchy 的主题软链接换成一个固定主题。

**限制**：每个程序都是单独的鸿蒙窗口，套一整个 Hyprland 桌面进去不合适。用 `uitest inputText` 往 XTerm 里打字，刚切到窗口时头几个字符会丢。详见 [docs/linux-engine-apps.md](docs/linux-engine-apps.md)。

### 路线 F：DevEco 模拟器里的 Aetherium

**原理**：不需要鸿蒙真机。DevEco Studio 在 Mac 上跑一个鸿蒙 7.0 "2in1"（PC）模拟器；模拟器里的 [Aetherium](https://github.com/AetheriumSimulator/qemu-hmos) app 在进程内跑 QEMU 10.1，纯软件模拟（TCG，因为模拟器不提供硬件虚拟化），启动原版 Omarchy 4.0.3 磁盘，用它自己的 7.2.3 内核，经 Limine 启动。画面由鸿蒙的 VNC 客户端 RemoteDesk 显示。

**打了什么补丁**：`emulator/lib/patch_aetherium.py` 修改固定版本的 Aetherium HAP：总是带上的 `-tpmdev emulator` 改成 `-L`；把走老式 MMIO 的 virtio-gpu（虚拟机会拒绝，状态 `0x83`）换成 `virtio-gpu-pci`；固件补齐到 64 MiB。已经向上游报告（#49-#53）。`emulator/10..60` 全程脚本化，包括通过 VNC 回答首次开机向导，以及开机自动登录进 uwsm（软件模拟下 SDDM 的登录界面 21 秒就被杀掉）。

**结果**：Hyprland 桌面能跑（CPU 渲染）；首次开机配置脚本跑用了 14 分钟，第一次手动跑用了 50 分钟（软件模拟下 mkinitcpio 很慢）。证明这套能跑通，但不是能日常用的桌面。详见 [docs/emulator-aetherium.md](docs/emulator-aetherium.md)。

### 路线 H：真机上的 Aetherium（已结束）

把路线 F 的 app 签成真机可装的版本（`device/sign-hap.sh`），用 root 装上。目标是测一个软件模拟的基准，再看能不能接上 HMV 硬件加速。结论：

- **软件模拟起不来**：QEMU 在 `tcg_region_init` 处 SIGABRT 退出，4 核 4 GB 和 1 核 2 GB 都一样。普通 app 不允许有"可写又可执行"的内存（路线 J 的探针直接证实了）。
- **这个 QEMU 没有 3D，也没有 120Hz**：`libqemu_full.so` 没链接 virglrenderer、EGL 或 Vulkan。
- **HMV**：`/dev/hmv` 不兼容 KVM，所有 KVM 的 ioctl 都返回 `ENOSYS`。它沿用 `0xAE` 这个魔数，但命令号是自己的；运行循环是 `libhmlibs.so.0` 里的 `hmv_join_actvpool_thread` / `hmv_wait_next_vmexit`。`su` 域的 root 进程能打开它，ioctl 失败的原因是 `ENOSYS`/`EINVAL`，不是 `EPERM`：对 root 来说没有权限关卡，只是接口没有公开。自己写一个加速器理论上可行，但没做，因为路线 I 已经用系统自带的 StratoVirt 跑起来了。
- **不用 root 的虚拟机服务是关着的**：测试 app（`native/vmtest`）用一个手写的接口声明就能编译、安装、加载模块、连上服务，但有权限的调用返回 `201 Permission denied`。`libvm_manager.z.so` 同时要求 `ohos.permission.MANAGE_VM` **和**调用方的 appIdentifier 在一个写死的 8 个值的名单里（OSEasy 和铠大师都在）。

详见 [docs/device-aetherium.md](docs/device-aetherium.md)、[docs/vm-api.md](docs/vm-api.md)。

### 路线 K：QEMU 解释模式（想法）

QEMU 的 TCG 解释器（TCI）不需要可执行内存。Aetherium 的 `libqemu_full.so` 是 JIT 版本（没有 `tci_*` 函数）。要做 TCI 版，也得按路线 J 的规矩编成 `.so` 签进 HAP。没开始，已降低优先级。

### 路线 L：鸿蒙浏览器内核里的 Linux（暂停）

**设想的原理**：一个普通 app（`webemu/app`，`com.ohmarchy.webemu`），里面放一个 ArkWeb 的 `Web` 组件，通过 `onInterceptRequest` 在 `https://routel.local/` 下提供网页、v86 模拟器、BIOS、内核和磁盘（磁盘支持按字节范围读取）。v86 在运行时把 x86 代码块编译成 WebAssembly。虚拟机里是 Arch Linux 32（i686，pacman 7.1，systemd 259，内核 6.19.11），由 `webemu/image/build-image.sh` 做出来，initramfs 只有 6 MB。网页里有 xterm.js 终端，还有一个探针，能判断浏览器引擎有没有 wasm 和 JIT。

**现状**：2026-10-25 Yao 决定暂停。从没在真机上跑过（那段时间屏幕一直被占用），所以还不知道 ArkWeb 会不会给第三方 app 开 wasm JIT。在电脑上的 Chrome 里：32-37 秒进 root 命令行，速度 400-1800 MIPS，编译了 928 个 JIT 模块、0 个失败。虚拟机里没有网络（pacman 要联网得另做转发）。详见 [docs/route-l-arkweb.md](docs/route-l-arkweb.md)。

### 路线 E：裸机

不要鸿蒙，Linux 直接装在硬件上。没开始，仓库里没有相关内容。

## 共性发现

### 鸿蒙的虚拟化

- **谁能跑虚拟机**：app 只能通过系统的虚拟机服务（`@hms:virtService.vmManager` / `@ohos.virtualization`）用虚拟化层，这个接口不在公开 SDK 里。`libvm_manager.z.so` 要求 `ohos.permission.MANAGE_VM`，并且调用方的 appIdentifier 必须在一个**写死的 8 个值的白名单**里。OSEasy 和铠大师在名单上，它们是应用市场的合作伙伴，自己没声明任何虚拟机权限。调试签名的 app 只会拿到 `201 Permission denied`。root 可以直接在 `/dev/hmv` 上起 StratoVirt（路线 I），但只有 app 才能拥有窗口。
- **整个系统同一时间只能跑一台虚拟机**：再起第二台会被拒绝，报 **401 "Not support vm multi-instance"**（2026-10-25 实测：鸿融的虚拟机在跑时，OSEasy 的 `createVm` 被拒）。起虚拟机前先 `pidof stratovirt` 看一下。
- **没有"增强服务"时，鸿融把正在运行的虚拟机显示成"已关机"**：鸿融要等虚拟机里的增强服务（vm-agent）报到以后，才把状态切成"运行中"。没装这个服务时，卡片一直显示"已关机"，普通的"关机"按钮也是灰的。关机请在虚拟机里面关（Omarchy 里按 Super+Esc 选 Shutdown），关完鸿融就会正常显示"已关机"；只有虚拟机没反应时才用强制关机。在虚拟机里关机和强制关机，在日志里走的是同一套状态（[docs/hongrong-whole-os.md](docs/hongrong-whole-os.md)，eb4646b）。OSEasy 有时明明没有虚拟机进程却被拒绝开机，原因还在查。另外鸿融的虚拟机一停，它的网桥也会被删掉。从 e0e0b7b 起，用鸿融挂进来的工具光盘把增强服务装进我们的开发者镜像就能用了：卡片显示"运行中"，普通"关机"按钮能正常关机。
- **HMV 的 ID 寄存器问题**：Linux 从 6.9 起启动时会读 `ID_AA64ISAR3_EL1`、`ID_AA64PFR2_EL1`、`ID_AA64FPFR0_EL1`，6.17 起还会再直接读一次 `ID_AA64PFR2_EL1`。按 Arm 的规定，不认识的 ID 寄存器应该读出 0，HMV 却把 vCPU 卡死了，至少 `ID_AA64PFR2_EL1` 是这样。现象是 EFI stub 之后就没动静了。这是二分法查出来的（合并提交 `0c5ade742e91`，然后是 GICv5 检测），已写成报告给华为：[docs/hmv-idreg-report.md](docs/hmv-idreg-report.md)。规避办法是内核补丁 `arm64.hmv_idreg_quirk`，B、C、G、I 都在用。
- **GIC ITS 报告 32 位事件号**：在 Linux 修复 `5a9d62555e71` 之前，这会让 MSI 中断全部失效。
- **GPU 后端**：鸿融给 Linux 虚拟机用的是 virgl → zink → 马良（只有 OpenGL）；Windows 类型的虚拟机（OSEasy、铠大师）用的是 `svga-pci` → D3D11 → DXVK → Vulkan。
- **刷新率**：屏幕跟着可见窗口"要"的帧率走，不要帧率的虚拟机 app 就停在 60Hz。到了 120Hz 时，`hidumper ... "composer fps"` 只看最近 384 个时间戳，可能会报高，要用 `hitrace` 数帧。
- **调试虚拟机**：OSEasy 和铠大师的虚拟机串口输出会写进 `/data/log/hwf_service/vmlog`（root 能读），鸿融的则丢进了 `/dev/null`。虚拟机的内存可以从 StratoVirt 进程里读出来（`memfd:stratovirt_anon_mem`）。

### 鸿蒙内核

没有 `/dev/dri`（显卡），没有 `/dev/kvm`。命名空间只有 ipc、mnt、net、pid、time、uts，没有 user 和 cgroup，cgroup 只有 v1。没有 Landlock，不允许 `PR_SET_KEEPCAPS`，进程之间不共享 `CLONE_FS`。root 的 SELinux `su` 域是宽松模式；普通 app（`normal_hap_attr`）可以连它的 unix socket、接收 dmabuf；`/dev/system_heap2` 是权限 666 的 dma-heap。系统调用上的差异：`splice` 返回 EPIPE，空路径的 `statx` 返回 EFAULT，阻塞的 `msgrcv` 不会被唤醒。读一个正在退出的进程的 `/proc/PID/cmdline` 可能永远转圈。鸿蒙的 grep 匹配不了用 NUL 分隔的 cmdline。完整的表：[docs/native-chroot.md](docs/native-chroot.md#hongmeng-quirks)。

### 签名和 XPM

- 测试机接受用 SDK 的 OpenHarmony 测试密钥签名、绑定本机 UDID 的调试 profile 的 HAP；正式版要用 AppGallery Connect 的证书。
- XPM（代码完整性保护）不给普通 app 可写又可执行的内存，也不让它运行没签名的代码：只有签进 HAP 的 `.so` 能加载，只有系统程序能 exec。所以 JIT 类的模拟器都走不通（H，以及 JIT 形式的 K），J 也只能按这个规矩来做。

## 需要有人在现场做的事

其余的都能远程做。来自 [docs/acceptance.md](docs/acceptance.md#on-site-what-needs-someone-at-the-machine)：

1. **用耳朵听声音**：把媒体音量调上去（之前测试时一直是 0），跑 `tests/audio/run.sh`，应该听到 10 声均匀的哔声；再用 `mpv --fs` 放个视频看口型对不对得上。
2. **用电源键熄屏亮屏**，开着"Omarchy (native)"做 20 次；超时熄屏那条路已经 20/20 通过。
3. **切换 Wi-Fi**：Firefox 开着网页，关 Wi-Fi 30 秒再打开，有条件的话换个网络再换回来；之后看 `tests/stability/soak.sh status`。
4. **用电池供电测功耗**：充到 80% 以上，拔电，固定亮度，在 5 种状态下各跑 30 分钟 `tests/perf/battery.sh`（只有鸿蒙桌面；原生桌面空闲；原生 + es2gears；鸿融空闲；鸿融 + es2gears）。
5. **Yao 在场时做一次计划内的重启**，验证开机自启服务能把原生桌面拉起来（`native/boot/`）。没有远程做，是因为上次重启后鸿蒙自己把鸿融从 1.3.1.80 换成了 1.1.1.103。

## 快速开始

命令和英文版一样，下面只说怎么用；完整命令见英文版的 ["Quick starts" 一节](README.md#quick-starts)，每条路线的细节和坑都在对应的 `docs/` 文档里。

下面按树的顺序排；A、K、E 没有快速开始。

- **路线 B**：现在的做法（7.2.12 内核 + `vmwgfx-oseasy`）：在 Arch 环境里用 `oseasy/vmwgfx-7.2/build.sh` 打驱动包，再用 `PROBE_DEFAULT=4 oseasy/probe/build.sh OUTDIR 内核包 驱动包` 做安装 ISO；把 `oseasy-probe.iso` 放进设备的"下载"，把 `omarchy-pure.img.zst`（由 `hongrong/pure/build-disk.sh` 做出）和 `oseasy/push-disk.sh` 放进 `/data/local/oseasy/`，然后按 [docs/demo.md](docs/demo.md#b-omarchy-in-oseasy) 在 OSEasy 里建虚拟机；`tests/demo/b.sh` 能全自动跑完。最早在 Fold 上的做法（Debian 6.1 内核，只有 EFI 帧缓冲）：在 Linux 主机上依次跑 `oseasy/10` 到 `oseasy/60`，再按 [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md#install-in-oseasy) 安装；设置在 `oseasy/config.sh`，输出在 `work/`；主机需要 bash、python3、curl、unzip、bsdtar、cpio、gzip、qemu-img、sfdisk/blkid、mtools、xorriso、kmod、make、带 aarch64 目标的 clang 和 hdc。
- **路线 C**：开发者镜像（设备上不要 root）：`hongrong/pure/build-disk.sh` 做盘，`hongrong/pure/make-qcow2.sh RAW OUT` 转 qcow2（会把 os_type 设成 1），放进文件管理的"下载"；鸿融里先删掉已有的虚拟机（它只能放一台），然后 本地文件 → 选 qcow2 → 打开 → 开始安装。和 deepin 共存的做法（Yao 的主虚拟机）：鸿融里装 deepin 25 并配静态地址，deepin 里用 root 跑 `hongrong/10-bootstrap-arch.sh USER PASSWORD`，重启后在 Arch 里跑 `~USER/hongrong/20-install-omarchy.sh USER`。
- **路线 G**（已结束，工具还在）：用 `tools/kaidashi/`（`wrap-iso.sh`、`installer/build.sh`、`probe.sh`、`kds-run.sh`）。
- **路线 D**：在鸿蒙电脑的 root shell 里，用 `native/` 的 `10`、`20`、`30` 建环境、装 Omarchy，`40-install-desktop.sh` 编打补丁的 aquamarine 和 Hyprland，`native/vtest/build-vtest.sh` 编 `vtest-broker`，`native/app/build.sh` 编显示 app；`omarchy desktop start` 后打开"Omarchy (native)"。`native/install.sh USER GPU_BIN_DIR` 一次做完（约 30 分钟），`native/reset.sh` 恢复干净镜像。要 Docker 得先起路线 I 的虚拟机。
- **路线 I**：宿主上以 root 运行 `sh /data/local/kaidashi/bin/ohmarchy-vm start|status|stop`（磁盘用 `tools/ownvm/prep-disk.sh` 准备）；D 的终端里直接 `docker run --rm hello-world`（docker gate 在跑的话，它会自己把虚拟机开起来）。
- **路线 J**：用 `device/jloader/build-busybox.sh`、`native/jloader/build.sh`、`device/jloader-run.sh`，Hyprland 全家的各步是 `device/userspace/build-stage{1,2,3}.sh`。
- **路线 F**：在装了 DevEco Studio 的 Mac 上依次跑 `emulator/10` 到 `emulator/60`。
- **路线 H**（已结束，工具还在）：用 `device/sign-hap.sh`、`push-inputs.sh`、`install.sh`，HMV 探针在 `device/hmv/`、`device/hmv-permtest.sh`，虚拟机服务探针在 `native/vmtest/`、`device/vmapi/probe-run.sh`。
- **路线 L**：见 [docs/route-l-arkweb.md](docs/route-l-arkweb.md#reproduce)。

## 目录结构

```
oseasy/              路线 B：Fold 上的流程（10..60）、安装 ISO（probe/）、虚拟机里的工具和诊断（guest/）、
                     驱动打包（vmwgfx-7.2/）、要 120Hz 的小窗口（vote120/）、每次运行的记录（runs/）
driver/
  vmwgfx-oseasy-7.2/ 鸿蒙 SVGA 设备的 vmwgfx，Linux 7.2 版（MMIO、fence 轮询、GEM_CLOSE、延迟回收、看门狗）
  vmwgfx-oseasy/     Debian 6.1 版
  efidrm/            Debian 6.1 上基于 EFI 帧缓冲的 simpledrm
hongrong/            路线 C：deepin 旁边装 Arch（10、20）、initcpio subroot 钩子、配置
  pure/              开发者镜像：build-disk.sh、make-qcow2.sh、os_type 文件头、testvm.sh
  edid/              120Hz EDID
  kernel/patches/    linux-aarch64 的两个补丁（ITS 中断数、hmv_idreg_quirk）
native/              路线 D：镜像、会话（arch.sh）、启动器（omarchy）、Arch 和 Omarchy 安装、一键安装/重置
  desktop/           aquamarine/Hyprland 补丁、鸿蒙内核补丁小库、声音转发、桌面脚本
  app/               显示 app（ArkTS + C++：ohdisp、gpu、audio、jl）、vtest-inapp.patch、sign/
  vtest/             vtest-broker 和宿主侧的 virgl_test_server
  boot/              开机自启（还没经过重启验证）
  vm/                给路线 C 桌面用的 waypipe 接收端
  jloader/ xpmprobe/ 路线 J 的加载器和 XPM 探针 app
  vmtest/            路线 H 的虚拟机服务探针
tools/ownvm/         路线 I：ohmarchy-vm、磁盘准备、虚拟机初始化、dropuid、上游 virtiofsd 编译
tools/kaidashi/ kaidashi/runs/   路线 G
emulator/ tools/emu/ tools/vnc/ tools/serial/   路线 F
device/              路线 H（签名、推送、安装、hmv 探针、vmapi）和路线 J（jprobe、jloader、userspace/）
webemu/              路线 L：镜像、网页、app
linux-engine/        路线 A 的安装脚本
tools/fold/ tools/ohdev/ tools/hongrong/ tools/kbuild/   设备辅助工具、内核编译和二分查找
tests/               路线 D 的验收测试（run-all.sh）、演示脚本（demo/）
docs/                所有文档，按路线分好的索引：docs/README.md
```

## 许可

本仓库的脚本、工具、app 代码和文档用 [MIT](LICENSE)。从 Linux 内核衍生出来的代码用 [GPL-2.0](LICENSES/GPL-2.0.txt)：包括 `driver/`（每个文件保留自己的 SPDX 标识，上游 vmwgfx 的文件是"GPL-2.0 OR MIT"）和仓库里所有的内核补丁。脚本下载或打补丁的上游项目沿用各自的许可。发布的磁盘镜像里包含 GPL 软件，对应的源码会随每个 release 一起发布。书面提供声明：每个 release 发布后三年内，其镜像中任何 GPL 或 LGPL 软件的完整对应源码均可应要求提供，收费不超过提供成本；请通过本仓库的 issue 提出。

# ohmarchy：在鸿蒙电脑上跑 Omarchy

[English](README.md) | 中文

让 [Omarchy](https://omarchy.org)（Arch Linux + Hyprland 桌面）在鸿蒙（HarmonyOS）电脑上跑起来。最早在 HUAWEI MateBook Fold（HarmonyOS 7.0）上开发，用的是 [riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image) 的 AArch64 版 Omarchy。现在的开发机（`ohdev`）是 HUAWEI MateBook 14 HM740（HarmonyOS 7.0.0.115）。

两种主要跑法：

- **原生**（路线 D）：不用虚拟机，Linux 程序直接跑在鸿蒙内核上，桌面显示在一个鸿蒙 app 里，可以到 120Hz。不能跑 Docker。
- **虚拟机**（路线 B、C）：在鸿融或 OSEasy 里跑完整的 Linux，Docker 等都能用。用的是打了补丁的 7.x 内核，补丁修的是华为虚拟化层（HMV）的 ID 寄存器问题。

## 路线

| 路线 | 在鸿蒙电脑上跑的是什么 | 状态 |
|---|---|---|
| **A. 鸿蒙 Linux 引擎**：[docs/linux-engine-apps.md](docs/linux-engine-apps.md) | Omarchy 的 neovim 配置和命令行工具，跑在鸿蒙自带的 Linux 引擎里，每个工具一个鸿蒙窗口 | 可用 |
| **B. OSEasy 虚拟机**：[docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) | 完整的 Omarchy 系统，跑在 OSEasy 虚拟机 app 里 | MateBook 14 上：7.2 内核加补丁能启动；GPU 渲染的画面能在窗口里显示（Mesa SVGA3D 硬件 3D），guest 出帧 120fps，但面板停在 60Hz（OSEasy 没投高刷票）；Omarchy 盘能装进去并冷启动，桌面还差一步 |
| **C. 鸿融虚拟机**：[docs/hongrong-whole-os.md](docs/hongrong-whole-os.md) | 完整的 Omarchy 系统，跑在华为的 Linux 虚拟机 app 里 | 原方案：借 deepin 的 6.6 内核，能进 Hyprland 桌面，virgl 加速。新进展：不带 deepin 的纯 Omarchy，用 7.2.12 补丁内核，冷启动加 3 次热重启都通过 |
| **D. 原生**：[docs/native-chroot.md](docs/native-chroot.md)、[docs/native-desktop.md](docs/native-desktop.md) | Arch Linux ARM 加 Omarchy 的软件包，直接跑在鸿蒙内核上，不用虚拟机 | Hyprland 桌面在鸿蒙 app 里以 120Hz 显示，用的是麒麟 GPU；78 个 app 测过，没有打不开的；声音、中文输入、剪贴板都能用；验收见 [docs/acceptance.md](docs/acceptance.md) |
| **E. 裸机** | 不要鸿蒙，Linux 直接装在硬件上 | 未开始 |
| **F. DevEco 模拟器里的 Aetherium**：[docs/emulator-aetherium.md](docs/emulator-aetherium.md) | 没有鸿蒙真机时，在 DevEco 的鸿蒙 PC 模拟器里，用打过补丁的 Aetherium（QEMU 软件模拟）跑完整的 Omarchy | 能进 Hyprland 桌面，纯软件模拟，很慢 |
| **G. 铠大师虚拟机**：[docs/vm-kaidashi.md](docs/vm-kaidashi.md) | 完整的 Omarchy 系统，跑在 sanway 的 Windows-on-ARM 虚拟机 app 里 | 7.2 内核能启动；底层和 OSEasy 一样；收尾中，经验并入 B |
| **H. 真机上的 Aetherium**：[docs/device-aetherium.md](docs/device-aetherium.md) | 和 F 一样的 QEMU，但跑在 ohdev 真机上，同时调查 QEMU 能不能用 HMV 硬件加速 | HMV 接口已经反汇编出来，是私有的 ioctl 接口，不兼容 KVM；软件模拟的基线测试和权限实测进行中 |

试过哪些路、为什么走不通：[docs/findings.md](docs/findings.md)。

<!-- progress:start -->
## 进展（每小时更新；最近一次：2026-10-24 08:25 PDT）

| 路线 | 正在做 | 最新结果 |
|---|---|---|
| B. OSEasy | 下一轮（约 09:30 PDT）：验证光标修好以后 Hyprland 能出画面，再测 120Hz、glmark2、热重启 | **120Hz 测通了**：屏幕上一直挂着一个小窗口（`ohmarchy-120`，不需要任何权限）要 120Hz，面板就从 60Hz 切到 120Hz，合成 120 帧。Hyprland 不出帧的原因是光标：显卡报的最大光标尺寸是 0，驱动已改成不用硬件光标。不做冒充 OSEasy 服务的代理 |
| C. 鸿融 | 让开发者镜像通过鸿融"导入 qcow2"的检查；30 分钟长测进行中 | **开发者镜像在鸿融里跑起来了**：7.2.12 内核、Omarchy 桌面、网络、麒麟 GPU 的 virgl 加速（glmark2 596 分）、Docker（hello-world、postgres、compose）、热重启都正常。没解决的：鸿融界面导入时不认我们的 qcow2；120Hz 的 EDID 读进去了，但 120Hz 模式被内核丢掉 |
| D. 原生 | 24 小时长测（到明天 02:52 PDT）；在鸿融里测"内核在虚拟机、画面在我们的 app" | 正式冷启动约 8 秒；桌面启动和重启从 12.5 秒降到 2.45 秒；A 到 G 验收总表写好了；远程画面方案准备好了（app 本身不碰网络） |
| G. 铠大师 | 已结束 | Linux 只能活在安装阶段，一关机就被删；显示和 B 是同一套 |
| I. 自建虚拟机 | 用系统的 StratoVirt 直接起虚拟机，配 virtio-gpu 加 virgl、120Hz EDID、Docker；排在 B 后面 | 共用的启动脚本补上了网卡收发线程参数（之前网络不通多半就是因为缺这两个）；画面上屏要么替换系统的一个库，要么走远程画面 |
| H. Aetherium | 第三方 app 不用 root 能不能调系统的虚拟机接口（补接口声明、做测试 app）；之后跑软件模拟基线 | 虚拟机接口是华为给合作伙伴的闭源模块，系统会检查调用方是谁（日志里有"不受信任的调用方"一类字样） |

ohdev 上用两把锁协调：`vm.lock` 管虚拟化层（同一时间只跑一台虚拟机），`screen.lock` 管前台屏幕；两样都不用的工作并行跑。
<!-- progress:end -->

## 快速开始

各路线的命令见英文版 [README.md](README.md) 里的 "Route X quick start" 各节，命令本身不需要翻译。每条路线的详细步骤和坑都写在对应的 `docs/` 文档里。

- 路线 B：在 Linux 主机上依次跑 `oseasy/10` 到 `oseasy/60`，然后按 [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) 在 OSEasy 里安装。
- 路线 C：见 [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md)，内核补丁在 `hongrong/kernel/`。
- 路线 D：在鸿蒙电脑的 root shell 里用 `native/` 下的脚本建环境、装 Omarchy 和桌面，再装 `native/app` 里的鸿蒙 app；一键安装和重置见 `native/install.sh`、`native/reset.sh`。
- 路线 F：在装了 DevEco Studio 的 Mac 上依次跑 `emulator/10` 到 `emulator/60`。
- 路线 G、H：见对应文档。

## 许可

`driver/` 派生自 Linux 内核，采用 GPL-2.0。脚本用到的上游项目保留各自的许可。

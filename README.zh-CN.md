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
## 进展（每小时更新；最近一次：2026-10-24 10:20 PDT）

| 路线 | 正在做 | 最新结果 |
|---|---|---|
| B. OSEasy | 下一轮（约 10:40 PDT，25 分钟）：装上修好的驱动，开机后在屏幕上实测：es2gears、切工作区、开应用、glmark2、热重启 | **查明了 Hyprland 为什么卡住**：前 166 帧都正常，之后有一帧在等显卡"画完了"的信号，可这个信号永远不来。原因是这块虚拟显卡从不产生中断，而驱动只在中断里推进这个信号。修法：用一个 1 毫秒的定时器代替中断（060fc92），还没实测 |
| C. 鸿融 | 等排队：用改成鸿融格式文件头的镜像走鸿融自己的"导入"；实测 120Hz 下屏幕上的帧数 | 开发者镜像在真正的鸿融虚拟机里全项通过：桌面、网络、麒麟 GPU 加速（glmark2 596 分）、Docker、热重启、30 分钟长测；显卡输出跑在 120Hz |
| D. 原生 | 最后一轮应用启动全量测试（78 项）；24 小时长测到 10 月 25 日 17:52 PDT | **原生桌面里能用 Docker 了**：经路线 I 的虚拟机，`docker run`、compose、lazydocker 都正常（1d70b74）。测试脚本改成按窗口地址关窗，Firefox 不再以为自己崩溃了（a3c8c89）。上一轮 74 项通过，0 项失败 |
| I. 自建虚拟机 | 下一轮（约 11:05 PDT）：把个人目录共享进虚拟机，测两边的文件归属、带目录挂载的 compose、符号链接能不能越界 | **作为后台验收通过**（ec76d4b）：一键启停、原生桌面经 ssh 用 Docker、端口映射、内存回收（释放 3GB 约 6 秒就还给鸿蒙；8GB 的虚拟机空闲时只占约 1.2GB）。原生桌面的 `/home/builder` 已经用同样的路径共享进虚拟机（ba66705、74d3b4b） |
| H. Aetherium | 正在用两把锁跑原版 Omarchy 镜像的软件模拟基线：建虚拟机、4GB 开机，测开机时间、帧率、刷新率、宿主 CPU 和温度 | 有 root 时能直接打开虚拟化设备，系统权限不拦；自己写虚拟机程序唯一的门槛是 StratoVirt 不公开的调用接口，决定不去逆向（0d27517、740663d）。不用 root 自建虚拟机这条路，对第三方仍然是关着的 |
| G. 铠大师 | 已结束 | 和 B 同一套显卡；Linux 只能活在安装阶段 |

ohdev 上用两把锁协调：`vm.lock` 管虚拟化层（同一时间只跑一台虚拟机），`screen.lock` 管前台屏幕；两样都不用的工作并行跑。在 ohdev 上启动或结束进程也要先拿 `vm.lock`：10:02 有个测试误杀了别的虚拟机的共享目录进程，没造成影响，之后定了这条规矩。
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

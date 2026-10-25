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
## 进展（每小时更新；最近一次：2026-10-25 10:18 PDT）

| 路线 | 正在做 | 最新结果 |
|---|---|---|
| B. OSEasy | 下一轮：开着 `AQ_TRACE=1` 跑 20 分钟压力测试，验证"帧完成看门狗"（不卡、而且看门狗确实触发过才算过） | 开调试追踪约 160 帧就卡住，是一个真实存在的竞态，只是追踪把它放大了：设备没有中断，"这一帧显示完了"的通知偶尔会丢。修法：每 1 毫秒的检查里，一帧挂起超过 50 毫秒就替它补上完成通知（61e5998）。之前已做到：GPU 应用能出画面，带 GPU 负载跑 4 小时 24 分钟没出问题，从 OSEasy 外面上不了 120Hz。对比表全部填完：测了鸿融里的应用启动时间（ce30bf8）；系统不允许同时开第二台虚拟机（9e49192） |
| C. 鸿融 | 下一轮（B 的测试之后）：用鸿融界面导入改好"系统类型"的镜像，测 120Hz 下屏幕上的实际帧数，然后恢复主虚拟机，让它开着 | **查清了鸿融为什么拒绝导入**（c9ddc15）：鸿融导入时会读磁盘文件头最后一个字节记的"系统类型"，我们的是 0，被当成"磁盘损坏"；它自己的盘是 1。生成文件头的脚本已经改成写 1。主虚拟机已经用今早的备份恢复（校验一致），开机能正常回到登录界面。鸿融里应用启动（第二次起）：终端 0.08 秒、文件管理器 0.6 秒、Chromium 0.8 秒、Obsidian 1.2 秒 |
| D. 原生 | 下一轮：熄屏亮屏 20 次、记电池读数、测声音电平 | **24 小时长测通过**（c6a0372）。两个安全问题查到底，都是平台限制、已有缓解（6448809）：Chromium 的沙箱要用一个鸿蒙内核不支持的特性，所以默认浏览器用 Firefox；su 没法切到更窄的 SELinux 域 |
| I. 自建虚拟机 | 完成 | **共享目录权限问题修好了**（2235eaf）：换成自己编的上游共享程序 virtiofsd 1.14.0，新建文件 0644、目录 0755，chmod 也能用，照样以普通用户身份运行、没有特权；现在默认用它（设 `OVM_VIRTIOFSD=system` 可以退回） |
| J. 在 app 沙箱里跑 Linux（不用 root） | 第 1c 步：能不能加载沙箱里没签名的程序库；能不能运行打进 app 安装包 libs/ 里的程序（Termux 的做法） | 第 1 步：app 拿不到可执行内存。第 1b 步：自己放进沙箱、没签名的程序一律不让运行（Permission denied），系统签名的程序可以，所以直接从沙箱跑 Arch 的程序行不通。如果 1c 里打进 libs/ 的那项能过，就可以在打包时把整套 Linux 程序放进签名的安装包里（只是运行时不能用 pacman 装新软件） |
| L. 在浏览器引擎里跑 Linux（不用 root） | 正在 ohdev 上测试 | 用网页模拟器 v86 在鸿蒙浏览器组件里跑 32 位 Arch Linux（`webemu/`，56dbf24）。普通 app 拿不到可执行内存，WebAssembly 可能只能解释执行，速度还要实测 |
| H. Aetherium | 已结束 | 不用 root 的话，Aetherium 在真机上跑不了（虚拟化层不对第三方开放，软件模拟拿不到可执行内存） |
| G. 铠大师 | 已结束 | 和 B 同一套显卡；Linux 只能活在安装阶段 |

ohdev 上用两把锁协调：`vm.lock` 管虚拟化层（同一时间只跑一台虚拟机），`screen.lock` 管前台屏幕；两样都不用的工作并行跑。在 ohdev 上启动或结束进程也要先拿 `vm.lock`。
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

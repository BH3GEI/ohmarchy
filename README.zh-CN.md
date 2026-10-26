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
| **L. 鸿蒙浏览器内核里的 Linux**：[docs/route-l-arkweb.md](docs/route-l-arkweb.md) | 普通应用里用 ArkWeb 网页跑 v86 模拟器（x86，翻译成 WebAssembly 执行），里面是 Arch Linux 32（有 pacman 和 systemd），不要 root，也不要虚拟机权限 | 2026-10-25 决定暂停。镜像、网页和签好名的应用都做好了，在电脑上的 Chrome 里 32 秒进到 root 命令行；没上真机（屏幕一直被别的测试占着），所以还不知道 ArkWeb 在第三方应用里能不能用 WebAssembly 即时编译 |

试过哪些路、为什么走不通：[docs/findings.md](docs/findings.md)。

<!-- progress:start -->
## 进展（每小时更新；最近一次：2026-10-25 20:24 PDT）

| 路线 | 正在做 | 最新结果 |
|---|---|---|
| B. OSEasy | 今天收尾 | **演示彩排通过，从没有虚拟机开始约 3 分钟**（73afc8e）：建虚拟机点几下约 1.5 分钟，安装 61 秒，重启后 6 秒进 Hyprland，es2gears 和切工作区屏幕上都是 60 帧，终端 0.08 秒、文件管理器 0.6 秒、Chromium 0.8 秒。第一次被拒，是因为鸿融主虚拟机上次在虚拟机里面关的机，鸿融 app 还以为它在跑；用鸿融界面开一次、再强制关机，状态就复位了。和别的虚拟机同时跑：不行（401，4f8f079） |
| C. 鸿融 | 离线：做一版新镜像，把 120Hz 的显示参数和 glmark2 都放进去 | **演示 C2 彩排通过：3 分 41 秒**（6df8c0d）：Yao 的主虚拟机，登录、终端加 fastfetch、Chromium 上网、切工作区。开发者镜像能用鸿融自己的界面导入（"系统类型"字节已改对，c9ddc15）；虚拟机里按 120Hz 画，鸿融全屏显示只给 60Hz |
| D. 原生 | 这个会话用量到上限了，10 月 26 日 19:00 PDT 恢复 | **演示彩排通过：全程 80 秒，切工作区 119 帧**（635265e）。彩排中修了：Omarchy 菜单关掉后还残留在画面上（现在改成整屏重绘，空闲时 CPU 还没复查）；启动命令让 ssh 一直不返回；每重启一次就多留一个后台进程。之前：熄屏亮屏 20 次全过，24 小时长测通过 |
| I. 自建虚拟机 | 完成 | **演示彩排通过：91 秒全部 PASS**（f62265a）：虚拟机 10 秒起来，hello-world、带目录挂载的 compose 服务、建出来的文件是 0644 并归 builder，最后正常关机。从宿主上用 `ohmarchy-vm ssh` 跑 `docker`，输出一走 ssh 就会挂住，演示里把输出重定向掉了（从 D 的终端走 docker context 没有这个问题）。共享目录 0660 的问题已经用上游 virtiofsd 1.14.0 修好（2235eaf） |
| J. 在 app 沙箱里跑 Linux（不用 root） | 这个会话用量到上限了，10 月 26 日 19:00 PDT 恢复；接下来编 C 的支撑库（cairo、pango、glib、字体那一套），再编 aquamarine 和带 D 补丁的 Hyprland | busybox 已经能在 D 的显示 app 里跑（9d4000c）。用鸿蒙的 musl 重新编：第 1 步 Wayland 底层（543a223）；第 2 步 Mesa，只要 virgl、不要 LLVM，16MB，带着 D 的 app 已经在用的 vtest 通道（c6ff963）；第 3 步工具链：clang 23 加一个共享、改了名的 C++ 运行库 `libc++_ohm.so.1`（1.9MB），hyprutils 2.6MB、hyprlang 0.3MB 已经编好（3da87ce、6065767） |
| L. 在浏览器引擎里跑 Linux（不用 root） | 已按决定暂停 | 用 v86 在鸿蒙浏览器组件里跑 32 位 Arch Linux（`webemu/`，56dbf24、561eb4b），没在 ohdev 上跑过。在电脑上的 Chrome 里：约 32 秒进到 root 提示符，速度 400–1800 MIPS |
| H. Aetherium | 已结束 | 不用 root 的话，Aetherium 在真机上跑不了（虚拟化层不对第三方开放，软件模拟拿不到可执行内存） |
| G. 铠大师 | 已结束 | 和 B 同一套显卡；Linux 只能活在安装阶段 |

ohdev 上不再用锁（2026-10-25 取消）：要用屏幕直接用。虚拟化层同一时间仍只能跑一台虚拟机，起别的虚拟机前先关掉鸿融的虚拟机。
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

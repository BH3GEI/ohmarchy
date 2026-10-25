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
## 进展（每小时更新；最近一次：2026-10-24 21:18 PDT）

| 路线 | 正在做 | 最新结果 |
|---|---|---|
| B. OSEasy | 今天收尾了。还剩两项等 Yao 决定：鸿融里的应用启动时间（鸿融开机停在登录界面，要登录才能测）；和别的虚拟机同时跑（虚拟化层同一时间只能跑一台） | **修好的版本带 GPU 负载一共跑了 4 小时 24 分钟没出问题**（先 77 分钟，再 3 小时 7 分钟，后一轮检测窗口放宽到 50 毫秒；75a22f2、38539b4）：内核没有任何报错，心跳一直没断，全程每秒 120 帧送到宿主、屏幕上合成 60 帧。修之前的两次分别在 38 分钟和 51 分钟卡死。原因（a145d58）：驱动一看到命令完成就马上释放那块内存，宿主却还没写完，结果把内存池写坏了；现在改成完成后先等 5 毫秒再释放。窗口放宽到 50 毫秒也一次晚写都没抓到，所以这个原因是推断，没有亲眼看到；正式版保持等 5 毫秒。**从 OSEasy 外面没法让屏幕上 120Hz**（f456da6）：用 1x1、什么都不画的小窗口申请，屏幕确实切到 120Hz，但系统改用 GPU 合成，虚拟机画面每秒只剩 35–47 帧上屏；切回 OSEasy 窗口，屏幕又回到 60Hz。OSEasy app 自己冷启动 1.1–1.9 秒（a1c47a7） |
| C. 鸿融 | 暂停（这条线的会话从 09:14 PDT 起就没动）：用改成鸿融格式文件头的镜像走鸿融自己的"导入"；实测 120Hz 下屏幕上的帧数 | 开发者镜像在真正的鸿融虚拟机里全项通过：桌面、网络、麒麟 GPU 加速（glmark2 596 分）、Docker、热重启、30 分钟长测；显卡输出跑在 120Hz |
| D. 原生 | 24 小时长测到 10 月 25 日 17:52 PDT | 应用启动：78 项里 74 项通过，0 项失败，95% 在 1.13 秒内。Docker、compose、挂载个人目录，经路线 I 的虚拟机都能用 |
| I. 自建虚拟机 | 今天收尾了 | 已知限制（6340109）：经共享目录建出来的文件权限是 0660/0771，是华为自带的共享程序定死的；`--mapped-perm` 只改虚拟机里看到的权限，`--posix-acl` 跟用户映射冲突，chmod 也不起作用。原生里自己建的文件是正常的 0644，文件也都归你的用户，所以原生方案不受影响 |
| H. Aetherium | 已结束（81cb74d、5a6b00a） | **不用 root 的话，Aetherium 在真机上跑不了**：虚拟化层不对第三方开放；软件模拟一开机就在 `tcg_region_init` 崩掉（4 核 4GB、1 核 2GB 都一样），推断是系统不给 app 可执行内存（没抓到直接证据）。用 root 去跑软件模拟的办法评估后不做，因为 root 下路线 I 已经能用硬件加速跑了 |
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

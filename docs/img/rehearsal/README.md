# 彩排记录 2026-10-28

按 [docs/demo-operator.zh-CN.md](../../demo-operator.zh-CN.md) 在 ohdev 上彩排了三段：原生桌面 + Docker、新原生沙箱、鸿融。OSEasy 段没有在现场跑（现场读不到 ISO），用当天上午回归时的截图代替。

- 录制方式：ohdev 后台以 nice 19 每约 1.1 秒执行一次 `snapshot_display`，只读屏幕，不注入输入，共 1109 张。设备上没有命令行录屏工具，鸿蒙自带的录屏会在屏幕上显示悬浮条，因此没有用。
- 操作方式：用 uitest 注入按键和点击，不是真人操作。uitest 一次最多注入 3 个键；输入大写字母不可靠。
- 视频：每段一个，另有一个全程视频；沙箱 4.4–4.10 的重录单独成一个视频。都由截图按真实时间戳合成，约 1 帧/秒，看不出 120 Hz 的流畅度。视频和原始截图保存在 Mac 本地，不进仓库。
- 本目录是挑出来的截图，文件名格式为 `<段>-<手册步骤>-<说明>.jpeg`，步骤号 `x` 表示手册里没有、本次加测的步骤。

## 第 1 段：原生桌面 + Docker（10:39–10:43，D 操作）

| 步骤 | 结果 | 截图 |
|---|---|---|
| 1.1–1.2 | app 已在运行，从 Dock 切到前台，最大化 | [1-1.2](1-1.2-native-desktop.jpeg) |
| 1.3 fastfetch | Kirin X90，Linux 6.6.0-hongmeng，Hyprland 0.56.2，120 Hz | [1-1.3](1-1.3-fastfetch.jpeg) |
| 1.5 Firefox | 约 10 秒，打开新标签页 | [1-1.7](1-1.7-firefox-files.jpeg) |
| 1.6 Omarchy 菜单 | 出现，按 Esc 关掉 | [1-1.6](1-1.6-omarchy-menu.jpeg) |
| 1.7 文件管理器 | 打开主目录 | [1-1.7](1-1.7-firefox-files.jpeg) |
| 1.8 `docker run --rm hello-world` | 35 秒内出现 "Hello from Docker!" | [1-1.8](1-1.8-docker-hello.jpeg) |
| 1.9 | hello-world 结束后约 18 秒，Docker 虚拟机自行关机，`pidof stratovirt` 为空 | — |

**与手册不符：** ohdev 上装的原生 app 是旧版，Super 键对应右 Alt，不是手册写的 Alt+Shift；按 Alt+Shift+Return 没有反应，按右 Alt+Return 才打开终端。监督决定：汇报前不重装这个 app。手册第 1 段和现场操作都改用右 Alt；沙箱是另一个 app，仍用 Alt+Shift。

## 第 2 段：新原生沙箱（10:44–10:50，D 操作）

| 步骤 | 结果 | 截图 |
|---|---|---|
| 4.1 双击图标 | 约 25 秒后全屏出现桌面，重录时约 24 秒（手册原来写的是 16–19 秒） | [2-4.1](2-4.1-sandbox-desktop.jpeg) |
| 4.4 `sudo pacman --sync --noconfirm cowsay`，再 `cowsay hello` | 第一次录制失败：sudo 报 "unable to allocate pty"（沙箱里没有 /dev/pts）。D 修复后在 11:06–11:10 重录：输入密码后装上 cowsay，`cowsay hello` 出现那头牛 | [2-4.4](2-4.4-cowsay.jpeg)（重录） |
| 4.5 `ls /storage /system` | 两个目录都报 No such file or directory | [2-4.6](2-4.6-fence-demo.jpeg) |
| 4.6 `curl -m 3 http://127.0.0.1:22` | 退出码 7，连接不上 | [2-4.6](2-4.6-fence-demo.jpeg) |
| x `ohm-fence-demo` | 连主机的 Wi-Fi 控制 socket：EACCES (Permission denied)；连沙箱内绑定的名字：connected | [2-4.6](2-4.6-fence-demo.jpeg) |
| 4.7 | Ctrl+Alt+Esc 可以最小化；在 Dock 图标上长按出现 "Reset Linux"，点击后先弹确认框 | [菜单](2-4.7-dock-reset-menu.jpeg)、[确认框](2-4.7-reset-confirm.jpeg) |
| 4.8 Reset | 第一次录制时画面没有恢复：后台重置成功，但 app 一直停在重置前的最后一帧（只在 app 开着时从 Dock 重置才出现）。D 修复后重录：从 11:07:50 起，Ctrl+Alt+Esc 最小化 → Dock 长按 → Reset Linux → 确认 → Reset，约 50 秒后出现新桌面，中间 app 自动重启一次，屏幕会黑一下 | [重置中](2-4.8-resetting.jpeg)、[新桌面](2-4.8-after-reset.jpeg)（重录） |
| 4.9 `cowsay hi` | 重录时显示 command not found（第一次录制因 4.4 失败而跳过） | [2-4.9](2-4.9-not-found.jpeg)（重录） |
| 4.10 关闭窗口 | 从 Dock 菜单关闭后约 10 秒 Linux 停止，`ohm-sandbox status` 为 stopped | — |

**注入工具的问题（真人操作没有）：** 大写字母 S 注入后变成 ","；在 sudo 的密码提示处，注入的 Ctrl+C 不起作用，接着重输的命令被 sudo 当成了一次错误密码。

## 第 3 段：鸿融（10:51–10:57，C 操作）

| 步骤 | 结果 | 截图 |
|---|---|---|
| 2.1 双击桌面图标 | 约 4 秒打开虚拟机页，显示"已关机"，已使用 7 GB | [3-2.1](3-2.1-hongrong-off.jpeg) |
| 2.2 开机 | 26 秒内进入桌面，不需要输密码 | [3-2.2](3-2.2-desktop.jpeg) |
| 2.3 fastfetch | KVM Virtual Machine (StratoVirt)，Virtio 1.0 GPU，2160x1440 120 Hz，Omarchy 4.0.6-1，Linux 7.2.12-1.2-aarch64-ARCH，Hyprland 0.56.2，793 个包 | [3-2.3](3-2.3-fastfetch.jpeg) |
| 2.4 Chromium 打开 omarchy.org | 正常，没有出现 "Restore pages?" | [3-2.4](3-2.4-chromium.jpeg) |
| 2.5 Super+2 / Super+1 | 正常 | — |
| x `sudo id` | 输入测试密码后得到 uid=0 | [3-x-sudo](3-x-sudo.jpeg) |
| x 锁屏 | 运行 `omarchy-system-lock`，按一下 Shift 出现 "Enter Password"，输入测试密码后解锁 | [3-x-lock](3-x-lock-screen.jpeg) |
| 2.6 把鸿融切到前台 | 卡片显示"运行中"，"关机"和"暂停"可以点 | [3-2.6](3-2.6-running.jpeg) |
| 2.7–2.8 关机 | 点击后 14 秒 stratovirt 退出，卡片显示"已关机" | [3-2.8](3-2.8-off.jpeg) |

**与手册不符：**
- 手册 2.3 写的内核是 7.2.12-1.1，现在是 1.2。
- 用 uitest 点击，切换不了 Hyprland 里的窗口焦点（Chromium 打开后点终端，按键仍然进了 Chromium），改用 Super+方向键才切过去。真人用鼠标点击不受影响。
- 锁屏界面有时截图是全黑的（2026-10-28 早些时候），这次截到了。

## 第 4 段：OSEasy（未在现场跑）

现场读不到 ISO，这一段没有跑，用当天上午回归时的截图代替。

## 收尾

三段结束后，`pidof stratovirt` 为空；屏幕恢复成开始时的样子：最前面是 OSEasy 的导入页，原生 app 最小化。

## 待办

1. ~~4.4、4.8 重录~~ 已完成（D，11:06–11:10），截图已替换。
2. ~~修改手册~~ 已改 docs/demo-operator.zh-CN.md：第 1 段改用右 Alt，注明原生演示版和新原生沙箱是两个 app；4.1 耗时改为 16–30 秒；2.3 内核改为 7.2.12-1.2；注入工具的限制在第 1 段说明里一句带过。

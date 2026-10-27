# 给 OSEasy 的需求清单（Linux 客户机支持）

面向 OSEasy（com.oseasy1.ohvm）团队。我们在鸿蒙 PC 的 OSEasy 上跑了 Arch Linux +
Hyprland（Omarchy）桌面，整体可用，但受限于 OSEasy 目前只按 Windows 客户机设计。以下是
按重要性排序的需求；满足其中几条，就能让 OSEasy 正式、顺畅地支持 Linux 客户机。

## 1. 正式支持 Linux 客户机的生命周期（最重要）

现状：Linux 客户机装好后，OSEasy 永远显示"正在安装 Windows 11…"，因为它靠 Windows guest
agent 的"安装完成"信号判断状态；Linux 不发这个信号。虚拟机一旦关闭，界面只给"再次安装"
（会**清空磁盘**）或"取消"，**没有"开机"**。于是一台装好的 Linux 虚拟机无法再次启动到原来的
系统，每次都得重装。

请求：
- 为 Linux 客户机提供正常的 **"开机 / 关机"** 按钮，启动现有磁盘，而不是强制走安装流程。
- 不要在"再次安装"之外就把磁盘判成"安装失败"；允许"已安装、已关机、可再次开机"这个状态。
- 不要在启动安装介质前清空系统盘，除非用户明确选择重新安装。

## 2. Linux 版 guest agent，或公开的协议

OSEasy 通过 **virtio-serial 通道**上的 **protobuf RPC** 和 Windows guest agent
（`agent_service.exe`，源码树 `vmagentservice`）通信，判断安装完成、心跳、分辨率、网络与
文件共享等。消息分两个 proto 包：`Guest.protobuf.link`（传输/握手：`Handshake{connectionMode,
clientName, authString}`、`Call{callID, methodID, parameters, async}` 这个 RPC 封装、
`CapInfo`/`CapSet` 能力协商）和 `Guest.protobuf.GuestAgent`（`NetInfo`/`NicInfo`/`DNSInfo` 网络
共享、`UserProfileInfo` 文件共享、`ResolutionInfo`、`TimeInfo`、`UpdateInfo` 等）。Windows 侧
把串口端口暴露为命名管道 `\\.\PIPE\VM_SYSTEM_SERVICE_COMMU`（命令）与 `\\.\PIPE\WIN_EVENT`
（事件）；Linux 侧对应 `/dev/vportNpX`。我们已把这套协议逆向出来并记录在本仓库
`docs/oseasy-agent-protocol.md`（早先文档里"tcp://172.16.100.2"的说法不准确：实际主通道是
virtio-serial，172.16.100.x 只是 tap 网里 guest 的地址）。

请求（二选一即可）：
- 提供 **Linux 版 guest agent**；或
- **公开这条协议**（消息格式、端口、握手），让第三方 Linux 镜像能自己上报"安装完成"和心跳，
  从而被 OSEasy 当作正常虚拟机管理。

我们已自行把协议逆向出来（见 `docs/oseasy-agent-protocol.md`），正在据此做一个最小的、
兼容的 Linux agent（只发握手 + install_complete + 心跳，让 OSEasy 把虚拟机当作"已安装、可开机"
来管理）。但这依赖逆向结果，OSEasy 升级协议就可能坏掉；我们不希望靠冒充厂商服务来绕过它——
**官方公开协议或提供 Linux agent 才是正途**。

## 3. 高刷新率

现状：OSEasy 的显示设备（SVGA）本身不向客户机协商高刷，stock 的 vmwgfx 只跑 60Hz。我们
**给 vmwgfx 打了补丁**（强制 120Hz 模式），客户机实测已能跑到 **2100x1511@120**（Hyprland
与 fastfetch 都报 120Hz）——但这是我们自己改驱动绕出来的。

请求：在显示设备侧**原生支持 120Hz（及更高）**（EDID / 模式列表 / 刷新率协商），让第三方
Linux 客户机不必自己改驱动就能用上高刷。

## 4. 虚拟机窗口支持全屏 / 最大化（当前只给固定浮动窗）

现状（已实测坐实）：在鸿蒙 2in1 PC 上，OSEasy 的虚拟机窗口是一个**固定尺寸的浮动窗**——
标题栏只有"最小化 / 关闭"，**没有最大化按钮**，也**不能拖拽边框缩放**，没有任何进入全屏的
入口。实测：
- 窗口管理器（WindowManagerService）里，VM 窗口是 `WINDOW_MODE_FLOATING`（Mode 102），
  而系统自身的窗口都是 `WINDOW_MODE_FULLSCREEN`（Mode 1）——**设备本身支持全屏**
  （`const.product.devicetype = 2in1`）。
- 分别从右边缘、右边缘外、右下角、下边缘拖拽四次，窗口尺寸纹丝不动。
- 对应到实现：`setSupportedWindowModes` 只给了 `FLOATING`、`setWindowTitleButtonVisible`
  藏掉了最大化键、`setResizeByDragEnabled` 关掉了拖拽缩放。

后果：Linux 桌面只能挤在一个小浮动窗里，铺不满高分屏，体验受限。

请求：
- 为 Linux 虚拟机窗口**开放最大化 / 全屏**（把 `FULL_SCREEN` 加进 `setSupportedWindowModes`、
  显示最大化按钮），并**允许拖拽缩放**；
- 窗口尺寸变化时，把新尺寸作为分辨率偏好下发给虚拟机显示设备（SVGA pref rect），让客户机
  按窗口大小**重新渲染**，而不是把小分辨率拉伸（避免模糊）。

## 5. 共享文件夹对 Linux 客户机可用（当前完全读不了）

现状（已实测坐实）：OSEasy 的 virtiofs 共享文件夹（宿主"文件管理器/Documents"）在普通
Linux 客户机里**根本读不了**。vm_manager 启动 virtiofsd 时**没有带 `--passthrough-fs`**，
所以它跑在 `virtual_fs`（按 share_id 映射）模式，而不是透传模式。表现：
- 宿主 virtiofsd 日志：`init_virtual_fs: share_id: 35243` 之后 `ERROR … error: -19 (No
  such device), opcode 27`（连根目录的 OPENDIR 都 ENODEV）；
- 客户机：`virtiofs virtio3: discovered new tag: shared_dir`（设备和 tag 都认），但一访问
  就 `virtio-fs: response too short (0)`，`ls` 失败，挂载点是空的。

这套 `virtual_fs`/share_id 模式需要 **厂商的 guest agent 通过 cmd-socket 注册 share** 才会
建出目录，光靠 Linux 的 `mount -t virtiofs` 绕不过去；而 virtiofsd 的启动参数由 vm_manager
决定，第三方改不了。（同样的现象我们在自建 virtiofsd 时见过，加上 `--passthrough-fs` 即可，
见本仓库 `docs/vm-own.md`。）

后果：Linux 客户机在 OSEasy 下**没有任何可持久化的存储**——系统盘 vda 每次"再次安装"被清，
共享文件夹又读不了。于是装好的 Linux 系统无法保存状态，每次都只能从头来。

请求（择一即可）：
- vm_manager 启动虚拟机 virtiofsd 时带上 `--passthrough-fs`（或提供一个开关），让 Linux
  客户机也能像 Windows 那样读写共享文件夹；或
- 公开那套 `virtual_fs` 的 share 注册协议（cmd-socket 消息格式），让 Linux guest agent 能
  自行注册并访问 share；
- 并请保留共享文件的 uid/gid 和权限位。

## 5. （可选）镜像相关

- 支持**更大的安装 ISO**（我们需要把系统镜像打进 ISO 时会超过常见限制）。
- 提供**"导入已有磁盘镜像"**的入口（直接把一个 qcow2 / raw 作为虚拟机磁盘启动），便于分发
  预装好的 Linux 系统，而不必走安装流程。

## 6. 虚拟化引擎在旧系统版本上的兼容性问题

以下两条在较旧的鸿蒙 PC 系统（实测 **7.0.0.32**）上复现；较新的版本（实测 7.0.0.115）没有。
公开发行的镜像会落到各种系统版本上，所以这两条对第三方 Linux 镜像能否"开箱即用"很关键。

### 6.1 旧版 stratovirt 的 virtio-pci feature select 崩溃

现象：在 7.0.0.32 上，用较新的 Linux 内核（7.2.12）启动虚拟机，内核在 virtio-pci 初始化时
（约开机 0.76 秒）崩溃，整个 vcpu 挂死：
```
virtio-pci 0000:00:05.0: enabling device
ERROR virtio_pci.rs: Failed to write common config ... Invalid features select 0x2
ERROR machine/lib.rs: Failed to mmio write addr 80020c00c ...
ERROR hm_cpu.rs: VCPUHmv emulate error
```
原因：新内核的 virtio-pci modern 驱动会写 device_feature_select=2（协商 64–95 位扩展特征），
而这版 stratovirt 只支持 select 0/1，对 select 2 返回错误，HMV 把这个失败的 MMIO 写升级成了
**致命的 vcpu fault**。同一份 ISO 在 7.0.0.115 上能正常装到桌面。

我们的退路（已做）：给内核打补丁，让 virtio-pci modern 默认只用 feature select 0/1（见本仓库
内核补丁 0003 / commit `139aa77`）。但更稳妥的是**引擎侧对 select 2/3 容错**（忽略或正确处理，
不要升级成致命 fault），这样任何较新的 Linux 内核都能起。

### 6.2 vm_manager 用 appIdentifier 白名单而非 MANAGE_VM 鉴权

现象：在 7.0.0.32 上，`libvm_manager.z.so` 不检查 `MANAGE_VM` 权限，而是用库里**硬编码的
一份 appIdentifier 白名单**（约 14 个）来决定谁能建虚拟机。结果 OSEasy 在名单里能用，其它
应用（例如另一个虚拟机应用）不在名单里，每次 createVm 都被判 `TokenID invalid / permission
denied`。7.0.0.115 则按 `MANAGE_VM` 鉴权，不在名单里的应用也能用。（详见本仓库
`docs/vm-api.md`。）

请求：统一改成**按 `MANAGE_VM` 权限鉴权**（而不是硬编码 appIdentifier 白名单），或提供把
第三方应用加入名单的途径。否则第三方虚拟化/镜像应用在旧版系统上完全用不了。

### 6.3 媒体文件系统忽略 chmod/chown，且 picker 文件访问授权在重启/重解锁后降级

现象：把 Linux 镜像 ISO 放在用户 Download 目录（hmdfs/media），OSEasy 有时读不到它——
"选择镜像文件"选上后传不进（页面仍空、下一步灰），"自动搜索"报"未找到可用的ISO文件"。

两个叠加的问题：
- hmdfs/media 文件系统**强制所有文件 owner=20001006:1006、mode=640，并忽略 chmod 和 chown**
  （两者都返回成功但实际不生效）。于是非文件管理器 uid 的应用（例如 OSEasy，uid 20020042）
  作为 other 对 640 文件没有直接读权限，只能依赖文件选择器下发的临时"安全访问文件"授权。
- 这个临时授权在设备**多次重启/重新解锁后会进入降级状态**：应用拿到了路径却读不到文件
  （同一路径在刚解锁时是正常的，重启几次后失效）。

请求（择一/组合）：①允许应用在 media 目录对自己的文件 chmod/chown，或提供一种让目标应用可
直接读取的放置方式；②修复文件访问授权在重启/重解锁后降级的问题；③提供一个可靠的"把本地
磁盘镜像交给虚拟机应用"的入口（不经过易降级的 picker 授权）。否则第三方分发的 Linux 镜像
ISO 无法稳定地被 OSEasy 读取安装。（归入 handover 3(a)：建议鸿蒙侧修的 bug。）

---

附：我们这边的实现与证据在本仓库 `docs/oseasy-whole-os.md`、`docs/oseasy-install.md`。
内核与 vmwgfx 驱动的改动（适配 OSEasy 的 SVGA 设备）按 GPL 开源，随发布一并提供。

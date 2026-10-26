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

OSEasy 通过一条通道（约 `tcp://172.16.100.2`，`install_complete`、`heartbeat` 等）和
Windows guest agent 通信来判断安装完成、心跳、分辨率等。

请求（二选一即可）：
- 提供 **Linux 版 guest agent**；或
- **公开这条协议**（消息格式、端口、握手），让第三方 Linux 镜像能自己上报"安装完成"和心跳，
  从而被 OSEasy 当作正常虚拟机管理。

我们不希望靠冒充厂商服务来绕过它——公开协议或官方 agent 是正途。

## 3. 高刷新率

现状：OSEasy 的显示设备（SVGA / vmwgfx）在客户机里只给 60Hz，而宿主本身是高刷屏。

请求：为虚拟机显示设备提供 **120Hz（及更高）** 的模式（EDID / 模式列表 / 刷新率协商），让
Linux 客户机也能用上高刷。

## 4. 共享文件夹对 Linux 客户机可用（当前完全读不了）

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

---

附：我们这边的实现与证据在本仓库 `docs/oseasy-whole-os.md`、`docs/oseasy-install.md`。
内核与 vmwgfx 驱动的改动（适配 OSEasy 的 SVGA 设备）按 GPL 开源，随发布一并提供。

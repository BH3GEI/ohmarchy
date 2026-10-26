# 纯 Omarchy（Arch Linux ARM）在鸿融中运行：技术说明与建议

给鸿融团队的内部材料。环境：HUAWEI MateBook 14（HongMeng 内核 1.11.13.0），鸿融 1.1.1.103（此前 1.3.1.80），StratoVirt + HMV。
时间：2026 年 10 月下旬。

## 摘要

我们让一个不含 deepin、UOS 或麒麟的纯 Arch Linux ARM + Omarchy（Hyprland 桌面）系统，作为鸿融自己的虚拟机运行。它通过鸿融界面的"本地文件"导入，有 virgl GPU 加速、网络和增强服务，卡片能显示"运行中"，普通关机也可用。为此做了四件事：

1. 让 qcow2 通过导入检查（os_type 字节）；
2. 给 Arch 官方内核 `linux-aarch64` 7.2.12 打两个补丁（GIC ITS、ID 寄存器）；
3. 用自定义 EDID 让虚拟机内部跑到 120 Hz；
4. 在非 UOS/麒麟发行版上装鸿融的增强服务。

文末列出我们希望鸿融做的改进。

## 1. 导入：qcow2 的 os_type 检查

用 qemu-img 生成的 qcow2，在"本地文件"导入时会被拒绝，界面提示"镜像可能在传输过程中损坏"或"disk is damaged"。从 hilog 看，导入分三步：

1. 应用内的 qcow2 校验（`[IsoCheckModel]`）：检查 magic、版本、cluster_bits、虚拟大小，以及 L1/L2/refcount 表和数据簇是否都在文件范围内。
2. 计算整个文件的 SHA-256，然后由 vm_manager 执行 `ImportVmDiskImage`。
3. `CheckBeforeImportVmDisk` 执行 `stratovirt-img get DISK os_type`。值为 0 时报 "src disk img ostype invalid"，导入失败。

os_type 是 StratoVirt 256 字节 qcow2 v3 头的最后一个字节（偏移 255）。鸿融自己的盘是 1，qemu-img 生成的是 0。用 `stratovirt-img set DISK os_type=1` 改成 1 以后，镜像就能导入；我们的脚本写入的头与它逐字节一致。

另外两点：

- 先建小盘、再用 `qemu-img resize` 扩大的镜像，第 1 步会报 "l1 table out of range"；直接按最终虚拟大小（256 GiB）创建则能通过。
- StratoVirt 不支持压缩簇：`stratovirt-img check` 对每个压缩簇都报 "Compressed is not supported"，`convert` 也失败。所以导入用的镜像只能是不压缩的 qcow2。

## 2. 内核：两个补丁

### 2.1 GIC ITS：32 位事件 ID 导致 MSI 全部失败

宿主的 ITS 报告 32 个事件 ID 位（`GITS_TYPER` = `0x603ff71`）。Linux 6.6.130–6.6.159 以及 7.2.11 中，`its_create_device()` 用 `min_t(unsigned int, nvecs, BIT(id_bits))` 限制向量数，id_bits 为 32 时结果是 0。于是每次 MSI 分配都返回 -ENOMEM，所有 PCI 设备退回 INTx，vsock 收不到中断，增强服务永远连不上。

上游已修复（`5a9d62555e71`，抄送 stable）。7.2.12 之前的内核需要自己打这个补丁。deepin 25 的 6.6.143 内核也受影响。

### 2.2 HMV：读取较新的 ID 寄存器时 vCPU 挂起

v6.9 及以后的上游内核在 EFI stub 之后就卡住：vCPU 0 停住，其他 vCPU 也不会被 PSCI 拉起。原因是 HMV 在 guest 读取 v6.8 之后新增的 ID 寄存器（至少包括 `ID_AA64PFR2_EL1`）时让 vCPU 挂起，而 Arm 架构要求未实现的 ID 寄存器读为 0。

我们用一个内核参数 `arm64.hmv_idreg_quirk` 绕开：开启后，这些寄存器直接按 0 处理，不去读硬件。二分结果、寄存器列表和复现方法见 [hmv-idreg-report.md](../hmv-idreg-report.md)。

## 3. 显示：120 Hz

我们做了一个只含 2160x1440@120 和 @60 模式、并且不标记首选时序的 EDID，通过 `drm.edid_firmware=Virtual-1:edid/...` 加载。这样 Hyprland 跑在 2160x1440@119.98。

不标记首选时序，是因为 virtio-gpu 的 `conn_mode_valid` 会删掉与宿主扫描输出尺寸相差超过 16 像素的首选模式。

但在鸿融里全屏显示时，屏幕实际只有 60 fps（`hidumper -s RenderService -a "composer fps"`）；切到其他窗口时，composer 是 120 fps。也就是说，虚拟机内部能渲染 120 Hz，鸿融送到屏幕上的是 60 Hz。

## 4. 增强服务（vm-agent）在 Arch 上

### 现象

不装增强服务时，鸿融始终认为虚拟机没有在运行：

- 卡片显示"已关机"，IP 为空，"关机"和"暂停"是灰的，"更多"里只剩"强制关机"。
- hilog 里每次开机都是 `STARTING`(3) → `VIEWING`(9) → `AGENT_INACTIVE`，之后一直停在 9。卡片只在 `STATE_RUNNING` 时显示运行。

装好之后：卡片显示"运行中"，"关机"会让 guest 走正常的 systemd 关机，卡片回到"已关机"。

### 安装方法

1. 从鸿融挂进虚拟机的光盘里取出 `虚拟机增强服务.deb`。光盘在 guest 里是 `sr0`/`sr1`，卷标"鸿融"。
2. 只装 `/opt/vm-agent`：`agent_service` 和它自带的 protobuf、abseil、cJSON、securec，再加上 systemd unit 和 `ld.so.conf`。其余依赖（systemd、glib2、libstdc++）Arch 都有。
3. 不装包里的 Mesa 19.2.6（会盖掉发行版自带的 Mesa 和 virgl），也不装 dkms 驱动（新内核里都已有）和 UOS/deepin 专用的桌面工具。

agent 第一次连上时，鸿融会把虚拟机关掉，约 12 秒后再开机。

### 观察到的问题

- **postinst 只认 UOS 和麒麟**：判断依据是 `lsb_release -is`，其他发行版什么也不做。在 deepin 上还会装一半失败，dpkg 留在待重装状态，apt 因此被堵住。
- **`/etc/systemd/logind.conf` 被整个重写**：新文件丢了 `[Login]` 段头，logind 会忽略写进去的这几行；同时覆盖了发行版或用户原有的配置。
- **自我更新依赖 dpkg**：日志里有 `dpkg-deb: command not found`；更新失败，但没有其他影响。
- **日志刷屏**：大量 `pgrep: regex error: Invalid range end`。
- **网络设置报错**：`802-3-ethernet.cloned-mac-address: '52a0c055ccbe' is not a valid Ethernet MAC`（缺冒号）。
- **网络配置被反复重新应用**：NetworkManager 连接在启动时被 reapply 十余次；agent 还新加了一个 `enp0s6` 配置。新配置内容正确，网络可用。
- **尝试挂载 `/data`**：日志里有 `mount: /data: mount point does not exist`。

## 5. 希望鸿融做的事

1. **支持高刷新率。** 让全屏虚拟机按 guest 的刷新率（或宿主屏幕的 120 Hz）显示，不要固定在 60 Hz。
2. **增强服务支持更多发行版。**
   - postinst 不要只认 UOS 和麒麟：对未知发行版至少安装并启用 `agent_service`；Mesa 和 dkms 驱动做成可选。
   - 再提供一个不依赖 dpkg 的安装包（tar 包加安装脚本即可），自我更新也不依赖 dpkg。
   - 修复上面的日志刷屏、MAC 格式和 `/data` 挂载问题。
3. **公开导入格式的文档。** 写明"本地文件"导入对 qcow2 的要求：os_type 字节及其取值、虚拟大小、表的位置，以及不支持压缩簇。最好在导入时直接把 os_type 设好，或者给出明确的错误提示，而不是"镜像可能已损坏"。
4. **不要整个重写 `logind.conf`。** 改用 drop-in，比如 `/etc/systemd/logind.conf.d/50-vm-agent.conf`，并带上 `[Login]` 段头。
5. **没有增强服务时，卡片也能显示真实状态。** 根据 StratoVirt 进程状态显示"运行中"，普通关机改走 ACPI 电源键。这样没装增强服务的发行版也能正常使用。
6. **HMV（转给相关团队）。**
   - 未实现的 ID 寄存器按 Arm 架构读为 0（见 2.2）。
   - ITS 报告的事件 ID 位数（32）与 Linux 主线的配合问题，见 2.1。上游已修，供参考。

## 附：复现要点

- **导入：** qemu-img 按 256G 创建 qcow2（cluster 64K，compat 1.1），convert 进去，再用 `stratovirt-img set DISK os_type=1`。
- **内核：** `linux-aarch64` 7.2.12，打上 ITS 补丁和 ID 寄存器补丁，命令行加 `arm64.hmv_idreg_quirk`。
- **增强服务：** 取光盘上 deb 里的 `/opt/vm-agent` 和 `agent_service.service`，`ldconfig` 之后 `systemctl enable --now agent_service`。

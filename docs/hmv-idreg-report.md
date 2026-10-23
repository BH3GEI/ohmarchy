# 问题报告：鸿融虚拟机读取三个 ID 寄存器时 vCPU 卡死

> **草稿（2026-10-24）**：6.9 的结论已验证。7.2.11 即使把所有新增 ID 寄存器都当作 0 仍然卡死，说明 6.9 以后还有第二个原因，正在按版本二分定位，定位后补进本报告。

致：华为 鸿融（com.huawei.medivh）/ HMV 虚拟化团队

## 摘要

在鸿融的 Linux 虚拟机里，Linux 6.9 及以后的上游内核都启动不了：EFI stub 退出启动服务后，0 号 vCPU 停住，再也不会通过 PSCI 拉起其他 vCPU，屏幕黑屏，没有任何报错。

问题出在客户机第一次读取以下三个 AArch64 ID 寄存器的时候：

| 寄存器 | 编码 (op0, op1, CRn, CRm, op2) | Linux 开始读取的版本 |
|---|---|---|
| `ID_AA64ISAR3_EL1` | (3, 0, 0, 6, 3) | 6.9 |
| `ID_AA64PFR2_EL1` | (3, 0, 0, 4, 2) | 6.9 |
| `ID_AA64FPFR0_EL1` | (3, 0, 0, 4, 7) | 6.9 |

按 Arm 架构，ID 寄存器空间（op0=3, op1=0, CRn=0, CRm=0..7）里还没分配的寄存器在 EL1 读出来应该是 0（RES0）。实现了 FEAT_IDST 时，这类读取最多陷入到 EL2，由 hypervisor 模拟返回 0。无论哪种情况，都不应该让 vCPU 卡住。Linux KVM 对这三个寄存器返回经过过滤的值（不支持的特性字段为 0）。

一句话：**希望 HMV 对这三个寄存器（最好是整个 ID 寄存器空间里它不认识的编码）按架构返回 0，而不是让 vCPU 卡住。**

## 环境

- 机器：HUAWEI MateBook 14（HM740，Kirin X90，20 线程），HongMeng 内核 1.11.13.0，HarmonyOS 7.0
- 鸿融：1.3.1.80 和 1.1.1.103 上都复现
- 虚拟机：StratoVirt `virt` 机型，`accel=hmv`，GICv3，6 个 vCPU，UEFI 固件 `/system/opt/virt_service/virtualized_hwf/stratovirt-uefi-linux`
- 客户机：Arch Linux ARM（Omarchy），能启动的内核是 deepin 的 6.6.143

鸿蒙内核开源代码里 `hongmeng/hm-verif-kernel` 的 `drivers/hypervisor.h` 显示，HMV 是华为自研的 hypervisor（vCPU 用 `HYP_VCPU_*` 接口管理，ioctl 只是借用了 KVM 的魔数 0xAE），不是 Linux KVM。所以客户机读 ID 寄存器时怎么陷入、怎么模拟，由 HMV 自己负责。

## 现象

- 内核能加载，EFI stub 调完 `ExitBootServices` 之后就没有任何输出了（`earlycon=efifb` 也一样）。
- 宿主机 `/data/log/hwf_service/vmlog` 里，正常启动时会出现 `hypervisor/src/hmv/aarch64/psci.rs:100: vCPU 1 is running.`（以及 vCPU 2..5）。卡死时这几行都不会出现，StratoVirt 进程一直在，只能强制关机。
- 跟内核配置无关：上游 `defconfig`、Debian、Ubuntu、Arch Linux ARM（linux-aarch64 7.2.11）的内核都一样卡；48 位和 52 位虚拟地址都一样卡。

## 定位过程

每轮测试都不带 initramfs 启动一次待测内核。判定方法：PASS = 宿主机日志里出现 `vCPU 1 is running`，FAIL = 30 秒内没出现。

1. 版本范围：v6.8 PASS，v6.9 FAIL（都是 `defconfig`）。
2. 在 v6.8..v6.9 之间对 arm64 早期启动相关的文件做 `git bisect`，第一个坏提交是合并提交 `0c5ade742e91`（arm64 for-next/core，2024-03）。它一次合进了 9 条分支，被合进来的每条分支分别测：

   | 分支（测试的提交） | 内容 | 结果 |
   |---|---|---|
   | for-next/reorg-va-space（`0dd4f60a2c76`、`27f2b9fcddc7`） | LPA2 / 早期页表重写 | PASS |
   | for-next/daif-cleanup（`527db67a4d85`） | 中断屏蔽清理 | PASS |
   | for-next/sysreg（`358fee291705`） | sysreg 定义更新 | PASS |
   | for-next/dpisa（`44d10c27bd75`） | 2023 DPISA：新增 FP8、FAMINMAX 等特性检测 | **FAIL** |

3. for-next/dpisa 让 `__cpuinfo_store_cpu()`（arch/arm64/kernel/cpuinfo.c）在启动 CPU 上新读三个寄存器：`ID_AA64ISAR3_EL1`、`ID_AA64PFR2_EL1`、`ID_AA64FPFR0_EL1`。
4. 验证：用坏的合并提交 `0c5ade742e91` 本身，只把这三处 `read_cpuid()` 改成直接赋 0，其他都不动。结果：**PASS**。不改：FAIL。

结论：只要不读这三个寄存器，同一个内核就能启动，所以是读这三个寄存器（至少其中一个）让 vCPU 卡住了。具体是哪一个还没有单独测。

## 复现步骤

1. 在鸿融里装好任意 aarch64 Linux（例如 deepin 25 或 openKylin），用 GRUB 启动。
2. 拿一个 v6.9 或更新的上游内核，`make defconfig && make Image`，放进虚拟机，加一个不带 initramfs 的 GRUB 启动项：
   `linux /boot/Image console=tty0 earlycon=efifb keep_bootcon ignore_loglevel loglevel=8`
3. 用这一项启动，同时在宿主机上看：
   `grep "\[<StratoVirt 的 pid>\]" /data/log/hwf_service/vmlog | grep "psci.rs.*vCPU 1 is running"`
   v6.8 会出现这一行，v6.9 不会。
4. 不改 hypervisor 的最小验证：v6.9 上打下面这个补丁（三处 `read_cpuid` 改成 0），这一行就出现了。

## 客户机侧的临时规避

Omarchy 在 7.2 内核上加了启动参数 `arm64.hmv_idreg_quirk`（见 `hongrong/kernel/patches/0002-*.patch`）：带上这个参数时，这三个寄存器不读，直接当 0。不带时行为和上游完全一样。HMV 修好之后，这个补丁和参数都可以删掉。

## 希望的修复

- HMV 对 ID 寄存器空间（op0=3, op1=0, CRn=0, CRm=0..7）里没有实现的编码，统一按 RAZ 模拟（读出 0），不要让 vCPU 停住或者无响应。
- 如果 HMV 想把某些特性藏起来不给客户机，也请返回过滤后的值，不要不返回。
- 以后 Arm 还会继续新增 ID 寄存器（7.2 已经在读 `ID_AA64MMFR4_EL1` 和 `AIDR_EL1`），所以通用的 RAZ 处理比逐个补寄存器更稳。

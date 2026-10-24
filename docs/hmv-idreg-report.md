# 问题报告：鸿融虚拟机读取 ID_AA64PFR2_EL1 等新 ID 寄存器时 vCPU 卡死

致：华为 鸿融（com.huawei.medivh）/ HMV 虚拟化团队

## 摘要

在鸿融的 Linux 虚拟机里，Linux 6.9 及以后的上游内核都启动不了：EFI stub 退出启动服务后，0 号 vCPU 停住，再也不会通过 PSCI 拉起其他 vCPU，屏幕黑屏，没有任何报错。

原因是客户机读取 Linux 6.9 以后才开始读的几个 AArch64 ID 寄存器时，vCPU 卡住。可以确定的是 `ID_AA64PFR2_EL1`：Linux 6.17 在启动早期单独读它一次，内核就停在那里（见下文）。

按 Arm 架构，ID 寄存器空间（op0=3, op1=0, CRn=0, CRm=0..7）里还没分配的寄存器在 EL1 读出来应该是 0。实现了 FEAT_IDST 时，这类读取最多陷入到 EL2，由 hypervisor 模拟返回 0。无论哪种情况，都不应该让 vCPU 卡住。Linux KVM 对这些寄存器返回经过过滤的值（不支持的特性字段为 0）。

一句话：**希望 HMV 对 ID 寄存器空间里它不认识的编码按架构返回 0，而不是让 vCPU 卡住。**

## 环境

- 机器：HUAWEI MateBook 14（HM740，Kirin X90，20 线程），HongMeng 内核 1.11.13.0，HarmonyOS 7.0
- 鸿融：1.3.1.80 和 1.1.1.103 上都复现
- 虚拟机：StratoVirt `virt` 机型，`accel=hmv`，GICv3，6 个 vCPU，8 GB，UEFI 固件 `/system/opt/virt_service/virtualized_hwf/stratovirt-uefi-linux`
- 客户机：Arch Linux ARM（Omarchy）；能启动的内核是 deepin 的 6.6.143

鸿蒙内核开源代码里 `hongmeng/hm-verif-kernel` 的 `drivers/hypervisor.h` 显示，HMV 是华为自研的 hypervisor（vCPU 用 `HYP_VCPU_*` 接口管理，ioctl 只是借用了 KVM 的魔数 0xAE），不是 Linux KVM。所以客户机读 ID 寄存器时怎么陷入、怎么模拟，由 HMV 自己负责。

## 涉及的寄存器

Linux 6.8 启动时不读、7.2 启动时会读的寄存器（`arch/arm64/kernel/cpuinfo.c`、`cpufeature.c` 对比得出）：

| 寄存器 | 编码 (op0, op1, CRn, CRm, op2) | Linux 开始读取的版本 | 读取位置 |
|---|---|---|---|
| `ID_AA64ISAR3_EL1` | (3, 0, 0, 6, 3) | 6.9 | `__cpuinfo_store_cpu()` |
| `ID_AA64PFR2_EL1` | (3, 0, 0, 4, 2) | 6.9；6.17 起启动早期再直接读一次 | `__cpuinfo_store_cpu()`；`has_cpuid_feature()` → `__read_sysreg_by_encoding()` |
| `ID_AA64FPFR0_EL1` | (3, 0, 0, 4, 7) | 6.9 | `__cpuinfo_store_cpu()` |
| `ID_AA64MMFR4_EL1` | (3, 0, 0, 7, 4) | 6.9 前后 | `__cpuinfo_store_cpu()` |
| `AIDR_EL1` | (3, 1, 0, 0, 7) | 6.15 前后 | `__cpuinfo_store_cpu()` |
| `SMIDR_EL1` | (3, 1, 0, 0, 6) | 6.x | 仅当 CPU 报告 SME 时 |
| `MPAMIDR_EL1` | (3, 0, 10, 4, 4) | 6.x | 仅当 CPU 报告 MPAM 时 |

## 现象

- 内核能加载，EFI stub 调完 `ExitBootServices` 之后屏幕上没有任何输出（`earlycon=efifb` 也一样；虚拟机的 PL011 串口接的是 `/dev/null`）。
- 宿主机 `/data/log/hwf_service/vmlog` 里，正常启动时会出现 `hypervisor/src/hmv/aarch64/psci.rs:100: vCPU 1 is running.`（以及 vCPU 2..5）。卡死时这几行都不会出现，StratoVirt 进程一直在，只能强制关机。
- 跟内核配置无关：上游 `defconfig`、Debian、Ubuntu、Arch Linux ARM（linux-aarch64 7.2.11）的内核都一样卡；48 位和 52 位虚拟地址都一样卡。

## 定位过程

判定方法：每次只启动一次待测内核，PASS = 宿主机日志里出现 `vCPU 1 is running`，FAIL = 30 秒内没出现。

### 第一处：6.9，`__cpuinfo_store_cpu()`

1. 版本范围：v6.8 PASS，v6.9 FAIL（都是 `defconfig`）。
2. 在 v6.8..v6.9 之间对 arm64 早期启动相关的文件做 `git bisect`，第一个坏提交是合并提交 `0c5ade742e91`（arm64 for-next/core，2024-03）。它一次合进了 9 条分支，被合进来的分支分别测：

   | 分支（测试的提交） | 内容 | 结果 |
   |---|---|---|
   | for-next/reorg-va-space（`0dd4f60a2c76`、`27f2b9fcddc7`） | LPA2 / 早期页表重写 | PASS |
   | for-next/daif-cleanup（`527db67a4d85`） | 中断屏蔽清理 | PASS |
   | for-next/sysreg（`358fee291705`） | sysreg 定义更新 | PASS |
   | for-next/dpisa（`44d10c27bd75`） | 2023 DPISA：FP8、FAMINMAX 等特性检测 | **FAIL** |

3. for-next/dpisa 让 `__cpuinfo_store_cpu()` 在启动 CPU 上新读三个寄存器：`ID_AA64ISAR3_EL1`、`ID_AA64PFR2_EL1`、`ID_AA64FPFR0_EL1`。
4. 验证：坏的合并提交 `0c5ade742e91` 本身，只把这三处 `read_cpuid()` 改成直接赋 0：**PASS**。不改：FAIL。

### 第二处：6.17，GICv5 特性检测直接读 `ID_AA64PFR2_EL1`

1. 把上表全部寄存器在 `cpuinfo.c`、`cpufeature.c` 里的 `read_cpuid()` 都改成 0，再测各个正式版本：

   | 版本 | 6.12 | 6.15 | 6.16 | 6.17 | 6.18 | 6.19 | 7.0 |
   |---|---|---|---|---|---|---|---|
   | 结果 | PASS | PASS | PASS | FAIL | FAIL | FAIL | FAIL |

2. 卡死时客户机没有任何输出，我们从宿主机读 StratoVirt 进程里客户机内存（`/proc/<pid>/mem` 中的 `memfd:stratovirt_anon_mem`），取出客户机内核日志。最后一行是：

   ```
   CPU features: detected: GICv3 CPU interface
   ```

3. 6.17 新增的启动 CPU 特性 `ARM64_HAS_GICV5_CPUIF`（编号紧跟 GICv3 CPU interface）用 `has_cpuid_feature()` 检查 `ID_AA64PFR2_EL1.GCIE`。启动 CPU 范围的特性检查不用 `cpuinfo` 里存的值，而是经 `__read_sysreg_by_encoding()` 直接执行 `mrs`。这是这一步里唯一的一次读取，vCPU 就停在这里。
4. 验证：在 `__read_sysreg_by_encoding()` 里同样对这些寄存器返回 0 之后，Arch Linux ARM 的 linux-aarch64 7.2.11 正常启动：6 个 vCPU 都起来，进入 Omarchy 桌面（Hyprland），virtio-gpu 报告 `+virgl`，vsock、网络正常。

结论：读 `ID_AA64PFR2_EL1` 会让 vCPU 卡住。`ID_AA64ISAR3_EL1`、`ID_AA64FPFR0_EL1` 等是否同样会卡，没有逐个单独测。

## 复现步骤

1. 在鸿融里装好任意 aarch64 Linux（例如 deepin 25 或 openKylin），用 GRUB 启动。
2. 拿一个 v6.9 或更新的上游内核，`make defconfig && make Image`，放进虚拟机，加一个不带 initramfs 的 GRUB 启动项：
   `linux /boot/Image console=tty0 earlycon=efifb keep_bootcon ignore_loglevel loglevel=8`
3. 用这一项启动，同时在宿主机上看：
   `grep "\[<StratoVirt 的 pid>\]" /data/log/hwf_service/vmlog | grep "psci.rs.*vCPU 1 is running"`
   v6.8 会出现这一行，v6.9 不会。
4. 不改 hypervisor 的最小验证：打上 `hongrong/kernel/patches/0002-*.patch`，启动参数加 `arm64.hmv_idreg_quirk`，这一行就出现了。

## 客户机侧的临时规避

Omarchy 的 linux-aarch64 内核加了启动参数 `arm64.hmv_idreg_quirk`（`hongrong/kernel/patches/0002-*.patch`）：带上这个参数时，上表的寄存器一律当 0，不实际读取（`cpuinfo` 和 `__read_sysreg_by_encoding()` 两处），并隐藏 MPAM 以免读 `MPAMIDR_EL1`。不带时行为和上游完全一样。HMV 修好之后，这个补丁和参数都可以删掉。

## 希望的修复

- HMV 对 ID 寄存器空间（op0=3, op1=0, CRn=0, CRm=0..7）里没有实现的编码，统一按 RAZ 模拟（读出 0），不要让 vCPU 停住或者无响应。
- 如果 HMV 想把某些特性藏起来不给客户机，也请返回过滤后的值，不要不返回。
- `AIDR_EL1` 等 IMPLEMENTATION DEFINED 寄存器也请给出确定的返回值。
- 以后 Arm 还会继续新增 ID 寄存器，所以通用的 RAZ 处理比逐个补寄存器更稳。

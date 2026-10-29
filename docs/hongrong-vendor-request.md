# 给鸿融的问题报告：Linux 客户机里的 Firefox 让 GPU 进程崩溃，虚拟机被停掉

面向鸿融（com.huawei.medivh）和 HarmonyOS 虚拟化、图形栈的团队。尚未与厂商联系；是否、何时
提交由 Yao 决定。

## 现象

2026-10-29，ohdev（MNT-W72C，HarmonyOS 7.0.0.115），鸿融里跑 Arch Linux ARM + Hyprland
（Omarchy，内核 7.2.12-1.2，virtio-gpu + virgl）。在虚拟机里打开 Firefox，几秒内整台虚拟机
消失。同一台虚拟机里 Chromium、Hyprland 桌面正常。重新开机后再开 Firefox，又崩一次。

## 宿主侧经过（/data/log/hwf_service/vmlog2）

1. 15:22:28，宿主的 `/system/bin/virt_service/vm_engine/stratovirt/vhost-device-gpu`
   （`--gpu-mode virglrenderer`）收到 SIGSEGV，空指针（pc=0）。
2. stratovirt 每 3 秒报一次 `Failed to connect vhost-user gpu. Try again after 3s.`。
3. 15:23:05，`Shutdown { guest: false, reason: "host-qmp-quit" }`，虚拟机被直接停掉，
   客户机没有机会同步磁盘。
4. 15:23:21 重新开机，15:23:51 以同样的调用栈再崩一次。

崩溃记录：/data/log/faultlog/temp/cppcrash-41202-1793258548724.json、
cppcrash-52361-1793258631938.json。两份调用栈相同（线程 vring_worker）：

```
#00 pc 0000000000000000  Not mapped
#01 update_gfx_pipeline<(zink_dynamic_state)0, false>+316   /system/lib64/libgallium-25.0.1.so
#02 zink_draw<(zink_multidraw)0, (zink_dynamic_state)0, false, false>+1456
#03 zink_draw_vbo<(zink_multidraw)0, (zink_dynamic_state)0, false>+116
#04 tc_batch_execute+10180
#05 _tc_sync+420
#06 tc_flush+256
#07 _mesa_fence_sync+124
#08 /system/lib64/libvirglrenderer.so.1
#09 /system/bin/virt_service/vm_engine/stratovirt/vhost-device-gpu
```

## 原因

- libgallium-25.0.1.so（buildId 528a989b0a7f1a92639c655e779f24849592942c）在 0xd5c86c 处的
  `blr x8`，x8 取自 zink 的 Vulkan 分发表。参数是 5 个阶段的 stage 数组
  （VERTEX、TESS_CTRL、TESS_EVAL、GEOMETRY、FRAGMENT）和程序里的 shader 对象数组，也就是
  zink 在 `curr_program->base.uses_shobj` 为真时调用的 `vkCmdBindShadersEXT`
  （VK_EXT_shader_object）。
- 宿主的 Vulkan 驱动 /vendor/lib64/passthrough/vulkan.hvgr_v210.so（ICD 报 1.3.231）里没有
  `VK_EXT_shader_object`，也没有 `vkCmdBindShadersEXT`，所以这个函数指针是空的。
- 也就是说，zink 在驱动没有 VK_EXT_shader_object 时仍走了 shader object 的路径。哪一种 GL 用法会
  进到这条路径没有在客户机里确认；Firefox 用硬件 WebRender，Chromium 在 virgl 上没有触发。

## 请求

1. 修 zink（或宿主 Mesa 的构建、配置）：驱动不支持 VK_EXT_shader_object 时，不要设置
   `uses_shobj`，也不要调用 `vkCmdBindShadersEXT`。
2. vhost-device-gpu 崩溃后，不要直接停掉虚拟机：重启 GPU 后端并让 virtio-gpu 重新连接，
   或至少先让客户机正常关机。现在一个客户机里的应用就能让整台虚拟机掉电。

## 我们的规避

Omarchy 镜像在 /etc/firefox/policies/policies.json 里把 `gfx.webrender.software` 默认设为
true，Firefox 改用软件 WebRender，不再经过 virgl 的硬件 GL
（hongrong/pure/firstboot/firefox-policies.json）。临时办法：`LIBGL_ALWAYS_SOFTWARE=1 firefox`。

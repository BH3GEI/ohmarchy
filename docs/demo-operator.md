# Demo operator manual (draft)

English | [中文](demo-operator.zh-CN.md)

For the person **operating the HarmonyOS PC by hand** on stage. Follow it and
the demo is hard to derail. Click coordinates, the automation scripts and the
rehearsal numbers are in [demo.md](demo.md); this page only says what your
hands do, what your eyes check, and what to say.

> **Draft, not yet rehearsed end to end against the final setup.** Every place
> marked **(to be confirmed in rehearsal)** has to be walked through by hand in
> the rehearsal before it can be trusted.

## Three hard rules

1. **Only one VM at a time.** 鸿融, OSEasy and the background Docker VM: only
   one of them may run. A second one is refused by the system (401 "Not
   support vm multi-instance"). So at the end of every part, **shut the VM
   down completely before starting the next part**.
2. **Shut down normally, never force**: the Omarchy disk in 鸿融 has the
   guest agent, so tap 关机 on 鸿融's card (or **Super+Esc → Shutdown** in
   Omarchy); in OSEasy use **Super+Esc → Shutdown**. Don't reboot inside the
   VM, don't log out.
3. **Don't close the native desktop's window**, minimize it. Opening "Omarchy
   (native)" again brings the desktop back by itself in about 6 s, but the
   windows that were open in it are gone.

"Super" is the Windows logo key on the keyboard. **On the native desktop (part 1)
press Alt+Shift together instead of Super**: HarmonyOS keeps the Windows key (its
start menu opens) and many of its chords; the app turns Alt+Shift into Super. So
Super+Return is Alt+Shift+Return. When the shortcut has Shift in it as well,
hold **both** Shift keys: Super+Shift+B is Alt+left Shift+right Shift+B. Right Alt
is a plain Alt again. In the VMs (parts 2 and 3) Super is the Windows key as usual.

The native-app version, "Omarchy（原生应用）" (pink icon; not part of this demo),
opens full screen: Alt+Tab switches away, Ctrl+Alt+Escape minimizes it, and
"关闭窗口" in its dock icon's menu closes it (Linux stops with it). "Reset Linux"
in the same menu puts Linux back as installed, after asking.

## Order (about 10 min)

| # | Part | Time (rehearsed) | Must be true at the end |
|---|---|---|---|
| 1 | D native desktop + I Docker | about 80 s + about 20 s for Docker | the background Docker VM has stopped (see 1.9) |
| 2 | C 鸿融 (the swapped-in Omarchy disk, same image as B) | about 3 min | 鸿融's card says 已关机 |
| 3 | B OSEasy | about 3 min (new flow to be confirmed in rehearsal) | VM shut down (end of demo, no rush) |

---

## 0. One-minute checklist before the demo

Check by looking wherever possible. Items that need a command are marked
**[backstage]**: a helper does them on their own laptop (`ssh ohdev`); Yao
doesn't touch them.

| # | Item | How to check |
|---|---|---|
| 1 | Power plugged in | battery icon at the bottom right shows charging |
| 2 | Brightness up, screen won't turn off by itself | set auto screen-off to long or never in Settings (exact menu to be confirmed in rehearsal) |
| 3 | Do Not Disturb on | turn on 免打扰 in the control center if it has one (location on the HarmonyOS PC to be confirmed in rehearsal) |
| 4 | Nobody else is driving the machine | [backstage] tell every remote session and automation script to stop; nobody touches the screen over ssh during the demo |
| 5 | **No VM running** | 鸿融's card says 已关机 and 开机 can be tapped (the Omarchy disk has the guest agent, so the label is reliable); OSEasy is not running either. [backstage] definitive: `ssh ohdev pidof stratovirt` prints nothing |
| 5b | **鸿融 does not start a VM by itself** | In 鸿融, 虚拟机 → 功能设置 → 启动与闲置: both 启动客户端后虚拟机自动运行 (start the VM when the app starts) and 闲置自动暂停虚拟机 (pause the VM when idle) are off (turned off on 2026-10-26; with the first on, opening 鸿融 starts the VM and takes the HMV that part 1's Docker needs). Do not tap 鸿融 in the dock before the start. [backstage] if `ssh ohdev pidof stratovirt` prints something and `ps -ef \| grep stratovirt` shows com.huawei.medivh, shut it down from 鸿融: 关机 for the Omarchy disk (it has the guest agent), 更多 → 强制关机 for the main disk (no agent); then check `pidof stratovirt` is empty again |
| 6 | Native desktop already running in the background | it starts at boot by itself (verified by a real reboot on 2026-10-26: the desktop was running about 50 s after power-on; after login, double-clicking the icon showed it at once). [backstage] `ssh ohdev sh /data/local/archtest/bin/omarchy desktop status`; if it is down, `... omarchy desktop start` (about 3 s) |
| 7 | Clean desktop | only HarmonyOS's own desktop; no 鸿融, OSEasy or "Omarchy (native)" window open; notifications cleared |
| 8 | The three icons can be found | 鸿融 (orange-yellow) and "Omarchy (native)" are on the desktop, top left; while 鸿融 is closed it is **not** in the dock (rehearsal 2026-10-27): open it by double-clicking the desktop icon |
| 9 | 鸿融 auto-update is off | AppGallery has swapped 鸿融's version on its own before. It should be 1.1.1.103 |
| 10 | OSEasy holds the installed VM | opening OSEasy shows 再次安装 (**to be confirmed in rehearsal**: the flow is being changed). Close OSEasy again after looking |
| 11 | OSEasy's trial has not expired | OSEasy allows one trial per device (**to be confirmed in rehearsal**: look for an expiry notice in the app) |
| 12 | 鸿融 holds the Omarchy disk, its password is set | see "Part 2: before the demo". Booting needs no password (autologin); the password is only for sudo and the lock screen. Yao memorizes it; it is never written into any file, including this one |
| 13 | Backup videos/screenshots open on another computer | see "Backup plan" below |

---

## Part 1: D native desktop + I Docker (about 2 min)

| # | Do | Expect on screen | Wait | Say |
|---|---|---|---|---|
| 1.1 | Double-click **"Omarchy (native)"** on the HarmonyOS desktop (it is in the dock only while it runs) | first a window saying what it waits for, then the Omarchy wallpaper and top bar | about 10 s | "This isn't a VM. Arch Linux programs run directly on the HarmonyOS kernel, and the desktop is drawn into an ordinary HarmonyOS app window." |
| 1.2 | Click **maximize** on the window's title bar | the desktop fills the screen | 1 s | |
| 1.3 | **Super+Return** (Alt+Shift+Return), type `fastfetch`, Enter | a terminal; fastfetch shows Arch Linux ARM, the HongMeng kernel, Hyprland | 10 s | "Look at the kernel line: HongMeng, HarmonyOS's own kernel. The programs are Arch's own binaries, unchanged." (Its GPU line says llvmpipe: that is the terminal drawing itself on the CPU; the desktop is composited on the GPU) |
| 1.4 | **Super+2**, then **Super+1** (Alt+Shift+2, Alt+Shift+1), a few times | workspaces slide back and forth smoothly | 10 s | "This is 120 Hz, drawn by the Maleoon GPU; measured at 110–119 fps." |
| 1.5 | **Super+Shift+B** (Alt+both Shift keys+B) | Firefox opens next to the terminal (a fresh window, never "Restore Session"); open omarchy.org. A first-run tip may show: click "Okay, Got It" | 15 s | "The browser is Firefox, with its sandbox." |
| 1.6 | **Super+Space** (Alt+Shift+Space) for the Omarchy menu, glance, **Esc** | the Omarchy menu appears and closes | 5 s | "That's Omarchy's own menu, unchanged." |
| 1.7 | **Super+Shift+F** (Alt+both Shift keys+F) | Files (Nautilus) on the home directory | 5 s | |
| 1.8 | Click back into the terminal, type `docker run --rm hello-world`, Enter | a pause (the background VM is starting), then **"Hello from Docker!"** | **first run about 27 s** (measured 2026-10-27), don't panic | "The HarmonyOS kernel can't run containers, so Docker borrows a small background VM that starts when it's used and stops about forty seconds after. I didn't type any root command." |
| 1.9 | **Nothing to do**: the Docker VM stops by itself | nothing visible | about 40 s, while the 1.8 line is said | "Done with it, it is off by itself; the next VM can start." |
| 1.10 | **Minimize** "Omarchy (native)" (don't close it) | back on the HarmonyOS desktop | 2 s | |

**1.9 The Docker VM stops by itself** (rehearsed 2026-10-27: hello-world 27 s cold, then nothing touched: `pidof stratovirt` empty about 40 s later). With no container running and no docker client connected it powers off after 30 s. **Don't type another `docker` command meanwhile**: each one restarts the timer. If it is still on, see the last row of the table below.

Rehearsed 2026-10-26 on ohdev with keys injected through HarmonyOS's input
service (right Alt as Super): 1.1–1.7 all as described; the desktop was up about
10 s after the double-click. In part 1 every "Super" is **Alt+Shift** (Super+Shift:
Alt and both Shift keys); the Windows key opens HarmonyOS's start menu (click back
into the desktop to close it). (That rehearsal used right Alt for Super, the rule
until 2026-10-27; Alt+Shift is not rehearsed yet.)
The display app on ohdev is main 48eee76 (installed 2026-10-27, adds the
HarmonyOS notification when Docker is blocked; the desktop opens normally).

### Part 1: if this happens, do this

| Symptom | Do |
|---|---|
| The app window keeps saying it is waiting; no desktop | The native desktop isn't running in the background (autostart didn't work; shouldn't happen, except within the first minute after boot). [backstage] `omarchy desktop start`, wait 10 s. Still nothing: close the app window, [backstage] `omarchy desktop stop; omarchy desktop start`, tap the icon again. On stage: "let's change the order", go straight to part 2 (鸿融) |
| "Omarchy (native)" was closed by accident | Double-click the icon again: the desktop starts afresh by itself, about 6 s (rehearsed 2026-10-26, no backstage command). Windows that were open are gone; open them again (Super = Alt+Shift) |
| Super+Return and other shortcuts do nothing, or HarmonyOS's start menu opens | Use **Alt+Shift** instead of the Windows key (Super+Shift: Alt and both Shift keys). Click inside the Omarchy window first so it has focus. Still nothing: skip the shortcuts and show what is already open |
| Firefox opens on "Sorry. We're having trouble getting your pages back." (Restore Session) | Click **Start New Session**, then open omarchy.org. (Caused by a desktop restart killing Firefox; fixed 2026-10-27 and verified: after reopening the app Firefox opens a new tab. Shouldn't happen any more) |
| A window is stuck | **Super+W** closes it; go on to the next step |
| `docker` shows nothing for about 30 s | Expected: the first run starts the background VM. Keep talking |
| `docker` says `后台 Docker 虚拟机启动不了：鸿融或者 OSEasy 的虚拟机正在运行，请先关掉它` | Another VM is running (checklist item 5 was missed). An Omarchy (native) notification also lands in HarmonyOS's notification center (no banner while the app is in front, just a red dot on the bell; clear it with checklist item 7). On stage: "this is exactly the one-VM-at-a-time limit", skip Docker. [backstage] find which VM it is; it has to be off before part 2 |
| `docker` shows nothing for over 1 min | Ctrl+C, skip Docker, show the backup screenshot (`docs/img/autostart/03-docker-cold.jpeg`). [backstage] `ohmarchy-vm stop`, confirm `pidof stratovirt` is empty before part 2 |
| A minute after hello-world, 鸿融 says another VM is running | The Docker VM is still on (e.g. another `docker` was typed). In the terminal: `docker-vm stop` (about 6 s, "Docker 虚拟机已关闭"); if it says a container is running, `docker ps`, `docker stop <name>` first. Or [backstage] `ohmarchy-vm stop` |

---

## Part 2: C 鸿融 (about 3 min)

鸿融 runs the swapped-in Omarchy disk, the **same public image** OSEasy
installs in part 3. It has 鸿融's guest agent, so it boots straight to the
desktop, the card says 运行中, and 鸿融's own 关机 button works.

### Before the demo ([backstage], about 10 min, can be done the day before)

鸿融 holds one VM, so Yao's main VM disk is swapped out first. 鸿融's VM stays
off throughout (`pidof stratovirt` empty).

1. **Back up the main disk**: copy `vm.qcow2` and `stratovirt-vars` from
   `/data/service/el0/virt_service/100/vm_manager/<id>/com.huawei.medivh/img`
   to a backup dir and check both copies have the same size (36 GB, about
   1.5 min).
2. **Swap**: `hrswap.sh use-dev <IMGDIR> /data/local/vmtest/omarchy-b-nopass-os1.qcow2`
   (made from the public image with `hongrong/pure/make-qcow2.sh`, about
   10 s). Open 鸿融: the disk shows 已使用 6 GB.
3. **Set the password**: tap **开机**. After about 45 s a fullscreen "请设置密码 /
   Set your password" appears. 鸿融 may show its 增强服务 guide dialog
   (**知道了**) or only a toast at the bottom right (the second preparation on
   2026-10-27 showed only the toast); click the VM picture before typing. Type a password of at least 8 characters twice (Yao's choice,
   memorized, never written down). It shows 密码已设置, installs 鸿融's guest agent and
   says 鸿融 restarts the VM once; press Enter. The toast goes away. About a minute later the VM
   is back on the Omarchy desktop, with no login screen.
4. **Check and shut down**: bring 鸿融 to the front (`aa start -b
   com.huawei.medivh -a EntryAbility`): the card says **运行中** (green). Tap
   **关机**; within 20 s it says 已关机.

Rehearsed 2026-10-27: password screen 45 s after 开机; desktop and 运行中
after the restart; 鸿融's 关机 done within 20 s, back on the VM page by
itself (screenshots k01–k09).

### Steps

Before starting: the Docker VM has stopped (1.9).

| # | Do | Expect on screen | Wait | Say |
|---|---|---|---|---|
| 2.1 | **Double-click 鸿融 on the desktop**, top left (orange-yellow; it is not in the dock while closed) | the VM page: Linux, 当前状态 已关机, 已使用 6 GB | 5 s | "鸿融 is Huawei's own Linux VM app, installed from AppGallery; no root needed." |
| 2.2 | Tap **开机** | 鸿融 switches to the fullscreen VM and lands on the Omarchy desktop (wallpaper, top bar with workspaces 1–5): **no password**, and no 增强服务 guide dialog any more | about 1 min (not timed exactly in the 2026-10-27 rehearsal: the network lagged). **Go on as soon as the desktop is there**: after 150 s idle the screensaver starts, after 300 s it locks and the display goes off (in the rehearsal it sat about 8 min: black screen, a key brought up the lock screen, the password and Enter brought the desktop back) | "This disk is the same public image OSEasy installs in part 3: a complete Arch + Omarchy." |
| 2.3 | **Super+Return**, type `fastfetch`, Enter | terminal; its first line is the AI agent setup hint (the public image has no key; expected). fastfetch: KVM Virtual Machine (StratoVirt), Virtio GPU, 2160x1440 120 Hz (after the 2026-10-27 EDID fix), Omarchy 4.0.6, Linux 7.2.12-1.1-aarch64-ARCH, Hyprland 0.56.2, 793 packages (rehearsal 2026-10-27) | 20 s | "This one is a VM, on HarmonyOS's own hypervisor HMV, with Huawei's StratoVirt." (Talk here: the next window halves the terminal) |
| 2.4 | **Super+Shift+B**; when Chromium is up, **Ctrl+L** (or click the address bar), type `omarchy.org`, Enter | Chromium opens on the right and loads the page; no "Restore pages?". Two Omarchy notifications (Update System, Learn Keybindings) stay at the top right over the end of Chromium's toolbar; ignore them | 30 s | "The network goes through 鸿融's own virtual bridge." |
| 2.5 | **Super+2**, then **Super+1** | empty workspace 2, then back to terminal and browser | 10 s | "Inside the VM it actually renders at 120 Hz, but 鸿融 shows it fullscreen at 60 Hz; that's on 鸿融's side." (the 2026-10-27 image in 鸿融: `hyprctl monitors` 2160x1440@119.98) |
| 2.6 | Bring 鸿融's main window forward: tap 鸿融 in the dock if it shows; otherwise [backstage] `ssh ohdev aa start -b com.huawei.medivh -a EntryAbility` | the card: 当前状态 **运行中** (green); 关机 and 暂停 active | 5 s | "Our system has 鸿融's guest agent, so 鸿融 knows it is running." |
| 2.7 | Tap **关机** (鸿融's window may open at a different position each time; aim at the button) | shutdown messages scroll by, then 鸿融 returns to the VM page by itself, card 已关机 | 18 s (rehearsal 2026-10-27) | "Shutting down is 鸿融's own button, too." |
| 2.8 | Confirm it is off: card 已关机, 开机 can be tapped ([backstage] `pidof stratovirt` empty) | | 5 s | |

### After the demo ([backstage], about 2 min)

With 鸿融's VM off, put Yao's main disk back: `hrswap.sh restore-main
<IMGDIR> <backup dir>`, and check `vm.qcow2` and `stratovirt-vars` have the
backup's sizes.

### Part 2: if this happens, do this

| Symptom | Do |
|---|---|
| 鸿融 is fullscreen and neither the Home key nor edge swipes get out | Known. If the dock shows, tap 鸿融's dock icon; otherwise [backstage] `ssh ohdev aa start -b com.huawei.medivh -a EntryAbility` |
| "请设置密码" or the 增强服务 guide dialog shows up after 开机 | The preparation was not finished (step 3). Type the password twice, Enter, wait for the one restart, go on |
| The screen goes dark or locks after some idle time | Omarchy's idle defaults: screensaver at 150 s, lock and display off at 300 s. Press a key (Shift) to get the lock prompt, type the password, Enter. Happened in the rehearsal; this recovered it |
| The card keeps saying 已关机 with 关机 greyed out, but the preview is live | The guest agent didn't connect. Tap the preview to get back to the VM and shut down inside with Super+Esc → Shutdown |
| 开机 is refused / nothing happens | Most likely another VM (Docker or OSEasy) is still running. [backstage] `pidof stratovirt`, `ohmarchy-vm stop` for the Docker VM, then tap 开机 again. What 鸿融 shows on screen when refused: **to be confirmed in rehearsal** |
| Typing does nothing, or goes elsewhere | Keys go to the window in front. Click the VM's picture first, then type again |
| The VM hangs; neither 关机 nor Super+Esc works | 更多 → **强制关机** (last resort) |
| No desktop after 3 min | 更多 → 强制关机, go to part 3, show the backup screenshot (`docs/img/hongrong-omarchy-fastfetch.jpg`) |
| **Never** | reboot inside the VM (sometimes hangs; power off and start instead); log out; tap 删除 in 鸿融 |

---

## Part 3: B OSEasy (about 3 min)

Before starting: the 鸿融 VM is shut down (2.9).

> **This flow is being changed**: it used to reinstall from the ISO every time
> (about 3 min); now 再次安装 is meant to boot the already-installed disk. The
> steps below describe the new flow; **the whole part is to be confirmed in
> rehearsal**.

| # | Do | Expect on screen | Wait | Say |
|---|---|---|---|---|
| 3.1 | Tap **OSEasy** in the dock | OSEasy's main page with 再次安装 (to be confirmed in rehearsal) | 2 s | "OSEasy is a third-party VM app made for Windows." |
| 3.2 | Tap **再次安装** | a "正在安装 Windows 11…" window may come first: **expected**, it thinks it is Windows. Then the VM console with an intro carousel on top: tap **收起介绍** | a few s | "The app says Windows 11; what's inside is Omarchy." |
| 3.3 | Wait | Omarchy's Hyprland desktop (auto-login expected, to be confirmed in rehearsal) | **about 10 s** (to be confirmed in rehearsal; the old flow measured 6 s from the reset to the desktop) | "The graphics driver is our patched Linux driver: Linux gets the 3D acceleration OSEasy built for Windows." |
| 3.4 | **Super+Return** for a terminal, type `es2gears_wayland`, Enter | spinning gears | 10 s | "The VM draws 120 frames a second, the screen shows 60, because OSEasy never asks the system for a high refresh rate." |
| 3.5 | **Super+2**, **Super+1**, a few times | smooth switching | 10 s | "With GPU load it ran over 4 hours without an error." |
| 3.6 | Back on the gears window, **Super+W** to close it (apps open faster afterwards) | the gears are gone | 2 s | |
| 3.7 | **Super+Return** for another terminal (foot) | appears almost instantly (measured 0.08 s) | 1 s | "A terminal in 0.08 s." |
| 3.8 | In the terminal type `chromium`, Enter (or Super+Shift+B; whether that opens Chromium is to be confirmed in rehearsal) | a Chromium window (measured 0.8 s) | 2 s | |
| 3.9 | Power off: **Super+Esc → Shutdown** | the VM powers off; OSEasy returns to its UI (what it shows: to be confirmed in rehearsal) | about 20 s | |

**After the OSEasy VM is off, never tap 取消**: on the 安装失败-style dialog,
取消 **deletes the VM**, and the next demo then needs a full install from the
ISO (about 3 min, plus a backstage disk push). Tap only 再次安装, or tap
nothing and close OSEasy's window.

### Part 3: if this happens, do this

| Symptom | Do |
|---|---|
| "检测到有其它虚拟机正在运行" (another VM is running) and it won't start | First: is 鸿融 really off? The Docker VM? [backstage] `pidof stratovirt`; if something runs, stop it and try once more. **If nothing runs and it is still refused**: this is a known, still-open issue (the system reports a VM although there is no VM process). On stage: **skip B**, say "OSEasy has a known issue we're still chasing", show the backup video and wrap up |
| "正在安装 Windows 11…" appears | Expected; wait, or bring the VM console window to the front |
| The intro carousel covers the picture | Tap 收起介绍 |
| No desktop after 30 s | Bring OSEasy's console window to the front and look. Still nothing: skip B, show the backup video |
| Keys do nothing | Click the VM picture first so it has focus |
| A window is stuck | Super+W, go on |
| After power-off OSEasy shows 安装失败 | Expected in the old flow (OSEasy forgets a non-Windows VM once it is off). **Don't tap 取消.** What the new flow does: to be confirmed in rehearsal |

---

## Backup plan

Rule: **if a part is stuck for more than 30 s (Docker 1 min, 鸿融 boot 3 min),
drop it**, say "here is a recording", play the backup, and move on. Before the
next part, still make sure no VM is running.

| Part | Backup material | Status |
|---|---|---|
| D native | video: `<to record: D end to end, about 80 s>`; screenshot: `docs/img/autostart/02-app-open.jpeg` | video to record |
| I Docker | screenshot: `docs/img/autostart/03-docker-cold.jpeg` | exists |
| C 鸿融 | video: `<to record: C2 end to end>`; screenshot: `docs/img/hongrong-omarchy-fastfetch.jpg` | video to record |
| B OSEasy | video: `<to record: B 再次安装 → desktop → es2gears>`; screenshot: `docs/img/oseasy-mb14-kmsgl-1.jpeg` | video to record |

Keep the backups on another computer (or a USB stick; don't depend on the
HarmonyOS PC for them), opened in advance.

---

## [backstage] Command cheat sheet (for the helper, not for Yao)

All run on the helper's own laptop; the shell on `ohdev` is root.

| Purpose | Command |
|---|---|
| Is any VM running (empty = none) | `ssh ohdev pidof stratovirt` |
| Stop the background Docker VM | `ssh ohdev sh /data/local/kaidashi/bin/ohmarchy-vm stop` |
| Native desktop status / start / restart | `ssh ohdev sh /data/local/archtest/bin/omarchy desktop status` (`start`, `stop`) |
| Open the native desktop app | `ssh ohdev aa start -a EntryAbility -b com.ohmarchy.display` |
| Bring 鸿融 to the front (to leave fullscreen) | `ssh ohdev aa start -b com.huawei.medivh -a EntryAbility` |
| Docker gate log | `ssh ohdev tail /data/local/kaidashi/ownvm/svc/gate.log` |

---

## Q&A cheat sheet

**Q: What are routes A to L, and why show only D, I, C and B?**
A: A is command-line tools in HarmonyOS's built-in Linux container, no
desktop; E (bare metal) hasn't started; F runs only in the emulator on a Mac,
in pure software, slowly; G (铠大师) and H (Aetherium on the device) are
confirmed dead ends; J (Linux programs signed into an app, no root) runs only
busybox so far; K hasn't started; L (Linux in the browser engine) is paused.
D, I, C and B are the ones that can be shown.

**Q: Can you sum it up?**
A: Two directions. **One: plug and play in VM apps** (B, C): no root, works
today; what's missing is in the apps themselves (60 Hz, OSEasy designed for
Windows). **Two: native** (D + I): the best result
(120 Hz, the GPU directly, 74 of 78 apps open in under 3 s) but it needs root.

**Q: Why only 60 Hz in the VM apps?**
A: HarmonyOS switches the panel to 120 Hz only when a visible window asks for
it. 鸿融 and OSEasy never ask. The guests do render at 120 Hz (119.98 Hz in
鸿融; OSEasy's host side receives 120 frames/s); the apps present them at
60 Hz. The native desktop's app asks for 120 Hz, hence 119 fps.

**Q: Why does D need root?**
A: Setting up the Arch environment needs chroot and mounts, and a small root
helper hands the GPU connection to the app. An ordinary app can't run programs
that aren't signed into its package (XPM code integrity), and doesn't get the
kernel features it would need.

**Q: What would HarmonyOS need to provide for native without root?**
A: Four things:
1. **Let apps run the Linux programs they bring** (relax XPM for this case, or
   a dedicated signature/permission);
2. **Kernel features**: user namespaces, cgroup v2, shared `CLONE_FS` (for
   sandboxes, containers, Chromium's sandbox);
3. **Open the VM API** (today a hard-coded allow-list of 8 apps; the Docker
   VM needs it);
4. **Fix HMV's ID-register bug** (newer kernels reading an unknown ID register
   hang the vCPU; we sent Huawei a report).

With the first two, D runs without root at today's performance.

**Q: How does Docker work on the native desktop?**
A: The HarmonyOS kernel lacks the namespaces and cgroups containers need, so
Docker runs in a small headless VM of our own: root starts the system's own
StratoVirt directly on `/dev/hmv` (HarmonyOS's hypervisor). **Not 鸿融**, and
**not the built-in 融合开发引擎** (that is a container and can't run Docker).
The first `docker` starts it (hello-world in about 27 s), it stops about 40 s after use, and
the home directory is shared in, so bind mounts work as usual. Idle, it costs
the host about 1.2 GB of memory.

**Q: Why only one VM at a time?**
A: HarmonyOS's hypervisor allows one VM system-wide; a second one is refused
(401 "Not support vm multi-instance"). That's why the demo hands over part by
part.

**Q: How does 鸿融 know the VM is running?**
A: 鸿融 shows 运行中 only after its guest agent inside the VM reports in. 鸿融
ships that agent for UOS and Kylin only; we install it on Arch too, at the
first password setup, so the card says 运行中 and 鸿融's 关机 works.

**Q: Can ordinary users get this?**
A: Direction one (B, C) needs no root; a public release is being prepared:
images on GitHub Releases plus instructions for ordinary users.

---

## To be confirmed in rehearsal

1. ~~The native desktop starts by itself at boot~~ Confirmed (real reboot on
   2026-10-26: running 50 s after power-on; after a normal login, the first
   screenshot after double-clicking the icon shows the desktop; `pidof
   stratovirt` empty; no backstage commands).
2. ~~Reopening the app after closing it restarts the desktop~~ Confirmed (same
   reboot: closed, double-clicked again, desktop back).
3. Super-key shortcuts in the native desktop: HarmonyOS intercepts the Windows
   key (start menu), so Alt+Shift stands in for Super (right Alt until
   2026-10-27, verified with injected keys); to be pressed by hand on the
   physical keyboard.
4. Where Do Not Disturb and auto screen-off live on the HarmonyOS PC.
5. What 鸿融 shows when 开机 is tapped while another VM (Docker) still runs.
6. ~~Whether 鸿融 leaves fullscreen by itself after a shutdown~~ Confirmed
   (2026-10-27): after 鸿融's 关机 it returns to the VM page, card 已关机.
7. OSEasy's new flow: it shows 再次安装, which boots the installed disk, with
   the desktop in about 10 s.
8. Whether the OSEasy guest logs in automatically.
9. Keyboard shortcuts by hand in the OSEasy VM; whether Super+Shift+B opens
   Chromium.
10. What OSEasy shows after a shutdown from inside, and whether 再次安装 still
    boots directly next time.
11. Whether the OSEasy trial is still valid.
12. The false "检测到有其它虚拟机正在运行" refusal (known, open); note how often
    it shows up in rehearsal.
13. The Docker VM really is off within 1 min of hello-world (`pidof stratovirt` empty).
14. Backup videos recorded and placed on another computer.

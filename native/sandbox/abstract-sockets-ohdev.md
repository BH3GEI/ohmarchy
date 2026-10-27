# Abstract Unix sockets on ohdev that the sandbox can reach

HongMeng does not keep abstract Unix socket names per network namespace (checked
2026-10-28: a process on the host connected to a name bound inside the sandbox's own
network namespace). So every abstract socket on the host that takes connections or
datagrams can be reached from inside the sandbox, whatever its namespaces. What
stands between the sandbox and these is the service's own checks (peer uid,
SELinux); the sandbox's processes run in the `su` domain as root or its user.

Taken on ohdev, 2026-10-28 04:30 (local), demo and sandbox helper running, from
`/proc/net/unix` (HongMeng prints Flags unpadded: `10000` is listening) and the
owners' `/proc/<pid>/fd`. Nothing was sent to any of them.

| Name | Type | Owner (pid, uid, SELinux) | Whose | Risk |
|---|---|---|---|---|
| `@/data/service/el1/public/wifi/sockets/wpa/wlan0` | datagram, bound | wpa_host (6277, 1010, `wifi_host`) | HarmonyOS: Wi-Fi (wpa_supplicant's control interface) | High: whoever can send to it can command Wi-Fi (scan, connect, read and change saved networks). Not tried. |
| `@tc_ns_socket` | stream, listening | teecd (696, 6668, `teecd`) | HarmonyOS: TEE client daemon (trusted execution environment) | High if it trusts its callers: the way to secure-world services. Not tried. |
| `@DUBAI_BUFFERED_LOG` | stream, listening | hiview (688, 1201, `hiview`) | HarmonyOS: hiview (system events, power statistics) | Low to medium: log and event injection. Not tried. |
| `@ohjpid-control` | stream, listening | hdcd (2383, 0, `su`) | HarmonyOS: hdcd, the device debugging daemon (JDWP-style process list) | Medium: debugging-side information; on a production device hdcd is off. |
| `@ohmarchy-display`, `@ohmarchy-vtest` | stream, listening | Hyprland (51487), vtest-broker (8220), uid 60000 | ours: the demo version | The demo's desktop and GPU broker; they serve the demo app's uid only. |
| `@ohmsbx-ctl` | stream, listening | ohm-sandboxd (12788, 0, `su`) | ours: the sandbox's helper | Answers only the sandbox app's uid (SO_PEERCRED); root inside the sandbox is refused (checked). |

Besides these: 26 connected stream and 18 connected seqpacket sockets with abstract
names (autobound `@0xxxx` names among them); connected sockets take no new peers.

The sandbox's own display, sound and GPU sockets (`@ohmsbx-display`, `-audio`,
`-vtest`; listening only while the sandbox desktop runs) are listed by the same
reasoning in the other direction: any process on the host can connect to them, and
they serve only the sandbox app's uid.

To close: abstract names per network namespace, as Linux keeps them
(docs/handover.zh-CN.md 3(a)); until then, a MAC domain for the sandbox that is
denied `connectto`/`sendto` on unix sockets outside its own (part of the domain
request in 3(b)).

#!/usr/bin/env python3
"""Print a sing-box configuration for one VLESS (Reality) server.

The server comes from the environment variable PROXY_VLESS_URL
(vless://UUID@HOST:PORT?security=reality&sni=...&pbk=...&sid=...&fp=...&flow=...),
never from the command line, so it does not show up in the process list.
Inbounds: a tun device (transparent proxy for every program) and a mixed
HTTP/SOCKS proxy on 127.0.0.1:7890. Private addresses, the Chinese mirrors
below and the domains listed in DIRECT_FILE (one per line, optional) go
direct; everything else goes through the server.
SINGBOX_TUN=0 leaves out the tun device (the native desktop shares the
HarmonyOS host's network, whose routes must not change): programs then use
the mixed proxy through http_proxy/https_proxy/all_proxy.
Usage: PROXY_VLESS_URL=... [SINGBOX_TUN=0] vless2singbox.py [DIRECT_FILE] > config.json
"""
import json
import os
import sys
from urllib.parse import parse_qs, unquote, urlsplit

DIRECT = [
    "tuna.tsinghua.edu.cn", "ustc.edu.cn", "npmmirror.com", "goproxy.cn",
    "archlinuxarm.org", "aliyun.com", "huaweicloud.com",
]

u = urlsplit(os.environ["PROXY_VLESS_URL"].strip())
if u.scheme != "vless" or not u.username or not u.hostname or not u.port:
    sys.exit("PROXY_VLESS_URL is not vless://UUID@HOST:PORT?...")
q = {k: v[0] for k, v in parse_qs(u.query).items()}

direct = list(DIRECT)
if len(sys.argv) > 1 and os.path.exists(sys.argv[1]):
    with open(sys.argv[1]) as f:
        direct += [l.strip() for l in f if l.strip() and not l.startswith("#")]

proxy = {"type": "vless", "tag": "proxy", "server": u.hostname,
         "server_port": u.port, "uuid": unquote(u.username)}
if q.get("flow"):
    proxy["flow"] = q["flow"]
if q.get("security") in ("tls", "reality"):
    tls = {"enabled": True, "server_name": q.get("sni", u.hostname)}
    if q.get("fp"):
        tls["utls"] = {"enabled": True, "fingerprint": q["fp"]}
    if q["security"] == "reality":
        tls["reality"] = {"enabled": True, "public_key": q["pbk"],
                          "short_id": q.get("sid", "")}
    proxy["tls"] = tls

config = {
    "log": {"level": "warn"},
    "dns": {
        "servers": [
            {"type": "https", "tag": "remote", "server": "1.1.1.1", "detour": "proxy"},
            {"type": "local", "tag": "local"},
        ],
        "rules": [{"domain_suffix": direct + [u.hostname], "server": "local"}],
        "final": "remote",
        "strategy": "ipv4_only",
    },
    "inbounds": [
        {"type": "tun", "tag": "tun-in", "interface_name": "singtun0",
         "address": ["172.19.0.1/30"], "auto_route": True,
         "strict_route": True, "stack": "mixed"},
        {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1",
         "listen_port": 7890},
    ],
    "outbounds": [proxy, {"type": "direct", "tag": "direct"}],
    "route": {
        "rules": [
            {"action": "sniff"},
            {"protocol": "dns", "action": "hijack-dns"},
            {"ip_is_private": True, "outbound": "direct"},
            {"domain_suffix": direct, "outbound": "direct"},
        ],
        "final": "proxy",
        "auto_detect_interface": True,
        "default_domain_resolver": "local",
    },
}
if os.environ.get("SINGBOX_TUN", "1") == "0":
    config["inbounds"] = [i for i in config["inbounds"] if i["type"] != "tun"]
    config["route"]["rules"] = [r for r in config["route"]["rules"] if r.get("protocol") != "dns"]
    # binding to the default interface needs netlink, which the HongMeng kernel
    # does not give ("missing default interface"); without tun it is not needed
    del config["route"]["auto_detect_interface"]
json.dump(config, sys.stdout, indent=2)
print()

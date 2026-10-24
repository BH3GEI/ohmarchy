#!/usr/bin/env python3
# oseasy-agent: the guest side of Oseasy's Linux-guest channel, first a recorder.
#
# The Oseasy app connects from the host (172.16.100.1) to tcp://172.16.100.2 and
# speaks a framed protocol (UInt32LE size + tag, commands such as heartbeat,
# install_complete, auth_confirm, shutdown, reboot, stopvm-async, stop-linux).
# Its bytecode is protected, so the port and the framing are taken from the wire:
# nftables redirects every TCP connection from the host (except ssh) to this
# listener, which logs the original destination port and the bytes it receives
# (hex and text) to the journal. Once the protocol is known, the replies
# (install_complete, heartbeat) go here.
import os, socket, struct, sys, threading, time, subprocess

LISTEN = 47000
HOST = "172.16.100.1"
SO_ORIGINAL_DST = 80

def log(msg):
    print(msg, flush=True)

def nft_setup():
    rules = f"""
table ip oseasy_agent {{
  chain pre {{
    type nat hook prerouting priority dstnat; policy accept;
    ip saddr {HOST} tcp dport != 22 tcp dport != {LISTEN} redirect to :{LISTEN}
  }}
}}
"""
    try:
        subprocess.run(["nft", "delete", "table", "ip", "oseasy_agent"], stderr=subprocess.DEVNULL)
        subprocess.run(["nft", "-f", "-"], input=rules.encode(), check=True)
        log("redirect via nft")
    except (OSError, subprocess.CalledProcessError):
        subprocess.run(["iptables", "-t", "nat", "-I", "PREROUTING", "-s", HOST, "-p", "tcp",
                        "-m", "multiport", "!", "--dports", f"22,{LISTEN}",
                        "-j", "REDIRECT", "--to-ports", str(LISTEN)], check=False)
        log("redirect via iptables")
    # ufw's INPUT policy drops unknown ports; allow the listener from the host
    subprocess.run(["iptables", "-I", "INPUT", "-s", HOST, "-p", "tcp", "--dport", str(LISTEN), "-j", "ACCEPT"],
                   stderr=subprocess.DEVNULL)

def original_dst(conn):
    try:
        raw = conn.getsockopt(socket.SOL_IP, SO_ORIGINAL_DST, 16)
        port, ip = struct.unpack_from("!2xH4s", raw)
        return socket.inet_ntoa(ip), port
    except OSError:
        return None, None

def handle(conn, addr):
    ip, port = original_dst(conn)
    log(f"connect from {addr[0]}:{addr[1]} to {ip}:{port}")
    conn.settimeout(120)
    total = 0
    try:
        while True:
            data = conn.recv(65536)
            if not data:
                break
            total += len(data)
            log(f"  [{port}] {len(data)} bytes: {data[:256].hex()}")
            log(f"  [{port}] text: {data[:256]!r}")
            if len(data) >= 8:
                size, tag = struct.unpack_from("<II", data)
                log(f"  [{port}] as <II: size={size} tag={tag}")
    except OSError as e:
        log(f"  [{port}] {e}")
    log(f"close {addr[0]}:{addr[1]} ({port}) after {total} bytes")
    conn.close()

def main():
    nft_setup()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", LISTEN))
    s.listen(16)
    log(f"oseasy-agent recording on :{LISTEN} (all TCP from {HOST} except ssh)")
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    main()

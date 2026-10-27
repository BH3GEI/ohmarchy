#!/usr/bin/env python3
"""Minimal, interoperable Linux guest agent for OSEasy (prototype).

Goal: make OSEasy treat a Linux VM as "installed / can power on" instead of only
offering 再次安装 (which wipes the disk). It does this by speaking OSEasy's own
guest-agent link protocol (virtio-serial + length/checksum framing + protobuf
RPC), reverse-engineered in docs/oseasy-agent-protocol.md.

Scope / ethics (set with the supervisor):
  * Interop only. We DO NOT send `authString` and DO NOT attempt the vendor's
    "authstring handshake"; `authString` is an optional field. If OSEasy refuses
    the plain handshake or demands authString, that is an authentication barrier
    — STOP and record it in docs/oseasy-vendor-request.md; do not bypass it.
  * `clientName` is our own honest name ("ohmarchy-linux-agent"); we never
    impersonate the vendor's agent.

Status: the frame codec (section B) and message schema (section A) are known and
unit-tested. Three things are only resolvable on-device and are marked TODO:
  (1) which virtio-serial port carries the `link` service,
  (2) the `connectionMode` string value and the handshake `msgType`,
  (3) the method-id registry (keepalive / install-complete / CapInfo query).
The agent logs every inbound frame so the bring-up run can fill these in.
"""

import glob
import os
import sys
import time

import frame
import pb

CLIENT_NAME = "ohmarchy-linux-agent"

# TODO(on-device): confirmed handshake parameters. These are placeholders; the
# bring-up run determines them from what OSEasy accepts / sends.
CONNECTION_MODE = os.environ.get("OSEASY_CONN_MODE", "command")
HANDSHAKE_MSGTYPE = int(os.environ.get("OSEASY_HS_MSGTYPE", "0"))
DATA_MSGTYPE = int(os.environ.get("OSEASY_DATA_MSGTYPE", "0"))
KEEPALIVE_SECONDS = int(os.environ.get("OSEASY_KEEPALIVE", "5"))

# Host-side virtio-serial port names seen in the StratoVirt command line. The
# right one for the main link still needs on-device confirmation.
PORT_NAME_CANDIDATES = [
    "winbox_serial0", "winbox_serial1",
    "additions_vioser0", "additions_vioser1",
]


def log(*a):
    print("[ohmarchy-oseasy-agent]", *a, file=sys.stderr, flush=True)


def find_vport(candidates=PORT_NAME_CANDIDATES):
    """Return the /dev/vportNpX whose /sys name matches a candidate, else None."""
    found = {}
    for name_path in glob.glob("/sys/class/virtio-ports/*/name"):
        try:
            with open(name_path) as fh:
                nm = fh.read().strip()
        except OSError:
            continue
        port = os.path.basename(os.path.dirname(name_path))  # e.g. vport2p1
        found[nm] = "/dev/" + port
    log("virtio-ports present:", found)
    for cand in candidates:
        if cand in found:
            return found[cand]
    return None


class Link:
    def __init__(self, path):
        self.fd = os.open(path, os.O_RDWR)
        log("opened", path)

    def recv_exactly(self, n):
        buf = b""
        while len(buf) < n:
            chunk = os.read(self.fd, n - len(buf))
            if not chunk:
                time.sleep(0.05)
                continue
            buf += chunk
        return buf

    def send(self, msg_type, body):
        os.write(self.fd, frame.encode(msg_type, body))

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass


def do_handshake(link):
    body = pb.encode_handshake(CONNECTION_MODE, CLIENT_NAME)
    log("sending handshake: connectionMode=%r clientName=%r (no authString)"
        % (CONNECTION_MODE, CLIENT_NAME))
    link.send(HANDSHAKE_MSGTYPE, body)


def serve(link):
    last_keepalive = 0.0
    while True:
        # keepalive heartbeat (methodID TODO; structure is a link.Call)
        now = time.time()
        if now - last_keepalive >= KEEPALIVE_SECONDS:
            # TODO(on-device): real keepalive methodID. Logged so bring-up can
            # observe whether OSEasy expects one and what id it uses.
            last_keepalive = now

        msg_type, data = frame.read_frame(link.recv_exactly)
        call = pb.decode_call(data)
        log("RX frame type=%d len=%d call=%s" % (msg_type, len(data), call))
        # TODO(on-device): dispatch by call["methodID"] — reply to a CapInfo
        # query with our CapSet, ack keepalive, etc. Until the method registry
        # is known we only observe.


def main():
    port = find_vport()
    if port is None:
        log("no matching virtio-serial port; set PORT_NAME_CANDIDATES after"
            " checking /sys/class/virtio-ports/*/name on the guest")
        return 1
    link = Link(port)
    try:
        do_handshake(link)
        serve(link)
    finally:
        link.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

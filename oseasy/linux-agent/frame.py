"""OSEasy guest-agent link frame codec.

Wire format reverse-engineered from the vendor's Windows agent
(agent_service.exe, COMMON::LinkBase::ReceiveMessage); see
docs/oseasy-agent-protocol.md section B. This is a clean-room, interoperable
re-implementation — it bypasses no authentication and copies no vendor code.

A message on the vioserial link is a 7-byte header followed by the body:

    offset  size  field         encoding
    0       4     payloadSize   uint32 big-endian   (sanity: payloadSize-1 <= 0x0FFFFFFF)
    4       1     msgType       uint8               (0..3)
    5       2     checksum      uint16 big-endian
    7       N     body          payloadSize bytes   (serialized Guest.protobuf.link message)

The checksum is a plain additive sum of the five header bytes before it:

    checksum = (h[0] + h[1] + h[2] + h[3] + h[4]) & 0xFFFF
"""

import struct

HEADER_LEN = 7
MAX_PAYLOAD = 0x0FFFFFFF


class ChecksumError(ValueError):
    pass


def header_checksum(first5: bytes) -> int:
    """16-bit additive checksum of the first five header bytes."""
    if len(first5) < 5:
        raise ValueError("need at least 5 header bytes")
    return sum(first5[:5]) & 0xFFFF


def encode(msg_type: int, body: bytes) -> bytes:
    """Build a full frame (header + body) for a body already serialized."""
    if not 0 <= msg_type <= 3:
        raise ValueError("msg_type must be 0..3")
    size = len(body)
    if size > MAX_PAYLOAD:
        raise ValueError("body larger than MAX_PAYLOAD")
    head5 = struct.pack(">IB", size, msg_type)  # 4-byte size + 1-byte type
    cksum = header_checksum(head5)
    return head5 + struct.pack(">H", cksum) + body


def decode_header(hdr: bytes):
    """Validate a 7-byte header; return (payloadSize, msgType)."""
    if len(hdr) != HEADER_LEN:
        raise ValueError("header must be exactly 7 bytes")
    size, msg_type = struct.unpack(">IB", hdr[:5])
    cksum = struct.unpack(">H", hdr[5:7])[0]
    want = header_checksum(hdr[:5])
    if cksum != want:
        raise ChecksumError("checksum mismatch: got 0x%04x want 0x%04x" % (cksum, want))
    if size > 0 and (size - 1) > MAX_PAYLOAD:
        raise ValueError("payloadSize out of range: %d" % size)
    return size, msg_type


def read_frame(recv_exactly):
    """Read one frame using a `recv_exactly(n) -> bytes` callable.

    Returns (msgType, body). Raises ChecksumError / ValueError on a bad frame.
    """
    hdr = recv_exactly(HEADER_LEN)
    size, msg_type = decode_header(hdr)
    body = recv_exactly(size) if size else b""
    return msg_type, body

"""Minimal protobuf codec for the Guest.protobuf.link messages we need.

Hand-rolled so the agent has no external dependency (the Omarchy guest image
only needs python3). Schema reverse-engineered from the vendor agent's embedded
FileDescriptorProtos; see docs/oseasy-agent-protocol.md section A.

Messages (field numbers / proto types):
  Handshake { connectionMode:1 string, clientName:2 string, authString:3 bytes }
  Call      { callID:1 uint32, methodID:2 uint32, parameters:3 bytes, async:4 bool }
  Result    { callID:1 uint32, response:2 bytes, errorCode:3 int32 }
  CapInfo   { cap:1 int32, status:2 int32 }
  CapSet    { capInfo:1 repeated CapInfo }

Wire types used: 0 = varint (int32/uint32/bool), 2 = length-delimited (string/bytes/message).
"""

# ---- primitives ----

def write_varint(n: int) -> bytes:
    if n < 0:
        n &= (1 << 64) - 1  # two's-complement for negative int32/int64
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def read_varint(buf: bytes, pos: int):
    shift = 0
    result = 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, pos
        shift += 7


def _tag(field: int, wire: int) -> bytes:
    return write_varint((field << 3) | wire)


def field_varint(field: int, value: int) -> bytes:
    return _tag(field, 0) + write_varint(value)


def field_bytes(field: int, value: bytes) -> bytes:
    return _tag(field, 2) + write_varint(len(value)) + value


def field_string(field: int, value: str) -> bytes:
    return field_bytes(field, value.encode("utf-8"))


def parse_fields(buf: bytes):
    """Yield (field_number, wire_type, value) for each field.

    value is an int for varint fields, bytes for length-delimited fields.
    """
    pos = 0
    n = len(buf)
    while pos < n:
        tag, pos = read_varint(buf, pos)
        field = tag >> 3
        wire = tag & 7
        if wire == 0:
            value, pos = read_varint(buf, pos)
        elif wire == 2:
            length, pos = read_varint(buf, pos)
            value = buf[pos:pos + length]
            pos += length
        elif wire == 5:
            value = buf[pos:pos + 4]
            pos += 4
        elif wire == 1:
            value = buf[pos:pos + 8]
            pos += 8
        else:
            raise ValueError("unsupported wire type %d" % wire)
        yield field, wire, value


# ---- messages ----

def encode_handshake(connection_mode: str, client_name: str) -> bytes:
    # authString (field 3) deliberately omitted: it is an optional field and we
    # do not attempt the vendor's authstring handshake (see agent-protocol doc).
    return field_string(1, connection_mode) + field_string(2, client_name)


def encode_call(call_id: int, method_id: int, parameters: bytes = b"", async_: bool = False) -> bytes:
    out = field_varint(1, call_id) + field_varint(2, method_id)
    if parameters:
        out += field_bytes(3, parameters)
    if async_:
        out += field_varint(4, 1)
    return out


def decode_call(buf: bytes) -> dict:
    out = {"callID": 0, "methodID": 0, "parameters": b"", "async": False}
    for field, _wire, value in parse_fields(buf):
        if field == 1:
            out["callID"] = value
        elif field == 2:
            out["methodID"] = value
        elif field == 3:
            out["parameters"] = value
        elif field == 4:
            out["async"] = bool(value)
    return out


def encode_result(call_id: int, response: bytes = b"", error_code: int = 0) -> bytes:
    out = field_varint(1, call_id)
    if response:
        out += field_bytes(2, response)
    if error_code:
        out += field_varint(3, error_code)
    return out


def decode_result(buf: bytes) -> dict:
    out = {"callID": 0, "response": b"", "errorCode": 0}
    for field, _wire, value in parse_fields(buf):
        if field == 1:
            out["callID"] = value
        elif field == 2:
            out["response"] = value
        elif field == 3:
            out["errorCode"] = value
    return out


def encode_capinfo(cap: int, status: int) -> bytes:
    out = b""
    if cap:
        out += field_varint(1, cap)
    if status:
        out += field_varint(2, status)
    return out


def encode_capset(cap_infos) -> bytes:
    # repeated CapInfo capInfo = 1;
    return b"".join(field_bytes(1, encode_capinfo(c, s)) for (c, s) in cap_infos)

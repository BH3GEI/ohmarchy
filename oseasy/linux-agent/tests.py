#!/usr/bin/env python3
"""Unit tests for the frame + protobuf codecs. Run: python3 tests.py"""

import struct
import unittest

import frame
import pb


class TestFrame(unittest.TestCase):
    def test_checksum_known(self):
        # header for empty body, type 1: size=0, type=1 -> sum = 1
        self.assertEqual(frame.header_checksum(b"\x00\x00\x00\x00\x01"), 1)
        # size=5, type=0 -> sum = 5
        self.assertEqual(frame.header_checksum(b"\x00\x00\x00\x05\x00"), 5)
        # all-0xff first five -> 5*255 = 1275
        self.assertEqual(frame.header_checksum(b"\xff\xff\xff\xff\xff"), 1275)

    def test_encode_known_bytes(self):
        self.assertEqual(frame.encode(1, b""), b"\x00\x00\x00\x00\x01\x00\x01")
        self.assertEqual(
            frame.encode(0, b"hello"),
            b"\x00\x00\x00\x05\x00\x00\x05hello",
        )

    def test_roundtrip(self):
        for mtype in range(4):
            for body in (b"", b"x", b"A" * 1000, bytes(range(256))):
                f = frame.encode(mtype, body)
                size, mt = frame.decode_header(f[:frame.HEADER_LEN])
                self.assertEqual(mt, mtype)
                self.assertEqual(size, len(body))
                self.assertEqual(f[frame.HEADER_LEN:], body)

    def test_bad_checksum_raises(self):
        f = bytearray(frame.encode(0, b"hi"))
        f[5] ^= 0xFF  # corrupt checksum high byte
        with self.assertRaises(frame.ChecksumError):
            frame.decode_header(bytes(f[:frame.HEADER_LEN]))

    def test_read_frame_with_recv(self):
        wire = frame.encode(2, b"payload-bytes")
        buf = {"pos": 0}

        def recv_exactly(n):
            chunk = wire[buf["pos"]:buf["pos"] + n]
            buf["pos"] += n
            if len(chunk) != n:
                raise EOFError
            return chunk

        mt, body = frame.read_frame(recv_exactly)
        self.assertEqual(mt, 2)
        self.assertEqual(body, b"payload-bytes")

    def test_type_range(self):
        with self.assertRaises(ValueError):
            frame.encode(4, b"")


class TestProtobuf(unittest.TestCase):
    def test_varint_roundtrip(self):
        for n in (0, 1, 127, 128, 300, 16384, 2**32 - 1):
            enc = pb.write_varint(n)
            val, pos = pb.read_varint(enc, 0)
            self.assertEqual(val, n)
            self.assertEqual(pos, len(enc))

    def test_varint_known(self):
        self.assertEqual(pb.write_varint(300), b"\xac\x02")
        self.assertEqual(pb.write_varint(1), b"\x01")

    def test_handshake_known_bytes(self):
        # field1 string "cmd", field2 string "ohmarchy-linux-agent"
        enc = pb.encode_handshake("cmd", "ohmarchy-linux-agent")
        self.assertEqual(
            enc,
            b"\x0a\x03cmd\x12\x14ohmarchy-linux-agent",
        )

    def test_call_roundtrip(self):
        enc = pb.encode_call(call_id=7, method_id=42, parameters=b"abc", async_=True)
        d = pb.decode_call(enc)
        self.assertEqual(d["callID"], 7)
        self.assertEqual(d["methodID"], 42)
        self.assertEqual(d["parameters"], b"abc")
        self.assertTrue(d["async"])

    def test_call_minimal(self):
        d = pb.decode_call(pb.encode_call(1, 2))
        self.assertEqual((d["callID"], d["methodID"], d["parameters"], d["async"]),
                         (1, 2, b"", False))

    def test_result_roundtrip(self):
        enc = pb.encode_result(call_id=9, response=b"ok", error_code=0)
        d = pb.decode_result(enc)
        self.assertEqual(d["callID"], 9)
        self.assertEqual(d["response"], b"ok")
        self.assertEqual(d["errorCode"], 0)

    def test_capset(self):
        enc = pb.encode_capset([(1, 1), (2, 0)])
        # two length-delimited CapInfo submessages under field 1
        fields = list(pb.parse_fields(enc))
        self.assertEqual(len(fields), 2)
        for field, wire, value in fields:
            self.assertEqual(field, 1)
            self.assertEqual(wire, 2)
            self.assertIsInstance(value, (bytes, bytearray))


if __name__ == "__main__":
    unittest.main(verbosity=2)

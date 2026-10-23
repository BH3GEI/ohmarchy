#!/usr/bin/env python3
"""Patch the Aetherium test HAP so its QEMU boots Omarchy with a display.

usage: patch_aetherium.py IN.hap OUT.hap

Only the release pinned in emulator/config.sh is supported: every patch checks
the original bytes first and the result is compared with the hashes of the
build that was verified in the emulator.

1. libqemu_hmos.so passes `-tpmdev emulator,id=tpm0` for every `virt` machine,
   but this build of libqemu_full.so lacks the built-in TPM patch, so
   qemu_init exits with "tpm-emulator: parameter 'chardev' is missing".
   "-tpmdev" is built inline (mov/movk immediates), so the two instructions are
   changed to build "-L" instead; `emulator,id=tpm0` becomes a harmless extra
   firmware search path.
2. The `-device tpm-tis-device,tpmdev=tpm0` that follows becomes
   `-device virtio-gpu-pci`. The app maps the virtio-gpu-pci display choice to
   virtio-gpu-device (MMIO), and virt's virtio-mmio transport is legacy, which
   virtio-gpu rejects (the guest shows status 0x83 and no /dev/dri/card0).
   The PCI device is modern, has a UEFI GOP driver and becomes VNC console 0.
3. The stand-alone "-tpmdev" string in .rodata is blanked to "-L" as well
   (unused by the boot path; kept so the output matches the verified build).
4. resources/rawfile/edk2-aarch64-code.fd is 2 MiB, QEMU 10's virt pflash0
   needs exactly 64 MiB: pad with zeros.
"""
import hashlib, struct, sys, zipfile

LIB = 'libs/arm64-v8a/libqemu_hmos.so'
FW = 'resources/rawfile/edk2-aarch64-code.fd'
LIB_IN = '4f763de63d754f24d145fefad42cb78f02dc5da930fad4274caf1886efd5d3af'
LIB_OUT = '7278ca5ab5a7c62dda915f640678efae8a8ba64d9ccd78ba2151693afa1c858e'
FW_IN = 'a98243d289ba6d4233bb9c856d74c0400e7a2348a6e717eb005154c774c4e7e8'
FW_OUT = '789fcd89b85bba50a019fb7e3ef59d77936325e6d58befb861797f213f0ef3f5'


def sha(b):
    return hashlib.sha256(b).hexdigest()


def patch_insn(d, off, old, new):
    cur = struct.unpack_from('<I', d, off)[0]
    if cur != old:
        sys.exit('unexpected instruction at %#x: %#x' % (off, cur))
    struct.pack_into('<I', d, off, new)


def patch_str(d, off, old, new):
    if d[off:off + len(old) + 1] != old + b'\0':
        sys.exit('unexpected string at %#x: %r' % (off, bytes(d[off:off + len(old)])))
    d[off:off + len(old)] = new.ljust(len(old), b'\0')


def main(src, dst):
    with zipfile.ZipFile(src) as z:
        lib = bytearray(z.read(LIB))
        fw = z.read(FW)
    if sha(lib) != LIB_IN or sha(fw) != FW_IN:
        sys.exit('input HAP is not the pinned Aetherium build')

    # file offsets (text segment: vaddr - 0x1000)
    patch_insn(lib, 0x38b1c, 0x528e85aa, 0x528985aa)  # mov  w10, #0x742d "-t" -> #0x4c2d "-L"
    patch_insn(lib, 0x38b28, 0x72adae0a, 0x72a0000a)  # movk w10, #0x6d70 "pm" -> #0
    patch_str(lib, 0x1d501, b'tpm-tis-device,tpmdev=tpm0', b'virtio-gpu-pci')
    patch_str(lib, 0x1d895, b'-tpmdev', b'-L')
    fw = fw.ljust(64 << 20, b'\0')
    if sha(lib) != LIB_OUT or sha(fw) != FW_OUT:
        sys.exit('patched output does not match the verified build')

    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w') as zout:
        for info in zin.infolist():
            data = {LIB: bytes(lib), FW: fw}.get(info.filename)
            if data is None:
                zout.writestr(info, zin.read(info.filename))
            else:
                info.compress_type = zipfile.ZIP_STORED
                zout.writestr(info, data)
    print(dst)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__.split('\n\n')[1])
    main(*sys.argv[1:])

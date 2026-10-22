#!/usr/bin/env python3
"""Minimal UKI (systemd-stub PE) tool.

  uki.py info   UKI
  uki.py get    UKI SECTION OUT          dump one section's payload
  uki.py build  BASE OUT --linux IMG --initrd A [--initrd B ...] --cmdline STR [--uname STR]

`build` keeps the base UKI's stub and leading sections and rebuilds the trailing
.cmdline/.linux/.initrd sections (they must be the last ones, as in Omarchy's
UKIs). Several --initrd parts are concatenated (cpio archives may be stacked;
each part is padded to 4 bytes).
"""
import struct, sys

def load(path):
    d = bytearray(open(path, 'rb').read())
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    if d[pe:pe + 4] != b'PE\0\0':
        sys.exit(f'{path}: not a PE image')
    nsec = struct.unpack_from('<H', d, pe + 6)[0]
    optsz = struct.unpack_from('<H', d, pe + 20)[0]
    opt = pe + 24
    salign, falign = struct.unpack_from('<II', d, opt + 32)
    secs = []
    for i in range(nsec):
        o = opt + optsz + 40 * i
        name = d[o:o + 8].rstrip(b'\0').decode()
        vs, va, rs, rp = struct.unpack_from('<IIII', d, o + 8)
        secs.append(dict(name=name, off=o, vs=vs, va=va, rs=rs, rp=rp))
    return d, pe, opt, salign, falign, secs

def up(x, a):
    return (x + a - 1) // a * a

def payload(d, s):
    return bytes(d[s['rp']:s['rp'] + min(s['vs'], s['rs'])])

def cmd_info(path):
    d, pe, opt, sa, fa, secs = load(path)
    print(f'{path}: salign={sa:#x} falign={fa:#x}')
    for s in secs:
        print(f"  {s['name']:9s} vs={s['vs']:#10x} va={s['va']:#10x} rs={s['rs']:#10x} rp={s['rp']:#10x}")

def cmd_get(path, name, out):
    d, *_, secs = load(path)
    for s in secs:
        if s['name'] == name:
            open(out, 'wb').write(payload(d, s))
            return
    sys.exit(f'{path}: no section {name}')

def cmd_build(base, out, linux, initrds, cmdline, uname):
    d, pe, opt, sa, fa, secs = load(base)
    tail = ['.cmdline', '.linux', '.initrd']
    names = [s['name'] for s in secs]
    if names[-3:] != tail:
        sys.exit(f'{base}: expected trailing sections {tail}, got {names[-3:]}')
    first = secs[-3]
    body = bytearray(d[:first['rp']])
    if uname is not None:
        for s in secs[:-3]:
            if s['name'] == '.uname':
                u = uname.encode()
                if len(u) > s['rs']:
                    sys.exit('uname too long')
                body[s['rp']:s['rp'] + s['rs']] = u + b'\0' * (s['rs'] - len(u))
                struct.pack_into('<I', body, s['off'] + 8, len(u))
    parts = b''
    for p in initrds:
        blob = open(p, 'rb').read()
        parts += blob + b'\0' * (up(len(blob), 4) - len(blob))
    data = {'.cmdline': cmdline.encode() + b'\0', '.linux': open(linux, 'rb').read(), '.initrd': parts}
    va = up(first['va'], sa)
    for s in secs[-3:]:
        blob = data[s['name']]
        rp = len(body)
        body += blob + b'\0' * (up(len(blob), fa) - len(blob))
        struct.pack_into('<IIII', body, s['off'] + 8, len(blob), va, up(len(blob), fa), rp)
        va = up(va + len(blob), sa)
    struct.pack_into('<I', body, opt + 56, va)          # SizeOfImage
    struct.pack_into('<I', body, opt + 64, 0)           # CheckSum (unused by UEFI)
    open(out, 'wb').write(body)
    print(f'{out}: {len(body)} bytes, kernel {len(data[".linux"])}, initrd {len(parts)}')

def main(a):
    if len(a) >= 2 and a[0] == 'info':
        return cmd_info(a[1])
    if len(a) == 4 and a[0] == 'get':
        return cmd_get(a[1], a[2], a[3])
    if len(a) >= 3 and a[0] == 'build':
        base, out, rest = a[1], a[2], a[3:]
        linux, initrds, cmdline, uname = None, [], None, None
        i = 0
        while i < len(rest):
            k, v = rest[i], rest[i + 1]
            if k == '--linux': linux = v
            elif k == '--initrd': initrds.append(v)
            elif k == '--cmdline': cmdline = v
            elif k == '--uname': uname = v
            else: sys.exit(f'unknown option {k}')
            i += 2
        if not (linux and initrds and cmdline):
            sys.exit('build needs --linux, --initrd and --cmdline')
        return cmd_build(base, out, linux, initrds, cmdline, uname)
    sys.exit(__doc__)

if __name__ == '__main__':
    main(sys.argv[1:])

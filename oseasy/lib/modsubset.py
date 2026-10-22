#!/usr/bin/env python3
"""modsubset.py MODROOT KVER OUTROOT MODULE...

Copy MODULE and everything it depends on (modules.dep) from
MODROOT/usr/lib/modules/KVER into OUTROOT/usr/lib/modules/KVER, plus the
modules.builtin* / modules.order metadata. Built-in modules are skipped.
Run `depmod -b OUTROOT KVER` afterwards to index the subset.
"""
import os, shutil, sys

def main(modroot, kver, outroot, wanted):
    src = os.path.join(modroot, 'usr/lib/modules', kver)
    dst = os.path.join(outroot, 'usr/lib/modules', kver)
    deps, byname = {}, {}
    for line in open(os.path.join(src, 'modules.dep')):
        path, _, rest = line.partition(':')
        deps[path] = rest.split()
        name = os.path.basename(path).split('.ko')[0].replace('-', '_')
        byname[name] = path
    builtin = set()
    for f in ('modules.builtin',):
        p = os.path.join(src, f)
        if os.path.exists(p):
            builtin |= {os.path.basename(l.strip()).split('.ko')[0].replace('-', '_') for l in open(p)}
    todo, keep, missing = [m.replace('-', '_') for m in wanted], set(), []
    while todo:
        m = todo.pop()
        if m in builtin:
            continue
        path = byname.get(m)
        if not path:
            missing.append(m)
            continue
        for p in [path] + deps[path]:
            if p not in keep:
                keep.add(p)
                todo.append(os.path.basename(p).split('.ko')[0].replace('-', '_'))
    for p in sorted(keep):
        os.makedirs(os.path.dirname(os.path.join(dst, p)), exist_ok=True)
        shutil.copy2(os.path.join(src, p), os.path.join(dst, p))
    for f in os.listdir(src):
        if f.startswith('modules.builtin') or f == 'modules.order':
            shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
    print(f'{len(keep)} modules copied; not found (ok if built-in elsewhere): {" ".join(missing) or "-"}')

if __name__ == '__main__':
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])

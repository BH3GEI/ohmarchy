# assemble-sources.py PKGLIST POOL META OUT: PKG_SOURCES for release.sh from what has been
# fetched so far: the archives of the GPL/LGPL package bases in PKGLIST (the
# image's exact list), PACKAGES.txt, and MISSING.txt for every such base
# without an archive (the reason from the runs, or "not fetched yet")
import os, re, sys
lst, pool, meta, out = sys.argv[1:5]
gpl = re.compile(r'(^| )(A|L)?GPL', re.I)
bases = {}  # base -> (ver, [names], lic)
for l in open(lst):
    n, v, b, lic = l.rstrip('\n').split('|', 3)
    if not gpl.search(lic):
        continue
    bases.setdefault(b, [v, [], lic])[1].append(n)
def rows(f):
    d = {}
    for l in open(os.path.join(meta, f)):
        p = l.rstrip('\n').split('|')
        if len(p) >= 4:
            d[(p[0], p[1])] = l.rstrip('\n')   # later lines (second pass) win
    return d
pk, ms = rows('PACKAGES.all'), rows('MISSING.all')
os.makedirs(out, exist_ok=True)
for f in os.listdir(out):
    os.remove(os.path.join(out, f))
P, M, size = [], [], 0
# built by this repository: its source is the release's own source archives
covered = {'linux-aarch64': 'kernel: ohmarchy-TAG-source.tar.gz (hongrong/kernel) + ohmarchy-TAG-upstream-source.tar'}
for b, (v, names, lic) in sorted(bases.items()):
    f = f'{b}-{v}.src.tar.gz'
    src = os.path.join(pool, f)
    if b in covered:
        P.append(f'{names[0]}|{v}|{lic}|{covered[b]}')
    elif os.path.isfile(src):
        os.link(src, os.path.join(out, f)); size += os.path.getsize(src)
        P.append(next((pk[(n, v)] for n in names if (n, v) in pk), f'{names[0]}|{v}|{lic}|(source archive {f})'))
    else:
        M.append(next((ms[(n, v)] for n in names if (n, v) in ms), f'{names[0]}|{v}|{lic}|源码还在下载 / not fetched yet'))
open(os.path.join(out, 'PACKAGES.txt'), 'w').write(''.join(l + '\n' for l in P))
open(os.path.join(out, 'MISSING.txt'), 'w').write(''.join(l + '\n' for l in M))
print(f'{len(bases)} GPL/LGPL package bases: {len(P)} with source ({size >> 20} MiB), {len(M)} missing')

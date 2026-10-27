# render-shots.py: draw demo.sh's real output (ANSI colours kept) as terminal images, one per step
# (docs/img/docker-test). python3 render-shots.py demo-output.txt OUTDIR DATE
import re, sys
from PIL import Image, ImageDraw, ImageFont
src, outdir, date = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()
start = text.index('\x1b[1;35m## 1.')
body = text[start:]
parts = re.split(r'(?=\x1b\[1;35m## )', body)
parts = [p for p in parts if p.strip()]
font = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 26)
bold = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 26, index=1)
small = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 20)
COL = {'1;35': (255, 121, 198), '1;32': (80, 250, 123), '0': (230, 230, 230)}
def lines_of(p):
    out = []
    for raw in p.rstrip('\n').split('\n'):
        segs, cur = [], '0'
        for tok in re.split(r'(\x1b\[[0-9;]*m)', raw):
            m = re.fullmatch(r'\x1b\[([0-9;]*)m', tok)
            if m: cur = m.group(1) or '0'
            elif tok: segs.append((cur, tok))
        out.append(segs)
    return out
footer = f'ohdev (HarmonyOS 7.0.0.115, HongMeng 1.11.13.0), {date}: real output of native/sandbox/docker-test/demo.sh, drawn as an image'
badge = 'TEST BUILD - not production isolation'
n = 0
for p in parts:
    if 'afterwards' in p: p_extra = True
    ls = lines_of(p)
    W = 1700; lh = 36; H = 70 + lh * len(ls) + 80
    im = Image.new('RGB', (W, H), (30, 31, 40)); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 44], fill=(52, 54, 66))
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse([18 + i * 30, 13, 36 + i * 30, 31], fill=c)
    d.text((120, 10), 'ssh ohdev sh -s < demo.sh', font=small, fill=(200, 200, 200))
    bw = d.textlength(badge, font=small)
    d.rectangle([W - bw - 36, 8, W - 14, 36], fill=(180, 60, 60)); d.text((W - bw - 25, 10), badge, font=small, fill=(255, 255, 255))
    y = 62
    for segs in ls:
        x = 24
        for c, t in segs:
            f = bold if c.startswith('1;') else font
            d.text((x, y), t, font=f, fill=COL.get(c, COL['0'])); x += d.textlength(t, font=f)
        y += lh
    d.text((24, H - 46), footer, font=small, fill=(140, 140, 150))
    n += 1
    name = f'{outdir}/docker-test-{n}.png'
    im.save(name); print(name, im.size)

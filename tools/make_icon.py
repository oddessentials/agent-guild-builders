import io
import random
import struct
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

if len(sys.argv) != 2:
    raise SystemExit('Usage: python tools/make_icon.py <agent-guild checkout>')
CONCEPT = Path(sys.argv[1]) / 'concept-art/professional-yard/concepts/bot_courier.png'
OUT = Path(__file__).resolve().parent.parent / 'data/brand'
WHEELS = [((172, 722), (96, 128)), ((596, 795), (113, 137)), ((856, 722), (92, 118))]
UNDERSIDE = [[(195, 690), (505, 690), (505, 832), (470, 832), (262, 806), (195, 790)],
             [(690, 680), (795, 680), (795, 778), (690, 778)]]
FLOOR = 760
GOLD = [(0, (255, 243, 207)), (.28, (246, 220, 156)), (.55, (232, 196, 124)), (.78, (184, 137, 61)), (1, (241, 208, 138))]
CREAM, CREAM_D, ORANGE, VISOR, EYE, TYRE, STEM = (236, 229, 214), (196, 189, 175), (203, 106, 64), (28, 33, 40), (150, 220, 238), (62, 65, 70), (60, 60, 64)


def cut():
    a = cv2.imread(str(CONCEPT)); h, w = a.shape[:2]
    lab = cv2.cvtColor(cv2.medianBlur(a, 9), cv2.COLOR_BGR2LAB).astype(int)
    edge = np.concatenate([lab[:20].reshape(-1, 3), lab[:, :20].reshape(-1, 3), lab[:, -20:].reshape(-1, 3)])
    med = np.median(edge, axis=0); spread = np.percentile(np.abs(edge - med).sum(1), 97)
    near = (np.abs(lab - med).sum(2) < max(16, spread + 5)).astype('uint8')
    _, c = cv2.connectedComponents(near); border = set(np.unique(np.concatenate([c[0], c[-1], c[:, 0], c[:, -1]]))) - {0}
    bg = cv2.morphologyEx(np.isin(c, list(border)).astype('uint8'), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8)) > 0
    m = np.where(bg, cv2.GC_PR_BGD, cv2.GC_PR_FGD).astype(np.uint8)
    m[cv2.erode((~bg).astype('uint8'), np.ones((21, 21), np.uint8)) > 0] = cv2.GC_FGD
    m[cv2.erode(bg.astype('uint8'), np.ones((15, 15), np.uint8)) > 0] = cv2.GC_BGD
    cv2.grabCut(a, m, None, np.zeros((1, 65)), np.zeros((1, 65)), 5, cv2.GC_INIT_WITH_MASK)
    al = np.where((m == 1) | (m == 3), 255, 0).astype('uint8')
    al = cv2.morphologyEx(al, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
    _, c = cv2.connectedComponents(al); ct = np.bincount(c.ravel()); ct[0] = 0; al = np.where(c == ct.argmax(), 255, 0).astype('uint8')
    fl = al.copy(); cv2.floodFill(fl, np.zeros((h + 2, w + 2), np.uint8), (0, 0), 255); al = al | cv2.bitwise_not(fl)
    al = cv2.GaussianBlur(cv2.erode(al, np.ones((3, 3), np.uint8)), (3, 3), 0)
    keep = np.zeros((h, w), np.uint8)
    for centre, axes in WHEELS:
        cv2.ellipse(keep, centre, axes, 0, 0, 360, 255, -1)
    for poly in UNDERSIDE:
        cv2.fillPoly(keep, [np.array(poly, np.int32)], 255)
    al[FLOOR:] = np.minimum(al[FLOOR:], cv2.GaussianBlur(keep, (5, 5), 0)[FLOOR:])
    im = Image.fromarray(cv2.cvtColor(a, cv2.COLOR_BGR2RGB)); im.putalpha(Image.fromarray(al))
    return im.crop(im.getbbox())


def squircle(size, inset, n=5.0):
    ss = 4; yy, xx = (np.mgrid[0:size * ss, 0:size * ss] + 0.5) / ss
    r = size / 2 - inset
    m = (np.abs((xx - size / 2) / r) ** n + np.abs((yy - size / 2) / r) ** n) <= 1
    return Image.fromarray((m * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)


def gold(size):
    t = np.linspace(0, 1, size); col = np.zeros((size, 3))
    for (t0, c0), (t1, c1) in zip(GOLD, GOLD[1:]):
        s = (t >= t0) & (t <= t1); f = ((t[s] - t0) / (t1 - t0))[:, None]
        col[s] = np.array(c0) * (1 - f) + np.array(c1) * f
    return Image.fromarray(np.repeat(col[:, None, :], size, 1).astype(np.uint8)).convert('RGBA')


def plate(size, motes=True):
    inset = size * 100 / 1024
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    d = np.clip(np.hypot(xx - size * .5, yy - size * .4) / (size * .62), 0, 1)[..., None] ** 1.3
    im = Image.fromarray((np.array([38, 52, 98]) * (1 - d) + np.array([9, 13, 30]) * d).astype(np.uint8)).convert('RGBA')
    if motes:
        rnd = random.Random(7); layer = Image.new('RGBA', (size, size)); dr = ImageDraw.Draw(layer)
        for _ in range(26):
            x, y = rnd.uniform(inset + size * .04, size - inset - size * .04), rnd.uniform(inset + size * .04, size * .55)
            r = rnd.uniform(1.2, 3.2) * size / 1024
            dr.ellipse((x - r, y - r, x + r, y + r), fill=(246, 214, 150, rnd.randint(70, 170)))
        im.alpha_composite(layer.filter(ImageFilter.GaussianBlur(size / 1024)))
        glow = Image.new('RGBA', (size, size)); ImageDraw.Draw(glow).ellipse((size * .2, size * .28, size * .8, size * .82), fill=(232, 180, 100, 70))
        im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(size * .09)))
    return im, inset


def finish(im, size, inset):
    rim = gold(size); rim.putalpha(ImageChops.subtract(squircle(size, inset), squircle(size, inset + max(1.0, size * 6 / 1024))).point(lambda v: v * .85))
    im.alpha_composite(rim)
    mask = squircle(size, inset); out = Image.new('RGBA', (size, size))
    shadow = Image.new('RGBA', (size, size)); shadow.putalpha(mask.point(lambda v: v * .35))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(size * .012)), (0, round(size * .012)))
    im.putalpha(mask); out.alpha_composite(im)
    return out


def with_shadow(size, bot, width, bottom, x_shift, dark):
    b = bot.resize((width, round(bot.size[1] * width / bot.size[0])), Image.LANCZOS)
    bx = (size - b.size[0]) // 2 + x_shift; by = bottom - b.size[1]
    layer = Image.new('RGBA', (size, size)); bw, bh = b.size
    ImageDraw.Draw(layer).ellipse((bx + bw * .04, by + bh * .89, bx + bw * .98, by + bh * 1.04), fill=(0, 0, 0, dark))
    layer = layer.filter(ImageFilter.GaussianBlur(size * .016)); layer.alpha_composite(b, (bx, by))
    return layer


def mac(bot, size=1024):
    im, inset = plate(size)
    im.alpha_composite(with_shadow(size, bot, round(size * .64), round(size * .80), round(size * .01), 150))
    return finish(im, size, inset)


def windows(bot, size):
    return with_shadow(size, bot, round(size * .94), round(size * .965), 0, 90)


def glyph(px, scale=1.0):
    k = 16; U = px * k / 32 * scale; o = px * k * (1 - scale) / 2
    im = Image.new('RGBA', (px * k, px * k)); d = ImageDraw.Draw(im)
    R = lambda *v: [round(o + x * U) for x in v]
    tiny = px * scale <= 20
    if not tiny:
        d.line(R(22, 7, 22, 3), fill=STEM, width=round(1.1 * U))
        d.ellipse(R(20.4, 1.2, 23.6, 4.4), fill=ORANGE)
    d.rounded_rectangle(R(1.5, 18, 8.5, 30), radius=3 * U, fill=TYRE)
    d.rounded_rectangle(R(23.5, 18, 30.5, 30), radius=3 * U, fill=TYRE)
    d.rounded_rectangle(R(4, 4.5 if tiny else 5.5, 28, 26.5), radius=6 * U, fill=CREAM)
    d.rounded_rectangle(R(4, 20, 28, 26.5), radius=4 * U, fill=CREAM_D)
    d.rectangle(R(4, 10, 28, 18.5), fill=ORANGE)
    d.rounded_rectangle(R(5.5 if tiny else 6.5, 11, 26.5 if tiny else 25.5, 17.5), radius=2.6 * U, fill=VISOR)
    r = 2.7 if tiny else 2.3
    for cx in (11.4, 20.6):
        d.ellipse(R(cx - r, 14.25 - r, cx + r, 14.25 + r), fill=EYE)
        if not tiny:
            d.ellipse(R(cx - 1, 13.25, cx + 1, 15.25), fill=VISOR)
    return im.resize((px, px), Image.LANCZOS)


def mac_small(px):
    im, inset = plate(px, motes=False)
    im.alpha_composite(glyph(px, .78))
    return finish(im, px, inset)


def png(im):
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True); return b.getvalue()


def write_ico(path, images):
    head = struct.pack('<HHH', 0, 1, len(images)); offset = 6 + 16 * len(images); entries = b''; blobs = b''
    for im in images:
        data = png(im); w = im.size[0] % 256
        entries += struct.pack('<BBBBHHII', w, w, 0, 0, 1, 32, len(data), offset)
        blobs += data; offset += len(data)
    path.write_bytes(head + entries + blobs)


def write_icns(path, chunks):
    body = b''.join(kind.encode() + struct.pack('>I', len(data) + 8) + data for kind, data in chunks)
    path.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)


bot = cut()
big = mac(bot)
big.save(OUT / 'icon.png', optimize=True)
art = {px: big.resize((px, px), Image.LANCZOS) for px in (64, 128, 256, 512)}
small = {px: mac_small(px) for px in (16, 32)}
write_icns(OUT / 'icon.icns', [('icp4', png(small[16])), ('icp5', png(small[32])), ('ic11', png(small[32])),
                               ('icp6', png(art[64])), ('ic12', png(art[64])), ('ic07', png(art[128])),
                               ('ic08', png(art[256])), ('ic13', png(art[256])), ('ic09', png(art[512])),
                               ('ic14', png(art[512])), ('ic10', png(big))])
write_ico(OUT / 'icon.ico', [glyph(px) for px in (16, 20, 24, 32, 40)] + [windows(bot, px) for px in (48, 64, 128, 256)])
write_ico(OUT / 'window.ico', [glyph(24), glyph(48)])

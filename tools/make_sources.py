import math, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

if len(sys.argv) < 3:
    raise SystemExit('Usage: python tools/make_sources.py <output folder> <folders holding Poly Haven sources...>')
OUT = Path(sys.argv[1])
SOURCES = [Path(a) for a in sys.argv[2:]]
SIZE = 2048
SUN_DARK = (-12.0, 3.4, 15.0)
SUN_LIGHT = (-12.0, 25.0, 15.0)

# name: (Poly Haven source, colour ramp over the source's brightness as (at, sRGB), share of the source's own colour kept)
GRADED = {
    'made_salt_crust': ('mud_cracked_dry_03', [(0.0, (0.50, 0.55, 0.62)), (0.3, (0.78, 0.81, 0.85)), (0.6, (0.93, 0.93, 0.93)), (1.0, (0.99, 0.98, 0.96))], 0.08),
    'made_salt_flat': ('aerial_beach_01', [(0.0, (0.80, 0.82, 0.85)), (0.5, (0.91, 0.91, 0.91)), (1.0, (0.98, 0.97, 0.95))], 0.08),
    'made_lava': ('mud_cracked_dry_03', [(0.0, (1.0, 0.9, 0.55)), (0.14, (1.0, 0.56, 0.12)), (0.3, (0.75, 0.16, 0.03)), (0.46, (0.16, 0.05, 0.03)), (0.62, (0.07, 0.05, 0.045)), (1.0, (0.13, 0.11, 0.105))], 0.0),
    'made_ash': ('burned_ground_01', [(0.0, (0.05, 0.045, 0.045)), (0.5, (0.14, 0.13, 0.125)), (1.0, (0.3, 0.28, 0.26))], 0.15),
    'made_basalt': ('rock_boulder_cracked', [(0.0, (0.035, 0.034, 0.038)), (0.5, (0.12, 0.115, 0.11)), (1.0, (0.26, 0.24, 0.22))], 0.1),
    'made_red_cinder': ('red_mud_stones', [(0.0, (0.08, 0.035, 0.025)), (0.5, (0.27, 0.11, 0.06)), (1.0, (0.5, 0.25, 0.14))], 0.25),
}


def find(rel):
    for folder in SOURCES:
        if (folder / rel).is_file():
            return folder / rel
    raise SystemExit(f'Missing source: {rel}. Run tools/fetch_sources.py first.')


def save_jpg(pixels, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(pixels * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(path, quality=92)


def flat_maps(name, rough):
    save_jpg(np.full((256, 256, 3), (0.5, 0.5, 1.0)), OUT / name / f'{name}_nor_gl_2k.jpg')
    save_jpg(np.full((256, 256, 3), rough), OUT / name / f'{name}_rough_2k.jpg')


def graded(name, source, ramp, keep):
    src = np.asarray(Image.open(find(f'{source}/{source}_diff_2k.jpg')).convert('RGB'), dtype=np.float32) / 255.0
    lum = src @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    lo, hi = np.percentile(lum, [1, 99])
    t = np.clip((lum - lo) / max(hi - lo, 1e-4), 0, 1)
    at = np.array([s[0] for s in ramp])
    colour = np.stack([np.interp(t, at, [s[1][c] for s in ramp]) for c in range(3)], -1)
    mean = src.reshape(-1, 3).mean(0)
    own = src / np.maximum(mean, 1e-4) * colour.reshape(-1, 3).mean(0)
    save_jpg(colour * (1 - keep) + own * keep, OUT / name / f'{name}_diff_2k.jpg')
    for m in ('nor_gl', 'rough'):
        (OUT / name).mkdir(parents=True, exist_ok=True)
        (OUT / name / f'{name}_{m}_2k.jpg').write_bytes(find(f'{source}/{source}_{m}_2k.jpg').read_bytes())


def raked(name):
    grain = np.asarray(Image.open(find('gravel_floor/gravel_floor_diff_2k.jpg')).convert('L'), dtype=np.float32) / 255.0
    grain = (grain - grain.mean()) / grain.std()
    x = np.arange(SIZE, dtype=np.float32) / SIZE
    groove = np.cos(x * 2 * math.pi * 12)[:, None] * np.ones((1, SIZE), np.float32)
    shade = 0.56 + 0.08 * groove + 0.03 * grain
    save_jpg(np.stack([shade * 0.97, shade * 0.96, shade * 0.92], -1), OUT / name / f'{name}_diff_2k.jpg')
    slope = -np.sin(x * 2 * math.pi * 12)[:, None] * np.ones((1, SIZE), np.float32) * 0.5
    normal = np.stack([np.full_like(slope, 0.5), 0.5 + slope * 0.5, np.full_like(slope, 1.0)], -1)
    save_jpg(normal, OUT / name / f'{name}_nor_gl_2k.jpg')
    save_jpg(np.full((256, 256, 3), 0.9), OUT / name / f'{name}_rough_2k.jpg')


def periodic_noise(rng, size, falloff):
    f = np.fft.fftfreq(size)
    k = np.sqrt(f[:, None] ** 2 + f[None, :] ** 2)
    k[0, 0] = 1.0
    spectrum = np.fft.fft2(rng.standard_normal((size, size))) / k ** falloff
    spectrum[0, 0] = 0
    n = np.real(np.fft.ifft2(spectrum))
    return (n - n.mean()) / n.std()


def stars(name):
    rng = np.random.default_rng(20261109)
    img = np.zeros((SIZE, SIZE, 3), np.float32)
    img[:] = (0.008, 0.01, 0.022)
    cloud = periodic_noise(rng, SIZE, 1.6)
    wisp = periodic_noise(rng, SIZE, 1.2)
    teal = np.clip(cloud - 0.6, 0, None) ** 1.5
    violet = np.clip(-cloud - 0.9, 0, None) ** 1.5 * np.clip(wisp + 0.6, 0, None)
    img += teal[..., None] * np.array([0.02, 0.09, 0.11]) + violet[..., None] * np.array([0.09, 0.03, 0.12])
    count = 2600
    ys, xs = rng.uniform(0, SIZE, count), rng.uniform(0, SIZE, count)
    bright = np.minimum(rng.pareto(2.2, count) * 0.25 + 0.12, 1.6)
    warmth = rng.uniform(-1, 1, count)
    tints = np.stack([1.0 + 0.18 * warmth, np.full(count, 1.0), 1.0 - 0.22 * warmth], -1)
    r = 7
    grid = np.arange(-r, r + 1)
    for y, x, b, tint in zip(ys, xs, bright, tints):
        iy, ix = int(y), int(x)
        dy, dx = grid[:, None] + iy - y, grid[None, :] + ix - x
        sigma = 0.9 + 1.6 * min(b, 1.0)
        spot = np.exp(-(dx * dx + dy * dy) / (2 * sigma * sigma)) * b
        rows, cols = (grid + iy) % SIZE, (grid + ix) % SIZE
        img[np.ix_(rows, cols)] += spot[..., None] * tint
    save_jpg(np.clip(img, 0, 1), OUT / name / f'{name}_diff_2k.jpg')
    flat_maps(name, 0.92)


def speckled(rng, colour, amount, falloff=0.4):
    return np.array(colour, np.float32) + periodic_noise(rng, SIZE, falloff)[..., None] * amount


def rough_map(name, rough):
    save_jpg(np.full((256, 256, 3), (0.5, rough, 0.5)), OUT / name / f'{name}_rough_2k.jpg')
    save_jpg(np.full((256, 256, 3), (0.5, 0.5, 1.0)), OUT / name / f'{name}_nor_gl_2k.jpg')


def clay_grounds():
    rng = np.random.default_rng(20261110)
    planks = speckled(rng, (0.78, 0.6, 0.42), 0.012)
    width = SIZE // 16
    for row in range(16):
        rows = slice(row * width, (row + 1) * width)
        cuts = np.sort(rng.choice(np.arange(64, SIZE - 64), 3, replace=False))
        for a, b in zip(np.r_[0, cuts], np.r_[cuts, SIZE]):
            planks[rows, a:b] *= 1.0 + rng.uniform(-0.045, 0.045)
            planks[rows, max(a - 1, 0):a + 1] *= 0.86
        planks[row * width:row * width + 2] *= 0.86
    save_jpg(planks.transpose(1, 0, 2), OUT / 'made_clay_planks' / 'made_clay_planks_diff_2k.jpg')
    rough_map('made_clay_planks', 0.8)
    save_jpg(speckled(rng, (0.86, 0.81, 0.73), 0.014, 0.2), OUT / 'made_clay_carpet' / 'made_clay_carpet_diff_2k.jpg')
    rough_map('made_clay_carpet', 0.97)
    save_jpg(speckled(rng, (0.63, 0.7, 0.6), 0.014, 0.2), OUT / 'made_clay_sage' / 'made_clay_sage_diff_2k.jpg')
    rough_map('made_clay_sage', 0.97)
    tiles = speckled(rng, (0.94, 0.92, 0.87), 0.006)
    side = SIZE // 8
    for k in range(8):
        tiles[k * side:k * side + 3] = (0.79, 0.76, 0.71)
        tiles[:, k * side:k * side + 3] = (0.79, 0.76, 0.71)
    save_jpg(tiles, OUT / 'made_clay_tiles' / 'made_clay_tiles_diff_2k.jpg')
    rough_map('made_clay_tiles', 0.45)
    wide = Image.fromarray(np.clip(speckled(rng, (0.9, 0.86, 0.79), 0.008) * 255.0 + 0.5, 0, 255).astype(np.uint8))
    draw = ImageDraw.Draw(wide)
    chips = [(184, 173, 158), (204, 168, 128), (247, 245, 237), (214, 158, 133), (115, 102, 92), (160, 176, 152)]
    for _ in range(5200):
        x, y = rng.uniform(0, SIZE, 2)
        w, h = rng.uniform(3, 13, 2)
        colour = chips[int(rng.choice(len(chips), p=[0.3, 0.24, 0.24, 0.1, 0.06, 0.06]))]
        for dx in (-SIZE, 0, SIZE):
            for dy in (-SIZE, 0, SIZE):
                draw.ellipse((x + dx - w, y + dy - h, x + dx + w, y + dy + h), fill=colour)
    (OUT / 'made_terrazzo').mkdir(parents=True, exist_ok=True)
    wide.save(OUT / 'made_terrazzo' / 'made_terrazzo_diff_2k.jpg', quality=92)
    rough_map('made_terrazzo', 0.5)


def write_hdr(pixels, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    h, w, _ = pixels.shape
    peak = pixels.max(-1)
    exp = np.where(peak > 1e-32, np.floor(np.log2(np.maximum(peak, 1e-32))) + 1, -128)
    scale = np.where(peak > 1e-32, 256.0 / np.exp2(exp), 0)
    rgbe = np.zeros((h, w, 4), np.uint8)
    rgbe[..., :3] = np.clip(pixels * scale[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(peak > 1e-32, exp + 128, 0).astype(np.uint8)
    with open(path, 'wb') as f:
        f.write(b'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n' + f'-Y {h} +X {w}\n'.encode())
        f.write(rgbe.tobytes())


def directions(w, h):
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    theta = v[:, None] * math.pi
    phi = (0.5 - u[None, :]) * 2 * math.pi
    return np.stack([np.sin(theta) * np.cos(phi), np.cos(theta) * np.ones_like(phi), -np.sin(theta) * np.sin(phi)], -1)


def unit(v):
    v = np.array(v, np.float64)
    return v / np.linalg.norm(v)


def gradient_sky(name, sun_at, zenith, horizon, ground, halo):
    d = directions(1024, 512)
    up = d[..., 1]
    cos_sun = np.clip(d @ unit(sun_at), -1, 1)
    above = np.clip(up, 0, 1)
    zenith, horizon, ground = np.array(zenith), np.array(horizon), np.array(ground)
    glow = sum((power * np.exp((cos_sun - 1) / width))[..., None] * np.array(colour) for power, width, colour in halo)
    if name == 'made_mars_dusk':
        glow = glow + (np.exp(-above / 0.08) * np.clip(cos_sun * 0.5 + 0.5, 0, 1) ** 2)[..., None] * np.array([0.3, 0.16, 0.1])
    sky = zenith + (horizon - zenith) * (1 - above[..., None]) ** 3
    sky = np.where(up[..., None] >= 0, sky, ground + (horizon - ground) * np.exp(up[..., None] / 0.05))
    sky = sky + glow * (up[..., None] > -0.05)
    write_hdr(sky.astype(np.float32), OUT / name / f'{name}_1k.hdr')


def pixel_map(name, pixels, rough):
    big = np.repeat(np.repeat(pixels, SIZE // pixels.shape[0], 0), SIZE // pixels.shape[1], 1)
    save_jpg(big, OUT / name / f'{name}_diff_2k.jpg')
    rough_map(name, rough)


def scattered(rng, field, shades, noise=0.5):
    """Picks a shade for each pixel from a smooth field, with ragged borders."""
    t = (field - field.min()) / (field.max() - field.min()) + rng.uniform(-noise, noise, field.shape) / len(shades)
    return np.array(shades, np.float32)[np.clip((t * len(shades)).astype(int), 0, len(shades) - 1)]


def flagstones(rng, side, wide, tall, shades, mortar, moss):
    out = np.zeros((side, side, 3), np.float32)
    for row in range(side // tall):
        shift = (wide // 2) * (row % 2)
        for col in range(side // wide):
            shade = np.array(shades[rng.integers(len(shades))]) * rng.uniform(0.94, 1.06)
            for y in range(tall):
                for x in range(wide):
                    edge = x == 0 or y == 0
                    pixel = mortar if edge else shade
                    if rng.random() < (0.3 if edge else 0.04):
                        pixel = moss[rng.integers(len(moss))]
                    out[row * tall + y, (col * wide + x + shift) % side] = pixel
    return out


def glade_grounds():
    rng = np.random.default_rng(20261111)
    side = 64
    grass = scattered(rng, periodic_noise(rng, side, 1.6), [(0.12, 0.29, 0.2), (0.16, 0.36, 0.23), (0.21, 0.43, 0.26), (0.28, 0.5, 0.28)])
    grass[rng.random((side, side)) < 0.02] = (0.42, 0.62, 0.32)
    grass[rng.random((side, side)) < 0.004] = (0.93, 0.85, 0.45)
    pixel_map('made_glade_grass', grass, 0.95)
    floor = scattered(rng, periodic_noise(rng, side, 1.6), [(0.09, 0.19, 0.17), (0.12, 0.24, 0.19), (0.16, 0.27, 0.18)])
    floor[rng.random((side, side)) < 0.05] = (0.3, 0.22, 0.15)
    floor[rng.random((side, side)) < 0.02] = (0.42, 0.3, 0.17)
    pixel_map('made_glade_floor', floor, 0.95)
    dirt = scattered(rng, periodic_noise(rng, side, 1.4), [(0.23, 0.17, 0.14), (0.3, 0.22, 0.17), (0.37, 0.28, 0.2)])
    dirt[rng.random((side, side)) < 0.025] = (0.5, 0.48, 0.44)
    pixel_map('made_glade_dirt', dirt, 0.95)
    stones = [(0.36, 0.39, 0.4), (0.44, 0.47, 0.47), (0.52, 0.55, 0.53)]
    mosses = [(0.22, 0.36, 0.21), (0.33, 0.47, 0.24)]
    pixel_map('made_glade_stone', flagstones(rng, side, 8, 4, stones, (0.17, 0.2, 0.21), mosses), 0.9)
    pixel_map('made_glade_paving', flagstones(rng, 32, 8, 4, stones, (0.17, 0.2, 0.21), mosses), 0.3)


def retro_grounds():
    rng = np.random.default_rng(20261112)
    side = 64
    y, x = np.indices((side, side))
    checker = np.where((((x // 4) + (y // 4)) % 2 == 0)[..., None], (0.93, 0.86, 0.68), (0.8, 0.67, 0.47)).astype(np.float32)
    pixel_map('made_retro_checker', checker, 0.6)
    pixel_map('made_retro_carpet', scattered(rng, rng.uniform(0, 1, (side, side)), [(0.3, 0.38, 0.55), (0.34, 0.43, 0.6), (0.39, 0.48, 0.65)], 0.0), 0.97)
    planks = np.zeros((side, side, 3), np.float32)
    for row in range(side // 2):
        shift = int(rng.integers(0, 16))
        for col in range(side):
            board = (col + shift) // 16
            shade = [(0.6, 0.39, 0.23), (0.66, 0.44, 0.26), (0.55, 0.35, 0.2)][(board + row) % 3]
            planks[row * 2:row * 2 + 2, col] = (0.4, 0.25, 0.15) if (col + shift) % 16 == 0 else shade
        planks[row * 2 + 1] *= 0.93
    pixel_map('made_retro_planks', planks, 0.8)
    slate = np.where((((x // 4) + (y // 4)) % 2 == 0)[..., None], (0.26, 0.28, 0.36), (0.2, 0.22, 0.3)).astype(np.float32)
    pixel_map('made_retro_slate', slate, 0.5)
    paving = np.full((32, 32, 3), (0.62, 0.66, 0.74), np.float32)
    paving[::8] = paving[:, ::8] = (0.42, 0.46, 0.56)
    paving[1::8] = paving[:, 1::8] = (0.74, 0.78, 0.85)
    paving[::8] = (0.42, 0.46, 0.56)
    paving[:, ::8] = (0.42, 0.46, 0.56)
    pixel_map('made_retro_paving', paving, 0.3)


def toy_grounds():
    rng = np.random.default_rng(20261113)
    grid = np.full((SIZE, SIZE, 3), (0.105, 0.12, 0.19), np.float32)
    metre = SIZE // 8
    for k in range(8):
        grid[k * metre:k * metre + 6] = grid[:, k * metre:k * metre + 6] = (0.2, 0.24, 0.36)
    grid[:6] = (0.2, 0.24, 0.36)
    grid[:, :6] = (0.2, 0.24, 0.36)
    save_jpg(grid, OUT / 'made_toy_grid' / 'made_toy_grid_diff_2k.jpg')
    rough_map('made_toy_grid', 0.7)
    for name, colour, rough in (('made_toy_white', (0.93, 0.93, 0.95), 0.6), ('made_toy_grey', (0.62, 0.65, 0.72), 0.6), ('made_toy_wood', (0.88, 0.74, 0.54), 0.6)):
        save_jpg(speckled(rng, colour, 0.004), OUT / name / f'{name}_diff_2k.jpg')
        rough_map(name, rough)
    slabs = speckled(rng, (0.93, 0.93, 0.96), 0.004)
    half = SIZE // 2
    for k in range(2):
        slabs[k * half:k * half + 8] = slabs[:, k * half:k * half + 8] = (0.78, 0.79, 0.86)
    slabs[:8] = (0.78, 0.79, 0.86)
    slabs[:, :8] = (0.78, 0.79, 0.86)
    save_jpg(slabs, OUT / 'made_toy_paving' / 'made_toy_paving_diff_2k.jpg')
    rough_map('made_toy_paving', 0.3)


def studio_sky(name, top, fill):
    """Soft light from overhead, and dark where the Yard's camera sees the sky mirrored in water."""
    d = directions(1024, 512)
    up = d[..., 1]
    overhead = np.clip((up - 0.6) / 0.34, 0, 1)
    overhead = overhead * overhead * (3 - 2 * overhead)
    sky = np.array(fill) + (np.array(top) - np.array(fill)) * overhead[..., None]
    sky = np.where(up[..., None] >= 0, sky, np.array(fill) * 0.5)
    mirrored = unit((-0.43611949136464423, 0.5508877785658665, -0.7115633806475775))
    sky = sky * (1 - np.exp((np.clip(d @ mirrored, -1, 1) - 1) / 0.12))[..., None]
    write_hdr(sky.astype(np.float32), OUT / name / f'{name}_1k.hdr')


def main():
    for name, (source, ramp, keep) in GRADED.items():
        graded(name, source, ramp, keep)
        print('made', name, flush=True)
    stars('made_stars')
    raked('made_raked_gravel')
    clay_grounds()
    glade_grounds()
    retro_grounds()
    toy_grounds()
    print('made made_stars', flush=True)
    gradient_sky('made_mars_day', SUN_LIGHT, [0.42, 0.27, 0.17], [0.98, 0.7, 0.46], [0.3, 0.18, 0.11],
                 [(0.9, 0.06, [1.0, 0.86, 0.7]), (0.25, 0.5, [1.0, 0.86, 0.7])])
    gradient_sky('made_mars_dusk', SUN_DARK, [0.06, 0.055, 0.06], [0.34, 0.2, 0.13], [0.07, 0.045, 0.035],
                 [(1.6, 0.035, [0.35, 0.62, 1.0]), (0.5, 0.2, [0.35, 0.62, 1.0])])
    gradient_sky('made_haze_day', SUN_LIGHT, [0.5, 0.42, 0.36], [0.92, 0.66, 0.44], [0.24, 0.17, 0.13],
                 [(0.6, 0.08, [1.0, 0.8, 0.6]), (0.3, 0.6, [1.0, 0.7, 0.5])])
    studio_sky('made_studio_day', [2.6, 2.5, 2.3], [0.62, 0.58, 0.52])
    studio_sky('made_studio_night', [0.42, 0.36, 0.3], [0.1, 0.09, 0.09])
    print('made skies')


main()

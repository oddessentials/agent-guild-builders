import math, sys
from pathlib import Path
import numpy as np
from PIL import Image

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


def main():
    for name, (source, ramp, keep) in GRADED.items():
        graded(name, source, ramp, keep)
        print('made', name, flush=True)
    stars('made_stars')
    raked('made_raked_gravel')
    print('made made_stars', flush=True)
    gradient_sky('made_mars_day', SUN_LIGHT, [0.42, 0.27, 0.17], [0.98, 0.7, 0.46], [0.3, 0.18, 0.11],
                 [(0.9, 0.06, [1.0, 0.86, 0.7]), (0.25, 0.5, [1.0, 0.86, 0.7])])
    gradient_sky('made_mars_dusk', SUN_DARK, [0.06, 0.055, 0.06], [0.34, 0.2, 0.13], [0.07, 0.045, 0.035],
                 [(1.6, 0.035, [0.35, 0.62, 1.0]), (0.5, 0.2, [0.35, 0.62, 1.0])])
    gradient_sky('made_haze_day', SUN_LIGHT, [0.5, 0.42, 0.36], [0.92, 0.66, 0.44], [0.24, 0.17, 0.13],
                 [(0.6, 0.08, [1.0, 0.8, 0.6]), (0.3, 0.6, [1.0, 0.7, 0.5])])
    print('made skies')


main()

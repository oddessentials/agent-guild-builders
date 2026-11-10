import math, sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import voxels
from voxels import Voxels

ONLY = set(sys.argv[sys.argv.index('--') + 2:])
# name: (sRGB, glow)
PALETTE = {
    'leaf1': ((0.11, 0.27, 0.23), 0), 'leaf2': ((0.16, 0.37, 0.26), 0), 'leaf3': ((0.25, 0.5, 0.29), 0), 'leaf4': ((0.43, 0.64, 0.32), 0),
    'pine1': ((0.07, 0.21, 0.21), 0), 'pine2': ((0.11, 0.3, 0.26), 0), 'pine3': ((0.18, 0.41, 0.32), 0),
    'bark1': ((0.2, 0.14, 0.12), 0), 'bark2': ((0.3, 0.2, 0.15), 0), 'bark3': ((0.41, 0.28, 0.19), 0),
    'stone1': ((0.25, 0.28, 0.3), 0), 'stone2': ((0.36, 0.39, 0.4), 0), 'stone3': ((0.49, 0.52, 0.51), 0), 'stone4': ((0.63, 0.66, 0.62), 0),
    'moss1': ((0.22, 0.36, 0.21), 0), 'moss2': ((0.35, 0.49, 0.24), 0),
    'dirt1': ((0.25, 0.18, 0.14), 0), 'dirt2': ((0.36, 0.27, 0.19), 0),
    'wood1': ((0.38, 0.24, 0.15), 0), 'wood2': ((0.52, 0.35, 0.2), 0), 'wood3': ((0.66, 0.47, 0.28), 0),
    'fire1': ((1.0, 0.4, 0.08), 0.6), 'fire2': ((1.0, 0.7, 0.2), 0.9), 'ember': ((0.8, 0.2, 0.06), 0.5),
    'crystal1': ((0.1, 0.5, 0.56), 0.3), 'crystal2': ((0.2, 0.85, 0.8), 0.6), 'crystal3': ((0.42, 0.95, 0.9), 0.6),
    'magic1': ((0.34, 0.2, 0.6), 0.4), 'magic2': ((0.6, 0.4, 0.95), 0.9),
    'iron1': ((0.17, 0.18, 0.21), 0), 'iron2': ((0.33, 0.35, 0.39), 0), 'gold': ((0.86, 0.66, 0.25), 0),
    'red1': ((0.5, 0.12, 0.14), 0), 'red2': ((0.72, 0.21, 0.18), 0), 'blue1': ((0.16, 0.24, 0.47), 0), 'blue2': ((0.26, 0.4, 0.66), 0),
    'cream': ((0.87, 0.8, 0.64), 0), 'white': ((0.93, 0.92, 0.86), 0), 'black': ((0.07, 0.07, 0.09), 0),
    'yellow': ((0.95, 0.8, 0.3), 0), 'pink': ((0.9, 0.5, 0.65), 0), 'shroom': ((0.5, 0.92, 1.0), 0.7),
    'water': ((0.16, 0.5, 0.56), 0.3),
}
NAMES = list(PALETTE)
voxels.use('glade_', PALETTE, Path(sys.argv[sys.argv.index('--') + 1]).resolve())
NAMES = voxels.NAMES


MODELS = {}


def model(build):
    MODELS['glade_' + build.__name__] = build
    return build


BARK = (['bark1', 'bark2', 'bark3'], [3, 5, 1])
STONE = (['stone1', 'stone2', 'stone3', 'stone4'], [2, 5, 4, 1])
DARK_STONE = (['stone1', 'stone2'], [3, 2])
MOSS = (['moss1', 'moss2'], [3, 2])
WOOD = (['wood1', 'wood2', 'wood3'], [2, 5, 2])
IRON = (['iron1', 'iron2'], [2, 1])
FIRE = (['fire1', 'fire2'], [1, 1])
LEAVES = ('leaf1', 'leaf2', 'leaf3', 'leaf4')
NEEDLES = ('pine1', 'pine2', 'pine2', 'pine3')


def new(name, wide, deep, tall, seed):
    return Voxels('glade_' + name, wide, deep, tall, seed)


def shaded(v, where, shades, low, high, ragged=0.3):
    """Darker below and lighter above, in ragged bands with stray specks."""
    t = np.clip((v.z - low) / max(high - low, 1), 0, 0.999) + v.rough(3) * ragged + v.rng.uniform(-0.12, 0.12, v.grid.shape)
    band = np.clip((t * len(shades)).astype(int), 0, len(shades) - 1)
    for k, shade in enumerate(shades):
        v.paint(where & (band == k), shade)


def mossy(v, where, amount=0.3):
    v.paint(v.top_of(where) & (v.rough(4) > 1 - amount * 2), *MOSS)


def bricks(v, where, course=3, length=7):
    v.paint(where, *STONE)
    row = (v.z // course).astype(int)
    joint = (v.z.astype(int) % course == 0) | (((v.x + v.y).astype(int) + row * (length // 2)) % length == 0)
    v.paint(where & joint, 'stone1')


def worn(v, where, amount=0.12):
    """Knocks cubes off the outside of a shape."""
    solid = np.pad(v.grid > 0, 1)
    inside = solid[2:, 1:-1, 1:-1] & solid[:-2, 1:-1, 1:-1] & solid[1:-1, 2:, 1:-1] & solid[1:-1, :-2, 1:-1] & solid[1:-1, 1:-1, 2:]
    v.clear(where & ~inside & (v.rng.random(v.grid.shape) < amount) & (v.z > 1))


def trunk(v, at, radius, height, lean=(0, 0), flare=1.3):
    t = np.clip(v.z / height, 0, 1)
    r = radius * (1 + flare * np.clip(1 - v.z / (radius * 1.8), 0, 1) ** 2) * (1 - 0.35 * t)
    where = ((v.x - at[0] - lean[0] * t) ** 2 + (v.y - at[1] - lean[1] * t) ** 2 <= r * r) & (v.z < height)
    v.paint(where, *BARK)
    return where


def canopy(v, blobs, shades=LEAVES):
    where = np.zeros(v.grid.shape, bool)
    edge = v.rough(3) * 0.2
    low, high = 1e9, -1e9
    for at, radii in blobs:
        r = radii if isinstance(radii, tuple) else (radii, radii, radii * 0.8)
        where |= ((v.x - at[0]) / r[0]) ** 2 + ((v.y - at[1]) / r[1]) ** 2 + ((v.z - at[2]) / r[2]) ** 2 <= 1.0 + edge
        low, high = min(low, at[2] - r[2]), max(high, at[2] + r[2])
    shaded(v, where, shades, low, high)
    return where


def flame(v, at, height, width):
    for z in range(height):
        w = width * (1 - z / height) + 0.5
        cell = (abs(v.x - at[0]) <= w) & (abs(v.y - at[1]) <= w) & (v.z >= at[2] + z) & (v.z < at[2] + z + 1)
        v.paint(cell, 'fire1' if z > height * 0.55 else ['fire1', 'fire2'])
        v.paint(cell & (abs(v.x - at[0]) <= w - 1) & (abs(v.y - at[1]) <= w - 1), 'fire2')


def shard(v, at, height, width, lean=(0, 0)):
    for z in range(height):
        t = z / height
        w = width * (1 - max(0.0, t - 0.6) / 0.4) + 0.4
        cx, cy = at[0] + lean[0] * t, at[1] + lean[1] * t
        cell = (abs(v.x - cx) + abs(v.y - cy) <= w) & (v.z >= at[2] + z) & (v.z < at[2] + z + 1)
        v.paint(cell, 'crystal2')
        v.paint(cell & (abs(v.x - cx) + abs(v.y - cy) <= w - 1.2), 'crystal3')
        v.paint(cell & (v.x - cx > 0.3) & (v.y - cy > 0.3), 'crystal1')


@model
def tree_oak():
    v = new('tree_oak', 60, 60, 76, 11)
    trunk(v, (0, 0), 3.4, 42, (1.5, -1))
    v.paint(v.line((1, 0, 30), (-12, 4, 44), 1.6), *BARK)
    v.paint(v.line((1, 0, 32), (12, -5, 46), 1.6), *BARK)
    canopy(v, [((0, 0, 54), (22, 22, 17)), ((-14, 5, 47), 12), ((14, -6, 49), 13), ((3, 12, 50), 12), ((-4, -13, 51), 12), ((2, 0, 64), (14, 14, 10))])
    return v


@model
def tree_pine():
    v = new('tree_pine', 44, 44, 112, 12)
    trunk(v, (0, 0), 2.6, 100)
    where = np.zeros(v.grid.shape, bool)
    for k in range(7):
        base = 26 + k * 12
        reach = 19 - k * 2.3
        where |= (v.z >= base) & (v.z < base + 15) & (np.hypot(v.x, v.y) < reach * (1 - (v.z - base) / 16) + 1.5 + v.rough(3) * 2.2)
    shaded(v, where, NEEDLES, 26, 112, 0.2)
    return v


@model
def tree_ancient():
    v = new('tree_ancient', 96, 96, 118, 21)
    trunk(v, (0, 0), 7.5, 66, (2, 1), 0.9)
    for k in range(7):
        a = math.tau * k / 7 + 0.3
        v.paint(v.line((math.cos(a) * 5, math.sin(a) * 5, 9), (math.cos(a) * 20, math.sin(a) * 20, 0), 2.6), *BARK)
    for a, b in (((2, 1, 50), (-24, 8, 68)), ((2, 1, 54), (25, -6, 72)), ((2, 1, 56), (4, 24, 74)), ((2, 1, 52), (-6, -24, 70))):
        v.paint(v.line(a, b, 2.4), *BARK)
    hollow = v.ball((0, -7.5, 13), (3.4, 4, 5))
    v.clear(hollow)
    v.paint(v.ball((0, -4.6, 13), (3.4, 1.6, 5)) & (v.grid == 0), 'black')
    v.paint(v.ball((0, -5.4, 10), (2, 1, 1.6)), 'shroom')
    leaves = canopy(v, [((2, 1, 84), (40, 40, 26)), ((-26, 8, 74), 18), ((27, -6, 77), 19), ((4, 26, 78), 18), ((-6, -26, 76), 18), ((0, 0, 102), (24, 24, 14))])
    under = np.zeros_like(leaves)
    under[:, :, 1:] = leaves[:, :, 1:] & ~leaves[:, :, :-1]
    for x, y, z in np.argwhere(under & (v.rng.random(v.grid.shape) < 0.045)):
        v.grid[x, y, max(z - int(v.rng.integers(2, 9)), 0):z] = NAMES.index('moss1') + 1
    mossy(v, (v.z < 24) & (v.grid > 0), 0.4)
    return v


@model
def tree_dead():
    v = new('tree_dead', 44, 44, 46, 22)
    trunk(v, (0, 0), 2.6, 30, (2, 1))
    for a, b, r in (((1, 0, 18), (-14, 4, 30), 1.3), ((-14, 4, 30), (-17, 2, 40), 0.9), ((2, 1, 24), (13, -6, 36), 1.3), ((13, -6, 36), (17, -3, 44), 0.9), ((2, 1, 28), (4, 12, 42), 1.1), ((2, 1, 29), (-2, -10, 40), 1.0)):
        v.paint(v.line(a, b, r), *BARK)
    return v


@model
def bush():
    v = new('bush', 22, 22, 13, 13)
    where = canopy(v, [((0, 0, 4), (9, 9, 8)), ((-4, 3, 5), 6), ((5, -2, 6), 6)], ('leaf2', 'leaf3', 'leaf3', 'leaf4'))
    v.paint(v.top_of(where) & (v.rng.random(v.grid.shape) < 0.035), ['pink', 'white'])
    return v


def tufts(v, heads=None):
    wide, deep = v.size[0], v.size[1]
    blades = (v.rng.random((wide, deep)) < 0.3)[:, :, None] & (v.z < 1 + v.rng.integers(1, 5, (wide, deep))[:, :, None]) & (v.x ** 2 + v.y ** 2 < 44)
    shaded(v, blades, ('leaf2', 'leaf3', 'leaf4'), 0, 6, 0.1)
    if heads:
        v.paint(v.top_of(blades) & (v.rng.random(v.grid.shape) < 0.45), heads)
    return v


@model
def grass():
    return tufts(new('grass', 14, 14, 6, 14))


@model
def flowers():
    return tufts(new('flowers', 14, 14, 6, 24), ['yellow', 'pink', 'white'])


def toadstool(v, at, stem, cap, colour, spots):
    v.paint(v.rod(at, 1.0, 0, stem), 'cream')
    hat = v.ball((at[0], at[1], stem), (cap, cap, cap * 0.75)) & (v.z >= stem)
    v.paint(hat, colour)
    if spots:
        v.paint(v.top_of(hat) & (v.rng.random(v.grid.shape) < 0.22), spots)


@model
def mushrooms():
    v = new('mushrooms', 18, 18, 9, 25)
    toadstool(v, (-3, 1), 4, 4.2, ['red1', 'red2'], 'white')
    toadstool(v, (4, -2), 3, 3.2, ['red1', 'red2'], 'white')
    toadstool(v, (2, 4), 2, 2.4, ['red1', 'red2'], 'white')
    return v


@model
def glow_mushrooms():
    v = new('glow_mushrooms', 18, 18, 8, 26)
    toadstool(v, (-3, 2), 4, 3.6, 'shroom', None)
    toadstool(v, (3, -3), 3, 3.0, 'shroom', None)
    toadstool(v, (4, 4), 2, 2.2, 'shroom', None)
    toadstool(v, (-4, -4), 2, 2.0, 'shroom', None)
    return v


def lump(v, radii, lift=1.0):
    where = ((v.x / radii[0]) ** 2 + (v.y / radii[1]) ** 2 + ((v.z - lift) / radii[2]) ** 2 <= 1.0 + v.rough(4) * 0.3)
    shaded(v, where, ('stone1', 'stone2', 'stone3', 'stone4'), -2, radii[2] + lift, 0.2)
    mossy(v, where, 0.3)
    return v


@model
def rock():
    return lump(new('rock', 22, 18, 12, 15), (9.5, 7.5, 9.5))


@model
def boulder():
    return lump(new('boulder', 34, 30, 20, 27), (15, 13, 17), 1.5)


@model
def log():
    v = new('log', 38, 12, 9, 28)
    body = (v.y ** 2 + (v.z - 4) ** 2 <= 16) & (np.abs(v.x) < 17)
    v.paint(body, *BARK)
    ends = body & (np.abs(v.x) > 16)
    v.paint(ends, 'wood3')
    v.paint(ends & (v.y ** 2 + (v.z - 4) ** 2 <= 5), 'wood2')
    v.paint(v.line((6, 0, 6), (9, 4, 9), 0.9), *BARK)
    mossy(v, body, 0.45)
    toadstool(v, (-8, -4.5), 2, 2.0, ['red1', 'red2'], 'white')
    return v


@model
def stump():
    v = new('stump', 22, 22, 7, 29)
    body = trunk(v, (0, 0), 4.2, 6, flare=0.45)
    top = v.top_of(body) & (v.z > 5)
    v.paint(top, 'wood3')
    v.paint(top & ((np.hypot(v.x, v.y).astype(int) % 2) == 0), 'wood2')
    mossy(v, body & (v.z < 5), 0.3)
    return v


@model
def dais():
    v = new('dais', 56, 56, 9, 18)
    for half, top in ((28, 3), (25, 6), (22, 9)):
        block = v.box((-half, -half, top - 3), (half, half, top))
        v.paint(block, *STONE)
        v.paint(block & ((v.x.astype(int) % 8 == 0) | (v.y.astype(int) % 8 == 0)) & (v.z > top - 1), 'stone1')
    rune = (np.abs(np.hypot(v.x, v.y) - 12) < 1.2) | ((np.abs(v.x) < 1) & (np.abs(v.y) < 12)) | ((np.abs(v.y) < 1) & (np.abs(v.x) < 12))
    v.paint(rune & (v.z > 8) & (v.grid > 0), ['crystal1', 'crystal2'])
    worn(v, v.grid > 0, 0.1)
    mossy(v, v.grid > 0, 0.22)
    return v


def column(v, at, height, ruined=False):
    v.paint(v.box((at[0] - 4, at[1] - 4, 0), (at[0] + 4, at[1] + 4, 3)), *STONE)
    shaft = v.rod(at, 2.8, 3, height - 3)
    bricks(v, shaft, 6, 99)
    if ruined:
        v.clear(shaft & (v.z > height - 9 + (v.x - at[0]) * 0.9 + v.rough(3) * 2))
    else:
        v.paint(v.box((at[0] - 4, at[1] - 4, height - 3), (at[0] + 4, at[1] + 4, height)), *STONE)


@model
def pillar():
    v = new('pillar', 10, 10, 30, 31)
    column(v, (0, 0), 30)
    worn(v, v.grid > 0, 0.06)
    mossy(v, v.grid > 0, 0.3)
    return v


@model
def pillar_broken():
    v = new('pillar_broken', 26, 22, 17, 32)
    column(v, (-3, 0), 20, True)
    for at, size in (((7, -5), 3), ((9, 3), 2), ((4, 7), 2), ((11, -1), 2)):
        v.paint(v.box((at[0] - size, at[1] - size, 0), (at[0] + size, at[1] + size, size + 1)), *STONE)
    worn(v, v.grid > 0, 0.1)
    mossy(v, v.grid > 0, 0.4)
    return v


@model
def shrine():
    v = new('shrine', 56, 56, 52, 33)
    for half, top in ((28, 3), (25, 6), (22, 9)):
        block = v.box((-half, -half, top - 3), (half, half, top))
        v.paint(block, *STONE)
        v.paint(block & ((v.x.astype(int) % 8 == 0) | (v.y.astype(int) % 8 == 0)) & (v.z > top - 1), 'stone1')
    rune = (np.abs(np.hypot(v.x, v.y) - 12) < 1.2) | (np.abs(np.hypot(v.x, v.y) - 6) < 1.0)
    v.paint(rune & (v.z > 8) & (v.z < 9) & (v.grid > 0), ['crystal1', 'crystal2'])
    for k, (x, y) in enumerate(((-17, -17), (17, -17), (-17, 17), (17, 17))):
        v.paint(v.box((x - 4, y - 4, 9), (x + 4, y + 4, 12)), *STONE)
        shaft = v.rod((x, y), 2.8, 12, 36)
        bricks(v, shaft, 6, 99)
        if k == 1:
            v.clear(shaft & (v.z > 24 + v.rough(3) * 2))
        else:
            v.paint(v.box((x - 4, y - 4, 36), (x + 4, y + 4, 39)), *STONE)
    v.paint(v.box((-21, 13, 39), (21, 21, 43)), *STONE)
    v.paint(v.box((-21, -21, 39), (-13, 21, 43)), *STONE)
    for z in range(26):
        t = abs(z - 13) / 13
        w = 5.5 * (1 - t) + 0.6
        cell = (abs(v.x) + abs(v.y) <= w) & (v.z >= 14 + z) & (v.z < 15 + z)
        v.paint(cell, 'crystal2')
        v.paint(cell & (abs(v.x) + abs(v.y) <= w - 1.5), 'crystal3')
        v.paint(cell & (v.x > 0.3) & (v.y > 0.3), 'crystal1')
    worn(v, (v.grid > 0) & (v.grid < NAMES.index('crystal1') + 1), 0.07)
    mossy(v, (v.grid > 0) & (v.grid < NAMES.index('crystal1') + 1), 0.25)
    return v


@model
def portal():
    v = new('portal', 40, 10, 46, 34)
    for side in (-1, 1):
        bricks(v, v.box((side * 13 - 3.5, -3.5, 0), (side * 13 + 3.5, 3.5, 28)), 4, 7)
        v.paint(v.box((side * 13 - 4.5, -4.5, 0), (side * 13 + 4.5, 4.5, 3)), *STONE)
    ring = np.hypot(v.x, v.z - 28)
    bricks(v, (ring >= 9.5) & (ring <= 16.5) & (v.z >= 28) & (np.abs(v.y) < 3.5), 4, 5)
    v.paint(v.box((-2.5, -4.5, 43), (2.5, 4.5, 46)), *STONE)
    film = (np.abs(v.y) < 1) & (((ring < 9.5) & (v.z >= 28)) | ((np.abs(v.x) < 9.5) & (v.z < 28) & (v.z >= 1)))
    swirl = np.sin(np.hypot(v.x, v.z - 22) * 0.9 + np.arctan2(v.z - 22, v.x) * 2.0)
    v.paint(film, 'magic1')
    v.paint(film & (swirl > 0.1), 'magic2')
    v.paint(film & (swirl > 0.85), 'white')
    worn(v, (v.grid > 0) & ~film, 0.07)
    mossy(v, (v.grid > 0) & ~film, 0.3)
    return v


@model
def wall_ruin():
    v = new('wall_ruin', 44, 8, 22, 35)
    body = v.box((-22, -3, 0), (22, 3, 22)) & (v.z < 11 + v.rough(7) * 9 + np.abs(v.x) * 0.12)
    bricks(v, body, 4, 8)
    v.clear(v.box((-4, -4, 7), (2, 4, 14)) | (v.ball((-1, 0, 14), (3, 5, 3))))
    ivy = v.box((-22, -4, 0), (22, -3, 22)) & np.roll(body, -1, 1) & (v.rough(4) > 0.25)
    v.paint(ivy, ['leaf2', 'leaf3', 'leaf1'])
    worn(v, body, 0.08)
    mossy(v, body, 0.35)
    return v


@model
def tower():
    v = new('tower', 34, 34, 70, 36)
    radius = np.hypot(v.x, v.y)
    shell = (radius <= 15) & (radius >= 11.5) & (v.z < 46 + v.rough(8) * 16 + v.x * 0.35)
    bricks(v, shell, 4, 8)
    v.paint((radius < 11.5) & (v.z < 1), *DARK_STONE)
    v.clear((np.abs(v.x) < 3) & (v.y < 0) & (v.z < 12) & (v.z >= 1))
    v.clear(v.ball((0, -13, 12), (3, 4, 3)))
    for angle, z in ((0.9, 24), (2.6, 34), (4.4, 22), (5.6, 38)):
        v.clear(v.ball((math.cos(angle) * 13, math.sin(angle) * 13, z), (2.4, 2.4, 3.6)) & (np.abs(v.z - z) < 3.2))
    v.paint(v.box((-8, -8, 20), (8, 8, 21)) & (radius < 11.5), *WOOD)
    v.paint(v.box((-1, 6, 21), (1, 8, 26)), 'iron1')
    flame(v, (0, 7, 26), 4, 1.2)
    ivy = (radius > 15) & (radius <= 16.2) & (v.rough(5) > 0.3) & (v.z < 34) & np.roll(shell, 1, 0) | ((radius > 15) & (radius <= 16.2) & (v.rough(5, 3) > 0.45) & (v.z < 30))
    v.paint(ivy & (v.grid == 0), ['leaf2', 'leaf3', 'leaf1'])
    worn(v, shell, 0.07)
    mossy(v, shell, 0.35)
    return v


@model
def statue():
    v = new('statue', 14, 14, 30, 37)
    bricks(v, v.box((-6, -6, 0), (6, 6, 5)), 3, 6)
    robe = v.rod((0, 0), 4.2, 5, 19, 2.6)
    v.paint(robe, ['stone2', 'stone3'])
    v.paint(v.box((-4.5, -2, 17), (4.5, 2.5, 21)), ['stone2', 'stone3'])
    hood = v.ball((0, 0.4, 23.5), (3.2, 3.2, 3.4))
    v.paint(hood, ['stone2', 'stone3'])
    v.paint(hood & (v.y < -1.6) & (v.z < 25) & (np.abs(v.x) < 2), 'stone1')
    v.paint(v.box((-1.5, -3, 23), (-0.5, -2, 24)) | v.box((0.5, -3, 23), (1.5, -2, 24)), 'crystal3')
    v.paint(v.box((-0.6, -4.6, 5), (0.6, -3.6, 18)), 'stone4')
    v.paint(v.box((-2.6, -4.6, 15), (2.6, -3.6, 16)), 'stone4')
    v.paint(v.box((-3.4, -4.2, 14), (3.4, -2, 17)) & (np.abs(v.x) > 0.6), ['stone2', 'stone3'])
    worn(v, v.grid > 0, 0.05)
    mossy(v, (v.grid > 0) & (v.z < 22), 0.3)
    return v


@model
def obelisk():
    v = new('obelisk', 14, 14, 28, 38)
    v.paint(v.box((-6, -6, 0), (6, 6, 2)), *STONE)
    v.paint(v.box((-5, -5, 2), (5, 5, 4)), *STONE)
    half = np.where(v.z < 23, 3.6 - (v.z - 4) * 0.06, 2.4 - (v.z - 23) * 0.55)
    body = (np.abs(v.x) <= half) & (np.abs(v.y) <= half) & (v.z >= 4)
    v.paint(body, *DARK_STONE)
    face = body & ((np.abs(v.x) > half - 1) | (np.abs(v.y) > half - 1)) & (v.z > 6) & (v.z < 22)
    strip = (np.abs(v.x) < 1.6) | (np.abs(v.y) < 1.6)
    v.paint(face & strip & (v.rng.random(v.grid.shape) < 0.42), ['crystal2', 'crystal3'], [3, 1])
    mossy(v, v.grid > 0, 0.2)
    return v


@model
def path():
    v = new('path', 26, 26, 1, 39)
    seeds = v.rng.uniform(-11, 11, (11, 2))
    gaps = np.sort(np.stack([np.hypot(v.x - sx, v.y - sy) for sx, sy in seeds]), 0)
    owner = np.argmin(np.stack([np.hypot(v.x - sx, v.y - sy) for sx, sy in seeds]), 0)
    slab = (gaps[1] - gaps[0] > 1.3) & (np.hypot(v.x, v.y) < 11.5 + v.rough(4) * 2)
    for k in range(len(seeds)):
        v.paint(slab & (owner == k), ['stone2', 'stone3', 'stone4'][k % 3])
    v.paint(slab & (v.rng.random(v.grid.shape) < 0.07), *MOSS)
    return v


@model
def well():
    v = new('well', 20, 20, 23, 40)
    radius = np.hypot(v.x, v.y)
    bricks(v, (radius <= 7.5) & (radius >= 5) & (v.z < 6), 3, 6)
    v.paint((radius < 5) & (v.z >= 3) & (v.z < 4), 'water')
    for side in (-1, 1):
        v.paint(v.box((side * 7 - 1, -1, 5), (side * 7 + 1, 1, 17)), *WOOD)
    v.paint(v.box((-7, -0.6, 13), (7, 0.6, 14.2)), 'wood1')
    v.paint(v.box((-0.5, -0.5, 8), (0.5, 0.5, 13)), 'cream')
    v.paint(v.box((-1.5, -1.5, 6), (1.5, 1.5, 8)), *WOOD)
    roof = (np.abs(v.y) <= (23 - v.z) * 1.5 + 0.5) & (v.z >= 17) & (np.abs(v.x) <= 9.5)
    v.paint(roof, ['red1', 'red2'])
    v.paint(roof & (v.x.astype(int) % 3 == 0), 'red1')
    mossy(v, (v.z < 6) & (v.grid > 0), 0.3)
    return v


@model
def brazier():
    v = new('brazier', 9, 9, 7, 41)
    v.paint(v.box((-2.5, -2.5, 0), (2.5, 2.5, 1)), *STONE)
    v.paint(v.box((-1.5, -1.5, 1), (1.5, 1.5, 3)), *STONE)
    v.paint((np.maximum(np.abs(v.x), np.abs(v.y)) <= 1.5 + (v.z - 3)) & (v.z >= 3) & (v.z < 5), *IRON)
    v.paint(v.box((-2.5, -2.5, 4), (2.5, 2.5, 5)), ['ember', 'fire1'])
    flame(v, (0, 0, 5), 2, 1.6)
    return v


@model
def torch():
    v = new('torch', 9, 9, 18, 16)
    v.paint(v.box((-2.5, -2.5, 0), (2.5, 2.5, 2)), *STONE)
    v.paint(v.box((-1, -1, 2), (1, 1, 12)), *WOOD)
    v.paint(v.box((-2, -2, 11), (2, 2, 13)), *IRON)
    flame(v, (0, 0, 13), 5, 1.4)
    return v


@model
def campfire():
    v = new('campfire', 16, 16, 7, 42)
    radius = np.hypot(v.x, v.y)
    v.paint((radius > 5) & (radius < 7.2) & (v.z < 1 + (v.rough(2) > 0)) & (v.rng.random(v.grid.shape) < 0.85), *STONE)
    v.paint(v.line((-4, -3, 0.5), (4, 3, 2.5), 1.0), *WOOD)
    v.paint(v.line((-4, 3, 0.5), (4, -3, 2.5), 1.0), *WOOD)
    v.paint((radius < 3.5) & (v.z < 1), ['ember', 'black'])
    flame(v, (0, 0, 2), 5, 2.2)
    return v


@model
def crystal():
    v = new('crystal', 18, 18, 22, 17)
    v.paint(((v.x / 8) ** 2 + (v.y / 7) ** 2 + (v.z / 3.5) ** 2 <= 1 + v.rough(3) * 0.3), *STONE)
    for at, height, width, lean in (((0, 0), 20, 2.6, (1, 0)), ((-4, 2), 12, 2.0, (-3, 1)), ((4, -2), 14, 2.0, (3, -2)), ((1, 4), 9, 1.6, (0, 3)), ((-2, -4), 8, 1.6, (-1, -3))):
        shard(v, (at[0], at[1], 1), height, width, lean)
    return v


@model
def crystal_small():
    v = new('crystal_small', 12, 12, 8, 43)
    v.paint(((v.x / 5) ** 2 + (v.y / 4.5) ** 2 + (v.z / 2.2) ** 2 <= 1 + v.rough(3) * 0.3), *STONE)
    for at, height, width, lean in (((0, 0), 7, 1.6, (0.5, 0)), ((-2.5, 1.5), 4, 1.2, (-1, 0.5)), ((2.5, -1.5), 5, 1.2, (1, -1))):
        shard(v, (at[0], at[1], 1), height, width, lean)
    return v


@model
def lantern_post():
    v = new('lantern_post', 16, 8, 22, 44)
    v.paint(v.box((-6, -2, 0), (-2, 2, 2)), *STONE)
    v.paint(v.box((-5, -1, 2), (-3, 1, 21)), *WOOD)
    v.paint(v.box((-5, -1, 19), (5, 1, 21)), *WOOD)
    v.paint(v.line((-4, 0, 14), (0, 0, 19), 0.8), *WOOD)
    v.paint(v.box((3, -0.5, 16), (4, 0.5, 19)), 'iron1')
    v.paint(v.box((1.5, -2, 11), (5.5, 2, 16)), *IRON)
    v.paint(v.box((2.5, -2, 12), (4.5, 2, 15)) | v.box((1.5, -1, 12), (5.5, 1, 15)), 'fire2')
    return v


@model
def forge():
    v = new('forge', 32, 24, 26, 45)
    furnace = v.box((-14, -3, 0), (-2, 9, 13))
    bricks(v, furnace, 3, 6)
    bricks(v, v.box((-11, 1, 13), (-5, 7, 26)), 3, 6)
    v.clear(v.box((-9, 3, 22), (-7, 5, 26)))
    v.clear(v.box((-11, -3, 3), (-5, 0, 8)))
    v.paint(v.box((-11, 0, 3), (-5, 1, 8)), ['ember', 'fire1', 'fire2'])
    v.paint(v.box((-12, -5, 0), (-4, -3, 1)), ['black', 'stone1'])
    v.paint(v.box((3, -5, 0), (8, 0, 3)), *WOOD)
    v.paint(v.box((2, -4, 3), (9, -1, 5)), 'iron1')
    v.paint(v.box((1, -4.5, 5), (12, -0.5, 6.5)), 'iron2')
    v.paint(v.box((12, -3.5, 5.5), (14, -1.5, 6.5)), 'iron2')
    v.paint(v.box((4, -3, 6.5), (5, -2, 9)), *WOOD)
    v.paint(v.box((3, -3.6, 9), (6, -1.4, 10.6)), 'iron1')
    barrel = v.rod((10, 6), 3.2, 0, 7)
    v.paint(barrel, *WOOD)
    v.paint(barrel & ((v.z.astype(int) == 1) | (v.z.astype(int) == 5)), 'iron1')
    v.paint(v.rod((10, 6), 2.4, 6, 7), 'water')
    v.paint(v.ball((-1, -6, 0), (3, 2.5, 2.4)), ['black', 'iron1'])
    return v


@model
def alchemy():
    v = new('alchemy', 34, 14, 15, 46)
    v.paint(v.box((-14, -4, 5), (6, 5, 6.5)), *WOOD)
    for x in (-13, 4):
        for y in (-3, 3):
            v.paint(v.box((x - 1, y - 1, 0), (x + 1, y + 1, 5)), 'wood1')
    v.paint(v.box((-14, 3.5, 6.5), (6, 5, 15)) & ((v.z.astype(int) % 4 == 2) | (np.abs(v.x + 4) > 9)), *WOOD)
    for shelf in (7.5, 11.5):
        for x in range(-12, 5, 3):
            colour = ['red2', 'blue2', 'crystal2', 'magic2', 'yellow', 'shroom'][int(v.rng.integers(6))]
            v.paint(v.box((x, 3.5, shelf), (x + 2, 5, shelf + 2)), colour)
            v.paint(v.box((x + 0.5, 3.5, shelf + 2), (x + 1.5, 5, shelf + 3)), 'cream')
    for x, colour, tall in ((-11, 'red2', 3), (-7, 'crystal2', 2), (-4, 'yellow', 3)):
        v.paint(v.box((x, -2, 6.5), (x + 2, 0, 6.5 + tall)), colour)
        v.paint(v.box((x + 0.5, -1.5, 6.5 + tall), (x + 1.5, -0.5, 7.5 + tall)), 'cream')
    v.paint(v.box((0, -3, 6.5), (5, 1, 7.5)), 'cream')
    v.paint(v.box((2, -3, 6.5), (3, 1, 7.8)), 'red1')
    for x in (9, 15):
        v.paint(v.box((x - 0.6, -0.6, 0), (x + 0.6, 0.6, 3)), 'iron1')
    v.paint(v.ball((12, 0, 5), (4.6, 4.6, 4)) & (v.z < 6.5), *IRON)
    v.clear(v.ball((12, 0, 6), (3.4, 3.4, 2.6)) & (v.z >= 5))
    v.paint((np.hypot(v.x - 12, v.y) < 3.5) & (v.z >= 5) & (v.z < 6), ['magic1', 'magic2'])
    v.paint(v.box((11, -1, 6), (12, 0, 7)) | v.box((13, 1, 6), (14, 2, 8)), 'magic2')
    return v


@model
def library():
    v = new('library', 26, 16, 20, 47)
    case = v.box((-12, 2, 0), (12, 7, 20))
    v.paint(case, *WOOD)
    for shelf in (1.5, 6, 10.5, 15):
        v.clear(v.box((-11, 2, shelf), (11, 5.5, shelf + 3.5)))
        x = -11
        while x < 10.5:
            if v.rng.random() < 0.13:
                x += 1
                continue
            tall = int(v.rng.integers(2, 4))
            colour = ['red1', 'red2', 'blue1', 'blue2', 'cream', 'leaf2', 'gold', 'magic1'][int(v.rng.integers(8))]
            v.paint(v.box((x, 3, shelf), (x + 1, 5.5, shelf + tall)), colour)
            x += 1
    v.paint(v.box((-6, -5, 0), (-2, -1, 1)), 'wood1')
    v.paint(v.box((-4.6, -3.6, 1), (-3.4, -2.4, 7)), *WOOD)
    for k in range(4):
        v.paint(v.box((-7, -6 + k, 7 + k * 0.5), (-1, -5 + k, 8 + k * 0.5)), 'wood2')
        v.paint(v.box((-6.5, -6 + k, 8 + k * 0.5), (-1.5, -5 + k, 8.6 + k * 0.5)), 'cream' if k not in (0,) else 'red1')
    v.paint(v.box((3, -5, 0), (7, -1, 3.5)), *WOOD)
    v.paint(v.box((9, -3, 0), (11, -1, 5)), 'cream')
    flame(v, (10, -2, 5), 2, 0.6)
    return v


@model
def scrying():
    v = new('scrying', 16, 16, 18, 48)
    v.paint(v.rod((0, 0), 7, 0, 1), *STONE)
    v.paint(v.rod((0, 0), 5, 1, 2), *STONE)
    bricks(v, v.rod((0, 0), 2, 2, 8), 3, 99)
    v.paint(v.rod((0, 0), 3.4, 8, 9.5), 'gold')
    orb = v.ball((0, 0, 13), 3.6)
    v.paint(orb, ['magic1', 'magic2'], [1, 2])
    v.paint(orb & (v.rng.random(v.grid.shape) < 0.12), 'white')
    ring = np.abs(np.hypot(v.x, v.y) - 5.6) < 0.8
    v.paint(ring & (v.z >= 12.5) & (v.z < 13.5), 'gold')
    return v


@model
def map_table():
    v = new('map_table', 20, 20, 7, 49)
    v.paint(v.rod((0, 0), 3.5, 0, 4), *STONE)
    v.paint(v.rod((0, 0), 8.5, 4, 6), *STONE)
    v.paint(v.box((-6, -4, 6), (6, 4, 6.6)) & (v.z < 7), 'cream')
    land = v.box((-6, -4, 6), (6, 4, 7)) & (v.rough(3) > 0.1)
    v.paint(land, ['leaf3', 'leaf4'])
    v.paint(v.box((-6, -4, 6), (6, 4, 7)) & ~land, ['cream', 'blue2'], [3, 1])
    return v


@model
def meeting_stones():
    v = new('meeting_stones', 40, 40, 7, 50)
    radius = np.hypot(v.x, v.y)
    v.paint((radius < 10.5) & (v.z < 1), *STONE)
    v.paint((np.abs(radius - 7.5) < 0.9) & (v.z < 1), ['crystal1', 'crystal2'])
    v.paint((radius < 2.2) & (v.z < 1), 'crystal3')
    for k in range(6):
        a = math.tau * k / 6 + 0.26
        x, y = math.cos(a) * 15, math.sin(a) * 15
        tall = 4 + k % 3
        seat = v.box((x - 2.6, y - 2.6, 0), (x + 2.6, y + 2.6, tall))
        v.paint(seat, *STONE)
    worn(v, v.grid > 0, 0.08)
    mossy(v, (radius > 11) & (v.grid > 0), 0.45)
    return v


@model
def tent():
    v = new('tent', 30, 26, 19, 51)
    slope = (19 - v.z) * 0.74
    cloth = (np.abs(v.x) <= slope) & (np.abs(v.y) < 12)
    inner = (np.abs(v.x) <= slope - 1.4) & (v.y < 11) & (v.z < 17)
    stripe = ((slope - np.abs(v.x) + v.z * 0.0).astype(int) + (np.abs(v.x) * 0.8).astype(int)) % 8 < 4
    v.paint(cloth & ~inner, 'cream')
    v.paint(cloth & ~inner & (((v.z.astype(int)) % 6) < 3), ['red1', 'red2'], [1, 3])
    v.clear((np.abs(v.x) < 5 - v.z * 0.3) & (v.y < -9))
    v.paint(v.box((-5, -11, 0), (5, 9, 0.9)), ['dirt1', 'dirt2'])
    v.paint(v.box((-3, -6, 0.9), (2, 6, 2)), ['red1', 'blue1'])
    v.paint(v.box((-0.8, -13, 0), (0.8, -12, 19)) | v.box((-0.8, 12, 0), (0.8, 13, 19)), *WOOD)
    return v


@model
def banner():
    v = new('banner', 12, 8, 27, 52)
    v.paint(v.box((-4, -2, 0), (0, 2, 2)), *STONE)
    v.paint(v.box((-3, -1, 2), (-1, 1, 26)), *WOOD)
    v.paint(v.box((-2.5, -0.5, 26), (-1.5, 0.5, 27)), 'gold')
    v.paint(v.box((-3, -0.6, 23), (6, 0.6, 24)), *WOOD)
    cloth = v.box((0, -0.5, 9), (6, 0.5, 23)) & (v.z > 11 - np.abs(v.x - 3) * 0.9)
    v.paint(cloth, ['red1', 'red2'], [1, 3])
    v.paint(cloth & (np.abs(v.x - 3) + np.abs(v.z - 18) < 2.4), 'gold')
    return v


@model
def signpost():
    v = new('signpost', 16, 6, 15, 53)
    v.paint(v.box((-1, -1, 0), (1, 1, 15)), *WOOD)
    v.paint(v.box((-1, -2, 10), (7, -1, 13)) & (v.x < 5 + (1.5 - np.abs(v.z - 11.5))), 'wood3')
    v.paint(v.box((-7, -2, 6), (1, -1, 9)) & (v.x > -5 - (1.5 - np.abs(v.z - 7.5))), 'wood3')
    v.paint(v.box((0, -2.2, 11), (4, -2, 12)) | v.box((-4, -2.2, 7), (0, -2, 8)), 'bark1')
    v.paint(v.box((-2, -2, 0), (2, 2, 1)), *STONE)
    return v


@model
def chest():
    v = new('chest', 12, 9, 7, 54)
    body = v.box((-5, -3.5, 0), (5, 3.5, 4))
    v.paint(body, *WOOD)
    lid = (np.abs(v.x) < 5) & (v.y ** 2 / 12.25 + (v.z - 4) ** 2 / 9 <= 1) & (v.z >= 4)
    v.paint(lid, *WOOD)
    bands = (np.abs(np.abs(v.x) - 3.5) < 0.6) | (np.abs(v.x) > 4.4)
    v.paint((body | lid) & bands, 'iron1')
    v.paint(v.box((-1, -4.5, 2.5), (1, -3.5, 4.5)), 'gold')
    v.paint(v.box((-5, -3.5, 3.6), (5, 3.5, 4)), 'iron1')
    return v


@model
def supplies():
    v = new('supplies', 22, 16, 7, 55)
    crate = v.box((-10, -3, 0), (-3, 4, 6))
    v.paint(crate, *WOOD)
    edge = ((np.abs(v.x + 6.5) > 2.6).astype(int) + (np.abs(v.y - 0.5) > 2.6).astype(int) + (np.abs(v.z - 3) > 2.1).astype(int)) >= 2
    v.paint(crate & edge, 'wood1')
    barrel = v.rod((4, 1), 3.4, 0, 7)
    v.paint(barrel, *WOOD)
    v.paint(barrel & ((v.z.astype(int) == 1) | (v.z.astype(int) == 5)), 'iron1')
    v.paint(v.rod((4, 1), 2.6, 6.2, 7), 'wood3')
    v.paint(v.ball((-1, -5, 1.6), (2.8, 2.2, 2.6)), 'cream')
    v.paint(v.box((-1.6, -5.6, 3.6), (-0.4, -4.4, 4.6)), 'wood3')
    v.paint(v.box((7, -6, 0), (10, -3, 3)), *WOOD)
    return v


@model
def weapon_rack():
    v = new('weapon_rack', 22, 8, 15, 56)
    for x in (-9, 9):
        v.paint(v.box((x - 1, -1, 0), (x + 1, 1, 13)), *WOOD)
        v.paint(v.box((x - 1, -3, 0), (x + 1, 3, 1)), 'wood1')
    for z in (4, 11):
        v.paint(v.box((-10, -0.6, z), (10, 0.6, z + 1.2)), *WOOD)
    for x in (-6, -3):
        v.paint(v.box((x - 0.5, -1.6, 2), (x + 0.5, -0.6, 12)), 'iron2')
        v.paint(v.box((x - 1.5, -1.6, 11), (x + 1.5, -0.6, 12)), 'gold')
        v.paint(v.box((x - 0.5, -1.6, 12), (x + 0.5, -0.6, 15)), 'wood1')
    shield = (np.hypot(v.x - 4, v.z - 7.5) < 4.2) & (v.y < -0.6) & (v.y > -1.8)
    v.paint(shield, 'blue2')
    v.paint(shield & (np.hypot(v.x - 4, v.z - 7.5) > 3.2), 'gold')
    v.paint(shield & (np.hypot(v.x - 4, v.z - 7.5) < 1.2), 'gold')
    return v


@model
def fence():
    v = new('fence', 18, 4, 7, 57)
    for x in (-8, 0, 8):
        v.paint(v.box((x - 1, -1, 0), (x + 1, 1, 7)), *WOOD)
    for z in (2, 5):
        v.paint(v.box((-9, -0.5, z), (9, 0.5, z + 1)), 'wood2')
    return v


for name, build in MODELS.items():
    if not ONLY or name in ONLY:
        build().save()
print('GLADE DONE', flush=True)

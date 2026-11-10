import math, random, sys
from pathlib import Path

from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import solids
from solids import Model, material

solids.use(Path(sys.argv[sys.argv.index('--') + 1]).resolve())
ONLY = set(sys.argv[sys.argv.index('--') + 2:])

CREAM = material('clay_cream', (0.93, 0.87, 0.77))
SAND = material('clay_sand', (0.83, 0.73, 0.59))
TAN = material('clay_tan', (0.72, 0.55, 0.38))
COCOA = material('clay_cocoa', (0.29, 0.23, 0.19), 0.8)
WHITE = material('clay_white', (0.97, 0.95, 0.91), 0.8)
STEEL = material('clay_steel', (0.74, 0.72, 0.69), 0.55)
GLASS = material('clay_glass', (0.72, 0.84, 0.9), 0.15)
SCREEN = material('clay_screen', (0.42, 0.72, 0.9), 0.3, 1.1)
LEAF = material('clay_leaf', (0.37, 0.52, 0.35))
LEAF_LIGHT = material('clay_leaf_light', (0.53, 0.65, 0.41))
SOIL = material('clay_soil', (0.33, 0.25, 0.2))
TERRACOTTA = material('clay_terracotta', (0.8, 0.46, 0.33))
MUSTARD = material('clay_mustard', (0.88, 0.69, 0.3))
BLUE = material('clay_blue', (0.42, 0.56, 0.68))
ROSE = material('clay_rose', (0.85, 0.62, 0.6))
LAMP = material('clay_lamp', (1.0, 0.86, 0.62), 0.6, 2.4)
NEON = material('clay_neon', (1.0, 0.56, 0.4), 0.4, 5.0)
LED_GREEN = material('clay_led_green', (0.45, 0.95, 0.6), 0.4, 3.0)
LED_BLUE = material('clay_led_blue', (0.45, 0.75, 1.0), 0.4, 3.0)
ACCENTS = [TERRACOTTA, MUSTARD, BLUE, ROSE]


MODELS = {}


def model(build):
    MODELS['clay_' + build.__name__] = build
    return build


# Every piece is authored facing -y: that side faces the room, or the person using it.

def chair(m, at, turn=0.0, seat=SAND):
    with m.at(at, turn):
        for k in range(5):
            a = math.tau * k / 5
            m.along(COCOA, (0, 0, 0.07), (math.cos(a) * 0.29, math.sin(a) * 0.29, 0.05), (0.05, 0.035), 0.012)
        m.disc(COCOA, (0, 0, 0.06), 0.03, 0.36, round=0.0)
        m.box(seat, (0, 0, 0.46), (0.48, 0.46, 0.1), round=0.04)
        m.box(COCOA, (0, 0.21, 0.6), (0.06, 0.03, 0.3), round=0.01)
        m.box(seat, (0, 0.23, 0.83), (0.44, 0.08, 0.46), round=0.035, tilt=('X', -0.12))
        for side in (-1, 1):
            m.box(COCOA, (side * 0.27, 0.02, 0.62), (0.04, 0.26, 0.03), round=0.012)
            m.box(COCOA, (side * 0.27, 0.1, 0.54), (0.03, 0.03, 0.16), round=0.01)


def monitor(m, at, turn=0.0, width=0.58):
    with m.at(at, turn):
        m.box(COCOA, (0, 0.02, 0.012), (0.24, 0.17, 0.024), round=0.01)
        m.box(COCOA, (0, 0.05, 0.12), (0.05, 0.03, 0.22), round=0.01)
        m.box(COCOA, (0, 0.03, 0.34), (width, 0.035, 0.36), round=0.014)
        m.box(SCREEN, (0, 0.01, 0.345), (width - 0.05, 0.012, 0.31), round=0.004)


def laptop(m, at, turn=0.0):
    with m.at(at, turn):
        m.box(STEEL, (0, 0, 0.01), (0.34, 0.24, 0.018), round=0.008)
        m.box(STEEL, (0, 0.15, 0.115), (0.34, 0.016, 0.23), round=0.008, tilt=('X', -0.3))
        m.box(SCREEN, (0, 0.142, 0.118), (0.3, 0.008, 0.19), round=0.003, tilt=('X', -0.3))


def mug(m, at, mat):
    m.disc(mat, at, 0.04, 0.09, round=0.008, segments=16)
    m.box(mat, (at[0] + 0.05, at[1], at[2] + 0.045), (0.03, 0.014, 0.05), round=0.006)


def books(m, at, rng, count=3, turn=0.0):
    with m.at(at, turn):
        z = 0.0
        for _ in range(count):
            thick = rng.uniform(0.03, 0.05)
            m.box(rng.choice([CREAM, SAND] + ACCENTS), (rng.uniform(-0.015, 0.015), rng.uniform(-0.01, 0.01), z + thick / 2), (rng.uniform(0.2, 0.26), rng.uniform(0.15, 0.18), thick), rng.uniform(-0.2, 0.2), 0.008)
            z += thick


def foliage(m, at, rng, reach, count, low, high):
    for k in range(count):
        a = math.tau * k / count + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.0, reach)
        size = rng.uniform(0.55, 1.0) * reach * 0.62
        m.ball(LEAF if k % 3 else LEAF_LIGHT, (at[0] + math.cos(a) * r, at[1] + math.sin(a) * r, at[2] + rng.uniform(low, high)), size, (1, 1, rng.uniform(0.75, 0.95)))


def pot(m, at, mat, radius=0.22, height=0.38):
    m.disc(mat, at, radius * 0.78, height, radius, round=0.02)
    m.disc(mat, (at[0], at[1], at[2] + height - 0.03), radius * 1.06, 0.05, round=0.02)
    m.disc(SOIL, (at[0], at[1], at[2] + height), radius * 0.9, 0.022, round=0.0)


def small_plant(m, at, rng, mat=CREAM):
    pot(m, at, mat, 0.075, 0.11)
    foliage(m, (at[0], at[1], at[2] + 0.12), rng, 0.1, 5, 0.03, 0.14)


def desk(m, at, turn, rng, extras=True):
    with m.at(at, turn):
        m.box(CREAM, (0, 0, 0.735), (1.6, 0.8, 0.055), round=0.02)
        for side in (-1, 1):
            m.box(SAND, (side * 0.74, 0, 0.355), (0.055, 0.7, 0.71), round=0.02)
        m.box(SAND, (0, 0.33, 0.5), (1.43, 0.03, 0.36), round=0.012)
        side = rng.choice((-1, 1))
        m.box(SAND, (side * 0.46, 0.04, 0.3), (0.42, 0.56, 0.56), round=0.02)
        for z in (0.16, 0.34, 0.5):
            m.box(COCOA, (side * 0.46, -0.245, z), (0.16, 0.016, 0.018), round=0.006)
        monitor(m, (rng.uniform(-0.08, 0.08), 0.16, 0.762), rng.uniform(-0.08, 0.08))
        m.box(WHITE, (0, -0.16, 0.772), (0.42, 0.13, 0.018), round=0.008)
        m.box(WHITE, (0.33, -0.16, 0.774), (0.06, 0.1, 0.024), round=0.01)
        if extras:
            pick = rng.random()
            if pick < 0.4:
                mug(m, (-0.5, -0.1, 0.762), rng.choice(ACCENTS + [WHITE]))
            elif pick < 0.7:
                small_plant(m, (-0.58, 0.2, 0.762), rng, rng.choice([CREAM, TERRACOTTA]))
            else:
                books(m, (-0.56, 0.12, 0.762), rng, 3, rng.uniform(-0.4, 0.4))


@model
def wall(m, length=8.0):
    m.box(CREAM, (0, 0, 3.0), (length, 0.4, 6.0), round=0.03)
    m.box(SAND, (0, -0.2, 0.16), (length - 0.02, 0.05, 0.32), round=0.015)
    m.box(SAND, (0, 0, 6.03), (length, 0.46, 0.14), round=0.03)


@model
def wall_short(m):
    wall(m, 4.0)


@model
def wall_window(m):
    m.box(CREAM, (0, 0, 0.6), (8.0, 0.4, 1.2), round=0.03)
    m.box(CREAM, (0, 0, 5.3), (8.0, 0.4, 1.4), round=0.03)
    for x in (-3.6, 0.0, 3.6):
        m.box(CREAM, (x, 0, 2.9), (0.8, 0.4, 3.4), round=0.03)
    for x in (-1.8, 1.8):
        m.box(GLASS, (x, 0.04, 2.9), (2.8, 0.05, 3.4), round=0.0)
        m.box(WHITE, (x, 0.0, 2.9), (0.07, 0.16, 3.4), round=0.015)
        for z in (2.35, 3.6):
            m.box(WHITE, (x, 0.0, z), (2.8, 0.16, 0.07), round=0.015)
        m.box(WHITE, (x, -0.2, 1.2), (2.9, 0.22, 0.07), round=0.02)
    m.box(SAND, (0, -0.2, 0.16), (7.98, 0.05, 0.32), round=0.015)
    m.box(SAND, (0, 0, 6.03), (8.0, 0.46, 0.14), round=0.03)


@model
def wall_door(m):
    m.box(CREAM, (0, 0, 4.4), (8.0, 0.4, 3.2), round=0.03)
    for side in (-1, 1):
        m.box(CREAM, (side * 2.5, 0, 1.4), (3.0, 0.4, 2.8), round=0.03)
        m.box(SAND, (side * 2.5, -0.2, 0.16), (2.98, 0.05, 0.32), round=0.015)
        m.box(TAN, (side * 0.49, 0.02, 1.38), (0.96, 0.07, 2.72), round=0.02)
        m.box(GLASS, (side * 0.49, -0.02, 1.75), (0.56, 0.03, 1.5), round=0.01)
        m.box(STEEL, (side * 0.1, -0.05, 1.1), (0.03, 0.05, 0.36), round=0.012)
    m.box(SAND, (0, -0.19, 2.85), (2.3, 0.06, 0.14), round=0.02)
    for side in (-1, 1):
        m.box(SAND, (side * 1.08, -0.19, 1.4), (0.14, 0.06, 2.8), round=0.02)
    m.box(SAND, (0, 0, 6.03), (8.0, 0.46, 0.14), round=0.03)


@model
def wall_corner(m):
    m.box(CREAM, (0, 0, 3.0), (0.4, 0.4, 6.0), round=0.03)
    m.box(SAND, (0, 0, 6.03), (0.46, 0.46, 0.14), round=0.03)


@model
def column(m):
    m.box(SAND, (0, 0, 0.12), (0.76, 0.76, 0.24), round=0.03)
    m.box(CREAM, (0, 0, 3.0), (0.6, 0.6, 5.6), round=0.05)
    m.box(SAND, (0, 0, 5.9), (0.76, 0.76, 0.24), round=0.03)


@model
def partition(m):
    m.box(SAND, (0, 0, 0.06), (4.0, 0.12, 0.12), round=0.02)
    m.box(SAND, (0, 0, 2.64), (4.0, 0.12, 0.12), round=0.02)
    for x in (-1.96, -0.66, 0.66, 1.96):
        m.box(SAND, (x, 0, 1.35), (0.08, 0.1, 2.5), round=0.02)
    m.box(GLASS, (0, 0, 1.35), (3.9, 0.03, 2.5), round=0.0)
    m.box(WHITE, (0, -0.02, 1.25), (3.9, 0.012, 0.5), round=0.0)


@model
def wall_art(m):
    rng = random.Random(3)
    for x, w, h, z in ((-1.25, 0.9, 1.2, 2.3), (0.0, 1.3, 0.9, 2.45), (1.3, 0.9, 1.2, 2.3)):
        m.box(TAN, (x, 0, z), (w, 0.05, h), round=0.015)
        m.box(WHITE, (x, -0.02, z), (w - 0.12, 0.03, h - 0.12), round=0.006)
        for k in range(3):
            m.box(rng.choice(ACCENTS), (x + rng.uniform(-0.2, 0.2) * w, -0.035, z + rng.uniform(-0.25, 0.25) * h), (rng.uniform(0.2, 0.4) * w, 0.012, rng.uniform(0.15, 0.35) * h), round=0.01)


@model
def wall_shelf(m):
    rng = random.Random(8)
    for z in (1.5, 2.15):
        m.box(TAN, (0, 0, z), (2.2, 0.28, 0.045), round=0.015)
        for x in (-0.8, 0.8):
            m.box(COCOA, (x, 0.05, z - 0.09), (0.03, 0.18, 0.14), round=0.01)
    x = -0.95
    while x < 0.1:
        w = rng.uniform(0.035, 0.07)
        h = rng.uniform(0.2, 0.3)
        m.box(rng.choice([CREAM, SAND, WHITE] + ACCENTS), (x + w / 2, 0.02, 1.525 + h / 2), (w, 0.17, h), round=0.008)
        x += w + 0.004
    small_plant(m, (0.55, 0.0, 1.523), rng, TERRACOTTA)
    m.box(WHITE, (0.9, 0.0, 1.6), (0.2, 0.14, 0.16), round=0.02)
    small_plant(m, (-0.75, 0.0, 2.173), rng)
    books(m, (-0.2, 0.0, 2.173), rng, 4)
    m.box(TAN, (0.55, 0.03, 2.33), (0.3, 0.03, 0.34), round=0.01, tilt=('X', -0.15))
    m.box(BLUE, (0.55, 0.012, 2.33), (0.22, 0.02, 0.26), round=0.006, tilt=('X', -0.15))


@model
def wall_clock(m):
    m.rod(COCOA, (0, 0.03, 2.6), (0, -0.03, 2.6), 0.36, segments=40, round=0.012)
    m.rod(WHITE, (0, -0.02, 2.6), (0, -0.045, 2.6), 0.31, segments=40)
    for k in range(12):
        a = math.tau * k / 12
        m.box(COCOA, (math.sin(a) * 0.26, -0.05, 2.6 + math.cos(a) * 0.26), (0.02, 0.012, 0.05 if k % 3 else 0.08), round=0.004, tilt=('Y', a))
    m.along(COCOA, (0, -0.058, 2.6), (0.1, -0.058, 2.72), (0.024, 0.012), 0.005)
    m.along(TERRACOTTA, (0, -0.064, 2.6), (-0.17, -0.064, 2.66), (0.016, 0.012), 0.005)
    m.rod(COCOA, (0, -0.05, 2.6), (0, -0.075, 2.6), 0.022, segments=12)


@model
def wall_display(m):
    rng = random.Random(5)
    m.box(COCOA, (0, 0, 2.4), (3.2, 0.08, 1.8), round=0.025)
    m.box(SCREEN, (0, -0.04, 2.4), (3.08, 0.02, 1.68), round=0.006)
    m.box(WHITE, (-0.95, -0.055, 3.02), (1.0, 0.012, 0.12), round=0.004)
    for k in range(6):
        h = rng.uniform(0.25, 0.95)
        m.box([MUSTARD, TERRACOTTA, WHITE][k % 3], (-1.25 + k * 0.24, -0.055, 1.75 + h / 2), (0.16, 0.012, h), round=0.004)
    m.rod(WHITE, (0.85, -0.05, 2.3), (0.85, -0.062, 2.3), 0.5, segments=40)
    m.rod(SCREEN, (0.85, -0.058, 2.3), (0.85, -0.066, 2.3), 0.3, segments=40)
    for z in (2.95, 2.75):
        m.box(WHITE, (0.9, -0.055, z + 0.15), (0.8, 0.012, 0.05), round=0.004)


@model
def neon_sign(m):
    m.box(COCOA, (0, 0.0, 3.0), (2.6, 0.04, 1.1), round=0.02)
    points = [(-1.0, 2.75), (-0.75, 3.25), (-0.5, 2.75), (-0.25, 3.25), (0.0, 2.75), (0.25, 3.25), (0.5, 2.75), (0.75, 3.25), (1.0, 2.75)]
    for a, b in zip(points, points[1:]):
        m.rod(NEON, (a[0], -0.05, a[1]), (b[0], -0.05, b[1]), 0.028, segments=10)
        m.ball(NEON, (b[0], -0.05, b[1]), 0.028, detail=1)
    m.ball(NEON, (points[0][0], -0.05, points[0][1]), 0.028, detail=1)


@model
def desk_single(m):
    rng = random.Random(2)
    desk(m, (0, 0, 0), 0.0, rng)
    chair(m, (0.05, -0.62, 0), math.pi + 0.25, BLUE)


@model
def desk_pod(m):
    rng = random.Random(14)
    seats = [SAND, SAND, BLUE, TERRACOTTA]
    k = 0
    for x in (-0.82, 0.82):
        for y, turn in ((-0.44, 0.0), (0.44, math.pi)):
            desk(m, (x, y, 0), turn, rng)
            chair(m, (x + rng.uniform(-0.12, 0.12), y + (-0.72 if y < 0 else 0.72), 0), turn + math.pi + rng.uniform(-0.5, 0.5), seats[k])
            k += 1
    m.box(BLUE, (0, 0, 1.0), (3.2, 0.05, 0.46), round=0.02)
    for x in (-1.5, 1.5):
        m.box(COCOA, (x, 0, 0.8), (0.03, 0.09, 0.1), round=0.01)


@model
def desk_pod_six(m):
    rng = random.Random(15)
    seats = [SAND, MUSTARD, SAND, ROSE, SAND, BLUE]
    k = 0
    for x in (-1.64, 0.0, 1.64):
        for y, turn in ((-0.44, 0.0), (0.44, math.pi)):
            desk(m, (x, y, 0), turn, rng)
            chair(m, (x + rng.uniform(-0.12, 0.12), y + (-0.72 if y < 0 else 0.72), 0), turn + math.pi + rng.uniform(-0.5, 0.5), seats[k])
            k += 1
    m.box(TERRACOTTA, (0, 0, 1.0), (4.84, 0.05, 0.46), round=0.02)
    for x in (-2.3, 0.0, 2.3):
        m.box(COCOA, (x, 0, 0.8), (0.03, 0.09, 0.1), round=0.01)


@model
def desk_row(m):
    rng = random.Random(21)
    seats = [SAND, MUSTARD, SAND]
    for k, x in enumerate((-1.64, 0.0, 1.64)):
        desk(m, (x, 0, 0), 0.0, rng)
        chair(m, (x + rng.uniform(-0.1, 0.1), -0.66, 0), math.pi + rng.uniform(-0.45, 0.45), seats[k])


@model
def desk_standing(m):
    m.box(CREAM, (0, 0, 1.1), (1.4, 0.7, 0.05), round=0.02)
    for side in (-1, 1):
        m.box(STEEL, (side * 0.55, 0, 0.54), (0.07, 0.09, 1.08), round=0.02)
        m.box(STEEL, (side * 0.55, 0, 0.025), (0.09, 0.66, 0.05), round=0.02)
    m.box(STEEL, (0, 0.05, 1.03), (1.1, 0.06, 0.05), round=0.015)
    laptop(m, (-0.1, 0.0, 1.126), 0.1)
    mug(m, (0.42, -0.12, 1.126), MUSTARD)
    m.box(COCOA, (0.0, -0.75, 0.02), (0.7, 0.5, 0.04), round=0.018)


@model
def office_chair(m):
    chair(m, (0, 0, 0), 0.0, SAND)


@model
def meeting_table(m):
    rng = random.Random(4)
    m.box(TAN, (0, 0, 0.72), (2.5, 1.3, 0.06), round=0.02)
    for side in (-1, 1):
        m.disc(TAN, (side * 1.25, 0, 0.69), 0.65, 0.06, segments=40, round=0.02)
        m.disc(SAND, (side * 0.95, 0, 0.0), 0.36, 0.05, segments=32)
        m.disc(SAND, (side * 0.95, 0, 0.04), 0.1, 0.66, round=0.0)
    seats = [SAND, SAND, BLUE, SAND, TERRACOTTA, SAND, SAND, MUSTARD]
    k = 0
    for y, turn in ((-1.0, math.pi), (1.0, 0.0)):
        for x in (-1.1, 0.0, 1.1):
            chair(m, (x + rng.uniform(-0.08, 0.08), y + rng.uniform(-0.08, 0.08), 0), turn + rng.uniform(-0.3, 0.3), seats[k])
            k += 1
    for x, turn in ((-2.25, math.pi / 2), (2.25, -math.pi / 2)):
        chair(m, (x, rng.uniform(-0.05, 0.05), 0), turn + rng.uniform(-0.25, 0.25), seats[k])
        k += 1
    laptop(m, (-1.05, -0.3, 0.752), 0.1)
    laptop(m, (0.2, 0.32, 0.752), math.pi - 0.15)
    laptop(m, (1.2, -0.3, 0.752), -0.1)
    m.disc(COCOA, (0.0, 0.0, 0.752), 0.12, 0.035, segments=20)
    mug(m, (-0.5, 0.25, 0.752), WHITE)
    mug(m, (0.7, -0.05, 0.752), TERRACOTTA)
    m.box(WHITE, (-0.3, -0.3, 0.756), (0.21, 0.29, 0.006), 0.3, 0.0)


@model
def sofa(m, width=2.2, pillows=(TERRACOTTA, MUSTARD)):
    for x in (-1, 1):
        for y in (-1, 1):
            m.disc(COCOA, (x * (width / 2 - 0.12), y * 0.33, 0), 0.035, 0.1, round=0.0, segments=12)
    m.box(SAND, (0, 0, 0.27), (width, 0.92, 0.34), round=0.07)
    m.box(SAND, (0, 0.34, 0.63), (width, 0.24, 0.5), round=0.09)
    for side in (-1, 1):
        m.box(SAND, (side * (width / 2 - 0.12), -0.02, 0.52), (0.24, 0.88, 0.3), round=0.09)
    seats = max(1, round((width - 0.48) / 0.85))
    span = (width - 0.5) / seats
    for k in range(seats):
        m.box(CREAM, (-(width - 0.5) / 2 + span * (k + 0.5), -0.1, 0.5), (span - 0.03, 0.66, 0.16), round=0.06)
    for k, mat in enumerate(pillows):
        side = -1 if k == 0 else 1
        m.box(mat, (side * (width / 2 - 0.42), 0.12, 0.74), (0.4, 0.14, 0.36), side * 0.25, 0.06, ('X', -0.3))


@model
def armchair(m):
    sofa(m, 1.05, (BLUE,))


@model
def coffee_table(m):
    rng = random.Random(6)
    m.disc(TAN, (0, 0, 0.34), 0.55, 0.05, segments=40, round=0.018)
    for k in range(3):
        a = math.tau * k / 3 + 0.4
        m.rod(COCOA, (math.cos(a) * 0.36, math.sin(a) * 0.36, 0.35), (math.cos(a) * 0.44, math.sin(a) * 0.44, 0.0), 0.025, 0.018, 12)
    books(m, (-0.15, 0.1, 0.39), rng, 3, 0.3)
    mug(m, (0.22, -0.12, 0.39), WHITE)
    small_plant(m, (0.12, 0.25, 0.39), rng, TERRACOTTA)


@model
def rug(m):
    m.disc(SAND, (0, 0, 0), 1.8, 0.03, segments=64, round=0.012)
    m.disc(CREAM, (0, 0, 0), 1.5, 0.036, segments=64, round=0.012)
    m.disc(ROSE, (0, 0, 0), 1.08, 0.042, segments=64, round=0.012)
    m.disc(CREAM, (0, 0, 0), 0.72, 0.048, segments=64, round=0.012)


@model
def rug_large(m):
    m.box(SAND, (0, 0, 0.015), (5.0, 3.4, 0.03), round=0.012)
    m.box(CREAM, (0, 0, 0.018), (4.6, 3.0, 0.036), round=0.012)
    m.box(BLUE, (0, 0, 0.021), (4.1, 2.5, 0.042), round=0.012)
    m.box(CREAM, (0, 0, 0.024), (3.5, 1.9, 0.048), round=0.012)


@model
def bookshelf(m):
    rng = random.Random(12)
    for side in (-1, 1):
        m.box(TAN, (side * 0.98, 0, 1.1), (0.045, 0.38, 2.2), round=0.015)
    m.box(TAN, (0, 0.18, 1.1), (1.94, 0.02, 2.2), round=0.0)
    shelves = (0.06, 0.5, 0.94, 1.38, 1.82, 2.18)
    for z in shelves:
        m.box(TAN, (0, 0, z), (1.96, 0.38, 0.045), round=0.012)
    for row, z in enumerate(shelves[:-1]):
        x = -0.93
        while x < 0.9:
            pick = rng.random()
            if pick < 0.1 and x < 0.6:
                small_plant(m, (x + 0.12, 0.0, z + 0.024), rng, rng.choice([CREAM, TERRACOTTA]))
                x += 0.28
            elif pick < 0.2 and x < 0.55:
                m.box(rng.choice([CREAM, SAND, WHITE]), (x + 0.17, -0.02, z + 0.13), (0.3, 0.26, 0.21), round=0.02)
                x += 0.36
            elif pick < 0.3:
                x += rng.uniform(0.08, 0.2)
            else:
                w = rng.uniform(0.03, 0.07)
                h = rng.uniform(0.22, 0.34)
                lean = rng.uniform(-0.12, 0.12) if rng.random() < 0.15 else 0.0
                m.box(rng.choice([CREAM, SAND, WHITE, CREAM, SAND] + ACCENTS), (x + w / 2, -0.03, z + 0.024 + h / 2), (w, rng.uniform(0.2, 0.25), h), round=0.008, tilt=('Y', lean))
                x += w + 0.005


@model
def cabinet(m):
    rng = random.Random(9)
    for x in (-0.8, 0.8):
        for y in (-0.17, 0.17):
            m.disc(COCOA, (x, y, 0), 0.025, 0.12, round=0.0, segments=12)
    m.box(CREAM, (0, 0, 0.47), (1.8, 0.48, 0.7), round=0.03)
    m.box(TAN, (0, 0, 0.835), (1.86, 0.52, 0.04), round=0.015)
    for x in (-0.6, 0.0, 0.6):
        m.box(SAND, (x, -0.235, 0.47), (0.56, 0.02, 0.62), round=0.012)
        m.box(COCOA, (x + 0.2, -0.255, 0.5), (0.02, 0.025, 0.2), round=0.008)
    small_plant(m, (-0.6, 0.02, 0.855), rng, TERRACOTTA)
    books(m, (0.05, 0.0, 0.855), rng, 4, 0.2)
    m.box(WHITE, (0.62, 0.0, 0.93), (0.36, 0.3, 0.15), round=0.03)
    m.box(COCOA, (0.62, -0.153, 0.93), (0.22, 0.01, 0.03), round=0.004)


@model
def whiteboard(m):
    rng = random.Random(17)
    for side in (-1, 1):
        m.box(STEEL, (side * 0.96, 0, 1.0), (0.045, 0.045, 1.9), round=0.015)
        m.box(STEEL, (side * 0.96, 0, 0.09), (0.05, 0.56, 0.05), round=0.018)
        for y in (-0.25, 0.25):
            m.rod(COCOA, (side * 0.96 - 0.02, y, 0.04), (side * 0.96 + 0.02, y, 0.04), 0.04, segments=14)
    m.box(STEEL, (0, 0, 1.3), (1.98, 0.05, 1.3), round=0.02)
    m.box(WHITE, (0, -0.025, 1.3), (1.88, 0.02, 1.2), round=0.006)
    m.box(STEEL, (0, -0.06, 0.68), (1.3, 0.07, 0.025), round=0.01)
    for k, mat in enumerate((TERRACOTTA, BLUE, COCOA)):
        m.rod(mat, (-0.3 + k * 0.17, -0.07, 0.705), (-0.18 + k * 0.17, -0.07, 0.705), 0.012, segments=8)
    for row in range(3):
        for col in range(4):
            if rng.random() < 0.8:
                m.box(rng.choice(ACCENTS), (-0.75 + col * 0.19 + rng.uniform(-0.02, 0.02), -0.04, 1.72 - row * 0.19 + rng.uniform(-0.02, 0.02)), (0.13, 0.008, 0.13), round=0.0, tilt=('Y', rng.uniform(-0.12, 0.12)))
    points = [(0.1, 1.1), (0.3, 1.35), (0.45, 1.25), (0.65, 1.6), (0.82, 1.5)]
    for a, b in zip(points, points[1:]):
        m.along(BLUE, (a[0], -0.038, a[1]), (b[0], -0.038, b[1]), (0.02, 0.008), 0.0)
    m.along(COCOA, (0.05, -0.038, 1.0), (0.05, -0.038, 1.75), (0.014, 0.008), 0.0)
    m.along(COCOA, (0.05, -0.038, 1.0), (0.88, -0.038, 1.0), (0.014, 0.008), 0.0)


@model
def screen(m):
    rng = random.Random(23)
    m.box(COCOA, (0, 0.1, 0.03), (1.3, 0.6, 0.06), round=0.025)
    m.box(COCOA, (0, 0.14, 0.8), (0.14, 0.08, 1.5), round=0.025)
    m.box(COCOA, (0, 0.06, 1.55), (2.5, 0.08, 1.45), round=0.025)
    m.box(SCREEN, (0, 0.02, 1.55), (2.4, 0.02, 1.35), round=0.006)
    m.box(WHITE, (-0.7, 0.005, 2.05), (0.8, 0.012, 0.1), round=0.004)
    for k in range(7):
        h = rng.uniform(0.2, 0.75)
        m.box([WHITE, MUSTARD, TERRACOTTA][k % 3], (-1.0 + k * 0.2, 0.005, 1.05 + h / 2), (0.13, 0.012, h), round=0.004)
    for k in range(3):
        m.box(WHITE, (0.75, 0.005, 1.9 - k * 0.3), (0.7, 0.012, 0.16), round=0.004)
        m.box([MUSTARD, TERRACOTTA, WHITE][k], (0.48, 0.0, 1.9 - k * 0.3), (0.1, 0.012, 0.1), round=0.004)


@model
def kitchen(m):
    rng = random.Random(31)
    m.box(SAND, (-0.4, 0, 0.46), (3.0, 0.62, 0.84), round=0.025)
    m.box(COCOA, (-0.4, -0.02, 0.03), (2.96, 0.54, 0.06), round=0.0)
    m.box(WHITE, (-0.4, -0.01, 0.905), (3.08, 0.68, 0.05), round=0.02)
    for k in range(5):
        x = -1.6 + k * 0.6
        m.box(CREAM, (x, -0.305, 0.47), (0.56, 0.02, 0.74), round=0.012)
        m.box(COCOA, (x + 0.2, -0.325, 0.72), (0.02, 0.025, 0.16), round=0.008)
    m.box(STEEL, (-1.1, -0.02, 0.928), (0.52, 0.4, 0.012), round=0.004)
    m.box(COCOA, (-1.1, -0.02, 0.932), (0.44, 0.32, 0.012), round=0.004)
    m.rod(STEEL, (-1.1, 0.22, 0.93), (-1.1, 0.22, 1.16), 0.016, segments=10)
    m.rod(STEEL, (-1.1, 0.22, 1.16), (-1.1, 0.06, 1.14), 0.014, segments=10)
    m.ball(STEEL, (-1.1, 0.22, 1.16), 0.018, detail=1)
    m.box(COCOA, (-0.25, 0.08, 1.11), (0.3, 0.36, 0.36), round=0.03)
    m.box(STEEL, (-0.25, -0.1, 1.2), (0.2, 0.03, 0.1), round=0.01)
    m.box(STEEL, (-0.25, -0.06, 0.945), (0.26, 0.22, 0.03), round=0.01)
    mug(m, (-0.25, -0.06, 0.96), WHITE)
    for k in range(4):
        mug(m, (0.2 + k * 0.13, 0.16, 0.93), ACCENTS[k])
    m.disc(TAN, (0.75, -0.02, 0.93), 0.17, 0.07, 0.2, segments=24)
    for k in range(5):
        a = math.tau * k / 5
        m.ball([MUSTARD, TERRACOTTA, MUSTARD, LEAF_LIGHT, TERRACOTTA][k], (0.75 + math.cos(a) * 0.08, -0.02 + math.sin(a) * 0.08, 1.02), 0.055, detail=2)
    m.box(CREAM, (1.52, 0.0, 0.98), (0.78, 0.7, 1.9), round=0.04)
    m.box(COCOA, (1.52, -0.01, 0.03), (0.72, 0.62, 0.06), round=0.0)
    m.box(SAND, (1.52, -0.352, 1.25), (0.74, 0.012, 0.012), round=0.0)
    for z in (0.95, 1.5):
        m.box(STEEL, (1.25, -0.37, z), (0.025, 0.035, 0.34), round=0.01)
    for x in (-1.3, -0.4):
        m.disc(COCOA, (x, -0.72, 0.0), 0.19, 0.03, segments=24)
        m.disc(STEEL, (x, -0.72, 0.03), 0.025, 0.66, round=0.0, segments=12)
        m.disc(rng.choice([TAN, TERRACOTTA]), (x, -0.72, 0.68), 0.18, 0.06, segments=24, round=0.02)


@model
def cafe_table(m):
    m.disc(COCOA, (0, 0, 0), 0.28, 0.035, segments=28)
    m.disc(STEEL, (0, 0, 0.03), 0.035, 1.0, round=0.0, segments=14)
    m.disc(TAN, (0, 0, 1.03), 0.42, 0.045, segments=36, round=0.018)
    mug(m, (0.12, -0.1, 1.075), WHITE)
    mug(m, (-0.16, 0.1, 1.075), TERRACOTTA)
    for k, mat in enumerate((SAND, BLUE, SAND)):
        a = math.tau * k / 3 + 0.5
        x, y = math.cos(a) * 0.75, math.sin(a) * 0.75
        m.disc(COCOA, (x, y, 0), 0.19, 0.03, segments=24)
        m.disc(STEEL, (x, y, 0.03), 0.024, 0.68, round=0.0, segments=12)
        m.disc(STEEL, (x, y, 0.3), 0.13, 0.02, segments=20, round=0.0)
        m.disc(mat, (x, y, 0.7), 0.18, 0.07, segments=24, round=0.028)


@model
def server_rack(m):
    rng = random.Random(41)
    m.box(COCOA, (0, 0, 1.04), (0.72, 1.0, 2.04), round=0.03)
    m.box(COCOA, (0, 0, 0.02), (0.66, 0.94, 0.04), round=0.0)
    for k in range(11):
        z = 0.2 + k * 0.165
        m.box(STEEL, (0, -0.5, z), (0.6, 0.02, 0.135), round=0.008)
        for j in range(rng.randint(2, 5)):
            m.box(rng.choice([LED_GREEN, LED_GREEN, LED_BLUE]), (-0.24 + j * 0.05, -0.513, z + 0.03), (0.026, 0.008, 0.026), round=0.0)
        m.box(COCOA, (0.14, -0.512, z - 0.01), (0.22, 0.006, 0.05), round=0.0)
    m.box(LED_BLUE, (0, -0.505, 2.01), (0.5, 0.012, 0.02), round=0.0)
    for x in (-0.2, 0.0, 0.2):
        m.box(STEEL, (x, 0, 2.065), (0.12, 0.7, 0.012), round=0.004)


@model
def plant(m):
    rng = random.Random(52)
    pot(m, (0, 0, 0), TERRACOTTA, 0.24, 0.42)
    foliage(m, (0, 0, 0.55), rng, 0.42, 11, 0.0, 0.55)


@model
def plant_tall(m):
    rng = random.Random(53)
    pot(m, (0, 0, 0), CREAM, 0.27, 0.5)
    m.rod(TAN, (0, 0, 0.45), (0.05, 0.03, 1.55), 0.035, 0.025, 10)
    for k in range(9):
        a = math.tau * k / 9 * 2.4 + rng.uniform(-0.2, 0.2)
        z = 1.0 + k * 0.13
        reach = rng.uniform(0.34, 0.5)
        droop = rng.uniform(0.25, 0.7)
        m.ball(LEAF if k % 2 else LEAF_LIGHT, (math.cos(a) * reach * 0.8, math.sin(a) * reach * 0.8, z), reach, (1.0, 0.5, 0.09), a, ('Y', droop))
    m.ball(LEAF_LIGHT, (0.05, 0.03, 2.05), 0.3, (0.5, 0.45, 1.0), detail=2)


@model
def planter(m):
    rng = random.Random(54)
    for x in (-1.0, 1.0):
        m.box(COCOA, (x, 0, 0.04), (0.08, 0.4, 0.08), round=0.02)
    m.box(CREAM, (0, 0, 0.33), (2.4, 0.5, 0.52), round=0.04)
    m.box(SOIL, (0, 0, 0.59), (2.28, 0.4, 0.02), round=0.0)
    for k in range(7):
        foliage(m, (-0.96 + k * 0.32, rng.uniform(-0.04, 0.04), 0.6), rng, 0.2, 4, 0.02, 0.22)


@model
def floor_lamp(m):
    m.disc(COCOA, (0, 0, 0), 0.2, 0.035, segments=28)
    m.disc(COCOA, (0, 0, 0.03), 0.016, 1.5, round=0.0, segments=10)
    m.disc(LAMP, (0, 0, 1.45), 0.25, 0.34, 0.17, segments=32, round=0.012)
    m.disc(COCOA, (0, 0, 1.79), 0.03, 0.03, segments=12, round=0.0)


@model
def slide(m):
    for x in (-0.8, 0.8):
        for y in (0.0, 1.6):
            m.box(SAND, (x, y, 1.6), (0.14, 0.14, 3.2), round=0.035)
    m.box(TAN, (0, 0.8, 2.2), (1.74, 1.74, 0.12), round=0.03)
    for x in (-0.8, 0.8):
        m.box(SAND, (x, 0.8, 3.16), (0.1, 1.74, 0.08), round=0.03)
        m.box(GLASS, (x, 0.8, 2.72), (0.03, 1.46, 0.8), round=0.0)
    m.box(SAND, (0, 1.6, 3.16), (1.7, 0.1, 0.08), round=0.03)
    for k in range(10):
        m.box(TAN, (0.0, 1.78 + k * 0.26, 2.08 - k * 0.22), (0.9, 0.3, 0.06), round=0.02)
    for side in (-1, 1):
        m.along(SAND, (side * 0.48, 1.68, 2.2), (side * 0.48, 4.26, 0.02), (0.06, 0.16), 0.02)
        m.along(SAND, (side * 0.48, 1.68, 3.1), (side * 0.48, 4.26, 0.92), (0.05, 0.05), 0.02)
        for k in (2, 5, 8):
            m.box(SAND, (side * 0.48, 1.78 + k * 0.26, 2.55 - k * 0.22), (0.04, 0.04, 0.9), round=0.015)
    path = []
    for k in range(13):
        t = k / 12
        ease = t * t * (3 - 2 * t)
        path.append(Vector((math.sin(t * math.pi) * 0.9, -0.05 - t * 4.6, 2.28 - 2.1 * (0.35 * t + 0.65 * ease))))
    for a, b in zip(path, path[1:]):
        side = (b - a).cross(Vector((0, 0, 1))).normalized()
        m.along(MUSTARD, a, b + (b - a) * 0.04, (0.86, 0.07), 0.025)
        for s in (-1, 1):
            lift = Vector((0, 0, 0.14))
            m.along(MUSTARD, a + side * s * 0.43 + lift, b + (b - a) * 0.04 + side * s * 0.43 + lift, (0.08, 0.3), 0.03)
    end = path[-1]
    m.box(MUSTARD, (end.x, end.y - 0.4, 0.16), (0.9, 0.9, 0.08), round=0.03)
    for s in (-1, 1):
        m.box(SAND, (end.x + s * 0.3, end.y - 0.4, 0.07), (0.1, 0.7, 0.14), round=0.03)
    m.box(SAND, (path[5].x, path[5].y, path[5].z / 2 - 0.05), (0.14, 0.14, path[5].z - 0.05), round=0.035)


@model
def ping_pong(m):
    m.box(BLUE, (0, 0, 0.75), (2.74, 1.525, 0.05), round=0.015)
    for y in (-0.75, 0.75):
        m.box(WHITE, (0, y, 0.777), (2.74, 0.03, 0.004), round=0.0)
    for x in (-1.355, 1.355):
        m.box(WHITE, (x, 0, 0.777), (0.03, 1.525, 0.004), round=0.0)
    m.box(WHITE, (0, 0, 0.777), (2.74, 0.012, 0.004), round=0.0)
    m.box(WHITE, (0, 0, 0.86), (0.012, 1.66, 0.15), round=0.0)
    for y in (-0.83, 0.83):
        m.box(COCOA, (0, y, 0.84), (0.03, 0.03, 0.2), round=0.01)
    for x in (-1.0, 1.0):
        m.box(STEEL, (x, 0, 0.7), (0.05, 1.2, 0.05), round=0.015)
        for y in (-0.55, 0.55):
            m.box(STEEL, (x, y, 0.36), (0.05, 0.05, 0.7), round=0.015)
        m.box(STEEL, (x, 0, 0.03), (0.05, 1.3, 0.05), round=0.015)
    for x, y, turn, mat in ((-0.9, -0.3, 0.6, TERRACOTTA), (0.8, 0.35, -2.2, COCOA)):
        with m.at((x, y, 0.778), turn):
            m.disc(mat, (0, 0, 0), 0.08, 0.014, segments=20, round=0.004)
            m.box(TAN, (0.12, 0, 0.008), (0.11, 0.028, 0.02), round=0.008)
    m.ball(WHITE, (0.3, -0.2, 0.798), 0.02, detail=2)


@model
def beanbag(m):
    m.ball(TERRACOTTA, (0, 0, 0.3), 0.55, (1.0, 1.0, 0.56), detail=3)
    m.ball(TERRACOTTA, (0, 0.16, 0.52), 0.4, (1.0, 0.8, 0.75), detail=3)
    m.ball(TERRACOTTA, (0, 0.3, 0.72), 0.06, detail=1)


@model
def reception(m):
    rng = random.Random(61)
    count = 9
    for k in range(count):
        a = math.radians(-70 + 140 * k / (count - 1)) - math.pi / 2
        with m.at((math.cos(a) * 1.9, math.sin(a) * 1.9 + 1.9, 0), a + math.pi / 2):
            m.box(CREAM, (0, 0, 0.53), (0.56, 0.5, 1.04), round=0.03)
            m.box(SAND, (0, -0.255, 0.3), (0.56, 0.02, 0.46), round=0.012)
            m.box(TAN, (0, 0.02, 1.07), (0.6, 0.6, 0.05), round=0.02)
            m.box(TAN, (0, 0.32, 0.76), (0.6, 0.44, 0.04), round=0.015)
    m.rod(MUSTARD, (0, -0.02, 0.62), (0, -0.06, 0.62), 0.24, segments=32, round=0.01)
    m.rod(WHITE, (0, -0.055, 0.62), (0, -0.075, 0.62), 0.12, segments=24)
    monitor(m, (-0.35, 0.3, 0.78), -0.2)
    laptop(m, (0.5, 0.42, 0.78), 0.35)
    small_plant(m, (1.25, 0.82, 1.095), rng, TERRACOTTA)
    mug(m, (0.9, 0.5, 0.78), BLUE)
    chair(m, (0.0, 1.05, 0), 0.2, BLUE)


@model
def phone_booth(m):
    m.box(SAND, (0, 0, 0.05), (1.3, 1.3, 0.1), round=0.03)
    m.box(CREAM, (0, 0.6, 1.2), (1.3, 0.1, 2.2), round=0.03)
    for side in (-1, 1):
        m.box(CREAM, (side * 0.6, 0, 1.2), (0.1, 1.3, 2.2), round=0.03)
        m.box(GLASS, (side * 0.62, -0.1, 1.45), (0.08, 0.7, 1.2), round=0.01)
    m.box(SAND, (0, 0, 2.35), (1.38, 1.38, 0.12), round=0.04)
    m.box(LAMP, (0, 0, 2.28), (0.7, 0.7, 0.03), round=0.01)
    m.box(GLASS, (0.14, -0.62, 1.2), (0.82, 0.04, 2.08), round=0.01)
    m.box(CREAM, (-0.42, -0.62, 1.2), (0.26, 0.08, 2.2), round=0.03)
    m.box(STEEL, (-0.2, -0.66, 1.1), (0.03, 0.05, 0.4), round=0.012)
    m.box(BLUE, (0, 0.5, 1.3), (1.08, 0.06, 1.7), round=0.03)
    m.box(TERRACOTTA, (0, 0.33, 0.5), (1.06, 0.42, 0.14), round=0.05)
    m.box(SAND, (0, 0.33, 0.27), (1.06, 0.4, 0.34), round=0.02)
    m.box(TAN, (0.34, -0.1, 0.78), (0.4, 0.5, 0.04), round=0.015)
    laptop(m, (0.34, -0.1, 0.8), -1.2)


@model
def water_cooler(m):
    m.box(WHITE, (0, 0, 0.5), (0.36, 0.36, 1.0), round=0.04)
    m.box(STEEL, (0, -0.19, 0.62), (0.26, 0.03, 0.22), round=0.012)
    for x, mat in ((-0.06, BLUE), (0.06, TERRACOTTA)):
        m.box(mat, (x, -0.21, 0.7), (0.035, 0.04, 0.05), round=0.012)
    m.box(STEEL, (0, -0.2, 0.5), (0.24, 0.1, 0.02), round=0.008)
    m.disc(GLASS, (0, 0, 1.06), 0.15, 0.36, segments=24, round=0.04)
    m.disc(GLASS, (0, 0, 1.0), 0.06, 0.08, segments=16, round=0.0)
    m.disc(WHITE, (0.17, -0.3, 0.0), 0.05, 0.3, 0.07, segments=16)


@model
def printer(m):
    m.box(SAND, (0, 0, 0.3), (0.7, 0.56, 0.6), round=0.03)
    m.box(COCOA, (0, -0.285, 0.3), (0.5, 0.012, 0.012), round=0.0)
    m.box(WHITE, (0, 0, 0.8), (0.6, 0.5, 0.4), round=0.04)
    m.box(COCOA, (0, 0.02, 1.01), (0.5, 0.36, 0.03), round=0.01)
    m.box(COCOA, (0, -0.25, 0.7), (0.44, 0.02, 0.06), round=0.008)
    m.box(WHITE, (0, -0.36, 0.66), (0.4, 0.24, 0.015), round=0.006, tilt=('X', 0.12))
    m.box(SCREEN, (0.18, -0.2, 0.985), (0.14, 0.1, 0.02), round=0.006, tilt=('X', 0.5))
    m.box(WHITE, (-0.05, 0.0, 1.03), (0.21, 0.29, 0.02), 0.1, 0.0)


@model
def bleachers(m):
    rng = random.Random(71)
    for k in range(3):
        depth = 2.7 - k * 0.9
        m.box(TAN, (0, 1.35 - depth / 2, 0.225 + k * 0.45), (4.4, depth, 0.45), round=0.03)
        m.box(SAND, (0, 1.35 - depth - 0.0, 0.225 + k * 0.45), (4.36, 0.03, 0.39), round=0.01)
    for k in range(3):
        for j in range(5):
            if rng.random() < 0.7:
                m.box(rng.choice(ACCENTS + [CREAM, CREAM]), (-1.7 + j * 0.85 + rng.uniform(-0.1, 0.1), -0.9 + k * 0.9 + rng.uniform(-0.05, 0.05), 0.49 + k * 0.45), (0.5, 0.5, 0.09), rng.uniform(-0.2, 0.2), 0.035)
    laptop(m, (0.3, -0.1, 0.9), 0.4)
    mug(m, (-1.3, -1.15, 0.45), WHITE)


@model
def mezzanine(m):
    rng = random.Random(81)
    m.box(CREAM, (0, 0, 2.95), (8.0, 4.6, 0.3), round=0.04)
    m.box(TAN, (0, 0, 3.115), (7.9, 4.5, 0.03), round=0.01)
    for x in (-3.7, 0.0, 3.7):
        for y in (-2.0, 2.0):
            m.box(SAND, (x, y, 1.4), (0.26, 0.26, 2.8), round=0.05)
    rails = [((-3.94, -2.24), (2.75, -2.24)), ((-3.94, -2.24), (-3.94, 2.24)), ((3.94, -2.24), (3.94, 2.24)), ((-3.94, 2.24), (3.94, 2.24))]
    for a, b in rails:
        a3, b3 = Vector((a[0], a[1], 4.16)), Vector((b[0], b[1], 4.16))
        m.along(SAND, a3, b3, (0.07, 0.06), 0.02)
        steps = max(1, round((b3 - a3).length / 1.3))
        for k in range(steps + 1):
            p = a3.lerp(b3, k / steps)
            m.box(SAND, (p.x, p.y, 3.64), (0.05, 0.05, 1.04), round=0.015)
        m.along(GLASS, Vector((a[0], a[1], 3.62)), Vector((b[0], b[1], 3.62)), (0.025, 0.82), 0.0)
    rise = 3.13 / 16
    for k in range(16):
        m.box(TAN, (3.35, -2.52 - k * 0.29, 3.13 - (k + 0.5) * rise), (1.15, 0.31, 0.06), round=0.02)
    for side in (2.75, 3.95):
        m.along(SAND, (side, -2.4, 2.98), (side, -7.1, -0.08), (0.07, 0.24), 0.02)
        m.along(SAND, (side, -2.3, 4.12), (side, -7.0, 1.05), (0.06, 0.06), 0.02)
        for k in (0, 5, 10, 15):
            y = -2.52 - k * 0.29
            m.box(SAND, (side, y, 3.13 - (k + 0.5) * rise + 0.52), (0.045, 0.045, 1.0), round=0.015)
    desk(m, (-2.7, 1.2, 3.13), 0.0, rng)
    chair(m, (-2.65, 0.55, 3.13), math.pi + 0.3, TERRACOTTA)
    desk(m, (-0.9, 1.2, 3.13), 0.0, rng)
    chair(m, (-0.95, 0.5, 3.13), math.pi - 0.4, SAND)
    with m.at((1.9, 1.35, 3.13), 0.0):
        sofa(m, 2.2, (BLUE, MUSTARD))
    with m.at((1.9, 0.1, 3.13)):
        m.disc(TAN, (0, 0, 0.3), 0.42, 0.045, segments=32, round=0.018)
        m.disc(COCOA, (0, 0, 0), 0.05, 0.3, round=0.0, segments=12)
        books(m, (0.05, 0.0, 0.345), rng, 2, 0.5)
    with m.at((-3.5, -1.7, 3.13)):
        pot(m, (0, 0, 0), TERRACOTTA, 0.22, 0.4)
        foliage(m, (0, 0, 0.5), rng, 0.38, 9, 0.0, 0.5)
    with m.at((0.4, -1.75, 3.13)):
        for x in (-0.5, 0.5):
            m.box(COCOA, (x, 0, 0.04), (0.08, 0.36, 0.08), round=0.02)
        m.box(CREAM, (0, 0, 0.3), (1.6, 0.44, 0.46), round=0.04)
        for k in range(5):
            foliage(m, (-0.64 + k * 0.32, 0.0, 0.56), rng, 0.2, 4, 0.02, 0.28)


for name, build in MODELS.items():
    if ONLY and name not in ONLY:
        continue
    made = Model(name)
    build(made)
    made.save()
print('CLAY DONE', flush=True)

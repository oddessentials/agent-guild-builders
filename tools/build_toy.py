import math, random, sys
from pathlib import Path

from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import solids
from solids import Model, material

solids.use(Path(sys.argv[sys.argv.index('--') + 1]).resolve())
ONLY = set(sys.argv[sys.argv.index('--') + 2:])


def plastic(name, rgb, glow=0.0, rough=0.45):
    return material('toy_' + name, rgb, rough, glow)


WHITE = plastic('white', (0.97, 0.97, 0.98))
GREY = plastic('grey', (0.78, 0.8, 0.85))
DARK = plastic('dark', (0.2, 0.23, 0.33))
RED = plastic('red', (0.95, 0.28, 0.26))
ORANGE = plastic('orange', (1.0, 0.6, 0.2))
YELLOW = plastic('yellow', (1.0, 0.83, 0.2))
GREEN = plastic('green', (0.3, 0.78, 0.42))
TEAL = plastic('teal', (0.15, 0.72, 0.72))
BLUE = plastic('blue', (0.22, 0.5, 0.95))
PURPLE = plastic('purple', (0.55, 0.38, 0.92))
PINK = plastic('pink', (1.0, 0.52, 0.72))
WOOD = plastic('wood', (0.86, 0.66, 0.42))
LEAF = plastic('leaf', (0.28, 0.74, 0.36))
LEAF_LIGHT = plastic('leaf_light', (0.5, 0.86, 0.4))
GLASS = plastic('glass', (0.7, 0.88, 0.98), rough=0.15)
WATER = plastic('water', (0.3, 0.7, 1.0), rough=0.1)
SCREEN = plastic('screen', (0.4, 0.75, 1.0), 0.8, 0.3)
LAMP = plastic('lamp', (1.0, 0.88, 0.6), 1.2, 0.5)
LED = plastic('led', (0.4, 1.0, 0.5), 1.0, 0.4)
BRIGHT = [RED, ORANGE, YELLOW, GREEN, TEAL, BLUE, PURPLE, PINK]
CARPETS = {'white': (0.95, 0.95, 0.97), 'purple': (0.56, 0.42, 0.95), 'teal': (0.16, 0.72, 0.68), 'coral': (1.0, 0.47, 0.42),
           'yellow': (1.0, 0.82, 0.3), 'blue': (0.3, 0.55, 1.0), 'green': (0.36, 0.8, 0.44)}
MODELS = {}


def model(build):
    MODELS['toy_' + build.__name__] = build
    return build


# Every piece is authored facing -y, and most stand no taller than a metre so they fit anywhere round the Yard.

def chair(m, at, turn=0.0, colour=BLUE):
    with m.at(at, turn):
        m.disc(DARK, (0, 0, 0), 0.24, 0.05, segments=20)
        m.disc(GREY, (0, 0, 0.04), 0.04, 0.34, round=0.0, segments=12)
        m.box(colour, (0, 0, 0.42), (0.5, 0.48, 0.12), round=0.055)
        m.box(colour, (0, 0.23, 0.68), (0.48, 0.12, 0.44), round=0.055)


def stool(m, at, colour):
    m.disc(GREY, (at[0], at[1], at[2]), 0.05, 0.4, round=0.0, segments=12)
    m.disc(DARK, at, 0.2, 0.04, segments=20)
    m.disc(colour, (at[0], at[1], at[2] + 0.4), 0.22, 0.1, segments=24, round=0.04)


def monitor(m, at, turn=0.0):
    with m.at(at, turn):
        m.box(DARK, (0, 0.04, 0.02), (0.2, 0.14, 0.04), round=0.015)
        m.box(DARK, (0, 0.05, 0.07), (0.06, 0.05, 0.1), round=0.015)
        m.box(DARK, (0, 0.04, 0.2), (0.46, 0.06, 0.3), round=0.025)
        m.box(SCREEN, (0, 0.005, 0.2), (0.4, 0.02, 0.24), round=0.008)


def desk(m, at, turn, rng, seat, legs=GREY):
    with m.at(at, turn):
        m.box(WHITE, (0, 0, 0.58), (1.4, 0.72, 0.09), round=0.04)
        for x in (-0.6, 0.6):
            for y in (-0.27, 0.27):
                m.disc(legs, (x, y, 0), 0.045, 0.56, round=0.0, segments=12)
        monitor(m, (rng.uniform(-0.1, 0.1), 0.12, 0.625), rng.uniform(-0.1, 0.1))
        m.box(GREY, (0, -0.16, 0.64), (0.4, 0.13, 0.03), round=0.012)
        m.disc(rng.choice(BRIGHT), (0.5, -0.1, 0.625), 0.05, 0.1, segments=14, round=0.012)
        chair(m, (rng.uniform(-0.08, 0.08), -0.62, 0), math.pi + rng.uniform(-0.4, 0.4), seat)


def blob(m, at, radius, squash=0.85):
    m.ball(LEAF, at, radius, (1, 1, squash), detail=2)
    m.ball(LEAF_LIGHT, (at[0] + radius * 0.35, at[1] - radius * 0.3, at[2] + radius * 0.35), radius * 0.6, detail=2)


def pot(m, at, colour, radius=0.22, height=0.34):
    m.disc(colour, at, radius * 0.8, height, radius, round=0.03)
    m.disc(DARK, (at[0], at[1], at[2] + height - 0.02), radius * 0.86, 0.03, round=0.0)


def tile(name, rgb):
    def build(m):
        m.box(plastic('carpet_' + name, rgb, rough=0.9), (0, 0, 0.025), (4.0, 4.0, 0.05), round=0.0)
    build.__name__ = 'floor_' + name
    model(build)


for carpet, rgb in CARPETS.items():
    tile(carpet, rgb)


@model
def wall(m, length=4.0):
    m.box(WHITE, (0, 0, 0.44), (length, 0.24, 0.84), round=0.03)
    m.box(DARK, (0, 0, 0.87), (length, 0.3, 0.07), round=0.025)


@model
def wall_short(m):
    wall(m, 2.0)


@model
def wall_glass(m):
    m.box(WHITE, (0, 0, 0.12), (4.0, 0.24, 0.24), round=0.03)
    m.box(GLASS, (0, 0, 0.52), (3.9, 0.08, 0.64), round=0.0)
    for x in (-1.94, 0.0, 1.94):
        m.box(WHITE, (x, 0, 0.5), (0.12, 0.2, 0.7), round=0.03)
    m.box(DARK, (0, 0, 0.87), (4.0, 0.3, 0.07), round=0.025)


@model
def wall_post(m):
    m.box(WHITE, (0, 0, 0.46), (0.34, 0.34, 0.9), round=0.04)
    m.box(DARK, (0, 0, 0.93), (0.4, 0.4, 0.07), round=0.025)


@model
def desk_single(m):
    desk(m, (0, 0, 0), 0.0, random.Random(3), BLUE)


@model
def desk_pod(m):
    rng = random.Random(4)
    seats = [RED, YELLOW, GREEN, PURPLE]
    k = 0
    for x in (-0.74, 0.74):
        for y, turn in ((-0.4, 0.0), (0.4, math.pi)):
            desk(m, (x, y, 0), turn, rng, seats[k], BRIGHT[k + 2])
            k += 1
    m.box(TEAL, (0, 0, 0.78), (2.9, 0.07, 0.34), round=0.03)


@model
def desk_long(m):
    rng = random.Random(5)
    for k, x in enumerate((-1.5, 0.0, 1.5)):
        desk(m, (x, 0, 0), 0.0, rng, [ORANGE, TEAL, PINK][k], [BLUE, RED, GREEN][k])


@model
def drawing_table(m):
    m.box(WHITE, (0, 0.05, 0.72), (1.3, 0.9, 0.07), round=0.03, tilt=('X', 0.38))
    for x in (-0.55, 0.55):
        m.along(WOOD, (x, -0.3, 0), (x, 0.1, 0.62), (0.07, 0.07), 0.025)
        m.along(WOOD, (x, 0.42, 0), (x, 0.1, 0.62), (0.07, 0.07), 0.025)
    m.box(YELLOW, (-0.2, 0.02, 0.76), (0.5, 0.36, 0.02), round=0.0, tilt=('X', 0.38))
    m.box(PINK, (0.32, 0.12, 0.8), (0.3, 0.22, 0.02), round=0.0, tilt=('X', 0.38))
    m.disc(TEAL, (0.5, 0.36, 0.87), 0.06, 0.12, segments=14, round=0.012)
    stool(m, (0, -0.75, 0), RED)


@model
def meeting_table(m):
    rng = random.Random(6)
    m.disc(WHITE, (0, 0, 0.6), 1.5, 0.1, segments=48, round=0.04)
    m.disc(YELLOW, (0, 0, 0.66), 0.6, 0.05, segments=36, round=0.02)
    m.disc(GREY, (0, 0, 0), 0.5, 0.06, segments=32)
    m.disc(GREY, (0, 0, 0.05), 0.16, 0.56, round=0.0, segments=20)
    for k in range(6):
        a = math.tau * k / 6 + 0.2
        chair(m, (math.cos(a) * 1.95, math.sin(a) * 1.95, 0), a - math.pi / 2 + rng.uniform(-0.2, 0.2), BRIGHT[k])


@model
def whiteboard(m):
    for x in (-0.5, 0.5):
        m.along(WOOD, (x, 0.25, 0), (x * 0.9, 0.0, 0.96), (0.06, 0.06), 0.02)
    m.along(WOOD, (0, 0.45, 0), (0, 0.02, 0.9), (0.06, 0.06), 0.02)
    m.box(WHITE, (0, -0.04, 0.6), (1.2, 0.05, 0.72), round=0.025, tilt=('X', -0.24))
    for k, (x, z, colour) in enumerate(((-0.35, 0.74, RED), (0.0, 0.74, BLUE), (0.35, 0.74, YELLOW), (-0.2, 0.48, GREEN), (0.2, 0.48, PINK))):
        m.box(colour, (x, -0.075 + (z - 0.6) * 0.245, z), (0.22, 0.02, 0.16), round=0.006, tilt=('X', -0.24))


@model
def screen(m):
    m.box(WHITE, (0, 0.05, 0.14), (1.3, 0.42, 0.28), round=0.05)
    m.box(BRIGHT[4], (0, -0.17, 0.14), (1.1, 0.02, 0.16), round=0.006)
    m.box(DARK, (0, 0.05, 0.64), (1.3, 0.1, 0.7), round=0.04)
    m.box(SCREEN, (0, -0.005, 0.64), (1.2, 0.02, 0.6), round=0.01)
    for k, tall in enumerate((0.16, 0.3, 0.22, 0.4)):
        m.box([YELLOW, PINK, WHITE, GREEN][k], (-0.42 + k * 0.17, -0.02, 0.4 + tall / 2), (0.11, 0.02, tall), round=0.006)
    m.rod(WHITE, (0.32, -0.012, 0.66), (0.32, -0.03, 0.66), 0.17, segments=28)


def couch(m, width, colour, pillow):
    m.box(colour, (0, 0, 0.24), (width, 0.86, 0.36), round=0.1)
    m.box(colour, (0, 0.32, 0.56), (width, 0.26, 0.44), round=0.11)
    for side in (-1, 1):
        m.box(colour, (side * (width / 2 - 0.13), -0.03, 0.46), (0.26, 0.8, 0.28), round=0.1)
    m.box(pillow, (width / 2 - 0.5, 0.08, 0.6), (0.36, 0.16, 0.34), -0.25, 0.07, ('X', -0.3))
    for x in (-1, 1):
        for y in (-1, 1):
            m.disc(DARK, (x * (width / 2 - 0.14), y * 0.3, 0), 0.05, 0.08, round=0.0, segments=12)


@model
def sofa(m):
    couch(m, 2.1, PURPLE, YELLOW)


@model
def armchair(m):
    couch(m, 1.05, TEAL, PINK)


@model
def beanbag(m):
    m.ball(ORANGE, (0, 0, 0.3), 0.55, (1.0, 1.0, 0.58), detail=3)
    m.ball(ORANGE, (0, 0.15, 0.52), 0.4, (1.0, 0.8, 0.72), detail=3)


@model
def coffee_table(m):
    m.disc(WHITE, (0, 0, 0.32), 0.55, 0.08, segments=36, round=0.035)
    m.disc(GREY, (0, 0, 0), 0.3, 0.05, segments=24)
    m.disc(GREY, (0, 0, 0.04), 0.07, 0.3, round=0.0, segments=14)
    m.disc(RED, (0.18, -0.1, 0.4), 0.05, 0.1, segments=14, round=0.012)
    m.box(BLUE, (-0.15, 0.1, 0.42), (0.26, 0.2, 0.04), 0.3, 0.012)
    m.box(YELLOW, (-0.13, 0.09, 0.46), (0.24, 0.18, 0.04), -0.2, 0.012)


@model
def rug_round(m):
    for k, (radius, colour) in enumerate(((2.0, BLUE), (1.6, WHITE), (1.2, PINK), (0.8, WHITE), (0.4, YELLOW))):
        m.disc(colour, (0, 0, 0.05), radius, 0.02 + k * 0.006, segments=64, round=0.008)


@model
def kitchen(m):
    m.box(WHITE, (0, 0, 0.42), (3.0, 0.64, 0.8), round=0.05)
    m.box(WOOD, (0, -0.01, 0.84), (3.1, 0.7, 0.07), round=0.03)
    for k in range(5):
        m.box(BRIGHT[k + 1], (-1.2 + k * 0.6, -0.33, 0.44), (0.5, 0.03, 0.62), round=0.03)
    m.box(DARK, (-1.0, 0.05, 0.94), (0.3, 0.32, 0.12), round=0.04)
    m.disc(RED, (-1.0, -0.14, 0.88), 0.05, 0.1, segments=14, round=0.012)
    m.box(GREY, (0.0, 0.0, 0.885), (0.5, 0.38, 0.02), round=0.008)
    m.rod(GREY, (0.0, 0.2, 0.88), (0.0, 0.2, 1.0), 0.02, segments=10)
    m.disc(WOOD, (1.0, 0, 0.875), 0.16, 0.06, 0.2, segments=24)
    for k in range(4):
        a = math.tau * k / 4
        m.ball([ORANGE, RED, YELLOW, GREEN][k], (1.0 + math.cos(a) * 0.07, math.sin(a) * 0.07, 0.95), 0.055, detail=2)


@model
def cafe_table(m):
    m.disc(GREY, (0, 0, 0), 0.26, 0.05, segments=24)
    m.disc(GREY, (0, 0, 0.04), 0.05, 0.64, round=0.0, segments=12)
    m.disc(WHITE, (0, 0, 0.68), 0.45, 0.08, segments=36, round=0.035)
    m.disc(TEAL, (0.12, -0.1, 0.76), 0.05, 0.1, segments=14, round=0.012)
    for k, colour in enumerate((RED, YELLOW, BLUE)):
        a = math.tau * k / 3 + 0.5
        stool(m, (math.cos(a) * 0.78, math.sin(a) * 0.78, 0), colour)


@model
def fridge(m):
    m.box(TEAL, (0, 0, 0.86), (0.8, 0.72, 1.66), round=0.08)
    m.box(WHITE, (0, -0.37, 1.2), (0.04, 0.03, 0.5), round=0.012)
    m.box(DARK, (0, -0.365, 0.92), (0.76, 0.012, 0.02), round=0.0)
    m.box(GREY, (0.28, -0.39, 1.2), (0.05, 0.05, 0.34), round=0.02)
    m.box(GREY, (0.28, -0.39, 0.6), (0.05, 0.05, 0.34), round=0.02)
    m.box(DARK, (0, 0, 0.03), (0.7, 0.62, 0.06), round=0.0)


@model
def ping_pong(m):
    m.box(GREEN, (0, 0, 0.74), (2.74, 1.525, 0.07), round=0.025)
    m.box(WHITE, (0, 0, 0.778), (2.6, 0.03, 0.006), round=0.0)
    m.box(WHITE, (0, 0, 0.85), (0.02, 1.62, 0.15), round=0.0)
    for x in (-1.0, 1.0):
        for y in (-0.55, 0.55):
            m.disc(GREY, (x, y, 0), 0.05, 0.72, round=0.0, segments=12)
    for x, y, turn, colour in ((-0.9, -0.3, 0.6, RED), (0.8, 0.35, -2.2, BLUE)):
        with m.at((x, y, 0.778), turn):
            m.disc(colour, (0, 0, 0), 0.09, 0.02, segments=20, round=0.006)
            m.box(WOOD, (0.13, 0, 0.01), (0.12, 0.035, 0.022), round=0.008)
    m.ball(ORANGE, (0.3, -0.2, 0.8), 0.025, detail=2)


@model
def table_football(m):
    m.box(WOOD, (0, 0, 0.72), (1.5, 0.84, 0.3), round=0.05)
    m.box(GREEN, (0, 0, 0.85), (1.3, 0.66, 0.05), round=0.0)
    for x in (-0.6, 0.6):
        for y in (-0.3, 0.3):
            m.disc(DARK, (x, y, 0), 0.05, 0.6, round=0.0, segments=12)
    for k, x in enumerate((-0.45, -0.15, 0.15, 0.45)):
        m.rod(GREY, (x, -0.62, 0.93), (x, 0.62, 0.93), 0.015, segments=10)
        m.ball(DARK, (x, -0.64, 0.93), 0.04, detail=1)
        for y in (-0.16, 0.16):
            m.box(RED if k % 2 else BLUE, (x, y, 0.93), (0.06, 0.08, 0.12), round=0.02)


@model
def arcade(m):
    rng = random.Random(7)
    m.box(PURPLE, (0, 0.05, 0.85), (0.74, 0.8, 1.7), round=0.06)
    m.box(DARK, (0, -0.33, 1.25), (0.62, 0.06, 0.5), round=0.02, tilt=('X', -0.2))
    m.box(SCREEN, (0, -0.37, 1.25), (0.52, 0.02, 0.4), round=0.008, tilt=('X', -0.2))
    for k in range(5):
        m.box(rng.choice([YELLOW, PINK, WHITE, GREEN]), (rng.uniform(-0.18, 0.18), -0.385 - rng.uniform(-0.14, 0.14) * 0.2, 1.25 + rng.uniform(-0.14, 0.14)), (0.07, 0.02, 0.07), round=0.004, tilt=('X', -0.2))
    m.box(YELLOW, (0, -0.42, 0.92), (0.74, 0.34, 0.08), round=0.03)
    m.rod(DARK, (-0.18, -0.46, 0.95), (-0.18, -0.46, 1.06), 0.02, segments=8)
    m.ball(RED, (-0.18, -0.46, 1.08), 0.05, detail=2)
    for k, x in enumerate((0.08, 0.2)):
        m.disc([GREEN, BLUE][k], (x, -0.46, 0.96), 0.04, 0.025, segments=14, round=0.008)
    m.box(YELLOW, (0, -0.36, 1.6), (0.66, 0.04, 0.16), round=0.02)


@model
def basketball(m):
    m.disc(DARK, (0, 0.5, 0), 0.4, 0.1, segments=28, round=0.03)
    m.along(GREY, (0, 0.5, 0.08), (0, 0.5, 2.5), (0.1, 0.1), 0.03)
    m.along(GREY, (0, 0.5, 2.45), (0, 0.05, 2.75), (0.08, 0.08), 0.03)
    m.box(WHITE, (0, 0.0, 2.9), (1.3, 0.07, 0.9), round=0.03)
    m.box(RED, (0, -0.04, 2.78), (0.5, 0.012, 0.36), round=0.0)
    m.box(WHITE, (0, -0.045, 2.78), (0.4, 0.012, 0.26), round=0.0)
    for k in range(14):
        a, b = math.tau * k / 14, math.tau * (k + 1) / 14
        m.rod(ORANGE, (math.cos(a) * 0.23, -0.3 + math.sin(a) * 0.23, 2.6), (math.cos(b) * 0.23, -0.3 + math.sin(b) * 0.23, 2.6), 0.02, segments=8)
    m.ball(ORANGE, (0.5, -0.5, 0.13), 0.13, detail=3)


def books(m, x0, x1, z, rng, depth=0.24):
    x = x0
    while x < x1 - 0.06:
        w = rng.uniform(0.05, 0.09)
        h = rng.uniform(0.22, 0.32)
        m.box(rng.choice(BRIGHT + [WHITE]), (x + w / 2, -0.12, z + h / 2), (w, depth, h), round=0.012)
        x += w + 0.008 + (rng.uniform(0.05, 0.16) if rng.random() < 0.12 else 0.0)


@model
def bookcase_low(m):
    rng = random.Random(8)
    m.box(WHITE, (0, 0, 0.5), (1.7, 0.36, 1.0), round=0.04)
    for z in (0.08, 0.53):
        m.box(DARK, (0, -0.175, z + 0.18), (1.56, 0.02, 0.36), round=0.0)
        books(m, -0.76, 0.76, z, rng)


@model
def bookcase_tall(m):
    rng = random.Random(9)
    m.box(YELLOW, (0, 0, 1.0), (1.7, 0.36, 2.0), round=0.04)
    for z in (0.08, 0.56, 1.04, 1.52):
        m.box(DARK, (0, -0.175, z + 0.19), (1.56, 0.02, 0.38), round=0.0)
        books(m, -0.76, 0.76, z, rng)


@model
def server(m):
    rng = random.Random(10)
    m.box(DARK, (0, 0, 0.5), (0.66, 0.8, 1.0), round=0.05)
    for k in range(5):
        z = 0.16 + k * 0.17
        m.box(GREY, (0, -0.4, z), (0.54, 0.03, 0.12), round=0.015)
        for j in range(rng.randint(2, 4)):
            m.box(LED if rng.random() < 0.75 else SCREEN, (-0.2 + j * 0.07, -0.42, z), (0.04, 0.012, 0.04), round=0.0)


@model
def treadmill(m):
    m.box(DARK, (0, 0, 0.1), (0.8, 1.7, 0.16), round=0.05)
    m.box(GREY, (0, -0.05, 0.19), (0.6, 1.4, 0.02), round=0.0)
    for x in (-0.36, 0.36):
        m.along(RED, (x, 0.75, 0.15), (x, 0.55, 0.95), (0.07, 0.07), 0.03)
        m.along(RED, (x, 0.55, 0.92), (x, 0.1, 0.86), (0.06, 0.06), 0.025)
    m.box(DARK, (0, 0.6, 0.95), (0.78, 0.12, 0.1), round=0.03, tilt=('X', 0.5))
    m.box(SCREEN, (0, 0.57, 0.96), (0.4, 0.04, 0.07), round=0.01, tilt=('X', 0.5))


@model
def exercise_bike(m):
    m.box(DARK, (0, 0, 0.04), (0.5, 1.1, 0.08), round=0.03)
    m.rod(BLUE, (0, 0.25, 0.4), (0.08, 0.25, 0.4), 0.3, segments=28)
    m.rod(BLUE, (0, 0.25, 0.4), (-0.08, 0.25, 0.4), 0.3, segments=28)
    m.along(GREY, (0, -0.25, 0.08), (0, -0.2, 0.75), (0.08, 0.08), 0.03)
    m.box(DARK, (0, -0.22, 0.8), (0.24, 0.34, 0.09), round=0.04)
    m.along(GREY, (0, 0.3, 0.6), (0, 0.42, 0.98), (0.07, 0.07), 0.03)
    m.along(DARK, (-0.25, 0.42, 0.97), (0.25, 0.42, 0.97), (0.05, 0.05), 0.02)


@model
def weights(m):
    for x in (-0.7, 0.7):
        m.box(GREY, (x, 0, 0.4), (0.08, 0.5, 0.8), round=0.03)
    for row, z in enumerate((0.28, 0.66)):
        m.box(DARK, (0, 0, z), (1.5, 0.4, 0.06), round=0.02)
        for k in range(4):
            x = -0.52 + k * 0.35
            colour = BRIGHT[(k + row * 3) % len(BRIGHT)]
            m.rod(GREY, (x - 0.12, 0, z + 0.12), (x + 0.12, 0, z + 0.12), 0.025, segments=10)
            for end in (-0.12, 0.12):
                m.rod(colour, (x + end - 0.035, 0, z + 0.12), (x + end + 0.035, 0, z + 0.12), 0.09, segments=18, round=0.015)


@model
def yoga_mat(m):
    m.box(PINK, (0, 0, 0.07), (0.75, 1.8, 0.05), round=0.015)
    m.ball(TEAL, (0.75, 0.3, 0.3), 0.3, detail=3)
    m.rod(PURPLE, (-0.7, -0.6, 0.08), (-0.7, 0.1, 0.08), 0.08, segments=18, round=0.02)


@model
def plant(m):
    pot(m, (0, 0, 0), ORANGE)
    blob(m, (0, 0, 0.62), 0.36)
    m.ball(LEAF, (-0.2, 0.1, 0.5), 0.22, detail=2)


@model
def tree(m):
    m.disc(WHITE, (0, 0, 0), 0.5, 0.3, 0.44, segments=28, round=0.04)
    m.disc(WOOD, (0, 0, 0.25), 0.14, 2.0, 0.1, segments=16)
    blob(m, (0, 0, 2.9), 1.15)
    m.ball(LEAF, (-0.75, 0.3, 2.3), 0.62, detail=2)
    m.ball(LEAF_LIGHT, (0.7, -0.35, 2.4), 0.55, detail=2)


@model
def planter(m):
    m.box(WHITE, (0, 0, 0.22), (2.0, 0.5, 0.44), round=0.06)
    for k in range(5):
        x = -0.78 + k * 0.39
        m.ball(LEAF if k % 2 else LEAF_LIGHT, (x, 0, 0.56), 0.24, (1, 1, 0.9), detail=2)
        m.ball([PINK, YELLOW, RED, WHITE, ORANGE][k], (x + 0.05, -0.12, 0.74), 0.07, detail=2)


@model
def bench(m):
    for x in (-0.7, 0.7):
        m.box(GREY, (x, 0, 0.2), (0.1, 0.44, 0.4), round=0.035)
    for k, y in enumerate((-0.14, 0.02, 0.18)):
        m.box([RED, YELLOW, BLUE][k], (0, y, 0.43), (1.8, 0.14, 0.07), round=0.03)
    m.box(GREEN, (0, 0.24, 0.72), (1.8, 0.07, 0.3), round=0.03)
    for x in (-0.7, 0.7):
        m.box(GREY, (x, 0.24, 0.55), (0.08, 0.07, 0.36), round=0.025)


@model
def fountain(m):
    m.disc(WHITE, (0, 0, 0), 1.3, 0.42, segments=48, round=0.06)
    m.disc(WATER, (0, 0, 0.36), 1.12, 0.07, segments=48, round=0.0)
    m.disc(WHITE, (0, 0, 0.3), 0.26, 0.42, segments=24, round=0.04)
    m.disc(WHITE, (0, 0, 0.7), 0.5, 0.1, segments=32, round=0.04)
    m.disc(WATER, (0, 0, 0.77), 0.42, 0.04, segments=32, round=0.0)
    m.ball(WATER, (0, 0, 0.86), 0.1, (1, 1, 1.2), detail=2)
    for k in range(6):
        a = math.tau * k / 6
        m.ball(WATER, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.58), 0.06, (1, 1, 2.2), detail=1)


@model
def flowerbed(m):
    rng = random.Random(11)
    m.disc(WOOD, (0, 0, 0), 0.9, 0.16, segments=36, round=0.05)
    m.disc(DARK, (0, 0, 0.13), 0.8, 0.04, segments=36, round=0.0)
    for k in range(11):
        a = math.tau * k / 11
        r = 0.55 if k % 2 else 0.25
        x, y = math.cos(a) * r, math.sin(a) * r
        m.rod(LEAF, (x, y, 0.15), (x, y, 0.36), 0.02, segments=8)
        m.ball(rng.choice([PINK, YELLOW, RED, WHITE, ORANGE, PURPLE]), (x, y, 0.4), 0.1, (1, 1, 0.7), detail=2)


@model
def reception(m):
    count = 7
    for k in range(count):
        a = math.radians(-60 + 120 * k / (count - 1)) - math.pi / 2
        with m.at((math.cos(a) * 1.7, math.sin(a) * 1.7 + 1.7, 0), a + math.pi / 2):
            m.box(WHITE, (0, 0, 0.44), (0.62, 0.46, 0.86), round=0.05)
            m.box(BRIGHT[k], (0, -0.24, 0.44), (0.5, 0.03, 0.6), round=0.03)
            m.box(WOOD, (0, 0.02, 0.9), (0.66, 0.56, 0.07), round=0.03)
            m.box(WHITE, (0, 0.42, 0.56), (0.66, 0.4, 0.06), round=0.025)
    monitor(m, (-0.3, 0.52, 0.59), -0.2)
    m.disc(YELLOW, (0.45, 0.2, 0.935), 0.07, 0.05, segments=16, round=0.02)
    chair(m, (0.0, 1.05, 0), 0.2, RED)


@model
def printer(m):
    m.box(WHITE, (0, 0, 0.28), (0.7, 0.56, 0.56), round=0.05)
    m.box(BLUE, (0, -0.285, 0.28), (0.54, 0.02, 0.36), round=0.03)
    m.box(GREY, (0, 0, 0.72), (0.62, 0.5, 0.34), round=0.06)
    m.box(WHITE, (0, -0.34, 0.66), (0.4, 0.26, 0.02), round=0.006, tilt=('X', 0.15))
    m.box(SCREEN, (0.18, -0.2, 0.9), (0.14, 0.1, 0.03), round=0.01, tilt=('X', 0.5))


@model
def boxes(m):
    for at, size, turn in (((-0.3, 0, 0.25), (0.6, 0.5, 0.5), 0.1), ((0.35, 0.05, 0.2), (0.5, 0.5, 0.4), -0.2), ((-0.2, 0.02, 0.66), (0.44, 0.4, 0.32), 0.4)):
        m.box(WOOD, at, size, turn, 0.03)
        m.box(WHITE, (at[0], at[1], at[2] + size[2] / 2), (0.08, size[1] * 0.98, 0.02), turn, 0.0)


@model
def rocket(m):
    m.disc(GREY, (0, 0, 0), 1.6, 0.2, segments=48, round=0.05)
    m.disc(DARK, (0, 0, 0.18), 0.5, 0.5, 0.75, segments=32)
    m.disc(WHITE, (0, 0, 0.6), 0.8, 3.4, segments=40, round=0.1)
    m.disc(RED, (0, 0, 3.9), 0.8, 1.9, 0.06, segments=40)
    m.ball(RED, (0, 0, 5.8), 0.1, detail=2)
    m.disc(BLUE, (0, 0, 2.2), 0.82, 0.24, segments=40, round=0.0)
    m.disc(YELLOW, (0, 0, 1.3), 0.82, 0.14, segments=40, round=0.0)
    m.rod(DARK, (0, -0.72, 3.1), (0, -0.84, 3.1), 0.36, segments=28, round=0.02)
    m.rod(SCREEN, (0, -0.8, 3.1), (0, -0.86, 3.1), 0.27, segments=28)
    for k in range(3):
        a = math.tau * k / 3 + math.pi / 6
        with m.at((math.cos(a) * 0.95, math.sin(a) * 0.95, 0), a):
            m.along(RED, (0.5, 0, 0.2), (-0.1, 0, 1.9), (0.16, 0.7), 0.06)
            m.box(RED, (0.42, 0, 0.5), (0.5, 0.16, 0.6), round=0.06)


@model
def lamp(m):
    m.disc(DARK, (0, 0, 0), 0.24, 0.06, segments=28)
    m.disc(GREY, (0, 0, 0.05), 0.03, 1.45, round=0.0, segments=12)
    m.disc(LAMP, (0, 0, 1.45), 0.3, 0.36, 0.2, segments=32, round=0.03)


@model
def lamp_low(m):
    m.disc(WHITE, (0, 0, 0), 0.2, 0.08, segments=24, round=0.03)
    m.disc(WHITE, (0, 0, 0.06), 0.09, 0.44, 0.07, segments=16)
    m.ball(LAMP, (0, 0, 0.66), 0.3, (1, 1, 0.75), detail=3)


@model
def flag(m):
    m.disc(GREY, (0, 0, 0), 0.26, 0.1, segments=24, round=0.03)
    m.disc(WHITE, (0, 0, 0.08), 0.045, 2.9, round=0.0, segments=12)
    m.ball(YELLOW, (0, 0, 3.02), 0.09, detail=2)
    m.box(RED, (0.5, 0, 2.6), (0.95, 0.04, 0.56), round=0.015)
    m.box(WHITE, (0.5, -0.03, 2.6), (0.3, 0.012, 0.3), 0.0, 0.0, ('Y', 0.785))


@model
def duck(m):
    m.ball(YELLOW, (0, 0, 0.36), 0.42, (0.95, 1.2, 0.82), detail=3)
    m.ball(YELLOW, (0, -0.3, 0.74), 0.27, detail=3)
    m.ball(YELLOW, (0, 0.5, 0.52), 0.16, (1, 1.3, 0.8), detail=2)
    m.box(ORANGE, (0, -0.58, 0.7), (0.2, 0.18, 0.07), round=0.03)
    for x in (-0.11, 0.11):
        m.ball(DARK, (x, -0.52, 0.82), 0.035, detail=1)
    for x in (-0.38, 0.38):
        m.ball(YELLOW, (x, 0.08, 0.38), 0.2, (0.45, 1.25, 0.75), detail=2)


for name, build in MODELS.items():
    if ONLY and name not in ONLY:
        continue
    made = Model(name)
    build(made)
    made.save()
print('TOY DONE', flush=True)

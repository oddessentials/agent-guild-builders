import math, sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import voxels
from voxels import Voxels

ONLY = set(sys.argv[sys.argv.index('--') + 2:])
# name: (sRGB, glow)
PALETTE = {
    'wall': ((0.9, 0.86, 0.74), 0), 'wall_low': ((0.36, 0.46, 0.62), 0), 'trim': ((0.2, 0.22, 0.32), 0),
    'wood1': ((0.36, 0.22, 0.14), 0), 'wood2': ((0.55, 0.34, 0.2), 0), 'wood3': ((0.72, 0.5, 0.3), 0),
    'beige1': ((0.66, 0.61, 0.52), 0), 'beige2': ((0.85, 0.8, 0.68), 0),
    'grey1': ((0.33, 0.35, 0.42), 0), 'grey2': ((0.55, 0.57, 0.62), 0), 'grey3': ((0.76, 0.78, 0.82), 0),
    'black': ((0.1, 0.1, 0.14), 0), 'white': ((0.96, 0.96, 0.94), 0),
    'red1': ((0.58, 0.13, 0.16), 0), 'red2': ((0.84, 0.22, 0.2), 0), 'blue1': ((0.14, 0.24, 0.56), 0), 'blue2': ((0.22, 0.42, 0.86), 0),
    'sky': ((0.45, 0.72, 0.96), 0), 'green1': ((0.13, 0.42, 0.22), 0), 'green2': ((0.25, 0.66, 0.3), 0), 'green3': ((0.52, 0.84, 0.36), 0),
    'yellow': ((0.98, 0.82, 0.22), 0), 'orange': ((0.96, 0.55, 0.16), 0), 'purple': ((0.56, 0.33, 0.8), 0), 'pink': ((0.96, 0.52, 0.7), 0),
    'teal': ((0.16, 0.66, 0.66), 0), 'clay': ((0.76, 0.4, 0.26), 0), 'card': ((0.8, 0.62, 0.4), 0), 'fabric': ((0.45, 0.52, 0.66), 0),
    'screen_green': ((0.3, 0.95, 0.45), 0.7), 'screen_blue': ((0.35, 0.65, 1.0), 0.7), 'screen_amber': ((1.0, 0.72, 0.2), 0.7),
    'lamp': ((1.0, 0.9, 0.6), 0.9), 'led_red': ((1.0, 0.2, 0.2), 0.9), 'led_green': ((0.3, 1.0, 0.4), 0.9),
}
voxels.use('retro_', PALETTE, Path(sys.argv[sys.argv.index('--') + 1]).resolve())
MODELS = {}
BRIGHT = ['red2', 'blue2', 'green2', 'yellow', 'orange', 'purple', 'pink', 'teal']


def model(build):
    MODELS['retro_' + build.__name__] = build
    return build


def new(name, wide, deep, tall, seed=1):
    return Voxels('retro_' + name, wide, deep, tall, seed)


def cells(v, x0, x1, y0, y1, z0, z1):
    return v.box((x0, y0, z0), (x1, y1, z1))


# In these helpers `back` is 1 when the piece's far side is +y, and -1 when it is turned round.

def chair(v, x, y, back, colour):
    v.paint(cells(v, x - 2, x + 2, y - 0.5, y + 0.5, 0, 1) | cells(v, x - 0.5, x + 0.5, y - 2, y + 2, 0, 1), 'black')
    v.paint(cells(v, x - 0.5, x + 0.5, y - 0.5, y + 0.5, 1, 3), 'grey1')
    v.paint(cells(v, x - 2, x + 2, y - 2, y + 2, 3, 4), colour)
    edge = (y + 1, y + 2) if back > 0 else (y - 2, y - 1)
    v.paint(cells(v, x - 2, x + 2, edge[0], edge[1], 4, 8), colour)


def computer(v, x, y, back, screen):
    """A boxy monitor at the back of a desk, with its screen towards the sitter."""
    body = (y, y + 3) if back > 0 else (y - 3, y)
    face = (y, y + 1) if back > 0 else (y - 1, y)
    v.paint(cells(v, x - 2, x + 2, body[0], body[1], 7, 11), 'beige2')
    v.paint(cells(v, x - 1, x + 1, body[0], body[1], 6, 7), 'beige1')
    v.paint(cells(v, x - 1, x + 1, face[0], face[1], 8, 10), screen)
    keys = (y - 2, y - 1) if back > 0 else (y + 1, y + 2)
    v.paint(cells(v, x - 2, x + 2, keys[0], keys[1], 6, 7), 'beige1')


def desk(v, x, y, back, screen, wood='wood3', extra=None):
    v.paint(cells(v, x - 6, x + 6, y - 3, y + 3, 5, 6), wood)
    for side in (-6, 5):
        v.paint(cells(v, x + side, x + side + 1, y - 3, y + 3, 0, 5), 'wood2')
    v.paint(cells(v, x + 2, x + 5, y - 2, y + 3, 2, 5), 'wood2')
    handle = (y - 3, y - 2) if back > 0 else (y + 3, y + 4)
    v.paint(cells(v, x + 3, x + 4, y - 2 if back > 0 else y + 2, y - 1 if back > 0 else y + 3, 3, 4), 'grey3')
    computer(v, x - 1, y, back, screen)
    if extra:
        spot = y - 2 if back > 0 else y + 1
        v.paint(cells(v, x + 4, x + 5, spot, spot + 1, 6, 7), extra)


def shelf_of_books(v, x0, x1, y0, y1, z, rng):
    x = x0
    while x < x1:
        if rng.random() < 0.12:
            x += 1
            continue
        v.paint(cells(v, x, x + 1, y0, y1, z, z + int(rng.integers(2, 4))), BRIGHT[int(rng.integers(len(BRIGHT)))] if rng.random() < 0.7 else 'white')
        x += 1


def leaves(v, at, radius, tall):
    where = v.ball((at[0], at[1], at[2] + tall / 2), (radius, radius, tall / 2)) & (v.rng.random(v.grid.shape) < 0.86)
    v.paint(where, ['green1', 'green2', 'green3'], [2, 4, 2])
    v.paint(where & (v.z > at[2] + tall * 0.6), ['green2', 'green3'])


def wall(v, half):
    body = cells(v, -half, half, -1.5, 1.5, 0, 40)
    v.paint(body, 'wall')
    v.paint(body & (v.z < 12), 'wall_low')
    v.paint(body & ((v.z < 1) | ((v.z >= 12) & (v.z < 13)) | (v.z >= 38)), 'trim')
    return body


def window(v, x):
    v.clear(cells(v, x - 8, x + 8, -1.5, -0.5, 15, 30))
    pane = cells(v, x - 8, x + 8, -0.5, 0.5, 15, 30)
    v.paint(pane, 'sky')
    v.paint(pane & (v.rough(4) > 0.35) & (v.z > 19), 'white')
    frame = cells(v, x - 9, x + 9, -1.5, -0.5, 14, 31) & ~cells(v, x - 8, x + 8, -1.5, -0.5, 15, 30)
    v.paint(frame, 'white')
    v.paint(cells(v, x - 0.5, x + 0.5, -1.5, -0.5, 15, 30) | cells(v, x - 8, x + 8, -1.5, -0.5, 22, 23), 'white')


@model
def wall_plain():
    v = new('wall_plain', 64, 3, 40)
    wall(v, 32)
    return v


@model
def wall_short():
    v = new('wall_short', 32, 3, 40)
    wall(v, 16)
    return v


@model
def wall_corner():
    v = new('wall_corner', 3, 3, 40)
    wall(v, 1.5)
    return v


@model
def wall_window():
    v = new('wall_window', 64, 3, 40, 3)
    wall(v, 32)
    window(v, -15)
    window(v, 15)
    return v


@model
def wall_door():
    v = new('wall_door', 64, 3, 40)
    wall(v, 32)
    v.clear(cells(v, -6, 6, -1.5, -0.5, 1, 20))
    v.paint(cells(v, -6, 6, -0.5, 0.5, 0, 20), 'wood2')
    v.paint(cells(v, -0.5, 0.5, -0.5, 0.5, 0, 20), 'wood1')
    for x in (-4, 2):
        v.paint(cells(v, x, x + 2, -0.5, 0.5, 11, 17), 'sky')
    v.paint(cells(v, -2, -1, -1.5, -0.5, 9, 10) | cells(v, 1, 2, -1.5, -0.5, 9, 10), 'yellow')
    v.paint(cells(v, -7, 7, -1.5, -0.5, 20, 21) | cells(v, -7, -6, -1.5, -0.5, 0, 20) | cells(v, 6, 7, -1.5, -0.5, 0, 20), 'trim')
    v.paint(cells(v, -4, 4, -1.5, -0.5, 23, 26), 'green1')
    v.paint(cells(v, -3, 3, -1.5, -0.5, 24, 25) & (v.x.astype(int) % 2 == 0), 'led_green')
    return v


@model
def wall_posters():
    v = new('wall_posters', 64, 3, 40, 5)
    wall(v, 32)
    front = lambda x0, x1, z0, z1: cells(v, x0, x1, -1.5, -0.5, z0, z1)
    v.paint(front(-26, -15, 16, 30), 'red2')
    star = (np.abs(v.x + 20.5) + np.abs(v.z - 23) < 4.2) | ((np.abs(v.x + 20.5) < 5) & (np.abs(v.z - 24) < 1))
    v.paint(front(-26, -15, 16, 30) & star, 'yellow')
    v.paint(front(-8, 8, 15, 31), 'trim')
    v.paint(front(-7, 7, 16, 30), 'blue1')
    for k, tall in enumerate((4, 7, 5, 10, 8, 11)):
        v.paint(front(-6 + k * 2, -5 + k * 2, 17, 17 + tall), ['screen_green', 'yellow', 'white'][k % 3])
    v.paint(front(16, 27, 17, 30), 'white')
    v.paint(front(16, 27, 27, 30), 'red2')
    grid = ((v.x.astype(int) % 3) == 1) & ((v.z.astype(int) % 3) == 1)
    v.paint(front(17, 26, 18, 26) & grid, 'grey2')
    v.paint(front(22, 23, 21, 22), 'red2')
    return v


@model
def partition():
    v = new('partition', 32, 2, 12)
    v.paint(cells(v, -16, 16, -1, 1, 0, 12), 'fabric')
    v.paint(cells(v, -16, 16, -1, 1, 11, 12) | cells(v, -16, 16, -1, 1, 0, 1), 'grey1')
    for x in (-16, 15):
        v.paint(cells(v, x, x + 1, -1, 1, 0, 12), 'grey1')
    return v


@model
def desk_single():
    v = new('desk_single', 14, 14, 11)
    desk(v, 0, 2, 1, 'screen_green', extra='red2')
    chair(v, -1, -4, -1, 'blue2')
    return v


@model
def desk_row():
    v = new('desk_row', 40, 14, 11)
    for k, x in enumerate((-13, 0, 13)):
        desk(v, x, 2, 1, ['screen_green', 'screen_blue', 'screen_amber'][k], extra=['red2', 'yellow', 'white'][k])
        chair(v, x - 1, -4, -1, ['red2', 'blue2', 'green2'][k])
    return v


@model
def cubicles():
    v = new('cubicles', 36, 34, 10, 7)
    v.paint(cells(v, -18, 18, -1, 1, 0, 10) | cells(v, -1, 1, -15, 15, 0, 10), 'fabric')
    v.paint((cells(v, -18, 18, -1, 1, 9, 10) | cells(v, -1, 1, -15, 15, 9, 10)), 'grey1')
    screens = ['screen_green', 'screen_blue', 'screen_amber', 'screen_green']
    seats = ['red2', 'blue2', 'yellow', 'green2']
    k = 0
    for x in (-9, 9):
        for y, back in ((-5, 1), (5, -1)):
            desk(v, x, y, back, screens[k], extra=BRIGHT[k + 3])
            chair(v, x - 1, y - 6 * back, -back, seats[k])
            k += 1
    note = lambda x, y, colour: v.paint(cells(v, x, x + 2, y, y + 1, 6, 8), colour)
    note(-14, -2, 'yellow')
    note(5, -2, 'pink')
    note(-6, 1, 'green3')
    note(12, 1, 'yellow')
    return v


@model
def boss_desk():
    v = new('boss_desk', 26, 18, 12)
    v.paint(cells(v, -11, 11, 0, 7, 5, 6), 'wood2')
    v.paint(cells(v, -11, 11, 0, 7, 0, 5) & ~cells(v, -8, 8, 0, 6, 0, 5), 'wood1')
    v.paint(cells(v, -11, 11, 6, 7, 1, 5), 'wood1')
    v.paint(cells(v, -11, 11, 6, 7, 2, 4) & (v.x.astype(int) % 6 != 0), 'wood2')
    computer(v, 4, 3, 1, 'screen_amber')
    v.paint(cells(v, -9, -6, 2, 5, 6, 7), 'red2')
    v.paint(cells(v, -9, -6, 2, 3, 7, 8), 'red1')
    v.paint(cells(v, -4, -1, 1, 4, 6, 6.6), 'white')
    v.paint(cells(v, -7, -6, 5, 6, 6, 10), 'yellow')
    v.paint(cells(v, -9, -5, 3, 6, 10, 11), 'green1')
    v.paint(cells(v, -8, -6, 4, 5, 9, 10), 'lamp')
    v.paint(cells(v, -2, 2, 6, 7, 6, 7), 'yellow')
    v.paint(cells(v, -3, 3, -6, -1, 3, 4), 'red1')
    v.paint(cells(v, -3, 3, -7, -6, 4, 11), 'red1')
    v.paint(cells(v, -4, -3, -6, -1, 4, 6) | cells(v, 3, 4, -6, -1, 4, 6), 'wood1')
    v.paint(cells(v, -0.5, 0.5, -4, -3, 1, 3), 'grey1')
    v.paint(cells(v, -2, 2, -4, -3, 0, 1) | cells(v, -0.5, 0.5, -6, -1, 0, 1), 'black')
    return v


@model
def office_chair():
    v = new('office_chair', 6, 6, 8)
    chair(v, 0, 0, 1, 'blue2')
    return v


@model
def meeting_table():
    v = new('meeting_table', 38, 26, 9)
    v.paint(cells(v, -12, 12, -5, 5, 5, 6), 'wood3')
    v.paint(cells(v, -12, 12, -5, 5, 4, 5) & ~cells(v, -11, 11, -4, 4, 4, 5), 'wood2')
    for x in (-9, 8):
        v.paint(cells(v, x, x + 1, -3, 3, 0, 5), 'wood1')
    seats = ['red2', 'blue2', 'green2', 'yellow', 'blue2', 'red2', 'purple', 'teal']
    for k, x in enumerate((-8, 0, 8)):
        chair(v, x, -9, -1, seats[k])
        chair(v, x, 9, 1, seats[k + 3])
    v.paint(cells(v, -9, -6, -3, -1, 6, 6.6) | cells(v, 1, 4, 1, 3, 6, 6.6) | cells(v, 7, 10, -3, -1, 6, 6.6), 'white')
    v.paint(cells(v, -2, -1, -1, 0, 6, 7), 'red2')
    v.paint(cells(v, 5, 6, 2, 3, 6, 7), 'blue2')
    v.paint(cells(v, -1, 1, -1, 1, 6, 7) & (v.x > 0), 'black')
    return v


@model
def mainframe():
    v = new('mainframe', 28, 8, 17, 9)
    v.paint(cells(v, -14, 2, -3, 4, 0, 17), 'grey3')
    v.paint(cells(v, -14, 2, -3, 4, 0, 1), 'grey1')
    front = lambda x0, x1, z0, z1: cells(v, x0, x1, -3, -2, z0, z1)
    v.paint(front(-13, 1, 9, 16), 'black')
    for x in (-9.5, -2.5):
        reel = np.hypot(v.x - x, v.z - 12.5)
        v.paint(front(-13, 1, 9, 16) & (reel < 3.2), 'grey2')
        v.paint(front(-13, 1, 9, 16) & (reel < 1.2), 'white')
    v.paint(front(-13, 1, 5, 8), 'grey1')
    lights = front(-12, 0, 6, 7) & (v.x.astype(int) % 2 == 0)
    v.paint(lights, ['led_red', 'led_green', 'yellow'])
    v.paint(front(-13, 1, 2, 4) & (v.x.astype(int) % 2 == 0), 'grey1')
    v.paint(cells(v, 3, 14, -3, 4, 0, 12), 'beige2')
    v.paint(cells(v, 3, 14, -3, 4, 0, 1), 'grey1')
    v.paint(cells(v, 4, 13, -3, -2, 6, 11), 'black')
    v.paint(cells(v, 5, 12, -3, -2, 7, 10), 'screen_green')
    v.paint(cells(v, 5, 12, -3, -2, 7, 10) & (v.rng.random(v.grid.shape) < 0.3), 'black')
    v.paint(cells(v, 4, 13, -3, -2, 3, 5) & (v.x.astype(int) % 2 == 1), ['led_green', 'led_red'], [3, 1])
    return v


@model
def printer():
    v = new('printer', 10, 9, 10)
    v.paint(cells(v, -4, 4, -3, 3, 0, 4), 'wood2')
    v.paint(cells(v, -3, 3, -3, -2, 1, 3), 'wood1')
    v.paint(cells(v, -4, 4, -3, 3, 4, 7), 'beige2')
    v.paint(cells(v, -4, 4, -3, -2, 4, 5), 'beige1')
    v.paint(cells(v, -3, 3, 0, 1, 7, 10) | cells(v, -3, 3, -4, 0, 7, 7.6), 'white')
    v.paint(cells(v, -3, 3, 0, 1, 7, 10) & (v.z.astype(int) % 2 == 0) & (np.abs(v.x) > 2), 'green3')
    v.paint(cells(v, 2, 3, -3, -2, 5, 6), 'led_green')
    return v


@model
def copier():
    v = new('copier', 14, 9, 10)
    v.paint(cells(v, -5, 5, -3, 4, 0, 8), 'grey3')
    v.paint(cells(v, -5, 5, -3, 4, 0, 1), 'grey1')
    v.paint(cells(v, -5, 5, -3, 4, 8, 9), 'grey1')
    v.paint(cells(v, -4, 4, -3, -2, 2, 3) | cells(v, -4, 4, -3, -2, 4, 5), 'grey2')
    v.paint(cells(v, 1, 5, -4, -3, 7, 8), 'black')
    v.paint(cells(v, 3, 4, -4, -3, 7, 8), 'led_green')
    v.paint(cells(v, 5, 7, -2, 3, 5, 5.6), 'white')
    v.paint(cells(v, -4, 0, -1, 2, 9, 9.6), 'white')
    return v


@model
def arcade():
    v = new('arcade', 8, 9, 16, 11)
    body = cells(v, -4, 4, -3, 4, 0, 16)
    v.paint(body, 'blue1')
    v.clear(cells(v, -4, 4, -3, -1, 8, 14) | cells(v, -4, 4, -3, 0, 10, 14))
    v.paint(cells(v, -4, -3, -3, 4, 0, 16) | cells(v, 3, 4, -3, 4, 0, 16), 'blue2')
    v.paint((cells(v, -4, -3, -1, 4, 3, 12) | cells(v, 3, 4, -1, 4, 3, 12)) & ((v.y + v.z).astype(int) % 4 < 2), 'yellow')
    screen = cells(v, -3, 3, 0, 1, 10, 14)
    v.paint(screen, 'black')
    v.paint(screen & (v.rng.random(v.grid.shape) < 0.35), ['screen_green', 'pink', 'yellow', 'screen_blue'])
    v.paint(cells(v, -3, 3, -3, -1, 7, 8), 'grey1')
    v.paint(cells(v, -2, -1, -2, -1, 8, 10), 'red2')
    v.paint(cells(v, 1, 2, -3, -2, 8, 9), 'yellow')
    v.paint(cells(v, 2, 3, -2, -1, 8, 9), 'screen_blue')
    v.paint(cells(v, -3, 3, -3, -2, 14, 16), 'screen_amber')
    v.paint(cells(v, -3, 3, -3, -2, 14, 16) & (v.x.astype(int) % 2 == 0), 'red2')
    v.paint(cells(v, -1, 1, -3, -2, 2, 5), 'grey1')
    v.paint(cells(v, -0.5, 0.5, -3, -2, 3, 4), 'yellow')
    return v


@model
def vending():
    v = new('vending', 9, 7, 16, 12)
    v.paint(cells(v, -4, 5, -3, 4, 0, 16), 'red2')
    v.paint(cells(v, -4, 5, -3, 4, 0, 1), 'grey1')
    v.paint(cells(v, -4, 5, -3, -2, 14, 16), 'lamp')
    v.paint(cells(v, -3, 2, -3, -2, 5, 13), 'black')
    for row in range(4):
        for col in range(5):
            v.paint(cells(v, -3 + col, -2 + col, -3, -2, 5 + row * 2, 6 + row * 2), BRIGHT[int(v.rng.integers(len(BRIGHT)))])
    v.paint(cells(v, 3, 4, -3, -2, 8, 12), 'grey3')
    v.paint(cells(v, 3, 4, -3, -2, 10, 11), 'led_green')
    v.paint(cells(v, -3, 2, -3, -2, 2, 4), 'black')
    v.paint(cells(v, -4, 5, -3, -2, 4, 5), 'white')
    return v


@model
def water_cooler():
    v = new('water_cooler', 4, 4, 12)
    v.paint(cells(v, -2, 2, -2, 2, 0, 8), 'white')
    v.paint(cells(v, -2, 2, -2, 2, 0, 1), 'grey2')
    v.paint(cells(v, -1.5, 1.5, -1.5, 1.5, 8, 12) | cells(v, -1, 1, -1, 1, 8, 12), 'sky')
    v.paint(cells(v, -1, 0, -2, -1, 5, 6), 'red2')
    v.paint(cells(v, 0, 1, -2, -1, 5, 6), 'blue2')
    v.paint(cells(v, -1, 1, -2, -1, 3, 4), 'grey2')
    return v


@model
def coffee_corner():
    v = new('coffee_corner', 30, 8, 15, 13)
    v.paint(cells(v, -15, 7, -3, 3, 0, 6), 'wood2')
    v.paint(cells(v, -15, 7, -3, -2, 1, 5) & (v.x.astype(int) % 5 != 0), 'wood3')
    v.paint(cells(v, -15, 7, -4, 3, 6, 7), 'beige2')
    v.paint(cells(v, -13, -9, -1, 2, 7, 11), 'black')
    v.paint(cells(v, -12, -10, -2, -1, 7, 9), 'orange')
    v.paint(cells(v, -10, -9, -1, 0, 10, 11), 'led_red')
    for k, x in enumerate((-7, -5, -3)):
        v.paint(cells(v, x, x + 1, -2, -1, 7, 8), ['red2', 'blue2', 'yellow'][k])
    v.paint(cells(v, 0, 6, -1, 3, 7, 11), 'beige2')
    v.paint(cells(v, 1, 4, -1, 0, 8, 10), 'black')
    v.paint(cells(v, 5, 6, -1, 0, 8, 10), 'grey2')
    v.paint(cells(v, 8, 15, -3, 4, 0, 15), 'beige2')
    v.paint(cells(v, 8, 15, -3, 4, 0, 1), 'grey1')
    v.paint(cells(v, 8, 15, -3, -2, 9, 10), 'beige1')
    v.paint(cells(v, 9, 10, -4, -3, 10, 13) | cells(v, 9, 10, -4, -3, 5, 8), 'grey2')
    v.paint(cells(v, 12, 14, -3, -2, 11, 13), 'yellow')
    return v


def couch(v, half, colour, dark, pillows):
    v.paint(cells(v, -half, half, -3, 4, 0, 3), dark)
    v.paint(cells(v, -half + 2, half - 2, -3, 2, 3, 4), colour)
    v.paint(cells(v, -half, half, 2, 4, 3, 8), colour)
    for side in (-half, half - 2):
        v.paint(cells(v, side, side + 2, -3, 2, 3, 6), colour)
    v.paint(cells(v, -half, half, 3, 4, 7, 8), dark)
    for x, pillow in pillows:
        v.paint(cells(v, x, x + 2, 1, 2, 4, 6), pillow)


@model
def sofa():
    v = new('sofa', 18, 8, 8)
    couch(v, 9, 'red2', 'red1', ((-6, 'yellow'), (4, 'white')))
    return v


@model
def armchair():
    v = new('armchair', 9, 8, 8)
    couch(v, 4.5, 'blue2', 'blue1', ((-0.5, 'yellow'),))
    return v


@model
def coffee_table():
    v = new('coffee_table', 10, 7, 4)
    v.paint(cells(v, -5, 5, -3, 3, 2, 3), 'wood3')
    for x in (-5, 4):
        for y in (-3, 2):
            v.paint(cells(v, x, x + 1, y, y + 1, 0, 2), 'wood1')
    v.paint(cells(v, -3, 0, -2, 1, 3, 3.6), 'teal')
    v.paint(cells(v, 2, 3, 0, 1, 3, 4), 'white')
    return v


@model
def bookshelf():
    v = new('bookshelf', 16, 5, 17, 14)
    v.paint(cells(v, -8, 8, -2, 3, 0, 17), 'wood2')
    for z in (1, 5, 9, 13):
        v.clear(cells(v, -7, 7, -2, 2, z, z + 3))
        shelf_of_books(v, -7, 7, -1, 2, z, v.rng)
    v.paint(cells(v, -8, 8, -2, 3, 16, 17), 'wood1')
    return v


@model
def filing():
    v = new('filing', 16, 6, 12, 15)
    for k, x in enumerate((-7, -2, 3)):
        v.paint(cells(v, x, x + 4, -2, 3, 0, 9), 'grey3' if k != 1 else 'beige2')
        for z in (3, 6):
            v.paint(cells(v, x, x + 4, -2, -1, z, z + 1), 'grey1')
        for z in (1, 4, 7):
            v.paint(cells(v, x + 1, x + 3, -2, -1, z, z + 1), 'grey2')
    v.paint(cells(v, -6, -4, 0, 2, 9, 10), 'clay')
    leaves(v, (-5, 1, 10), 2, 2)
    v.paint(cells(v, 3, 7, -1, 2, 9, 11), 'card')
    return v


@model
def whiteboard():
    v = new('whiteboard', 20, 6, 15)
    for x in (-9, 8):
        v.paint(cells(v, x, x + 1, -0.5, 0.5, 0, 14), 'grey2')
        v.paint(cells(v, x, x + 1, -3, 3, 0, 1), 'grey1')
    v.paint(cells(v, -9, 9, -0.5, 0.5, 5, 15), 'grey2')
    board = cells(v, -8, 8, -1.5, -0.5, 6, 14)
    v.paint(board, 'white')
    for k, tall in enumerate((2, 3, 2, 5, 4, 6)):
        v.paint(cells(v, -7 + k, -6 + k, -1.5, -0.5, 7 + tall, 8 + tall), 'red2')
    for x, z, colour in ((2, 11, 'yellow'), (5, 11, 'pink'), (2, 8, 'green3'), (5, 8, 'yellow')):
        v.paint(cells(v, x, x + 2, -1.5, -0.5, z, z + 2), colour)
    v.paint(cells(v, -6, 6, -2, -1, 5, 6), 'grey1')
    return v


@model
def plant():
    v = new('plant', 8, 8, 10, 16)
    v.paint(cells(v, -2, 2, -2, 2, 0, 3), 'clay')
    v.paint(cells(v, -1, 1, -1, 1, 2, 3), 'wood1')
    leaves(v, (0, 0, 3), 4, 7)
    return v


@model
def plant_tall():
    v = new('plant_tall', 12, 12, 18, 17)
    v.paint(cells(v, -2.5, 2.5, -2.5, 2.5, 0, 4), 'white')
    v.paint(cells(v, -2.5, 2.5, -2.5, 2.5, 3, 4), 'blue2')
    v.paint(cells(v, -0.5, 0.5, -0.5, 0.5, 4, 11), 'wood1')
    leaves(v, (0, 0, 9), 6, 9)
    return v


@model
def planter():
    v = new('planter', 18, 5, 8, 18)
    v.paint(cells(v, -9, 9, -2, 3, 0, 4), 'white')
    v.paint(cells(v, -9, 9, -2, 3, 0, 1), 'grey2')
    green = cells(v, -8, 8, -1, 2, 4, 8) & (v.rng.random(v.grid.shape) < 0.75) & (v.z < 5 + v.rng.integers(1, 4, (18, 5))[:, :, None])
    v.paint(green, ['green1', 'green2', 'green3'], [2, 4, 2])
    v.paint(v.top_of(green) & (v.rng.random(v.grid.shape) < 0.3), ['red2', 'yellow', 'pink', 'white'])
    return v


@model
def cactus():
    v = new('cactus', 8, 4, 8)
    v.paint(cells(v, -2, 2, -2, 2, 0, 2), 'clay')
    v.paint(cells(v, -1, 1, -1, 1, 2, 8), 'green2')
    v.paint(cells(v, -3, -1, -1, 1, 4, 5) | cells(v, -3, -2, -1, 1, 5, 7) | cells(v, 1, 3, -1, 1, 3, 4) | cells(v, 2, 3, -1, 1, 4, 6), 'green2')
    v.paint(cells(v, -1, 0, -1, 0, 2, 8) | cells(v, -3, -2, -1, 0, 5, 7), 'green1')
    v.paint(cells(v, 0, 1, 0, 1, 7, 8), 'pink')
    return v


@model
def floor_lamp():
    v = new('floor_lamp', 5, 5, 15)
    v.paint(cells(v, -2, 2, -2, 2, 0, 1), 'black')
    v.paint(cells(v, -0.5, 0.5, -0.5, 0.5, 1, 12), 'grey2')
    v.paint(cells(v, -2.5, 2.5, -2.5, 2.5, 11, 12) | cells(v, -2, 2, -2, 2, 12, 14) | cells(v, -1, 1, -1, 1, 14, 15), 'lamp')
    return v


@model
def bin():
    v = new('bin', 4, 4, 4)
    v.paint(cells(v, -1.5, 1.5, -1.5, 1.5, 0, 3) | cells(v, -2, 2, -2, 2, 2, 3), 'grey2')
    v.paint(cells(v, -1, 1, -1, 1, 3, 4), 'white')
    return v


def carpet(v, half_x, half_y, field, border, motif):
    v.paint(cells(v, -half_x, half_x, -half_y, half_y, 0, 1), border)
    v.paint(cells(v, -half_x + 2, half_x - 2, -half_y + 2, half_y - 2, 0, 1), field)
    diamonds = ((np.abs((v.x % 8) - 4) + np.abs((v.y % 8) - 4)) < 2) & cells(v, -half_x + 3, half_x - 3, -half_y + 3, half_y - 3, 0, 1)
    v.paint(diamonds, motif)
    v.paint(cells(v, -half_x + 1, half_x - 1, -half_y + 1, half_y - 1, 0, 1) & ~cells(v, -half_x + 2, half_x - 2, -half_y + 2, half_y - 2, 0, 1), motif)


@model
def rug():
    v = new('rug', 24, 16, 1)
    carpet(v, 12, 8, 'red2', 'red1', 'yellow')
    return v


@model
def rug_large():
    v = new('rug_large', 40, 28, 1)
    carpet(v, 20, 14, 'blue2', 'blue1', 'white')
    return v


@model
def tv():
    v = new('tv', 12, 7, 13)
    v.paint(cells(v, -6, 6, -2, 3, 0, 4), 'wood2')
    v.paint(cells(v, -5, 5, -2, -1, 1, 3), 'wood1')
    v.paint(cells(v, -5, 5, -2, 3, 4, 11), 'wood1')
    v.paint(cells(v, -4, 2, -2, -1, 5, 10), 'black')
    for k, colour in enumerate(('white', 'yellow', 'teal', 'green2', 'pink', 'red2')):
        v.paint(cells(v, -4 + k, -3 + k, -2, -1, 6, 10), colour if k else 'screen_blue')
    v.paint(cells(v, 3, 4, -2, -1, 8, 9) | cells(v, 3, 4, -2, -1, 6, 7), 'grey3')
    v.paint(v.line((0, 1, 11), (-3, 1, 13), 0.5) | v.line((0, 1, 11), (3, 1, 13), 0.5), 'grey2')
    return v


@model
def table_football():
    v = new('table_football', 18, 12, 8)
    v.paint(cells(v, -8, 8, -4, 4, 4, 5), 'green2')
    v.paint(cells(v, -8, 8, -4, 4, 5, 7) & ~cells(v, -7, 7, -3, 3, 5, 7), 'wood2')
    v.paint(cells(v, -0.5, 0.5, -3, 3, 4, 5), 'white')
    for x in (-8, 7):
        for y in (-4, 3):
            v.paint(cells(v, x, x + 1, y, y + 1, 0, 4), 'wood1')
    for k, x in enumerate((-5, -2, 2, 5)):
        v.paint(cells(v, x, x + 1, -6, 6, 6, 7), 'grey3')
        v.paint(cells(v, x, x + 1, -6, -5, 6, 7) | cells(v, x, x + 1, 5, 6, 6, 7), 'black')
        for y in (-2, 1):
            v.paint(cells(v, x, x + 1, y, y + 1, 5, 7), 'red2' if k % 2 == 0 else 'blue2')
    return v


@model
def reception():
    v = new('reception', 28, 16, 11, 19)
    v.paint(cells(v, -13, 13, -6, -2, 0, 8), 'wood2')
    v.paint(cells(v, -13, -9, -2, 6, 0, 8), 'wood2')
    v.paint(cells(v, -14, 14, -7, -2, 8, 9) | cells(v, -14, -9, -2, 7, 8, 9), 'beige2')
    v.paint(cells(v, -13, 13, -6, -5, 1, 7) & (v.x.astype(int) % 6 != 0), 'wood3')
    v.paint(cells(v, -3, 3, -7, -6, 2, 7) & (np.abs(v.x) + np.abs(v.z - 4.5) < 3.2), 'yellow')
    v.paint(cells(v, -9, 10, -2, 1, 5, 6), 'wood3')
    computer(v, 2, -2, -1, 'screen_green')
    v.paint(cells(v, 9, 10, -5, -4, 9, 10), 'yellow')
    v.paint(cells(v, -12, -10, 3, 5, 9, 10), 'clay')
    leaves(v, (-11, 4, 10), 2, 2)
    chair(v, 2, 4, 1, 'red2')
    return v


@model
def lockers():
    v = new('lockers', 16, 5, 15)
    for k, colour in enumerate(('blue2', 'red2', 'yellow', 'green2')):
        x = -8 + k * 4
        v.paint(cells(v, x, x + 4, -2, 3, 0, 15), 'grey2')
        v.paint(cells(v, x + 0.5, x + 3.5, -2, -1, 1, 14), colour)
        v.paint(cells(v, x + 1, x + 3, -2, -1, 11, 13) & (v.z.astype(int) % 2 == 1), 'black')
        v.paint(cells(v, x + 2.5, x + 3.5, -3, -2, 6, 8) & (v.x > x + 2.6), 'grey3')
    return v


@model
def boxes():
    v = new('boxes', 12, 10, 8)
    for lo, hi in (((-6, -4, 0), (0, 2, 5)), ((1, -3, 0), (6, 3, 4)), ((-4, -3, 5), (0, 1, 8)), ((-5, 2, 0), (-1, 5, 3))):
        box = v.box(lo, hi)
        v.paint(box, 'card')
        v.paint(box & (np.abs(v.x - (lo[0] + hi[0]) / 2) < 0.6) & (v.z >= hi[2] - 1), 'beige2')
    return v


for name, build in MODELS.items():
    if not ONLY or name in ONLY:
        build().save()
print('RETRO DONE', flush=True)

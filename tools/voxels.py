import math
from pathlib import Path

import bpy
import numpy as np

PER_METRE = 8
PREFIX = ''
PALETTE = {}
NAMES = []
OUT = Path('.')


def use(prefix, palette, out):
    """Sets the colours, as name: (sRGB, glow), and where pieces are saved."""
    global PREFIX, PALETTE, NAMES, OUT
    PREFIX, PALETTE, NAMES, OUT = prefix, palette, list(palette), out


def linear(rgb):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb)


def material(name):
    found = bpy.data.materials.get(PREFIX + name)
    if found:
        return found
    rgb, glow = PALETTE[name]
    made = bpy.data.materials.new(PREFIX + name)
    made.use_nodes = True
    bsdf = next(n for n in made.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*linear(rgb), 1.0)
    bsdf.inputs['Roughness'].default_value = 0.95
    if glow:
        bsdf.inputs['Emission Color'].default_value = (*linear(rgb), 1.0)
        bsdf.inputs['Emission Strength'].default_value = glow
    return made


class Voxels:
    """A block of cubes, eight to the metre. x runs right, y back and z up, with
    the ground at z = 0 and the piece's own centre at x = y = 0."""

    def __init__(self, name, wide, deep, tall, seed=1):
        self.name = name
        self.size = (wide, deep, tall)
        self.grid = np.zeros((wide, deep, tall), np.uint8)
        self.rng = np.random.default_rng(seed)
        x, y, z = np.indices((wide, deep, tall))
        self.x = x - wide / 2 + 0.5
        self.y = y - deep / 2 + 0.5
        self.z = z + 0.5

    def paint(self, where, colours, weights=None):
        """Fills cells with one colour, or a scatter of several."""
        if isinstance(colours, str):
            colours = [colours]
        picks = self.rng.choice(len(colours), self.grid.shape, p=None if weights is None else np.array(weights) / sum(weights))
        index = np.array([NAMES.index(c) + 1 for c in colours], np.uint8)[picks]
        self.grid[where] = index[where]

    def clear(self, where):
        self.grid[where] = 0

    def box(self, lo, hi):
        return ((self.x >= lo[0]) & (self.x < hi[0]) & (self.y >= lo[1]) & (self.y < hi[1]) & (self.z >= lo[2]) & (self.z < hi[2]))

    def ball(self, at, radii):
        if not isinstance(radii, tuple):
            radii = (radii, radii, radii)
        return ((self.x - at[0]) / radii[0]) ** 2 + ((self.y - at[1]) / radii[1]) ** 2 + ((self.z - at[2]) / radii[2]) ** 2 <= 1.0

    def rod(self, at, radius, z0, z1, top=None):
        t = np.clip((self.z - z0) / max(z1 - z0, 1e-6), 0, 1)
        r = radius + ((radius if top is None else top) - radius) * t
        return ((self.x - at[0]) ** 2 + (self.y - at[1]) ** 2 <= r * r) & (self.z >= z0) & (self.z < z1)

    def line(self, a, b, radius):
        a, b = np.array(a, float), np.array(b, float)
        ab = b - a
        t = np.clip(((self.x - a[0]) * ab[0] + (self.y - a[1]) * ab[1] + (self.z - a[2]) * ab[2]) / ab.dot(ab), 0, 1)
        return (self.x - a[0] - ab[0] * t) ** 2 + (self.y - a[1] - ab[1] * t) ** 2 + (self.z - a[2] - ab[2] * t) ** 2 <= radius * radius

    def rough(self, scale, seed_shift=0):
        """Smooth noise from -1 to 1, for breaking up edges."""
        rng = np.random.default_rng(self.rng.integers(1 << 30) + seed_shift)
        coarse = rng.uniform(-1, 1, tuple(int(math.ceil(s / scale)) + 2 for s in self.size))
        ix, iy, iz = (np.arange(s) / scale for s in self.size)
        out = np.zeros(self.size)
        fx, fy, fz = ix - np.floor(ix), iy - np.floor(iy), iz - np.floor(iz)
        x0, y0, z0 = ix.astype(int), iy.astype(int), iz.astype(int)
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    w = (np.where(dx, fx, 1 - fx)[:, None, None] * np.where(dy, fy, 1 - fy)[None, :, None] * np.where(dz, fz, 1 - fz)[None, None, :])
                    out += w * coarse[np.ix_(x0 + dx, y0 + dy, z0 + dz)]
        return out

    def top_of(self, where):
        """The cells of `where` with nothing above them."""
        above = np.zeros_like(self.grid, bool)
        above[:, :, :-1] = self.grid[:, :, 1:] > 0
        return where & (self.grid > 0) & ~above

    def save(self):
        solid = self.grid > 0
        verts, faces, colours = [], [], []
        corners = {
            (1, 0, 0): [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], (-1, 0, 0): [(0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1)],
            (0, 1, 0): [(1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)], (0, -1, 0): [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
            (0, 0, 1): [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, -1): [(0, 1, 0), (1, 1, 0), (1, 0, 0), (0, 0, 0)],
        }
        padded = np.pad(solid, 1)
        for (dx, dy, dz), quad in corners.items():
            beside = padded[1 + dx:padded.shape[0] - 1 + dx, 1 + dy:padded.shape[1] - 1 + dy, 1 + dz:padded.shape[2] - 1 + dz]
            cells = np.argwhere(solid & ~beside)
            if dz == -1:
                cells = cells[cells[:, 2] > 0]
            if not len(cells):
                continue
            base = len(verts) and sum(len(v) for v in verts)
            quad = np.array(quad)
            points = (cells[:, None, :] + quad[None, :, :]).reshape(-1, 3).astype(np.float64)
            points[:, 0] -= self.size[0] / 2
            points[:, 1] -= self.size[1] / 2
            verts.append(points / PER_METRE)
            faces.append(base + np.arange(len(cells) * 4).reshape(-1, 4))
            colours.append(self.grid[cells[:, 0], cells[:, 1], cells[:, 2]])
        verts, faces, colours = np.concatenate(verts), np.concatenate(faces), np.concatenate(colours)
        used = sorted(set(colours.tolist()))
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(verts.tolist(), [], faces.tolist())
        for index in used:
            mesh.materials.append(material(NAMES[index - 1]))
        slot = np.zeros(256, np.int32)
        slot[used] = np.arange(len(used))
        mesh.polygons.foreach_set('material_index', slot[colours])
        mesh.update()
        made = bpy.data.objects.new(self.name, mesh)
        keep = bpy.data.scenes.new(self.name)
        keep.collection.objects.link(made)
        folder = OUT / self.name
        folder.mkdir(parents=True, exist_ok=True)
        bpy.data.libraries.write(str(folder / f'{self.name}.blend'), {made}, fake_user=True)
        print('BUILT', self.name, len(faces) * 2, 'tris', len(used), 'colours', flush=True)

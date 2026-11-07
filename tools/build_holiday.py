import math, random, sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = Path(sys.argv[sys.argv.index('--') + 1]).resolve()


def material(name, rgb, rough=0.6, metal=0.0, glow=0.0):
    found = bpy.data.materials.get(name)
    if found:
        return found
    made = bpy.data.materials.new(name)
    made.use_nodes = True
    bsdf = next(n for n in made.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*rgb, 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if glow > 0.0:
        bsdf.inputs['Emission Color'].default_value = (*rgb, 1.0)
        bsdf.inputs['Emission Strength'].default_value = glow
    return made


class Model:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []

    def _paint(self, verts, mat, smooth):
        if mat not in self.slots:
            self.slots.append(mat)
        index = self.slots.index(mat)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = index
            face.smooth = smooth

    def sphere(self, mat, at, radius, squash=(1, 1, 1), segments=24):
        scale = Matrix.Diagonal((*squash, 1))
        made = bmesh.ops.create_uvsphere(self.bm, u_segments=segments, v_segments=max(8, segments // 2), radius=radius, matrix=Matrix.Translation(at) @ scale)
        self._paint(made['verts'], mat, True)
        return made['verts']

    def rod(self, mat, a, b, r1, r2=None, segments=12, smooth=True):
        a, b = Vector(a), Vector(b)
        along = b - a
        turn = along.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        made = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r1, radius2=r1 if r2 is None else r2,
                                     depth=along.length, matrix=Matrix.Translation((a + b) / 2) @ turn)
        self._paint(made['verts'], mat, smooth)

    def box(self, mat, at, size, turn=0.0):
        place = Matrix.Translation(at) @ Matrix.Rotation(turn, 4, 'Z') @ Matrix.Diagonal((*size, 1))
        made = bmesh.ops.create_cube(self.bm, size=1.0, matrix=place)
        self._paint(made['verts'], mat, False)
        return made['verts']

    def tube(self, mat, points, radius, segments=10):
        for a, b in zip(points, points[1:]):
            self.rod(mat, a, b, radius, segments=segments)
            self.sphere(mat, b, radius, segments=segments)

    def prism(self, mat, outline, y0, y1):
        front = [self.bm.verts.new((x, y0, z)) for x, z in outline]
        back = [self.bm.verts.new((x, y1, z)) for x, z in outline]
        self.bm.faces.new(front)
        self.bm.faces.new(list(reversed(back)))
        for i in range(len(outline)):
            j = (i + 1) % len(outline)
            self.bm.faces.new((front[j], front[i], back[i], back[j]))
        self._paint(front + back, mat, False)

    def save(self):
        bmesh.ops.rotate(self.bm, verts=list(self.bm.verts), cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi, 3, 'Z'))
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for slot in self.slots:
            mesh.materials.append(slot)
        made = bpy.data.objects.new(self.name, mesh)
        keep = bpy.data.scenes.new(self.name)
        keep.collection.objects.link(made)
        folder = OUT / self.name
        folder.mkdir(parents=True, exist_ok=True)
        bpy.data.libraries.write(str(folder / f'{self.name}.blend'), {made}, fake_user=True)
        print('HOLIDAY', self.name, flush=True)


def ring(radius, height, count, phase=0.0):
    return [Vector((math.cos(phase + math.tau * i / count) * radius, math.sin(phase + math.tau * i / count) * radius, height)) for i in range(count)]


def christmas_tree(name='xmas_tree'):
    rng = random.Random(25)
    m = Model(name)
    needles = material('fir_needles', (0.03, 0.17, 0.08), 0.8)
    bark = material('fir_bark', (0.13, 0.08, 0.05), 0.9)
    colours = [material('bauble_red', (0.65, 0.03, 0.04), 0.2, 0.4), material('bauble_gold', (0.85, 0.6, 0.15), 0.25, 0.9), material('bauble_blue', (0.07, 0.17, 0.55), 0.2, 0.4)]
    lit = material('tree_lights', (1.0, 0.75, 0.35), 0.4, 0.0, 6.0)
    star = material('tree_star', (1.0, 0.8, 0.3), 0.3, 0.6, 5.0)
    m.rod(bark, (0, 0, 0), (0, 0, 5.1), 0.17, 0.03)
    tiers = 9
    for tier in range(tiers):
        t = tier / (tiers - 1)
        height = 0.7 + t * 4.0
        reach = 1.75 * (1.0 - t) + 0.22
        count = int(18 - 10 * t)
        for tip in ring(reach, height - 0.4 * reach, count, tier * 0.37):
            m.rod(needles, (0, 0, height), tip, 0.28 * (1.0 - t * 0.55), 0.015, segments=7)
            side = tip * 0.72 + Vector((0, 0, 0.28 * height / 5.0))
            if rng.random() < 0.5:
                m.sphere(rng.choice(colours), tip + Vector((0, 0, -0.1)), 0.095, segments=12)
            elif rng.random() < 0.7:
                m.sphere(lit, side, 0.045, segments=8)
    m.sphere(star, (0, 0, 5.28), 0.2, (1, 1, 1.25), 8)
    m.rod(star, (0, 0, 5.16), (0, 0, 5.6), 0.08, 0.0, 6)
    m.rod(star, (-0.27, 0, 5.28), (0.27, 0, 5.28), 0.05, 0.0, 6)
    m.save()


def gift(m, at, size, paper, ribbon, turn=0.0):
    w, d, h = size
    centre = Vector(at) + Vector((0, 0, h / 2))
    m.box(paper, centre, size, turn)
    m.box(ribbon, centre, (w * 0.16, d * 1.015, h * 1.015), turn)
    m.box(ribbon, centre, (w * 1.015, d * 0.16, h * 1.015), turn)
    top = Vector(at) + Vector((0, 0, h))
    for side in (-1, 1):
        lobe = Matrix.Rotation(turn, 4, 'Z') @ Vector((side * w * 0.14, 0, h * 0.09))
        m.sphere(ribbon, top + lobe, w * 0.14, (1.1, 0.45, 0.8), 14)
    m.sphere(ribbon, top + Vector((0, 0, h * 0.05)), w * 0.05, segments=10)


def gifts():
    red = material('paper_red', (0.6, 0.04, 0.05), 0.45)
    green = material('paper_green', (0.04, 0.3, 0.13), 0.45)
    blue = material('paper_blue', (0.08, 0.2, 0.55), 0.45)
    gold = material('ribbon_gold', (0.85, 0.6, 0.15), 0.3, 0.8)
    white = material('ribbon_white', (0.85, 0.85, 0.82), 0.5)
    m = Model('gift_red')
    gift(m, (0, 0, 0), (1.2, 1.2, 0.95), red, gold)
    m.save()
    m = Model('gift_green')
    gift(m, (0, 0, 0), (1.5, 1.0, 0.8), green, white, 0.3)
    m.save()
    m = Model('gift_pile')
    gift(m, (0, 0, 0), (1.3, 1.3, 1.0), red, gold)
    gift(m, (1.25, 0.25, 0), (0.95, 0.95, 0.7), blue, white, 0.5)
    gift(m, (-0.2, -1.1, 0), (0.85, 0.85, 0.6), green, gold, -0.35)
    gift(m, (0.05, 0.0, 1.0), (0.7, 0.7, 0.55), blue, gold, 0.7)
    m.save()


def snowman():
    m = Model('snowman')
    snow = material('snow', (0.85, 0.88, 0.92), 0.85)
    coal = material('coal', (0.02, 0.02, 0.02), 0.5)
    carrot = material('carrot', (0.85, 0.3, 0.03), 0.7)
    scarf = material('scarf', (0.6, 0.04, 0.05), 0.85)
    hat = material('hat', (0.03, 0.03, 0.035), 0.5)
    stick = material('twig', (0.13, 0.08, 0.05), 0.9)
    m.sphere(snow, (0, 0, 0.5), 0.55, (1, 1, 0.93), 32)
    m.sphere(snow, (0, 0, 1.2), 0.4, (1, 1, 0.95), 32)
    m.sphere(snow, (0, 0, 1.72), 0.28, segments=32)
    for x, z in ((-0.1, 1.79), (0.1, 1.79)):
        m.sphere(coal, (x, 0.25, z), 0.03, segments=10)
    for i in range(5):
        a = -0.75 + i * 0.375
        m.sphere(coal, (math.sin(a) * 0.15, 0.255, 1.66 - math.cos(a) * 0.05 + 0.03), 0.018, segments=8)
    for z in (1.3, 1.1, 0.75):
        m.sphere(coal, (0, math.sqrt(max(0.0, (0.4 if z > 1 else 0.55) ** 2 - (z - (1.2 if z > 1 else 0.5)) ** 2)) - 0.005, z), 0.035, segments=10)
    m.rod(carrot, (0, 0.26, 1.72), (0.03, 0.55, 1.7), 0.04, 0.003)
    m.rod(scarf, (0, 0, 1.45), (0, 0, 1.53), 0.3, 0.27, 32)
    m.box(scarf, (0.15, 0.27, 1.27), (0.13, 0.05, 0.42), 0.15)
    m.rod(hat, (0, 0, 1.94), (0, 0, 1.96), 0.32, segments=32)
    m.rod(hat, (0, 0, 1.96), (0, 0, 2.28), 0.19, 0.2, 32)
    m.tube(stick, [(0.36, 0, 1.25), (0.72, 0.03, 1.5), (0.92, 0.03, 1.72)], 0.02)
    m.tube(stick, [(-0.36, 0, 1.25), (-0.72, -0.03, 1.48), (-0.95, -0.02, 1.42)], 0.02)
    m.save()


def candy_cane():
    m = Model('candy_cane')
    red = material('cane_red', (0.65, 0.03, 0.04), 0.25)
    white = material('cane_white', (0.85, 0.85, 0.83), 0.25)
    points = [Vector((0, 0, z * 0.14)) for z in range(0, 12)]
    for i in range(1, 13):
        a = math.pi * i / 12
        points.append(Vector((0.3 - math.cos(a) * 0.3, 0, 1.54 + math.sin(a) * 0.3)))
    for a, b, i in zip(points, points[1:], range(99)):
        colour = red if i % 2 else white
        m.rod(colour, a, b, 0.09, segments=16)
        m.sphere(colour, b, 0.09, segments=16)
    m.save()


def sleigh():
    m = Model('sleigh')
    body = material('sleigh_red', (0.55, 0.04, 0.05), 0.35)
    trim = material('sleigh_gold', (0.85, 0.6, 0.15), 0.3, 0.9)
    seat = material('sleigh_seat', (0.28, 0.02, 0.05), 0.8)
    for side in (-0.62, 0.62):
        rail = [(side, -1.45, 0.05), (side, 1.1, 0.05)]
        for i in range(1, 8):
            a = math.pi * i / 8
            rail.append((side, 1.1 + math.sin(a) * 0.5, 0.55 - math.cos(a) * 0.5))
        m.tube(trim, rail, 0.05, 8)
        m.rod(trim, (side, -0.8, 0.05), (side * 0.9, -0.8, 0.5), 0.04, segments=8)
        m.rod(trim, (side, 0.6, 0.05), (side * 0.9, 0.6, 0.5), 0.04, segments=8)
    m.box(body, (0, -0.1, 0.72), (1.25, 2.2, 0.48))
    m.box(body, (0, -1.1, 1.12), (1.25, 0.2, 0.9))
    m.box(body, (0, 1.03, 0.9), (1.25, 0.14, 0.85), 0.0)
    m.box(trim, (0, -0.1, 0.98), (1.29, 2.24, 0.05))
    m.box(seat, (0, -0.55, 1.05), (1.1, 0.75, 0.2))
    m.box(seat, (0, -0.96, 1.32), (1.1, 0.14, 0.6))
    paper = material('paper_green', (0.04, 0.3, 0.13), 0.45)
    ribbon = material('ribbon_gold', (0.85, 0.6, 0.15), 0.3, 0.8)
    gift(m, (0, 0.5, 0.96), (0.72, 0.72, 0.6), paper, ribbon, 0.25)
    m.save()


def wreath_arch():
    m = Model('wreath_arch')
    leaf = material('wreath_green', (0.03, 0.2, 0.08), 0.8)
    bow = material('bow_red', (0.65, 0.03, 0.04), 0.4)
    lit = material('arch_lights', (1.0, 0.75, 0.35), 0.4, 0.0, 6.0)
    rng = random.Random(7)
    path = []
    for i in range(0, 15):
        path.append(Vector((-1.6, 0, i * 0.15)))
    for i in range(1, 25):
        a = math.pi - math.pi * i / 25
        path.append(Vector((math.cos(a) * 1.6, 0, 2.1 + math.sin(a) * 1.6)))
    for i in range(14, -1, -1):
        path.append(Vector((1.6, 0, i * 0.15)))
    for p in path:
        for k in range(4):
            off = Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2)))
            m.sphere(leaf, p + off, rng.uniform(0.13, 0.2), (1, 1, 0.75), 8)
    for p in path[::3]:
        m.sphere(lit, p + Vector((0, -0.24, 0.05)), 0.05, segments=8)
    for at in (Vector((0, -0.24, 3.75)), Vector((-1.6, -0.24, 2.1)), Vector((1.6, -0.24, 2.1))):
        for side in (-1, 1):
            m.sphere(bow, at + Vector((side * 0.17, 0, 0)), 0.18, (1.1, 0.4, 0.75), 12)
        m.sphere(bow, at, 0.07, segments=10)
    m.save()


def ornament(name, shell):
    m = Model(name)
    cap = material('ornament_cap', (0.85, 0.6, 0.15), 0.3, 0.9)
    band = material('ornament_band', (0.85, 0.82, 0.75), 0.35, 0.5)
    m.sphere(shell, (0, 0, 0.55), 0.55, segments=40)
    m.rod(band, (0, 0, 0.5), (0, 0, 0.62), 0.555, segments=40)
    m.rod(cap, (0, 0, 1.06), (0, 0, 1.17), 0.12, 0.1, 16)
    m.tube(cap, [(0, -0.05, 1.17), (0, -0.05, 1.24), (0, 0.05, 1.24), (0, 0.05, 1.17)], 0.015, 8)
    m.save()


def gingerbread_hut():
    m = Model('gingerbread_hut')
    cookie = material('gingerbread', (0.32, 0.13, 0.04), 0.8)
    icing = material('icing', (0.86, 0.85, 0.82), 0.5)
    door = material('hut_door', (0.45, 0.04, 0.05), 0.5)
    window = material('hut_window', (1.0, 0.72, 0.3), 0.4, 0.0, 3.0)
    colours = [material('gum_red', (0.65, 0.03, 0.04), 0.25), material('gum_green', (0.05, 0.4, 0.13), 0.25), material('gum_yellow', (0.85, 0.6, 0.05), 0.25)]
    m.box(cookie, (0, 0, 1.0), (3.2, 2.6, 2.0))
    m.prism(cookie, [(-1.6, 2.0), (0, 3.25), (1.6, 2.0)], -1.3, 1.3)
    for side in (-1, 1):
        m.prism(icing, [(side * 1.85, 1.82), (0, 3.3), (0, 3.48), (side * 1.85, 2.0)], -1.55, 1.55)
    m.rod(icing, (0, -1.55, 3.45), (0, 1.55, 3.45), 0.09, segments=10)
    m.box(door, (0, 1.32, 0.62), (0.75, 0.07, 1.24))
    m.sphere(colours[2], (0.26, 1.37, 0.65), 0.05, segments=10)
    for x in (-1.05, 1.05):
        m.box(window, (x, 1.32, 1.15), (0.55, 0.05, 0.55))
        m.box(icing, (x, 1.35, 1.15), (0.63, 0.03, 0.06))
        m.box(icing, (x, 1.35, 1.15), (0.06, 0.03, 0.63))
    m.box(window, (0, 1.32, 2.45), (0.42, 0.05, 0.42))
    for z in (0.04, 1.97):
        m.box(icing, (0, 0, z), (3.3, 2.7, 0.08))
    rng = random.Random(4)
    for x in (-1.3, -0.65, 0.65, 1.3):
        m.sphere(rng.choice(colours), (x, 1.34, 1.95), 0.11, (1, 0.7, 1), 12)
    for y in (-1.2, -0.6, 0.0, 0.6, 1.2):
        for side in (-1, 1):
            for t in (0.33, 0.72):
                m.sphere(rng.choice(colours), (side * t * 1.85, y, 3.5 - t * 1.48), 0.11, (1, 1, 0.75), 12)
    m.box(cookie, (1.0, -0.5, 3.1), (0.45, 0.45, 1.0))
    m.box(icing, (1.0, -0.5, 3.6), (0.53, 0.53, 0.09))
    m.save()


def pumpkin_body(m, skin, stem, radius=0.5, ribs=11):
    for a in ring(radius * 0.55, radius * 0.82, ribs):
        m.sphere(skin, a, radius * 0.5, (0.72, 0.72, 1.55), 20)
    m.sphere(skin, (0, 0, radius * 0.82), radius * 0.82, (1, 1, 0.85), 24)
    m.rod(stem, (0, 0, radius * 1.5), (radius * 0.08, radius * 0.04, radius * 2.0), radius * 0.2, radius * 0.11, 8)


def pumpkins():
    skin = material('pumpkin_skin', (0.85, 0.3, 0.03), 0.55)
    stem = material('pumpkin_stem', (0.16, 0.22, 0.05), 0.85)
    m = Model('pumpkin')
    pumpkin_body(m, skin, stem)
    m.save()
    m = Model('jack_o_lantern')
    glow = material('lantern_glow', (1.0, 0.55, 0.1), 0.4, 0.0, 4.0)
    pumpkin_body(m, skin, stem)
    for x in (-0.17, 0.17):
        m.prism(glow, [(x - 0.09, 0.46), (x, 0.62), (x + 0.09, 0.46)], 0.38, 0.47)
    m.prism(glow, [(-0.045, 0.36), (0, 0.44), (0.045, 0.36)], 0.42, 0.5)
    for i in range(-3, 4):
        x = i * 0.07
        m.box(glow, (x, 0.45 - abs(x) * 0.28, 0.23 + abs(x) * 0.45 + (0.02 if i % 2 else -0.02)), (0.06, 0.07, 0.08 if i % 2 else 0.12))
    m.save()


def hay_bale():
    m = Model('hay_bale')
    straw = [material('straw_a', (0.72, 0.53, 0.2), 0.95), material('straw_b', (0.56, 0.4, 0.14), 0.95), material('straw_c', (0.8, 0.63, 0.28), 0.95)]
    twine = material('twine', (0.25, 0.14, 0.07), 0.9)
    rng = random.Random(11)
    m.box(straw[1], (0, 0, 0.5), (1.5, 0.95, 0.96))
    for i in range(260):
        side = rng.choice((0, 1, 2))
        pick = rng.choice(straw)
        at = Vector((rng.uniform(-0.76, 0.76), rng.uniform(-0.49, 0.49), rng.uniform(0.03, 0.99)))
        if side == 0:
            at.z = rng.choice((0.02, 0.99))
        elif side == 1:
            at.y = rng.choice((-0.49, 0.49))
        else:
            at.x = rng.choice((-0.76, 0.76))
        m.rod(pick, at, at + Vector((rng.uniform(-0.16, 0.16), rng.uniform(-0.1, 0.1), rng.uniform(-0.08, 0.08))), 0.014, 0.004, 4)
    for x in (-0.4, 0.4):
        m.box(twine, (x, 0, 0.5), (0.04, 0.99, 1.0))
    m.save()


def scarecrow():
    m = Model('scarecrow')
    pole = material('scarecrow_pole', (0.2, 0.13, 0.07), 0.9)
    burlap = material('burlap', (0.5, 0.38, 0.22), 0.95)
    shirt = material('scarecrow_shirt', (0.42, 0.13, 0.08), 0.9)
    hat = material('straw_hat', (0.28, 0.19, 0.08), 0.9)
    eyes = material('scarecrow_eyes', (0.02, 0.02, 0.02), 0.6)
    m.rod(pole, (0, 0, 0), (0, 0, 2.15), 0.05, segments=8)
    m.rod(pole, (-0.95, 0, 1.55), (0.95, 0, 1.55), 0.04, segments=8)
    m.rod(shirt, (0, 0, 0.85), (0, 0, 1.68), 0.34, 0.17, 12, False)
    m.rod(shirt, (0, 0, 1.55), (0.85, 0, 1.53), 0.12, 0.17, 10, False)
    m.rod(shirt, (0, 0, 1.55), (-0.85, 0, 1.53), 0.12, 0.17, 10, False)
    m.sphere(burlap, (0, 0, 1.95), 0.24, segments=18)
    m.rod(burlap, (0, 0, 1.68), (0, 0, 1.76), 0.16, 0.08, 10)
    for x in (-0.09, 0.09):
        m.sphere(eyes, (x, 0.21, 2.0), 0.03, segments=8)
    m.rod(eyes, (-0.09, 0.22, 1.86), (0.09, 0.22, 1.86), 0.012, segments=6)
    m.rod(hat, (0, 0, 2.1), (0, 0, 2.13), 0.42, 0.42, 20)
    m.rod(hat, (0, 0, 2.13), (0.02, 0, 2.5), 0.21, 0.03, 14)
    m.save()


def gravestones():
    stone = material('grave_stone', (0.27, 0.27, 0.26), 0.9)
    moss = material('grave_moss', (0.1, 0.17, 0.06), 0.95)
    carved = material('grave_carved', (0.09, 0.09, 0.09), 0.95)
    m = Model('gravestone')
    m.box(stone, (0, 0, 0.45), (0.75, 0.16, 0.9))
    m.rod(stone, (0, -0.08, 0.9), (0, 0.08, 0.9), 0.375, segments=24, smooth=True)
    m.box(stone, (0, 0, 0.05), (0.95, 0.38, 0.1))
    m.box(carved, (0, 0.085, 0.84), (0.09, 0.012, 0.44))
    m.box(carved, (0, 0.085, 0.9), (0.3, 0.012, 0.08))
    m.sphere(moss, (-0.28, 0.02, 0.12), 0.14, (1.3, 0.8, 0.5), 10)
    m.save()
    m = Model('grave_cross')
    m.box(stone, (0, 0, 0.72), (0.2, 0.14, 1.45))
    m.box(stone, (0, 0, 1.0), (0.8, 0.14, 0.2))
    m.box(stone, (0, 0, 0.05), (0.7, 0.4, 0.1))
    m.save()


def cauldron():
    m = Model('cauldron')
    iron = material('cauldron_iron', (0.03, 0.03, 0.035), 0.45, 0.7)
    brew = material('cauldron_brew', (0.1, 0.6, 0.13), 0.3, 0.0, 1.5)
    wood = material('cauldron_wood', (0.11, 0.07, 0.04), 0.9)
    m.sphere(iron, (0, 0, 0.55), 0.48, (1, 1, 0.82), 32)
    m.rod(iron, (0, 0, 0.84), (0, 0, 0.97), 0.42, 0.45, 32)
    m.rod(brew, (0, 0, 0.965), (0, 0, 0.98), 0.4, segments=32)
    for a in ring(0.16, 1.0, 5, 0.6):
        m.sphere(brew, a, 0.07, (1, 1, 0.65), 10)
    for a in ring(0.33, 0.08, 3):
        m.rod(iron, a, a * 0.8 + Vector((0, 0, 0.25)), 0.05, segments=8)
    m.tube(iron, [(-0.46, 0, 0.87), (-0.54, 0, 0.92), (-0.46, 0, 0.97)], 0.015, 8)
    m.tube(iron, [(0.46, 0, 0.87), (0.54, 0, 0.92), (0.46, 0, 0.97)], 0.015, 8)
    for a in ring(0.42, 0.05, 5, 0.3):
        m.rod(wood, a, -a + Vector((0, 0, 0.1)), 0.04, segments=6)
    m.save()


def spooky_tree():
    m = Model('tree_spooky')
    bark = material('spooky_bark', (0.07, 0.055, 0.05), 0.95)
    rng = random.Random(31)

    def limb(start, direction, length, radius, depth):
        points = [start]
        at = start
        for _ in range(4):
            direction = (direction + Vector((rng.uniform(-.35, .35), rng.uniform(-.35, .35), rng.uniform(-.1, .3)))).normalized()
            at = at + direction * length / 4
            points.append(at)
        for i, (a, b) in enumerate(zip(points, points[1:])):
            r1 = radius * (1 - i * 0.16)
            m.rod(bark, a, b, r1, radius * (1 - (i + 1) * 0.16), 9)
            m.sphere(bark, b, radius * (1 - (i + 1) * 0.16), segments=9)
        if depth > 0:
            for _ in range(2 if depth < 3 else 3):
                turn = (direction + Vector((rng.uniform(-.9, .9), rng.uniform(-.9, .9), rng.uniform(-.25, .5)))).normalized()
                limb(points[-1], turn, length * 0.68, radius * 0.5, depth - 1)

    limb(Vector((0, 0, 0)), Vector((0, 0, 1)), 2.4, 0.3, 4)
    for a in ring(0.32, 0.03, 6, 0.4):
        m.rod(bark, Vector((0, 0, 0.3)), a * 2.3, 0.14, 0.02, 7)
    m.save()


def paper_lanterns():
    m = Model('paper_lanterns')
    post = material('lantern_post', (0.15, 0.09, 0.05), 0.85)
    rope = material('lantern_rope', (0.13, 0.11, 0.09), 0.9)
    cap = material('lantern_cap', (0.03, 0.03, 0.03), 0.5)
    colours = [material('paper_glow_red', (0.95, 0.18, 0.07), 0.6, 0.0, 3.5), material('paper_glow_gold', (1.0, 0.65, 0.2), 0.6, 0.0, 3.5), material('paper_glow_rose', (0.95, 0.3, 0.3), 0.6, 0.0, 3.5)]
    for x in (-1.7, 1.7):
        m.rod(post, (x, 0, 0), (x, 0, 2.6), 0.05, segments=8)
    line = [(x * 0.1, 0, 2.52 - (1 - (x / 17) ** 2) * 0.32) for x in range(-17, 18)]
    m.tube(rope, line, 0.01, 6)
    for x, colour in zip((-1.05, 0, 1.05), colours):
        z = 2.52 - (1 - (x / 1.7) ** 2) * 0.32
        m.rod(rope, (x, 0, z), (x, 0, z - 0.14), 0.008, segments=5)
        m.sphere(colour, (x, 0, z - 0.42), 0.27, (1, 1, 0.95), 18)
        m.rod(cap, (x, 0, z - 0.19), (x, 0, z - 0.14), 0.09, segments=10)
        m.rod(cap, (x, 0, z - 0.7), (x, 0, z - 0.65), 0.09, segments=10)
    m.save()


def bunting():
    m = Model('bunting')
    post = material('bunting_post', (0.2, 0.13, 0.07), 0.85)
    rope = material('bunting_rope', (0.75, 0.72, 0.65), 0.9)
    flags = [material('flag_red', (0.65, 0.05, 0.05), 0.8), material('flag_yellow', (0.85, 0.6, 0.05), 0.8), material('flag_blue', (0.07, 0.2, 0.55), 0.8), material('flag_green', (0.05, 0.35, 0.13), 0.8)]
    for x in (-2.4, 2.4):
        m.rod(post, (x, 0, 0), (x, 0, 3.0), 0.06, segments=8)
    line = [(x * 0.2, 0, 2.9 - (1 - (x / 12) ** 2) * 0.5) for x in range(-12, 13)]
    m.tube(rope, line, 0.012, 6)
    for i, (x, _, z) in enumerate(line[1:-1:2]):
        verts = bmesh.ops.create_cone(m.bm, cap_ends=True, segments=3, radius1=0.18, radius2=0.18, depth=0.012,
                                      matrix=Matrix.Translation((x, 0, z - 0.14)) @ Matrix.Rotation(math.pi / 2, 4, 'X') @ Matrix.Rotation(-math.pi / 2, 4, 'Z') @ Matrix.Diagonal((1.2, 1.0, 1.0, 1)))['verts']
        m._paint(verts, flags[i % len(flags)], False)
    m.save()


def egg(name, shell, stripe, dots):
    m = Model(name)
    m.sphere(shell, (0, 0, 0.72), 0.5, (1, 1, 1.42), 40)
    for z, r in ((0.55, 0.49), (0.95, 0.455)):
        m.rod(stripe, (0, 0, z - 0.035), (0, 0, z + 0.035), r + 0.004, segments=40)
    for a in ring(0.49, 0.75, 9):
        m.sphere(dots, a, 0.055, (1, 1, 1), 10)
    m.save()


christmas_tree()
gifts()
snowman()
candy_cane()
sleigh()
wreath_arch()
ornament('ornament_red', material('ornament_shell_red', (0.65, 0.03, 0.04), 0.12, 0.5))
ornament('ornament_gold', material('ornament_shell_gold', (0.85, 0.6, 0.15), 0.15, 0.95))
gingerbread_hut()
pumpkins()
hay_bale()
scarecrow()
gravestones()
cauldron()
spooky_tree()
paper_lanterns()
bunting()
egg('easter_egg_pink', material('egg_pink', (0.82, 0.3, 0.45), 0.35), material('egg_cream', (0.85, 0.8, 0.6), 0.35), material('egg_blue', (0.15, 0.4, 0.7), 0.35))
egg('easter_egg_blue', material('egg_sky', (0.2, 0.5, 0.75), 0.35), material('egg_yellow', (0.85, 0.7, 0.15), 0.35), material('egg_rose', (0.8, 0.25, 0.4), 0.35))
print('HOLIDAY DONE', flush=True)

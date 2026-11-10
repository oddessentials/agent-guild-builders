import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = Path('.')


def use(out):
    """Sets where pieces are saved."""
    global OUT
    OUT = out


def linear(rgb):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb)


def material(name, rgb, rough=0.9, glow=0.0, metal=0.0):
    found = bpy.data.materials.get(name)
    if found:
        return found
    made = bpy.data.materials.new(name)
    made.use_nodes = True
    bsdf = next(n for n in made.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*linear(rgb), 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if glow > 0.0:
        bsdf.inputs['Emission Color'].default_value = (*linear(rgb), 1.0)
        bsdf.inputs['Emission Strength'].default_value = glow
    return made


class Model:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []
        self.frames = [Matrix.Identity(4)]

    def at(self, position, turn=0.0):
        self.frames.append(self.frames[-1] @ Matrix.Translation(position) @ Matrix.Rotation(turn, 4, 'Z'))
        return self

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.frames.pop()

    def _add(self, part, mat, smooth):
        if mat not in self.slots:
            self.slots.append(mat)
        index = self.slots.index(mat)
        for face in part.faces:
            face.material_index = index
            face.smooth = smooth
        mesh = bpy.data.meshes.new('part')
        part.to_mesh(mesh)
        part.free()
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)

    def box(self, mat, at, size, turn=0.0, round=0.02, tilt=None):
        place = self.frames[-1] @ Matrix.Translation(at) @ Matrix.Rotation(turn, 4, 'Z')
        if tilt:
            place = place @ Matrix.Rotation(tilt[1], 4, tilt[0])
        part = bmesh.new()
        bmesh.ops.create_cube(part, size=1.0, matrix=place @ Matrix.Diagonal((*size, 1)))
        round = min(round, min(size) * 0.45)
        if round > 0.0:
            bmesh.ops.bevel(part, geom=list(part.edges), offset=round, offset_type='OFFSET', segments=2, profile=0.5, affect='EDGES', clamp_overlap=True)
        self._add(part, mat, round > 0.0)

    def along(self, mat, a, b, size, round=0.02):
        a, b = Vector(a), Vector(b)
        turn = (b - a).to_track_quat('Y', 'Z').to_matrix().to_4x4()
        part = bmesh.new()
        bmesh.ops.create_cube(part, size=1.0, matrix=self.frames[-1] @ Matrix.Translation((a + b) / 2) @ turn @ Matrix.Diagonal((size[0], (b - a).length, size[1], 1)))
        if round > 0.0:
            bmesh.ops.bevel(part, geom=list(part.edges), offset=min(round, min(size) * 0.45), offset_type='OFFSET', segments=2, profile=0.5, affect='EDGES', clamp_overlap=True)
        self._add(part, mat, round > 0.0)

    def rod(self, mat, a, b, r1, r2=None, segments=20, round=0.0):
        a, b = Vector(a), Vector(b)
        turn = (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4()
        part = bmesh.new()
        bmesh.ops.create_cone(part, cap_ends=True, cap_tris=False, segments=segments, radius1=r1, radius2=r1 if r2 is None else r2,
                              depth=(b - a).length, matrix=self.frames[-1] @ Matrix.Translation((a + b) / 2) @ turn)
        if round > 0.0:
            rims = [e for e in part.edges if len(e.link_faces) == 2 and any(len(f.verts) > 4 for f in e.link_faces)]
            bmesh.ops.bevel(part, geom=rims, offset=round, offset_type='OFFSET', segments=2, profile=0.5, affect='EDGES', clamp_overlap=True)
        self._add(part, mat, True)

    def disc(self, mat, at, radius, height, r2=None, segments=28, round=0.015):
        at = Vector(at)
        self.rod(mat, at, at + Vector((0, 0, height)), radius, r2, segments, min(round, height * 0.45))

    def ball(self, mat, at, radius, squash=(1, 1, 1), turn=0.0, tilt=None, detail=2):
        place = self.frames[-1] @ Matrix.Translation(at) @ Matrix.Rotation(turn, 4, 'Z')
        if tilt:
            place = place @ Matrix.Rotation(tilt[1], 4, tilt[0])
        part = bmesh.new()
        bmesh.ops.create_icosphere(part, subdivisions=detail, radius=radius, matrix=place @ Matrix.Diagonal((*squash, 1)))
        self._add(part, mat, True)

    def save(self):
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
        print('BUILT', self.name, len(mesh.polygons), flush=True)

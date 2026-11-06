import json, re, shutil, sys, tempfile
from pathlib import Path
def inputs(args):
    if len(args) != 2:
        raise SystemExit('Usage: blender -b --factory-startup --python tools/build_kit.py -- <source folder> <raw meadow source JPG>')
    source, meadow = (Path(arg).resolve() for arg in args)
    if not source.is_dir():
        raise SystemExit(f'Source folder does not exist: {source}')
    if not meadow.is_file():
        raise SystemExit(f'Meadow source does not exist: {meadow}')
    if meadow.suffix.lower() not in ('.jpg', '.jpeg'):
        raise SystemExit('Use the original Meadow source JPG; the builder prepares the wrapping itself.')
    return source, meadow


if __name__ == '__main__':
    SOURCE, MEADOW = inputs(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

import bpy
import numpy as np
from mathutils import Vector
ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / 'kits' / 'meadow'
LICENCE = 'CC0-1.0 (Poly Haven)'

# id: (source, level of detail, label, group, scatter spacing in metres)
MODELS = {
    'tree_oak': ('island_tree_01', 1, 'Broadleaf tree', 'trees', 9),
    'tree_elm': ('island_tree_02', 1, 'Spreading tree', 'trees', 9),
    'tree_fir': ('fir_tree_01', 2, 'Fir', 'trees', 6),
    'tree_young': ('tree_small_02', 1, 'Young tree', 'trees', 6),
    'shrub_round': ('shrub_01', 1, 'Round shrub', 'plants', 3),
    'shrub_low': ('shrub_02', 1, 'Low shrub', 'plants', 2.5),
    'shrub_wild': ('shrub_04', 1, 'Wild shrub', 'plants', 2.5),
    'fern': ('fern_02', None, 'Fern', 'plants', 1.5),
    'grass': ('grass_medium_01', 2, 'Long grass', 'plants', 0.8),
    'dandelion': ('dandelion_01', 1, 'Dandelions', 'plants', 1.2),
    'celandine': ('celandine_01', 1, 'Celandines', 'plants', 1.0),
    'boulder': ('boulder_01', 2, 'Boulder', 'rocks', 6),
    'stone': ('stone_01', 1, 'Stone', 'rocks', 2),
    'stump': ('tree_stump_01', None, 'Tree stump', 'rocks', 6),
    'trunk': ('dead_tree_trunk', None, 'Fallen trunk', 'rocks', 10),
    'lantern': ('Lantern_01', None, 'Lantern', 'lights', 8),
    'barrel': ('Barrel_01', None, 'Barrel', 'props', 2),
    'table': ('WoodenTable_01', None, 'Table', 'props', 3),
    'bench': ('painted_wooden_bench', None, 'Bench', 'props', 3),
}
# Real-world heights in metres; a model is scaled to its height wherever it's used.
TARGET = {'tree_oak': 9, 'tree_elm': 8, 'tree_fir': 16, 'tree_young': 6, 'shrub_round': 1.4, 'shrub_low': 1.1, 'shrub_wild': 1.0,
          'fern': .7, 'grass': .5, 'dandelion': .25, 'celandine': .2, 'boulder': 1.6, 'stone': .35, 'stump': .6, 'trunk': .7,
          'lantern': .5, 'barrel': .9, 'table': .75, 'bench': .9}
# Lit at dusk only: watts, colour and height above the model's base, in Blender's units.
LIGHTS = {'lantern': {'watts': 60.0, 'color': [1.0, 0.6, 0.3], 'height': 0.3}}
GROUNDS = {
    'grass': ('leafy_grass', 'Meadow grass'), 'dirt': ('forest_ground_04', 'Forest floor'),
    'rock': ('rocky_trail', 'Rocky ground'), 'gravel': ('gravel_floor', 'Gravel'),
    'cobble': ('cobblestone_floor_04', 'Cobbles'),
}
SKIES = {
    'day': ('kloofendal_48d_partly_cloudy_puresky', 'Clear day', 0.9),
    'overcast': ('kloofendal_misty_morning_puresky', 'Misty morning', 0.9),
    'dusk': ('qwantani_dusk_2_puresky', 'Warm dusk', 0.5),
    'moon': ('qwantani_moonrise_puresky', 'Moonrise', 0.3),
}


def blend_of(name):
    found = sorted(SOURCE.joinpath(name).rglob('*.blend'))
    return found[0] if found else None


def parts_at(objects, lod, source):
    meshes = [o for o in objects if o is not None and o.type == 'MESH']
    meshes = [o for o in meshes if 'sphere' not in o.name.lower() and not any(m and 'sphere' in m.name.lower() for m in o.data.materials)]
    suffix = f'_LOD{lod}' if lod is not None else ''
    main = [o for o in meshes if o.name == source + suffix]
    if main:
        return main
    at_lod = [o for o in meshes if lod is None or o.name.endswith(suffix) or not re.search(r'_LOD\d+$', o.name)]
    variants = [o for o in at_lod if re.search(r'_a(_LOD\d+)?$', o.name)]
    return variants or at_lod


def standard_foliage(material):
    """Poly Haven's foliage runs through a node group the glTF exporter can't read,
    which would export leaves with no colour or cutout. Wire the same textures to a
    plain material; the bake's many lights give it translucency's soft look."""
    if material is None or not material.use_nodes:
        return
    tree = material.node_tree
    images = {}
    for n in tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image:
            for key in ('diff', 'alpha', 'rough', 'nor_gl'):
                if key in n.image.name.lower():
                    images.setdefault(key, n)
    has_group = any(n.type == 'GROUP' for n in tree.nodes)
    if 'alpha' not in images and not has_group:
        return
    if 'diff' not in images:
        return
    output = next(n for n in tree.nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output)
    bsdf = tree.nodes.new('ShaderNodeBsdfPrincipled')
    tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    tree.links.new(images['diff'].outputs['Color'], bsdf.inputs['Base Color'])
    if 'alpha' in images:
        tree.links.new(images['alpha'].outputs['Color'], bsdf.inputs['Alpha'])
    else:
        tree.links.new(images['diff'].outputs['Alpha'], bsdf.inputs['Alpha'])
    if 'rough' in images:
        tree.links.new(images['rough'].outputs['Color'], bsdf.inputs['Roughness'])
    if 'nor_gl' in images:
        normal = tree.nodes.new('ShaderNodeNormalMap')
        tree.links.new(images['nor_gl'].outputs['Color'], normal.inputs['Color'])
        tree.links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
    material.surface_render_method = 'DITHERED'


def export_model(kit_id, spec):
    name, lod, label, group, spacing = spec
    path = blend_of(name)
    if path is None:
        print('KIT missing', name)
        return None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(path), link=False) as (src, dst):
        dst.objects = list(src.objects)
    parts = parts_at(dst.objects, lod, name)
    scene = bpy.context.scene
    for o in parts:
        o.location = (0, 0, 0)
    for o in parts:
        scene.collection.objects.link(o)
    bpy.context.view_layer.update()
    low, high = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    tris = 0
    for o in parts:
        tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
        for corner in o.bound_box:
            c = o.matrix_world @ Vector(corner)
            low = Vector(map(min, low, c))
            high = Vector(map(max, high, c))
    for material in {m for o in parts for m in o.data.materials}:
        standard_foliage(material)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    out = KIT / 'models' / f'{kit_id}.glb'
    bpy.ops.export_scene.gltf(filepath=str(out), use_selection=True, export_format='GLB', export_image_format='WEBP',
                              export_image_quality=85, export_animations=False, export_cameras=False, export_lights=False)
    target = TARGET[kit_id]
    size = max(high.z - min(low.z, 0), .001)
    entry = {'label': label, 'group': group, 'spacing': spacing, 'height': target,
             'radius': round(max(high.x - low.x, high.y - low.y) / 2 * target / size, 2), 'triangles': tris,
             'source': name, 'licence': LICENCE, 'bytes': out.stat().st_size}
    if kit_id in LIGHTS:
        entry['light'] = LIGHTS[kit_id]
    print('KIT', kit_id, tris, 'tris', entry['height'], 'm', entry['bytes'] // 1024, 'KiB', flush=True)
    return entry


def write_meadow_texture(source, destination):
    img = bpy.data.images.load(str(source))
    w, h = img.size
    if min(w, h) <= 0:
        bpy.data.images.remove(img)
        raise RuntimeError(f'Meadow source could not be read: {source}')
    pixels = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    for axis, length in ((1, w), (0, h)):
        weight = np.sin(np.pi * (np.arange(length) + .5) / length) ** 2
        weight = weight.reshape((1, length, 1) if axis == 1 else (length, 1, 1))
        pixels = pixels * weight + np.roll(pixels, length // 2, axis) * (1 - weight)
    tile = bpy.data.images.new('meadow_tile', w, h)
    tile.pixels[:] = pixels.ravel()
    with tempfile.TemporaryDirectory(dir=destination.parent) as folder:
        tile_path = str(Path(folder) / 'meadow.png')
        tile.filepath_raw, tile.file_format = tile_path, 'PNG'
        tile.save()
        bpy.data.images.remove(tile)
        wrapped = bpy.data.images.load(tile_path)
        scene = bpy.context.scene
        scene.render.image_settings.file_format = 'JPEG'
        scene.render.image_settings.quality = 90
        wrapped.save_render(str(destination), scene=scene)
        bpy.data.images.remove(wrapped)


def main():
    meadow = bpy.data.images.load(str(MEADOW))
    if min(meadow.size) <= 0:
        raise RuntimeError(f'Meadow texture could not be read: {MEADOW}')
    bpy.data.images.remove(meadow)
    (KIT / 'models').mkdir(parents=True, exist_ok=True)
    (KIT / 'textures').mkdir(parents=True, exist_ok=True)
    (KIT / 'skies').mkdir(parents=True, exist_ok=True)
    kit = {'id': 'meadow', 'title': 'Meadow', 'models': {}, 'grounds': {}, 'skies': {}}
    for key, spec in MODELS.items():
        entry = export_model(key, spec)
        if entry:
            kit['models'][key] = entry
    for key, (name, label) in GROUNDS.items():
        for m in ('diff', 'nor_gl', 'rough'):
            shutil.copyfile(SOURCE / name / f'{name}_{m}_2k.jpg', KIT / 'textures' / f'{key}_{m}.jpg')
        kit['grounds'][key] = {'label': label, 'source': name, 'licence': LICENCE}
    write_meadow_texture(MEADOW, KIT / 'textures' / 'grass_diff.jpg')
    kit['grounds']['grass'].update({'source': 'agent-guild concept-art/guild-yard/env/textures/meadow.jpg',
                                    'licence': 'AGPL-3.0-only (Agent Guild)', 'note': 'Generated locally for the shipped Yard worlds; see ART.md in agent-guild.'})
    for key, (name, label, strength) in SKIES.items():
        shutil.copyfile(SOURCE / name / f'{name}_1k.hdr', KIT / 'skies' / f'{key}.hdr')
        kit['skies'][key] = {'label': label, 'strength': strength, 'source': name, 'licence': LICENCE}
    (KIT / 'kit.json').write_text(json.dumps(kit, indent=1) + '\n', encoding='utf-8', newline='\n')
    print('KIT done', len(kit['models']), 'models')


if __name__ == '__main__':
    main()

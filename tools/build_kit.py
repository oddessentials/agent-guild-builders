import json, re, shutil, sys, tempfile
from pathlib import Path
def inputs(args):
    if len(args) < 2:
        raise SystemExit('Usage: blender -b --factory-startup --python tools/build_kit.py -- <source folder> <raw meadow source JPG> [more source folders]')
    source, meadow, *more = (Path(arg).resolve() for arg in args)
    for folder in (source, *more):
        if not folder.is_dir():
            raise SystemExit(f'Source folder does not exist: {folder}')
    if not meadow.is_file():
        raise SystemExit(f'Meadow source does not exist: {meadow}')
    if meadow.suffix.lower() not in ('.jpg', '.jpeg'):
        raise SystemExit('Use the original Meadow source JPG; the builder prepares the wrapping itself.')
    return source, meadow, more


if __name__ == '__main__':
    SOURCE, MEADOW, MORE_SOURCES = inputs(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])

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
    'snag': ('dead_quiver_trunk', 1, 'Dead snag', 'trees', 3),
    'gazania': ('flower_gazania', 1, 'Gazanias', 'plants', 1.2),
    'ursinia': ('flower_ursinia', 1, 'Ursinias', 'plants', 1.2),
    'empodium': ('flower_empodium', 1, 'Empodium', 'plants', 1.2),
    'stinkkruid': ('flower_stinkkruid', 1, 'Yellow daisies', 'plants', 1.2),
    'potted_plant': ('potted_plant_01', None, 'Potted plant', 'plants', 1.5),
    'planter_low': ('planter_box_01', None, 'Low planter', 'plants', 1.5),
    'planter_tall': ('planter_box_03', None, 'Tall planter', 'plants', 1.5),
    'clay_pot': ('planter_pot_clay', None, 'Clay pot', 'plants', 1),
    'rock_face': ('rock_face_01', None, 'Rock face', 'rocks', 8),
    'rock_wall': ('rock_face_02', None, 'Rock outcrop', 'rocks', 6),
    'mossy_rocks': ('rock_moss_set_01', None, 'Mossy rocks', 'rocks', 6),
    'stump_old': ('tree_stump_02', None, 'Old stump', 'rocks', 3),
    'trunk_old': ('dead_tree_trunk_02', 1, 'Old log', 'rocks', 6),
    'street_lamp': ('street_lamp_01', None, 'Street lamp', 'lights', 8),
    'lantern_wood': ('wooden_lantern_01', None, 'Wooden lantern', 'lights', 4),
    'lantern_brass': ('brass_diya_lantern', None, 'Brass lantern', 'lights', 3),
    'oil_lamp': ('vintage_oil_lamp', None, 'Oil lamp', 'lights', 3),
    'candles': ('brass_candleholders', None, 'Candleholders', 'lights', 3),
    'candlestick': ('wooden_candlestick', None, 'Candlestick', 'lights', 2),
    'fire_pit': ('stone_fire_pit', None, 'Fire pit', 'lights', 6),
    'barrel_stove': ('barrel_stove', 1, 'Barrel stove', 'lights', 4),
    'barrel_dark': ('Barrel_02', None, 'Dark barrel', 'props', 2),
    'barrel_rusty': ('barrel_03', None, 'Rusty barrel', 'props', 2),
    'wine_barrel': ('wine_barrel_01', None, 'Wine barrel', 'props', 2),
    'crate': ('wooden_crate_01', None, 'Crate', 'props', 2),
    'crate_long': ('wooden_crate_02', None, 'Long crate', 'props', 2),
    'crate_army': ('old_military_crate', None, 'Army crate', 'props', 3),
    'crate_ammo': ('wooden_military_crate', None, 'Supply crate', 'props', 2),
    'treasure_chest': ('treasure_chest', None, 'Treasure chest', 'props', 2),
    'basket': ('wicker_basket_01', None, 'Basket', 'props', 1),
    'basket_tall': ('wicker_basket_02', None, 'Tall basket', 'props', 1),
    'bucket': ('wooden_bucket_01', None, 'Bucket', 'props', 1),
    'watering_can': ('watering_can_metal_01', None, 'Watering can', 'props', 1),
    'trash_can': ('metal_trash_can', None, 'Bins', 'props', 3),
    'cardboard_box': ('cardboard_box_01', None, 'Cardboard box', 'props', 1),
    'tool_cart': ('tool_cart', None, 'Tool cart', 'props', 3),
    'tool_chest': ('metal_tool_chest', None, 'Tool chest', 'props', 2),
    'ladder': ('ladder_sectioned_01', None, 'Ladder', 'props', 2),
    'spinning_wheel': ('spinning_wheel_01', None, 'Spinning wheel', 'props', 2),
    'big_pot': ('ceramic_pot', None, 'Big pot', 'props', 1.5),
    'brass_pot': ('brass_pot_01', None, 'Brass pot', 'props', 1),
    'hydrant': ('fire_hydrant', None, 'Fire hydrant', 'props', 2),
    'gnome': ('garden_gnome', None, 'Garden gnome', 'props', 1),
    'road_barrier': ('concrete_road_barrier', 1, 'Road barrier', 'props', 3),
    'patio_set': ('outdoor_table_chair_set_01', None, 'Patio set', 'furniture', 4),
    'chair': ('painted_wooden_chair_01', None, 'Painted chair', 'furniture', 1.5),
    'stool': ('painted_wooden_stool', None, 'Painted stool', 'furniture', 1),
    'rocking_chair': ('Rockingchair_01', None, 'Rocking chair', 'furniture', 2),
    'camp_stool': ('folding_wooden_stool', None, 'Camp stool', 'furniture', 1),
    'old_chair': ('gallinera_chair', None, 'Old chair', 'furniture', 1.5),
    'lounge_chair': ('mid_century_lounge_chair', None, 'Lounge chair', 'furniture', 2),
    'street_seat': ('modular_street_seating', None, 'Street seating', 'furniture', 5),
    'plastic_chair': ('plastic_monobloc_chair_01', None, 'Plastic chair', 'furniture', 1.5),
    'statue_gothic': ('gothic_statue', None, 'Gothic statue', 'statues', 4),
    'statue_horse': ('horse_statue_01', None, 'Horse statue', 'statues', 4),
    'statue_whale': ('bronze_whale_statue', None, 'Whale statue', 'statues', 4),
    'statue_shark': ('bronze_shark_statue', None, 'Shark statue', 'statues', 3),
    'statue_ray': ('bronze_ray_statue', None, 'Ray statue', 'statues', 3),
    'statue_cat': ('concrete_cat_statue', None, 'Cat statue', 'statues', 2),
    'statue_lion': ('lion_head', None, 'Lion head', 'statues', 2),
    'giant_vase': ('antique_ceramic_vase_01', None, 'Giant vase', 'statues', 2),
    'giant_chess': ('chess_set', None, 'Giant chess set', 'statues', 6),
    'ship': ('dutch_ship_medium', None, 'Tall ship', 'landmarks', 28),
    'pier': ('modular_wooden_pier', None, 'Wooden pier', 'landmarks', 12),
    'castle_door': ('large_castle_door', None, 'Castle door', 'landmarks', 4),
    'chain_fence': ('modular_chainlink_fence', None, 'Chain fence', 'landmarks', 6),
}
MADE_HERE = {
    'xmas_tree': ('Christmas tree', 8), 'gift_red': ('Red gift', 2), 'gift_green': ('Green gift', 2), 'gift_pile': ('Pile of gifts', 4),
    'snowman': ('Snowman', 3), 'candy_cane': ('Candy cane', 2), 'sleigh': ('Sleigh', 5), 'wreath_arch': ('Wreath arch', 6),
    'ornament_red': ('Giant red bauble', 2), 'ornament_gold': ('Giant gold bauble', 2), 'gingerbread_hut': ('Gingerbread hut', 7),
    'pumpkin': ('Pumpkin', 1.5), 'jack_o_lantern': ("Jack-o'-lantern", 1.5), 'hay_bale': ('Hay bale', 2.5), 'scarecrow': ('Scarecrow', 3),
    'gravestone': ('Gravestone', 2), 'grave_cross': ('Stone cross', 2), 'cauldron': ('Cauldron', 2.5), 'tree_spooky': ('Spooky tree', 7),
    'paper_lanterns': ('Paper lanterns', 5), 'bunting': ('Bunting', 6), 'easter_egg_pink': ('Pink Easter egg', 2), 'easter_egg_blue': ('Blue Easter egg', 2),
}
MADE_LICENCE = 'AGPL-3.0-only (Agent Guild: Builders)'
LEGACY = {'tree_oak', 'tree_elm', 'tree_fir', 'tree_young', 'shrub_round', 'shrub_low', 'shrub_wild', 'fern', 'grass', 'dandelion',
          'celandine', 'boulder', 'stone', 'stump', 'trunk', 'lantern', 'barrel', 'table', 'bench'}
# Real-world heights in metres; a model is scaled to its height wherever it's used.
TARGET = {'tree_oak': 9, 'tree_elm': 8, 'tree_fir': 16, 'tree_young': 6, 'shrub_round': 1.4, 'shrub_low': 1.1, 'shrub_wild': 1.0,
          'fern': .7, 'grass': .5, 'dandelion': .25, 'celandine': .2, 'boulder': 1.6, 'stone': .35, 'stump': .6, 'trunk': .7,
          'lantern': .5, 'barrel': .9, 'table': .75, 'bench': .9,
          'snag': 3, 'gazania': .35, 'ursinia': .3, 'empodium': .25,
          'stinkkruid': .3, 'potted_plant': 1.35, 'planter_low': .42, 'planter_tall': .86, 'clay_pot': .3, 'rock_face': 5, 'rock_wall': 4.7,
          'mossy_rocks': 1.8, 'stump_old': .55, 'trunk_old': 1.05, 'street_lamp': 3.9, 'lantern_wood': .55,
          'lantern_brass': .4, 'oil_lamp': .8, 'candles': .85, 'candlestick': .3, 'fire_pit': .4, 'barrel_stove': .9, 'barrel_dark': .9,
          'barrel_rusty': .93, 'wine_barrel': .9, 'crate': .45, 'crate_long': .5, 'crate_army': .4, 'crate_ammo': .5,
          'treasure_chest': .65, 'basket': .25, 'basket_tall': .3, 'bucket': .55, 'watering_can': .3, 'trash_can': .95, 'cardboard_box': .35,
          'tool_cart': .95, 'tool_chest': .65, 'ladder': 2.1, 'spinning_wheel': 1.0, 'big_pot': .55, 'brass_pot': .35, 'hydrant': .8,
          'gnome': .6, 'road_barrier': .85, 'patio_set': .9, 'chair': .95, 'stool': .6, 'rocking_chair': 1.0, 'camp_stool': .45,
          'old_chair': 1.05, 'lounge_chair': 1.15, 'street_seat': .95, 'plastic_chair': .88, 'statue_gothic': 2.6, 'statue_horse': 2.0,
          'statue_whale': 1.6, 'statue_shark': 1.0, 'statue_ray': 1.0, 'statue_cat': .9, 'statue_lion': 1.0, 'giant_vase': 1.4,
          'giant_chess': .6, 'ship': 24, 'pier': 7.5, 'castle_door': 3, 'chain_fence': 2.5, 
          'xmas_tree': 5.5, 'gift_red': 1.1, 'gift_green': 0.9, 'gift_pile': 1.65, 'snowman': 2.25, 'candy_cane': 2.0, 'sleigh': 1.7,
          'wreath_arch': 4.0, 'ornament_red': 1.25, 'ornament_gold': 1.25, 'gingerbread_hut': 3.5, 'pumpkin': 0.75, 'jack_o_lantern': 0.75,
          'hay_bale': 1.0, 'scarecrow': 2.5, 'gravestone': 1.25, 'grave_cross': 1.45, 'cauldron': 1.05, 'tree_spooky': 7.0,
          'paper_lanterns': 2.6, 'bunting': 3.0, 'easter_egg_pink': 1.4, 'easter_egg_blue': 1.4}
# Lit at dusk only: watts, colour and height above the model's base, in Blender's units.
LIGHTS = {'lantern': {'watts': 60.0, 'color': [1.0, 0.6, 0.3], 'height': 0.3},
          'street_lamp': {'watts': 300.0, 'color': [1.0, 0.72, 0.45], 'height': 3.6},
          'lantern_wood': {'watts': 60.0, 'color': [1.0, 0.6, 0.3], 'height': 0.3},
          'lantern_brass': {'watts': 30.0, 'color': [1.0, 0.6, 0.3], 'height': 0.2},
          'oil_lamp': {'watts': 40.0, 'color': [1.0, 0.65, 0.35], 'height': 0.55},
          'candles': {'watts': 30.0, 'color': [1.0, 0.6, 0.3], 'height': 0.85},
          'candlestick': {'watts': 12.0, 'color': [1.0, 0.6, 0.3], 'height': 0.3},
          'fire_pit': {'watts': 220.0, 'color': [1.0, 0.45, 0.15], 'height': 0.5},
          'barrel_stove': {'watts': 80.0, 'color': [1.0, 0.42, 0.12], 'height': 0.9},
          'xmas_tree': {'watts': 200.0, 'color': [1.0, 0.72, 0.4], 'height': 3.0},
          'gingerbread_hut': {'watts': 120.0, 'color': [1.0, 0.65, 0.3], 'height': 1.2},
          'jack_o_lantern': {'watts': 40.0, 'color': [1.0, 0.5, 0.12], 'height': 0.45},
          'cauldron': {'watts': 60.0, 'color': [0.35, 1.0, 0.4], 'height': 1.15},
          'wreath_arch': {'watts': 80.0, 'color': [1.0, 0.72, 0.4], 'height': 3.3},
          'paper_lanterns': {'watts': 70.0, 'color': [1.0, 0.45, 0.2], 'height': 1.9}}
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
    for folder in (SOURCE, *MORE_SOURCES):
        found = sorted(folder.joinpath(name).rglob('*.blend'))
        if found:
            return found[0]
    return None


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


def stand_at_origin(parts):
    worlds = [o.matrix_world.copy() for o in parts]
    for o, world in zip(parts, worlds):
        o.parent = None
        o.matrix_world = world
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in parts for c in o.bound_box]
    shift = Vector(((min(c.x for c in corners) + max(c.x for c in corners)) / -2,
                    (min(c.y for c in corners) + max(c.y for c in corners)) / -2,
                    -min(c.z for c in corners)))
    for o in parts:
        o.matrix_world.translation += shift
    bpy.context.view_layer.update()


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
    if kit_id in LEGACY:
        for o in parts:
            o.location = (0, 0, 0)
    for o in parts:
        scene.collection.objects.link(o)
    bpy.context.view_layer.update()
    if kit_id not in LEGACY:
        stand_at_origin(parts)
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
             'source': name, 'licence': MADE_LICENCE if kit_id in MADE_HERE else LICENCE, 'bytes': out.stat().st_size}
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
    built = json.loads((KIT / 'kit.json').read_text(encoding='utf-8')) if (KIT / 'kit.json').exists() else {}
    kit = {'id': 'meadow', 'title': 'Meadow', 'models': {}, 'grounds': {}, 'skies': {}}
    made = {key: (key, None, label, 'holiday', spacing) for key, (label, spacing) in MADE_HERE.items()}
    for key, spec in {**MODELS, **made}.items():
        if key in built.get('models', {}) and (KIT / 'models' / f'{key}.glb').exists():
            kit['models'][key] = built['models'][key]
            continue
        entry = export_model(key, spec)
        if entry:
            kit['models'][key] = entry
    for key, (name, label) in GROUNDS.items():
        for m in ('diff', 'nor_gl', 'rough'):
            if (key, m) != ('grass', 'diff') and not (KIT / 'textures' / f'{key}_{m}.jpg').exists():
                shutil.copyfile(SOURCE / name / f'{name}_{m}_2k.jpg', KIT / 'textures' / f'{key}_{m}.jpg')
        kit['grounds'][key] = {'label': label, 'source': name, 'licence': LICENCE}
    if not (KIT / 'textures' / 'grass_diff.jpg').exists():
        write_meadow_texture(MEADOW, KIT / 'textures' / 'grass_diff.jpg')
    kit['grounds']['grass'].update({'source': 'agent-guild concept-art/guild-yard/env/textures/meadow.jpg',
                                    'licence': 'AGPL-3.0-only (Agent Guild)', 'note': 'Generated locally for the shipped Yard worlds; see ART.md in agent-guild.'})
    for key, (name, label, strength) in SKIES.items():
        if not (KIT / 'skies' / f'{key}.hdr').exists():
            shutil.copyfile(SOURCE / name / f'{name}_1k.hdr', KIT / 'skies' / f'{key}.hdr')
        kit['skies'][key] = {'label': label, 'strength': strength, 'source': name, 'licence': LICENCE}
    (KIT / 'kit.json').write_text(json.dumps(kit, indent=1) + '\n', encoding='utf-8', newline='\n')
    print('KIT done', len(kit['models']), 'models')


if __name__ == '__main__':
    main()

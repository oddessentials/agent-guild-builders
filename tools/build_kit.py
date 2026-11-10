import json, math, re, shutil, sys, tempfile
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
from mathutils import Matrix, Vector
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
    'table': ('WoodenTable_01', None, 'Table', 'furniture', 3),
    'bench': ('painted_wooden_bench', None, 'Bench', 'furniture', 3),
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
    'trash_can': ('metal_trash_can', None, 'Bins', 'city', 3),
    'cardboard_box': ('cardboard_box_01', None, 'Cardboard box', 'props', 1),
    'tool_cart': ('tool_cart', None, 'Tool cart', 'props', 3),
    'tool_chest': ('metal_tool_chest', None, 'Tool chest', 'props', 2),
    'ladder': ('ladder_sectioned_01', None, 'Ladder', 'props', 2),
    'spinning_wheel': ('spinning_wheel_01', None, 'Spinning wheel', 'props', 2),
    'big_pot': ('ceramic_pot', None, 'Big pot', 'plants', 1.5),
    'brass_pot': ('brass_pot_01', None, 'Brass pot', 'plants', 1),
    'hydrant': ('fire_hydrant', None, 'Fire hydrant', 'city', 2),
    'gnome': ('garden_gnome', None, 'Garden gnome', 'gnomes', 1),
    'road_barrier': ('concrete_road_barrier', 1, 'Road barrier', 'city', 3),
    'patio_set': ('outdoor_table_chair_set_01', None, 'Patio set', 'furniture', 4),
    'chair': ('painted_wooden_chair_01', None, 'Painted chair', 'furniture', 1.5),
    'stool': ('painted_wooden_stool', None, 'Painted stool', 'furniture', 1),
    'rocking_chair': ('Rockingchair_01', None, 'Rocking chair', 'furniture', 2),
    'camp_stool': ('folding_wooden_stool', None, 'Camp stool', 'furniture', 1),
    'old_chair': ('gallinera_chair', None, 'Old chair', 'furniture', 1.5),
    'lounge_chair': ('mid_century_lounge_chair', None, 'Lounge chair', 'furniture', 2),
    'street_seat': ('modular_street_seating', None, 'Street seating', 'city', 5),
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
    'castle_door': ('large_castle_door', None, 'Castle door', 'medieval', 4),
    'chain_fence': ('modular_chainlink_fence', None, 'Chain fence', 'city', 6),
    'fort_thick_straight': ('modular_fort_01:wall_thick_straight_01', None, 'Thick wall', 'medieval', 15),
    'fort_thick_straight_b': ('modular_fort_01:wall_thick_straight_02', None, 'Gun-port wall', 'medieval', 15),
    'fort_thick_corner': ('modular_fort_01:wall_thick_corner_01', None, 'Thick corner', 'medieval', 6),
    'fort_thick_corner_b': ('modular_fort_01:wall_thick_corner_02', None, 'Inner corner', 'medieval', 7),
    'fort_thick_end': ('modular_fort_01:wall_thick_end_01', None, 'Plain wall end', 'medieval', 5),
    'fort_thick_end_b': ('modular_fort_01:wall_thick_end_02', None, 'Battlement end', 'medieval', 5),
    'fort_thick_thin_transition': ('modular_fort_01:wall_thick_thin_transition_01', None, 'Wall join', 'medieval', 4),
    'fort_thin_straight': ('modular_fort_01:wall_thin_straight_01', None, 'Thin wall', 'medieval', 15),
    'fort_thin_straight_b': ('modular_fort_01:wall_thin_straight_02', None, 'Arrow-slit wall', 'medieval', 15),
    'fort_thin_straight_c': ('modular_fort_01:wall_thin_straight_03', None, 'Short plain wall', 'medieval', 8),
    'fort_thin_straight_d': ('modular_fort_01:wall_thin_straight_04', None, 'Short thin wall', 'medieval', 8),
    'fort_thin_corner': ('modular_fort_01:wall_thin_corner_01', None, 'Thin corner', 'medieval', 5),
    'fort_thin_corner_b': ('modular_fort_01:wall_thin_corner_02', None, 'Rounded corner', 'medieval', 5),
    'fort_thin_corner_c': ('modular_fort_01:wall_thin_corner_03', None, 'Angled corner', 'medieval', 6),
    'fort_thin_gate': ('modular_fort_01:wall_thin_gate_01', None, 'Gate wall', 'medieval', 8),
    'fort_walkway_straight': ('modular_fort_01:wall_walkway_straight_01', None, 'Walkway', 'medieval', 15),
    'fort_walkway_straight_b': ('modular_fort_01:wall_walkway_straight_02', None, 'Plain walkway', 'medieval', 15),
    'fort_walkway_corner': ('modular_fort_01:wall_walkway_corner_01', None, 'Walkway corner', 'medieval', 8),
    'fort_walkway_corner_b': ('modular_fort_01:wall_walkway_corner_02', None, 'Walkway post', 'medieval', 3),
    'fort_walkway_end': ('modular_fort_01:wall_walkway_end_01', None, 'Walkway end', 'medieval', 5),
    'fort_stairs_straight': ('modular_fort_01:wall_stairs_straight_01', None, 'Wall stairs', 'medieval', 15),
    'fort_tower_round': ('modular_fort_01:tower_round', None, 'Round tower', 'medieval', 16),
    'tree_blossom': ('jacaranda_tree', 1, 'Blossom tree', 'trees', 9),
    'moon_rock': ('moon_rock_01', None, 'Moon rock', 'rocks', 3),
    'moon_boulder': ('moon_rock_03', None, 'Moon boulder', 'rocks', 6),
}
# id: (label, scatter spacing in metres), built by tools/build_clay.py
CLAY = {
    'clay_wall': ('Wall', 8), 'clay_wall_short': ('Short wall', 4), 'clay_wall_window': ('Window wall', 8), 'clay_wall_door': ('Door wall', 8),
    'clay_wall_corner': ('Wall corner', 2), 'clay_partition': ('Glass partition', 4), 'clay_column': ('Column', 4),
    'clay_wall_art': ('Framed prints', 4), 'clay_wall_shelf': ('Wall shelves', 3), 'clay_wall_clock': ('Wall clock', 2),
    'clay_wall_display': ('Wall display', 4), 'clay_neon_sign': ('Neon sign', 4),
    'clay_desk_single': ('Desk', 3), 'clay_desk_row': ('Desk row', 6), 'clay_desk_pod': ('Desk pod', 6), 'clay_desk_pod_six': ('Desk pod of six', 7), 'clay_desk_standing': ('Standing desk', 3),
    'clay_office_chair': ('Office chair', 1.5), 'clay_meeting_table': ('Meeting table', 6), 'clay_whiteboard': ('Whiteboard', 3),
    'clay_screen': ('Presentation screen', 4), 'clay_reception': ('Reception desk', 6), 'clay_phone_booth': ('Focus booth', 3),
    'clay_sofa': ('Sofa', 3), 'clay_armchair': ('Armchair', 2), 'clay_coffee_table': ('Coffee table', 2), 'clay_rug': ('Round rug', 4), 'clay_rug_large': ('Large rug', 5),
    'clay_beanbag': ('Beanbag', 1.5), 'clay_bleachers': ('Stepped seating', 6),
    'clay_bookshelf': ('Bookshelf', 3), 'clay_cabinet': ('Sideboard', 3), 'clay_server_rack': ('Server rack', 2), 'clay_printer': ('Printer', 2),
    'clay_kitchen': ('Kitchenette', 5), 'clay_cafe_table': ('Caf\u00e9 table', 3), 'clay_water_cooler': ('Water cooler', 1.5),
    'clay_plant': ('Office plant', 1.5), 'clay_plant_tall': ('Tall office plant', 2), 'clay_planter': ('Plant divider', 3),
    'clay_floor_lamp': ('Floor lamp', 3), 'clay_ping_pong': ('Table tennis', 5), 'clay_slide': ('Slide', 7), 'clay_mezzanine': ('Mezzanine', 12),
}
# id: (label, scatter spacing in metres), built by tools/build_glade.py
GLADE = {
    'glade_tree_oak': ('Oak', 7), 'glade_tree_pine': ('Pine', 5), 'glade_tree_ancient': ('Ancient tree', 12), 'glade_tree_dead': ('Bare tree', 5),
    'glade_bush': ('Bush', 2.5), 'glade_grass': ('Grass tuft', 1.2), 'glade_flowers': ('Wildflowers', 1.2),
    'glade_mushrooms': ('Toadstools', 1.5), 'glade_glow_mushrooms': ('Glowing mushrooms', 1.5),
    'glade_rock': ('Rock', 3), 'glade_boulder': ('Mossy boulder', 4), 'glade_log': ('Fallen log', 4), 'glade_stump': ('Stump', 3),
    'glade_dais': ('Rune dais', 8), 'glade_shrine': ('Crystal shrine', 9), 'glade_portal': ('Portal arch', 5), 'glade_tower': ('Ruined tower', 6),
    'glade_wall_ruin': ('Ruined wall', 5), 'glade_pillar': ('Pillar', 2), 'glade_pillar_broken': ('Broken pillar', 3),
    'glade_statue': ('Guardian statue', 3), 'glade_obelisk': ('Rune stone', 3), 'glade_well': ('Well', 4), 'glade_path': ('Stepping stones', 3),
    'glade_brazier': ('Brazier', 3), 'glade_torch': ('Torch', 4), 'glade_lantern_post': ('Lantern post', 4), 'glade_campfire': ('Campfire', 4),
    'glade_crystal': ('Crystals', 3), 'glade_crystal_small': ('Small crystals', 2),
    'glade_forge': ('Forge', 5), 'glade_alchemy': ('Alchemy bench', 5), 'glade_library': ('Library', 4), 'glade_scrying': ('Scrying orb', 3),
    'glade_map_table': ('Map table', 3), 'glade_meeting_stones': ('Meeting stones', 6),
    'glade_tent': ('Tent', 5), 'glade_banner': ('Banner', 3), 'glade_signpost': ('Signpost', 3), 'glade_chest': ('Chest', 2),
    'glade_supplies': ('Supplies', 3), 'glade_weapon_rack': ('Weapon rack', 3), 'glade_fence': ('Fence', 2.2),
}
MADE_SETS = {'clay': CLAY, 'glade': GLADE}
CLAY_JOINS = {'clay_wall', 'clay_wall_short', 'clay_wall_window', 'clay_wall_door', 'clay_wall_corner', 'clay_partition'}
CLAY_FIXED = CLAY_JOINS | {'clay_wall_art', 'clay_wall_shelf', 'clay_wall_clock', 'clay_wall_display', 'clay_neon_sign'}
FORT = {key for key in MODELS if key.startswith('fort_')}
MODULAR = FORT | {'castle_door'} | CLAY_FIXED
JOINS = FORT - {'fort_thick_corner_b', 'fort_walkway_corner_b'} | CLAY_JOINS
SEATED_GROUPS = {'city', 'medieval', 'gnomes', 'goblins', 'forest', 'space'}
MADE_HERE = {
    'xmas_tree': ('Christmas tree', 8), 'gift_red': ('Red gift', 2), 'gift_green': ('Green gift', 2), 'gift_pile': ('Pile of gifts', 4),
    'snowman': ('Snowman', 3), 'candy_cane': ('Candy cane', 2), 'sleigh': ('Sleigh', 5), 'wreath_arch': ('Wreath arch', 6),
    'ornament_red': ('Giant red bauble', 2), 'ornament_gold': ('Giant gold bauble', 2), 'gingerbread_hut': ('Gingerbread hut', 7),
    'pumpkin': ('Pumpkin', 1.5), 'jack_o_lantern': ("Jack-o'-lantern", 1.5), 'hay_bale': ('Hay bale', 2.5), 'scarecrow': ('Scarecrow', 3),
    'gravestone': ('Gravestone', 2), 'grave_cross': ('Stone cross', 2), 'cauldron': ('Cauldron', 2.5), 'tree_spooky': ('Spooky tree', 7),
    'paper_lanterns': ('Paper lanterns', 5), 'bunting': ('Bunting', 6), 'easter_egg_pink': ('Pink Easter egg', 2), 'easter_egg_blue': ('Blue Easter egg', 2),
}
MADE_LICENCE = 'AGPL-3.0-only (Agent Guild: Builders)'
# id: (GLB under a source folder or kits/, mesh object to keep or None for all, label, group, scatter spacing in metres)
GUILD = {
    'car_sedan': ('professional-yard/models/car_sedan.glb', None, 'Sedan', 'city', 5),
    'car_hatch': ('professional-yard/models/car_hatch.glb', None, 'Hatchback', 'city', 5),
    'car_suv': ('professional-yard/models/car_suv.glb', None, 'SUV', 'city', 5),
    'car_taxi': ('professional-yard/models/car_taxi.glb', None, 'Taxi', 'city', 5),
    'city_bus': ('professional-yard/models/city_bus.glb', None, 'City bus', 'city', 12),
    'delivery_van': ('professional-yard/models/delivery_van.glb', None, 'Delivery van', 'city', 7),
    'gnome_cottage': ('gnomeland-yard/models/town_cottage_a.glb', None, 'Gnome cottage', 'gnomes', 9),
    'gnome_cottage_small': ('gnomeland-yard/models/town_cottage_b.glb', None, 'Gnome cabin', 'gnomes', 7),
    'gnome_tower': ('gnomeland-yard/models/town_tower.glb', None, 'Gnome tower', 'gnomes', 7),
    'gnome_workshop': ('gnomeland-yard/models/town_workshop.glb', None, 'Gnome workshop', 'gnomes', 7),
    'gnome_mill': ('gnomeland-yard/models/town_mill.glb', None, 'Gnome mill', 'gnomes', 8),
    'goblin_house': ('goblinville-yard/models/town_house_a.glb', None, 'Goblin house', 'goblins', 9),
    'goblin_shack': ('goblinville-yard/models/town_house_b.glb', None, 'Goblin shack', 'goblins', 8),
    'goblin_hut': ('goblinville-yard/models/town_house_c.glb', None, 'Goblin hut', 'goblins', 7),
    'goblin_factory': ('goblinville-yard/models/factory.glb', None, 'Goblin factory', 'goblins', 17),
    'goblin_water_tower': ('goblinville-yard/models/water_tower.glb', None, 'Water tower', 'goblins', 11),
    'goblin_crane': ('goblinville-yard/models/crane.glb', None, 'Goblin crane', 'goblins', 14),
    'treehouse': ('grove-yard/models/town_treehouse.glb', None, 'Treehouse', 'forest', 9),
    'stump_house': ('grove-yard/models/town_stump.glb', None, 'Stump house', 'forest', 6),
    'mushroom_house': ('grove-yard/models/town_mushroom.glb', None, 'Mushroom house', 'forest', 7),
    'stone_lantern': ('grove-yard/models/town_lantern.glb', None, 'Stone lantern', 'forest', 3),
    'space_dish': ('orbital-yard/models/town_dish.glb', None, 'Satellite dish', 'space', 8),
    'space_crane': ('orbital-yard/models/town_crane.glb', None, 'Gantry crane', 'space', 7),
    'space_shuttle': ('orbital-yard/models/town_shuttle.glb', None, 'Shuttle', 'space', 11),
}
HALL_AGENTS = {'anthropic': 'Claude', 'openai': 'Codex', 'google': 'Antigravity', 'xai': 'Grok', 'docker': 'Docker', 'shell': 'Shell'}
HALL_GROUPS = {'guild': 'medieval', 'professional': 'city', 'gnomeland': 'gnomes', 'goblinville': 'goblins', 'grove': 'forest', 'orbital': 'space'}
GUILD.update({f'hall_{base}_{agent}': (f'halls/{base}.glb', f'hall_{agent}_mesh', f'{name} hall', group, 9 if agent == 'docker' else 7)
              for base, group in HALL_GROUPS.items() for agent, name in HALL_AGENTS.items()})
GUILD_LICENCE = 'AGPL-3.0-only (Agent Guild)'
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
          'paper_lanterns': 2.6, 'bunting': 3.0, 'easter_egg_pink': 1.4, 'easter_egg_blue': 1.4,
          'car_sedan': 1.5, 'car_hatch': 1.55, 'car_suv': 1.75, 'car_taxi': 1.6, 'city_bus': 3.3, 'delivery_van': 2.6,
          'gnome_cottage': 8.5, 'gnome_cottage_small': 6.5, 'gnome_tower': 12.5, 'gnome_workshop': 6, 'gnome_mill': 8,
          'goblin_house': 9, 'goblin_shack': 7, 'goblin_hut': 5, 'goblin_factory': 13, 'goblin_water_tower': 10, 'goblin_crane': 11,
          'treehouse': 10, 'stump_house': 4.5, 'mushroom_house': 6.5, 'stone_lantern': 2.2,
          'space_dish': 7, 'space_crane': 5, 'space_shuttle': 5.5,
          'tree_blossom': 8, 'moon_rock': 0.8, 'moon_boulder': 2.4}
FOLIAGE = {'tree_blossom': ((0.62, 0.26, 0.4), (0.98, 0.78, 0.86))}
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
          'paper_lanterns': {'watts': 70.0, 'color': [1.0, 0.45, 0.2], 'height': 1.9},
          'stone_lantern': {'watts': 160.0, 'color': [1.0, 0.6, 0.3], 'height': 1.28},
          'glade_brazier': {'watts': 700.0, 'color': [1.0, 0.55, 0.22], 'height': 1.5},
          'glade_torch': {'watts': 800.0, 'color': [1.0, 0.55, 0.22], 'height': 2.8},
          'glade_campfire': {'watts': 1000.0, 'color': [1.0, 0.55, 0.22], 'height': 1.6},
          'glade_lantern_post': {'watts': 600.0, 'color': [1.0, 0.7, 0.35], 'height': 1.7},
          'glade_crystal': {'watts': 400.0, 'color': [0.3, 1.0, 0.92], 'height': 3.0},
          'glade_shrine': {'watts': 900.0, 'color': [0.3, 1.0, 0.92], 'height': 5.6},
          'glade_dais': {'watts': 300.0, 'color': [0.3, 1.0, 0.92], 'height': 1.6},
          'glade_obelisk': {'watts': 300.0, 'color': [0.3, 1.0, 0.92], 'height': 3.6},
          'glade_meeting_stones': {'watts': 400.0, 'color': [0.3, 1.0, 0.92], 'height': 0.6},
          'glade_portal': {'watts': 600.0, 'color': [0.62, 0.42, 1.0], 'height': 6.0},
          'glade_scrying': {'watts': 500.0, 'color': [0.62, 0.42, 1.0], 'height': 2.3},
          'glade_alchemy': {'watts': 350.0, 'color': [0.62, 0.42, 1.0], 'height': 2.0},
          'glade_tower': {'watts': 400.0, 'color': [1.0, 0.55, 0.22], 'height': 3.6},
          'glade_forge': {'watts': 600.0, 'color': [1.0, 0.55, 0.22], 'height': 1.6},
          'glade_library': {'watts': 250.0, 'color': [1.0, 0.7, 0.35], 'height': 1.6},
          'clay_floor_lamp': {'watts': 420.0, 'color': [1.0, 0.72, 0.45], 'height': 1.95},
          'clay_kitchen': {'watts': 260.0, 'color': [1.0, 0.76, 0.5], 'height': 1.6},
          'clay_reception': {'watts': 220.0, 'color': [1.0, 0.76, 0.5], 'height': 1.6},
          'clay_mezzanine': {'watts': 320.0, 'color': [1.0, 0.74, 0.48], 'height': 3.9},
          'clay_phone_booth': {'watts': 60.0, 'color': [1.0, 0.8, 0.55], 'height': 2.0},
          'clay_neon_sign': {'watts': 140.0, 'color': [1.0, 0.45, 0.3], 'height': 3.7},
          'clay_wall_display': {'watts': 160.0, 'color': [0.5, 0.75, 1.0], 'height': 3.45},
          'clay_screen': {'watts': 120.0, 'color': [0.5, 0.75, 1.0], 'height': 2.4},
          'clay_desk_pod': {'watts': 110.0, 'color': [0.72, 0.84, 1.0], 'height': 1.3},
          'clay_desk_pod_six': {'watts': 140.0, 'color': [0.72, 0.84, 1.0], 'height': 1.3},
          'clay_desk_row': {'watts': 90.0, 'color': [0.72, 0.84, 1.0], 'height': 1.3}}
GROUNDS = {
    'grass': ('leafy_grass', 'Meadow grass'), 'dirt': ('forest_ground_04', 'Forest floor'),
    'rock': ('rocky_trail', 'Rocky ground'), 'gravel': ('gravel_floor', 'Gravel'),
    'cobble': ('cobblestone_floor_04', 'Cobbles'),
    'mars_sand': ('red_sand', 'Red sand'), 'mars_stones': ('red_laterite_soil_stones', 'Red stones'),
    'mars_cliff': ('cliff_side', 'Layered rock'), 'mars_dust': ('red_mud_stones', 'Dark regolith'),
    'moon_dust': ('moon_01', 'Grey regolith'), 'moon_bright': ('moon_dusted_03', 'Bright dust'),
    'moon_rock': ('moon_meteor_01', 'Cratered rock'), 'space': ('made_stars', 'Open space'),
    'salt_crust': ('made_salt_crust', 'Salt crust'), 'salt_flat': ('made_salt_flat', 'Smooth salt'),
    'salt_mud': ('dry_mud_field_001', 'Dry mud'),
    'ash': ('made_ash', 'Ash'), 'cinder': ('made_red_cinder', 'Red cinder'),
    'basalt': ('made_basalt', 'Basalt'), 'lava': ('made_lava', 'Lava'),
    'raked': ('made_raked_gravel', 'Raked gravel'),
    'mossy_stone': ('mossy_rock', 'Mossy stone'), 'pebbles': ('dry_river_pebbles', 'River pebbles'),
    'plaza_panels': ('granite_tile', 'Stone panels'),
    'plaza_sandstone': ('white_sandstone_blocks_02', 'White sandstone'), 'plaza_basalt': ('volcanic_rock_tiles', 'Basalt tiles'),
    'plaza_slate': ('large_grey_tiles', 'Grey flagstones'), 'plaza_concrete': ('concrete_pavers_02', 'Concrete pavers'),
    'clay_planks': ('made_clay_planks', 'Oak planks'), 'clay_carpet': ('made_clay_carpet', 'Cream carpet'),
    'clay_sage': ('made_clay_sage', 'Sage carpet'), 'clay_tiles': ('made_clay_tiles', 'White tiles'),
    'plaza_terrazzo': ('made_terrazzo', 'Terrazzo'),
    'glade_grass': ('made_glade_grass', 'Pixel grass'), 'glade_floor': ('made_glade_floor', 'Pixel forest floor'),
    'glade_stone': ('made_glade_stone', 'Pixel flagstones'), 'glade_dirt': ('made_glade_dirt', 'Pixel dirt'),
    'plaza_glade': ('made_glade_paving', 'Pixel paving'),
}
# A world's four painted grounds and its plaza. Per ground: metres per repeat as a
# multiple of the land shader's, glow from within, and side projection on steep land.
LANDS = {
    'meadow': {'label': 'Meadow', 'grounds': ['grass', 'dirt', 'rock', 'gravel'], 'plaza': 'cobble', 'grass': True, 'leaves': True},
    'mars': {'label': 'Red planet', 'grounds': ['mars_sand', 'mars_stones', 'mars_cliff', 'mars_dust'], 'plaza': 'plaza_concrete',
             'scale': [2, 1, 4, 1.5], 'triplanar': True},
    'moon': {'label': 'Moon', 'grounds': ['moon_dust', 'moon_bright', 'moon_rock', 'space'], 'plaza': 'plaza_panels',
             'scale': [2, 2, 2, 20], 'glow': [0, 0, 0, 3], 'glow_power': [1, 1, 1, 1], 'triplanar': True},
    'salt': {'label': 'Salt flat', 'grounds': ['salt_crust', 'salt_flat', 'basalt', 'salt_mud'], 'plaza': 'plaza_sandstone',
             'scale': [8, 3, 3, 2], 'triplanar': True,
             'water': {'shallow': [0.16, 0.66, 0.64], 'deep': [0.01, 0.3, 0.38], 'clear': 0.25, 'mirror': 0.2}},
    'volcano': {'label': 'Volcanic', 'grounds': ['ash', 'cinder', 'basalt', 'lava'], 'plaza': 'plaza_basalt',
                'scale': [2, 1.5, 3, 6], 'glow': [0, 0, 0, 9], 'glow_power': [1, 1, 1, 1.6], 'triplanar': True},
    'garden': {'label': 'Garden', 'grounds': ['grass', 'raked', 'mossy_stone', 'pebbles'], 'plaza': 'plaza_slate', 'grass': True,
               'grass_tint': [0.5, 0.78, 0.42], 'water': {'shallow': [0.08, 0.16, 0.1], 'deep': [0.006, 0.03, 0.025], 'clear': 0.55}},
    'clay': {'label': 'Clay office', 'grounds': ['clay_planks', 'clay_carpet', 'clay_sage', 'clay_tiles'], 'plaza': 'plaza_terrazzo',
             'scale': [2, 1, 1, 1], 'water': {'shallow': [0.012, 0.012, 0.014], 'deep': [0.012, 0.012, 0.014], 'clear': 0.0}},
    'glade': {'label': 'Pixel glade', 'grounds': ['glade_grass', 'glade_floor', 'glade_stone', 'glade_dirt'], 'plaza': 'plaza_glade',
              'scale': [2.6667, 2.6667, 2.6667, 2.6667], 'water': {'shallow': [0.05, 0.3, 0.3], 'deep': [0.01, 0.1, 0.14], 'clear': 0.35}},
}
SKIES = {
    'day': ('kloofendal_48d_partly_cloudy_puresky', 'Clear day', 0.9),
    'overcast': ('kloofendal_misty_morning_puresky', 'Misty morning', 0.9),
    'dusk': ('qwantani_dusk_2_puresky', 'Warm dusk', 0.5),
    'moon': ('qwantani_moonrise_puresky', 'Moonrise', 0.3),
    'clear': ('kloofendal_43d_clear_puresky', 'Clear sky', 0.9),
    'sunset': ('qwantani_sunset_puresky', 'Golden sunset', 0.5),
    'haze': ('made_haze_day', 'Volcanic haze', 0.9),
    'fire': ('the_sky_is_on_fire', 'Fire sky', 0.5),
    'mars_day': ('made_mars_day', 'Mars day', 0.9),
    'mars_dusk': ('made_mars_dusk', 'Mars blue dusk', 0.9),
    'orbit_day': ('yard-env/orbital-day', 'Orbit', 1.0),
    'orbit_dusk': ('yard-env/orbital-dusk', 'Orbit dusk', 1.0),
    'studio': ('made_studio_day', 'Studio light', 1.0),
    'studio_night': ('made_studio_night', 'Studio night', 1.0),
}


def source_file(rel):
    for folder in (SOURCE, *MORE_SOURCES):
        if folder.joinpath(rel).is_file():
            return folder / rel
    raise RuntimeError(f'Missing source {rel}: run tools/fetch_sources.py and tools/make_sources.py')


def licence_of(name):
    return MADE_LICENCE if name.startswith('made_') else GUILD_LICENCE if '/' in name else LICENCE


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


def recolour_foliage(material, dark, light):
    if material is None or not material.use_nodes or 'leaves' not in material.name.lower():
        return
    for n in material.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image and 'diff' in n.image.name.lower():
            img = n.image
            px = np.empty(len(img.pixels), np.float32)
            img.pixels.foreach_get(px)
            px = px.reshape(-1, 4)
            lum = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)
            t = np.clip((lum - np.percentile(lum, 5)) / max(np.percentile(lum, 95) - np.percentile(lum, 5), 1e-4), 0, 1)[:, None]
            px[:, :3] = np.array(dark, np.float32) + (np.array(light, np.float32) - np.array(dark, np.float32)) * t
            img.pixels.foreach_set(px.ravel())
            img.update()
            img.pack()


def stand_at_origin(parts, grounded=True):
    worlds = [o.matrix_world.copy() for o in parts]
    for o, world in zip(parts, worlds):
        o.parent = None
        o.matrix_world = world
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in parts for c in o.bound_box]
    shift = Vector(((min(c.x for c in corners) + max(c.x for c in corners)) / -2,
                    (min(c.y for c in corners) + max(c.y for c in corners)) / -2,
                    -min(c.z for c in corners) if grounded else 0))
    for o in parts:
        o.matrix_world.translation += shift
    bpy.context.view_layer.update()


def glb_of(name):
    for folder in (SOURCE, *MORE_SOURCES, ROOT / 'kits'):
        if folder.joinpath(name).is_file():
            return folder / name
    return None


def guild_parts(name, keep):
    path = glb_of(name)
    if path is None:
        return None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.ops.object.select_all(action='DESELECT')
    return [o for o in bpy.context.scene.objects if o.type == 'MESH' and (keep is None or o.name == keep)] or None


def blend_parts(kit_id, name, lod):
    name, _, piece = name.partition(':')
    path = blend_of(name)
    if path is None:
        return None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(path), link=False) as (src, dst):
        dst.objects = list(src.objects)
    if piece:
        parts = [o for o in dst.objects if o is not None and o.type == 'MESH' and o.name == f'{name}_{piece}']
    else:
        parts = parts_at(dst.objects, lod, name)
    if kit_id in LEGACY:
        for o in parts:
            o.location = (0, 0, 0)
    for o in parts:
        bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.update()
    return parts


JOINT_WIDTHS = (2.55, 3.12, 3.54, 4.17)
# In the piece's own Blender frame: its wall side is x = 0 and it runs to y = -length.
AUTHORED_JOINTS = {
    'fort_stairs_straight': [((0, 0), (-1, 0), 1), ((0, -14.819), (-1, 0), 1), ((0, -14.819), (0, -1), 0)],
    'clay_wall_corner': [((0.2, 0), (1, 0), 0), ((-0.2, 0), (-1, 0), 0), ((0, 0.2), (0, 1), 0), ((0, -0.2), (0, -1), 0)],
}
AUTHORED_JOINTS.update({key: [((half, 0), (1, 0), 0), ((-half, 0), (-1, 0), 0)]
                        for key, half in (('clay_wall', 4), ('clay_wall_window', 4), ('clay_wall_door', 4), ('clay_wall_short', 2), ('clay_partition', 2))})
TOWER_REACH = 7.0


def joints_of(kit_id, parts):
    """Where a modular piece meets others, in the model's own frame as Godot reads
    it: [x, z, facing x, facing z, 0 for an end or 1 for a ledge]. An open end is a full-height cut face one wall
    thick, met at its ground corner on the battered outer side; a full-length face
    at the 7.08 m ledge is where a walkway stands behind a wall."""
    if kit_id == 'fort_tower_round':
        return [[x * TOWER_REACH, z * TOWER_REACH, x, z, 0] for x, z in ((1, 0), (0, 1), (-1, 0), (0, -1))]
    if kit_id in AUTHORED_JOINTS:
        to_world = parts[0].matrix_world
        out = []
        for (x, y), (fx, fy), ledge in AUTHORED_JOINTS[kit_id]:
            at = to_world @ Vector((x, y, 0))
            facing = (to_world.to_3x3() @ Vector((fx, fy, 0))).normalized()
            out.append([round(at.x, 4), round(-at.y, 4), round(facing.x, 4), round(-facing.y, 4), ledge])
        return sorted(out)
    faces = {}
    for o in parts:
        to_world = o.matrix_world
        normals = to_world.to_3x3().inverted().transposed()
        for poly in o.data.polygons:
            n = (normals @ poly.normal).normalized()
            if abs(n.z) > 0.05:
                continue
            points = [to_world @ o.data.vertices[i].co for i in poly.vertices]
            angle = round(math.degrees(math.atan2(n.y, n.x)) / 2) * 2
            faces.setdefault(angle, []).append((n.x * points[0].x + n.y * points[0].y, points))
    planes = []
    for angle, found in faces.items():
        found.sort(key=lambda f: f[0])
        for offset, points in found:
            if planes and planes[-1][0] == angle and offset - planes[-1][1] <= 0.03:
                planes[-1][2].extend(points)
            else:
                planes.append([angle, offset, list(points)])
    joints = []
    for angle, offset, points in planes:
        n = Vector((math.cos(math.radians(angle)), math.sin(math.radians(angle))))
        t = Vector((-n.y, n.x))
        along = [t.x * p.x + t.y * p.y for p in points]
        z0, z1 = min(p.z for p in points), max(p.z for p in points)
        width = max(along) - min(along)
        if z0 > 0.25:
            continue
        if z1 >= 7.4 and any(abs(width - w) < 0.06 for w in JOINT_WIDTHS):
            low = [a for a, p in zip(along, points) if p.z < z0 + 0.05]
            high = [a for a, p in zip(along, points) if p.z > z1 - 0.3]
            near, far = abs(min(high) - min(low)), abs(max(high) - max(low))
            if abs(near - far) < 0.2:
                continue
            corners, ledge = [min(low) if near > far else max(low)], 0
        elif width >= 7.0 and 7.0 <= z1 <= 7.15:
            corners, ledge = [min(along), max(along)], 1
        else:
            continue
        for c in corners:
            at = n * offset + t * c
            joints.append([round(at.x, 4), round(-at.y, 4), round(n.x, 4), round(-n.y, 4), ledge])
    return sorted(joints)


def described(entry, kit_id, spec):
    entry.update({'label': spec[2], 'group': spec[3], 'spacing': spec[4]})
    for key, on in (('light', kit_id in LIGHTS), ('modular', kit_id in MODULAR), ('joins', kit_id in JOINS), ('seated', spec[3] in SEATED_GROUPS)):
        entry.pop(key, None)
        if on:
            entry[key] = LIGHTS[kit_id] if key == 'light' else True
    return entry


def export_model(kit_id, spec):
    name, lod, label, group, spacing = spec
    parts = guild_parts(name, lod) if kit_id in GUILD else blend_parts(kit_id, name, lod)
    if not parts:
        print('KIT missing', name)
        return None
    if kit_id not in LEGACY:
        stand_at_origin(parts, kit_id not in MODULAR)
    if kit_id in MODULAR:
        top = max((o.matrix_world @ v.co).z for o in parts for v in o.data.vertices)
        factor = TARGET.get(kit_id, round(top, 4)) / top
        for o in parts:
            o.matrix_world = Matrix.Scale(factor, 4) @ o.matrix_world
        bpy.context.view_layer.update()
    low, high = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    tris = 0
    for o in parts:
        tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
        for v in o.data.vertices:
            c = o.matrix_world @ v.co
            low = Vector(map(min, low, c))
            high = Vector(map(max, high, c))
    for material in {m for o in parts for m in o.data.materials}:
        standard_foliage(material)
        if kit_id in FOLIAGE:
            recolour_foliage(material, *FOLIAGE[kit_id])
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    out = KIT / 'models' / f'{kit_id}.glb'
    bpy.ops.export_scene.gltf(filepath=str(out), use_selection=True, export_format='GLB', export_image_format='WEBP',
                              export_image_quality=85, export_animations=False, export_cameras=False, export_lights=False)
    size = max(high.z if kit_id in MODULAR else high.z - min(low.z, 0), .001)
    target = TARGET.get(kit_id, round(size, 4 if kit_id in MODULAR else 2))
    licence = MADE_LICENCE if kit_id in MADE_HERE or any(kit_id in ids for ids in MADE_SETS.values()) else GUILD_LICENCE if kit_id in GUILD else LICENCE
    entry = {'label': label, 'group': group, 'spacing': spacing, 'height': target,
             'radius': round(max(high.x - low.x, high.y - low.y) / 2 * target / size, 2), 'triangles': tris,
             'source': f'{name} {lod}' if kit_id in GUILD and lod else name, 'licence': licence, 'bytes': out.stat().st_size}
    described(entry, kit_id, spec)
    if kit_id in JOINS:
        entry['joints'] = joints_of(kit_id, parts)
        if not entry['joints']:
            raise RuntimeError(f'{kit_id} is marked as joining but has no joints')
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
    for group, ids in MADE_SETS.items():
        made.update({key: (key, None, label, group, spacing) for key, (label, spacing) in ids.items()})
    for key, spec in {**MODELS, **made, **GUILD}.items():
        if key in built.get('models', {}) and (KIT / 'models' / f'{key}.glb').exists():
            kit['models'][key] = described(built['models'][key], key, spec)
            continue
        entry = export_model(key, spec)
        if entry:
            kit['models'][key] = entry
    for key, (name, label) in GROUNDS.items():
        for m in ('diff', 'nor_gl', 'rough'):
            if (key, m) != ('grass', 'diff') and not (KIT / 'textures' / f'{key}_{m}.jpg').exists():
                shutil.copyfile(source_file(f'{name}/{name}_{m}_2k.jpg'), KIT / 'textures' / f'{key}_{m}.jpg')
        kit['grounds'][key] = {'label': label, 'source': name, 'licence': licence_of(name)}
    if not (KIT / 'textures' / 'grass_diff.jpg').exists():
        write_meadow_texture(MEADOW, KIT / 'textures' / 'grass_diff.jpg')
    kit['grounds']['grass'].update({'source': 'agent-guild concept-art/guild-yard/env/textures/meadow.jpg',
                                    'licence': 'AGPL-3.0-only (Agent Guild)', 'note': 'Generated locally for the shipped Yard worlds; see ART.md in agent-guild.'})
    for key, (name, label, strength) in SKIES.items():
        if not (KIT / 'skies' / f'{key}.hdr').exists():
            shutil.copyfile(source_file(f'{name}.hdr' if '/' in name else f'{name}/{name}_1k.hdr'), KIT / 'skies' / f'{key}.hdr')
        kit['skies'][key] = {'label': label, 'strength': strength, 'source': name, 'licence': licence_of(name)}
    kit['lands'] = LANDS
    (KIT / 'kit.json').write_text(json.dumps(kit, indent=1) + '\n', encoding='utf-8', newline='\n')
    print('KIT done', len(kit['models']), 'models')


if __name__ == '__main__':
    main()

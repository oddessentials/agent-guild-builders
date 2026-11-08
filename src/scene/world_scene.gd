class_name WorldScene
extends Node3D
## Draws a document: land, plaza, water, placed things and their lamps. The app's
## editor and the plate baker both use this, so what you shape is what is baked.

const GROUND_ORDER := ["grass", "dirt", "rock", "gravel"]
const PLAZA_RADIUS := 13.7
const CELL := 32.0
const LAMP_FACTOR := 1.0 / (4.0 * PI * PI * PI) # Blender watts to Godot's energy
const CHUNK_CELLS := 32
const GRASS_TINT := Vector3(0.72, 0.74, 0.5)
const AUTUMN_GRASS_TINT := Vector3(0.8, 0.66, 0.36)
const AUTUMN_LEAVES := {
	"tree_oak": Color(2.8, 0.75, 0.25), "tree_elm": Color(2.5, 1.25, 0.3), "tree_young": Color(3.0, 0.6, 0.25),
	"shrub_round": Color(2.0, 0.85, 0.3), "shrub_low": Color(2.4, 0.75, 0.3), "shrub_wild": Color(1.9, 1.05, 0.35), "fern": Color(1.9, 0.9, 0.3), "grass": Color(1.6, 1.15, 0.5),
}
const WINTER_SHRUB := Color(0.75, 0.6, 0.45)
const EVERGREEN := ["tree_fir"]
const WINTER_GONE := ["grass", "fern", "dandelion", "celandine", "gazania", "ursinia", "empodium", "stinkkruid"]
const ICE_COLOR := Vector3(0.62, 0.7, 0.75)
const ICE_DEEP_COLOR := Vector3(0.5, 0.6, 0.68)

static var kit: Dictionary = {}
static var _meshes: Dictionary = {}
static var _kits := ""
static var _textures: Dictionary = {}
static var _skies: Dictionary = {}
static var _halls: Dictionary = {}
static var _season_meshes: Dictionary = {}

static func kits_dir() -> String:
	if _kits == "":
		for candidate in [ProjectSettings.globalize_path("res://kits"), OS.get_executable_path().get_base_dir().path_join("kits"), OS.get_user_data_dir().path_join("kits")]:
			if FileAccess.file_exists(candidate.path_join("meadow/kit.json")):
				_kits = candidate
				break
	return _kits

static func kit_file(rel: String) -> String:
	return kits_dir().path_join("meadow").path_join(rel)

var doc: WorldDoc
var lamps: Node3D
var _land: Node3D
var _land_material: ShaderMaterial
var _chunks: Array[MeshInstance3D] = []
var _chunk_indices := PackedInt32Array()
var _dirty_chunks := {}
var _weights_raw := PackedByteArray()
var _weights: ImageTexture
var _weights_dirty := false
var _heights: ImageTexture
var _heights_dirty := false
var _relay_chunks := {}
var _things: Node3D
var _by_cell := {}
var _nodes := {}
var _key_lamps := {}
var _theme := "light"
var _water: MeshInstance3D
var _plaza: Node3D
var _plaza_stone: ShaderMaterial
var _kerb_stone: StandardMaterial3D
var _pool: StandardMaterial3D
var _drawn_season := ""

static func load_kit() -> Dictionary:
	if kit.is_empty():
		if not FileAccess.file_exists(kit_file("kit.json")):
			return {}
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(kit_file("kit.json")))
		kit = parsed if parsed is Dictionary else {}
	return kit

## The kit's mesh for a kind, loaded once. Cutout leaves are solid to shadows and
## two-sided, as a path tracer sees them.
static func mesh_ready(kind: String) -> bool:
	return _meshes.has(kind)

## Whether a kind has gone for the season: still in the world, but not drawn, and
## nothing can touch it or be stopped by it until it returns.
static func gone_in(kind: String, season: String) -> bool:
	return season == "winter" and kind in WINTER_GONE

## A kind as it looks in a season. Summer is the model itself.
static func season_mesh(kind: String, season: String) -> Mesh:
	if season == "summer":
		return mesh_of(kind)
	var key := "%s@%s" % [kind, season]
	if not _season_meshes.has(key):
		_season_meshes[key] = _dress_for(kind, season, mesh_of(kind))
	return _season_meshes[key]

static func _dress_for(kind: String, season: String, plain: Mesh) -> ArrayMesh:
	var dressed := ArrayMesh.new()
	if gone_in(kind, season):
		return dressed
	var group: String = load_kit().get("models", {}).get(kind, {}).get("group", "")
	var snow := load("res://src/scene/snow.gdshader") as Shader
	for s in plain.get_surface_count():
		var material := plain.surface_get_material(s) as StandardMaterial3D
		var foliage := material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if season == "winter" and foliage and group == "trees" and kind not in EVERGREEN:
			continue
		var worn: Material = plain.surface_get_material(s)
		if material:
			var copy: StandardMaterial3D = material.duplicate()
			if season == "autumn" and foliage and AUTUMN_LEAVES.has(kind):
				copy.albedo_color = AUTUMN_LEAVES[kind]
			if season == "winter":
				if foliage and group == "plants":
					copy.albedo_color = WINTER_SHRUB
				var cover := ShaderMaterial.new()
				cover.shader = snow
				if foliage:
					cover.set_shader_parameter("cutout", material.albedo_texture)
					cover.set_shader_parameter("cutout_below", material.alpha_scissor_threshold)
				copy.next_pass = cover
			worn = copy
		dressed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plain.surface_get_arrays(s))
		dressed.surface_set_material(dressed.get_surface_count() - 1, worn)
	return dressed

static func mesh_of(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var doc_gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var combined := ArrayMesh.new()
	if doc_gltf.append_from_file(kit_file("models/%s.glb" % kind), state) == OK:
		var root: Node = doc_gltf.generate_scene(state)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = _to_root(mi, root)
			var mesh: Mesh = mi.mesh
			for s in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(s)
				_transform_arrays(arrays, xf)
				combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var m: Material = mi.get_active_material(s)
				var sm := m as StandardMaterial3D
				if sm:
					_add_mipmaps(sm)
				if sm and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					sm.alpha_scissor_threshold = 0.3
					sm.cull_mode = BaseMaterial3D.CULL_DISABLED
					sm.backlight_enabled = true
					var tree: bool = load_kit().get("models", {}).get(kind, {}).get("group") == "trees"
					sm.backlight = Color(0.5, 0.58, 0.25) if tree else Color(0.25, 0.3, 0.12)
					sm.albedo_color = Color(1.2, 1.2, 1.2) if tree else Color.WHITE
				combined.surface_set_material(combined.get_surface_count() - 1, m)
		root.free()
	var mesh := _scaled_to_height(combined, kind)
	if mesh.get_surface_count() > 0:
		_meshes[kind] = mesh
	return mesh

## A model at its real-world height (kit.json), so a scale of 1 means life size.
static func _scaled_to_height(mesh: ArrayMesh, kind: String) -> ArrayMesh:
	var aabb := mesh.get_aabb()
	var target: float = float(load_kit().get("models", {}).get(kind, {}).get("height", 0.0))
	var top: float = aabb.position.y + aabb.size.y
	if target <= 0.0 or top <= 0.0:
		return mesh
	var factor := target / top
	var out := ArrayMesh.new()
	var xf := Transform3D(Basis().scaled(Vector3.ONE * factor), Vector3.ZERO)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		_transform_arrays(arrays, xf)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out

static func _add_mipmaps(m: StandardMaterial3D) -> void:
	if m.albedo_texture == null:
		return
	var img: Image = m.albedo_texture.get_image()
	if img == null or img.has_mipmaps():
		return
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)

static func _to_root(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

static func _transform_arrays(arrays: Array, xf: Transform3D) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] = xf * v[i]
	arrays[Mesh.ARRAY_VERTEX] = v
	var n = arrays[Mesh.ARRAY_NORMAL]
	if n != null:
		var basis := xf.basis.inverse().transposed()
		var nn: PackedVector3Array = n
		for i in nn.size():
			nn[i] = (basis * nn[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = nn
	var t = arrays[Mesh.ARRAY_TANGENT]
	if t != null:
		var tt: PackedFloat32Array = t
		for i in tt.size() / 4:
			var d := (xf.basis * Vector3(tt[i * 4], tt[i * 4 + 1], tt[i * 4 + 2])).normalized()
			tt[i * 4] = d.x
			tt[i * 4 + 1] = d.y
			tt[i * 4 + 2] = d.z
		arrays[Mesh.ARRAY_TANGENT] = tt

func build(document: WorldDoc) -> void:
	doc = document
	load_kit()
	for c in get_children():
		c.free()
	_chunks.clear()
	lamps = Node3D.new()
	lamps.name = "lamps"
	add_child(lamps)
	_build_land()
	_build_plaza()
	_build_water()
	_things = Node3D.new()
	add_child(_things)
	_drawn_season = doc.season()
	_apply_season_surfaces()
	refresh_things()

## Dresses the world for its season, and redraws things only if it changed.
func refresh_season() -> void:
	if _drawn_season == doc.season():
		return
	_drawn_season = doc.season()
	_apply_season_surfaces()
	refresh_things(_theme)

func _apply_season_surfaces() -> void:
	var autumn := doc.season() == "autumn"
	var winter := doc.season() == "winter"
	_land_material.set_shader_parameter("grass_tint", AUTUMN_GRASS_TINT if autumn else GRASS_TINT)
	_land_material.set_shader_parameter("fallen_leaves", 0.7 if autumn else 0.0)
	_land_material.set_shader_parameter("snow", 1.0 if winter else 0.0)
	_plaza_stone.set_shader_parameter("fallen_leaves", 0.5 if autumn else 0.0)
	_plaza_stone.set_shader_parameter("snow", 1.0 if winter else 0.0)
	_kerb_stone.albedo_color = Color(0.42, 0.44, 0.47) if winter else Color(0.2, 0.19, 0.17)
	_pool.albedo_color = Color(0.56, 0.68, 0.74) if winter else Color(0.06, 0.19, 0.21)
	_pool.roughness = 0.45 if winter else 0.3
	var water := _water.material_override as ShaderMaterial
	water.set_shader_parameter("shallow_color", ICE_COLOR if winter else Vector3(0.07, 0.09, 0.06))
	water.set_shader_parameter("deep_color", ICE_DEEP_COLOR if winter else Vector3(0.008, 0.022, 0.026))
	water.set_shader_parameter("clear", 0.0 if winter else 0.7)
	water.set_shader_parameter("roughness", 0.4 if winter else 0.02)

func mesh_for(kind: String) -> Mesh:
	return season_mesh(kind, doc.season())

## The land's height map, for the land and water shaders.
func _height_image() -> Image:
	return Image.create_from_data(WorldDoc.TERRAIN_RES, WorldDoc.TERRAIN_RES, false, Image.FORMAT_RF, doc.heights.to_byte_array())

static func chunk_count() -> int:
	return (WorldDoc.TERRAIN_RES - 1) / CHUNK_CELLS

## One square of land. Normals read the neighbouring cells, so squares meet
## without a seam.
func chunk_arrays(cx: int, cy: int) -> Array:
	var res := WorldDoc.TERRAIN_RES
	var side := CHUNK_CELLS + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(side * side)
	normals.resize(side * side)
	uvs.resize(side * side)
	var step := WorldDoc.TERRAIN_SIZE / (res - 1)
	var heights := doc.heights
	var n := 0
	for j in range(cy * CHUNK_CELLS, (cy + 1) * CHUNK_CELLS + 1):
		for i in range(cx * CHUNK_CELLS, (cx + 1) * CHUNK_CELLS + 1):
			var o := j * res + i
			verts[n] = Vector3(i * step - WorldDoc.TERRAIN_SIZE / 2.0, heights[o], j * step - WorldDoc.TERRAIN_SIZE / 2.0)
			var l := heights[j * res + maxi(i - 1, 0)]
			var r := heights[j * res + mini(i + 1, res - 1)]
			var d := heights[maxi(j - 1, 0) * res + i]
			var u := heights[mini(j + 1, res - 1) * res + i]
			normals[n] = Vector3(l - r, 2.0 * step, d - u).normalized()
			uvs[n] = Vector2(float(i) / (res - 1), float(j) / (res - 1))
			n += 1
	if _chunk_indices.is_empty():
		_chunk_indices.resize(CHUNK_CELLS * CHUNK_CELLS * 6)
		var k := 0
		for j in CHUNK_CELLS:
			for i in CHUNK_CELLS:
				var a := j * side + i
				for idx in [a, a + 1, a + side, a + 1, a + side + 1, a + side]:
					_chunk_indices[k] = idx
					k += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _chunk_indices
	return arrays

func _draw_chunk(cx: int, cy: int) -> void:
	var mesh: ArrayMesh = _chunks[cy * chunk_count() + cx].mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk_arrays(cx, cy))

func _build_land() -> void:
	_land = Node3D.new()
	add_child(_land)
	_land_material = ShaderMaterial.new()
	_land_material.shader = load("res://src/scene/land.gdshader")
	_rebuild_weights_raw()
	_weights = ImageTexture.create_from_image(_blended_weights())
	_land_material.set_shader_parameter("weights", _weights)
	for i in GROUND_ORDER.size():
		var name: String = GROUND_ORDER[i]
		_land_material.set_shader_parameter("color_%d" % i, _texture("%s_diff" % name, true))
		_land_material.set_shader_parameter("normal_%d" % i, _texture("%s_nor_gl" % name, false))
		_land_material.set_shader_parameter("rough_%d" % i, _texture("%s_rough" % name, false))
	var count := chunk_count()
	for cy in count:
		for cx in count:
			var part := MeshInstance3D.new()
			part.mesh = ArrayMesh.new()
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			part.material_override = _land_material
			_land.add_child(part)
			_chunks.append(part)
			_draw_chunk(cx, cy)

static func _texture(name: String, _srgb: bool) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	var file := kit_file("textures/%s.jpg" % name)
	var img := Image.load_from_file(file) if FileAccess.file_exists(file) else null
	if img:
		img.generate_mipmaps()
		_textures[name] = ImageTexture.create_from_image(img)
	return _textures.get(name)

static func sky_texture(name: String) -> Texture2D:
	if _skies.has(name):
		return _skies[name]
	var file := kit_file("skies/%s.hdr" % name)
	var img := Image.load_from_file(file) if FileAccess.file_exists(file) else null
	if img:
		_skies[name] = ImageTexture.create_from_image(img)
	return _skies.get(name)

## Reads a base's halls once, so opening a world needn't read them again.
static func load_halls(base: String) -> Dictionary:
	if _halls.has(base):
		return _halls[base]
	var state := GLTFState.new()
	var importer := GLTFDocument.new()
	var path := kits_dir().path_join("halls/%s.glb" % base)
	if not FileAccess.file_exists(path) or importer.append_from_file(path, state) != OK or state.get_meshes().is_empty():
		return {}
	_halls[base] = {"importer": importer, "state": state}
	return _halls[base]

static func halls_scene(base: String) -> Node3D:
	var loaded := load_halls(base)
	return loaded.importer.generate_scene(loaded.state) if not loaded.is_empty() else null

func _rebuild_weights_raw() -> void:
	var res := WorldDoc.TERRAIN_RES
	_weights_raw.resize(res * res * 4)
	_weights_raw.fill(0)
	for o in res * res:
		_weights_raw[o * 4 + clampi(doc.ground[o], 0, 3)] = 255

func _blended_weights() -> Image:
	var res := WorldDoc.TERRAIN_RES
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, _weights_raw)
	img.resize(res / 3, res / 3, Image.INTERPOLATE_BILINEAR)
	img.resize(res, res, Image.INTERPOLATE_CUBIC)
	return img

func _build_plaza() -> void:
	_plaza = Node3D.new()
	add_child(_plaza)
	var disc := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = PLAZA_RADIUS
	shape.bottom_radius = PLAZA_RADIUS + 0.1
	shape.height = 0.1
	shape.radial_segments = 128
	shape.rings = 1
	disc.mesh = shape
	disc.position.y = -0.03
	var stone := ShaderMaterial.new()
	_plaza_stone = stone
	stone.shader = load("res://src/scene/plaza.gdshader")
	stone.set_shader_parameter("color_map", _texture("cobble_diff", true))
	stone.set_shader_parameter("normal_map_tex", _texture("cobble_nor_gl", false))
	stone.set_shader_parameter("rough_map", _texture("cobble_rough", false))
	disc.material_override = stone
	_plaza.add_child(disc)
	var kerb_stone := StandardMaterial3D.new()
	_kerb_stone = kerb_stone
	kerb_stone.albedo_color = Color(0.2, 0.19, 0.17)
	kerb_stone.roughness = 0.9
	var kerb_disc := MeshInstance3D.new()
	var kerb_shape := CylinderMesh.new()
	kerb_shape.top_radius = PLAZA_RADIUS + 0.5
	kerb_shape.bottom_radius = PLAZA_RADIUS + 0.6
	kerb_shape.height = 0.1
	kerb_shape.radial_segments = 128
	kerb_shape.rings = 1
	kerb_disc.mesh = kerb_shape
	kerb_disc.position.y = -0.04
	kerb_disc.material_override = kerb_stone
	_plaza.add_child(kerb_disc)
	var kerb_box := MeshInstance3D.new()
	var kerb_court := BoxMesh.new()
	kerb_court.size = Vector3((PLAZA_RADIUS + 0.5) * 2.0, 0.1, 32.5)
	kerb_box.mesh = kerb_court
	kerb_box.position = Vector3(0, -0.04, 16.25)
	kerb_box.material_override = kerb_stone
	_plaza.add_child(kerb_box)
	var court := MeshInstance3D.new()
	var court_shape := BoxMesh.new()
	court_shape.size = Vector3(PLAZA_RADIUS * 2.0, 0.1, 32.0)
	court.mesh = court_shape
	court.position = Vector3(0, -0.03, 16.0)
	court.material_override = stone
	_plaza.add_child(court)
	# The centrepiece characters rest round: a stone well inside the plaza's
	# half width of 2.2 metres.
	var half: float = Yard.data().plaza.half
	var rim := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = half * 0.92
	ring.bottom_radius = half
	ring.height = 0.7
	ring.radial_segments = 64
	rim.mesh = ring
	rim.position.y = 0.35
	rim.material_override = stone
	_plaza.add_child(rim)
	var pool := MeshInstance3D.new()
	var surface := CylinderMesh.new()
	surface.top_radius = half * 0.7
	surface.bottom_radius = half * 0.7
	surface.height = 0.02
	surface.radial_segments = 64
	pool.mesh = surface
	pool.position.y = 0.71
	var dark := StandardMaterial3D.new()
	_pool = dark
	dark.albedo_color = Color(0.06, 0.19, 0.21)
	dark.roughness = 0.3
	pool.material_override = dark
	_plaza.add_child(pool)

func _build_water() -> void:
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WorldDoc.TERRAIN_SIZE, WorldDoc.TERRAIN_SIZE)
	_water.mesh = plane
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/scene/water.gdshader")
	_heights = ImageTexture.create_from_image(_height_image())
	mat.set_shader_parameter("heights", _heights)
	mat.set_shader_parameter("terrain_size", WorldDoc.TERRAIN_SIZE)
	_water.material_override = mat
	add_child(_water)
	refresh_water()

func refresh_water() -> void:
	var level := doc.safe_water_level()
	_water.visible = level > WorldDoc.NO_WATER_BELOW
	_water.position.y = level
	(_water.material_override as ShaderMaterial).set_shader_parameter("level", level)
	if _water.visible and _heights_dirty:
		_heights_dirty = false
		_heights.update(_height_image())

## Notes that these land cells changed. Nothing is redrawn until flush_land.
func mark_land(cells: Array, ground_only := false) -> void:
	if cells.is_empty():
		return
	var res := WorldDoc.TERRAIN_RES
	var count := chunk_count()
	var lo := Vector2i(res, res)
	var hi := Vector2i(-1, -1)
	for o in cells:
		var i: int = o % res
		var j: int = o / res
		lo = Vector2i(mini(lo.x, i), mini(lo.y, j))
		hi = Vector2i(maxi(hi.x, i), maxi(hi.y, j))
		var kind: int = clampi(doc.ground[o], 0, 3)
		if _weights_raw[o * 4 + kind] != 255:
			for c in 4:
				_weights_raw[o * 4 + c] = 255 if c == kind else 0
			_weights_dirty = true
	if ground_only:
		return
	for cy in range(clampi((lo.y - 2) / CHUNK_CELLS, 0, count - 1), clampi((hi.y + 1) / CHUNK_CELLS, 0, count - 1) + 1):
		for cx in range(clampi((lo.x - 2) / CHUNK_CELLS, 0, count - 1), clampi((hi.x + 1) / CHUNK_CELLS, 0, count - 1) + 1):
			_dirty_chunks[Vector2i(cx, cy)] = true
			_relay_chunks[Vector2i(cx, cy)] = true
	_heights_dirty = true

func land_pending() -> bool:
	return not _dirty_chunks.is_empty() or _weights_dirty

## Redraws changed land for up to `budget_ms`, and says whether any is left, so
## a big brush catches up over a few frames instead of stalling one.
func flush_land(budget_ms := INF) -> bool:
	var start := Time.get_ticks_usec()
	if _weights_dirty:
		_weights_dirty = false
		_weights.update(_blended_weights())
	while not _dirty_chunks.is_empty():
		var c: Vector2i = _dirty_chunks.keys()[0]
		_dirty_chunks.erase(c)
		_draw_chunk(c.x, c.y)
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			return true
	if _water.visible and _heights_dirty:
		_heights_dirty = false
		_heights.update(_height_image())
	return false

## Stands things back on land that has moved.
func settle_things() -> void:
	if _relay_chunks.is_empty():
		return
	var cells := {}
	var chunk_metres := WorldDoc.TERRAIN_SIZE / chunk_count()
	for c in _relay_chunks:
		var x0: float = c.x * chunk_metres - WorldDoc.TERRAIN_SIZE / 2.0 - 2.0
		var z0: float = c.y * chunk_metres - WorldDoc.TERRAIN_SIZE / 2.0 - 2.0
		for cz in range(floori(z0 / CELL), floori((z0 + chunk_metres + 4.0) / CELL) + 1):
			for cx in range(floori(x0 / CELL), floori((x0 + chunk_metres + 4.0) / CELL) + 1):
				cells[Vector2i(cx, cz)] = true
	_relay_chunks.clear()
	for key in _by_cell.keys():
		if cells.has(_by_cell[key].cell):
			_draw_cell(key)

func refresh_land() -> void:
	var count := chunk_count()
	for cy in count:
		for cx in count:
			_dirty_chunks[Vector2i(cx, cy)] = true
			_relay_chunks[Vector2i(cx, cy)] = true
	_rebuild_weights_raw()
	_weights_dirty = true
	_heights_dirty = true
	flush_land()
	settle_things()

static func _key_of(t: Dictionary) -> String:
	return "%s@%d,%d" % [t.kind, floori(float(t.x) / CELL), floori(float(t.z) / CELL)]

## Rebuilds placed things as one MultiMesh per kind and area.
func refresh_things(theme := "light") -> void:
	_theme = theme
	for c in _things.get_children():
		c.free()
	for c in lamps.get_children():
		c.free()
	_nodes.clear()
	_key_lamps.clear()
	_by_cell.clear()
	for t in doc.data.things:
		_list_thing(t)
	for key in _by_cell.keys():
		_draw_cell(key)

func _list_thing(t: Dictionary) -> String:
	var key := _key_of(t)
	if not _by_cell.has(key):
		_by_cell[key] = {"kind": t.kind, "cell": Vector2i(floori(float(t.x) / CELL), floori(float(t.z) / CELL)), "things": []}
	_by_cell[key].things.append(t)
	return key

## Redraws only the areas these things are in.
func update_things(added: Array, removed: Array) -> void:
	var touched := {}
	for t in removed:
		var key := _key_of(t)
		if _by_cell.has(key):
			_by_cell[key].things = _by_cell[key].things.filter(func(o): return int(o.id) != int(t.id))
			touched[key] = true
	for t in added:
		touched[_list_thing(t)] = true
	for key in touched:
		_draw_cell(key)

func _draw_cell(key: String) -> void:
	if _nodes.has(key):
		_nodes[key].free()
		_nodes.erase(key)
	for lamp in _key_lamps.get(key, []):
		lamp.free()
	_key_lamps.erase(key)
	var list: Array = _by_cell[key].things
	if list.is_empty():
		_by_cell.erase(key)
		return
	var kind: String = _by_cell[key].kind
	var mesh := mesh_for(kind)
	if mesh.get_surface_count() == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, transform_of(list[i]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	_things.add_child(node)
	_nodes[key] = node
	var info: Dictionary = kit.get("models", {}).get(kind, {})
	if info.has("light") and _theme == "dark":
		var made := []
		for t in list:
			made.append(_add_lamp(info.light, t))
		_key_lamps[key] = made

func transform_of(t: Dictionary) -> Transform3D:
	var s: float = t.scale
	var b := Basis(Vector3.UP, t.turn).scaled(Vector3(s, s, s))
	return Transform3D(b, Vector3(t.x, Placing.base_height(doc, t), t.z))

func _add_lamp(light: Dictionary, t: Dictionary) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	var c: Array = light.color
	lamp.light_color = Color(c[0], c[1], c[2]).linear_to_srgb()
	lamp.light_energy = float(light.watts) * LAMP_FACTOR
	lamp.omni_attenuation = 2.0
	lamp.omni_range = 60.0
	lamp.shadow_enabled = true
	lamp.light_size = 0.12
	lamp.position = Vector3(t.x, Placing.base_height(doc, t) + float(light.height) * float(t.scale), t.z)
	lamps.add_child(lamp)
	return lamp

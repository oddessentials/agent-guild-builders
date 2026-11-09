class_name PlateBaker
extends Node
## Bakes a scene into the Yard's plate tiles. A bake need not be real time, so
## instead of approximating sky light, it lights the scene from many directions
## one at a time, each with real shadows, and adds the results in linear light:
## true sky occlusion and soft sun, on any GPU, without a path tracer. The sum
## then goes through the plates' colour transform (data/agx_mhc.lut).
##
## Passes for each chunk of a tile:
##   base: reflections, lamps and glow. Godot ties sky reflection to sky light,
##         so this is (sky light + reflection + lamps + glow) - (sky light).
##   sky:  SKY_SAMPLES directions over the hemisphere.
##   sun:  SUN_SAMPLES across the sun's disk; the sky's own disk the same way.
## The camera moves by a fraction of a pixel per pass, which antialiases.

signal progress(done: int, total: int)

const CHUNK := 1024
const PAD := 48
const CAMERA_BACK := 700.0
const DEPTH := 420.0
const QUALITY := {
	"final": {"sky": 128, "sun": 12, "disk": 4, "scale": 1.0, "atlas": 8192, "lamp_shadows": true},
	"draft": {"sky": 16, "sun": 2, "disk": 1, "scale": 0.5, "atlas": 4096, "lamp_shadows": false},
}

var _scene_root: Node3D
var _view: SubViewport
var _sum: SubViewport
var _out: SubViewport
var _rect: TextureRect
var _graded: TextureRect
var _add: CanvasItemMaterial
var _subtract: CanvasItemMaterial
var _camera: Camera3D
var _env: Environment
var _light: DirectionalLight3D
var _lamps: Node3D
var _passes: Array = []
var _glow_materials: Array = []
var _px := 0.05
var _q: Dictionary = QUALITY.final
var cancelled := false
var _done_chunks := 0
var _total_chunks := 0
var _vsync_before := -1
var _idle_before := false

## Sets up the viewports around `scene`, a Node3D holding only the world.
func setup(scene: Node3D, lamps: Node3D, quality := "final") -> void:
	_q = QUALITY[quality]
	_idle_before = OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	_vsync_before = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_scene_root = scene
	_lamps = lamps
	var size := Vector2i(Vector2(CHUNK + 2 * PAD, CHUNK + 2 * PAD) * float(_q.scale))
	RenderingServer.directional_shadow_atlas_set_size(int(_q.atlas), true)

	_out = SubViewport.new()
	_out.size = size
	_out.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_out)
	_sum = SubViewport.new()
	_sum.size = size
	_sum.use_hdr_2d = true
	_sum.transparent_bg = true
	_sum.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sum.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_out.add_child(_sum)
	_view = SubViewport.new()
	_view.size = size
	_view.use_hdr_2d = true
	_view.own_world_3d = true
	_view.mesh_lod_threshold = 0.0
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sum.add_child(_view)

	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_subtract = CanvasItemMaterial.new()
	_subtract.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	_rect = TextureRect.new()
	_rect.texture = _view.get_texture()
	_rect.size = Vector2(size)
	_rect.material = _add
	_sum.add_child(_rect)

	_graded = TextureRect.new()
	_graded.texture = _sum.get_texture()
	_graded.size = Vector2(size)
	var grade := ShaderMaterial.new()
	grade.shader = load("res://src/bake/grade.gdshader")
	var lut := load_lut()
	grade.set_shader_parameter("lut", lut.texture)
	grade.set_shader_parameter("lo", lut.lo)
	grade.set_shader_parameter("hi", lut.hi)
	_graded.material = grade
	_out.add_child(_graded)

	_view.add_child(scene)
	_env = Environment.new()
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	_view.add_child(world_env)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = CAMERA_BACK - DEPTH
	_camera.far = CAMERA_BACK + DEPTH
	_view.add_child(_camera)
	_camera.current = true
	_light = DirectionalLight3D.new()
	_light.shadow_enabled = true
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_light.directional_shadow_max_distance = CAMERA_BACK + DEPTH
	_light.shadow_bias = 0.03
	_light.shadow_normal_bias = 1.2
	_light.shadow_blur = 1.0
	_view.add_child(_light)
	_collect_glow()

func _exit_tree() -> void:
	if _vsync_before >= 0:
		DisplayServer.window_set_vsync_mode(_vsync_before)
		OS.low_processor_usage_mode = _idle_before
		RenderingServer.directional_shadow_atlas_set_size(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")), true)

static func load_lut() -> Dictionary:
	var f := FileAccess.open("res://data/agx_mhc.lut", FileAccess.READ)
	var size := f.get_32()
	var lo := f.get_float()
	var hi := f.get_float()
	var layer := size * size * 8
	var slices: Array[Image] = []
	for i in size:
		slices.append(Image.create_from_data(size, size, false, Image.FORMAT_RGBAH, f.get_buffer(layer)))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBAH, size, size, size, false, slices)
	return {"texture": tex, "lo": lo, "hi": hi}

func _collect_glow() -> void:
	var seen := {}
	for m in _glow_materials:
		seen[m] = true
	var stack: Array[Node] = [_scene_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mats := []
		if n is MeshInstance3D and n.mesh:
			for s in n.mesh.get_surface_count():
				mats.append(n.get_active_material(s))
		elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
			for s in n.multimesh.mesh.get_surface_count():
				mats.append(n.multimesh.mesh.surface_get_material(s))
		for m in mats:
			var glows: bool = (m is StandardMaterial3D and m.emission_enabled) or (m is ShaderMaterial and m.get_shader_parameter("glow_on") != null)
			if glows and not seen.has(m):
				seen[m] = true
				_glow_materials.append(m)

## The lights of one theme. Sun energy and colour are as Blender states them
## (linear, watts per square metre).
func prepare_theme(theme: String, sky: BakeSky, sun_energy: float, sun_color: Color, sun_angle: float) -> void:
	_passes = []
	for lamp in _lamps.get_children():
		lamp.shadow_enabled = _q.lamp_shadows
	var samples: int = _q.sky
	var patch := int(max(1.0, sky.image.get_height() * 0.5 / sqrt(float(samples))))
	var weight := 2.0 / samples
	for i in samples:
		var y := 1.0 - (i + 0.5) / samples
		var a := i * PI * (3.0 - sqrt(5.0))
		var r := sqrt(max(0.0, 1.0 - y * y))
		var d := Vector3(r * cos(a), y, r * sin(a))
		var c := sky.radiance(d, patch)
		_passes.append({"dir": d, "rgb": Color(c.r * weight, c.g * weight, c.b * weight), "specular": 0.0})
	var e := sun_energy / PI
	var to_sun := Yard.sun(theme).normalized()
	_passes += _disk(to_sun, Color(sun_color.r * e, sun_color.g * e, sun_color.b * e), sun_angle, _q.sun)
	if sky.source_dir != Vector3.ZERO:
		var s := sky.source_rgb
		_passes += _disk(sky.source_dir, Color(s.r / PI, s.g / PI, s.b / PI), deg_to_rad(BakeSky.PEAK_ANGLE), _q.disk)
	var material := PanoramaSkyMaterial.new()
	material.panorama = ImageTexture.create_from_image(sky.reflection_image())
	var sky_res := Sky.new()
	sky_res.sky_material = material
	sky_res.radiance_size = Sky.RADIANCE_SIZE_256
	_env.sky = sky_res
	_env.sky_rotation = Vector3(0, PI / 2, 0)

static func _disk(dir: Vector3, rgb: Color, angle: float, n: int) -> Array:
	var out := []
	var t := dir.cross(Vector3.UP).normalized()
	var b := dir.cross(t).normalized()
	var radius := tan(angle * 0.5)
	for i in n:
		var r := radius * sqrt((i + 0.5) / n)
		var a := i * PI * (3.0 - sqrt(5.0))
		out.append({"dir": (dir + t * r * cos(a) + b * r * sin(a)).normalized(), "rgb": Color(rgb.r / n, rgb.g / n, rgb.b / n), "specular": 1.0})
	return out

func _draw_view() -> void:
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

func _draw_and_sum() -> void:
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sum.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_sum.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER

func _glow(on: bool) -> void:
	for m in _glow_materials:
		if m is ShaderMaterial:
			m.set_shader_parameter("glow_on", 1.0 if on else 0.0)
		else:
			m.emission_enabled = on

func _chunk() -> void:
	_sum.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_rect.material = _add
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_lamps.visible = true
	_light.visible = false
	_glow(true)
	for i in 4:
		await _draw_view()
	await _draw_and_sum()
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_lamps.visible = false
	_glow(false)
	_rect.material = _subtract
	for i in 4:
		await _draw_view()
	await _draw_and_sum()
	_rect.material = _add
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_light.visible = true
	var first := true
	var index := 0
	for p in _passes:
		if cancelled:
			return
		index += 1
		var c: Color = p.rgb
		var peak: float = max(c.r, c.g, c.b)
		if peak <= 1e-6:
			continue
		var d: Vector3 = p.dir
		_light.look_at_from_position(d * 100.0, Vector3.ZERO, Vector3.UP if abs(d.y) < 0.99 else Vector3.FORWARD)
		_light.light_color = Color(c.r / peak, c.g / peak, c.b / peak).linear_to_srgb()
		_light.light_energy = peak
		_light.light_specular = p.specular
		_camera.h_offset = (_halton(index, 2) - 0.5) * _px
		_camera.v_offset = (_halton(index, 3) - 0.5) * _px
		if first:
			first = false
			await _draw_view()
		await _draw_and_sum()
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	_out.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

static func chunks_in(tile: Dictionary) -> int:
	return ceili(float(tile.width) / CHUNK) * ceili(float(tile.height) / CHUNK)

## Counts progress in chunks across a whole job, however many tiles it spans.
func set_progress_total(total: int) -> void:
	_total_chunks = total
	_done_chunks = 0

static func _halton(i: int, base: int) -> float:
	var f := 1.0
	var r := 0.0
	var n := i
	while n > 0:
		f /= base
		r += f * (n % base)
		n /= base
	return r

## Renders one tile (from Yard.tiles) and returns it, graded and 8-bit.
func bake_tile(tile: Dictionary) -> Image:
	var a := Yard.axes()
	var fwd: Vector3 = a.forward
	var right: Vector3 = a.right
	var up: Vector3 = a.up
	var density: float = tile.density
	_px = 1.0 / density
	_camera.size = float(CHUNK + 2 * PAD) / density
	var w: int = tile.width
	var h: int = tile.height
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var rc: float = tile.right[0] + (x + CHUNK / 2.0) / density
			var uc: float = tile.up[1] - (y + CHUNK / 2.0) / density
			_camera.transform = Transform3D(Basis(right, up, -fwd), right * rc + up * uc - fwd * CAMERA_BACK)
			await _chunk()
			if cancelled:
				return img
			var g := _out.get_texture().get_image()
			g.convert(Image.FORMAT_RGB8)
			if float(_q.scale) < 1.0:
				g.resize(CHUNK + 2 * PAD, CHUNK + 2 * PAD, Image.INTERPOLATE_LANCZOS)
			img.blit_rect(g, Rect2i(PAD, PAD, CHUNK, CHUNK), Vector2i(x, y))
			_done_chunks += 1
			progress.emit(_done_chunks, _total_chunks)
			x += CHUNK
		y += CHUNK
	return img

## Bakes every tile of one theme into `out_dir` as the Yard's WebP files.
## `mood` is {sky: BakeSky, energy, color, angle}.
func bake_theme(theme: String, mood: Dictionary, out_dir: String) -> Error:
	var all := []
	for layer in Yard.layers():
		all += Yard.tiles(layer)
	_collect_glow()
	prepare_theme(theme, mood.sky, mood.energy, mood.color, mood.angle)
	for tile in all:
		var img: Image = await bake_tile(tile)
		if cancelled:
			return ERR_SKIP
		var err := img.save_webp(out_dir.path_join("%s-%s.webp" % [theme, tile.name]), true, 0.72)
		if err != OK:
			return err
	return OK

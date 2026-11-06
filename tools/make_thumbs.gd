extends SceneTree
## Makes data/thumbs: a small picture of each kit item, mix, ground and template.
## godot --path . --script res://tools/make_thumbs.gd

const OUT := "res://data/thumbs"
const ITEM := Vector2i(232, 160)
const TEMPLATE := Vector2i(600, 340)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if OS.get_cmdline_user_args().has("templates"):
		for key in Templates.LIST:
			await _template(key)
		quit()
		return
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var stage := _stage()
	for kind in models:
		await _shoot(stage, [kind], kind)
	for key in Placing.MIXES:
		await _shoot(stage, Placing.MIXES[key].kinds, "mix_" + key)
	stage.free()
	for key in WorldScene.GROUND_ORDER:
		var img := Image.load_from_file(WorldScene.kit_file("textures/%s_diff.jpg" % key))
		img.resize(ITEM.x, ITEM.y, Image.INTERPOLATE_LANCZOS)
		_save(img, "ground_" + key)
	for key in Templates.LIST:
		await _template(key)
	print("THUMBS DONE")
	quit(0)

func _stage() -> SubViewport:
	var v := SubViewport.new()
	v.size = ITEM * 2
	v.own_world_3d = true
	v.msaa_3d = Viewport.MSAA_4X
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(v)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.94, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	v.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.look_at_from_position(Vector3(1, 2, 1.5), Vector3.ZERO, Vector3.UP)
	v.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	v.add_child(cam)
	cam.current = true
	v.set_meta("camera", cam)
	return v

func _shoot(stage: SubViewport, kinds: Array, name: String) -> void:
	var holder := Node3D.new()
	stage.add_child(holder)
	var box := AABB()
	var seen := {}
	var x := 0.0
	for kind in kinds:
		if seen.has(kind):
			continue
		seen[kind] = true
		var mesh := WorldScene.mesh_of(kind)
		var part := MeshInstance3D.new()
		part.mesh = mesh
		var aabb := mesh.get_aabb()
		part.position.x = x - aabb.position.x
		holder.add_child(part)
		var placed := AABB(aabb.position + part.position, aabb.size)
		box = placed if box.size == Vector3.ZERO else box.merge(placed)
		x += aabb.size.x * 0.9
	var cam: Camera3D = stage.get_meta("camera")
	var centre := box.get_center()
	var dir := Vector3(0.45, 0.45, 1.0).normalized()
	cam.size = maxf(box.size.y * 1.12, maxf(box.size.x, box.size.z) * 1.05 * float(ITEM.y) / ITEM.x)
	var reach := box.size.length() + 10.0
	cam.far = reach * 3.0
	cam.look_at_from_position(centre + dir * reach, centre, Vector3.UP)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := stage.get_texture().get_image()
	img.resize(ITEM.x, ITEM.y, Image.INTERPOLATE_LANCZOS)
	_save(img, name)
	holder.free()

func _template(key: String) -> void:
	var script: GDScript = load("res://src/ui/editor_view.gd")
	var view: Control = script.new()
	root.size = Vector2i(1674, 790)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	view.open(Templates.create(key, "guild", key, 7), "")
	view.set_process(false)
	view._select_tool(view.Tool.LOOK)
	var framing := {
		"meadow": [0.3, Vector3(0, 1, -25)],
		"lakeside": [0.42, Vector3(-20, 1, -24)],
		"highland": [0.26, Vector3(10, 1, -25)],
	}
	view._zoom = framing[key][0]
	view._target = framing[key][1]
	view._place_camera()
	view._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 12:
		await RenderingServer.frame_post_draw
	var img: Image = view._viewport.get_texture().get_image()
	var want := float(TEMPLATE.x) / TEMPLATE.y
	var cut_w := mini(img.get_width(), int(img.get_height() * want))
	var cut_h := int(cut_w / want)
	img = img.get_region(Rect2i((img.get_width() - cut_w) / 2, (img.get_height() - cut_h) / 2, cut_w, cut_h))
	img.resize(TEMPLATE.x, TEMPLATE.y, Image.INTERPOLATE_LANCZOS)
	_save(img, "template_" + key)
	view.free()

func _save(img: Image, name: String) -> void:
	img.convert(Image.FORMAT_RGB8)
	img.save_webp("%s/%s.webp" % [OUT, name], true, 0.82)

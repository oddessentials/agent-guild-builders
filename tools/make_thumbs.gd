extends SceneTree
## Makes data/thumbs: a small picture of each kit item, mix, ground and template.
## godot --path . --script res://tools/make_thumbs.gd

const OUT := "res://data/thumbs"
const ITEM := ThumbStage.ITEM
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
		if not _made(kind):
			await _shoot(stage, [kind], kind)
	for key in Placing.MIXES:
		if not _made("mix_" + key):
			await _shoot(stage, Placing.MIXES[key].kinds, "mix_" + key)
	stage.free()
	for key in WorldScene.GROUND_ORDER:
		var img := Image.load_from_file(WorldScene.kit_file("textures/%s_diff.jpg" % key))
		img.resize(ITEM.x, ITEM.y, Image.INTERPOLATE_LANCZOS)
		_save(img, "ground_" + key)
	for key in Templates.LIST:
		if not _made("template_" + key):
			await _template(key)
	print("THUMBS DONE")
	quit(0)

func _made(name: String) -> bool:
	return FileAccess.file_exists("%s/%s.webp" % [OUT, name])

func _stage() -> SubViewport:
	return ThumbStage.make(root)

func _shoot(stage: SubViewport, kinds: Array, name: String) -> void:
	var meshes := []
	var seen := {}
	for kind in kinds:
		if not seen.has(kind):
			seen[kind] = true
			meshes.append(WorldScene.mesh_of(kind))
	_save(await ThumbStage.shoot(stage, meshes), name)

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
		"blank": [0.5, Vector3(0, 1, -6)],
		"island": [0.2, Vector3(0, 1, 6)],
		"canyon": [0.26, Vector3(-6, 1, -22)],
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

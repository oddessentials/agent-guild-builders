extends SceneTree
var failed := 0
var passed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL ", what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var only := OS.get_cmdline_user_args()
	for t in [["grid", _grid_matches_shipped_plates], ["cover", _tiles_cover_every_view], ["clearance", _clearance], ["document", _document], ["history", _history], ["templates", _templates], ["packages", _packages], ["editor", _editor], ["library", _library], ["land", _land], ["placing", _placing], ["loader", _loader], ["arrange", _arrange], ["place_panel", _place_panel], ["seasons", _seasons], ["review", _review], ["review_slider_edits", _review_slider_edits], ["review_hidden", _review_hidden], ["castle", _castle], ["seating", _seating], ["custom", _custom], ["mcp", _mcp]]:
		if only.is_empty() or only.has(t[0]):
			check(await t[1].call() == true, t[0] + ": completes without a script error")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _grid_matches_shipped_plates() -> bool:
	var shipped := OS.get_environment("AGENT_GUILD_CHECKOUT").path_join("web/yard/assets/gnomeland/plates.json")
	if not FileAccess.file_exists(shipped):
		printerr("Set AGENT_GUILD_CHECKOUT to an Agent Guild checkout containing web/yard/assets/gnomeland/plates.json before running grid.")
		return false
	var spec = JSON.parse_string(FileAccess.get_file_as_string(shipped))
	var ours := Yard.manifest("x")
	for theme in Yard.THEMES:
		check(spec.themes[theme].size() == ours.themes[theme].size(), "layer count " + theme)
		for l in spec.themes[theme].size():
			var a: Array = spec.themes[theme][l].tiles
			var b: Array = ours.themes[theme][l].tiles
			check(a.size() == b.size(), "tile count layer %d" % l)
			for t in min(a.size(), b.size()):
				check(int(a[t].width) == int(b[t].width) and int(a[t].height) == int(b[t].height), "tile size %s: %d x %d, ours %d x %d" % [a[t].file, a[t].width, a[t].height, b[t].width, b[t].height])
				for k in ["right", "up"]:
					for e in 2:
						check(absf(a[t][k][e] - b[t][k][e]) < 0.1, "tile %s %s: %f, ours %f" % [a[t].file, k, a[t][k][e], b[t][k][e]])
	return true

func _tiles_cover_every_view() -> bool:
	var extent: Dictionary = Yard.data().extent
	var covered := Yard.tiles(Yard.layers()[0])
	var lo: float = covered[0].right[0]
	var hi: float = covered[-1].right[1]
	check(lo <= extent.right[0] + 0.01 and hi >= extent.right[1] - 0.01, "base layer spans the view")
	return true

func _clearance() -> bool:
	check(Clearance.live_distance(0, 0) == 0.0, "plaza is live")
	check(Clearance.live_distance(0, 25) == 0.0, "front rows are live")
	check(Clearance.refuse(0, 0, 1) != "", "refuses the plaza")
	check(Clearance.tall_clear(-120, -120, 8), "far back is clear")
	check(not Clearance.tall_clear(40, 45, 30), "tall in front rises over the yard")
	check(Clearance.refuse(120, -120, 1.0) == "", "low, far away is fine")
	return true

func _document() -> bool:
	var doc := WorldDoc.create("guild", "Test", 7)
	var a := doc.add_thing("rock", 50, 60, 0.1, 1.2)
	doc.heights[100] = 3.5
	doc.ground[5] = 2
	var dir := OS.get_user_data_dir().path_join("test-world")
	check(doc.save(dir) == OK, "saves")
	check(doc.save(dir) == OK, "saves over itself")
	var back := WorldDoc.open(dir)
	check(back != null, "opens")
	if back:
		check(back.data.things.size() == 1 and int(back.data.things[0].id) == a.id, "things survive")
		check(is_equal_approx(back.heights[100], 3.5) and back.ground[5] == 2, "land survives")
		check(back.add_thing("rock", 1, 1, 0, 1).id != a.id, "ids stay unique after opening")
	var future := {"format": WorldDoc.FORMAT + 1}
	var f := FileAccess.open(dir.path_join("world.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(future))
	f.close()
	check(WorldDoc.open(dir) == null, "refuses a newer format")
	WorldDoc.remove_folder(dir)
	var keep := WorldDoc.create("guild", "Keep", 1)
	keep.add_thing("rock", 5, 5, 0, 1)
	keep.save(dir)
	DirAccess.rename_absolute(dir, dir + ".old")
	var recovered := WorldDoc.open(dir)
	check(recovered != null and recovered.data.things.size() == 1, "recovers the old copy after a save cut short")
	var thumb := FileAccess.open(dir.path_join(WorldDoc.THUMB), FileAccess.WRITE)
	thumb.store_string("x")
	thumb.close()
	keep.save(dir)
	check(FileAccess.file_exists(dir.path_join(WorldDoc.THUMB)), "saving keeps the picture")
	check(not DirAccess.dir_exists_absolute(dir + ".old") and not DirAccess.dir_exists_absolute(dir + ".saving"), "saving leaves nothing behind")
	WorldDoc.remove_folder(dir)
	return true

func _history() -> bool:
	var doc := WorldDoc.create("guild", "Test", 7)
	var h := History.new(doc)
	h.place("rock", 50, 60, 0, 1)
	check(doc.data.things.size() == 1, "place")
	h.undo()
	check(doc.data.things.is_empty(), "undo place")
	h.redo()
	check(doc.data.things.size() == 1, "redo place")
	var id: int = doc.data.things[0].id
	h.remove(id)
	h.undo()
	check(doc.data.things.size() == 1 and int(doc.data.things[0].id) == id, "undo remove keeps the id")
	h.land_stroke("Shape land", {10: [2.0, 0], 11: [3.0, 1]})
	check(is_equal_approx(doc.heights[11], 3.0) and doc.ground[11] == 1, "stroke")
	h.undo()
	check(is_zero_approx(doc.heights[11]) and doc.ground[11] == 0, "undo stroke")
	check(h.can_redo() and h.redo_label() == "Shape land", "says what redo will do")
	h.redo()
	check(h.undo_label() == "Shape land", "says what undo will do")
	var parts := []
	h.changed.connect(func(part, detail): parts.append([part, detail]))
	var things := [doc.add_thing("rock", 1, 1, 0, 1), doc.add_thing("rock", 2, 2, 0, 1)]
	var count: int = doc.data.things.size()
	h.things_edit("Paint", things, [], true)
	check(parts.is_empty(), "recording a finished stroke redraws nothing")
	check(doc.data.things.size() == count, "recording a finished stroke doesn't add twice")
	h.undo()
	check(doc.data.things.size() == count - 2, "one undo removes a whole stroke of things")
	check(parts[0][0] == History.Part.THINGS and parts[0][1].removed == things, "undo says which things went")
	h.redo()
	check(doc.data.things.size() == count, "redo brings them all back")
	parts.clear()
	var mood: Dictionary = doc.data.mood.light
	mood.sun_energy = 4.0
	h.set_value("Sun", mood, "sun_energy", 4.0, 3.3)
	h.undo()
	check(is_equal_approx(float(mood.sun_energy), 3.3), "undo returns to the value before a live preview")
	check(parts[-1][0] == History.Part.VALUE, "a value change names itself")
	h.set_values("Sky", mood, {"sky": "moon", "strength": 0.3})
	h.undo()
	check(mood.sky == "day" and is_equal_approx(float(mood.strength), 0.9), "changing a sky is one undo step")
	h.dispose()
	return true

func _templates() -> bool:
	for key in Templates.LIST:
		var a := Templates.create(key, "guild", "T", 42)
		var b := Templates.create(key, "guild", "T", 42)
		check(JSON.stringify(a.data.things) == JSON.stringify(b.data.things) and a.heights == b.heights, key + ": the same seed gives the same world")
		check(JSON.stringify(a.data.things) != JSON.stringify(Templates.create(key, "guild", "T", 43).data.things), key + ": another seed differs")
		var legal := true
		var models: Dictionary = WorldScene.load_kit().get("models", {})
		for t in a.data.things:
			if Clearance.refuse(t.x, t.z, a.height_at(t.x, t.z) + float(models.get(t.kind, {}).get("height", 1.0)) * float(t.scale)) != "":
				legal = false
		check(legal, key + ": everything placed keeps the placement rules")
		var flat := true
		for j in WorldDoc.TERRAIN_RES:
			for i in WorldDoc.TERRAIN_RES:
				var p := WorldDoc.cell_to_world(i, j)
				if Clearance.live_distance(p.x, p.y) < 0.5 and absf(a.heights[j * WorldDoc.TERRAIN_RES + i]) > 0.001:
					flat = false
		check(flat, key + ": the ground crews stand on is flat")
		check(Clearance.check_world(a).get("valid", false), key + ": a new world is ready to export")
		if float(a.data.water_level) > -50.0 and key != "island":
			var wet := 0
			for h in a.heights:
				if h < float(a.data.water_level):
					wet += 1
			check(float(wet) / a.heights.size() < 0.12, key + ": water stays in its lake")
			check(a.ground[(WorldDoc.TERRAIN_RES * WorldDoc.TERRAIN_RES) / 2] != 3, key + ": the plaza isn't shore")
	var blank := Templates.create("blank", "guild", "T", 42)
	check(blank.data.things.size() <= 12, "blank: nearly empty")
	var island := Templates.create("island", "guild", "T", 42)
	var at_edge := true
	for t in [[-200.0, 0.0], [200.0, 0.0], [0.0, -200.0], [0.0, 200.0]]:
		at_edge = at_edge and island.height_at(t[0], t[1]) < float(island.data.water_level)
	check(at_edge, "island: water on every side")
	check(island.height_at(0.0, 0.0) > float(island.data.water_level), "island: the Yard is dry")
	check(island.data.things.size() < 500, "island: stays sparse")
	var canyon := Templates.create("canyon", "guild", "T", 42)
	var up := Clearance._ground_up()
	var behind := up * 70.0
	var front := up * -62.0
	check(canyon.height_at(behind.x, behind.y) > 20.0, "canyon: cliffs rise behind the Yard")
	check(canyon.height_at(front.x, front.y) < float(canyon.data.water_level), "canyon: a gorge runs in front of it")
	check(canyon.data.things.any(func(t): return t.kind == "rock_face"), "canyon: rock faces dress the walls")
	return true

func _pack(path: String, changes: Dictionary = {}, drop: Array = [], meta_changes: Dictionary = {}, relist := true) -> void:
	var files := {}
	files["web/sky-light.hdr"] = "#?RADIANCE".to_ascii_buffer()
	files["web/sky-dark.hdr"] = "#?RADIANCE".to_ascii_buffer()
	var tiny := Image.create(16, 16, false, Image.FORMAT_RGB8).save_webp_to_buffer(true, 0.5)
	for name in WorldPackage.plate_names():
		files[name] = tiny
	var listing := {}
	for k in files:
		listing[k] = {"size": files[k].size(), "sha256": WorldPackage.sha256(files[k])}
	for k in changes:
		files[k] = changes[k]
		if relist:
			listing[k] = {"size": files[k].size(), "sha256": WorldPackage.sha256(files[k])}
	var meta := {"format": WorldPackage.FORMAT, "kind": WorldPackage.KIND, "title": "Test", "base": "guild", "environment": WorldPackage.environment_abi(), "generator": 1, "files": listing}
	for k in meta_changes:
		meta[k] = meta_changes[k]
	var entries := [[WorldPackage.MANIFEST, JSON.stringify(meta).to_utf8_buffer()]]
	for k in files:
		if not drop.has(k):
			entries.append([k, files[k]])
	_store(path, WorldPackage.tar_gz(entries))

func _store(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()

func _refused(path: String, what: String, changes: Dictionary = {}, drop: Array = [], meta_changes: Dictionary = {}, relist := true) -> void:
	_pack(path, changes, drop, meta_changes, relist)
	check(not WorldPackage.accepted(WorldPackage.check(path)), "refuses " + what)

func _packages() -> bool:
	var path := OS.get_user_data_dir().path_join("test.agworld")
	_pack(path)
	var good := WorldPackage.check(path)
	check(WorldPackage.accepted(good), "accepts a good package: " + str(good))
	var x := "x".to_utf8_buffer()
	_refused(path, "a page", {"web/x.html": "<script>alert(1)</script>".to_utf8_buffer()})
	_refused(path, "a script", {"web/x.js": x})
	_refused(path, "an SVG", {"web/x.svg": "<svg onload=alert(1)>".to_utf8_buffer()})
	_refused(path, "Godot resources", {"scene.tscn": x})
	_refused(path, "a path out of the folder", {"../../evil.webp": x})
	_refused(path, "an absolute path", {"/etc/evil.webp": x})
	_refused(path, "a backslash path", {"web\\..\\evil.webp": x})
	_refused(path, "a device name", {"web/NUL.webp": x})
	_refused(path, "a drive path", {"C:/evil.webp": x})
	_refused(path, "a stream name", {"web/x.webp:evil": x})
	_refused(path, "names that differ only by case", {"WEB/SKY-LIGHT.HDR": "#?RADIANCE".to_ascii_buffer()})
	_refused(path, "HTML pretending to be a picture", {"web/light-base-0-0.webp": "<html><script>".to_utf8_buffer()})
	var huge := Image.create(16, 16, false, Image.FORMAT_RGB8).save_webp_to_buffer(false)
	check(huge.slice(12, 16).get_string_from_ascii() == "VP8L", "lossless test picture")
	huge[21] = 0xff
	huge[22] = 0xff
	huge[23] = 0xff
	huge[24] = 0x0f
	_refused(path, "a picture claiming enormous dimensions", {"web/light-base-0-0.webp": huge})
	_refused(path, "a non-sky file named as a sky", {"web/sky-light.hdr": x})
	_refused(path, "a missing picture", {}, ["web/light-base-0-0.webp"])
	_refused(path, "a changed picture", {"web/light-base-0-0.webp": Image.create(8, 8, false, Image.FORMAT_RGB8).save_webp_to_buffer(true, 0.5)}, [], {}, false)
	_refused(path, "a newer format", {}, [], {"format": 99})
	_refused(path, "another kind of file", {}, [], {"kind": "mod"})
	_refused(path, "an unknown base", {}, [], {"base": "../../x"})
	_refused(path, "a long title", {}, [], {"title": "x".repeat(500)})
	_refused(path, "a world for a different Yard", {}, [], {"environment": "0"})
	_refused(path, "bad light colours", {}, [], {"lights": {"light": {"sun": "red", "hemi": 1}, "dark": {"sun": 1, "hemi": 1}}})
	var tiny := Image.create(16, 16, false, Image.FORMAT_RGB8).save_webp_to_buffer(true, 0.5)
	_store(path, WorldPackage.tar_gz([["web/sky-light.hdr", tiny]]))
	check(not WorldPackage.accepted(WorldPackage.check(path)), "refuses a manifest that isn't first")
	var meta := {"format": 1, "kind": WorldPackage.KIND, "title": "T", "base": "guild", "environment": WorldPackage.environment_abi(), "files": {}}
	_store(path, WorldPackage.tar_gz([[WorldPackage.MANIFEST, JSON.stringify(meta).to_utf8_buffer()], ["web/link", PackedByteArray(), "2"]]))
	check(not WorldPackage.accepted(WorldPackage.check(path)), "refuses a symlink")
	var zeros := PackedByteArray()
	zeros.resize(40 * 1024 * 1024)
	_store(path, zeros.compress(FileAccess.COMPRESSION_GZIP))
	check(not WorldPackage.accepted(WorldPackage.check(path)), "refuses a file that expands enormously")
	_store(path, "not a package".to_ascii_buffer())
	check(not WorldPackage.accepted(WorldPackage.check(path)), "refuses something that isn't a package")
	DirAccess.remove_absolute(path)
	return true

## Drives the real editor with simulated mouse input.
func _click(view: Control, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	view._on_stage_input(e)

func _drag(view: Control, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	view._on_stage_input(e)

## A point on screen over open ground, far enough out for anything small.
func _open_ground(view: Control) -> Vector2:
	var size: Vector2 = view._viewport.size
	for y in range(40, int(size.y) - 40, 20):
		for x in range(40, int(size.x) - 40, 20):
			var hit = view._ground_at(Vector2(x, y))
			if hit != null and Clearance.live_distance(hit.x, hit.z) > 12.0:
				return Vector2(x, y)
	return Vector2.ZERO

func _editor() -> bool:
	var doc := WorldDoc.create("guild", "Test", 3)
	var script: GDScript = load("res://src/ui/editor_view.gd")
	var view: Control = script.new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	view.open(doc, "")
	await process_frame
	var spot := _open_ground(view)
	check(spot != Vector2.ZERO, "editor: finds open ground under the pointer")
	view.place_kind = "stone"
	view._next_scale = 1.0
	view._select_tool(view.Tool.SCATTER)
	_click(view, spot, true)
	_click(view, spot, false)
	check(doc.data.things.size() == 1, "editor: a click places one thing")
	view.history.undo()
	check(doc.data.things.is_empty(), "editor: undo removes it")
	view.history.redo()
	check(doc.data.things.size() == 1, "editor: redo restores it")
	var plaza_hit: Vector2 = view._camera.unproject_position(Vector3(0, 0, 0))
	_click(view, plaza_hit, true)
	_click(view, plaza_hit, false)
	check(doc.data.things.size() == 1, "editor: won't place on the plaza")
	check(view._status.text != "", "editor: says why it refused")
	check(view._hint.visible and view._hint_text.text == view._status.text, "editor: says why at the pointer without the mouse moving")
	var aim := _open_ground(view) + Vector2(60, 40)
	var aim_from: Vector3 = view._camera.project_ray_origin(aim)
	var aim_along: Vector3 = view._camera.project_ray_normal(aim)
	var flat_hit: Vector3 = aim_from + aim_along * (-aim_from.y / aim_along.y)
	var aim_hit: Vector3 = view._ground_at(aim)
	check(flat_hit.distance_to(aim_hit) < 0.01, "editor: a click lands on the ground under the pointer")
	var placed_before: int = doc.data.things.size()
	_click(view, aim, true)
	_click(view, aim, false)
	var placed: Dictionary = doc.data.things[-1]
	check(doc.data.things.size() == placed_before + 1 and Vector2(placed.x, placed.z).distance_to(Vector2(flat_hit.x, flat_hit.z)) < 0.01, "editor: one thing lands exactly where clicked")
	check(view._placed_ring.visible and not view._ghost.visible and not view._hint.visible, "editor: a placed thing is marked, with no refusal showing")
	check(view._status.text.begins_with("Placed "), "editor: says it was placed")
	_drag(view, aim + Vector2(2, 0))
	check(not view._hint.visible, "editor: a small jitter after placing shows no refusal")
	_click(view, aim, true)
	_click(view, aim, false)
	check(doc.data.things.size() == placed_before + 1 and view._hint.visible, "editor: clicking the same spot again is refused at the pointer")
	view._placed_ring_until = 0.0
	view._process(0.0)
	check(not view._placed_ring.visible, "editor: the placed marker goes away")
	view.history.undo()
	view._select_tool(view.Tool.ERASE)
	_click(view, spot, true)
	_click(view, spot, false)
	check(doc.data.things.is_empty(), "editor: clear removes it")
	view._select_tool(view.Tool.LAND)
	view.land_mode = "raise"
	var before := doc.height_at(0, 0)
	var hit = view._ground_at(spot)
	var total_before := 0.0
	for h in doc.heights:
		total_before += h
	_click(view, spot, true)
	_drag(view, spot + Vector2(10, 0))
	_click(view, spot + Vector2(10, 0), false)
	var total_after := 0.0
	for h in doc.heights:
		total_after += h
	check(total_after > total_before, "editor: a stroke raises land")
	view.history.undo()
	var total_undone := 0.0
	for h in doc.heights:
		total_undone += h
	check(absf(total_undone - total_before) < 0.01, "editor: one undo removes the whole stroke")
	view._select_tool(view.Tool.LAND)
	view.brush_radius = 40.0
	_click(view, plaza_hit, true)
	_click(view, plaza_hit, false)
	check(is_equal_approx(doc.height_at(0, 0), before), "editor: the crews' ground stays flat")
	view.history.undo()
	view._select_tool(view.Tool.GROUND)
	view.ground_kind = 2
	view.brush_radius = 8.0
	_click(view, spot, true)
	_click(view, spot, false)
	check(doc.ground.count(2) > 0, "editor: paints ground")
	view._select_tool(view.Tool.WATER)
	view.history.set_value("Water", doc.data, "water_level", -1.0)
	check(is_equal_approx(float(doc.data.water_level), -1.0), "editor: sets water")
	view._select_tool(view.Tool.MOOD)
	view._toggle_time()
	check(view.theme_name == "dark", "editor: switches to dusk")
	var day_sun: float = doc.data.mood.light.sun_energy
	var sun_slider: HSlider = null
	for c in view._options.get_children():
		if c is HSlider:
			sun_slider = c
			break
	sun_slider.drag_started.emit()
	sun_slider.value = 4.5
	check(is_equal_approx(float(doc.data.mood.dark.sun_energy), 4.5), "editor: a slider previews live, on the time showing")
	sun_slider.drag_ended.emit(true)
	check(float(doc.data.mood.light.sun_energy) == day_sun, "editor: changing dusk leaves day alone")
	view.history.undo()
	check(is_equal_approx(float(doc.data.mood.dark.sun_energy), 2.4), "editor: one undo returns a slider")
	var fresh: HSlider = null
	for c in view._options.get_children():
		if c is HSlider:
			fresh = c
			break
	check(is_equal_approx(fresh.value, 2.4), "editor: the panel follows undo")
	view._toggle_time()
	view._select_tool(view.Tool.ERASE)
	for i in 3:
		doc.add_thing("stone", 60.0 + i, 60.0, 0.0, 1.0)
	view._scene.refresh_things("light")
	var cluster: Vector2 = view._camera.unproject_position(Vector3(61, 0, 60))
	var counted: int = view.history._undo.get_current_action()
	view.brush_radius = 8.0
	_click(view, cluster, true)
	_click(view, cluster, false)
	check(view.history._undo.get_current_action() == counted + 1, "editor: clearing many things is one undo step")
	view.history.undo()
	view._select_tool(view.Tool.SCATTER)
	view.place_mode = "paint"
	view.paint_choice = "mix:wildflowers"
	view.brush_radius = 6.0
	doc.data.things.clear()
	view._scene.refresh_things("light")
	counted = view.history._undo.get_current_action()
	_click(view, spot, true)
	for i in 8:
		_drag(view, spot + Vector2(i * 12, 0))
	_click(view, spot + Vector2(96, 0), false)
	var painted: Array = doc.data.things.map(func(t): return t.kind)
	check(painted.size() >= 2 and view.history._undo.get_current_action() == counted + 1, "editor: a painted drift is one undo step")
	var mixed := true
	for k in painted:
		mixed = mixed and Placing.MIXES.wildflowers.kinds.has(k)
	check(mixed, "editor: a mix paints only its own things")
	view.history.undo()
	check(doc.data.things.is_empty(), "editor: undo removes the whole drift")
	view.place_mode = "one"
	view.place_kind = "grass"
	view._select_tool(view.Tool.SCATTER)
	check(view._zone_wanted < 0.0, "editor: low things shade nothing")
	view._choose("tree_oak")
	var zone_shown: float = view._zone_wanted
	check(zone_shown >= 9.0 * Placing.SMALLEST, "editor: tall things show clearance for their size")
	view._roll_next()
	check(view._zone_wanted == zone_shown, "editor: the clearance shown doesn't change from one click to the next")
	view._select_tool(view.Tool.LAND)
	check(view._zone_wanted == 0.0, "editor: shaping shows the ground that stays flat")
	view._select_tool(view.Tool.LOOK)
	check(view._zone_wanted < 0.0, "editor: looking shades nothing")
	view._select_tool(view.Tool.SCATTER)
	view._next_scale = 1.0
	_click(view, plaza_hit, true)
	_click(view, plaza_hit, false)
	check(doc.data.things.is_empty(), "editor: a tree is refused on the plaza")
	var z0: float = view._zoom
	var under := Vector2(100, 100)
	var ground_before = view._ground_at(under)
	view._zoom_at(under, z0 * 1.2)
	var ground_after = view._ground_at(under)
	check((ground_before - ground_after).length() < 3.0, "editor: zoom stays on the ground under the pointer")
	view._reset_view()
	check(view._zoom == view.DEFAULT_ZOOM, "editor: reset view")
	view._exporting = true
	_click(view, spot, true)
	_click(view, spot, false)
	check(doc.data.things.is_empty(), "editor: no edits while rendering")
	view._exporting = false
	view._select_tool(view.Tool.LOOK)
	view._select_tool(view.Tool.LOOK)
	view._save_now()
	doc.add_thing("stone", 20.0, 20.0, 0.0, 1.0)
	doc.add_thing("stone", 21.0, 20.0, 0.0, 1.0)
	doc.add_thing("stone", -60.0, 90.0, 0.0, 1.0)
	view._scene.refresh_things("light")
	check(view._scene._things.get_child_count() == 2, "editor: things far apart are drawn in separate cells")
	check(view.path != "" and FileAccess.file_exists(view.path.path_join("world.json")), "editor: saves")
	check(WorldDoc.open(view.path) != null, "editor: what it saved opens")
	var saved: String = view.path
	var requested := {"left": false}
	view.request_leave(func(): requested.left = true)
	check(requested.left, "editor: leaving saves and goes")
	view.free()
	WorldDoc.remove_folder(saved)
	return true

func _library() -> bool:
	WorldLibrary.root_override = OS.get_user_data_dir().path_join("test-library")
	var root := WorldLibrary.root()
	var first := WorldDoc.create("guild", "Same name", 1)
	first.add_thing("rock", 1, 1, 0, 1)
	var a := WorldLibrary.folder_for("Same name")
	check(first.save(a) == OK, "library: saves")
	var b := WorldLibrary.folder_for("Same name")
	check(a != b, "library: a second world of the same name gets its own folder")
	var second := WorldDoc.create("guild", "Same name", 2)
	second.save(b)
	check(WorldDoc.open(a).data.things.size() == 1, "library: the first world survives the second")
	check(WorldLibrary.unique_title("Same name") == "Same name 2", "library: suggests a free name")
	check(WorldLibrary.folder_for("CON").ends_with("con-world"), "library: avoids Windows device names")
	check(WorldLibrary.folder_for("   ").ends_with("world"), "library: a blank title still gets a folder")
	check(WorldLibrary.list().size() == 2, "library: lists saved worlds")
	check(WorldLibrary.rename(a, "Renamed") == OK and WorldDoc.open(a).data.title == "Renamed", "library: renames")
	var copy := WorldLibrary.duplicate_world(a)
	check(copy != "" and WorldDoc.open(copy).data.things.size() == 1 and WorldDoc.open(copy).data.title == "Renamed copy", "library: duplicates")
	DirAccess.make_dir_recursive_absolute(root.path_join("not-a-world"))
	check(WorldLibrary.list().size() == 3, "library: ignores other folders")
	DirAccess.remove_absolute(root.path_join("not-a-world"))
	for w in WorldLibrary.list():
		WorldDoc.remove_folder(w.path)
	DirAccess.remove_absolute(root)
	WorldLibrary.root_override = ""
	var main_script: GDScript = load("res://src/ui/main.gd")
	var noon := 1_700_000_000 - 1_700_000_000 % 86400 + 43200
	check(main_script.edited_text(noon, noon + 60, 0) == "Today, 12:00", "library: today")
	check(main_script.edited_text(noon, noon + 86400, 0) == "Yesterday, 12:00", "library: yesterday")
	check(main_script.edited_text(noon, noon + 86400 * 3, 0).begins_with("2023-"), "library: older")
	return true

func _land() -> bool:
	var doc := WorldDoc.create("guild", "T", 1)
	var res := WorldDoc.TERRAIN_RES
	var rng := Templates.Rng.new(9)
	for o in doc.heights.size():
		doc.heights[o] = rng.next() * 5.0
	var scene := WorldScene.new()
	root.add_child(scene)
	scene.build(doc)
	var count := WorldScene.chunk_count()
	check(count * WorldScene.CHUNK_CELLS == res - 1, "land: squares cover the terrain exactly")
	var a: Array = scene.chunk_arrays(1, 2)
	var b: Array = scene.chunk_arrays(2, 2)
	var side := WorldScene.CHUNK_CELLS + 1
	var seam := true
	for row in side:
		var left: int = row * side + WorldScene.CHUNK_CELLS
		var right: int = row * side
		seam = seam and a[Mesh.ARRAY_VERTEX][left] == b[Mesh.ARRAY_VERTEX][right] and a[Mesh.ARRAY_NORMAL][left] == b[Mesh.ARRAY_NORMAL][right] and a[Mesh.ARRAY_TEX_UV][left] == b[Mesh.ARRAY_TEX_UV][right]
	check(seam, "land: neighbouring squares share positions and normals")
	var corner := WorldDoc.cell_to_world(WorldScene.CHUNK_CELLS, 2 * WorldScene.CHUNK_CELLS)
	var v: Vector3 = a[Mesh.ARRAY_VERTEX][0]
	check(is_equal_approx(v.x, corner.x) and is_equal_approx(v.z, corner.y) and v.y == doc.heights[2 * WorldScene.CHUNK_CELLS * res + WorldScene.CHUNK_CELLS], "land: a square sits where the map says")
	scene.flush_land()
	var middle := 2 * WorldScene.CHUNK_CELLS * res + 2 * WorldScene.CHUNK_CELLS
	scene.mark_land([middle + 5 * res + 5])
	check(scene._dirty_chunks.size() == 1, "land: a change inside a square redraws one square")
	scene.flush_land()
	scene.mark_land([middle])
	check(scene._dirty_chunks.size() == 4, "land: a change on a corner redraws the four squares it touches")
	scene.flush_land()
	scene.mark_land([middle + 1])
	check(scene._dirty_chunks.size() == 4, "land: a change beside a seam redraws across it, for its normals")
	scene.flush_land()
	doc.ground[middle] = 2
	scene.mark_land([middle], true)
	check(scene._dirty_chunks.is_empty() and scene._weights_dirty, "land: painting redraws no shapes")
	check(scene._weights_raw[middle * 4 + 2] == 255 and scene._weights_raw[middle * 4] == 0, "land: painting updates the map")
	scene.flush_land()
	var thing := doc.add_thing("stone", 0.0, 0.0, 0.0, 1.0)
	scene.update_things([thing], [])
	check(scene._by_cell.has(WorldScene._key_of(thing)), "land: a new thing is listed")
	scene.update_things([], [thing])
	check(not scene._by_cell.has(WorldScene._key_of(thing)), "land: a removed thing leaves no empty area")
	var other := doc.add_thing("grass", 100.0, 100.0, 0.0, 1.0)
	var keeper := doc.add_thing("grass", 0.0, 0.0, 0.0, 1.0)
	scene.refresh_things("light")
	var far_node = scene._nodes.get(WorldScene._key_of(other))
	var near_key := WorldScene._key_of(keeper)
	scene.update_things([doc.add_thing("grass", 1.0, 1.0, 0.0, 1.0)], [])
	check(scene._nodes.get(WorldScene._key_of(other)) == far_node, "land: placing leaves other areas alone")
	check(scene._by_cell[near_key].things.size() == 2, "land: placing adds to its own area")
	var paved := 0.0
	for child in scene._plaza.get_children():
		if child.mesh is BoxMesh and is_equal_approx(child.position.y, -0.03):
			paved = child.mesh.size.x / 2.0
	for id in Yard.data().halls:
		var hall: Dictionary = Yard.data().halls[id]
		var half: float = Yard.data().hall.docker if id == "docker" else Yard.data().hall.half
		if float(hall.z) >= 0.0:
			check(absf(float(hall.x)) + half <= paved, "land: the " + id + " hall stands on the paving")
	scene.free()
	return true

func _placing() -> bool:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	for mix in Placing.MIXES:
		for kind in Placing.MIXES[mix].kinds:
			check(models.has(kind), "placing: %s names a real item: %s" % [mix, kind])
	check(Placing.kinds_of("fern") == ["fern"], "placing: one thing is one kind")
	check(Placing.kinds_of("mix:rocks") == Placing.MIXES.rocks.kinds, "placing: a mix is its kinds")
	var doc := WorldDoc.create("guild", "T", 1)
	check(Placing.why_not(doc, "fern", 120, -120, 1.0) == "", "placing: open ground is fine")
	check(Placing.why_not(doc, "fern", 0, 0, 1.0) != "", "placing: refuses the plaza")
	doc.add_thing("boulder", 120, -120, 0, 1.0)
	var why := Placing.why_not(doc, "fern", 120, -120, 1.0)
	check(why.contains("boulder"), "placing: a crowded spot names what's in the way, not nothing: " + why)
	var lantern_doc := WorldDoc.create("guild", "T", 1)
	lantern_doc.add_thing("grass", 120, -120, 0, 1.0)
	check(Placing.why_not_one(lantern_doc, "lantern", 121, -120) == "", "placing: one chosen item may stand beside grass")
	check(Placing.why_not(lantern_doc, "lantern", 121, -120, 1.0) != "", "placing: painting keeps its spacing")
	check(Placing.why_not_one(lantern_doc, "grass", 120, -120).contains("long grass"), "placing: the same spot twice is refused")
	check(Placing.why_not_one(lantern_doc, "tree_fir", 0, 0) != "", "placing: one chosen item still keeps off the plaza")
	var fit_doc := Templates.create("meadow", "guild", "T", 7)
	var fit_rng := Templates.Rng.new(5)
	var same_answer := true
	var in_range := true
	fit_doc.data.things = []
	var near_kinds := ["barrel", "shrub_wild", "shrub_round", "boulder", "tree_young", "tree_fir"]
	for attempt in 200:
		var fit_kind: String = near_kinds[attempt % near_kinds.size()]
		var fit_x := fit_rng.range_f(-70.0, 70.0)
		var fit_z := fit_rng.range_f(-70.0, 70.0)
		var answer := Placing.why_not_one(fit_doc, fit_kind, fit_x, fit_z)
		check(Placing.why_not_one(fit_doc, fit_kind, fit_x, fit_z) == answer, "placing: a spot's answer doesn't change on asking again")
		if answer == "":
			var fitted := Placing.fitted_scale(fit_doc, fit_kind, fit_x, fit_z, fit_rng.range_f(Placing.SMALLEST, Placing.LARGEST))
			in_range = in_range and fitted >= Placing.SMALLEST and fitted <= Placing.LARGEST
			var top := fit_doc.height_at(fit_x, fit_z) + float(models[fit_kind].height) * fitted
			in_range = in_range and Clearance.refuse(fit_x, fit_z, top) == ""
	check(in_range, "placing: every fitted size stays in range and keeps the Yard clear")
	var fit_world := Templates.create("meadow", "guild", "T", 7)
	var fit_world_ok := true
	for attempt in 60:
		var fit_kind: String = near_kinds[attempt % near_kinds.size()]
		var fit_x := fit_rng.range_f(-70.0, 70.0)
		var fit_z := fit_rng.range_f(-70.0, 70.0)
		if Placing.why_not_one(fit_world, fit_kind, fit_x, fit_z) == "":
			fit_world.add_thing(fit_kind, fit_x, fit_z, 0.0, Placing.fitted_scale(fit_world, fit_kind, fit_x, fit_z, Placing.LARGEST))
	fit_world_ok = Clearance.check_world(fit_world).get("valid", false)
	check(fit_world_ok, "placing: a world with single placements still passes the export check")
	var wet := WorldDoc.create("guild", "T", 1)
	wet.data.water_level = -0.5
	var wet_i := 40
	var wet_at := WorldDoc.cell_to_world(wet_i, wet_i)
	wet.heights[wet_i * WorldDoc.TERRAIN_RES + wet_i] = -3.0
	check(Placing.why_not_one(wet, "fern", wet_at.x, wet_at.y).contains("under the water"), "placing: refuses a spot under the water")
	check(Placing.why_not(wet, "fern", wet_at.x, wet_at.y, 1.0).contains("under the water"), "placing: painting refuses it too")
	var dry := WorldDoc.create("guild", "T", 1)
	dry.heights[wet_i * WorldDoc.TERRAIN_RES + wet_i] = -102.0
	check(Placing.why_not_one(dry, "fern", wet_at.x, wet_at.y) == "", "placing: deep land is dry when there is no water")
	check(Placing.why_not(dry, "fern", wet_at.x, wet_at.y, 1.0) == "", "placing: painting agrees when there is no water")
	var shade := WorldDoc.create("guild", "T", 1)
	var shade_up := Clearance._ground_up()
	shade.add_thing("tree_fir", 120, -120, 0, 1.0)
	var behind_fir := Vector2(120, -120) + shade_up * 6.0
	var before_fir := Vector2(120, -120) - shade_up * 6.0
	check(Placing.hidden_behind(shade, "fern", behind_fir.x, behind_fir.y, 1.0) == "fir", "placing: knows when a tree would hide an item")
	check(Placing.hidden_behind(shade, "fern", before_fir.x, before_fir.y, 1.0) == "", "placing: an item in front of a tree isn't hidden")
	check(Placing.hidden_behind(shade, "tree_fir", behind_fir.x, behind_fir.y, 1.0) == "", "placing: a tree as tall isn't hidden")
	var res := 65
	var mask := Clearance.mask(16.0, res)
	var agrees := true
	for j in res:
		for i in res:
			var x := (float(i) / (res - 1) - 0.5) * WorldDoc.TERRAIN_SIZE
			var z := (float(j) / (res - 1) - 0.5) * WorldDoc.TERRAIN_SIZE
			agrees = agrees and (mask[(j * res + i) * 2 + 1] == 255) == (Clearance.refuse(x, z, 16.0) != "")
	check(agrees, "placing: the map shows exactly what is refused")
	var flat := Clearance.mask(0.0, res)
	var centre := (res / 2 * res + res / 2) * 2 + 1
	check(flat[centre] == 255 and flat[1] == 0, "placing: the flat map marks only the crews' ground")
	return true

func _loader() -> bool:
	var made := WorldLoader.new()
	root.add_child(made)
	var labels := []
	var result := {}
	made.step.connect(func(label, fraction): labels.append(fraction))
	made.done.connect(func(doc): result.doc = doc)
	made.start(func(): return Templates.create("meadow", "guild", "T", 42))
	while not result.has("doc"):
		await process_frame
	check(result.doc != null and result.doc.data.things.size() > 0, "loader: makes the world off the main thread")
	check(labels.size() > 3 and labels.max() <= 1.0, "loader: reports progress")
	var ordered := true
	for i in range(1, labels.size()):
		ordered = ordered and labels[i] >= labels[i - 1]
	check(ordered, "loader: progress only moves forward")
	check(JSON.stringify(result.doc.data.things) == JSON.stringify(Templates.create("meadow", "guild", "T", 42).data.things), "loader: same world as the main thread would make")
	var bad := {}
	made.done.connect(func(doc): bad.doc = doc, CONNECT_ONE_SHOT)
	made.start(func(): return null)
	while not bad.has("doc"):
		await process_frame
	check(bad.doc == null, "loader: reports a world that can't be opened")
	made.free()
	return true

func _arrange_view(doc: WorldDoc) -> Control:
	var script: GDScript = load("res://src/ui/editor_view.gd")
	var view: Control = script.new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	view.open(doc, "")
	await process_frame
	view._select_tool(view.Tool.ARRANGE)
	return view

func _screen_of(view: Control, t: Dictionary) -> Vector2:
	return view._camera.unproject_position(Vector3(t.x, view.doc.height_at(t.x, t.z), t.z))

func _arrange() -> bool:
	var doc := WorldDoc.create("guild", "T", 3)
	var stone := doc.add_thing("stone", 24.0, 8.0, 0.5, 1.0)
	var fir := doc.add_thing("tree_fir", 40.0, -40.0, 0.0, 1.0)
	var view: Control = await _arrange_view(doc)
	var at := _screen_of(view, stone)
	check(view._thing_at(at).get("id") == stone.id, "arrange: finds the thing under the pointer")
	check(view._thing_at(Vector2(2, 2)).is_empty(), "arrange: empty ground finds nothing")
	_click(view, at, true)
	_click(view, at, false)
	check(view._selected_id == stone.id and view._selected_ring.visible, "arrange: a click chooses it")
	check(doc.data.things.size() == 2 and not view.history.can_undo(), "arrange: choosing changes nothing")
	var to := at + Vector2(60, 30)
	var hit_to: Vector3 = view._ground_at(to)
	_click(view, at, true)
	_drag(view, to)
	_click(view, to, false)
	var moved: Dictionary = view._selected()
	check(Vector2(moved.x, moved.z).distance_to(Vector2(hit_to.x, hit_to.z)) < 0.01 and moved.id == stone.id, "arrange: a drag moves it")
	check(view.history.undo_label().begins_with("Move"), "arrange: a move is one undo step")
	view.history.undo()
	var back: Dictionary = view._selected()
	check(is_equal_approx(back.x, 24.0) and is_equal_approx(back.z, 8.0), "arrange: undo puts it back")
	view.history.redo()
	check(view._selected().x == moved.x, "arrange: redo moves it again")
	var from_here := _screen_of(view, view._selected())
	var plaza: Vector2 = view._camera.unproject_position(Vector3.ZERO)
	var kept: Dictionary = view._selected()
	_click(view, from_here, true)
	_drag(view, plaza)
	check(view._drag.why != "", "arrange: says why while over a refused spot")
	_click(view, plaza, false)
	check(view._selected().x == kept.x and view._selected().z == kept.z, "arrange: a refused move leaves it where it was")
	check(view._status.text != "", "arrange: says why it was refused")
	check(view._scene._by_cell.has(view._scene._key_of(kept)) and view._scene._by_cell[view._scene._key_of(kept)].things.size() == 1, "arrange: a refused move still draws it")
	view._turn_selected(view.TURN_STEP)
	check(is_equal_approx(view._selected().turn, wrapf(kept.turn + view.TURN_STEP, 0.0, TAU)), "arrange: Q and E turn it")
	view.history.undo()
	check(is_equal_approx(view._selected().turn, kept.turn), "arrange: undo turns it back")
	var before_scale: float = view._selected().scale
	view._preview_selected("scale", 1.5)
	view._commit_selected("Resize", "scale", before_scale)
	check(view._selected().scale == 1.5, "arrange: resizes it")
	view.history.undo()
	check(view._selected().scale == before_scale, "arrange: undo restores the size")
	view._select_thing(fir.id)
	check(Placing.largest_scale(doc, "tree_fir", fir.x, fir.z) * 16.0 + doc.height_at(fir.x, fir.z) <= maxf(1.0, Clearance.max_elevation(fir.x, fir.z)), "arrange: the largest size keeps the Yard clear")
	view._remove_selected()
	check(doc.data.things.size() == 1 and view._selected_id == -1, "arrange: remove takes it away and clears the choice")
	view.history.undo()
	check(doc.data.things.size() == 2, "arrange: undo brings it back")
	check(Placing.why_not_moved(doc, view._selected() if not view._selected().is_empty() else fir, fir.x, fir.z) == "", "arrange: a thing never blocks itself")
	view.free()
	return true

func _place_panel() -> bool:
	var doc := WorldDoc.create("guild", "T", 3)
	var script: GDScript = load("res://src/ui/editor_view.gd")
	var view: Control = script.new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	view.open(doc, "")
	await process_frame
	check(view._place_group == "plants", "panel: shows the chosen item's group")
	check(view._item_buttons.has("fern") and not view._item_buttons.has("tree_oak"), "panel: shows one group at a time")
	view._place_search = "tree"
	view._fill_place_items()
	check(view._item_buttons.has("tree_oak") and view._item_buttons.has("stump") and not view._item_buttons.has("fern"), "panel: search looks through every group")
	view._place_search = "no such thing"
	view._fill_place_items()
	check(view._item_buttons.is_empty(), "panel: search can find nothing")
	view._place_search = ""
	var listed: Array = view.PLACE_GROUPS.map(func(entry): return entry[0])
	check(WorldScene.load_kit().models.values().all(func(m): return listed.has(m.group)), "panel: every kit item has a group button")
	view._place_group = "goblins"
	view._fill_place_items()
	check(view._item_buttons.has("goblin_factory") and view._item_buttons.has("hall_goblinville_docker") and not view._item_buttons.has("gnome_mill"), "panel: a theme's buildings and halls share its group")
	view.place_mode = "one"
	view._choose("fort_thick_straight")
	check(view._next_scale == 1.0 and (is_equal_approx(fposmod(view._next_turn, PI / 2.0), 0.0) or is_equal_approx(fposmod(view._next_turn, PI / 2.0), PI / 2.0)), "panel: a castle piece starts at full size and square")
	check(view._turn_step("fort_thick_straight") == PI / 2.0 and view._turn_step("barrel") == view.TURN_STEP, "panel: castle pieces turn a quarter at a time")
	view._build_options()
	var turns: Node = view._options.find_child("Turns", true, false)
	var before: float = view._next_turn
	turns.get_child(1).pressed.emit()
	var after_e: float = view._next_turn
	turns.get_child(0).pressed.emit()
	check(turns.get_child_count() == 2 and is_equal_approx(wrapf(after_e - before, 0.0, TAU), PI / 2.0) and is_equal_approx(view._next_turn, before), "panel: the turn buttons turn the next piece both ways")
	var spot := Placing.on_grid(doc, "fort_thick_straight", Vector3(-60.13, 0.0, -80.38))
	check(spot.x == -60.0 and spot.z == -80.5 and Placing.on_grid(doc, "barrel", Vector3(1.13, 0.0, 2.38)) == Vector3(1.13, 0.0, 2.38), "panel: castle pieces snap to the grid and other things don't")
	check(Placing.fitted_scale(doc, "fort_tower_round", spot.x, spot.z, 0.9) == 1.0, "panel: castle pieces keep their size")
	doc.add_thing("fort_thick_straight", spot.x, spot.z, 0.0, 1.0)
	check(Placing.why_not_one(doc, "fort_walkway_straight", spot.x + 0.2, spot.z) == "" and Placing.why_not_one(doc, "barrel", spot.x + 0.2, spot.z) != "", "panel: castle pieces may meet, other things keep clear")
	view.tool = view.Tool.SCATTER
	view._choose("fort_tower_round")
	view._update_zones()
	check(view._zone_wanted >= float(WorldScene.load_kit().models.fort_tower_round.height), "panel: the red zone for a castle piece uses its full size")
	_joining()
	view.free()
	var opened := WorldDoc.create("guild", "T", 3)
	opened.add_thing("stone", 40.0, 40.0, 0.0, 1.0)
	var used := {}
	for t in opened.data.things:
		used[t.kind] = true
	var made := WorldLoader.new()
	root.add_child(made)
	var result := {}
	made.done.connect(func(d): result.doc = d)
	made.start(func(): return opened)
	while not result.has("doc"):
		await process_frame
	made.free()
	check(result.doc != null and WorldScene.mesh_ready("stone"), "panel: opening a world loads what it uses")
	return true

func _joined_end(doc: WorldDoc, thing: Dictionary, kind: String, spot: Dictionary) -> bool:
	var models: Dictionary = WorldScene.load_kit().models
	for j in models[thing.kind].joints:
		var a: Vector2 = Vector2(thing.x, thing.z) + Placing._turned(Vector2(j[0], j[1]), thing.turn)
		for k in models[kind].joints:
			var b: Vector2 = Vector2(spot.at.x, spot.at.z) + Placing._turned(Vector2(k[0], k[1]), spot.turn)
			var fa := Placing._turned(Vector2(j[2], j[3]), thing.turn)
			var fb := Placing._turned(Vector2(k[2], k[3]), spot.turn)
			if a.distance_to(b) < 0.001 and fa.dot(fb) < -0.999:
				return true
	return false

func _joining() -> void:
	var doc := WorldDoc.create("guild", "Castle", 3)
	var wall := doc.add_thing("fort_thick_straight", -60.0, -80.0, 0.0, 1.0)
	var end := Vector2(-60.0, -80.0) + Placing._turned(Vector2(7.2813, 2.0861), 0.0)
	var next := Placing.placement(doc, "fort_thick_straight", Vector3(end.x + 1.0, 0.0, end.y + 0.5), 1.0)
	check(next.joins == "fort_thick_straight" and absf(next.at.x - (-60.0 + 14.5626)) < 0.002 and is_equal_approx(next.at.z, -80.0) and is_zero_approx(wrapf(next.turn, -PI, PI)), "joining: a wall continues the wall it's dropped beside")
	var turned := doc.add_thing("fort_thin_straight", 60.0, -80.0, PI / 2.0, 1.0)
	var t_end := Vector2(60.0, -80.0) + Placing._turned(Vector2(7.41, 1.275), PI / 2.0)
	var after := Placing.placement(doc, "fort_thin_straight", Vector3(t_end.x, 0.0, t_end.y), 0.0)
	check(_joined_end(doc, turned, "fort_thin_straight", after) and Vector2(after.at.x, after.at.z).distance_to(Vector2(60.0, -80.0)) > 14.0, "joining: a turned wall is continued, not doubled back")
	var corner := Placing.placement(doc, "fort_thick_corner", Vector3(end.x, 0.0, end.y), 0.0)
	check(corner.joins == "fort_thick_straight" and _joined_end(doc, wall, "fort_thick_corner", corner), "joining: a corner meets a wall end exactly")
	var ledge := Vector2(-60.0, -80.0) + Placing._turned(Vector2(-7.281, -2.086), 0.0)
	var walk := Placing.placement(doc, "fort_walkway_straight", Vector3(ledge.x, 0.0, ledge.y), 0.0)
	check(walk.joins == "fort_thick_straight" and _joined_end(doc, wall, "fort_walkway_straight", walk) and is_zero_approx(wrapf(walk.turn, -PI, PI)), "joining: a walkway stands behind a wall")
	var free := Placing.placement(doc, "fort_thick_straight", Vector3(-20.13, 0.0, -90.38), PI / 2.0)
	check(free.joins == "" and free.at.x == -20.0 and free.at.z == -90.5 and free.turn == PI / 2.0, "joining: away from other pieces, pieces sit on the grid")
	var dragged := Placing.placement(doc, "fort_thick_straight", Vector3(end.x, 0.0, end.y), 0.0, int(wall.id))
	check(dragged.joins == "", "joining: a piece being moved doesn't join itself")

func _castle() -> bool:
	var models: Dictionary = WorldScene.load_kit().models
	check(models.values().all(func(m): return not m.get("joins", false) or not m.get("joints", []).is_empty()), "castle: every joining piece has joints")
	var doc := WorldDoc.create("guild", "Castle", 3)
	for kind in ["fort_thin_straight", "fort_thick_straight"]:
		var first := doc.add_thing(kind, -60.0, -120.0 if kind == "fort_thin_straight" else -140.0, 0.0, 1.0)
		var box := WorldScene.mesh_of(kind).get_aabb()
		var end := Vector2(first.x + box.end.x, first.z)
		var second := Placing.placement(doc, kind, Vector3(end.x + 0.5, 0.0, end.y), 0.0)
		check(absf(float(first.x) + box.end.x - (second.at.x + box.position.x)) < 0.001 and is_zero_approx(wrapf(second.turn, -PI, PI)), "castle: joined %s meet within a millimetre as drawn" % kind)
	var view: Control = load("res://src/ui/editor_view.gd").new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	doc = WorldDoc.create("guild", "Castle", 3)
	view.open(doc, "")
	await process_frame
	view._select_tool(view.Tool.SCATTER)
	view.place_mode = "one"
	view._choose("fort_thick_straight")
	view._scatter_at(Vector3(-60.13, 0.0, -80.2), true)
	view._finish_stroke()
	var a: Dictionary = doc.data.things[-1]
	check(a.kind == "fort_thick_straight" and a.x == -60.0 and a.z == -80.0, "castle: the first piece sits on the grid")
	var a_end := Vector2(a.x, a.z) + Placing._turned(Vector2(7.281, 2.086), a.turn)
	view._scatter_at(Vector3(a_end.x + 0.8, 0.0, a_end.y), true)
	view._finish_stroke()
	var b: Dictionary = doc.data.things[-1]
	var b_expected := Vector2(a.x, a.z) + Placing._turned(Vector2(14.5626, 0.0), a.turn)
	check(doc.data.things.size() == 2 and Vector2(b.x, b.z).distance_to(b_expected) < 0.002, "castle: clicking beside its end extends the wall")
	var again := Placing.placement(doc, "fort_thick_straight", Vector3(a_end.x, 0.0, a_end.y), 0.0)
	check(again.joins == "", "castle: a taken end offers no join")
	check(Placing.why_not_one(doc, "fort_thick_straight", b.x, b.z, b.turn) == Placing.DUPLICATE, "castle: an exact duplicate is refused")
	var ledge := Vector2(a.x, a.z) + Placing._turned(Vector2(-7.281, -2.086), a.turn)
	var walk := Placing.placement(doc, "fort_walkway_straight", Vector3(ledge.x, 0.0, ledge.y), 0.0)
	check(walk.joins == "fort_thick_straight" and Placing.why_not_one(doc, "fort_walkway_straight", walk.at.x, walk.at.z, walk.turn) == "", "castle: a walkway may still overlap its wall")
	var free := Placing.placement(doc, "fort_thick_corner_b", Vector3(-20.13, 0.0, -90.38), 0.3)
	check(free.joins == "" and is_equal_approx(free.at.x, -20.13) and is_equal_approx(free.at.z, -90.38) and free.turn == 0.3 and view._turn_step("fort_thick_corner_b") == view.TURN_STEP, "castle: pieces without joins go exactly where they're put")
	view._choose("fort_thick_corner_b")
	view._next_turn = deg_to_rad(15.0)
	view._roll_next()
	var kept_turn: float = view._next_turn
	view._choose("fort_thick_straight")
	check(is_equal_approx(kept_turn, deg_to_rad(15.0)) and is_zero_approx(fposmod(view._next_turn, PI / 2.0)), "castle: a free piece keeps its turn, a joining piece squares up")
	var c := doc.add_thing("fort_thick_straight", -100.0, -120.0, 0.0, 1.0)
	view._scene.update_things([c], [])
	view._select_tool(view.Tool.ARRANGE)
	var a_start := Vector2(a.x, a.z) + Placing._turned(Vector2(-7.281, 2.086), a.turn)
	var grab := _screen_of(view, c)
	var target: Vector2 = view._camera.unproject_position(Vector3(a_start.x, 0.0, a_start.y))
	_click(view, grab, true)
	_click(view, grab, false)
	_click(view, grab, true)
	_drag(view, target)
	_click(view, target, false)
	var dragged: Dictionary = view._selected()
	var c_expected := Vector2(a.x, a.z) + Placing._turned(Vector2(-14.5626, 0.0), a.turn)
	check(dragged.id == c.id and Vector2(dragged.x, dragged.z).distance_to(c_expected) < 0.002, "castle: dragging a piece onto a free end joins it")
	var before := Vector2(dragged.x, dragged.z)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_RIGHT
	view._unhandled_key_input(key)
	var nudged: Dictionary = view._selected()
	check(is_equal_approx(Vector2(nudged.x, nudged.z).distance_to(before), view.NUDGE) and view.history.undo_label().begins_with("Nudge"), "castle: an arrow key nudges the chosen thing")
	view.history.undo()
	check(Vector2(view._selected().x, view._selected().z) == before, "castle: undo takes the nudge back")
	view.free()
	return true

func _sloped(grade: float) -> WorldDoc:
	var doc := WorldDoc.create("guild", "Slope", 3)
	var res := WorldDoc.TERRAIN_RES
	for o in res * res:
		var p := WorldDoc.cell_to_world(o % res, o / res)
		if p.x > -100.0 and p.x < -20.0 and p.y > -140.0 and p.y < -60.0:
			doc.heights[o] = grade * (p.x + 100.0)
	return doc

func _seating() -> bool:
	var doc := _sloped(0.05)
	var view: Control = load("res://src/ui/editor_view.gd").new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	view.open(doc, "")
	await process_frame
	var hut := doc.add_thing("goblin_hut", -60.0, -100.0, 0.0, 1.0)
	var barrel := doc.add_thing("barrel", -50.0, -100.0, 0.0, 1.0)
	var span := Placing.ground_span(doc, "goblin_hut", -60.0, -100.0, 0.0, 1.0)
	var y: float = view._scene.transform_of(hut).origin.y
	check(is_equal_approx(y, span.x) and y < doc.height_at(-60.0, -100.0) - 0.05, "seating: a building sits on the lowest ground under it")
	check(is_equal_approx(view._scene.transform_of(barrel).origin.y, doc.height_at(-50.0, -100.0)), "seating: small things keep standing at their middle")
	check(Placing.why_not_one(doc, "goblin_hut", -70.0, -120.0, 0.0) == "", "seating: a gentle slope is fine")
	view.free()
	var steep := _sloped(0.4)
	check(Placing.why_not_one(steep, "goblin_hut", -60.0, -100.0, 0.0) == Placing.STEEP and Placing.why_not_one(steep, "barrel", -60.0, -100.0, 0.0) == "", "seating: a building is refused on a steep slope, small things aren't")
	var cross := _sloped(0.1)
	check(Placing.why_not_one(cross, "fort_thick_straight", -60.0, -100.0, 0.0) == Placing.STEEP and Placing.why_not_one(cross, "fort_thick_straight", -60.0, -100.0, PI / 2.0) == "", "seating: the slope is judged along the piece as it's turned")
	var wall := cross.add_thing("fort_thick_straight", -60.0, -100.0, PI / 2.0, 1.0)
	check(Placing.why_not_moved(cross, wall, -60.0, -100.0, 0.0) == Placing.STEEP, "seating: turning or moving onto a steep spot is refused too")
	return true

func _alpha_surfaces(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s) as StandardMaterial3D
		if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			count += 1
	return count

func _seasons() -> bool:
	check(not Templates.create("meadow", "guild", "T", 1).data.has("season"), "seasons: a new world says nothing until one is chosen")
	check(WorldDoc.create("guild", "T", 1).season() == "summer", "seasons: worlds start in summer")
	check(WorldScene.season_mesh("tree_oak", "summer") == WorldScene.mesh_of("tree_oak"), "seasons: summer draws the very same model")
	var bare := WorldScene.season_mesh("tree_oak", "winter")
	var plain := WorldScene.mesh_of("tree_oak")
	check(_alpha_surfaces(plain) > 0 and _alpha_surfaces(bare) == 0 and bare.get_surface_count() > 0, "seasons: broadleaf trees are bare in winter")
	check(_alpha_surfaces(WorldScene.season_mesh("tree_fir", "winter")) == _alpha_surfaces(WorldScene.mesh_of("tree_fir")), "seasons: firs stay green")
	check(WorldScene.season_mesh("grass", "winter").get_surface_count() == 0, "seasons: long grass is gone in winter")
	var turned := WorldScene.season_mesh("tree_oak", "autumn")
	var changed := false
	for s in turned.get_surface_count():
		var m := turned.surface_get_material(s) as StandardMaterial3D
		if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			changed = m.albedo_color == WorldScene.AUTUMN_LEAVES.tree_oak
	check(changed, "seasons: leaves turn in autumn")
	for s in plain.get_surface_count():
		var m := plain.surface_get_material(s) as StandardMaterial3D
		check(m == null or m.next_pass == null, "seasons: dressing a model leaves the original alone")
	var folder := OS.get_user_data_dir().path_join("season-test")
	WorldDoc.remove_folder(folder)
	var doc := WorldDoc.create("guild", "T", 1)
	doc.data.season = "winter"
	check(doc.save(folder) == OK and WorldDoc.open(folder).season() == "winter", "seasons: saved and opened again")
	WorldDoc.remove_folder(folder)
	var odd := doc.data.duplicate(true)
	odd.season = "monsoon"
	check(not WorldDoc._valid_data(odd), "seasons: an unknown season is refused")
	var script: GDScript = load("res://src/ui/editor_view.gd")
	var view: Control = script.new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	var live := WorldDoc.create("guild", "T", 1)
	live.add_thing("tree_oak", 60.0, -60.0, 0.0, 1.0)
	view.open(live, "")
	await process_frame
	view._set_season("winter")
	check(live.season() == "winter" and view._scene._drawn_season == "winter", "seasons: one click dresses the world")
	check(view._scene._nodes.values()[0].multimesh.mesh == WorldScene.season_mesh("tree_oak", "winter"), "seasons: things redraw for it")
	check(view.history.undo_label() == "Season", "seasons: one undo step")
	var moved_before: Dictionary = live.data.things[0].duplicate()
	view.history.undo()
	check(live.season() == "summer" and view._scene._drawn_season == "summer", "seasons: undo goes back")
	check(view._scene._nodes.values()[0].multimesh.mesh == WorldScene.mesh_of("tree_oak"), "seasons: and redraws the summer tree")
	check(JSON.stringify(live.data.things[0]) == JSON.stringify(moved_before), "seasons: nothing moved")
	view.free()
	return true

func _sliders(view: Control) -> Array:
	return view._options.get_children().filter(func(c): return c is HSlider)

func _land_is_protected(doc: WorldDoc) -> bool:
	var checked := Clearance.check_world(doc)
	return checked.get("valid", false) or checked.issues.all(func(i): return i.kind != "land")

func _review() -> bool:
	var keep := WorldLibrary.root_override
	WorldLibrary.root_override = OS.get_user_data_dir().path_join("review-test")
	var doc := WorldDoc.create("guild", "T", 3)
	var elm := doc.add_thing("tree_elm", -40.0, -40.0, 0.5, 1.0)
	var fir := doc.add_thing("tree_fir", 60.0, -60.0, 0.5, 1.0)
	var odd := doc.add_thing("stone", 40.0, 40.0, 0.5, 1.0045)
	var view: Control = await _arrange_view(doc)
	view._zoom = 0.3
	view._place_camera()
	var from := _screen_of(view, elm)
	var to: Vector2 = view._camera.unproject_position(Vector3(0.0, 0.0, 48.0))
	_click(view, from, true)
	_drag(view, to)
	_click(view, to, false)
	var moved: Dictionary = view._selected()
	check(Vector2(moved.x, moved.z).distance_to(Vector2(0.0, 48.0)) < 0.5, "review: the elm moved near the Yard")
	var limit := Placing.largest_scale(doc, "tree_elm", moved.x, moved.z)
	check(_sliders(view)[1].max_value <= limit, "review: the size limit follows a move, %f against %f" % [_sliders(view)[1].max_value, limit])
	_sliders(view)[1].value = 2.0
	view._finish_edits()
	check(Clearance.check_world(doc).get("valid", false), "review: resizing after a move keeps the world exportable")
	view._zoom = view.DEFAULT_ZOOM
	view._target = Vector3(fir.x, 1.0, fir.z)
	view._place_camera()
	var base := _screen_of(view, fir)
	var per_pixel: float = view._camera.size / float(view._viewport.size.y)
	var grabbed := base + Vector2(0.0, -14.0 * Yard.axes().up.y / per_pixel)
	check(view._thing_at(grabbed).get("id") == fir.id, "review: a fir can be grabbed high up")
	_click(view, grabbed, true)
	_drag(view, grabbed + Vector2(7, 0))
	_click(view, grabbed + Vector2(7, 0), false)
	var nudged: Dictionary = view._selected()
	var went := Vector2(nudged.x, nudged.z).distance_to(Vector2(fir.x, fir.z))
	check(went > 0.0 and went < 1.0, "review: a small drag moves it a small way, went %f m" % went)
	_click(view, _screen_of(view, nudged), true)
	_drag(view, _screen_of(view, nudged) + Vector2(20, 0))
	while Time.get_ticks_msec() < 2100:
		await process_frame
	view._dirty_at = 0.001
	view._process(0.0)
	check(not view._drag.is_empty() and view._drag.moving, "review: autosave waits for a drag to finish")
	view._dirty_at = -1.0
	_click(view, _screen_of(view, nudged) + Vector2(20, 0), false)
	view._zoom = 0.3
	view._target = Vector3(0, 1, 0)
	view._place_camera()
	view._select_thing(odd.id)
	var exact: Dictionary = view._selected().duplicate()
	var undo_before: int = view.history._undo.get_current_action()
	_sliders(view)[0].value = 90.0
	var turn_start: float = _sliders(view)[0].value
	view._finish_edits()
	view.history.undo()
	check(view._selected().turn == exact.turn, "review: undo restores the exact turn, %f against %f" % [view._selected().turn, exact.turn])
	view._select_thing(odd.id)
	_sliders(view)[1].value = 1.5
	view._finish_edits()
	view.history.undo()
	check(view._selected().scale == exact.scale, "review: undo restores the exact size, %f against %f" % [view._selected().scale, exact.scale])
	view._select_thing(odd.id)
	var start: float = _sliders(view)[0].value
	_sliders(view)[0].value = start + 40.0
	_sliders(view)[0].value = start
	view._finish_edits()
	check(view._selected().turn == exact.turn and view.history._undo.get_current_action() == undo_before, "review: dragging back to the start changes nothing")
	var raised := WorldDoc.create("guild", "T", 3)
	raised.add_thing("stone", 40.0, 40.0, 0.0, 1.0)
	view._select_thing(-1)
	view.free()
	var land_view: Control = await _arrange_view(raised)
	land_view._select_thing(raised.data.things[0].id)
	var size_cap: float = _sliders(land_view)[1].max_value
	var cell := roundi((40.0 + WorldDoc.TERRAIN_SIZE / 2.0) / (WorldDoc.TERRAIN_SIZE / (WorldDoc.TERRAIN_RES - 1)))
	var cells := {}
	for dj in range(-4, 5):
		for di in range(-4, 5):
			var at := (cell + dj) * WorldDoc.TERRAIN_RES + cell + di
			cells[at] = [Clearance.max_elevation(40.0, 40.0) - 0.05, raised.ground[at]]
	land_view.history.land_stroke("Raise", cells)
	check(_sliders(land_view)[1].max_value < size_cap, "review: the size limit follows the land under the chosen thing")
	check(absf(land_view._selected_ring.position.y - (raised.height_at(40.0, 40.0) + 0.1)) < 0.001, "review: the marker follows the land too")
	land_view.free()
	var wet := WorldDoc.create("guild", "T", 3)
	wet.data.water_level = -11.0
	var water_view: Control = await _arrange_view(wet)
	water_view._select_tool(water_view.Tool.WATER)
	check(_sliders(water_view)[0].value == -11.0, "review: the water slider shows the real level, %f" % _sliders(water_view)[0].value)
	_sliders(water_view)[0].value = -7.9
	water_view._finish_edits()
	water_view.history.undo()
	check(float(wet.data.water_level) == -11.0, "review: undo restores the real water level, %f" % wet.data.water_level)
	wet.data.water_level = -33.33
	water_view._build_options()
	_sliders(water_view)[0].value = -2.0
	water_view._finish_edits()
	water_view.history.undo()
	check(float(wet.data.water_level) == -33.33, "review: any water level survives a slider and undo")
	water_view.free()
	WorldLibrary.root_override = keep
	var sun_doc := WorldDoc.create("guild", "T", 3)
	sun_doc.data.mood.light.sun_energy = 3.37
	var sun_view: Control = await _arrange_view(sun_doc)
	sun_view._select_tool(sun_view.Tool.MOOD)
	_sliders(sun_view)[0].value = 4.0
	sun_view._finish_edits()
	sun_view.history.undo()
	check(float(sun_doc.data.mood.light.sun_energy) == 3.37, "review: every slider's undo is exact")
	sun_view.free()
	check(Clearance.check_world(Templates.create("canyon", "guild", "T", 1941)).get("valid", false), "review: canyon seed 1941 can export")
	for key in ["canyon", "island"]:
		for seed_value in [1, 2, 3, 1941, 99999]:
			check(_land_is_protected(Templates.create(key, "guild", "T", seed_value)), "review: %s seed %d keeps the Yard's ground" % [key, seed_value])
	return true

func _review_slider_edits() -> bool:
	var doc := WorldDoc.create("guild", "T", 3)
	var stone := doc.add_thing("stone", 40.0, 40.0, 0.5, 1.0)
	var view: Control = await _arrange_view(doc)
	view._zoom = 0.3
	view._place_camera()
	view._select_thing(stone.id)
	_sliders(view)[0].value = _sliders(view)[0].value + 15.0
	var turned: float = view._selected().turn
	_sliders(view)[1].value = 1.01
	view._finish_edits()
	check(view.history.undo_label().begins_with("Resize"), "slider edits: the last slider is the last undo step")
	view.history.undo()
	check(view._selected().scale == 1.0 and view._selected().turn == turned, "slider edits: the first undo restores only the size")
	view.history.undo()
	check(view._selected().scale == 1.0 and view._selected().turn == 0.5, "slider edits: the second restores only the turn")
	view.history.redo()
	view.history.redo()
	check(view._selected().scale == 1.01 and view._selected().turn == turned, "slider edits: redo brings both back")
	view.history.undo()
	view.history.undo()
	view._select_thing(stone.id)
	var start: float = _sliders(view)[0].value
	_sliders(view)[0].value = start + 40.0
	_sliders(view)[0].value = start
	view._finish_edits()
	check(view._selected().turn == 0.5, "slider edits: moving away and back restores the exact turn")
	view._turn_selected(view.TURN_STEP)
	var after_key: float = view._selected().turn
	_sliders(view)[0].value = _sliders(view)[0].value + 20.0
	view._finish_edits()
	view.history.undo()
	check(view._selected().turn == after_key, "slider edits: undo returns to the keyed turn, %f against %f" % [view._selected().turn, after_key])
	view.history.undo()
	check(view._selected().turn == 0.5, "slider edits: and then to the one before it")
	_sliders(view)[0].value = 90.0
	view._finish_edits()
	var ninety: float = view._selected().turn
	_sliders(view)[0].value = 120.0
	view._finish_edits()
	view.history.undo()
	check(view._selected().turn == ninety, "slider edits: a second edit on one slider undoes to the first")
	view.free()
	var mood_doc := WorldDoc.create("guild", "T", 3)
	mood_doc.data.mood.light.sun_energy = 3.37
	mood_doc.data.mood.light.strength = 0.93
	var mood_view: Control = await _arrange_view(mood_doc)
	mood_view._select_tool(mood_view.Tool.MOOD)
	_sliders(mood_view)[0].value = 4.0
	_sliders(mood_view)[1].value = 1.2
	mood_view._finish_edits()
	mood_view.history.undo()
	mood_view.history.undo()
	check(float(mood_doc.data.mood.light.sun_energy) == 3.37 and float(mood_doc.data.mood.light.strength) == 0.93, "slider edits: other panels follow the same rule")
	mood_view.free()
	return true

func _review_hidden() -> bool:
	var doc := WorldDoc.create("guild", "T", 3)
	var stone := doc.add_thing("stone", 40.0, 40.0, 0.0, 1.0)
	var up := Clearance._ground_up()
	var ahead := Vector2(40.0, 40.0) - up * 0.6
	var fern := doc.add_thing("fern", ahead.x, ahead.y, 0.0, 1.0)
	var view: Control = await _arrange_view(doc)
	view._target = Vector3(40.0, 1.0, 40.0)
	view._place_camera()
	var near_fern: Vector2 = _screen_of(view, stone).lerp(_screen_of(view, fern), 0.75)
	check(view._thing_at(near_fern).get("id") == fern.id, "hidden: a visible fern can be chosen in summer")
	view._select_thing(fern.id)
	view.history.set_value("Season", doc.data, "season", "winter", "summer")
	check(view._selected_id == -1 and not view._selected_ring.visible, "hidden: a chosen fern is let go when winter hides it")
	check(view._thing_at(near_fern).get("id") == stone.id, "hidden: clicking in winter chooses the visible stone")
	check(view._thing_at(_screen_of(view, fern)).get("id", -1) != fern.id, "hidden: a hidden plant can't be chosen")
	check(Placing.why_not_moved(doc, stone, fern.x, fern.z) == "", "hidden: a hidden plant doesn't block a move")
	check(Placing.why_not_one(doc, "stone", fern.x, fern.z) == "", "hidden: or a placement")
	check(Placing.why_not(doc, "stone", fern.x, fern.z, 1.0).contains("stone"), "hidden: visible things still crowd")
	var far := doc.add_thing("grass", 70.0, 70.0, 0.0, 1.0)
	check(Placing.crowded_by(doc, 70.0, 70.0, 3.0) == "", "hidden: or crowd painting")
	view._select_tool(view.Tool.ERASE)
	view.brush_radius = 4.0
	view._erase_at(Vector3(70.0, 0.0, 70.0))
	view._finish_edits()
	check(doc.data.things.any(func(t): return t.id == far.id), "hidden: clearing leaves what can't be seen")
	view._erase_at(Vector3(40.0, 0.0, 40.0))
	view._finish_edits()
	check(not doc.data.things.any(func(t): return t.id == stone.id) and doc.data.things.any(func(t): return t.id == fern.id), "hidden: clearing still takes what can")
	view.history.set_value("Season", doc.data, "season", "summer", "winter")
	check(Placing.why_not_one(doc, "fern", fern.x, fern.z) != "", "hidden: back in summer the plant counts again")
	view.free()
	return true

func _glb(json: Dictionary, bin: PackedByteArray) -> PackedByteArray:
	return _glb_raw(JSON.stringify(json).to_utf8_buffer(), bin)

func _glb_raw(text: PackedByteArray, bin: PackedByteArray) -> PackedByteArray:
	var json_chunk := text.duplicate()
	while json_chunk.size() % 4 != 0:
		json_chunk.append(0x20)
	var bin_chunk := bin.duplicate()
	while bin_chunk.size() % 4 != 0:
		bin_chunk.append(0)
	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, CustomItems.GLB_MAGIC)
	out.encode_u32(4, 2)
	for chunk in [[json_chunk, CustomItems.CHUNK_JSON], [bin_chunk, CustomItems.CHUNK_BIN]]:
		var head := PackedByteArray()
		head.resize(8)
		head.encode_u32(0, chunk[0].size())
		head.encode_u32(4, chunk[1])
		out.append_array(head)
		out.append_array(chunk[0])
	out.encode_u32(8, out.size())
	return out

func _scene_glb(mesh: Mesh) -> PackedByteArray:
	var holder := Node3D.new()
	var part := MeshInstance3D.new()
	part.mesh = mesh
	holder.add_child(part)
	part.owner = holder
	var g := GLTFDocument.new()
	var state := GLTFState.new()
	g.append_from_scene(holder, state)
	holder.free()
	return g.generate_buffer(state)

func _plane(cuts: int) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	plane.subdivide_width = cuts
	plane.subdivide_depth = cuts
	return plane

func _refuses_glb(bytes: PackedByteArray, wanted: Array, what: String) -> void:
	var error: String = CustomItems.check_glb(bytes).error
	check(error != "" and wanted.all(func(w): return error.contains(w)), "custom: refuses %s: %s" % [what, error])

func _file(dir: String, name: String, bytes: PackedByteArray) -> String:
	var at := dir.path_join(name)
	_store(at, bytes)
	return at

func _box_of(mesh: Mesh, surface: int) -> AABB:
	var points := mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var box := AABB(points[0], Vector3.ZERO)
	for v in points:
		box = box.expand(v)
	return box

func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

func _custom() -> bool:
	var keep_custom := CustomItems.root_override
	var keep_worlds := WorldLibrary.root_override
	CustomItems.root_override = OS.get_user_data_dir().path_join("custom-test")
	WorldLibrary.root_override = OS.get_user_data_dir().path_join("custom-worlds-test")
	var files := OS.get_user_data_dir().path_join("custom-files-test")
	for dir in [CustomItems.root_override, WorldLibrary.root_override, files]:
		_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(files)
	WorldScene.refresh_custom()
	var models: Dictionary = WorldScene.load_kit().models
	var barrel := FileAccess.get_file_as_bytes(WorldScene.kit_file("models/barrel.glb"))
	var good := _file(files, "barrel.glb", barrel)
	var checked := CustomItems.check_model_file(good)
	check(checked.error == "" and checked.warning == "" and checked.triangles == int(models.barrel.triangles), "custom: a kit model passes with its triangles counted: %s %d" % [checked.error, checked.triangles])
	var parts := CustomItems.glb_parts(barrel)
	var magic := barrel.duplicate()
	magic[0] = 0
	_refuses_glb(magic, ["Not a .glb file"], "a file that isn't a .glb")
	var longer := barrel.duplicate()
	longer.append_array(PackedByteArray([0, 0, 0, 0]))
	_refuses_glb(longer, ["header says", "4 extra bytes"], "a length that doesn't match")
	_refuses_glb(barrel.slice(0, barrel.size() - 10), ["10 bytes missing"], "a cut-short file")
	var external: Dictionary = parts.json.duplicate(true)
	external.buffers[0].uri = "barrel.bin"
	_refuses_glb(_glb(external, parts.bin), ["external buffer file (barrel.bin)"], "an external buffer")
	var linked: Dictionary = parts.json.duplicate(true)
	linked.images[0].erase("bufferView")
	linked.images[0].uri = "textures/wood.png"
	_refuses_glb(_glb(linked, parts.bin), ["external image file (wood.png)"], "an external image")
	var squeezed: Dictionary = parts.json.duplicate(true)
	squeezed.extensionsUsed = ["KHR_draco_mesh_compression"]
	squeezed.extensionsRequired = ["KHR_draco_mesh_compression"]
	_refuses_glb(_glb(squeezed, parts.bin), ["Draco", "KHR_draco_mesh_compression"], "Draco compression")
	var meshopt: Dictionary = parts.json.duplicate(true)
	meshopt.extensionsUsed = ["EXT_meshopt_compression"]
	_refuses_glb(_glb(meshopt, parts.bin), ["meshopt"], "meshopt compression")
	var overrun: Dictionary = parts.json.duplicate(true)
	overrun.accessors[0].count = 100000000
	_refuses_glb(_glb(overrun, parts.bin), ["accessor 0", "past the end"], "an accessor past its data")
	var looped: Dictionary = parts.json.duplicate(true)
	looped.nodes[0].children = [0]
	_refuses_glb(_glb(looped, parts.bin), ["more than once"], "a node that contains itself")
	_refuses_glb(_glb_raw("{\"asset\": {\"version\": \"2.0\"}, \"meshes\": [".to_utf8_buffer(), parts.bin), ["JSON can't be read"], "malformed JSON")
	_refuses_glb(PackedByteArray([1, 2, 3]), ["too short"], "a tiny file")
	_refuses_glb(_scene_glb(_plane(300)), ["181,202", "31,202 over the 150,000 limit"], "too many triangles")
	var middling := CustomItems.check_glb(_scene_glb(_plane(200)))
	check(middling.error == "" and middling.warning.contains("80,802") and middling.warning.contains("20,802 over the 60,000"), "custom: warns above 60,000 triangles: " + middling.warning)
	var huge := PackedByteArray()
	huge.resize(55050240)
	var too_big := CustomItems.check_model_file(_file(files, "huge.glb", huge))
	check(too_big.error == "Too large: 52.5 MB, 2.5 MB over the 50 MB limit.", "custom: refuses a model over 50 MB: " + too_big.error)
	DirAccess.remove_absolute(files.path_join("huge.glb"))
	check(CustomItems.check_model_file(_file(files, "barrel.obj", barrel)).error.contains(".glb"), "custom: asks for a .glb file")
	var wide_picture := Image.create(3000, 1000, false, Image.FORMAT_RGBA8)
	wide_picture.fill(Color(0.8, 0.2, 0.2))
	var painted := StandardMaterial3D.new()
	painted.albedo_texture = ImageTexture.create_from_image(wide_picture)
	var box := BoxMesh.new()
	box.material = painted
	var textured := _scene_glb(box)
	check(CustomItems.check_glb(textured).error == "", "custom: a model with a large texture passes")
	var read := WorldScene.glb_mesh(textured, true)
	var texture: Texture2D = (read.surface_get_material(0) as BaseMaterial3D).albedo_texture if read.get_surface_count() > 0 else null
	check(texture != null and texture.get_size() == Vector2(2048, 683), "custom: textures over 2,048 px are scaled down to 2,048: %s" % [texture.get_size() if texture else "none"])
	var picture := Image.create(400, 200, false, Image.FORMAT_RGB8)
	picture.fill(Color(0.1, 0.4, 0.8))
	var sign_file := _file(files, "logo.png", picture.save_png_to_buffer())
	var scaled := CustomItems.check_image(Image.create(3000, 1500, false, Image.FORMAT_RGB8).save_png_to_buffer())
	check(scaled.error == "" and scaled.image.get_size() == Vector2i(2048, 1024), "custom: a picture is scaled down to 2,048 px")
	var oversized := CustomItems.check_image(Image.create(9000, 3000, false, Image.FORMAT_L8).save_png_to_buffer())
	check(oversized.error == "The picture is 9,000 × 3,000 px, 808 px over the 8,192 px limit.", "custom: refuses a picture over 8,192 px: " + oversized.error)
	var stretched := CustomItems.check_image(Image.create(900, 200, false, Image.FORMAT_RGB8).save_png_to_buffer())
	check(stretched.error == "Too wide: 4.5 to 1, over the 4 to 1 limit by 0.5.", "custom: refuses a very wide picture: " + stretched.error)
	check(CustomItems.check_image("<svg/>".to_utf8_buffer()).error.contains("Not a PNG, JPG or WebP"), "custom: refuses something that isn't a picture")
	var heavy_picture := PackedByteArray()
	heavy_picture.resize(22020096)
	check(CustomItems.check_image_file(_file(files, "heavy.png", heavy_picture)).error == "Too large: 21.0 MB, 1.0 MB over the 20 MB limit.", "custom: refuses a picture over 20 MB")
	DirAccess.remove_absolute(files.path_join("heavy.png"))
	check(CustomItems.check_image(picture.save_jpg_to_buffer()).size == Vector2i(400, 200) and CustomItems.check_image(picture.save_webp_to_buffer()).size == Vector2i(400, 200), "custom: JPG and WebP sizes are read")
	var sign_layout := CustomItems.display_layout("sign", 2.0, 2.0)
	check(is_equal_approx(sign_layout.picture.x / sign_layout.picture.y, 2.0), "custom: a sign takes the picture's shape")
	var banner_mesh := CustomItems.display_mesh(picture, "banner", 3.0)
	var cloth := _box_of(banner_mesh, banner_mesh.get_surface_count() - 1)
	check(is_equal_approx(banner_mesh.get_aabb().end.y, 3.0) and is_equal_approx(cloth.size.x / cloth.size.y, 2.0), "custom: a banner is its height and its cloth the picture's shape")
	check(CustomItems.name_problem("Giant gold bauble") == "" and CustomItems.name_problem("A very long name for my company HQ").begins_with("Name too long for its button: shorten it by") and CustomItems.name_problem("  ") == "Give it a name.", "custom: names must fit their button")
	var settings := {"type": "model", "label": "My barrel", "height": 6.0, "rights": true, "upright": "", "seated": true}
	check(CustomItems.add(good, {"type": "model", "label": "My barrel", "height": 6.0, "rights": false}).error.contains("rights"), "custom: asks for the rights")
	check(CustomItems.add(good, {"type": "model", "label": "A very long name for my company HQ", "height": 6.0, "rights": true}).error.begins_with("Name too long"), "custom: refuses a name that won't fit")
	var added := CustomItems.add(good, settings)
	var kind: String = added.get("kind", "")
	check(added.error == "" and CustomItems.is_custom(kind), "custom: a model is stored: " + added.error)
	check(CustomItems.add(good, settings).error == "This file is already in Custom as “My barrel”.", "custom: the same file isn't stored twice")
	var stored := CustomItems.folder(CustomItems.id_of(kind))
	check(FileAccess.file_exists(stored.path_join("model.glb")) and FileAccess.file_exists(stored.path_join(CustomItems.ITEM_FILE)) and FileAccess.file_exists(stored.path_join(CustomItems.THUMB)), "custom: source, item.json and thumb.webp are kept")
	WorldScene.refresh_custom()
	models = WorldScene.load_kit().models
	check(models.has(kind) and models[kind].group == CustomItems.GROUP and models[kind].label == "My barrel" and models[kind].get("seated", false), "custom: uploads join the kit's models")
	check(models.has("barrel") and models.size() > 100, "custom: the kit's own models stay")
	check(is_equal_approx(WorldScene.mesh_of(kind).get_aabb().end.y, 6.0), "custom: the model is drawn at its height")
	check(ProTheme.thumb(kind) != null, "custom: it has a picture")
	check(not Placing.modular(kind) and not Placing.joins(kind) and Placing.sizes(kind) == Vector2.ONE, "custom: uploads never join, aren't modular and place at their own height")
	var slope := _sloped(0.05)
	check(Placing.why_not_one(slope, kind, -60.0, -100.0, 0.0) == "" and Placing.why_not_one(slope, kind, 0.0, 0.0, 0.0) != "", "custom: placed like any item, kept off the crews' ground")
	var placed := slope.add_thing(kind, -60.0, -100.0, 0.0, 1.0)
	check(is_equal_approx(Placing.base_height(slope, placed), Placing.ground_span(slope, kind, -60.0, -100.0, 0.0, 1.0).x), "custom: stands on the lowest ground under its flat base")
	check(Placing.why_not_one(_sloped(0.4), kind, -60.0, -100.0, 0.0) == Placing.STEEP, "custom: refused on a steep slope")
	check(Placing.why_not_one(slope, "fern", -60.0, -100.0).contains("my barrel"), "custom: other things keep clear of it by name")
	var signed := CustomItems.add(sign_file, {"type": "image", "label": "Logo sign", "height": 2.0, "rights": true, "display": "sign"})
	var sign_kind: String = signed.get("kind", "")
	WorldScene.refresh_custom()
	var sign_mesh := WorldScene.mesh_of(sign_kind)
	var face := _box_of(sign_mesh, sign_mesh.get_surface_count() - 1) if sign_mesh.get_surface_count() > 0 else AABB()
	check(signed.error == "" and is_equal_approx(sign_mesh.get_aabb().end.y, 2.0) and is_equal_approx(face.size.x / face.size.y, 2.0), "custom: a picture on a sign is its height, in the picture's shape")
	check(not WorldScene.load_kit().models[sign_kind].get("seated", false), "custom: a sign stands at its middle")
	check(CustomItems.add(sign_file, {"type": "image", "label": "Logo banner", "height": 3.0, "rights": true, "display": "banner"}).error == "", "custom: the same picture can also be a banner")
	check(CustomItems.rename(kind, "Big barrel") == "" and CustomItems.rename(kind, "A very long name for my company HQ").begins_with("Name too long"), "custom: renames, and refuses a name that won't fit")
	WorldScene.refresh_custom()
	check(WorldScene.load_kit().models[kind].label == "Big barrel", "custom: the new name shows")
	await _custom_size(kind, 6.0)
	var view: Control = load("res://src/ui/editor_view.gd").new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	var world := WorldDoc.create("guild", "Custom world", 3)
	var here := world.add_thing(kind, 60.0, -60.0, 0.0, 1.0)
	DirAccess.make_dir_recursive_absolute(WorldLibrary.root_override)
	var world_path := WorldLibrary.folder_for("Custom world")
	check(world.save(world_path) == OK, "custom: a world using an upload saves")
	view.open(world, world_path)
	await process_frame
	view.place_mode = "one"
	view._choose(kind)
	view._build_options()
	check(view._place_group == CustomItems.GROUP and view._item_buttons.has(kind) and view._options.find_child("CustomUploads", true, false) != null, "custom: the Custom group lists uploads")
	var actions: Node = view._options.find_child("CustomActions", true, false)
	check(actions != null and not actions.get_child(0).disabled, "custom: rename and delete are offered for an upload")
	view._place_search = "big bar"
	view._fill_place_items()
	check(view._item_buttons.has(kind) and view._item_buttons.size() == 1, "custom: search finds uploads")
	view._place_search = ""
	check(view._scene._nodes.has(view._scene._key_of(here)), "custom: a placed upload is drawn")
	check(view.custom_users(kind) == ["Custom world (open now)"], "custom: delete warns which worlds use it: %s" % [view.custom_users(kind)])
	check(CustomItems.worlds_using(kind) == ["Custom world"], "custom: finds saved worlds that use it")
	view.rename_custom(kind, "HQ")
	check(view._thing_name(kind) == "HQ", "custom: renaming from the panel shows at once")
	view.delete_custom(kind)
	check(not DirAccess.dir_exists_absolute(stored) and not WorldScene.load_kit().models.has(kind) and view.place_kind == "fern", "custom: delete removes the upload")
	check(not view._scene._nodes.has(view._scene._key_of(here)) and world.data.things.size() == 1, "custom: its copies stay in the world, not drawn")
	check(view._missing_button.visible and not Clearance.check_world(world).valid, "custom: missing items block export and offer removal")
	view.free()
	var loader := WorldLoader.new()
	root.add_child(loader)
	var result := {}
	loader.done.connect(func(d): result.doc = d)
	loader.start(func(): return null, world_path)
	while not result.has("doc"):
		await process_frame
	loader.free()
	var reopened: WorldDoc = result.doc
	check(reopened != null and reopened.data.things.size() == 1 and reopened.notice.contains(Clearance.MISSING_UPLOAD), "custom: a world with a missing upload still opens and says why: %s" % [reopened.notice if reopened else "not opened"])
	check(WorldScene.gone_in(kind, "summer") and Placing.why_not_one(reopened, "fern", 60.0, -60.0) == "", "custom: nothing is blocked by a missing item")
	view = load("res://src/ui/editor_view.gd").new()
	root.add_child(view)
	view.size = Vector2(1200, 800)
	view.open(reopened, world_path)
	await process_frame
	view.remove_missing()
	await process_frame
	check(reopened.data.things.is_empty() and Clearance.check_world(reopened).valid and not view._missing_button.visible, "custom: one click removes missing items")
	view.history.undo()
	check(reopened.data.things.size() == 1 and not Clearance.check_world(reopened).valid, "custom: undo brings them back")
	var again := CustomItems.add(good, settings)
	view._uploads_changed()
	check(again.get("kind", "") == kind and Clearance.check_world(reopened).valid and view._scene._nodes.has(view._scene._key_of(reopened.data.things[0])), "custom: uploading the same file again brings them back")
	view.free()
	var plates := files.path_join("plates")
	DirAccess.make_dir_recursive_absolute(plates)
	var tiny := Image.create(16, 16, false, Image.FORMAT_RGB8).save_webp_to_buffer(true, 0.5)
	for name in WorldPackage.plate_names():
		_store(plates.path_join(name.get_file()), tiny)
	var skies := {}
	for theme in Yard.THEMES:
		skies[theme] = BakeSky.from_file(WorldScene.kit_file("skies/%s.hdr" % reopened.data.mood[theme].sky), 1.0)
	var out := files.path_join("custom.agworld")
	check(WorldPackage.write(reopened, plates, skies, null, out) == OK and WorldPackage.accepted(WorldPackage.check(out)), "custom: a world with uploads exports")
	var unpacked := WorldPackage.read_tar(FileAccess.get_file_as_bytes(out).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP))
	var allowed := WorldPackage.allowed_names() + [WorldPackage.MANIFEST]
	var clean: bool = unpacked.problem == "" and not unpacked.entries.is_empty() and unpacked.entries.all(func(e): return allowed.has(e[0]) and e[1] != barrel and e[1] != picture.save_png_to_buffer())
	check(clean and not unpacked.entries[0][1].get_string_from_utf8().contains(CustomItems.PREFIX), "custom: the export holds no custom files")
	var dialog := CustomDialog.new()
	root.add_child(dialog)
	dialog.use_file(_file(files, "broken.glb", magic))
	check(dialog._message.text.begins_with("Not a .glb file") and dialog.get_ok_button().disabled, "dialog: a refused file says why and can't be added")
	dialog.use_file(good)
	var textures := int(CustomItems.check_glb(barrel).textures)
	check(dialog._message.text.begins_with("Checked: %s triangles, %d %s, largest " % [CustomItems.number(int(models.barrel.triangles)), textures, "texture" if textures == 1 else "textures"]) and textures > 0, "dialog: says what the checks found: " + dialog._message.text)
	check(CustomItems.summary(CustomItems.check_glb(textured)) == "Checked: 12 triangles, 1 texture, largest 3,000 px, scaled to 2,048 px.", "dialog: says when a texture will be scaled down: " + CustomItems.summary(CustomItems.check_glb(textured)))
	dialog._name.text = ""
	dialog.use_file(_file(files, "office_tower.glb", _scene_glb(_plane(200))))
	check(dialog._message.text.contains("Heavy model") and dialog._name.text == "Office tower" and dialog.why_not().contains("rights"), "dialog: warns, names it from the file, and asks for the rights: %s / %s" % [dialog._message.text, dialog._name.text])
	dialog._rights.button_pressed = true
	dialog._refresh_ok()
	check(not dialog.get_ok_button().disabled and dialog._shown != null, "dialog: ready to add, with a preview")
	var made := {}
	dialog.added.connect(func(k): made.kind = k)
	dialog._add()
	check(CustomItems.is_custom(made.get("kind", "")), "dialog: adds the upload")
	dialog = CustomDialog.new()
	root.add_child(dialog)
	dialog.set_type("image")
	dialog.use_file(_file(files, "flag.png", picture.save_png_to_buffer()))
	check(dialog._message.text == "Checked: 400 × 200 px." and dialog._shown != null and is_equal_approx(dialog._height.value, CustomItems.DISPLAY_HEIGHT.sign), "dialog: a picture previews on its sign: " + dialog._message.text)
	dialog.free()
	await _custom_hardening(files)
	for dir in [CustomItems.root_override, WorldLibrary.root_override, files]:
		_remove_tree(dir)
	CustomItems.root_override = keep_custom
	WorldLibrary.root_override = keep_worlds
	WorldScene.refresh_custom()
	return true

func _custom_size(kind: String, height: float) -> void:
	var doc := WorldDoc.create("guild", "Sizes", 3)
	var view: Control = load("res://src/ui/editor_view.gd").new()
	root.add_child(view)
	view.size = Vector2(1200, 800)
	view.open(doc, "")
	await process_frame
	var top := func(t: Dictionary) -> float: return view._scene.transform_of(t).basis.get_scale().y * WorldScene.mesh_of(kind).get_aabb().end.y
	view.place_mode = "one"
	view._choose(kind)
	check(view._next_scale == 1.0, "custom size: the next copy is set to its own height")
	view._scatter_at(Vector3(100.0, 0.0, -100.0), true)
	view._finish_stroke()
	var one: Dictionary = doc.data.things[-1]
	check(one.kind == kind and one.scale == 1.0 and is_equal_approx(top.call(one), height), "custom size: a placed copy is exactly the height entered: %.3f" % top.call(one))
	view.place_mode = "paint"
	view._choose(kind)
	view.brush_radius = 4.0
	for at in [Vector3(-120.0, 0.0, -120.0), Vector3(120.0, 0.0, -150.0), Vector3(-150.0, 0.0, -60.0)]:
		view._scatter_at(at, true)
	view._finish_stroke()
	var painted: Array = doc.data.things.filter(func(t): return t.kind == kind and t.id != one.id)
	check(not painted.is_empty() and painted.all(func(t): return t.scale == 1.0), "custom size: painted copies are their own height too")
	var agrees := true
	for x in range(-60, 61, 10):
		var z := 50.0
		var limit := Clearance.refuse(float(x), z, doc.height_at(x, z) + height) != ""
		agrees = agrees and (Placing.why_not_one(doc, kind, float(x), z) != "") == limit
		agrees = agrees and Placing.fitted_scale(doc, kind, float(x), z, Placing.LARGEST) == 1.0
	check(agrees, "custom size: the limits near the Yard judge it at its own height, never shrunk to fit")
	view._select_tool(view.Tool.ARRANGE)
	view._select_thing(int(one.id))
	view._preview_selected("scale", 1.5)
	view._commit_selected("Resize", "scale", 1.0)
	var resized: Dictionary = view._selected()
	check(resized.scale == 1.5 and is_equal_approx(top.call(resized), height * 1.5), "custom size: a copy can still be resized on purpose")
	var folder := OS.get_user_data_dir().path_join("custom-size-test")
	WorldDoc.remove_folder(folder)
	doc.save(folder)
	var back := WorldDoc.open(folder)
	check(back != null and back.data.things.filter(func(t): return t.id == one.id)[0].scale == 1.5, "custom size: a resized copy keeps its size when the world opens again")
	WorldDoc.remove_folder(folder)
	view._select_tool(view.Tool.SCATTER)
	view.place_mode = "one"
	view._choose(kind)
	check(view._next_scale == 1.0, "custom size: resizing one copy doesn't change the next")
	view.free()

func _indexed_glb(position: Dictionary, extra_views := []) -> PackedByteArray:
	var idx := PackedByteArray()
	idx.resize(72)
	for i in 36:
		idx.encode_u16(i * 2, i % 8)
	var bin := idx.duplicate()
	var views := [{"buffer": 0, "byteLength": 72}]
	for v in extra_views:
		views.append({"buffer": 0, "byteOffset": bin.size(), "byteLength": v.size()})
		bin.append_array(v)
	var json := {"asset": {"version": "2.0"}, "buffers": [{"byteLength": bin.size()}], "bufferViews": views,
		"accessors": [{"bufferView": 0, "componentType": 5123, "count": 36, "type": "SCALAR"}, position],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 1}, "indices": 0}]}],
		"nodes": [{"mesh": 0}], "scenes": [{"nodes": [0]}], "scene": 0}
	return _glb(json, bin)

func _custom_hardening(files: String) -> void:
	var bomb := _indexed_glb({"componentType": 5126, "count": 6000000, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 1]})
	_refuses_glb(bomb, ["18,000,036", "2,000,036 over the 16,000,000 limit"], "a tiny file that unpacks to far too much")
	var sparse_index := PackedByteArray()
	sparse_index.resize(4)
	var sparse_value := PackedByteArray()
	sparse_value.resize(12)
	var sparse_bomb := _indexed_glb({"componentType": 5126, "count": 6000000, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 1],
		"sparse": {"count": 1, "indices": {"bufferView": 1, "componentType": 5125}, "values": {"bufferView": 2}}}, [sparse_index, sparse_value])
	_refuses_glb(sparse_bomb, ["16,000,000 limit"], "a sparse accessor that unpacks to far too much")
	var huge_count := _indexed_glb({"componentType": 5126, "count": 4503599627370496, "type": "MAT4"})
	_refuses_glb(huge_count, ["16,000,000 limit"], "a count big enough to overflow")
	var many := {"asset": {"version": "2.0"}, "accessors": [], "meshes": [], "nodes": [], "scenes": []}
	for i in 600:
		many.accessors.append({"componentType": 5126, "count": 4503599627370496, "type": "MAT4"})
	_refuses_glb(_glb(many, PackedByteArray()), ["16,000,000 limit"], "many huge counts that would overflow a sum")
	_refuses_glb(_indexed_glb({"componentType": 5126, "count": -5, "type": "VEC3"}), ["impossible count"], "a negative count")
	_refuses_glb(_indexed_glb({"componentType": 5126, "count": 2.5, "type": "VEC3"}), ["impossible count"], "a fractional count")
	var empty_sparse := _indexed_glb({"componentType": 5126, "count": 8, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 1],
		"sparse": {"count": 1, "indices": {"bufferView": 1, "componentType": 5125}, "values": {"bufferView": 2}}}, [sparse_index, sparse_value])
	check(CustomItems.check_glb(empty_sparse).error == "" and CustomItems.check_glb(_indexed_glb({"componentType": 5126, "count": 8, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 1]})).error == "", "custom: small empty and sparse accessors still pass")
	var kit_dir := WorldScene.kit_file("models")
	var kit_clear := true
	for name in DirAccess.get_files_at(kit_dir):
		if name.ends_with(".glb"):
			var said: String = CustomItems.check_glb(FileAccess.get_file_as_bytes(kit_dir.path_join(name))).error
			if said.contains("mesh data"):
				kit_clear = false
				print("  kit model over the data limit: ", name, " ", said)
	check(kit_clear, "custom: no kit model reaches the data limit")
	var picture := Image.create(40, 20, false, Image.FORMAT_RGB8)
	var outward := true
	for display in CustomItems.DISPLAYS:
		var mesh := CustomItems.display_mesh(picture, display, 2.0)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			for t in range(0, order.size(), 3):
				var a := v[order[t]]
				outward = outward and (v[order[t + 1]] - a).cross(v[order[t + 2]] - a).dot(n[order[t]]) < 0.0
	check(outward, "custom: every face of a sign or banner faces the way it's lit, as Godot draws it")
	var lone := MeshInstance3D.new()
	lone.mesh = BoxMesh.new()
	var g := GLTFDocument.new()
	g.root_node_mode = GLTFDocument.ROOT_NODE_MODE_SINGLE_ROOT
	var state := GLTFState.new()
	g.append_from_scene(lone, state)
	var single_path := _file(files, "single_root.glb", g.generate_buffer(state))
	lone.free()
	var single := CustomItems.add(single_path, {"type": "model", "label": "Single root", "height": 1.0, "rights": true, "upright": "", "seated": false})
	WorldScene.refresh_custom()
	check(single.error == "" and WorldScene.load_kit().models.has(single.get("kind", "")) and WorldScene.mesh_of(single.kind).get_surface_count() > 0, "custom: a file whose root is the mesh itself is read: " + single.error)
	var pole_box := BoxMesh.new()
	pole_box.size = Vector3(0.01, 2.0, 0.01)
	var pole_path := _file(files, "pole.glb", _scene_glb(pole_box))
	var pole := CustomItems.add(pole_path, {"type": "model", "label": "Pole", "height": 1.0, "rights": true, "upright": "", "seated": false})
	WorldScene.refresh_custom()
	check(pole.error == "" and WorldScene.load_kit().models.has(pole.get("kind", "")) and float(WorldScene.load_kit().models[pole.kind].radius) >= 0.01, "custom: a very thin model stays listed after it's added")
	var crate := _file(files, "crate.glb", FileAccess.get_file_as_bytes(WorldScene.kit_file("models/crate.glb")))
	var crate_settings := {"type": "model", "label": "Crate", "height": 1.0, "rights": true, "upright": "", "seated": false}
	var crate_kind: String = CustomItems.add(crate, crate_settings).get("kind", "")
	var crate_dir := CustomItems.folder(CustomItems.id_of(crate_kind))
	var whole := FileAccess.get_file_as_bytes(crate_dir.path_join("model.glb"))
	_store(crate_dir.path_join("model.glb"), whole.slice(0, whole.size() / 2))
	WorldScene.refresh_custom()
	var doc := WorldDoc.create("guild", "Damaged", 3)
	doc.add_thing(crate_kind, 120.0, -120.0, 0.0, 1.0)
	check(not WorldScene.load_kit().models.has(crate_kind) and CustomItems.missing_in(doc).size() == 1 and not Clearance.check_world(doc).valid and Placing.why_not_one(doc, "fern", 120.0, -120.0) == "", "custom: a damaged upload is treated as missing")
	check(CustomItems.add(crate, {"type": "model", "label": "Crate", "height": 1.0, "rights": false}).error != "" and FileAccess.get_file_as_bytes(crate_dir.path_join("model.glb")).size() == whole.size() / 2, "custom: a refused re-upload leaves the damaged copy alone")
	_store(crate_dir + ".saving", "in the way".to_utf8_buffer())
	var blocked := CustomItems.add(crate, crate_settings)
	check(blocked.error != "" and FileAccess.get_file_as_bytes(crate_dir.path_join("model.glb")).size() == whole.size() / 2 and FileAccess.file_exists(crate_dir.path_join(CustomItems.ITEM_FILE)), "custom: a re-upload that can't be saved leaves the damaged copy alone: " + blocked.error)
	DirAccess.remove_absolute(crate_dir + ".saving")
	var replaced := CustomItems.add(crate, crate_settings)
	WorldScene.refresh_custom()
	check(replaced.error == "" and replaced.get("kind", "") == crate_kind and WorldScene.load_kit().models.has(crate_kind) and FileAccess.get_file_as_bytes(crate_dir.path_join("model.glb")) == whole and Clearance.check_world(doc).valid, "custom: re-uploading the same file replaces a damaged copy: " + replaced.error)
	check(not DirAccess.dir_exists_absolute(crate_dir + ".saving") and not DirAccess.dir_exists_absolute(crate_dir + ".old"), "custom: replacing leaves nothing behind")
	await _custom_integrity(files)

func _usable(kind: String, doc: WorldDoc) -> Array:
	WorldScene.refresh_custom()
	return [WorldScene.load_kit().models.has(kind), CustomItems.missing_in(doc).is_empty(), Clearance.check_world(doc).valid, not CustomItems.item(kind).is_empty()]

func _flipped(bytes: PackedByteArray) -> PackedByteArray:
	var out := bytes.duplicate()
	for i in range(100, 200):
		out[i] = out[i] ^ 0xFF
	return out

func _arranged(wrap: bool, mode: int) -> AABB:
	var body := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(1, 2, 3)
	body.mesh = block
	body.rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)
	body.scale = Vector3(2, 2, 1)
	var arm := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.5, 0.5, 0.5)
	arm.mesh = cube
	arm.position = Vector3(1, 0, 0)
	body.add_child(arm)
	arm.owner = body
	var top: Node = body
	if wrap:
		top = Node3D.new()
		top.add_child(body)
		body.owner = top
		arm.owner = top
	var g := GLTFDocument.new()
	g.root_node_mode = mode
	var state := GLTFState.new()
	g.append_from_scene(top, state)
	var bytes := g.generate_buffer(state)
	top.free()
	return WorldScene.glb_mesh(bytes, true).get_aabb()

func _custom_integrity(files: String) -> void:
	var bucket_bytes := FileAccess.get_file_as_bytes(WorldScene.kit_file("models/bucket.glb"))
	var bucket := _file(files, "bucket.glb", bucket_bytes)
	var kind: String = CustomItems.add(bucket, {"type": "model", "label": "Bucket", "height": 1.0, "rights": true, "upright": "", "seated": false}).get("kind", "")
	var dir := CustomItems.folder(CustomItems.id_of(kind))
	var source := dir.path_join("model.glb")
	check(kind == CustomItems.PREFIX + CustomItems.new_id(bucket_bytes, "model") and CustomItems.new_id(FileAccess.get_file_as_bytes(source), "model") == CustomItems.id_of(kind), "integrity: the stored model hashes to its id exactly as the id was made")
	var flag := Image.create(300, 200, false, Image.FORMAT_RGB8)
	flag.fill(Color(0.2, 0.6, 0.3))
	var flag_bytes := flag.save_png_to_buffer()
	var flag_path := _file(files, "flag.png", flag_bytes)
	for display in CustomItems.DISPLAYS:
		var shown: String = CustomItems.add(flag_path, {"type": "image", "label": "Flag", "height": 2.0, "rights": true, "display": display}).get("kind", "")
		var stored := CustomItems.folder(CustomItems.id_of(shown)).path_join("image.png")
		check(shown == CustomItems.PREFIX + CustomItems.new_id(flag_bytes, display) and CustomItems.new_id(FileAccess.get_file_as_bytes(stored), display) == CustomItems.id_of(shown) and not CustomItems.item(shown).is_empty(), "integrity: a picture on a %s hashes to its id exactly as the id was made" % display)
	check(not FileAccess.get_file_as_string(dir.path_join(CustomItems.ITEM_FILE)).contains("sha256"), "integrity: no separate fingerprint is stored")
	var doc := WorldDoc.create("guild", "Integrity", 3)
	doc.add_thing(kind, 120.0, -120.0, 0.0, 1.0)
	var settings := {"type": "model", "label": "Bucket", "height": 1.0, "rights": true, "upright": "", "seated": false}
	for cycle in 3:
		_store(source, _flipped(bucket_bytes))
		check(FileAccess.get_file_as_bytes(source).size() == bucket_bytes.size() and _usable(kind, doc) == [false, false, false, false], "integrity: a same-length corruption is seen at once, cycle %d" % cycle)
		var repaired := CustomItems.add(bucket, settings)
		check(repaired.error == "" and _usable(kind, doc) == [true, true, true, true] and WorldScene.mesh_of(kind).get_surface_count() > 0, "integrity: an immediate repair is usable at once, cycle %d: %s" % [cycle, repaired.error])
	var picture_kind := CustomItems.PREFIX + CustomItems.new_id(flag_bytes, "sign")
	var picture_source := CustomItems.folder(CustomItems.id_of(picture_kind)).path_join("image.png")
	_store(picture_source, _flipped(flag_bytes))
	WorldScene.refresh_custom()
	check(not WorldScene.load_kit().models.has(picture_kind), "integrity: a corrupted picture is unavailable too")
	var legacy = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(CustomItems.ITEM_FILE)))
	legacy.erase("sha256")
	_store(dir.path_join(CustomItems.ITEM_FILE), JSON.stringify(legacy).to_utf8_buffer())
	check(_usable(kind, doc) == [true, true, true, true], "integrity: an upload saved before fingerprints still shows")
	_store(source, bucket_bytes.slice(0, bucket_bytes.size() / 2))
	check(_usable(kind, doc) == [false, false, false, false], "integrity: a damaged upload saved before fingerprints is unavailable, flagged and blocks export")
	check(CustomItems.add(bucket, settings).error == "" and _usable(kind, doc) == [true, true, true, true], "integrity: re-uploading repairs an upload saved before fingerprints")
	legacy = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(CustomItems.ITEM_FILE)))
	legacy.sha256 = "0".repeat(64)
	_store(dir.path_join(CustomItems.ITEM_FILE), JSON.stringify(legacy).to_utf8_buffer())
	check(_usable(kind, doc) == [true, true, true, true], "integrity: an upload is checked by its id, whatever else its file says")
	var reference := AABB()
	var body_xf := Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(30.0), 0.0)).scaled_local(Vector3(2, 2, 1)), Vector3.ZERO)
	reference = body_xf * AABB(Vector3(-0.5, -1.0, -1.5), Vector3(1, 2, 3))
	reference = reference.merge(body_xf * Transform3D(Basis(), Vector3(1, 0, 0)) * AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5)))
	var arrangements := {"holder root": _arranged(true, GLTFDocument.ROOT_NODE_MODE_SINGLE_ROOT), "mesh as the root": _arranged(false, GLTFDocument.ROOT_NODE_MODE_SINGLE_ROOT), "several roots": _arranged(true, GLTFDocument.ROOT_NODE_MODE_MULTI_ROOT)}
	for name in arrangements:
		var box: AABB = arrangements[name]
		check(box.position.is_equal_approx(reference.position) and box.size.is_equal_approx(reference.size), "geometry: %s gives the model's true bounds, transforms applied once: %s vs %s" % [name, box, reference])
	var kit_dir := WorldScene.kit_file("models")
	var plain_roots := true
	for name in DirAccess.get_files_at(kit_dir):
		if name.ends_with(".glb"):
			var g := GLTFDocument.new()
			var state := GLTFState.new()
			if g.append_from_file(kit_dir.path_join(name), state) == OK:
				var root: Node = g.generate_scene(state)
				plain_roots = plain_roots and (not root is Node3D or (root as Node3D).transform == Transform3D.IDENTITY)
				root.free()
	check(plain_roots, "geometry: every kit model's root is untransformed, so applying the root changes no kit model")
	_custom_mirrors()

func _outward(arrays: Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	var right := 0
	var wrong := 0
	for t in range(0, order.size(), 3):
		var a := v[order[t]]
		if (v[order[t + 1]] - a).cross(v[order[t + 2]] - a).dot(n[order[t]]) < 0.0:
			right += 1
		else:
			wrong += 1
	return [right, wrong]

func _mesh_outward(mesh: Mesh) -> Array:
	var total := [0, 0]
	for s in mesh.get_surface_count():
		var f := _outward(mesh.surface_get_arrays(s))
		total = [total[0] + f[0], total[1] + f[1]]
	return total

func _mirrored_glb(top_scale: Vector3, child_scale: Vector3, wrap: bool) -> PackedByteArray:
	var top := MeshInstance3D.new() if not wrap else Node3D.new()
	top.scale = top_scale
	if top is MeshInstance3D:
		top.mesh = BoxMesh.new()
	var child := MeshInstance3D.new()
	child.mesh = BoxMesh.new()
	child.scale = child_scale
	child.position = Vector3(1.5, 0.0, 0.0)
	top.add_child(child)
	child.owner = top
	var g := GLTFDocument.new()
	g.root_node_mode = GLTFDocument.ROOT_NODE_MODE_SINGLE_ROOT
	var state := GLTFState.new()
	g.append_from_scene(top, state)
	var bytes := g.generate_buffer(state)
	top.free()
	return bytes

func _custom_mirrors() -> void:
	var cases := {
		"a mirrored mesh as the root": _mirrored_glb(Vector3(-1, 1, 1), Vector3.ONE, false),
		"a mirrored child in a holder": _mirrored_glb(Vector3.ONE, Vector3(-1, 1, 1), true),
		"a mirrored parent with a plain child": _mirrored_glb(Vector3(-1, 1, 1), Vector3.ONE, true),
		"two mirrors that cancel": _mirrored_glb(Vector3(-1, 1, 1), Vector3(1, 1, -1), true),
		"no mirror at all": _mirrored_glb(Vector3.ONE, Vector3.ONE, false),
	}
	for name in cases:
		var faces := _mesh_outward(WorldScene.glb_mesh(cases[name], true))
		check(faces[0] > 0 and faces[1] == 0, "mirrors: every face points outward for %s: %s" % [name, faces])
	var root_box := WorldScene.glb_mesh(cases["a mirrored mesh as the root"], true).get_aabb()
	var flip := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	var reference := (flip * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)).merge(flip * Transform3D(Basis(), Vector3(1.5, 0, 0)) * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))
	check(root_box.position.is_equal_approx(reference.position) and root_box.size.is_equal_approx(reference.size), "mirrors: a mirrored model keeps its true bounds: %s vs %s" % [root_box, reference])
	var box_arrays := BoxMesh.new().get_mesh_arrays()
	var lean := Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(-2, 1, 1.5)), Vector3(3, 0, 1))
	for xf in [lean, Transform3D(Basis.from_scale(Vector3(2, 1, 1)), Vector3.ZERO)]:
		var mirrored: bool = xf.basis.determinant() < 0.0
		var arrays := box_arrays.duplicate(true)
		var before_order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX].duplicate()
		var n0: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
		var t0: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT].duplicate()
		WorldScene._transform_arrays(arrays, xf)
		var n1: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var t1: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var handed := true
		for i in n0.size():
			var bitangent := n0[i].cross(Vector3(t0[i * 4], t0[i * 4 + 1], t0[i * 4 + 2])) * t0[i * 4 + 3]
			var rebuilt := n1[i].cross(Vector3(t1[i * 4], t1[i * 4 + 1], t1[i * 4 + 2])) * t1[i * 4 + 3]
			handed = handed and rebuilt.dot(xf.basis * bitangent) > 0.0
		var faces := _outward(arrays)
		check(faces[1] == 0 and handed, "mirrors: an indexed mesh keeps outward faces and tangent handedness, mirrored=%s: %s" % [mirrored, faces])
		if not mirrored:
			check(arrays[Mesh.ARRAY_INDEX] == before_order, "mirrors: an unmirrored mesh keeps its triangles exactly as they were")
		var st := SurfaceTool.new()
		st.create_from_arrays(box_arrays.duplicate(true))
		st.deindex()
		var loose := st.commit_to_arrays()
		var loose_count: int = loose[Mesh.ARRAY_VERTEX].size()
		WorldScene._transform_arrays(loose, xf)
		var loose_faces := _outward(loose)
		check(loose_faces[1] == 0 and loose[Mesh.ARRAY_VERTEX].size() == loose_count and (loose[Mesh.ARRAY_INDEX] != null) == mirrored, "mirrors: a mesh without an index list keeps outward faces, mirrored=%s: %s" % [mirrored, loose_faces])
	var kit_dir := WorldScene.kit_file("models")
	var kit_mirrored := []
	for name in DirAccess.get_files_at(kit_dir):
		if name.ends_with(".glb"):
			var g := GLTFDocument.new()
			var state := GLTFState.new()
			if g.append_from_file(kit_dir.path_join(name), state) == OK:
				var root: Node = g.generate_scene(state)
				var found: Array = root.find_children("*", "MeshInstance3D", true, false)
				if root is MeshInstance3D:
					found.push_front(root)
				for mi in found:
					var xf: Transform3D = WorldScene._to_root(mi, root)
					if root is Node3D:
						xf = (root as Node3D).transform * xf
					if xf.basis.determinant() < 0.0:
						kit_mirrored.append(name)
				root.free()
	check(kit_mirrored.is_empty(), "mirrors: no kit model contains a mirrored mesh, so the kit is unchanged: %s" % [kit_mirrored])

class McpStubHost:
	extends Node
	var disconnected := 0
	func agent_editor() -> Control:
		return null
	func agent_loading() -> bool:
		return false
	func agent_disconnected() -> void:
		disconnected += 1

func _mcp_server(host: Node, lines: Array) -> McpServer:
	var server := McpServer.new()
	server.read_stdin = false
	server.host = host
	server.write_line = func(line: String): lines.append(line)
	host.add_child(server)
	return server

const REPLY_WAIT_MS := 60000

func _rpc(server: McpServer, lines: Array, msg: Dictionary) -> Dictionary:
	lines.clear()
	server.receive(JSON.stringify(msg))
	var deadline := Time.get_ticks_msec() + REPLY_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		for line in lines:
			var parsed = JSON.parse_string(line)
			if parsed is Dictionary and parsed.has("id") and _same_id(parsed.id, msg.get("id")):
				return parsed
		await process_frame
	return {}

static func _same_id(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b

func _call_tool(server: McpServer, lines: Array, id: int, name: String, args: Dictionary) -> Dictionary:
	var reply := await _rpc(server, lines, {"jsonrpc": "2.0", "id": id, "method": "tools/call", "params": {"name": name, "arguments": args}})
	return reply.get("result", {})

static func _data(result: Dictionary) -> Dictionary:
	return result.get("structuredContent", {})

static func _text(result: Dictionary) -> String:
	return str(result.get("content", [{}])[0].get("text", ""))

func _mcp() -> bool:
	var lines := []
	var stub := McpStubHost.new()
	root.add_child(stub)
	var server := _mcp_server(stub, lines)
	var bad := await _rpc(server, lines, {"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
	check(bad.get("error", {}).get("code") == McpServer.INVALID_REQUEST, "mcp: refuses tools before initialize")
	lines.clear()
	server.receive("{not json")
	check(lines.size() == 1 and JSON.parse_string(lines[0]).error.code == McpServer.PARSE_ERROR and JSON.parse_string(lines[0]).id == null, "mcp: malformed JSON gets a parse error")
	lines.clear()
	server.receive("[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}]")
	check(lines.size() == 1 and JSON.parse_string(lines[0]).error.code == McpServer.INVALID_REQUEST, "mcp: refuses batches")
	lines.clear()
	server.receive("{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"ping\"}")
	check(lines.size() == 1 and JSON.parse_string(lines[0]).error.code == McpServer.INVALID_REQUEST, "mcp: refuses a null id")
	var init := await _rpc(server, lines, {"jsonrpc": "2.0", "id": 7, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}}})
	check(init.get("result", {}).get("protocolVersion") == "2025-11-25" and init.result.serverInfo.name == "agent-guild-builders" and init.result.has("instructions"), "mcp: initialize answers with the asked version")
	check(lines.size() == 1 and lines[0].contains("\"id\":7,") and not lines[0].contains("7.0"), "mcp: integer ids come back as integers")
	check(not init.result.has("resultType"), "mcp: legacy results carry no resultType")
	var old := await _rpc(server, lines, {"jsonrpc": "2.0", "id": 8, "method": "initialize", "params": {"protocolVersion": "1999-01-01"}})
	check(old.result.protocolVersion == McpServer.LEGACY[0], "mcp: an unknown version gets the newest legacy one")
	lines.clear()
	server.receive(JSON.stringify({"jsonrpc": "2.0", "method": "notifications/initialized"}))
	check(lines.is_empty(), "mcp: notifications get no reply")
	var meta := {McpServer.META_VERSION: McpServer.MODERN, McpServer.META_CAPABILITIES: {}, "io.modelcontextprotocol/clientInfo": {"name": "t", "version": "1"}}
	var discover := await _rpc(server, lines, {"jsonrpc": "2.0", "id": "d1", "method": "server/discover", "params": {"_meta": meta}})
	check(discover.get("result", {}).get("resultType") == "complete" and McpServer.MODERN in discover.result.supportedVersions and discover.result._meta[McpServer.META_SERVER].name == "agent-guild-builders", "mcp: server/discover answers a 2026-07-28 request")
	var future := await _rpc(server, lines, {"jsonrpc": "2.0", "id": "d2", "method": "server/discover", "params": {"_meta": {McpServer.META_VERSION: "2099-01-01", McpServer.META_CAPABILITIES: {}}}})
	check(future.get("error", {}).get("code") == McpServer.UNSUPPORTED_VERSION and future.error.data.requested == "2099-01-01" and McpServer.MODERN in future.error.data.supported, "mcp: an unsupported version gets -32022 with the supported list")
	var no_caps := await _rpc(server, lines, {"jsonrpc": "2.0", "id": "d3", "method": "tools/list", "params": {"_meta": {McpServer.META_VERSION: McpServer.MODERN}}})
	check(no_caps.get("error", {}).get("code") == McpServer.INVALID_PARAMS, "mcp: a 2026-07-28 request without client capabilities is refused")
	var bare := await _rpc(server, lines, {"jsonrpc": "2.0", "id": "d4", "method": "server/discover"})
	check(bare.get("error", {}).get("code") == McpServer.INVALID_PARAMS, "mcp: server/discover needs its metadata")
	var modern_init := await _rpc(server, lines, {"jsonrpc": "2.0", "id": "d5", "method": "initialize", "params": {"_meta": meta, "protocolVersion": "2025-11-25"}})
	check(modern_init.get("error", {}).get("code") == McpServer.METHOD_NOT_FOUND, "mcp: initialize isn't part of 2026-07-28")
	var listed := await _rpc(server, lines, {"jsonrpc": "2.0", "id": "d6", "method": "tools/list", "params": {"_meta": meta}})
	var names: Array = listed.get("result", {}).get("tools", []).map(func(t): return t.name)
	check(names == ["list_worlds", "create_world", "open_world", "describe_world", "list_items", "place_items", "paint_area", "move_items", "remove_items", "shape_land", "paint_ground", "set_look", "undo", "redo", "render_preview", "export_world"], "mcp: lists the planned tools")
	check(listed.result.tools.all(func(t): return t.inputSchema.type == "object" and t.annotations.has("readOnlyHint") and t.has("description")), "mcp: every tool has a schema, hints and a description")
	check(listed.result.resultType == "complete", "mcp: 2026-07-28 results carry resultType")
	var unknown := await _rpc(server, lines, {"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "fly", "arguments": {}}})
	check(unknown.get("error", {}).get("code") == McpServer.INVALID_PARAMS, "mcp: an unknown tool is a protocol error")
	var nothing := await _rpc(server, lines, {"jsonrpc": "2.0", "id": 10, "method": "resources/list"})
	check(nothing.get("error", {}).get("code") == McpServer.METHOD_NOT_FOUND, "mcp: unknown methods are refused")
	var wrong := await _call_tool(server, lines, 11, "place_items", {"world": "x"})
	check(wrong.get("isError") == true and _text(wrong).contains("items"), "mcp: bad arguments come back as a tool error naming the problem")
	var closed := await _call_tool(server, lines, 12, "describe_world", {"world": "x"})
	check(closed.get("isError") == true and _text(closed).contains("No world is open"), "mcp: world tools say when nothing is open")
	server._active = {"ctx": {"id": 99, "cancelled": false}, "long": false}
	lines.clear()
	server.receive(JSON.stringify({"jsonrpc": "2.0", "id": 13, "method": "ping"}))
	check(lines.is_empty(), "mcp: requests wait while a world is opening")
	server.receive(JSON.stringify({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 13}}))
	server._active = {}
	server._pump()
	check(lines.is_empty(), "mcp: a cancelled request is never answered")
	server._active = {"ctx": {"id": 98, "cancelled": false}, "long": true}
	var busy := await _call_tool(server, lines, 14, "place_items", {"world": "x", "items": [{"kind": "stone", "x": 100, "z": -100}]})
	check(busy.get("isError") == true and _text(busy).contains("rendering"), "mcp: edits are refused while rendering")
	var reading := await _call_tool(server, lines, 15, "list_items", {"search": "stone"})
	check(reading.get("isError") == false and _data(reading).items.size() > 0, "mcp: reading tools still answer while rendering")
	server._active = {}
	check(lines.all(func(l): return not l.contains("\n") and JSON.parse_string(l) is Dictionary), "mcp: every line written is one JSON message")
	server._stdin_closed()
	check(stub.disconnected == 1, "mcp: the end of stdin closes the app")
	lines.clear()
	server.receive(JSON.stringify({"jsonrpc": "2.0", "id": 16, "method": "ping"}))
	check(lines.is_empty(), "mcp: nothing is answered after stdin closes")
	stub.free()

	var outside := OS.get_user_data_dir().path_join("mcp-export-test")
	DirAccess.make_dir_recursive_absolute(outside)
	var docs := ProjectSettings.globalize_path("res://").path_join(".godot/mcp-export-test")
	DirAccess.make_dir_recursive_absolute(docs)
	check(McpTools.export_problem("world.agworld", false) != "", "mcp: export needs a full path")
	check(McpTools.export_problem(docs + "/../x.agworld", false).contains(".."), "mcp: export refuses ..")
	check(McpTools.export_problem(docs + "/x.zip", false).contains(".agworld"), "mcp: export needs the .agworld extension")
	check(McpTools.export_problem(docs + "/missing/x.agworld", false).contains("doesn't exist"), "mcp: export needs an existing folder")
	check(McpTools.export_problem(outside + "/x.agworld", false).contains("own files"), "mcp: export stays out of the app's data")
	check(McpTools.export_problem(docs + "/x.agworld", false) == "", "mcp: export accepts a writable folder")
	var existing := FileAccess.open(docs + "/x.agworld", FileAccess.WRITE)
	existing.store_8(1)
	existing.close()
	check(McpTools.export_problem(docs + "/x.agworld", false).contains("replace"), "mcp: export won't replace a file unless asked")
	check(McpTools.export_problem(docs + "/x.agworld", true) == "", "mcp: export replaces when asked")
	DirAccess.remove_absolute(docs + "/x.agworld")
	DirAccess.remove_absolute(docs)
	DirAccess.remove_absolute(outside)

	var commands: Array = load("res://src/ui/main.gd").connect_commands("C:/Program Files/Agent Guild Builders/AgentGuildBuilders.exe", [])
	check(commands.map(func(c): return c[0]) == ["Claude Code", "Codex CLI", "Antigravity CLI", "Grok Build", "Docker Agent"], "mcp: connect commands cover every Agent Guild provider")
	check(commands[0][1] == "claude mcp add -s user agent-guild-builders \"--\" 'C:/Program Files/Agent Guild Builders/AgentGuildBuilders.exe' --no-header \"--\" --mcp", "mcp: the Claude Code command quotes the path and every --")
	var brackets: Array = load("res://src/ui/main.gd").connect_commands("C:/Apps(Builders)/AgentGuildBuilders.exe", [])
	check(brackets[0][1].contains(" 'C:/Apps(Builders)/AgentGuildBuilders.exe' "), "mcp: a path PowerShell would read as an expression is single-quoted")
	check(commands[2][1].begins_with("agy mcp add agent-guild-builders \"--\" "), "mcp: Antigravity flags come before the name")
	check(commands[4][1].contains("type: mcp") and commands[4][1].contains("'--no-header', '--', '--mcp'"), "mcp: the Docker Agent toolset has the server's arguments")
	var dollar: Array = load("res://src/ui/main.gd").connect_commands("C:/Apps $x/it's/AgentGuildBuilders.exe", [])
	check(dollar[1][1].contains("'C:/Apps $x/it''s/AgentGuildBuilders.exe'"), "mcp: paths PowerShell would expand are single-quoted")
	var job := BakeJob.new()
	root.add_child(job)
	var ended := []
	job.finished.connect(func(e): ended.append(e))
	job.run(WorldDoc.create("guild", "T", 1), OS.get_user_data_dir().path_join("mcp-never.agworld"), "draft")
	for i in 10:
		await process_frame
	check(ended == [BakeJob.NEEDS_WINDOW], "mcp: exporting without a window fails at once")
	check(await job.preview(WorldDoc.create("guild", "T", 1), "light") == null and job.error == BakeJob.NEEDS_WINDOW, "mcp: previewing without a window fails at once")
	job.free()
	return await _mcp_editor()

## The tools against the real app and editor, as an agent would use them.
func _mcp_editor() -> bool:
	var library := OS.get_user_data_dir().path_join("mcp-test-worlds")
	WorldLibrary.root_override = library
	var app: Control = load("res://src/ui/main.gd").new()
	root.size = Vector2i(1440, 900)
	root.add_child(app)
	var lines := []
	var server := _mcp_server(app, lines)
	app._mcp = server
	await _rpc(server, lines, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}})
	var made := await _call_tool(server, lines, 2, "create_world", {"template": "blank", "title": "Agent test", "seed": 5})
	check(made.get("isError") == false and FileAccess.file_exists(str(_data(made).get("world", "")).path_join("world.json")), "mcp: create_world makes, opens and saves a world")
	var world := str(_data(made).get("world", ""))
	var view: Control = app.agent_editor()
	check(view != null and view.path == world and view._agent_label.visible, "mcp: the window shows the new world and that an agent is connected")
	var worlds := await _call_tool(server, lines, 3, "list_worlds", {})
	check(_data(worlds).worlds.any(func(w): return w.world == world and w.open), "mcp: list_worlds marks the open world")
	var elsewhere := await _call_tool(server, lines, 4, "describe_world", {"world": library.path_join("other")})
	check(elsewhere.get("isError") == true and _text(elsewhere).contains(world), "mcp: a different world's id is refused, naming the open one")
	var doc: WorldDoc = view.doc
	var spots := []
	for x in range(60, 200, 6):
		var z := -100.0
		if Placing.why_not_one(doc, "stone", x, z) == "" and spots.size() < 3:
			spots.append(Vector2(x, z))
	var before: int = doc.data.things.size()
	var plaza_why := Placing.why_not_one(doc, "stone", 0, 0)
	var placed := await _call_tool(server, lines, 5, "place_items", {"world": world, "items": [
		{"kind": "stone", "x": spots[0].x, "z": spots[0].y, "turn": 90}, {"kind": "stone", "x": 0, "z": 0}, {"kind": "unicorn", "x": spots[1].x, "z": spots[1].y},
		{"kind": "stone", "x": spots[2].x, "z": spots[2].y}]})
	var results: Array = _data(placed).get("results", [])
	check(results.size() == 4 and results[0].has("id") and results[3].has("id"), "mcp: place_items places the items that fit")
	check(results.size() == 4 and results[1].get("refused") == plaza_why and plaza_why != "", "mcp: a refusal carries the editor's own reason")
	check(results.size() == 4 and results[2].get("refused", "").contains("unicorn"), "mcp: an unknown kind is refused alone")
	check(doc.data.things.size() == before + 2 and view.history.undo_label() == "Place 2 things", "mcp: the placed items are one undo step")
	check(results.size() == 4 and is_equal_approx(float(results[0].turn), 90.0), "mcp: turns are in degrees")
	var moved := await _call_tool(server, lines, 6, "move_items", {"world": world, "moves": [{"id": results[0].id, "x": spots[0].x + 3, "z": spots[0].y}, {"id": results[3].id, "x": 0, "z": 0}, {"id": 999999}]})
	var moves: Array = _data(moved).get("results", [])
	check(moves.size() == 3 and moves[0].has("x") and moves[1].has("refused") and moves[2].get("refused", "").contains("999999"), "mcp: move_items moves what the rules allow and explains the rest")
	check(view.history.undo_label().begins_with("Move "), "mcp: the moves are one undo step")
	var undone := await _call_tool(server, lines, 7, "undo", {"world": world})
	check(undone.get("isError") == false and view.history.undo_label() == "Place 2 things", "mcp: undo steps back through the shared history")
	var redone := await _call_tool(server, lines, 8, "redo", {"world": world})
	check(redone.get("isError") == false and view.history.undo_label().begins_with("Move "), "mcp: redo steps forward again")
	var near := await _call_tool(server, lines, 9, "describe_world", {"world": world, "items_near": {"x": spots[0].x, "z": spots[0].y, "radius": 8}})
	check(_data(near).get("items_near", []).any(func(t): return int(t.id) == int(results[0].id)), "mcp: describe_world lists nearby items by id")
	var gone := await _call_tool(server, lines, 10, "remove_items", {"world": world, "ids": [results[0].id, 424242]})
	check(_data(gone).get("removed") == 1 and _data(gone).get("not_found", []).map(func(n): return int(n)) == [424242], "mcp: remove_items removes by id and lists ids it didn't find")
	var both := await _call_tool(server, lines, 11, "remove_items", {"world": world, "ids": [1], "radius": 3})
	check(both.get("isError") == true, "mcp: remove_items takes ids or an area, not both")
	var steps_before: String = view.history.undo_label()
	var painted := await _call_tool(server, lines, 12, "paint_area", {"world": world, "choice": "mix:rocks", "points": [{"x": 120, "z": -140}, {"x": 150, "z": -140}], "radius": 8})
	check(_data(painted).get("added", 0) > 0 and _data(painted).added_ids.size() == _data(painted).added and view.history.undo_label().begins_with("Paint "), "mcp: paint_area scatters a mix as one undo step")
	check(view.tool == view.Tool.SCATTER and view.place_mode == "one", "mcp: the person's own tool and options are left as they were")
	var raised := await _call_tool(server, lines, 13, "shape_land", {"world": world, "mode": "raise", "points": [{"x": 150, "z": -150}], "radius": 6, "strength": 3})
	check(_data(raised).get("cells", 0) > 0 and view.history.undo_label() == "Shape land" and doc.height_at(150, -150) > 0.0, "mcp: shape_land raises land as one undo step")
	var flat := await _call_tool(server, lines, 14, "shape_land", {"world": world, "mode": "raise", "points": [{"x": 0, "z": 0}], "radius": 4})
	check(_data(flat).get("cells") == 0 and _data(flat).get("limited") == true and doc.height_at(0, 0) == 0.0, "mcp: the crews' ground stays flat")
	var grounded := await _call_tool(server, lines, 15, "paint_ground", {"world": world, "ground": "gravel", "points": [{"x": 100, "z": -160}], "radius": 5})
	check(_data(grounded).get("cells", 0) > 0 and view.history.undo_label() == "Paint ground", "mcp: paint_ground paints as one undo step")
	var look := await _call_tool(server, lines, 16, "set_look", {"world": world, "season": "winter", "water": {"on": true, "level": -2.0}, "day": {"sky": "overcast", "sun_strength": 2.0}})
	check(look.get("isError") == false and doc.season() == "winter" and doc.data.mood.light.sky == "overcast" and is_equal_approx(float(doc.data.mood.light.sun_energy), 2.0) and is_equal_approx(doc.safe_water_level(), -2.0), "mcp: set_look changes season, water and sky")
	await _call_tool(server, lines, 17, "undo", {"world": world})
	check(doc.season() == "summer" and doc.data.mood.light.sky == "day" and float(doc.data.water_level) < WorldDoc.NO_WATER_BELOW, "mcp: one undo puts the whole look back")
	var preview := await _call_tool(server, lines, 18, "render_preview", {"world": world})
	check(preview.get("isError") == true and _text(preview) == BakeJob.NEEDS_WINDOW, "mcp: render_preview says it needs a window when headless")
	view._painting = true
	lines.clear()
	server.receive(JSON.stringify({"jsonrpc": "2.0", "id": 19, "method": "tools/call", "params": {"name": "undo", "arguments": {"world": world}}}))
	for i in 5:
		await process_frame
	check(lines.is_empty(), "mcp: an edit waits while the person is mid-stroke")
	view._painting = false
	for i in 5:
		await process_frame
	check(lines.size() == 1 and JSON.parse_string(lines[0]).id == 19, "mcp: the edit runs once the person lets go")
	view._exporting = true
	var rendering := await _call_tool(server, lines, 20, "place_items", {"world": world, "items": [{"kind": "stone", "x": spots[1].x, "z": spots[1].y}]})
	check(rendering.get("isError") == true and _text(rendering).contains("rendering"), "mcp: edits wait their turn behind the window's own render")
	view._exporting = false
	var renamed_path: String = view.path
	view.path = library.path_join("switched")
	var stale := await _call_tool(server, lines, 21, "place_items", {"world": world, "items": [{"kind": "stone", "x": spots[1].x, "z": spots[1].y}]})
	check(stale.get("isError") == true and doc.data.things.size() > 0, "mcp: an edit for a world that's no longer open is refused")
	view.path = renamed_path
	var reopened := await _call_tool(server, lines, 22, "create_world", {"template": "island", "title": "Agent test two", "seed": 6})
	var first := WorldDoc.open(world)
	check(reopened.get("isError") == false and first != null and first.season() == "summer" and first.data.mood.light.sky == "day", "mcp: switching worlds saves the one that was open")
	check(app.agent_editor() != null and app.agent_editor().path == str(_data(reopened).get("world")), "mcp: the window shows the newly created world")
	var back := await _call_tool(server, lines, 23, "open_world", {"world": world})
	check(back.get("isError") == false and app.agent_editor().path == world, "mcp: open_world opens a saved world")
	var missing := await _call_tool(server, lines, 24, "open_world", {"world": library.path_join("nowhere")})
	check(missing.get("isError") == true, "mcp: open_world refuses a folder with no world")
	await _mcp_edit_rules(server, lines, app.agent_editor(), world)
	await _mcp_review(server, lines, app.agent_editor(), world, library)
	await _mcp_races(server, lines, app, world, library)
	await _mcp_ux(server, lines, app, world)
	app.free()
	WorldLibrary.root_override = ""
	for w in DirAccess.get_directories_at(library):
		WorldDoc.remove_folder(library.path_join(w))
	DirAccess.remove_absolute(library)
	return await _mcp_integrity()

static func _things_key(doc: WorldDoc) -> String:
	var rows := []
	for t in doc.data.things:
		rows.append("%d:%s:%.4f:%.4f:%.4f:%.4f" % [int(t.id), t.kind, float(t.x), float(t.z), wrapf(float(t.turn), 0.0, TAU), float(t.scale)])
	rows.sort()
	return "|".join(rows)

static func _ids_unique(doc: WorldDoc) -> bool:
	var seen := {}
	for t in doc.data.things:
		if seen.has(int(t.id)):
			return false
		seen[int(t.id)] = true
	return true

## The world as it stands keeps unique ids, saves, and reopens with the same items.
func _round_trip(doc: WorldDoc, what: String) -> void:
	var dir := OS.get_user_data_dir().path_join("mcp-round-trip")
	var saved := doc.save(dir) == OK
	var back := WorldDoc.open(dir)
	check(_ids_unique(doc) and saved and back != null and _things_key(back) == _things_key(doc), "mcp: %s keeps unique ids and survives save and reopen" % what)
	WorldDoc.remove_folder(dir)

static func _item(doc: WorldDoc, id: int) -> Dictionary:
	var found: Array = doc.data.things.filter(func(t): return int(t.id) == id)
	return found[0] if found.size() == 1 else {}

## move_items and remove_items against the editor's drag, turn and resize rules,
## checked by the items' actual values through undo, redo, save and reopen.
func _mcp_edit_rules(server: McpServer, lines: Array, view: Control, world: String) -> void:
	var doc: WorldDoc = view.doc
	var id := 100
	var placed := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "stone", "x": 170, "z": -60}]})
	var stone: Dictionary = _item(doc, int(_data(placed).results[0].get("id", -1)))
	check(not stone.is_empty(), "mcp: a stone to move")
	var before := _things_key(doc)
	var undo_before: String = view.history.undo_label()
	id += 1
	var twice := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": stone.id, "x": 173, "z": -60}, {"id": stone.id, "x": 176, "z": -60}]})
	check(twice.get("isError") == true and _text(twice).contains(str(stone.id)) and _things_key(doc) == before and view.history.undo_label() == undo_before, "mcp: a move naming an id twice is refused and changes nothing")
	id += 1
	var original: Dictionary = stone.duplicate()
	var gone := await _call_tool(server, lines, id, "remove_items", {"world": world, "ids": [stone.id, stone.id]})
	check(_data(gone).get("removed") == 1 and _item(doc, stone.id).is_empty(), "mcp: removing an id twice removes it once")
	_round_trip(doc, "a repeated remove")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	var back: Dictionary = _item(doc, stone.id)
	check(doc.data.things.filter(func(t): return int(t.id) == int(stone.id)).size() == 1 and back.x == original.x and back.z == original.z and back.scale == original.scale, "mcp: undoing it restores exactly one copy, unchanged")
	_round_trip(doc, "undoing a repeated remove")
	id += 1
	await _call_tool(server, lines, id, "redo", {"world": world})
	check(_item(doc, stone.id).is_empty(), "mcp: redo removes it again")
	_round_trip(doc, "redoing a repeated remove")

	id += 1
	var oak := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "tree_oak", "x": -150, "z": -150, "scale": 1.0}]})
	var tree: Dictionary = _item(doc, int(_data(oak).results[0].get("id", -1)))
	check(not tree.is_empty() and is_equal_approx(float(tree.scale), 1.0), "mcp: a full-size oak far back")
	var tree_was: Dictionary = tree.duplicate()
	id += 1
	var tall := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": tree.id, "x": -12, "z": 41}]})
	check(_data(tall).results[0].has("refused") and _item(doc, tree.id).x == tree_was.x, "mcp: a full-size oak can't move in front of the Yard")
	id += 1
	var small := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": tree.id, "x": -12, "z": 41, "scale": 0.5}]})
	var shrunk: Dictionary = _item(doc, tree.id)
	check(_data(small).results[0].has("id") and is_equal_approx(float(shrunk.x), -12.0) and is_equal_approx(float(shrunk.z), 41.0) and is_equal_approx(float(shrunk.scale), 0.5), "mcp: moving and shrinking is judged at the new size")
	_round_trip(doc, "a move with a resize")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	var undone: Dictionary = _item(doc, tree.id)
	check(undone.x == tree_was.x and undone.z == tree_was.z and undone.scale == tree_was.scale, "mcp: undo puts the oak back at its old place and size")
	_round_trip(doc, "undoing a move with a resize")
	id += 1
	await _call_tool(server, lines, id, "redo", {"world": world})
	var redone: Dictionary = _item(doc, tree.id)
	check(is_equal_approx(float(redone.x), -12.0) and is_equal_approx(float(redone.scale), 0.5), "mcp: redo moves and shrinks it again")
	_round_trip(doc, "redoing a move with a resize")
	id += 1
	var too_big := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": tree.id, "scale": 2.0}]})
	check(_data(too_big).results[0].has("refused") and is_equal_approx(float(_item(doc, tree.id).scale), 0.5), "mcp: a resize in place follows the size slider's limit")
	id += 1
	var pebble_placed := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "stone", "x": 170, "z": -40, "scale": 1.0}]})
	var pebble: Dictionary = _item(doc, int(_data(pebble_placed).results[0].get("id", -1)))
	id += 1
	var turned := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": pebble.id, "turn": 30, "scale": 1.5}]})
	var t_after: Dictionary = _item(doc, pebble.id)
	check(_data(turned).results[0].has("id") and t_after.x == pebble.x and t_after.z == pebble.z and is_equal_approx(rad_to_deg(float(t_after.turn)), 30.0) and is_equal_approx(float(t_after.scale), 1.5), "mcp: a turn with a resize keeps the position")
	_round_trip(doc, "a turn with a resize")

	id += 1
	var wall_placed := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "fort_thick_straight", "x": 100, "z": -180}]})
	var wall: Dictionary = _item(doc, int(_data(wall_placed).results[0].get("id", -1)))
	var pointer := Vector2.ZERO
	for joint in WorldScene.load_kit().models.fort_thick_straight.joints:
		var at := Vector2(float(wall.get("x", 0)) + joint[0], float(wall.get("z", 0)) + joint[1])
		if Placing.placement(doc, "fort_thick_thin_transition", Vector3(at.x, 0, at.y), 0.0).joins != "":
			pointer = at
			break
	id += 1
	var join_placed := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "fort_thick_thin_transition", "x": pointer.x, "z": pointer.y}]})
	var piece: Dictionary = _item(doc, int(_data(join_placed).results[0].get("id", -1)))
	check(not piece.is_empty() and _data(join_placed).results[0].get("joined") == "fort_thick_straight", "mcp: a transition piece joined to a wall")
	var piece_was: Dictionary = piece.duplicate()
	var quarter := wrapf(rad_to_deg(float(piece.turn)) + 90.0, 0.0, 360.0)
	id += 1
	var q := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": piece.id, "turn": quarter}]})
	var p_after: Dictionary = _item(doc, piece.id)
	check(_data(q).results[0].has("id") and p_after.x == piece_was.x and p_after.z == piece_was.z and is_equal_approx(rad_to_deg(float(p_after.turn)), quarter), "mcp: turning a joined piece a quarter keeps its place and takes the turn")
	_round_trip(doc, "turning a joined piece")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	check(is_equal_approx(float(_item(doc, piece.id).turn), float(piece_was.turn)), "mcp: undo turns it back")
	var key := _things_key(doc)
	id += 1
	var odd := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": piece.id, "turn": 45}]})
	check(_data(odd).results[0].get("refused", "").contains("90°") and _things_key(doc) == key, "mcp: a joined piece refuses a turn that isn't a quarter, unchanged")
	id += 1
	var conflict := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": piece.id, "x": pointer.x, "z": pointer.y, "turn": quarter}]})
	check(_data(conflict).results[0].get("refused", "").contains("join") and _things_key(doc) == key, "mcp: a move whose join would override the asked turn is refused, unchanged")
	id += 1
	var resize_wall := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": wall.id, "scale": 1.5}]})
	check(_data(resize_wall).results[0].get("refused", "").contains("own size") and _things_key(doc) == key, "mcp: a wall piece can't be resized")
	id += 1
	var nothing := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": wall.id}]})
	check(_data(nothing).results[0].get("refused", "").contains("Nothing to change"), "mcp: a move with nothing to change says so")

	var steps_before: String = view.history.undo_label()
	id += 1
	var mixed := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": tree.id, "x": -14, "z": 41}, {"id": wall.id, "x": 0, "z": 0}, {"id": piece.id, "turn": quarter}]})
	var results: Array = _data(mixed).results
	check(results[0].has("id") and results[1].has("refused") and results[2].has("id") and _text(mixed).begins_with("Moved 2 of 3"), "mcp: a mixed batch reports exactly what it applied")
	check(view.history.undo_label() == "Move 2 things" and view.history.undo_label() != steps_before and _item(doc, wall.id).x == wall.x, "mcp: the accepted moves are one undo step and the refused item is untouched")
	_round_trip(doc, "a mixed batch")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	check(is_equal_approx(float(_item(doc, tree.id).x), -12.0) and is_equal_approx(float(_item(doc, piece.id).turn), float(piece_was.turn)), "mcp: one undo reverts the whole batch")
	_round_trip(doc, "undoing a mixed batch")

## The shared guards: history refuses an item twice, a failed history record
## leaves nothing changed, and saving refuses a world that couldn't reopen.
func _mcp_integrity() -> bool:
	var library := OS.get_user_data_dir().path_join("mcp-integrity-worlds")
	WorldLibrary.root_override = library
	var doc := WorldDoc.create("guild", "Integrity", 4)
	var view: Control = load("res://src/ui/editor_view.gd").new()
	root.size = Vector2i(1200, 800)
	root.add_child(view)
	view.size = Vector2(1200, 800)
	view.open(doc, "")
	await process_frame
	var t := doc.add_thing("stone", 100, -100, 0, 1)
	var key := _things_key(doc)
	check(view.history.things_edit("Twice", [t, t], []) == false and not view.history.can_undo() and _things_key(doc) == key, "mcp: history refuses an item listed twice and records nothing")
	var r: Array = view.agent_move([{"id": t.id, "x": 103.0, "z": -100.0}, {"id": t.id, "x": 106.0, "z": -100.0}])
	check(_things_key(doc) == key and not view.history.can_undo() and r.all(func(e): return e.get("why") == view.NOT_RECORDED), "mcp: an edit history refuses leaves the world unchanged and says so")
	view._begin_job("Agent render")
	var running: BakeJob = view._job
	var told := []
	view._export_to(OS.get_user_data_dir().path_join("mcp-never.agworld"), func(e, _notice): told.append(e))
	check(view._job == running and view._exporting and not running._cancelled and told == [view.ALREADY_RENDERING] and view._status.text == view.ALREADY_RENDERING, "mcp: an export chosen while a render runs is refused and the running render is kept")
	view._end_job()
	var dir := OS.get_user_data_dir().path_join("mcp-integrity")
	check(doc.save(dir) == OK, "mcp: a valid world saves")
	doc.data.things.append(t.duplicate())
	check(doc.save(dir) == ERR_INVALID_DATA and doc.save_error != "", "mcp: saving refuses a world with a repeated id")
	var kept := WorldDoc.open(dir)
	check(kept != null and _things_key(kept) == key, "mcp: the last good save is kept")
	doc.data.things.pop_back()
	doc.heights[10] = NAN
	check(doc.save(dir) == ERR_INVALID_DATA and WorldDoc.open(dir) != null, "mcp: saving refuses broken land and keeps the last good save")
	doc.heights[10] = 0.0
	WorldDoc.remove_folder(dir)
	view.free()
	_remove_tree(library)
	WorldLibrary.root_override = ""
	return true

func _mcp_review(server: McpServer, lines: Array, view: Control, world: String, library: String) -> void:
	var doc: WorldDoc = view.doc
	var id := 300
	var count: int = doc.data.things.size()
	var exact := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "stone", "x": 170, "z": -80, "scale": 0.5}, {"kind": "stone", "x": 176, "z": -80, "scale": 2.0}]})
	var rs: Array = _data(exact).results
	check(rs.size() == 2 and rs[0].has("id") and rs[1].has("id") and float(_item(doc, int(rs[0].id)).scale) == 0.5 and float(_item(doc, int(rs[1].id)).scale) == 2.0, "mcp: placing at an explicit scale keeps it exactly")
	_round_trip(doc, "placing at explicit scales")
	count = doc.data.things.size()
	id += 1
	var big := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "tree_oak", "x": -12, "z": 41, "scale": 1.0}]})
	check(_data(big).results[0].get("refused", "").contains("0.50×") and doc.data.things.size() == count, "mcp: a scale past the size slider's limit is refused with the range, and nothing is placed")
	var snug := Vector2.INF
	for x in range(-80, 81, 4):
		for z in [30.0, 36.0, 42.0, 48.0]:
			var room := Placing.largest_scale(doc, "tree_oak", x, z)
			if snug == Vector2.INF and room >= 0.55 and room < 0.85 and Placing.why_not_one(doc, "tree_oak", x, z) != "" and Placing.why_not_moved(doc, {"id": -1, "kind": "tree_oak", "x": x, "z": z, "turn": 0.0, "scale": 0.5}, x, z, 0.0) == "":
				snug = Vector2(x, z)
	check(snug != Vector2.INF, "mcp: a spot where a placed oak's usual size won't fit but a smaller one will")
	id += 1
	var fits := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "tree_oak", "x": snug.x, "z": snug.y, "scale": 0.5}]})
	var small_oak: Dictionary = _item(doc, int(_data(fits).results[0].get("id", -1)))
	check(not small_oak.is_empty() and float(small_oak.scale) == 0.5, "mcp: an explicit scale that fits is placed, judged at that size: %s" % _data(fits).results[0].get("refused", ""))
	id += 1
	await _call_tool(server, lines, id, "remove_items", {"world": world, "ids": [small_oak.get("id", -1)]})
	count = doc.data.things.size()
	id += 1
	var wall_scaled := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "fort_thick_straight", "x": 100, "z": -220, "scale": 1.5}]})
	check(_data(wall_scaled).results[0].get("refused", "").contains("own size") and doc.data.things.size() == count, "mcp: a wall piece given a scale is refused")
	id += 1
	var wall_placed := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "fort_thick_straight", "x": 100, "z": -220, "scale": 1.0}]})
	var wall: Dictionary = _item(doc, int(_data(wall_placed).results[0].get("id", -1)))
	check(not wall.is_empty() and float(wall.scale) == 1.0, "mcp: a wall piece given its own size is placed")
	var pointer := Vector2.ZERO
	var join_turn := 0.0
	for joint in WorldScene.load_kit().models.fort_thick_straight.joints:
		var at := Vector2(float(wall.x) + joint[0], float(wall.z) + joint[1])
		var spot := Placing.placement(doc, "fort_thick_thin_transition", Vector3(at.x, 0, at.y), 0.0)
		if spot.joins != "":
			pointer = at
			join_turn = rad_to_deg(float(spot.turn))
			break
	count = doc.data.things.size()
	id += 1
	var odd := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "fort_thick_thin_transition", "x": pointer.x, "z": pointer.y, "turn": 45}]})
	check(_data(odd).results[0].get("refused", "").contains("90°") and doc.data.things.size() == count, "mcp: placing a joining piece at a turn that isn't a quarter is refused")
	id += 1
	var overridden := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "fort_thick_thin_transition", "x": pointer.x, "z": pointer.y, "turn": wrapf(join_turn + 90.0, 0.0, 360.0)}]})
	check(_data(overridden).results[0].get("refused", "").contains("join") and doc.data.things.size() == count, "mcp: placing with a turn a join would override is refused")
	id += 1
	var joined := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "fort_thick_thin_transition", "x": pointer.x, "z": pointer.y}]})
	check(_data(joined).results[0].get("joined") == "fort_thick_straight", "mcp: without a turn the join decides")
	_round_trip(doc, "placing joined pieces")

	var edge := Vector2.INF
	var limit := 0.0
	for x in range(-90, 91, 3):
		for z in [28.0, 34.0, 40.0, 46.0, 52.0]:
			var r: float = view.size_range("tree_oak", x, z)[1]
			if edge == Vector2.INF and r > 0.5 and r < 0.99 and not is_equal_approx(r * 4.0, roundf(r * 4.0)) and Placing.why_not_moved(doc, {"id": -1, "kind": "tree_oak", "x": x, "z": z, "turn": 0.0, "scale": r}, x, z, 0.0) == "":
				edge = Vector2(x, z)
				limit = r
	check(edge != Vector2.INF and limit == floorf(Placing.largest_scale(doc, "tree_oak", edge.x, edge.y) * 100.0) / 100.0, "mcp: the size limit is the slider's plain two-decimal value")
	id += 1
	var over := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "tree_oak", "x": edge.x, "z": edge.y, "scale": limit + 0.01}]})
	check(_data(over).results[0].has("refused"), "mcp: just past the size limit is refused")
	id += 1
	var at_limit := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "tree_oak", "x": edge.x, "z": edge.y, "scale": limit}]})
	var limit_oak: Dictionary = _item(doc, int(_data(at_limit).results[0].get("id", -1)))
	check(not limit_oak.is_empty() and float(limit_oak.scale) == limit, "mcp: a scale exactly at the size limit is accepted: %s %s" % [limit, _data(at_limit).results[0].get("refused", "")])
	id += 1
	await _call_tool(server, lines, id, "remove_items", {"world": world, "ids": [limit_oak.get("id", -1)]})
	for bounds in [[0.1, 0.5], [1.5, 5.0]]:
		id += 1
		var edges := await _call_tool(server, lines, id, "set_look", {"world": world, "day": {"sky_strength": bounds[0], "sun_strength": bounds[1]}})
		check(edges.get("isError") == false and float(doc.data.mood.light.strength) == bounds[0] and float(doc.data.mood.light.sun_energy) == bounds[1], "mcp: sky %s and sun %s, exactly at the slider ends, are accepted" % bounds)
	id += 1
	var below := await _call_tool(server, lines, id, "set_look", {"world": world, "day": {"sky_strength": 0.09}})
	check(below.get("isError") == true and float(doc.data.mood.light.strength) == 1.5, "mcp: a sky strength below the slider is refused")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})

	var keep_custom := CustomItems.root_override
	CustomItems.root_override = OS.get_user_data_dir().path_join("mcp-custom-test")
	var files := OS.get_user_data_dir().path_join("mcp-custom-files")
	_remove_tree(CustomItems.root_override)
	_remove_tree(files)
	DirAccess.make_dir_recursive_absolute(files)
	var upload := _file(files, "barrel.glb", FileAccess.get_file_as_bytes(WorldScene.kit_file("models/barrel.glb")))
	var kind: String = CustomItems.add(upload, {"type": "model", "label": "My barrel", "height": 2.0, "rights": true, "upright": "", "seated": false}).get("kind", "")
	WorldScene.refresh_custom()
	id += 1
	var listed := await _call_tool(server, lines, id, "list_items", {"group": CustomItems.GROUP})
	check(kind != "" and _data(listed).items.any(func(i): return i.kind == kind and i.resizable), "mcp: list_items says custom uploads can be resized")
	id += 1
	var custom := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": kind, "x": -150, "z": -170, "scale": 1.5}]})
	var mine: Dictionary = _item(doc, int(_data(custom).results[0].get("id", -1)))
	check(not mine.is_empty() and float(mine.scale) == 1.5, "mcp: a custom upload is placed at its explicit scale")
	id += 1
	var resized := await _call_tool(server, lines, id, "move_items", {"world": world, "moves": [{"id": mine.get("id", -1), "scale": 0.8}]})
	check(_data(resized).results[0].has("id") and float(_item(doc, int(mine.get("id", -1))).scale) == 0.8, "mcp: a custom upload resizes like the editor's size slider allows")
	_round_trip(doc, "resizing a custom upload")
	id += 1
	await _call_tool(server, lines, id, "remove_items", {"world": world, "ids": [mine.get("id", -1)]})
	_remove_tree(CustomItems.root_override)
	_remove_tree(files)
	CustomItems.root_override = keep_custom
	WorldScene.refresh_custom()

	id += 1
	await _call_tool(server, lines, id, "list_worlds", {})
	var saved_key := _things_key(doc)
	id += 1
	var other := await _call_tool(server, lines, id, "create_world", {"template": "blank", "title": "Agent test three", "seed": 8})
	check(other.get("isError") == false, "mcp: a second world to switch to")
	DirAccess.rename_absolute(world, world + ".old")
	id += 1
	var recovered := await _call_tool(server, lines, id, "open_world", {"world": world})
	var open_view: Control = server.host.agent_editor()
	check(recovered.get("isError") == false and open_view != null and open_view.path == world and _things_key(open_view.doc) == saved_key, "mcp: open_world recovers an interrupted save with its items intact")
	var missing_kind := WorldDoc.create("guild", "Uses a missing item", 2)
	missing_kind.add_thing("not_in_any_kit", 120, -120, 0, 1)
	var missing_path := library.path_join("uses-missing")
	missing_kind.save(missing_path)
	var staying: Control = server.host.agent_editor()
	id += 1
	await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "stone", "x": 188, "z": -80}]})
	var staying_undo: String = staying.history.undo_label()
	var staying_key := _things_key(staying.doc)
	id += 1
	var unavailable := await _call_tool(server, lines, id, "open_world", {"world": missing_path})
	check(unavailable.get("isError") == true and _text(unavailable).contains("not_in_any_kit") and server.host.agent_editor() == staying and staying.path == world and staying_undo == "Place Stone" and staying.history.undo_label() == staying_undo and _things_key(staying.doc) == staying_key, "mcp: a world that fails to load leaves the open editor and its undo history in place")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	WorldDoc.remove_folder(missing_path)
	var broken := library.path_join("broken")
	DirAccess.make_dir_recursive_absolute(broken)
	_store(broken.path_join("world.json"), "{not json".to_utf8_buffer())
	_store(broken.path_join("terrain.bin"), PackedByteArray([1, 2, 3]))
	var before_view: Control = server.host.agent_editor()
	var before_doc: WorldDoc = before_view.doc
	id += 1
	var refused := await _call_tool(server, lines, id, "open_world", {"world": broken})
	check(refused.get("isError") == true and server.host.agent_editor() == before_view and before_view.path == world and _things_key(before_doc) == saved_key, "mcp: a world that can't be opened leaves the open world as it was")
	WorldDoc.remove_folder(broken)

func _close_dialogs(under: Node) -> void:
	for d in under.find_children("*", "AcceptDialog", true, false):
		d.hide()
		d.free()

func _mcp_ux(server: McpServer, lines: Array, app: Control, world: String) -> void:
	var view: Control = app.agent_editor()
	var doc: WorldDoc = view.doc
	var id := 500
	var steps: String = view.history.undo_label()
	var empty := await _call_tool(server, lines, id, "set_look", {"world": world, "day": {}})
	check(empty.get("isError") == true and view.history.undo_label() == steps, "mcp: an empty set_look is refused and records nothing")
	id += 1
	var same := await _call_tool(server, lines, id, "set_look", {"world": world, "season": doc.season(), "day": {"sky": doc.data.mood.light.sky}})
	check(same.get("isError") == false and _text(same).begins_with("Nothing changed") and view.history.undo_label() == steps, "mcp: values already set change nothing and add no undo step")
	var original_strength := float(doc.data.mood.light.strength)
	var sky: String = doc.data.mood.light.sky
	id += 1
	await _call_tool(server, lines, id, "set_look", {"world": world, "day": {"sky_strength": 0.7}})
	var after_strength: String = view.history.undo_label()
	check(float(doc.data.mood.light.strength) == 0.7 and after_strength == "Change the look", "mcp: a real look change is one undo step")
	id += 1
	var reselect := await _call_tool(server, lines, id, "set_look", {"world": world, "day": {"sky": sky}})
	check(_text(reselect).begins_with("Nothing changed") and float(doc.data.mood.light.strength) == 0.7, "mcp: choosing the sky already set keeps its strength, as the sky menu does")
	var other_sky := "overcast" if sky != "overcast" else "day"
	id += 1
	await _call_tool(server, lines, id, "set_look", {"world": world, "day": {"sky": other_sky}})
	check(doc.data.mood.light.sky == other_sky and float(doc.data.mood.light.strength) == float(WorldScene.load_kit().skies[other_sky].strength), "mcp: choosing a different sky resets its strength, as the sky menu does")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	check(doc.data.mood.light.sky == sky and float(doc.data.mood.light.strength) == 0.7, "mcp: one undo puts the sky and its strength back")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	check(float(doc.data.mood.light.strength) == original_strength and view.history.undo_label() == steps, "mcp: undo returns to where it started")

	view._open_custom_dialog()
	await process_frame
	var key := _things_key(doc)
	id += 1
	var refused := await _call_tool(server, lines, id, "create_world", {"template": "blank", "title": "Not now", "seed": 9})
	check(refused.get("isError") == true and _text(refused).contains("dialog") and app.agent_editor() == view and view.path == world and view.find_children("*", "CustomDialog", true, false).size() == 1, "mcp: a world switch is refused while a dialog is open, and the dialog stays")
	id += 1
	var meanwhile := await _call_tool(server, lines, id, "place_items", {"world": world, "items": [{"kind": "stone", "x": 182, "z": -80}]})
	check(_data(meanwhile).results[0].has("id"), "mcp: other edits still work while a dialog is open")
	id += 1
	await _call_tool(server, lines, id, "undo", {"world": world})
	check(_things_key(doc) == key, "mcp: and undo as usual")
	_close_dialogs(view)
	await process_frame
	view._title_box.grab_focus()
	view._title_box.text = "A name being typed"
	id += 1
	var typing := await _call_tool(server, lines, id, "open_world", {"world": world + "-nowhere"})
	check(typing.get("isError") == true and view._title_box.text == "A name being typed", "mcp: a world switch is refused while the person types, and the text stays")
	id += 1
	var typing_new := await _call_tool(server, lines, id, "create_world", {"template": "blank", "title": "Not now", "seed": 9})
	check(typing_new.get("isError") == true and _text(typing_new).contains("typing") and app.agent_editor() == view, "mcp: create_world waits for the person's typing too")
	view._title_box.text = str(doc.data.title)
	view._title_box.release_focus()

	await _mcp_disconnect(app, view)

	view._save_now()
	app._start_screen()
	await process_frame
	app._rename_dialog(WorldLibrary.list()[0])
	await process_frame
	id += 1
	var start := await _call_tool(server, lines, id, "create_world", {"template": "blank", "title": "Not now", "seed": 9})
	check(start.get("isError") == true and app.agent_editor() == null and app.find_children("*", "ConfirmationDialog", true, false).size() == 1, "mcp: on the start screen, a world switch waits for the person's dialog")
	_close_dialogs(app)

	root.size = Vector2i(1440, 900)
	app._connect_dialog("C:/" + "p".repeat(234) + "/AgentGuildBuilders.exe")
	var listeners := root.size_changed.get_connections().size()
	for size in [Vector2i(1440, 900), Vector2i(1120, 640), Vector2i(1440, 900)]:
		root.size = size
		await process_frame
		await process_frame
		var resized: AcceptDialog = app.get_node("ConnectAgentDialog")
		var resized_box := Rect2(resized.position, resized.size)
		var scroll_now: ScrollContainer = resized.find_child("Commands", true, false)
		check(resized.size.y <= size.y and Rect2(Vector2.ZERO, Vector2(size)).encloses(resized_box) and Rect2(Vector2.ZERO, resized.size).encloses(resized.get_ok_button().get_global_rect()) and scroll_now.size.y > 0, "mcp: after resizing to %s the open Connect dialog still fits with Done visible" % size)
	_close_dialogs(app)
	await process_frame
	check(root.size_changed.get_connections().size() == listeners - 1, "mcp: closing the Connect dialog removes its resize listener")
	root.size = Vector2i(1120, 640)
	for length in [151, 260]:
		var exe := "C:/" + "p".repeat(length - 26) + "/AgentGuildBuilders.exe"
		app._connect_dialog(exe)
		await process_frame
		await process_frame
		var dialog: AcceptDialog = app.get_node("ConnectAgentDialog")
		var done: Button = dialog.get_ok_button()
		var box := Rect2(Vector2.ZERO, dialog.size)
		var scroll: ScrollContainer = dialog.find_child("Commands", true, false)
		check(exe.length() == length and dialog.size.y <= 640 and box.encloses(done.get_global_rect()), "mcp: with a %d-character path the Connect dialog fits a 1120×640 window with Done visible" % length)
		check(scroll != null and scroll.get_child(0).get_combined_minimum_size().y > scroll.size.y, "mcp: and its commands scroll")
		_close_dialogs(app)

func _waiting(app: Control) -> Array:
	var result := [null]
	var wait := func():
		result[0] = await app.until_free_to_close()
	wait.call()
	return result

func _settle(result: Array) -> void:
	var deadline := Time.get_ticks_msec() + REPLY_WAIT_MS
	while result[0] == null and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout

## After the agent disconnects: Builders waits for dialogs and renders, and
## the person's "Keep rendering" or "Keep editing" ends automatic closing.
func _mcp_disconnect(app: Control, view: Control) -> void:
	app._connect_dialog()
	await process_frame
	var r := _waiting(app)
	for i in 20:
		await process_frame
	check(r[0] == null, "mcp: after a disconnect, Builders waits while a dialog is open")
	_close_dialogs(app)
	await _settle(r)
	check(r[0] == true, "mcp: and closes once it's closed")
	view._exporting = true
	r = _waiting(app)
	for i in 20:
		await process_frame
	check(r[0] == null, "mcp: a running render is waited for, never cancelled")
	view._exporting = false
	await _settle(r)
	check(r[0] == true, "mcp: and closing follows once it finishes")
	view._begin_job("Test render")
	var job: BakeJob = view._job
	view.request_leave(func(): pass)
	r = _waiting(app)
	for i in 20:
		await process_frame
	check(r[0] == null and view._leave_dialog != null, "mcp: the person's own leave question is waited for")
	view._leave_dialog.get_cancel_button().pressed.emit()
	await _settle(r)
	check(r[0] == false and view._exporting and is_instance_valid(job) and not job._cancelled and view._leave_dialog == null, "mcp: Keep rendering ends automatic closing and the render carries on")
	view._end_job()
	view.stayed_open = false
	view._show_save_error(func(): pass)
	r = _waiting(app)
	for i in 20:
		await process_frame
	check(r[0] == null, "mcp: the save-error question is waited for")
	view._leave_dialog.get_cancel_button().pressed.emit()
	await _settle(r)
	for i in 10:
		await process_frame
	check(r[0] == false and view._leave_dialog == null and app.find_children("*", "ConfirmationDialog", true, false).is_empty(), "mcp: Keep editing ends automatic closing and the prompt doesn't return")
	r = _waiting(app)
	await _settle(r)
	check(r[0] == false, "mcp: once the person has chosen to stay, a later disconnect doesn't close Builders")
	view.stayed_open = false

func _send_tool(server: McpServer, lines: Array, id: int, name: String, args: Dictionary) -> void:
	lines.clear()
	server.receive(JSON.stringify({"jsonrpc": "2.0", "id": id, "method": "tools/call", "params": {"name": name, "arguments": args}}))

func _reply_to(lines: Array, id: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + REPLY_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		for line in lines:
			var parsed = JSON.parse_string(line)
			if parsed is Dictionary and _same_id(parsed.get("id"), id):
				return parsed.get("result", {})
		await process_frame
	return {}

func _has_stone_at(doc: WorldDoc, x: float) -> bool:
	return doc.data.things.any(func(t): return t.kind == "stone" and is_equal_approx(float(t.x), x))

func _mcp_races(server: McpServer, lines: Array, app: Control, world: String, library: String) -> void:
	var target := library.path_join("race-target")
	WorldDoc.create("guild", "Race target", 3).save(target)
	var id := 700
	var view: Control = app.agent_editor()
	var doc: WorldDoc = view.doc
	_send_tool(server, lines, id, "open_world", {"world": target})
	view.history.place("stone", 190.0, -60.0, 0.0, 1.0)
	var edited := await _reply_to(lines, id)
	check(edited.get("isError") == true and app.agent_editor() == view and view.path == world and _has_stone_at(doc, 190.0) and view.history.undo_label() == "Place stone", "mcp: an edit made while a world loads keeps the editor, the edit and its undo step")
	_round_trip(doc, "an edit made during a load")
	view.history.undo()
	view._save_now()

	var counted := History.new(WorldDoc.create("guild", "Revisions", 1))
	var seen := [counted.revision]
	counted.place("stone", 1.0, 1.0, 0.0, 1.0)
	seen.append(counted.revision)
	var applied := counted.doc.add_thing("stone", 5.0, 5.0, 0.0, 1.0)
	counted.things_edit("Already applied", [applied], [], true)
	seen.append(counted.revision)
	counted.set_value("Season", counted.doc.data, "season", "winter")
	seen.append(counted.revision)
	var version_before_undo := counted._undo.get_version()
	counted.undo()
	seen.append(counted.revision)
	counted.place("stone", 9.0, 9.0, 0.0, 1.0)
	seen.append(counted.revision)
	var repeated := counted._undo.get_version() == version_before_undo
	counted.undo()
	seen.append(counted.revision)
	counted.redo()
	seen.append(counted.revision)
	var rising := true
	for i in range(1, seen.size()):
		rising = rising and seen[i] > seen[i - 1]
	check(repeated and rising, "mcp: the revision rises on every edit, undo and redo, even where UndoRedo's version repeats")
	counted.dispose()

	view.history.place("stone", 194.0, -60.0, 0.0, 1.0)
	var version_at_start: int = view.history._undo.get_version()
	id += 1
	_send_tool(server, lines, id, "open_world", {"world": target})
	view.history.undo()
	view.history.place("stone", 196.0, -60.0, 0.0, 1.0)
	var same_version: bool = view.history._undo.get_version() == version_at_start
	var reworked := await _reply_to(lines, id)
	check(same_version and reworked.get("isError") == true and app.agent_editor() == view and view.path == world, "mcp: an undo then a different edit during a load refuses the switch, though UndoRedo's version is back where it started")
	check(_has_stone_at(doc, 196.0) and not _has_stone_at(doc, 194.0) and view.history.undo_label() == "Place stone" and view.history.can_redo() == false, "mcp: and the editor keeps the new edit and its undo history")
	check(view._save_now() and _has_stone_at(WorldDoc.open(world), 196.0) and not _has_stone_at(WorldDoc.open(world), 194.0), "mcp: and the saved world matches it")
	view.history.undo()
	view._save_now()

	id += 1
	_send_tool(server, lines, id, "open_world", {"world": target})
	app._clear()
	app._edit(WorldDoc.open(target), target)
	var person: Control = app.agent_editor()
	person.history.place("stone", 192.0, -60.0, 0.0, 1.0)
	var navigated := await _reply_to(lines, id)
	check(navigated.get("isError") == true and app.agent_editor() == person and person.path == target and _has_stone_at(person.doc, 192.0) and person.history.undo_label() == "Place stone", "mcp: when the person opens the target during the load, their editor, edit and undo step stay")
	check(person._save_now() and _has_stone_at(WorldDoc.open(target), 192.0), "mcp: and their saved world keeps the edit")

	var gone := library.path_join("race-gone")
	WorldDoc.create("guild", "Race gone", 4).save(gone)
	id += 1
	_send_tool(server, lines, id, "open_world", {"world": gone})
	WorldDoc.remove_folder(gone)
	var vanished := await _reply_to(lines, id)
	check(vanished.get("isError") == true and app.agent_editor() == person and not FileAccess.file_exists(gone.path_join("world.json")), "mcp: a target deleted during the load isn't opened or recreated")

	id += 1
	var cancel_id := id
	_send_tool(server, lines, id, "open_world", {"world": world})
	person._begin_job("Person export")
	var theirs: BakeJob = person._job
	server.receive(JSON.stringify({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": cancel_id}}))
	var deadline := Time.get_ticks_msec() + REPLY_WAIT_MS
	while not server._active.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(server._active.is_empty() and not theirs._cancelled and person._exporting and person._job == theirs and app.agent_editor() == person, "mcp: cancelling a world switch leaves the person's export running and switches nothing")
	check(lines.all(func(l): return not _same_id(JSON.parse_string(l).get("id"), cancel_id)), "mcp: and the cancelled request is never answered")
	var stray := BakeJob.new()
	server.tools.cancel({"job": stray})
	server.tools.cancel({})
	check(not theirs._cancelled, "mcp: cancelling another request's job, or none, never stops the person's render")
	stray.free()
	person._end_job()

	var ctx := {}
	server.tools._own_job(ctx, person)
	person._begin_job("Agent render")
	var mine: BakeJob = person._job
	person._end_job()
	person._begin_job("Later render")
	var later: BakeJob = person._job
	check(ctx.get("job") == mine and ctx.get("job") != later, "mcp: a request owns only the job its own call started")
	server.tools.cancel({"job": later})
	check(later._cancelled, "mcp: cancelling its own running job stops it")
	person._end_job()

	id += 1
	var back := await _call_tool(server, lines, id, "open_world", {"world": world})
	check(back.get("isError") == false and app.agent_editor().path == world, "mcp: switching back afterwards works")
	WorldDoc.remove_folder(target)

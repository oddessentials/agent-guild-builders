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
	for t in [["grid", _grid_matches_shipped_plates], ["cover", _tiles_cover_every_view], ["clearance", _clearance], ["document", _document], ["history", _history], ["templates", _templates], ["packages", _packages], ["editor", _editor], ["library", _library], ["land", _land], ["placing", _placing], ["loader", _loader], ["arrange", _arrange], ["place_panel", _place_panel], ["seasons", _seasons], ["review", _review], ["review_slider_edits", _review_slider_edits], ["review_hidden", _review_hidden], ["castle", _castle], ["seating", _seating], ["custom", _custom]]:
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
	var info = JSON.parse_string(FileAccess.get_file_as_string(crate_dir.path_join(CustomItems.ITEM_FILE)))
	info.erase("sha256")
	_store(crate_dir.path_join(CustomItems.ITEM_FILE), JSON.stringify(info).to_utf8_buffer())
	WorldScene.refresh_custom()
	check(WorldScene.load_kit().models.has(crate_kind), "custom: an upload saved before fingerprints still shows")

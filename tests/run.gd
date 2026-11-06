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
	for t in [["grid", _grid_matches_shipped_plates], ["cover", _tiles_cover_every_view], ["clearance", _clearance], ["document", _document], ["history", _history], ["templates", _templates], ["packages", _packages], ["editor", _editor], ["library", _library], ["land", _land], ["placing", _placing], ["loader", _loader]]:
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
		if float(a.data.water_level) > -50.0:
			var wet := 0
			for h in a.heights:
				if h < float(a.data.water_level):
					wet += 1
			check(float(wet) / a.heights.size() < 0.12, key + ": water stays in its lake")
			check(a.ground[(WorldDoc.TERRAIN_RES * WorldDoc.TERRAIN_RES) / 2] != 3, key + ": the plaza isn't shore")
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
	check(view._zone_wanted >= 9.0 * view._next_scale, "editor: tall things show clearance for their actual size")
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

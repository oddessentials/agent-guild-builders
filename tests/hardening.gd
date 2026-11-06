extends SceneTree

const Editor := preload("res://src/ui/editor_view.gd")
var passed := 0
var failed := 0
var work := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	work = OS.get_user_data_dir().path_join("hardening-tests")
	if DirAccess.dir_exists_absolute(work):
		printerr("Test directory already exists: ", work)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(work)
	WorldLibrary.root_override = work.path_join("library")
	var only := OS.get_cmdline_user_args()
	for entry in [["saves", _saves], ["documents", _documents], ["gestures", _gestures], ["loading", _loading], ["rendering", _rendering]]:
		if only.is_empty() or only.has(entry[0]):
			check(await entry[1].call() == true, entry[0] + " completes without a script error")
	WorldLibrary.root_override = ""
	await process_frame
	_remove(work)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _remove(path: String) -> void:
	assert(path == work or path.begins_with(work + "/"))
	for name in WorldDoc._entries(path):
		var child := path.path_join(name)
		if DirAccess.dir_exists_absolute(child):
			_remove(child)
		else:
			DirAccess.remove_absolute(child)
	DirAccess.remove_absolute(path)

func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.close()

func _saves() -> bool:
	var doc := WorldDoc.create("guild", "Original", 7)
	var path := work.path_join("save")
	check(doc.save(path) == OK, "initial save")
	_write(path.path_join("notes.txt"), "notes")
	_write(path.path_join("export.agworld"), "export")
	_write(path.path_join(".hidden"), "hidden")
	_write(path.path_join("references/photo.txt"), "photo")
	doc.data.title = "Updated"
	doc.heights[10] = 2.0
	for i in 2:
		check(doc.save(path) == OK, "repeated save succeeds")
	for entry in [["notes.txt", "notes"], ["export.agworld", "export"], [".hidden", "hidden"], ["references/photo.txt", "photo"]]:
		check(FileAccess.get_file_as_string(path.path_join(entry[0])) == entry[1], "save preserves " + entry[0])
	check(not DirAccess.dir_exists_absolute(path + ".old"), "successful save cleans backup")
	DirAccess.rename_absolute(path, path + ".old")
	_write((path + ".saving").path_join("world.json"), "partial")
	var restored := WorldDoc.open(path)
	check(restored != null and restored.data.title == "Updated" and restored.heights[10] == 2.0, "interrupted swap restores a complete document")
	check(FileAccess.get_file_as_string(path.path_join("notes.txt")) == "notes", "rollback restores unrelated files")
	check(doc.save(path) == OK, "partial stage can be replaced")
	DirAccess.rename_absolute(path, path + ".old")
	var newer := WorldDoc.create("guild", "Newer", 7)
	var staged := work.path_join("staged")
	newer.save(staged)
	DirAccess.rename_absolute(staged, path)
	DirAccess.rename_absolute((path + ".old").path_join("notes.txt"), path.path_join("notes.txt"))
	restored = WorldDoc.open(path)
	check(restored != null and restored.data.title == "Newer", "interrupted preservation keeps new document")
	check(FileAccess.get_file_as_string(path.path_join("references/photo.txt")) == "photo", "recovery finishes preserving subdirectories")
	check(not DirAccess.dir_exists_absolute(path + ".old"), "recovery cleans only completed backup")
	_write((path + ".saving").path_join("unrelated.txt"), "keep staging")
	check(newer.save(path) != OK, "unknown staging contents block saving")
	check(FileAccess.get_file_as_string((path + ".saving").path_join("unrelated.txt")) == "keep staging", "unknown staging contents survive")
	_remove(path + ".saving")
	DirAccess.rename_absolute(path, path + ".old")
	newer.save(staged)
	DirAccess.rename_absolute(staged, path)
	_write(path.path_join("notes.txt"), "new notes")
	_write(path.path_join("notes.txt.recovered"), "earlier recovery")
	var recovered := WorldDoc.open(path)
	check(recovered != null and recovered.notice.contains("notes.txt.recovered-2"), "conflict opens with recovery location")
	check(FileAccess.get_file_as_string(path.path_join("notes.txt")) == "new notes" and FileAccess.get_file_as_string(path.path_join("notes.txt.recovered-2")) == "notes", "both conflicting files survive")
	check(FileAccess.get_file_as_string(path.path_join("notes.txt.recovered")) == "earlier recovery", "earlier recovery is preserved")
	check(recovered.save(path) == OK, "recovered conflict does not block later saves")
	_write(work.path_join("blocked.saving"), "file")
	check(newer.save(work.path_join("blocked")) != OK, "blocked staging path fails predictably")
	return true

func _documents() -> bool:
	var doc := WorldDoc.create("guild", "Valid", 7)
	doc.add_thing("fern", 40, 40, 0, 1)
	var path := work.path_join("document")
	check(doc.save(path) == OK, "document fixture saves")
	var valid := JSON.parse_string(FileAccess.get_file_as_string(path.path_join("world.json"))) as Dictionary
	var cases: Array[Dictionary] = []
	for key in ["title", "base", "mood", "things", "water_level"]:
		var changed := valid.duplicate(true)
		changed.erase(key)
		cases.append(changed)
	for version in [0, -1, 1.5, 99, "1"]:
		var changed := valid.duplicate(true)
		changed.format = version
		cases.append(changed)
	var broken := valid.duplicate(true)
	broken.mood.light.sun_color = [1, 2]
	cases.append(broken)
	broken = valid.duplicate(true)
	broken.mood.dark.sky = "../../sky"
	cases.append(broken)
	broken = valid.duplicate(true)
	broken.things.append(broken.things[0].duplicate())
	cases.append(broken)
	broken = valid.duplicate(true)
	broken.things[0].scale = 0
	cases.append(broken)
	for i in cases.size():
		_write(path.path_join("world.json"), JSON.stringify(cases[i]))
		check(WorldDoc.open(path) == null, "invalid document %d is refused" % i)
	valid.water_level = 4.0
	valid.next_id = 1
	_write(path.path_join("world.json"), JSON.stringify(valid))
	var loaded := WorldDoc.open(path)
	check(loaded != null and loaded.water_adjusted and loaded.data.water_level == WorldDoc.MAX_WATER_LEVEL, "unsafe water is normalized with notice")
	check(loaded.add_thing("fern", 50, 50, 0, 1).id == 2, "loaded IDs stay unique")
	check(loaded.save(path) == OK and not WorldDoc.open(path).water_adjusted, "corrected water survives saving")
	doc.heights[5] = NAN
	doc.save(path)
	check(WorldDoc.open(path) == null, "non-finite terrain is refused")
	doc.heights[5] = 0
	doc.ground[5] = 4
	doc.save(path)
	check(WorldDoc.open(path) == null, "unknown ground is refused")
	return true

func _fixture_kit() -> void:
	var dir := work.path_join("kit")
	WorldScene._kits = dir
	WorldScene._halls.clear()
	WorldScene.kit = {"models": {"fern": {"label": "Fern", "height": 0.5, "spacing": 2.0, "group": "plants"}}, "skies": {"day": {"label": "Day", "strength": 0.9}, "dusk": {"label": "Dusk", "strength": 0.5}}}
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(img)
	WorldScene._textures.clear()
	for kind in WorldScene.GROUND_ORDER + ["cobble"]:
		for suffix in ["_diff", "_nor_gl", "_rough"]:
			WorldScene._textures[kind + suffix] = texture
	WorldScene._skies = {"day": texture, "dusk": texture}
	WorldScene._meshes = {"fern": BoxMesh.new()}
	DirAccess.make_dir_recursive_absolute(dir.path_join("halls"))
	var scene := Node3D.new()
	scene.name = "Halls"
	for id in Yard.data().halls:
		var hall := Node3D.new()
		hall.name = "hall_" + id
		scene.add_child(hall)
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = BoxMesh.new()
		hall.add_child(mesh)
	var writer := GLTFDocument.new()
	var state := GLTFState.new()
	check(writer.append_from_scene(scene, state) == OK, "fixture halls convert")
	for base in WorldDoc.BASES:
		check(writer.write_to_filesystem(state, dir.path_join("halls/%s.glb" % base)) == OK, "fixture halls written for " + base)
	scene.free()

func _view() -> Control:
	var view := Editor.new()
	root.size = Vector2i(1120, 640)
	root.add_child(view)
	view.size = Vector2(root.size)
	view.open(WorldDoc.create("guild", "Test", 7), "")
	view.set_process(false)
	return view

func _slider(view: Control) -> HSlider:
	for child in view._options.get_children():
		if child is HSlider:
			return child
	return null

func _mouse(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	return event

func _gestures() -> bool:
	_fixture_kit()
	var view := _view()
	await process_frame
	var doc: WorldDoc = view.doc
	var spot: Vector2 = view._camera.unproject_position(Vector3(40, 0, 40))
	view._select_tool(view.Tool.GROUND)
	view.ground_kind = 0
	view._on_stage_input(_mouse(spot, true))
	view._on_stage_input(_mouse(spot, false))
	check(not view.history.can_undo(), "painting unchanged ground adds no undo step")
	view._select_tool(view.Tool.LAND)
	view.land_mode = "smooth"
	view._on_stage_input(_mouse(spot, true))
	view._on_stage_input(_mouse(spot, false))
	check(not view.history.can_undo(), "smoothing flat land adds no undo step")
	view.land_mode = "raise"
	var initial := doc.heights.duplicate()
	view._on_stage_input(_mouse(spot, true))
	view._select_tool(view.Tool.LOOK)
	view._on_stage_input(_mouse(spot, false))
	check(not view._painting and view._stroke.is_empty() and view.history.can_undo(), "tool switch completes stroke")
	check(doc.heights != initial, "stroke changes terrain")
	view._undo()
	check(doc.heights == initial, "one undo restores interrupted stroke exactly")
	view._select_tool(view.Tool.LAND)
	view._on_stage_input(_mouse(spot, true))
	view._input(_mouse(Vector2(-100, -100), false))
	check(not view._painting and view._stroke.is_empty(), "release outside canvas completes stroke")
	view._undo()
	view._on_stage_input(_mouse(spot, true))
	view._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not view._painting and view._stroke.is_empty(), "focus loss completes stroke")
	view._undo()
	view._select_tool(view.Tool.MOOD)
	var slider := _slider(view)
	var original: float = doc.data.mood.light.sun_energy
	slider.value = original + 0.2
	view._select_tool(view.Tool.LOOK)
	check(view._dirty_at >= 0 and view.history.undo_label() == "Sun strength", "immediate tool change commits keyboard slider")
	view._undo()
	check(is_equal_approx(doc.data.mood.light.sun_energy, original), "slider undo restores original value")
	view._select_tool(view.Tool.MOOD)
	slider = _slider(view)
	slider.drag_started.emit()
	slider.value = original + 0.1
	slider.value = original + 0.3
	view._set_time("dark")
	view._undo()
	check(is_equal_approx(doc.data.mood.light.sun_energy, original) and doc.data.mood.dark.sun_energy == 2.4, "day switch commits only the edited mood")
	view._set_time("light")
	slider = _slider(view)
	slider.value = original + 0.4
	view._undo()
	check(is_equal_approx(doc.data.mood.light.sun_energy, original), "undo flushes pending slider first")
	view._redo()
	check(is_equal_approx(doc.data.mood.light.sun_energy, original + 0.4), "redo replays flushed slider")
	view._title_box.text = "Saved name"
	slider = _slider(view)
	slider.value = original + 0.5
	check(view._save_now(), "save flushes pending title and slider")
	var saved := WorldDoc.open(view.path)
	check(saved != null and saved.data.title == "Saved name" and is_equal_approx(saved.data.mood.light.sun_energy, original + 0.5), "saved document matches visible edits")
	slider = _slider(view)
	slider.value = original + 0.6
	view._title_box.text = "Another name"
	view._commit_title()
	view._undo()
	check(doc.data.title == "Saved name" and is_equal_approx(doc.data.mood.light.sun_energy, original + 0.6), "title focus exit finishes pending slider before renaming")
	view._undo()
	check(is_equal_approx(doc.data.mood.light.sun_energy, original + 0.5), "slider committed on title exit remains separately undoable")
	view._title_box.grab_focus()
	check(view._title_box.has_focus(), "title fixture has focus")
	var undo_before_title: String = view.history.undo_label()
	view._title_box.text = "My "
	view._title_box.caret_column = 3
	view._title_box.select(0, 2)
	view._stage.mouse_exited.emit()
	check(view._save_now(false), "autosave saves committed edits while typing")
	check(view._title_box.text == "My " and view._title_box.caret_column == 3 and view._title_box.get_selected_text() == "My", "autosave and pointer exit preserve focused title text, caret and selection")
	check(doc.data.title == "Saved name" and view.history.undo_label() == undo_before_title, "focused title is not prematurely committed")
	check(view._save_label.text == "Unsaved title", "autosave does not claim pending title is saved")
	view._title_box.text_submitted.emit(view._title_box.text)
	check(doc.data.title == "My" and view.history.undo_label() == "Rename", "Enter commits trimmed title")
	view._undo()
	check(doc.data.title == "Saved name", "one undo restores title before typing")
	view._select_tool(view.Tool.WATER)
	slider = _slider(view)
	check(slider.max_value == WorldDoc.MAX_WATER_LEVEL, "water slider cannot flood protected ground")
	for child in view._options.get_children():
		if child is CheckBox:
			child.button_pressed = true
	check(is_equal_approx(doc.data.water_level, -0.6), "enabling water starts at a shallow safe level")
	view._undo()
	check(doc.data.water_level == -100.0, "water toggle is one undoable change")
	doc.data.water_level = 4.0
	view._scene.refresh_water()
	check(is_equal_approx(view._scene._water.position.y, WorldDoc.MAX_WATER_LEVEL), "rendering enforces safe water independently")
	var target := work.path_join("blocked-leave")
	_write(target + ".saving", "block")
	view.path = target
	var left := {"count": 0}
	var leave := func(): left.count += 1
	view.request_leave(leave)
	check(left.count == 0 and view._leave_dialog != null and view._save_label.text == "Couldn't save", "failed save keeps document open")
	var dialog: ConfirmationDialog = view._leave_dialog
	view.request_leave(leave)
	check(view._leave_dialog == dialog, "repeated close uses one dialog")
	dialog.canceled.emit()
	check(left.count == 0 and view._leave_dialog == null, "keep editing retains changes")
	var failure: String = view._save_failure
	view._title_box.text_changed.emit("A new title")
	check(view._save_label.text == "Couldn't save" and view._save_label.tooltip_text.contains(failure), "typing preserves save failure and explanation")
	view._commit_title()
	check(view._save_label.text == "Couldn't save", "unchanged title focus exit preserves save failure")
	view._title_box.text = "Changed after failure"
	view._commit_title()
	check(view._save_label.text == "Couldn't save" and view._save_failure == failure, "committed title edit preserves failed save state")
	view.request_leave(leave)
	view._leave_dialog.custom_action.emit("discard")
	check(left.count == 1, "discard requires explicit action")
	view.request_leave(leave)
	DirAccess.remove_absolute(target + ".saving")
	view._leave_dialog.confirmed.emit()
	check(left.count == 2 and WorldDoc.open(target) != null, "retry leaves only after successful save")
	check(view._status.text == "Saved.", "successful retry clears the previous failure message")
	check(view._save_failure == "" and view._save_label.text == "Saved" and not view._save_label.tooltip_text.contains("Trying"), "successful retry clears persistent error state and tooltip")
	view.free()
	return true

func _loading() -> bool:
	_fixture_kit()
	for base in WorldDoc.BASES:
		for i in 2:
			var halls := WorldScene.halls_scene(base)
			check(halls != null and halls.find_children("*", "MeshInstance3D", true, false).size() == Yard.data().halls.size(), "visible halls on repeated open of " + base)
			if halls:
				halls.free()
	var loader := WorldLoader.new()
	root.add_child(loader)
	var replies := []
	loader.done.connect(func(doc): replies.append(doc))
	var broken := WorldDoc.create("guild", "Broken", 7)
	broken.data.erase("mood")
	loader.start(func(): return broken)
	await loader.done
	check(replies.size() == 1 and replies[0] == null and loader.error != "" and loader._thread == null, "malformed project terminates loading with error")
	var valid := WorldDoc.create("guild", "Valid", 7)
	var progress := []
	loader.step.connect(func(_label, fraction): progress.append(fraction))
	loader.start(func(): return valid)
	loader._tell("Stale progress", 0.9, loader._generation - 1)
	check(progress.is_empty(), "previous load cannot update current progress")
	await loader.done
	check(replies.size() == 2 and replies[1] == valid and loader.error == "", "valid project loads after failure")
	WorldScene._skies.erase("day")
	loader.start(func(): return valid)
	await loader.done
	check(replies.size() == 3 and replies[2] == null and loader.error.contains("sky"), "missing sky reports failure")
	WorldScene._skies.day = WorldScene._skies.dusk
	loader.start(func(): return valid)
	await loader.done
	check(replies.size() == 4 and replies[3] == valid, "repaired assets can be retried")
	await process_frame
	loader.free()
	loader = WorldLoader.new()
	root.add_child(loader)
	loader.start(func(): return null)
	loader.free()
	check(true, "loader can close while worker finishes")
	return true

func _rendering() -> bool:
	_fixture_kit()
	var view := _view()
	await process_frame
	view._overlay = PanelContainer.new()
	view._stage_holder.add_child(view._overlay)
	view._set_time("dark")
	check(view._overlay == null, "day change dismisses stale preview")
	view._select_tool(view.Tool.MOOD)
	view._overlay = PanelContainer.new()
	view._stage_holder.add_child(view._overlay)
	_slider(view).value = 3.0
	check(view._overlay == null, "live slider dismisses stale preview immediately")
	view._begin_job("Test render")
	check(view._exporting and view._preview_button.disabled and view._title_box.editable == false, "render pauses editing")
	var job: BakeJob = view._job
	job.cancel()
	var preview: Image = await job.preview(view.doc, "dark")
	check(preview == null, "cancel before rendering completes without GPU work")
	view._end_job()
	view._end_job()
	check(not view._exporting and not view._preview_button.disabled and view._title_box.editable and not view._progress.visible, "render cleanup is repeatable and restores controls")
	job = BakeJob.new()
	root.add_child(job)
	preview = await job.preview(view.doc, "dark")
	check(preview == null and job.error.contains("sky"), "missing preview sky returns an actionable error")
	job.free()
	view.free()
	return true

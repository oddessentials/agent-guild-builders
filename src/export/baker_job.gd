class_name BakeJob
extends Node
## One whole export: a document in, a .agworld file out. Both the app and the
## command line use this.

signal progress(done: int, total: int)
signal finished(error: String)

const CANCELLED := "cancelled"
const NEEDS_WINDOW := "Rendering needs a window. Start Builders without --headless to preview or export."
var _baker: PlateBaker
var _cancelled := false
var error := ""
var recovery_path := ""
var notice := ""

func cancel() -> void:
	_cancelled = true
	if is_instance_valid(_baker):
		_baker.cancelled = true

static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"

static func total_chunks() -> int:
	var count := 0
	for layer in Yard.layers():
		for tile in Yard.tiles(layer):
			count += PlateBaker.chunks_in(tile)
	return count

func run(doc: WorldDoc, out_path: String, quality := "final", replace := true) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _cancelled:
		finished.emit(CANCELLED)
		return
	WorldScene.load_kit()
	var checked := Clearance.check_world(doc)
	if not checked.get("valid", false):
		finished.emit(checked.get("problem", "The project couldn't be checked for export."))
		return
	var report := {}
	if WorldPackage.prepare_destination(out_path, report, replace) != OK:
		finished.emit(report.error)
		return
	if not can_render():
		finished.emit(NEEDS_WINDOW)
		return
	clean_leftovers()
	var plates := OS.get_user_data_dir().path_join("bakes").path_join("%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	var made := DirAccess.make_dir_recursive_absolute(plates)
	if made != OK:
		finished.emit("Couldn't create the render folder: %s (%s)." % [plates, error_string(made)])
		return
	var scene := WorldScene.new()
	scene.build(doc)
	var baker := PlateBaker.new()
	add_child(baker)
	_baker = baker
	baker.progress.connect(func(d, t): progress.emit(d, t))
	baker.setup(scene, scene.lamps, quality)
	baker.set_progress_total(total_chunks() * Yard.THEMES.size())
	var moods := {}
	var skies := {}
	for theme in Yard.THEMES:
		var m: Dictionary = doc.data.mood[theme]
		var path := WorldScene.kit_file("skies/%s.hdr" % m.sky)
		var sky := BakeSky.from_file(path, float(m.strength))
		if sky == null:
			finished.emit("A sky couldn't be read: " + str(m.sky))
			baker.queue_free()
			_clean(plates)
			return
		skies[theme] = sky
		var c: Array = m.sun_color
		moods[theme] = {"sky": sky, "energy": float(m.sun_energy), "color": Color(c[0], c[1], c[2]), "angle": deg_to_rad(1.4 if theme == "light" else 2.5)}
	for theme in Yard.THEMES:
		scene.refresh_things(theme)
		var single := {theme: moods[theme]}
		var err: Error = await baker.bake_theme(theme, single[theme], plates)
		if err == ERR_SKIP:
			_clean(plates)
			baker.queue_free()
			finished.emit(CANCELLED)
			return
		if err != OK:
			_clean(plates)
			baker.queue_free()
			finished.emit("A picture couldn't be saved (%s)." % error_string(err))
			return
	var preview := Image.load_from_file(plates.path_join("light-base-0-0.webp"))
	if preview:
		preview.resize(960, int(960.0 * preview.get_height() / preview.get_width()), Image.INTERPOLATE_LANCZOS)
	recovery_path = plates.path_join("world.agworld")
	var written := WorldPackage.write(doc, plates, skies, preview, recovery_path, report)
	baker.queue_free()
	if written != OK:
		recovery_path = ""
		finished.emit(report.get("error", "The world file couldn't be written (%s)." % error_string(written)) + " Rendered pictures have been kept at " + plates)
		return
	if save_rendered(recovery_path, out_path, report, replace) != OK:
		finished.emit(report.get("error", "The world file couldn't be written.") + " The finished world is kept at " + recovery_path)
		return
	recovery_path = ""
	notice = report.get("notice", "")
	finished.emit("")

static func save_rendered(source: String, out_path: String, report := {}, replace := true) -> Error:
	var source_folder := ProjectSettings.globalize_path(source).replace("\\", "/").get_base_dir().simplify_path().to_lower()
	var destination := ProjectSettings.globalize_path(out_path).replace("\\", "/").simplify_path().to_lower()
	if destination.begins_with(source_folder + "/"):
		report.error = "Choose a destination outside the recovered export folder."
		return ERR_INVALID_PARAMETER
	var written := WorldPackage.publish(source, out_path, report, replace)
	if written == OK:
		var folder := source.get_base_dir()
		var root := OS.get_user_data_dir().path_join("bakes")
		if folder.get_base_dir() == root and source.get_file() == "world.agworld":
			_clean(folder)
	return written

func preview(doc: WorldDoc, theme: String) -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	if _cancelled:
		return null
	error = ""
	var m: Dictionary = doc.data.mood[theme]
	var sky := BakeSky.from_file(WorldScene.kit_file("skies/%s.hdr" % m.sky), float(m.strength))
	if sky == null:
		error = "The %s sky couldn't be read. Extract the complete app ZIP, including its kits folder." % str(m.sky)
		return null
	if not can_render():
		error = NEEDS_WINDOW
		return null
	WorldScene.load_kit()
	var scene := WorldScene.new()
	scene.build(doc)
	var baker := PlateBaker.new()
	add_child(baker)
	_baker = baker
	baker.setup(scene, scene.lamps, "draft")
	baker.progress.connect(func(d, t): progress.emit(d, t))
	var c: Array = m.sun_color
	scene.refresh_things(theme)
	baker.prepare_theme(theme, sky, float(m.sun_energy), Color(c[0], c[1], c[2]), deg_to_rad(1.4 if theme == "light" else 2.5))
	var tile: Dictionary = Yard.tiles(Yard.layers()[2])[0]
	baker.set_progress_total(PlateBaker.chunks_in(tile))
	var img: Image = await baker.bake_tile(tile)
	var done := not baker.cancelled
	baker.queue_free()
	_baker = null
	return img if done else null

static func clean_leftovers() -> void:
	var root := OS.get_user_data_dir().path_join("bakes")
	if not DirAccess.dir_exists_absolute(root):
		return
	for dir_name in DirAccess.get_directories_at(root):
		var folder := root.path_join(dir_name)
		if not _completed(folder):
			_clean(folder)

static func has_recovered_export() -> bool:
	var root := OS.get_user_data_dir().path_join("bakes")
	if not DirAccess.dir_exists_absolute(root):
		return false
	for dir_name in DirAccess.get_directories_at(root):
		if _completed(root.path_join(dir_name)):
			return true
	return false

static func _completed(folder: String) -> bool:
	if FileAccess.file_exists(folder.path_join("world.agworld")):
		return true
	for name in WorldPackage.plate_names():
		if not FileAccess.file_exists(folder.path_join(name.get_file())):
			return false
	return true

static func _clean(dir_path: String) -> void:
	for name in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(name))
	DirAccess.remove_absolute(dir_path)

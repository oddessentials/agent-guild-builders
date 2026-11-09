extends SceneTree

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
		printerr("FAIL ", label)

func _run() -> void:
	work = OS.get_user_data_dir().path_join("package-hardening")
	if DirAccess.dir_exists_absolute(work):
		printerr("Test directory already exists: ", work)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(work)
	check(_types(), "type checks complete")
	check(_replacement(), "replacement checks complete")
	check(await _recovery(), "export recovery checks complete")
	check(_no_replace(), "no-replace checks complete")
	for name in DirAccess.get_files_at(work):
		DirAccess.remove_absolute(work.path_join(name))
	DirAccess.remove_absolute(work)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _fixture() -> Dictionary:
	var files := {}
	for name in WorldPackage.plate_names():
		files[name] = Image.create(16, 16, false, Image.FORMAT_RGB8).save_webp_to_buffer(true, 0.5)
	for time in Yard.THEMES:
		files["web/sky-%s.hdr" % time] = WorldPackage.hdr_bytes(Image.create(2, 2, false, Image.FORMAT_RGBF))
	var listing := {}
	for name in files:
		listing[name] = {"size": files[name].size(), "sha256": WorldPackage.sha256(files[name])}
	return {"files": files, "meta": {"format": 1, "kind": WorldPackage.KIND, "title": "Test", "base": "guild", "environment": WorldPackage.environment_abi(), "generator": 1, "files": listing}}

func _no_replace() -> bool:
	var fixture := _fixture()
	var bytes := _bytes(fixture.meta, fixture.files)
	var other := "SOMEONE ELSE".to_utf8_buffer()
	var kept := work.path_join("kept.agworld")
	_store(kept, other)
	var report := {}
	check(WorldPackage._write_package(bytes, kept, report, false) == ERR_ALREADY_EXISTS and report.error.contains("wasn't replaced"), "replace false refuses an existing file")
	check(FileAccess.get_file_as_bytes(kept) == other and not FileAccess.file_exists(kept + ".tmp") and not FileAccess.file_exists(kept + ".previous"), "the existing file is untouched and nothing is left behind")
	var raced := work.path_join("raced.agworld")
	check(WorldPackage.prepare_destination(raced, {}, false) == OK, "the destination is free before rendering")
	_store(raced + ".tmp", bytes)
	_store(raced, other)
	report = {}
	check(WorldPackage._publish_new(raced + ".tmp", raced, report) == ERR_ALREADY_EXISTS and report.error.contains("wasn't replaced"), "a file that appears before publishing is never replaced")
	check(FileAccess.get_file_as_bytes(raced) == other and not FileAccess.file_exists(raced + ".tmp"), "the file that appeared is untouched")
	var fresh := work.path_join("fresh.agworld")
	check(WorldPackage._write_package(bytes, fresh, {}, false) == OK and FileAccess.get_file_as_bytes(fresh) == bytes and not FileAccess.file_exists(fresh + ".tmp"), "replace false publishes to a free name")
	var source_folder := work.path_join("finished")
	DirAccess.make_dir_recursive_absolute(source_folder)
	var source := source_folder.path_join("world.agworld")
	_store(source, bytes)
	report = {}
	check(BakeJob.save_rendered(source, kept, report, false) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(kept) == other, "saving a finished export never replaces when told not to")
	check(FileAccess.get_file_as_bytes(source) == bytes, "the finished export is kept")
	check(WorldPackage._write_package(bytes, kept, {}) == OK and FileAccess.get_file_as_bytes(kept) == bytes, "existing callers still replace")
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(source_folder)
	var odd_folder := work.path_join("Art%USERNAME% [x] it's $y & z")
	DirAccess.make_dir_recursive_absolute(odd_folder)
	var odd := odd_folder.path_join("Yard.agworld")
	check(WorldPackage._write_package(bytes, odd, {}, false) == OK and FileAccess.get_file_as_bytes(odd) == bytes and not FileAccess.file_exists(odd + ".tmp"), "a folder name a shell would expand is published literally")
	var odd_taken := odd_folder.path_join("Taken.agworld")
	_store(odd_taken, other)
	_store(odd_taken + ".tmp", bytes)
	report = {}
	check(WorldPackage._publish_new(odd_taken + ".tmp", odd_taken, report) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(odd_taken) == other and not FileAccess.file_exists(odd_taken + ".tmp"), "there, a taken name is refused and left untouched")
	for name in DirAccess.get_files_at(odd_folder):
		DirAccess.remove_absolute(odd_folder.path_join(name))
	DirAccess.remove_absolute(odd_folder)
	var long_root := work.path_join("long")
	var long_folder := long_root
	while long_folder.length() < 230:
		long_folder = long_folder.path_join("a-folder-name-of-forty-characters-here")
	var long_file := long_folder.path_join("Y".repeat(278 - long_folder.length() - 1 - WorldPackage.EXT.length()) + WorldPackage.EXT)
	DirAccess.make_dir_recursive_absolute(long_folder)
	check(ProjectSettings.globalize_path(long_file).length() == 278 and WorldPackage._write_package(bytes, long_file, {}, false) == OK and FileAccess.get_file_as_bytes(long_file) == bytes and not FileAccess.file_exists(long_file + ".tmp"), "a 278-character destination is published")
	_store(long_file + ".tmp", other)
	report = {}
	check(WorldPackage._publish_new(long_file + ".tmp", long_file, report) == ERR_ALREADY_EXISTS and FileAccess.get_file_as_bytes(long_file) == bytes and not FileAccess.file_exists(long_file + ".tmp"), "at that length, an existing file is still never replaced")
	DirAccess.remove_absolute(long_file)
	while long_folder.length() >= long_root.length():
		DirAccess.remove_absolute(long_folder)
		long_folder = long_folder.get_base_dir()
	return true

func _bytes(meta: Variant, files: Dictionary) -> PackedByteArray:
	var entries := [[WorldPackage.MANIFEST, JSON.stringify(meta).to_utf8_buffer()]]
	for name in files:
		entries.append([name, files[name]])
	return WorldPackage.tar_gz(entries)

func _store(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null)
	f.store_buffer(bytes)
	f.close()

func _refused(meta: Variant, files: Dictionary, label: String) -> void:
	var path := work.path_join("bad.agworld")
	_store(path, _bytes(meta, files))
	var result := WorldPackage.check(path)
	check(not WorldPackage.accepted(result) and not WorldPackage.explanation(result).is_empty(), label)

func _types() -> bool:
	var fixture := _fixture()
	var path := work.path_join("good.agworld")
	_store(path, _bytes(fixture.meta, fixture.files))
	check(WorldPackage.accepted(WorldPackage.check(path)), "valid package accepted")
	for result in [null, [], {}, {"valid": "true"}, {"valid": false}, {"valid": true}, {"valid": true, "problems": ["incomplete"]}]:
		check(not WorldPackage.accepted(result), "incomplete validation refused")
	for value in [null, [], true, 5, "world"]:
		_refused(value, fixture.files, "invalid manifest type")
	for key in fixture.meta:
		for value in [null, [], {}, true]:
			var meta: Dictionary = fixture.meta.duplicate(true)
			meta[key] = value
			_refused(meta, fixture.files, "invalid type for " + key)
		if key != "generator":
			var missing: Dictionary = fixture.meta.duplicate(true)
			missing.erase(key)
			_refused(missing, fixture.files, "missing " + key)
	for entry in [["kind", 5], ["environment", 7], ["title", 7], ["base", 7], ["format", 1.5], ["format", "1"], ["generator", 1.5]]:
		var meta: Dictionary = fixture.meta.duplicate(true)
		meta[entry[0]] = entry[1]
		_refused(meta, fixture.files, "invalid value for " + entry[0])
	var name: String = fixture.files.keys()[0]
	for value in [null, [], true, 5, "file"]:
		var meta: Dictionary = fixture.meta.duplicate(true)
		meta.files[name] = value
		_refused(meta, fixture.files, "invalid file entry")
	for key in ["size", "sha256"]:
		for value in [null, [], {}, true, "1", -1, 1.5, 9007199254740992.0]:
			var meta: Dictionary = fixture.meta.duplicate(true)
			meta.files[name][key] = value
			_refused(meta, fixture.files, "invalid file " + key)
			_refused(meta, {}, "manifest-only invalid file " + key)
	for value in [null, [], true, 7, "lights", {}, {"light": 7}, {"light": {"sun": [], "hemi": 1}, "dark": {"sun": 1, "hemi": 1}}]:
		var meta: Dictionary = fixture.meta.duplicate(true)
		meta.lights = value
		_refused(meta, fixture.files, "invalid lights")
	var output := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--check=" + work.path_join("bad.agworld")], output, true)
	check(code != 0 and not "\n".join(output).contains("OK:"), "CLI refuses malformed package")
	check(not "\n".join(output).contains("SCRIPT ERROR"), "CLI handles malformed package without script errors")
	var large := work.path_join("oversize.agworld")
	var file := FileAccess.open(large, FileAccess.WRITE)
	file.seek(WorldPackage.MAX_PACKAGE)
	file.store_8(0)
	file.close()
	check(not WorldPackage.accepted(WorldPackage.check(large)), "oversized file refused before reading its contents")
	return true

func _replacement() -> bool:
	var fixture := _fixture()
	var original := _bytes(fixture.meta, fixture.files)
	fixture.meta.title = "Replacement"
	var replacement := _bytes(fixture.meta, fixture.files)
	var path := work.path_join("export.agworld")
	_store(path, original)
	check(WorldPackage._write_package("broken".to_utf8_buffer(), path) == ERR_FILE_CORRUPT, "invalid temporary export refused")
	check(FileAccess.get_file_as_bytes(path) == original, "invalid export preserves previous bytes")
	_store(path + ".tmp", "unrelated".to_utf8_buffer())
	check(WorldPackage._write_package(replacement, path) == OK, "abandoned staging file does not block export")
	check(FileAccess.get_file_as_bytes(path) == replacement and FileAccess.get_file_as_string(path + ".tmp.recovered") == "unrelated", "abandoned staging contents preserved separately")
	check(WorldPackage._write_package(replacement, path) == OK, "valid export replaces previous file")
	check(FileAccess.get_file_as_bytes(path) == replacement, "published bytes match validated file")
	DirAccess.rename_absolute(path, path + ".previous")
	check(WorldPackage._write_package(original, path) == OK, "interrupted replacement recovers before writing")
	check(FileAccess.get_file_as_bytes(path) == original, "recovered replacement publishes")
	_store(path + ".previous", replacement)
	check(WorldPackage._write_package(replacement, path) == OK, "leftover previous export does not lock destination")
	check(FileAccess.get_file_as_bytes(path + ".recovered") == replacement, "leftover previous export remains recoverable")
	var blocked := work.path_join("directory.agworld")
	DirAccess.make_dir_absolute(blocked)
	check(WorldPackage._write_package(replacement, blocked) != OK and DirAccess.dir_exists_absolute(blocked), "destination directory is never removed")
	DirAccess.remove_absolute(blocked)
	return true

func _recovery() -> bool:
	var fixture := _fixture()
	var bytes := _bytes(fixture.meta, fixture.files)
	var blocked := work.path_join("blocked.agworld")
	DirAccess.make_dir_absolute(blocked)
	var job := BakeJob.new()
	root.add_child(job)
	job.run(WorldDoc.create("guild", "Preflight", 7), blocked, "draft")
	var message: String = await job.finished
	check(message.contains(blocked) and job._baker == null, "invalid destination refused before rendering starts")
	job.queue_free()
	await process_frame
	var folder := OS.get_user_data_dir().path_join("bakes/package-recovery-test")
	check(not DirAccess.dir_exists_absolute(folder), "recovery fixture starts clean")
	DirAccess.make_dir_recursive_absolute(folder)
	for name in WorldPackage.plate_names():
		_store(folder.path_join(name.get_file()), fixture.files[name])
	BakeJob.clean_leftovers()
	check(DirAccess.dir_exists_absolute(folder), "completed plates survive cleanup before packaging")
	var source := folder.path_join("world.agworld")
	_store(source, bytes)
	var report := {}
	check(BakeJob.save_rendered(source, blocked, report) != OK, "late destination failure reported")
	check(report.error.contains(blocked) and FileAccess.get_file_as_bytes(source) == bytes, "late failure preserves finished world and names destination")
	BakeJob.clean_leftovers()
	check(BakeJob.has_recovered_export() and FileAccess.get_file_as_bytes(source) == bytes, "returning home preserves discoverable recovered export")
	check(BakeJob.save_rendered(source, source.to_upper(), {}) != OK, "recovery copy cannot replace itself through a case alias")
	check(BakeJob.save_rendered(source, folder.path_join("another.agworld"), {}) != OK, "retry cannot publish into its cleanup folder")
	var view := preload("res://src/ui/editor_view.gd").new()
	root.add_child(view)
	view.open(WorldDoc.create("guild", "Later edits", 7), "")
	view.set_process(false)
	view._recovery_path = source
	view._save_rendered_button.visible = true
	view._save_rendered_to(blocked)
	check(view._recovery_path == source and view._save_rendered_button.visible, "failed save-only retry remains available")
	var destination := work.path_join("retried.agworld")
	view._save_rendered_to(destination)
	check(view._recovery_path == "" and not view._save_rendered_button.visible and view._result_button.visible, "successful save-only retry exposes the published file")
	check(view._job == null and not view._exporting, "save-only retry never starts another render")
	check(FileAccess.get_file_as_bytes(destination) == bytes and not DirAccess.dir_exists_absolute(folder), "successful retry publishes same bytes and clears only its own recovery folder")
	view.free()
	DirAccess.remove_absolute(blocked)
	return true

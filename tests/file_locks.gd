extends SceneTree

var failed := 0
var work := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL ", label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	work = args[1].replace("\\", "/")
	match args[0]:
		"prepare": check(_prepare(), "prepare completes")
		"locked": check(_locked(), "locked checks complete")
		"released": check(_released(), "retry checks complete")
		_: failed += 1
	print("File lock phase %s: %d failures" % [args[0], failed])
	quit(1 if failed else 0)

func _package(title: String) -> PackedByteArray:
	var files := {}
	for name in WorldPackage.plate_names():
		files[name] = Image.create(16, 16, false, Image.FORMAT_RGB8).save_webp_to_buffer(true)
	for time in Yard.THEMES:
		files["web/sky-%s.hdr" % time] = WorldPackage.hdr_bytes(Image.create(2, 2, false, Image.FORMAT_RGBF))
	var listing := {}
	for name in files:
		listing[name] = {"size": files[name].size(), "sha256": WorldPackage.sha256(files[name])}
	var meta := {"format": 1, "kind": WorldPackage.KIND, "title": title, "base": "guild", "environment": WorldPackage.environment_abi(), "files": listing}
	var entries := [[WorldPackage.MANIFEST, JSON.stringify(meta).to_utf8_buffer()]]
	for name in files:
		entries.append([name, files[name]])
	return WorldPackage.tar_gz(entries)

func _store(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()

func _prepare() -> bool:
	if DirAccess.dir_exists_absolute(work):
		return false
	var doc := WorldDoc.create("guild", "Original", 7)
	check(doc.save(work.path_join("project")) == OK, "save fixture")
	check(doc.save(work.path_join("recover")) == OK, "recovery fixture")
	_store(work.path_join("recover/notes.txt"), "new notes".to_utf8_buffer())
	_store(work.path_join("recover.old/notes.txt"), "old notes".to_utf8_buffer())
	_store(work.path_join("export.agworld"), _package("Original"))
	_store(work.path_join("ready/world.agworld"), _package("Changed"))
	_store(work.path_join("cleanup.agworld.previous"), _package("Original"))
	_store(work.path_join("cleanup.agworld.tmp"), _package("Changed"))
	return true

func _locked() -> bool:
	var path := work.path_join("project")
	var original := FileAccess.get_file_as_bytes(path.path_join("world.json"))
	var doc := WorldDoc.open(path)
	doc.data.title = "Changed"
	var saved := doc.save(path)
	check(saved != OK and doc.save_error.contains(path), "locked project save reports its path")
	check(FileAccess.get_file_as_bytes(path.path_join("world.json")) == original, "locked save preserves original project")
	path = work.path_join("export.agworld")
	check(WorldPackage._write_package(_package("Changed"), path) != OK, "locked export refuses replacement")
	check(FileAccess.get_file_as_bytes(path) == _package("Original"), "locked export preserves original bytes")
	var rendered := work.path_join("ready/world.agworld")
	var publish_report := {}
	check(BakeJob.save_rendered(rendered, path, publish_report) != OK and publish_report.error.contains(path), "locked destination reports failure when saving a completed render")
	check(FileAccess.get_file_as_bytes(rendered) == _package("Changed"), "locked destination preserves the finished render")
	var cleanup := work.path_join("cleanup.agworld")
	var cleanup_report := {}
	check(WorldPackage._publish_staged(cleanup + ".tmp", cleanup, true, cleanup_report) == OK, "backup cleanup failure does not misreport successful publication")
	check(cleanup_report.get("notice", "").contains(cleanup + ".previous"), "backup cleanup notice names preserved backup")
	check(FileAccess.get_file_as_bytes(cleanup) == _package("Changed") and FileAccess.get_file_as_bytes(cleanup + ".previous") == _package("Original"), "cleanup failure preserves published export and previous copy")
	var report := {}
	doc = WorldDoc.open(work.path_join("recover"), report)
	check(doc != null and doc.notice.contains("notes.txt"), "locked recovery opens valid current world with specific notice")
	check(doc.save(work.path_join("recover")) != OK, "locked recovery refuses to discard backup")
	check(FileAccess.get_file_as_string(work.path_join("recover.old/notes.txt")) == "old notes", "locked recovery retains old content")
	return true

func _released() -> bool:
	var path := work.path_join("project")
	var doc := WorldDoc.open(path)
	doc.data.title = "Changed"
	check(doc.save(path) == OK and WorldDoc.open(path).data.title == "Changed", "project save succeeds after lock release")
	path = work.path_join("export.agworld")
	check(BakeJob.save_rendered(work.path_join("ready/world.agworld"), path) == OK, "finished render saves after lock release without rebaking")
	check(FileAccess.get_file_as_bytes(path) == _package("Changed"), "replacement bytes are complete")
	doc = WorldDoc.open(work.path_join("recover"))
	check(doc != null and doc.notice.contains("notes.txt.recovered"), "conflict recovers after lock release")
	check(FileAccess.get_file_as_string(work.path_join("recover/notes.txt.recovered")) == "old notes", "recovered content retained")
	check(doc.save(work.path_join("recover")) == OK, "recovered world remains savable")
	_remove(work)
	return true

func _remove(path: String) -> void:
	assert(path == work or path.begins_with(work + "/"))
	for name in WorldDoc._entries(path):
		var child := path.path_join(name)
		if DirAccess.dir_exists_absolute(child):
			_remove(child)
		else:
			DirAccess.remove_absolute(child)
	DirAccess.remove_absolute(path)

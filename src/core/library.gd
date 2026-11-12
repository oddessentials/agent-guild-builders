class_name WorldLibrary
extends RefCounted
## The worlds saved on this computer.

static var root_override := ""

static func root() -> String:
	return root_override if root_override != "" else OS.get_user_data_dir().path_join("worlds")

## Newest first: {path, title, base, modified, thumb}.
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(root()):
		return out
	for name in DirAccess.get_directories_at(root()):
		if name.ends_with(".saving"):
			continue
		if name.ends_with(".old"):
			name = name.trim_suffix(".old")
			if DirAccess.dir_exists_absolute(root().path_join(name)):
				continue
			WorldDoc._recover(root().path_join(name))
		var path := root().path_join(name)
		var file := path.path_join("world.json")
		if not FileAccess.file_exists(file):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not parsed is Dictionary or not parsed.has("format"):
			continue
		var thumb := path.path_join(WorldDoc.THUMB)
		out.append({"path": path, "title": str(parsed.get("title", name)), "base": str(parsed.get("base", "")),
			"modified": FileAccess.get_modified_time(file), "thumb": thumb if FileAccess.file_exists(thumb) else ""})
	out.sort_custom(func(a, b): return a.modified > b.modified)
	return out

static func _slug(title: String) -> String:
	var name := title.strip_edges().to_lower().validate_filename().replace(" ", "-").trim_suffix(".")
	if name == "":
		return "world"
	if name in ["con", "prn", "aux", "nul"] or (name.length() == 4 and (name.begins_with("com") or name.begins_with("lpt")) and name[3].is_valid_int()):
		return name + "-world"
	return name

## A folder nothing else uses, so one world can never replace another.
static func folder_for(title: String) -> String:
	var slug := _slug(title)
	var candidate := root().path_join(slug)
	var n := 2
	while DirAccess.dir_exists_absolute(candidate) or DirAccess.dir_exists_absolute(candidate + ".old") or DirAccess.dir_exists_absolute(candidate + ".saving"):
		candidate = root().path_join("%s-%d" % [slug, n])
		n += 1
	return candidate

static func unique_title(title: String) -> String:
	var taken := {}
	for w in list():
		taken[w.title.to_lower()] = true
	var whole := _fit(title, WorldDoc.MAX_TITLE)
	var candidate := whole
	var n := 2
	while taken.has(candidate.to_lower()):
		var suffix := " %d" % n
		candidate = _fit(whole, WorldDoc.MAX_TITLE - suffix.length()) + suffix
		n += 1
	return candidate

static func _fit(text: String, units: int) -> String:
	while text.to_utf16_buffer().size() > units * 2:
		text = text.left(-1)
	return text.strip_edges()

static func rename(path: String, title: String) -> Error:
	var doc := WorldDoc.open(path)
	if doc == null:
		return ERR_FILE_CORRUPT
	doc.data.title = title
	return doc.save(path)

static func duplicate_world(path: String) -> String:
	var doc := WorldDoc.open(path)
	if doc == null:
		return ""
	doc.data.title = unique_title("%s copy" % doc.data.title)
	var folder := folder_for(doc.data.title)
	DirAccess.make_dir_recursive_absolute(root())
	if doc.save(folder) != OK:
		return ""
	if FileAccess.file_exists(path.path_join(WorldDoc.THUMB)):
		DirAccess.copy_absolute(path.path_join(WorldDoc.THUMB), folder.path_join(WorldDoc.THUMB))
	return folder

## Goes to the Recycle Bin, or the Trash on a Mac, so a mistake can be undone.
static func delete_world(path: String) -> Error:
	return OS.move_to_trash(path)

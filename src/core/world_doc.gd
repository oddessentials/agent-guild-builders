class_name WorldDoc
extends RefCounted
## A saved project: a folder holding world.json and terrain.bin. Nothing here
## depends on how a world is drawn, so later export targets can read it too.

const FORMAT := 1
const GENERATOR := 1
const SEASONS := ["summer", "autumn", "winter"]
const BASES := ["guild", "orbital", "grove", "professional", "goblinville", "gnomeland"]
const TERRAIN_RES := 257
const TERRAIN_SIZE := 520.0
const MAX_WATER_LEVEL := -0.1
const NO_WATER_BELOW := -50.0
## Each entry takes a document of format N to N+1. Append only.
const MIGRATIONS: Array[Callable] = []
const THUMB := "thumb.webp"
const PROJECT_FILES := ["world.json", "terrain.bin", THUMB]

var data: Dictionary = {}
var heights := PackedFloat32Array()
var ground := PackedByteArray()
var _next_id := 1
var water_adjusted := false
var notice := ""
var save_error := ""

static func create(base: String, title: String, seed_value: int) -> WorldDoc:
	var doc := WorldDoc.new()
	doc.data = {
		"format": FORMAT, "generator": GENERATOR, "seed": seed_value, "base": base, "title": title,
		"mood": {
			"light": {"sky": "day", "strength": 0.9, "sun_energy": 3.3, "sun_color": [1.0, 0.93, 0.82]},
			"dark": {"sky": "dusk", "strength": 0.5, "sun_energy": 2.4, "sun_color": [1.0, 0.56, 0.3]},
		},
		"plaza": {"ground": "cobble"},
		"water_level": -100.0,
		"things": [],
	}
	doc.heights.resize(TERRAIN_RES * TERRAIN_RES)
	doc.ground.resize(TERRAIN_RES * TERRAIN_RES)
	return doc

func season() -> String:
	return str(data.get("season", "summer"))

static func cell_to_world(i: int, j: int) -> Vector2:
	var step := TERRAIN_SIZE / (TERRAIN_RES - 1)
	return Vector2(i * step - TERRAIN_SIZE / 2.0, j * step - TERRAIN_SIZE / 2.0)

func height_at(x: float, z: float) -> float:
	var step := TERRAIN_SIZE / (TERRAIN_RES - 1)
	var fx := clampf((x + TERRAIN_SIZE / 2.0) / step, 0.0, TERRAIN_RES - 1.001)
	var fz := clampf((z + TERRAIN_SIZE / 2.0) / step, 0.0, TERRAIN_RES - 1.001)
	var i := int(fx)
	var j := int(fz)
	var a := heights[j * TERRAIN_RES + i]
	var b := heights[j * TERRAIN_RES + i + 1]
	var c := heights[(j + 1) * TERRAIN_RES + i]
	var d := heights[(j + 1) * TERRAIN_RES + i + 1]
	return lerpf(lerpf(a, b, fx - i), lerpf(c, d, fx - i), fz - j)

func make_thing(kind: String, x: float, z: float, turn: float, scale: float) -> Dictionary:
	var thing := {"id": _next_id, "kind": kind, "x": x, "z": z, "turn": turn, "scale": scale}
	_next_id += 1
	return thing

func add_thing(kind: String, x: float, z: float, turn: float, scale: float) -> Dictionary:
	var thing := make_thing(kind, x, z, turn, scale)
	data.things.append(thing)
	return thing

func remove_thing(id: int) -> void:
	data.things = data.things.filter(func(t): return int(t.id) != id)

func remove_things(things: Array) -> void:
	if things.is_empty():
		return
	var ids := {}
	for t in things:
		ids[int(t.id)] = true
	data.things = data.things.filter(func(t): return not ids.has(int(t.id)))

func save(dir_path: String) -> Error:
	save_error = ""
	notice = ""
	var tmp := dir_path + ".saving"
	var old := dir_path + ".old"
	var report := {}
	var recovered := _recover(dir_path, report)
	if recovered != OK:
		save_error = report.get("error", "Couldn't recover " + dir_path)
		return recovered
	var cleared := _remove_snapshot(tmp)
	if cleared != OK:
		return _save_failed(cleared, "clear the staging folder", tmp)
	var made := DirAccess.make_dir_recursive_absolute(tmp)
	if made != OK:
		return _save_failed(made, "create the staging folder", tmp)
	var out := data.duplicate(true)
	out.water_level = safe_water_level()
	out["next_id"] = _next_id
	var f := FileAccess.open(tmp.path_join("world.json"), FileAccess.WRITE)
	if f == null:
		return _save_failed(FileAccess.get_open_error(), "write", tmp.path_join("world.json"))
	f.store_string(JSON.stringify(out, " "))
	f.flush()
	var failed := f.get_error()
	f.close()
	if failed != OK:
		return _save_failed(failed, "write", tmp.path_join("world.json"))
	f = FileAccess.open(tmp.path_join("terrain.bin"), FileAccess.WRITE)
	if f == null:
		return _save_failed(FileAccess.get_open_error(), "write", tmp.path_join("terrain.bin"))
	f.store_buffer(heights.to_byte_array())
	f.store_buffer(ground)
	f.flush()
	failed = f.get_error()
	f.close()
	if failed != OK:
		return _save_failed(failed, "write", tmp.path_join("terrain.bin"))
	if FileAccess.file_exists(dir_path.path_join(THUMB)):
		var copied := DirAccess.copy_absolute(dir_path.path_join(THUMB), tmp.path_join(THUMB))
		if copied != OK:
			return _save_failed(copied, "copy the thumbnail from", dir_path)
	if DirAccess.dir_exists_absolute(dir_path):
		var moved := DirAccess.rename_absolute(dir_path, old)
		if moved != OK:
			return _save_failed(moved, "move the current project to its backup", dir_path)
	var swapped := DirAccess.rename_absolute(tmp, dir_path)
	if swapped != OK:
		var restored := DirAccess.rename_absolute(old, dir_path) if DirAccess.dir_exists_absolute(old) else OK
		return _save_failed(swapped, "publish the saved project; previous files remain at " + old if restored != OK else "publish the saved project", dir_path)
	recovered = _recover(dir_path, report)
	if recovered != OK:
		save_error = report.get("error", "Couldn't finish saving " + dir_path)
	if report.has("recovered"):
		notice = "Recovered files kept at: " + ", ".join(report.recovered)
	return recovered

func _save_failed(err: Error, operation: String, at: String) -> Error:
	save_error = "Couldn't %s: %s (%s)." % [operation, at, error_string(err)]
	return err

func safe_water_level() -> float:
	return minf(float(data.water_level), MAX_WATER_LEVEL)

static func _entries(dir_path: String) -> PackedStringArray:
	var dir := DirAccess.open(dir_path)
	var names := PackedStringArray()
	if dir:
		dir.include_hidden = true
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			names.append(name)
			name = dir.get_next()
		dir.list_dir_end()
	return names

static func _remove_snapshot(dir_path: String) -> Error:
	if not DirAccess.dir_exists_absolute(dir_path):
		return ERR_ALREADY_EXISTS if FileAccess.file_exists(dir_path) else OK
	for name in _entries(dir_path):
		if name not in PROJECT_FILES or DirAccess.dir_exists_absolute(dir_path.path_join(name)):
			return ERR_ALREADY_EXISTS
	for name in _entries(dir_path):
		var err := DirAccess.remove_absolute(dir_path.path_join(name))
		if err != OK:
			return err
	return DirAccess.remove_absolute(dir_path)

static func remove_folder(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for name in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(name))
	DirAccess.remove_absolute(dir_path)

static func recovery_path(path: String) -> String:
	var candidate := path + ".recovered"
	var n := 2
	while FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate):
		candidate = path + ".recovered-%d" % n
		n += 1
	return candidate

static func _recovery_error(report: Dictionary, err: Error, at: String) -> Error:
	report.error = "Couldn't recover saved files at %s (%s). Both copies have been kept; close any program using them and retry." % [at, error_string(err)]
	return err

static func _recover(dir_path: String, report := {}) -> Error:
	var old := dir_path + ".old"
	if not DirAccess.dir_exists_absolute(old):
		return _recovery_error(report, ERR_ALREADY_EXISTS, old) if FileAccess.file_exists(old) else OK
	if not DirAccess.dir_exists_absolute(dir_path):
		var restored := DirAccess.rename_absolute(old, dir_path)
		return _recovery_error(report, restored, old) if restored != OK else OK
	# Keep the backup until every unrelated entry has been restored; open() resumes this after interruption.
	for name in _entries(old):
		if name in PROJECT_FILES:
			continue
		var destination := dir_path.path_join(name)
		if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
			destination = recovery_path(destination)
		var moved := DirAccess.rename_absolute(old.path_join(name), destination)
		if moved != OK:
			return _recovery_error(report, moved, old.path_join(name))
		if destination != dir_path.path_join(name):
			if not report.has("recovered"):
				report.recovered = []
			report.recovered.append(destination)
	var cleaned := _remove_snapshot(old)
	return _recovery_error(report, cleaned, old) if cleaned != OK else OK

static func open(dir_path: String, report := {}) -> WorldDoc:
	_recover(dir_path, report)
	var doc := _read_snapshot(dir_path)
	if doc == null:
		if not report.has("error"):
			report.error = "Couldn't read the project at %s. It may be damaged or made by a newer version." % dir_path
		return null
	if report.has("error"):
		doc.notice = report.error
	elif report.has("recovered"):
		doc.notice = "Recovered files kept at: " + ", ".join(report.recovered)
	return doc

static func _read_snapshot(dir_path: String) -> WorldDoc:
	if not FileAccess.file_exists(dir_path.path_join("world.json")) or not FileAccess.file_exists(dir_path.path_join("terrain.bin")):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir_path.path_join("world.json")))
	if not parsed is Dictionary or not _integer(parsed.get("format")):
		return null
	if int(parsed.format) < 1 or int(parsed.format) > FORMAT:
		return null
	var doc := WorldDoc.new()
	doc.data = migrate(parsed)
	if not _valid_data(doc.data):
		return null
	doc._next_id = int(doc.data.get("next_id", 1))
	for thing in doc.data.things:
		doc._next_id = maxi(doc._next_id, int(thing.id) + 1)
	doc.data.erase("next_id")
	var raw := FileAccess.get_file_as_bytes(dir_path.path_join("terrain.bin"))
	var count := TERRAIN_RES * TERRAIN_RES
	if raw.size() != count * 5:
		return null
	doc.heights = raw.slice(0, count * 4).to_float32_array()
	doc.ground = raw.slice(count * 4)
	for i in count:
		if not is_finite(doc.heights[i]) or doc.ground[i] > 3:
			return null
	doc.water_adjusted = float(doc.data.water_level) > MAX_WATER_LEVEL
	doc.data.water_level = doc.safe_water_level()
	return doc

static func valid_kind(kind: String) -> bool:
	return kind.is_valid_identifier() or (kind.begins_with(CustomItems.PREFIX) and CustomItems.valid_id(kind.trim_prefix(CustomItems.PREFIX)))

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and absf(float(value)) < 9007199254740991.0

static func _valid_data(d: Dictionary) -> bool:
	if d.get("base") not in BASES or not d.get("title") is String or d.title.strip_edges().is_empty() or d.title.length() > 128:
		return false
	if not _number(d.get("water_level")) or not d.get("mood") is Dictionary or not d.get("things") is Array:
		return false
	if d.has("season") and d.season not in SEASONS:
		return false
	if d.has("next_id") and (not _integer(d.next_id) or d.next_id < 1):
		return false
	for time in ["light", "dark"]:
		var mood = d.mood.get(time)
		if not mood is Dictionary or not mood.get("sky") is String or not mood.sky.is_valid_identifier():
			return false
		for key in ["strength", "sun_energy"]:
			if not _number(mood.get(key)) or mood[key] < 0:
				return false
		if not mood.get("sun_color") is Array or mood.sun_color.size() != 3:
			return false
		for channel in mood.sun_color:
			if not _number(channel) or channel < 0:
				return false
	var ids := {}
	for thing in d.things:
		if not thing is Dictionary or not _integer(thing.get("id")) or thing.id < 1 or ids.has(int(thing.id)):
			return false
		ids[int(thing.id)] = true
		if not thing.get("kind") is String or not valid_kind(thing.kind):
			return false
		for key in ["x", "z", "turn", "scale"]:
			if not _number(thing.get(key)):
				return false
		if thing.scale <= 0:
			return false
	return true

static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.format)
	while v < FORMAT:
		d = MIGRATIONS[v - 1].call(d)
		v += 1
	d.format = FORMAT
	return d

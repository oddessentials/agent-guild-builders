class_name WorldLoader
extends Node

signal step(label: String, fraction: float)
signal done(doc: WorldDoc)

var error := ""
var _thread: Thread
var _generation := 0

func start(make: Callable, path := "") -> void:
	if _thread:
		return
	error = ""
	_generation += 1
	WorldScene.refresh_custom()
	Yard.data()
	Clearance.terrain_limits()
	_thread = Thread.new()
	var started := _thread.start(_work.bind(make, path))
	if started != OK:
		_thread = null
		error = "Couldn't start loading (%s). Try opening the world again." % error_string(started)
		done.emit(null)
		return
	set_process(true)

func _say(label: String, fraction: float) -> void:
	_tell.call_deferred(label, fraction, _generation)

func _tell(label: String, fraction: float, generation: int) -> void:
	if _thread and generation == _generation:
		step.emit(label, fraction)

func _work(make: Callable, path: String) -> Dictionary:
	_say("Laying out your world…", 0.02)
	var report := {}
	var doc: WorldDoc = WorldDoc.open(path, report) if path != "" else make.call()
	if doc == null or not WorldDoc._valid_data(doc.data):
		return {"error": report.get("error", "That world couldn't be opened. It may be damaged or made by a newer version.")}
	var kit := WorldScene.load_kit()
	var models: Dictionary = kit.get("models", {})
	if models.is_empty():
		return {"error": "The Meadow kit is missing or damaged. Extract the complete app ZIP, including its kits folder."}
	for thing in doc.data.things:
		if not models.has(thing.kind) and not CustomItems.is_custom(thing.kind):
			return {"error": "This world uses an unavailable item: %s." % thing.kind}
	_say("Loading ground textures…", 0.15)
	for name in WorldScene.surface_textures(doc):
		for suffix in ["_diff", "_nor_gl", "_rough"]:
			if WorldScene._texture(name + suffix, false) == null:
				return {"error": "A ground texture is missing or damaged: %s. Extract the complete app ZIP, including its kits folder." % name}
	var used := {}
	for thing in doc.data.things:
		if models.has(thing.kind):
			used[thing.kind] = true
	var total := 0.0
	for kind in used:
		total += maxf(float(models[kind].get("bytes", 1)), 1.0)
	var loaded := 0.0
	for kind in used:
		_say("Loading %s…" % str(models[kind].get("label", kind)).to_lower(), 0.25 + 0.6 * loaded / total)
		if WorldScene.mesh_of(kind).get_surface_count() == 0 and not CustomItems.is_custom(kind):
			return {"error": "An item is missing or damaged: %s. Extract the complete app ZIP, including its kits folder." % str(models[kind].get("label", kind))}
		loaded += maxf(float(models[kind].get("bytes", 1)), 1.0)
	_say("Loading the halls…", 0.85)
	if WorldScene.load_halls(doc.data.base).is_empty():
		return {"error": "The halls for this world are missing or damaged. Extract the complete app ZIP, including its kits folder."}
	_say("Loading the sky…", 0.95)
	for time in Yard.THEMES:
		var sky: String = doc.data.mood[time].sky
		if not kit.get("skies", {}).has(sky) or WorldScene.sky_texture(sky) == null:
			return {"error": "A sky is missing or damaged: %s. Extract the complete app ZIP, including its kits folder." % sky}
	var checked := Clearance.check_world(doc)
	if not checked.get("valid", false):
		doc.notice = (doc.notice + " " if doc.notice != "" else "") + checked.get("problem", "The project couldn't be checked for export.")
	return {"doc": doc}

func _process(_delta: float) -> void:
	if not _thread or _thread.is_alive():
		return
	var result = _thread.wait_to_finish()
	_thread = null
	set_process(false)
	if result is Dictionary and result.get("doc") is WorldDoc:
		step.emit("Ready", 1.0)
		done.emit(result.doc)
	else:
		error = result.get("error", "Couldn't finish loading this world.") if result is Dictionary else "Couldn't finish loading this world. It may be damaged."
		done.emit(null)

func _exit_tree() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null

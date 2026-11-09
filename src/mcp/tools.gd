class_name McpTools
extends RefCounted
## The tools an agent gets. Each checks its arguments against its own schema,
## then calls the editor's operations, so agents follow the same rules, undo
## history and saving as the person at the window.

const EditorView := preload("res://src/ui/editor_view.gd")
const PREVIEW_WIDTH := 1024
const MAX_LISTED := 500
const READING := ["list_worlds", "describe_world", "list_items"]
const OPENING := ["create_world", "open_world"]
const RENDERING := ["render_preview", "export_world"]

var server: McpServer
var _defs: Array = []
var _by_name := {}

func _init(owner: McpServer) -> void:
	server = owner
	_defs = _definitions()
	for d in _defs:
		_by_name[d.name] = d

func has(name: String) -> bool:
	return _by_name.has(name)

func definitions() -> Array:
	return _defs

func is_async(name: String) -> bool:
	return name in OPENING or name in RENDERING

func is_long(name: String) -> bool:
	return name in RENDERING

func can_run_while_rendering(name: String) -> bool:
	return name in READING

func waits_for_person(name: String) -> bool:
	if name in READING:
		return false
	var view = _host_editor()
	return view != null and view.agent_busy() == EditorView.AGENT_GESTURE

func failure(text: String) -> Dictionary:
	return {"content": [{"type": "text", "text": text}], "isError": true}

func _done(text: String, data: Variant = null) -> Dictionary:
	var out := {"content": [{"type": "text", "text": text if data == null else text + "\n" + JSON.stringify(data)}], "isError": false}
	if data != null:
		out["structuredContent"] = data
	return out

## Stops only the job this request started, while it's still the running one.
func cancel(ctx: Dictionary) -> void:
	var job = ctx.get("job")
	var view = _host_editor()
	if job != null and is_instance_valid(job) and view and view._job == job:
		view.cancel_job()

func _wanted(ctx: Dictionary) -> Callable:
	return func(): return not ctx.cancelled and not server._closed

func _own_job(ctx: Dictionary, view: Control) -> Callable:
	var claim := func(job: BakeJob): ctx["job"] = job
	view.job_started.connect(claim, CONNECT_ONE_SHOT)
	return claim

func _host_editor() -> Control:
	return server.host.agent_editor() if server.host and server.host.has_method("agent_editor") else null

func call_tool(ctx: Dictionary, name: String, args: Dictionary) -> void:
	var problem := check(_by_name[name].inputSchema, args, "")
	if problem != "":
		server.respond(ctx, failure("Invalid arguments: " + problem))
		return
	var result: Dictionary = await Callable(self, "_tool_" + name).call(ctx, args)
	if not result.is_empty():
		server.respond(ctx, result)

static func check(schema: Dictionary, value: Variant, at: String) -> String:
	var here := at if at != "" else "arguments"
	match schema.get("type"):
		"object":
			if not value is Dictionary:
				return "%s must be an object." % here
			var props: Dictionary = schema.get("properties", {})
			for key in schema.get("required", []):
				if not value.has(key):
					return "%s needs `%s`." % [here, key]
			for key in value:
				if not props.has(key):
					if schema.get("additionalProperties", true) == false:
						return "%s doesn't take `%s`." % [here, key]
					continue
				var inner := check(props[key], value[key], (at + "." if at != "" else "") + str(key))
				if inner != "":
					return inner
		"array":
			if not value is Array:
				return "%s must be a list." % here
			if value.size() < int(schema.get("minItems", 0)):
				return "%s needs at least %d entries." % [here, schema.minItems]
			if schema.has("maxItems") and value.size() > int(schema.maxItems):
				return "%s takes at most %d entries." % [here, schema.maxItems]
			for i in value.size():
				var inner := check(schema.items, value[i], "%s[%d]" % [here, i])
				if inner != "":
					return inner
		"string":
			if not value is String:
				return "%s must be text." % here
			if schema.has("enum") and value not in schema.enum:
				return "%s must be one of: %s." % [here, ", ".join(schema.enum)]
			if value.length() < int(schema.get("minLength", 0)) or (schema.has("maxLength") and value.length() > int(schema.maxLength)):
				return "%s must be %d to %d characters." % [here, int(schema.get("minLength", 0)), int(schema.get("maxLength", 0))]
		"number", "integer":
			if not (value is float or value is int) or not is_finite(float(value)):
				return "%s must be a number." % here
			if schema.type == "integer" and float(value) != floorf(float(value)):
				return "%s must be a whole number." % here
			if (schema.has("minimum") and float(value) < float(schema.minimum)) or (schema.has("maximum") and float(value) > float(schema.maximum)):
				return "%s must be from %s to %s." % [here, schema.get("minimum", "-∞"), schema.get("maximum", "∞")]
		"boolean":
			if not value is bool:
				return "%s must be true or false." % here
	return ""

static func _point() -> Dictionary:
	return {"type": "object", "properties": {"x": {"type": "number", "minimum": -259, "maximum": 259}, "z": {"type": "number", "minimum": -259, "maximum": 259}}, "required": ["x", "z"], "additionalProperties": false}

static func _points() -> Dictionary:
	return {"type": "array", "items": _point(), "minItems": 1, "maxItems": 200, "description": "Ground points the brush is dragged through, in order. One point is a single dab."}

static func _world() -> Dictionary:
	return {"type": "string", "minLength": 1, "maxLength": 4096, "description": "The world's `world` value from list_worlds, create_world or open_world."}

static func _radius() -> Dictionary:
	return {"type": "number", "minimum": 1, "maximum": 40, "description": "Brush radius in metres."}

static func _object(props: Dictionary, required: Array) -> Dictionary:
	return {"type": "object", "properties": props, "required": required, "additionalProperties": false}

static func _time() -> Dictionary:
	var skies: Dictionary = WorldScene.load_kit().get("skies", {})
	return _object({"sky": {"type": "string", "enum": skies.keys()}, "sun_strength": {"type": "number", "minimum": EditorView.SUN_STRENGTH[0], "maximum": EditorView.SUN_STRENGTH[1]}, "sky_strength": {"type": "number", "minimum": EditorView.SKY_STRENGTH[0], "maximum": EditorView.SKY_STRENGTH[1]}}, [])

func _definitions() -> Array:
	var groups := []
	for entry in EditorView.PLACE_GROUPS:
		groups.append(entry[0])
	var read := {"readOnlyHint": true, "openWorldHint": false}
	var edit := {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}
	var removes := {"readOnlyHint": false, "destructiveHint": true, "openWorldHint": false}
	return [
		{"name": "list_worlds", "title": "List worlds", "description": "The worlds saved on this computer, newest first, and which one is open in the window.",
			"inputSchema": _object({}, []), "annotations": read},
		{"name": "create_world", "title": "Create a world", "description": "Saves the open world, then creates a new one from a template and opens it in the window. `preview_yard` chooses whose halls and crews show while building; in Agent Guild a world shows the halls of the Yard it replaces.",
			"inputSchema": _object({"template": {"type": "string", "enum": Templates.LIST.keys()}, "title": {"type": "string", "minLength": 1, "maxLength": 128},
				"preview_yard": {"type": "string", "enum": WorldDoc.BASES}, "seed": {"type": "integer", "minimum": 0, "maximum": 2147483647}}, ["template", "title"]), "annotations": edit},
		{"name": "open_world", "title": "Open a world", "description": "Saves the open world, then opens this one in the window.",
			"inputSchema": _object({"world": _world()}, ["world"]), "annotations": edit},
		{"name": "describe_world", "title": "Describe the open world", "description": "Title, season, sky and sun by day and at dusk, water, item counts, undo state and anything that would stop an export. With `items_near`, also lists the items in that circle with their ids.",
			"inputSchema": _object({"world": _world(), "items_near": _object({"x": _point().properties.x, "z": _point().properties.z, "radius": {"type": "number", "minimum": 1, "maximum": 400}}, ["x", "z", "radius"])}, ["world"]), "annotations": read},
		{"name": "list_items", "title": "List placeable items", "description": "Kinds you can place, with their size and whether they're tall (only fit further out), join into walls, or can be resized. Also lists the mixes paint_area can use.",
			"inputSchema": _object({"group": {"type": "string", "enum": groups}, "search": {"type": "string", "maxLength": 64}}, []), "annotations": read},
		{"name": "place_items", "title": "Place items", "description": "Places each item by the same rules as clicking: walls and other joining pieces snap together, sizes shrink to keep the Yard clear, and refused spots say why. Everything placed is one undo step; refusals don't undo the rest.",
			"inputSchema": _object({"world": _world(), "items": {"type": "array", "minItems": 1, "maxItems": 200, "items": _object({"kind": {"type": "string", "minLength": 1, "maxLength": 128},
				"x": _point().properties.x, "z": _point().properties.z, "turn": {"type": "number", "minimum": -3600, "maximum": 3600, "description": "Degrees."},
				"scale": {"type": "number", "minimum": EditorView.SMALLEST_SIZE, "maximum": EditorView.LARGEST_SIZE}}, ["kind", "x", "z"])}}, ["world", "items"]), "annotations": edit},
		{"name": "paint_area", "title": "Paint items over an area", "description": "Drags the Paint brush through the points, scattering a kind or a mix (`mix:<name>` from list_items) with natural spacing. Spots the rules refuse are skipped. One undo step.",
			"inputSchema": _object({"world": _world(), "choice": {"type": "string", "minLength": 1, "maxLength": 128}, "points": _points(), "radius": _radius()}, ["world", "choice", "points", "radius"]), "annotations": edit},
		{"name": "move_items", "title": "Move items", "description": "Moves, turns (degrees) or resizes placed items by id, by the Move tool's rules. Accepted changes are one undo step; refusals say why.",
			"inputSchema": _object({"world": _world(), "moves": {"type": "array", "minItems": 1, "maxItems": 200, "items": _object({"id": {"type": "integer", "minimum": 1},
				"x": _point().properties.x, "z": _point().properties.z, "turn": {"type": "number", "minimum": -3600, "maximum": 3600},
				"scale": {"type": "number", "minimum": EditorView.SMALLEST_SIZE, "maximum": EditorView.LARGEST_SIZE}}, ["id"])}}, ["world", "moves"]), "annotations": edit},
		{"name": "remove_items", "title": "Remove items", "description": "Removes items by id, or clears everything the brush passes over (give `points` and `radius` instead of `ids`). One undo step.",
			"inputSchema": _object({"world": _world(), "ids": {"type": "array", "minItems": 1, "maxItems": 2000, "items": {"type": "integer", "minimum": 1}}, "points": _points(), "radius": _radius()}, ["world"]), "annotations": removes},
		{"name": "shape_land", "title": "Shape land", "description": "Raises, lowers or smooths the ground along the points. `strength` repeats the stroke, like holding the brush longer. The ground where crews stand stays flat and nothing may rise to hide the Yard. One undo step.",
			"inputSchema": _object({"world": _world(), "mode": {"type": "string", "enum": ["raise", "lower", "smooth"]}, "points": _points(), "radius": _radius(), "strength": {"type": "integer", "minimum": 1, "maximum": 10}}, ["world", "mode", "points", "radius"]), "annotations": edit},
		{"name": "paint_ground", "title": "Paint ground", "description": "Paints a ground along the points. One undo step.",
			"inputSchema": _object({"world": _world(), "ground": {"type": "string", "enum": WorldScene.GROUND_ORDER}, "points": _points(), "radius": _radius()}, ["world", "ground", "points", "radius"]), "annotations": edit},
		{"name": "set_look", "title": "Set the look", "description": "Season, water, and the sky and sun by day and at dusk. The sun's direction is fixed to match the Yard. Choosing a sky resets its strength unless you give one. One undo step.",
			"inputSchema": _object({"world": _world(), "season": {"type": "string", "enum": WorldDoc.SEASONS},
				"water": _object({"on": {"type": "boolean"}, "level": {"type": "number", "minimum": EditorView.WATER_LOWEST, "maximum": WorldDoc.MAX_WATER_LEVEL}}, ["on"]),
				"day": _time(), "dusk": _time()}, ["world"]), "annotations": edit},
		{"name": "undo", "title": "Undo", "description": "Undoes the last change in this world, whoever made it.", "inputSchema": _object({"world": _world()}, ["world"]), "annotations": edit},
		{"name": "redo", "title": "Redo", "description": "Redoes the last undone change in this world.", "inputSchema": _object({"world": _world()}, ["world"]), "annotations": edit},
		{"name": "render_preview", "title": "Render a preview", "description": "Renders the area round the Yard by day or at dusk, without the live halls and crews, and returns the picture. Takes a few seconds.",
			"inputSchema": _object({"world": _world(), "time": {"type": "string", "enum": ["day", "dusk"]}}, ["world"]), "annotations": read},
		{"name": "export_world", "title": "Export the world", "description": "Saves, then renders by day and at dusk and writes the .agworld file Agent Guild loads. Final quality takes several minutes; draft is quicker. `to` is a full path ending in .agworld; an existing file is only replaced with `replace`.",
			"inputSchema": _object({"world": _world(), "to": {"type": "string", "minLength": 1, "maxLength": 4096}, "replace": {"type": "boolean"}, "quality": {"type": "string", "enum": ["draft", "final"]}}, ["world", "to"]), "annotations": removes},
	]

static func _same_path(a: String, b: String) -> bool:
	var na := a.replace("\\", "/").simplify_path().trim_suffix("/")
	var nb := b.replace("\\", "/").simplify_path().trim_suffix("/")
	return na.to_lower() == nb.to_lower() if OS.get_name() == "Windows" else na == nb

func _editor_for(args: Dictionary) -> Variant:
	if server.host.agent_loading():
		return "Builders is opening a world. Try again in a moment."
	var view = _host_editor()
	if view == null:
		return "No world is open. Use create_world or open_world."
	if view.path == "" or not _same_path(view.path, args.world):
		return "That world isn't the one open in the window. The open world is %s (%s); call open_world to switch." % [view.path if view.path != "" else "not saved yet", view.doc.data.title]
	return view

func _editing(args: Dictionary) -> Variant:
	var view = _editor_for(args)
	if view is String:
		return view
	var busy: String = view.agent_busy()
	return busy if busy != "" else view

static func _models() -> Dictionary:
	return WorldScene.load_kit().get("models", {})

static func _degrees(radians: float) -> float:
	return snappedf(rad_to_deg(wrapf(radians, 0.0, TAU)), 0.1)

static func _thing(t: Dictionary) -> Dictionary:
	return {"id": int(t.id), "kind": t.kind, "x": snappedf(float(t.x), 0.01), "z": snappedf(float(t.z), 0.01), "turn": _degrees(float(t.turn)), "scale": snappedf(float(t.scale), 0.01)}

static func _flat(points: Array) -> Array:
	return points.map(func(p): return Vector2(float(p.x), float(p.z)))

static func export_problem(to: String, replace: bool) -> String:
	var path := to.replace("\\", "/")
	if not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"):
		return "`to` must be a full path, such as C:/Users/you/Documents/My Yard.agworld."
	if path.split("/").has(".."):
		return "`to` can't contain `..`."
	if not path.to_lower().ends_with(WorldPackage.EXT):
		return "`to` must end in %s." % WorldPackage.EXT
	if path.get_file().get_basename().strip_edges() == "" or not path.get_file().is_valid_filename():
		return "`to` needs a valid file name."
	var folder := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder):
		return "The folder %s doesn't exist." % folder
	for protected in [OS.get_user_data_dir(), OS.get_executable_path().get_base_dir(), WorldLibrary.root()]:
		var p := str(protected).replace("\\", "/").trim_suffix("/")
		if p != "" and (_same_path(folder, p) or (folder.to_lower() + "/").begins_with(p.to_lower() + "/")):
			return "Builders keeps its own files in %s. Export somewhere else, such as Documents." % p
	if DirAccess.dir_exists_absolute(path):
		return "%s is a folder." % path
	if FileAccess.file_exists(path) and not replace:
		return "%s already exists. Pass `replace: true` to replace it." % path
	return ""

func _tool_list_worlds(_ctx: Dictionary, _args: Dictionary) -> Dictionary:
	var view = _host_editor()
	var out := []
	for w in WorldLibrary.list():
		out.append({"world": w.path, "title": w.title, "preview_yard": w.base,
			"modified": Time.get_datetime_string_from_unix_time(int(w.modified)), "open": view != null and view.path != "" and _same_path(view.path, w.path)})
	return _done("%d saved worlds." % out.size(), {"worlds": out})

func _tool_create_world(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var title := WorldLibrary.unique_title(str(args.title).strip_edges())
	var base := str(args.get("preview_yard", "guild"))
	var seed_value := int(args.get("seed", randi() % 100000))
	var template := str(args.template)
	var error: String = await server.host.agent_open(func(): return Templates.create(template, base, title, seed_value), "", _wanted(ctx))
	if error != "":
		return failure(error)
	var view = _host_editor()
	if view == null or not view._save_now():
		return failure("The new world is open but couldn't be saved yet. " + (view._save_failure if view else ""))
	return _done("Created and opened “%s”." % title, {"world": view.path, "title": title, "template": template, "preview_yard": base, "seed": seed_value})

func _tool_open_world(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _host_editor()
	if view and view.path != "" and _same_path(view.path, args.world):
		return _done("Already open.", {"world": view.path, "title": view.doc.data.title})
	var folder := str(args.world).replace("\\", "/")
	if not folder.is_absolute_path():
		return failure("Give the world's full path, as list_worlds shows it.")
	var report := {}
	var opened := WorldDoc.open(folder, report)
	if opened == null:
		return failure(str(report.get("error", "There's no world at %s." % folder)) + " Use list_worlds to find one.")
	var error: String = await server.host.agent_open(func(): return opened, folder, _wanted(ctx))
	if error != "":
		return failure(error)
	view = _host_editor()
	return _done("Opened “%s”." % view.doc.data.title, {"world": view.path, "title": view.doc.data.title})

func _tool_describe_world(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editor_for(args)
	if view is String:
		return failure(view)
	var doc: WorldDoc = view.doc
	var models := _models()
	var groups := {}
	var kinds := {}
	for t in doc.data.things:
		var g := str(models.get(t.kind, {}).get("group", "missing"))
		groups[g] = int(groups.get(g, 0)) + 1
		kinds[t.kind] = int(kinds.get(t.kind, 0)) + 1
	var low := INF
	var high := -INF
	for h in doc.heights:
		low = minf(low, h)
		high = maxf(high, h)
	var looks := {}
	for time in [["day", "light"], ["dusk", "dark"]]:
		var m: Dictionary = doc.data.mood[time[1]]
		looks[time[0]] = {"sky": m.sky, "sun_strength": snappedf(float(m.sun_energy), 0.01), "sky_strength": snappedf(float(m.strength), 0.01)}
	var checked := Clearance.check_world(doc)
	var problems := []
	for issue in checked.get("issues", []):
		problems.append({"kind": issue.kind, "message": issue.get("message", ""), "x": snappedf(issue.position.x, 0.1), "z": snappedf(issue.position.y, 0.1)})
	var out := {"world": view.path, "title": doc.data.title, "template": doc.data.get("template", ""), "preview_yard": doc.data.base, "season": doc.season(),
		"day": looks.day, "dusk": looks.dusk, "water": {"on": float(doc.data.water_level) > WorldDoc.NO_WATER_BELOW, "level": snappedf(doc.safe_water_level(), 0.01)},
		"land": {"lowest": snappedf(low, 0.01), "highest": snappedf(high, 0.01)}, "items": doc.data.things.size(), "groups": groups, "kinds": kinds,
		"can_export": checked.get("valid", false), "problems": problems, "problem_summary": checked.get("summary", checked.get("problem", "")),
		"undo": view.history.undo_label(), "redo": view.history.redo_label(), "rendering": view._exporting}
	if args.has("items_near"):
		var near: Dictionary = args.items_near
		var listed := []
		for t in doc.data.things:
			if Vector2(float(t.x) - float(near.x), float(t.z) - float(near.z)).length() <= float(near.radius):
				listed.append(_thing(t))
		out["items_near"] = listed.slice(0, MAX_LISTED)
		if listed.size() > MAX_LISTED:
			out["items_near_truncated"] = listed.size()
	return _done("“%s”: %d items, %s." % [doc.data.title, doc.data.things.size(), "ready to export" if out.can_export else "export blocked: " + str(out.problem_summary)], out)

func _tool_list_items(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var wanted := str(args.get("search", "")).strip_edges().to_lower()
	var group := str(args.get("group", ""))
	var items := []
	var models := _models()
	for kind in models:
		var info: Dictionary = models[kind]
		if group != "" and info.group != group:
			continue
		if wanted != "" and not str(info.label).to_lower().contains(wanted) and not str(kind).contains(wanted):
			continue
		var size := Placing.sizes(kind)
		items.append({"kind": kind, "label": info.label, "group": info.group, "height": snappedf(float(info.get("height", 1.0)), 0.01),
			"tall": float(info.get("height", 1.0)) * size.x > 1.0, "joins": Placing.joins(kind), "resizable": not Placing.modular(kind)})
	var mixes := []
	for key in Placing.MIXES:
		mixes.append({"choice": "mix:" + key, "label": Placing.MIXES[key].label, "kinds": Placing.MIXES[key].kinds})
	return _done("%d items." % items.size(), {"items": items, "mixes": mixes})

func _tool_place_items(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var models := _models()
	var results := []
	var accepted := []
	var at := []
	for i in args.items.size():
		var item: Dictionary = args.items[i]
		var kind := str(item.kind)
		if not models.has(kind):
			results.append({"index": i, "kind": kind, "refused": "There's no item called %s. Use list_items." % kind})
			continue
		results.append({})
		at.append(i)
		accepted.append({"kind": kind, "x": float(item.x), "z": float(item.z), "turn": deg_to_rad(float(item.get("turn", 0.0))),
			"scale": float(item.get("scale", Placing.sizes(kind).x if Placing.modular(kind) else 1.0)), "exact": {"turn": item.has("turn"), "scale": item.has("scale")}})
	var placed: Array = view.agent_place(accepted) if not accepted.is_empty() else []
	var count := 0
	for n in placed.size():
		var r: Dictionary = placed[n]
		var i: int = at[n]
		if r.why != "":
			results[i] = {"index": i, "kind": accepted[n].kind, "refused": r.why}
			continue
		count += 1
		var entry := _thing(r.thing)
		entry["index"] = i
		if r.joins != "":
			entry["joined"] = r.joins
		if r.behind != "":
			entry["note"] = "Behind the %s, so it may be hidden from view." % r.behind
		results[i] = entry
	var refused: int = args.items.size() - count
	return _done("Placed %d of %d%s." % [count, args.items.size(), (" as one undo step" if count > 0 else "") + ("; %d refused" % refused if refused > 0 else "")], {"results": results})

func _tool_paint_area(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var choice := str(args.choice)
	if choice.begins_with("mix:"):
		if not Placing.MIXES.has(choice.trim_prefix("mix:")):
			return failure("There's no mix called %s. Use list_items." % choice)
	elif not _models().has(choice):
		return failure("There's no item called %s. Use list_items." % choice)
	var r: Dictionary = view.agent_brush(EditorView.Tool.SCATTER, _flat(args.points), float(args.radius), {"place_mode": "paint", "paint_choice": choice})
	return _done("Painted %d items%s." % [r.added, "; %d spots were refused by the placement rules" % r.skipped if r.skipped > 0 else ""], {"added": r.added, "added_ids": r.added_ids, "skipped": r.skipped})

func _tool_move_items(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var seen := {}
	var repeated := []
	for m in args.moves:
		if seen.has(int(m.id)) and not repeated.has(int(m.id)):
			repeated.append(int(m.id))
		seen[int(m.id)] = true
	if not repeated.is_empty():
		return failure("Each id may appear once in moves; repeated: %s. Nothing was changed." % ", ".join(repeated.map(func(i): return str(i))))
	var moves := []
	for m in args.moves:
		var move: Dictionary = m.duplicate()
		if move.has("turn"):
			move.turn = deg_to_rad(float(move.turn))
		moves.append(move)
	var done: Array = view.agent_move(moves)
	var results := []
	var count := 0
	for i in done.size():
		if done[i].has("why"):
			results.append({"index": i, "id": int(args.moves[i].id), "refused": done[i].why})
		else:
			count += 1
			var entry := _thing(done[i].thing)
			entry["index"] = i
			results.append(entry)
	return _done("Moved %d of %d." % [count, done.size()], {"results": results})

func _tool_remove_items(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var by_ids := args.has("ids")
	var by_area := args.has("points") or args.has("radius")
	if by_ids == by_area or (by_area and not (args.has("points") and args.has("radius"))):
		return failure("Give either `ids`, or both `points` and `radius`.")
	if by_ids:
		var r: Dictionary = view.agent_remove(args.ids)
		if r.has("why"):
			return failure(r.why)
		return _done("Removed %d." % r.removed, {"removed": r.removed, "not_found": r.not_found})
	var r: Dictionary = view.agent_brush(EditorView.Tool.ERASE, _flat(args.points), float(args.radius), {})
	return _done("Cleared %d items." % r.removed, {"removed": r.removed})

func _tool_shape_land(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var r: Dictionary = view.agent_brush(EditorView.Tool.LAND, _flat(args.points), float(args.radius), {"land_mode": args.mode}, int(args.get("strength", 1)))
	var note := " Some land stayed at its limit: the ground where crews stand stays flat, and land can't rise to hide the Yard." if r.limited else ""
	return _done("Changed %d land cells.%s" % [r.cells, note], {"cells": r.cells, "limited": r.limited})

func _tool_paint_ground(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var r: Dictionary = view.agent_brush(EditorView.Tool.GROUND, _flat(args.points), float(args.radius), {"ground_kind": WorldScene.GROUND_ORDER.find(args.ground)})
	return _done("Painted %d land cells with %s." % [r.cells, args.ground], {"cells": r.cells})

func _tool_set_look(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var doc: WorldDoc = view.doc
	var look := {}
	if args.has("season"):
		look["season"] = args.season
	if args.has("water"):
		if not args.water.on:
			look["water_level"] = -100.0
		else:
			var level := doc.safe_water_level() if float(doc.data.water_level) > WorldDoc.NO_WATER_BELOW else -0.6
			look["water_level"] = float(args.water.get("level", level))
	for time in [["day", "light"], ["dusk", "dark"]]:
		var given: Dictionary = args.get(time[0], {})
		var values := {}
		if given.has("sky"):
			values["sky"] = given.sky
		if given.has("sky_strength"):
			values["strength"] = float(given.sky_strength)
		if given.has("sun_strength"):
			values["sun_energy"] = float(given.sun_strength)
		if not values.is_empty():
			look[time[1]] = values
	if look.is_empty():
		return failure("Nothing to change: give season, water, or a day or dusk sky, sky_strength or sun_strength.")
	if not view.agent_set_look(look):
		return _done("Nothing changed: the look already matches.")
	return _done("Changed the look as one undo step.")

func _tool_undo(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	return _step(args, false)

func _tool_redo(_ctx: Dictionary, args: Dictionary) -> Dictionary:
	return _step(args, true)

func _step(args: Dictionary, redo: bool) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	var label: String = view.agent_undo(redo)
	if label == "":
		return failure("Nothing to %s." % ("redo" if redo else "undo"))
	return _done("%s: %s." % ["Redid" if redo else "Undid", label])

func _tool_render_preview(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	if not BakeJob.can_render():
		return failure(BakeJob.NEEDS_WINDOW)
	var claim := _own_job(ctx, view)
	var shown: Dictionary = await view.render_preview("dark" if args.get("time", "day") == "dusk" else "light")
	if is_instance_valid(view) and view.job_started.is_connected(claim):
		view.job_started.disconnect(claim)
	if ctx.cancelled:
		return {}
	var img: Image = shown.image
	if img == null:
		return failure("The preview was stopped in the window." if shown.error == BakeJob.CANCELLED else "Couldn't render a preview: " + shown.error)
	var small: Image = img.duplicate()
	small.resize(PREVIEW_WIDTH, int(float(PREVIEW_WIDTH) * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	var jpg: PackedByteArray = small.save_jpg_to_buffer(0.85)
	return {"content": [{"type": "image", "data": Marshalls.raw_to_base64(jpg), "mimeType": "image/jpeg"},
		{"type": "text", "text": "%s preview of the area round the Yard, without its live halls and crews." % ("Dusk" if args.get("time", "day") == "dusk" else "Day")}], "isError": false}

class Finished:
	signal ended
	var result := []
	func finish(error: String, notice: String) -> void:
		result = [error, notice]
		ended.emit()

func _tool_export_world(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var view = _editing(args)
	if view is String:
		return failure(view)
	if not BakeJob.can_render():
		return failure(BakeJob.NEEDS_WINDOW)
	var to := str(args.to).replace("\\", "/")
	var problem := export_problem(to, bool(args.get("replace", false)))
	if problem != "":
		return failure(problem)
	var finished := Finished.new()
	var started := Time.get_ticks_msec()
	var claim := _own_job(ctx, view)
	view.agent_export(to, str(args.get("quality", "final")), bool(args.get("replace", false)), finished.finish,
		func(done, total): server.progress(ctx, float(done), float(total), "Rendering: %d%%" % roundi(100.0 * done / maxf(total, 1))))
	if view.job_started.is_connected(claim):
		view.job_started.disconnect(claim)
	if finished.result.is_empty():
		await finished.ended
	var result: Array = finished.result
	if ctx.cancelled:
		return {}
	if result[0] == BakeJob.CANCELLED:
		return failure("The export was stopped in the window. Nothing was exported.")
	if result[0] != "":
		return failure("That didn't export: " + result[0])
	var size := FileAccess.get_file_as_bytes(to).size()
	return _done("Exported %s in %ds.%s" % [to.get_file(), (Time.get_ticks_msec() - started) / 1000, " " + result[1] if result[1] != "" else ""], {"path": to, "bytes": size})

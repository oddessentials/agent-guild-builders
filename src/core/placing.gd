class_name Placing
extends RefCounted
## What can be placed, alone or as a named mix, and why a spot is refused.

const SMALLEST := 0.85
const LARGEST := 1.2
const MIXES := {
	"wildflowers": {"label": "Wildflowers", "kinds": ["grass", "dandelion", "celandine", "fern"]},
	"undergrowth": {"label": "Undergrowth", "kinds": ["shrub_low", "shrub_wild", "shrub_round", "fern"]},
	"woodland": {"label": "Mixed woodland", "kinds": ["tree_oak", "tree_elm", "tree_young", "tree_fir"]},
	"rocks": {"label": "Scattered rocks", "kinds": ["stone", "stone", "boulder"]},
	"garden": {"label": "Flower garden", "kinds": ["gazania", "ursinia", "empodium", "stinkkruid"]},
	"camp": {"label": "Camp clutter", "kinds": ["crate", "crate_long", "barrel_rusty", "bucket", "basket"]},
}

const GRID := 0.5
const JOIN_REACH := 3.0
const DUPLICATE := "There's already one here. Move it a little, or turn it."
const STEEPEST := 1.0
const STEEP := "Too steep here. Smooth the ground first, or choose a flatter spot."

static func modular(kind: String) -> bool:
	return bool(WorldScene.load_kit().get("models", {}).get(kind, {}).get("modular", false))

static func joins(kind: String) -> bool:
	return bool(WorldScene.load_kit().get("models", {}).get(kind, {}).get("joins", false))

static func seated(kind: String) -> bool:
	return bool(WorldScene.load_kit().get("models", {}).get(kind, {}).get("seated", false))

static func ground_span(doc: WorldDoc, kind: String, x: float, z: float, turn: float, scale: float) -> Vector2:
	var box := WorldScene.mesh_of(kind).get_aabb()
	var span := Vector2(INF, -INF)
	for u in [0.0, 0.5, 1.0]:
		for v in [0.0, 0.5, 1.0]:
			var p := Vector2(x, z) + _turned(Vector2(box.position.x + box.size.x * u, box.position.z + box.size.z * v) * scale, turn)
			var h := doc.height_at(p.x, p.y)
			span = Vector2(minf(span.x, h), maxf(span.y, h))
	return span

static func base_height(doc: WorldDoc, t: Dictionary) -> float:
	if seated(t.kind):
		return ground_span(doc, t.kind, float(t.x), float(t.z), float(t.turn), float(t.scale)).x
	return doc.height_at(float(t.x), float(t.z))

static func _too_steep(doc: WorldDoc, kind: String, x: float, z: float, turn: float, scale: float) -> String:
	if not seated(kind):
		return ""
	var span := ground_span(doc, kind, x, z, 0.0 if is_nan(turn) else turn, scale)
	return STEEP if span.y - span.x > STEEPEST else ""

static func sizes(kind: String) -> Vector2:
	return Vector2.ONE if modular(kind) else Vector2(SMALLEST, LARGEST)

static func placement(doc: WorldDoc, kind: String, at: Vector3, turn: float, ignore_id := -1) -> Dictionary:
	if not joins(kind):
		return {"at": at, "turn": turn, "joins": ""}
	var joined := _joined(doc, kind, Vector2(at.x, at.z), ignore_id)
	if joined.is_empty():
		return {"at": on_grid(doc, kind, at), "turn": turn, "joins": ""}
	return {"at": Vector3(joined.x, doc.height_at(joined.x, joined.z), joined.z), "turn": joined.turn, "joins": joined.joins}

static func _joined(doc: WorldDoc, kind: String, pointer: Vector2, ignore_id: int) -> Dictionary:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var own: Array = models.get(kind, {}).get("joints", [])
	var placed := []
	for t in doc.data.things:
		if int(t.id) == ignore_id or not joins(t.kind):
			continue
		for j in models.get(t.kind, {}).get("joints", []):
			placed.append({"thing": t, "joint": j, "at": Vector2(float(t.x), float(t.z)) + _turned(Vector2(j[0], j[1]), float(t.turn)), "facing": _turned(Vector2(j[2], j[3]), float(t.turn))})
	var best := {}
	var best_score := INF
	for open in placed:
		var t: Dictionary = open.thing
		var j: Array = open.joint
		var at: Vector2 = open.at
		var reach := at.distance_to(pointer)
		if reach > JOIN_REACH or _taken(open, placed):
			continue
		var facing: Vector2 = open.facing
		var hand := _hand(Vector2(j[0], j[1]), Vector2(j[2], j[3]))
		for k in own:
			var k_at := Vector2(k[0], k[1])
			var k_facing := Vector2(k[2], k[3])
			var k_hand := _hand(k_at, k_facing)
			if int(k[4]) != int(j[4]) or (hand != 0.0 and k_hand != 0.0 and hand == k_hand):
				continue
			var turn := wrapf(k_facing.angle() - (-facing).angle(), 0.0, TAU)
			var spot := at - _turned(k_at, turn)
			var score := reach + 0.01 * spot.distance_to(pointer)
			if score < best_score:
				best_score = score
				best = {"x": spot.x, "z": spot.y, "turn": turn, "joins": t.kind}
	return best

static func _taken(open: Dictionary, placed: Array) -> bool:
	for other in placed:
		if other.thing.id != open.thing.id and int(other.joint[4]) == int(open.joint[4]) and other.at.distance_to(open.at) < 0.01 and other.facing.dot(open.facing) < -0.99:
			return true
	return false

static func duplicate_of(doc: WorldDoc, kind: String, x: float, z: float, turn: float, ignore_id := -1) -> bool:
	for t in doc.data.things:
		if int(t.id) != ignore_id and t.kind == kind and Vector2(float(t.x) - x, float(t.z) - z).length() < 0.01 and absf(wrapf(float(t.turn) - turn, -PI, PI)) < 0.001:
			return true
	return false

static func _turned(v: Vector2, turn: float) -> Vector2:
	var r := Vector3(v.x, 0.0, v.y).rotated(Vector3.UP, turn)
	return Vector2(r.x, r.z)

static func _hand(at: Vector2, facing: Vector2) -> float:
	var side := facing.cross(-at)
	return 0.0 if absf(side) < 0.01 else signf(side)

static func on_grid(doc: WorldDoc, kind: String, at: Vector3) -> Vector3:
	if not modular(kind):
		return at
	var x := snappedf(at.x, GRID)
	var z := snappedf(at.z, GRID)
	return Vector3(x, doc.height_at(x, z), z)

static func kinds_of(choice: String) -> Array:
	if choice.begins_with("mix:"):
		return MIXES[choice.trim_prefix("mix:")].kinds
	return [choice]

## What stands too close to (x, z) for this spacing, or "" if nothing does.
static func crowded_by(doc: WorldDoc, x: float, z: float, spacing: float) -> String:
	var limit := spacing * 0.6
	for t in doc.data.things:
		if WorldScene.gone_in(t.kind, doc.season()):
			continue
		var dx: float = float(t.x) - x
		var dz: float = float(t.z) - z
		if dx * dx + dz * dz < limit * limit:
			return t.kind
	return ""

## Why this can't go here, in plain words, or "" if it can.
static func why_not(doc: WorldDoc, kind: String, x: float, z: float, scale: float, turn := NAN) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var info: Dictionary = models.get(kind, {})
	var why := _why_not_here(doc, info, x, z, scale)
	if why == "":
		why = _too_steep(doc, kind, x, z, turn, scale)
	if why != "":
		return why
	return _too_close(models, crowded_by(doc, x, z, float(info.get("spacing", 2.0)) * scale))

static func why_not_one(doc: WorldDoc, kind: String, x: float, z: float, turn := NAN) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var why := _why_not_here(doc, models.get(kind, {}), x, z, sizes(kind).x)
	if why == "":
		why = _too_steep(doc, kind, x, z, turn, sizes(kind).x)
	if why != "":
		return why
	if not is_nan(turn) and duplicate_of(doc, kind, x, z, turn):
		return DUPLICATE
	return _too_close(models, _standing_on(doc, models, kind, x, z))

## The same question for a placed item moving to (x, z).
static func why_not_moved(doc: WorldDoc, thing: Dictionary, x: float, z: float, turn := NAN) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var turned := float(thing.turn) if is_nan(turn) else turn
	var why := _why_not_here(doc, models.get(thing.kind, {}), x, z, float(thing.scale))
	if why == "":
		why = _too_steep(doc, thing.kind, x, z, turned, float(thing.scale))
	if why != "":
		return why
	if duplicate_of(doc, thing.kind, x, z, turned, int(thing.id)):
		return DUPLICATE
	return _too_close(models, _standing_on(doc, models, thing.kind, x, z, int(thing.id)))

## The largest size that keeps the Yard clear at this spot.
static func largest_scale(doc: WorldDoc, kind: String, x: float, z: float) -> float:
	var height := float(WorldScene.load_kit().get("models", {}).get(kind, {}).get("height", 1.0))
	return (maxf(1.0, Clearance.max_elevation(x, z)) - doc.height_at(x, z) - 0.001) / height

## `rolled`, capped to the largest size that keeps the Yard clear at this spot.
static func fitted_scale(doc: WorldDoc, kind: String, x: float, z: float, rolled: float) -> float:
	var allowed := sizes(kind)
	return clampf(minf(rolled, largest_scale(doc, kind, x, z)), allowed.x, allowed.y)

## What would mostly hide this item on screen, or "" if nothing would.
static func hidden_behind(doc: WorldDoc, kind: String, x: float, z: float, scale: float) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var up := Clearance._ground_up()
	var top := doc.height_at(x, z) + float(models.get(kind, {}).get("height", 1.0)) * scale
	for t in doc.data.things:
		if WorldScene.gone_in(t.kind, doc.season()):
			continue
		var info: Dictionary = models.get(t.kind, {})
		var s := float(t.scale)
		if _covers(Vector2(x, z), top, Vector2(t.x, t.z), doc.height_at(t.x, t.z) + float(info.get("height", 1.0)) * s, float(info.get("radius", 0.5)) * s, up):
			return str(info.get("label", t.kind)).to_lower()
	var yard := Yard.data()
	for id in yard.halls:
		var at: Dictionary = yard.halls[id]
		var docker: bool = id == "docker"
		if _covers(Vector2(x, z), top, Vector2(at.x, at.z), float(yard.hall.dockerHeight if docker else yard.hall.height), float(yard.hall.docker if docker else yard.hall.half), up):
			return "hall"
	return ""

static func _covers(spot: Vector2, top: float, at: Vector2, at_top: float, radius: float, up: Vector2) -> bool:
	var off := spot - at
	var along := off.dot(up)
	return along > 0.0 and along + top * Clearance.RISE < at_top * Clearance.RISE and absf(off.dot(Vector2(-up.y, up.x))) < radius * 0.7

static func _why_not_here(doc: WorldDoc, info: Dictionary, x: float, z: float, scale: float) -> String:
	var top := doc.height_at(x, z) + float(info.get("height", 1.0)) * scale
	var why := Clearance.refuse(x, z, top)
	if why != "":
		return why
	var water := float(doc.data.water_level)
	if water > WorldDoc.NO_WATER_BELOW and top < water:
		return "This would be under the water. Choose a spot on land, or lower the water."
	return ""

static func _standing_on(doc: WorldDoc, models: Dictionary, kind: String, x: float, z: float, ignore_id := -1) -> String:
	var own := float(models.get(kind, {}).get("radius", 0.5))
	for t in doc.data.things:
		if int(t.id) == ignore_id or WorldScene.gone_in(t.kind, doc.season()) or (modular(kind) and modular(t.kind)):
			continue
		var limit := minf(own, float(models.get(t.kind, {}).get("radius", 0.5)))
		var dx: float = float(t.x) - x
		var dz: float = float(t.z) - z
		if dx * dx + dz * dz < limit * limit:
			return t.kind
	return ""

static func _too_close(models: Dictionary, near: String) -> String:
	if near == "":
		return ""
	return "Too close to the %s here. Move a little, or clear it first." % str(models.get(near, {}).get("label", near)).to_lower()

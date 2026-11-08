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

static func modular(kind: String) -> bool:
	return bool(WorldScene.load_kit().get("models", {}).get(kind, {}).get("modular", false))

static func snapped(doc: WorldDoc, kind: String, at: Vector3) -> Vector3:
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
static func why_not(doc: WorldDoc, kind: String, x: float, z: float, scale: float) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var info: Dictionary = models.get(kind, {})
	var why := _why_not_here(doc, info, x, z, scale)
	if why != "":
		return why
	return _too_close(models, crowded_by(doc, x, z, float(info.get("spacing", 2.0)) * scale))

## The same question for one chosen item: the answer depends only on the spot, and
## only an item standing on the same spot gets in the way.
static func why_not_one(doc: WorldDoc, kind: String, x: float, z: float) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var why := _why_not_here(doc, models.get(kind, {}), x, z, 1.0 if modular(kind) else SMALLEST)
	if why != "":
		return why
	return _too_close(models, _standing_on(doc, models, kind, x, z))

## The same question for a placed item moving to (x, z).
static func why_not_moved(doc: WorldDoc, thing: Dictionary, x: float, z: float) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var why := _why_not_here(doc, models.get(thing.kind, {}), x, z, float(thing.scale))
	if why != "":
		return why
	return _too_close(models, _standing_on(doc, models, thing.kind, x, z, int(thing.id)))

## The largest size that keeps the Yard clear at this spot.
static func largest_scale(doc: WorldDoc, kind: String, x: float, z: float) -> float:
	var height := float(WorldScene.load_kit().get("models", {}).get(kind, {}).get("height", 1.0))
	return (maxf(1.0, Clearance.max_elevation(x, z)) - doc.height_at(x, z) - 0.001) / height

## `rolled`, capped to the largest size that keeps the Yard clear at this spot.
static func fitted_scale(doc: WorldDoc, kind: String, x: float, z: float, rolled: float) -> float:
	if modular(kind):
		return 1.0
	return maxf(SMALLEST, minf(rolled, largest_scale(doc, kind, x, z)))

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

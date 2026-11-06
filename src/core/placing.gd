class_name Placing
extends RefCounted
## What can be placed, alone or as a named mix, and why a spot is refused.

const MIXES := {
	"wildflowers": {"label": "Wildflowers", "kinds": ["grass", "dandelion", "celandine", "fern"]},
	"undergrowth": {"label": "Undergrowth", "kinds": ["shrub_low", "shrub_wild", "shrub_round", "fern"]},
	"woodland": {"label": "Mixed woodland", "kinds": ["tree_oak", "tree_elm", "tree_young", "tree_fir"]},
	"rocks": {"label": "Scattered rocks", "kinds": ["stone", "stone", "boulder"]},
}

static func kinds_of(choice: String) -> Array:
	if choice.begins_with("mix:"):
		return MIXES[choice.trim_prefix("mix:")].kinds
	return [choice]

## What stands too close to (x, z) for this spacing, or "" if nothing does.
static func crowded_by(doc: WorldDoc, x: float, z: float, spacing: float) -> String:
	var limit := spacing * 0.6
	for t in doc.data.things:
		var dx: float = float(t.x) - x
		var dz: float = float(t.z) - z
		if dx * dx + dz * dz < limit * limit:
			return t.kind
	return ""

## Why this can't go here, in plain words, or "" if it can.
static func why_not(doc: WorldDoc, kind: String, x: float, z: float, scale: float) -> String:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var info: Dictionary = models.get(kind, {})
	var why := Clearance.refuse(x, z, doc.height_at(x, z) + float(info.get("height", 1.0)) * scale)
	if why != "":
		return why
	var near := crowded_by(doc, x, z, float(info.get("spacing", 2.0)) * scale)
	if near != "":
		return "Too close to the %s here. Move a little, or clear it first." % str(models.get(near, {}).get("label", near)).to_lower()
	return ""

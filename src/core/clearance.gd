class_name Clearance
extends RefCounted

const COURTYARD_RADIUS := 13.7
const CLEAR_MARGIN := 4.0
## How far up the screen each metre of height rises.
const RISE := 1.55
static var _terrain_limits := PackedFloat32Array()

## Metres from where halls and characters can stand: the courtyard and the rows
## in front of it (z 0 to 32).
static func live_distance(x: float, z: float) -> float:
	var ring: float = max(0.0, Vector2(x, z).length() - COURTYARD_RADIUS - 1.0)
	var dx: float = max(abs(x) - 13.0, 0.0)
	var dz: float = max(max(z - 32.0, 0.0), -z)
	return min(ring, Vector2(dx, dz).length())

## The ground direction that runs up the screen.
static func _ground_up() -> Vector2:
	var f: Array = Yard.data().basis.forward
	return Vector2(f[0], f[2]).normalized()

## Whether something `height` metres tall at (x, z) stays off the live area on
## screen.
static func tall_clear(x: float, z: float, height: float) -> bool:
	return height <= max_elevation(x, z)

static func max_elevation(x: float, z: float, margin := CLEAR_MARGIN) -> float:
	var p := Vector2(x, z)
	var up := _ground_up()
	var reach := _ray_circle(p, up, Vector2.ZERO, COURTYARD_RADIUS + 1.0 + margin)
	reach = minf(reach, _ray_rect(p, up, Vector2(-13.0, -margin), Vector2(13.0, 32.0 + margin)))
	reach = minf(reach, _ray_rect(p, up, Vector2(-13.0 - margin, 0.0), Vector2(13.0 + margin, 32.0)))
	for corner in [Vector2(-13, 0), Vector2(13, 0), Vector2(-13, 32), Vector2(13, 32)]:
		reach = minf(reach, _ray_circle(p, up, corner, margin))
	return maxf(0.0, reach / RISE - 0.01)

static func _ray_circle(p: Vector2, direction: Vector2, centre: Vector2, radius: float) -> float:
	var offset := p - centre
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var b := offset.dot(direction)
	var discriminant := b * b - c
	return -b - sqrt(discriminant) if b < 0.0 and discriminant >= 0.0 else INF

static func _ray_rect(p: Vector2, direction: Vector2, lo: Vector2, hi: Vector2) -> float:
	var near := 0.0
	var far := INF
	for axis in 2:
		if absf(direction[axis]) < 0.000001:
			if p[axis] < lo[axis] or p[axis] > hi[axis]:
				return INF
		else:
			var a := (lo[axis] - p[axis]) / direction[axis]
			var b := (hi[axis] - p[axis]) / direction[axis]
			near = maxf(near, minf(a, b))
			far = minf(far, maxf(a, b))
	return near if near <= far else INF

static func terrain_limits() -> PackedFloat32Array:
	if _terrain_limits.is_empty():
		var res := WorldDoc.TERRAIN_RES
		var margin := CLEAR_MARGIN + sqrt(2.0) * WorldDoc.TERRAIN_SIZE / (res - 1)
		_terrain_limits.resize(res * res)
		for j in res:
			for i in res:
				var p := WorldDoc.cell_to_world(i, j)
				_terrain_limits[j * res + i] = max_elevation(p.x, p.y, margin)
	return _terrain_limits

static func land_constraints(doc: WorldDoc) -> Dictionary:
	var out := {}
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var res := WorldDoc.TERRAIN_RES
	var step := WorldDoc.TERRAIN_SIZE / (res - 1)
	for thing in doc.data.things:
		var limit := maxf(1.0, max_elevation(thing.x, thing.z)) - float(models.get(thing.kind, {}).get("height", 1.0)) * float(thing.scale) - 0.001
		if is_inf(limit):
			continue
		var fx := clampf((float(thing.x) + WorldDoc.TERRAIN_SIZE / 2.0) / step, 0.0, res - 1.001)
		var fz := clampf((float(thing.z) + WorldDoc.TERRAIN_SIZE / 2.0) / step, 0.0, res - 1.001)
		var o := int(fz) * res + int(fx)
		var u := fx - int(fx)
		var v := fz - int(fz)
		for entry in [[o, (1.0 - u) * (1.0 - v)], [o + 1, u * (1.0 - v)], [o + res, (1.0 - u) * v], [o + res + 1, u * v]]:
			if entry[1] <= 0.0:
				continue
			if not out.has(entry[0]):
				out[entry[0]] = []
			out[entry[0]].append([Vector2(thing.x, thing.z), limit, entry[1]])
	return out

static func limit_land(doc: WorldDoc, index: int, requested: float, constraints: Dictionary) -> float:
	var before := doc.heights[index]
	var p := WorldDoc.cell_to_world(index % WorldDoc.TERRAIN_RES, index / WorldDoc.TERRAIN_RES)
	if must_be_flat(p.x, p.y):
		return clampf(requested, minf(before, 0.0), maxf(before, 0.0))
	if requested <= before:
		return requested
	var limit := terrain_limits()[index]
	for entry in constraints.get(index, []):
		var headroom: float = entry[1] - doc.height_at(entry[0].x, entry[0].y)
		limit = minf(limit, before + headroom / entry[2])
	return minf(requested, maxf(before, limit))

static func check_world(doc: WorldDoc) -> Dictionary:
	if doc == null or not WorldDoc._valid_data(doc.data) or doc.heights.size() != WorldDoc.TERRAIN_RES * WorldDoc.TERRAIN_RES:
		return {"valid": false, "problem": "The project data is incomplete."}
	var limits := terrain_limits()
	var land := PackedInt32Array()
	var remaining := {}
	for index in doc.heights.size():
		var p := WorldDoc.cell_to_world(index % WorldDoc.TERRAIN_RES, index / WorldDoc.TERRAIN_RES)
		var h := doc.heights[index]
		if not is_finite(h) or h > limits[index] + 0.001 or (must_be_flat(p.x, p.y) and absf(h) > 0.001):
			land.append(index)
			remaining[index] = true
	var issues := []
	for index in land:
		if not remaining.has(index):
			continue
		var cells := [index]
		remaining.erase(index)
		var at := 0
		while at < cells.size():
			var cell: int = cells[at]
			at += 1
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var x := cell % WorldDoc.TERRAIN_RES + dx
					var z := cell / WorldDoc.TERRAIN_RES + dz
					var next := z * WorldDoc.TERRAIN_RES + x
					if x >= 0 and x < WorldDoc.TERRAIN_RES and z >= 0 and z < WorldDoc.TERRAIN_RES and remaining.has(next):
						remaining.erase(next)
						cells.append(next)
		var p := WorldDoc.cell_to_world(index % WorldDoc.TERRAIN_RES, index / WorldDoc.TERRAIN_RES)
		issues.append({"kind": "land", "position": p, "message": "Land near (%.1f, %.1f) needs lowering or smoothing to keep the Yard clear." % [p.x, p.y]})
	var land_count := issues.size()
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	for thing in doc.data.things:
		var problem := ""
		if not models.has(thing.kind):
			problem = "An item is unavailable: " + str(thing.kind)
		else:
			var top := doc.height_at(thing.x, thing.z) + float(models[thing.kind].height) * float(thing.scale)
			if refuse(thing.x, thing.z, top) != "":
				problem = "%s: lower the land or clear this item to keep the Yard clear." % models[thing.kind].label
		if problem != "":
			issues.append({"kind": "item", "position": Vector2(thing.x, thing.z), "message": problem})
	var parts := []
	if land_count > 0:
		parts.append("%d %s of land" % [land_count, "area" if land_count == 1 else "areas"])
	var items := issues.size() - land_count
	if items > 0:
		parts.append("%d %s" % [items, "item" if items == 1 else "items"])
	var summary := " and ".join(parts) + (" needs" if issues.size() == 1 else " need") + " attention before export." if not issues.is_empty() else ""
	return {"valid": issues.is_empty(), "problem": summary + " " + issues[0].message if not issues.is_empty() else "", "summary": summary, "issues": issues, "land": land}

## The land must stay flat where the Yard draws live characters on the ground.
static func must_be_flat(x: float, z: float) -> bool:
	return live_distance(x, z) < 1.0

## Why something can't go here, in plain words, or "" if it can.
static func refuse(x: float, z: float, height: float) -> String:
	if live_distance(x, z) < 0.5:
		return "This is where your crews stand. Keep it clear."
	if height > 1.0 and not tall_clear(x, z, height):
		return "Too tall here: it would hide part of the Yard. Move it further out or choose something smaller."
	return ""

## Grey and alpha pixels over the whole terrain, opaque wherever something this
## tall is refused. A height of 0 maps where the land must stay flat instead.
static func mask(height: float, res: int, heights := PackedFloat32Array()) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(res * res * 2)
	var size := WorldDoc.TERRAIN_SIZE
	for j in res:
		var z := (float(j) / (res - 1) - 0.5) * size
		for i in res:
			var x := (float(i) / (res - 1) - 0.5) * size
			var elevation := 0.0
			if not heights.is_empty():
				var terrain_x := roundi(float(i) / (res - 1) * (WorldDoc.TERRAIN_RES - 1))
				var terrain_z := roundi(float(j) / (res - 1) * (WorldDoc.TERRAIN_RES - 1))
				elevation = heights[terrain_z * WorldDoc.TERRAIN_RES + terrain_x]
			var blocked := must_be_flat(x, z) if height <= 0.0 else (height > 1.0 or height + elevation > 1.0) and refuse(x, z, height + elevation) != ""
			var o := (j * res + i) * 2
			out[o] = 255
			out[o + 1] = 255 if blocked else 0
	return out

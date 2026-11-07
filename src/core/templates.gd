class_name Templates
extends RefCounted
## Starting worlds. Everyone begins from a complete, valid place and changes it.
## The same seed always gives the same world: this uses its own number generator,
## so an engine update can't quietly change what a seed means.

const LIST := {
	"blank": {"label": "Blank", "note": "Open ground and the Yard, ready for anything"},
	"island": {"label": "Island", "note": "A small island with water on every side"},
	"canyon": {"label": "Canyon", "note": "Layered cliffs behind the Yard, and a gorge before it"},
	"meadow": {"label": "Meadow", "note": "Open grass with a forest edge and hills beyond"},
	"lakeside": {"label": "Lakeside", "note": "A still lake behind the Yard, ringed by firs"},
	"highland": {"label": "Highland", "note": "Bare rock and tall hills, with little cover"},
}

const LAKE_CENTRE := Vector2(-30.0, -44.0)
const LAKE_RADII := Vector2(30.0, 17.0)

class Rng:
	## xorshift32: small, and identical on every platform.
	var state: int
	func _init(seed_value: int) -> void:
		state = (seed_value * 2654435761 + 1) & 0xffffffff
		if state == 0:
			state = 1
	func next() -> float:
		state ^= (state << 13) & 0xffffffff
		state ^= state >> 17
		state ^= (state << 5) & 0xffffffff
		return float(state) / 4294967296.0
	func range_f(a: float, b: float) -> float:
		return a + (b - a) * next()

## Smooth value noise from the same generator.
class ValueNoise:
	var grid := PackedFloat32Array()
	const SIZE := 64
	func _init(rng: Rng) -> void:
		grid.resize(SIZE * SIZE)
		for i in grid.size():
			grid[i] = rng.next()
	func at(x: float, y: float) -> float:
		var i := floori(x)
		var j := floori(y)
		var fx := x - i
		var fy := y - j
		fx = fx * fx * (3.0 - 2.0 * fx)
		fy = fy * fy * (3.0 - 2.0 * fy)
		return lerpf(lerpf(_g(i, j), _g(i + 1, j), fx), lerpf(_g(i, j + 1), _g(i + 1, j + 1), fx), fy)
	func _g(i: int, j: int) -> float:
		return grid[posmod(j, SIZE) * SIZE + posmod(i, SIZE)]
	func fbm(x: float, y: float) -> float:
		return at(x, y) * 0.55 + at(x * 2.1 + 7.0, y * 2.1 + 3.0) * 0.3 + at(x * 4.3 + 1.0, y * 4.3 + 9.0) * 0.15

static func create(template: String, base: String, title: String, seed_value: int) -> WorldDoc:
	var doc := WorldDoc.create(base, title, seed_value)
	doc.data["template"] = template
	var rng := Rng.new(seed_value)
	var noise := ValueNoise.new(rng)
	match template:
		"blank":
			_blank(doc, rng, noise)
			return doc
		"island":
			_island(doc, rng, noise)
			return doc
		"canyon":
			_canyon(doc, rng, noise)
			return doc
		"lakeside":
			_shape(doc, noise, 7.0, 34.0)
			_lake(doc, LAKE_CENTRE, LAKE_RADII, 4.0)
			doc.data.water_level = -0.6
			_above_water(doc, LAKE_CENTRE, LAKE_RADII)
			_paint(doc, noise, 22.0, 0.45)
			_frame(doc, rng, ["tree_fir"], 40)
			_scatter(doc, rng, noise, ["tree_fir"], 260, 24.0, 230.0, 0.34, 1.0)
		"highland":
			_shape(doc, noise, 22.0, 70.0)
			_paint(doc, noise, 7.0, 0.3)
			_frame(doc, rng, ["tree_fir", "boulder"], 30)
			_scatter(doc, rng, noise, ["boulder"], 170, 26.0, 230.0, 0.0, 1.6)
			_scatter(doc, rng, noise, ["tree_fir"], 70, 30.0, 230.0, 0.5, 1.0)
			doc.data.mood.light.sky = "overcast"
			doc.data.mood.dark.sky = "moon"
			doc.data.mood.dark.strength = 0.3
		_:
			_shape(doc, noise, 9.0, 40.0)
			_paint(doc, noise, 30.0, 0.5)
			_frame(doc, rng, ["tree_oak", "tree_elm", "tree_young", "tree_fir"], 44)
			_scatter(doc, rng, noise, ["tree_oak", "tree_elm", "tree_young"], 320, 22.0, 230.0, 0.36, 1.0)
			_scatter(doc, rng, noise, ["tree_fir"], 160, 60.0, 240.0, 0.42, 1.0)
	_scatter(doc, rng, noise, ["shrub_low", "shrub_wild", "shrub_round"], 420, 16.0, 150.0, 0.28, 1.0)
	_scatter(doc, rng, noise, ["grass", "fern", "dandelion", "celandine"], 2600, 15.0, 90.0, 0.18, 1.0)
	_scatter(doc, rng, noise, ["stone", "boulder"], 80, 18.0, 140.0, 0.0, 1.0)
	return doc

static func _blank(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	_shape(doc, noise, 2.5, 6.0)
	_paint(doc, noise, 1000.0, 0.62)
	_scatter(doc, rng, noise, ["stone"], 12, 18.0, 110.0, 0.0, 1.0)

static func _island(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	doc.data.water_level = -0.6
	var res := WorldDoc.TERRAIN_RES
	var limits := Clearance.terrain_limits()
	var centre := Vector2(0.0, 10.0)
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var off := p - centre
			var a := off.angle()
			var coast := 66.0 + (noise.fbm(cos(a) * 1.7 + 4.0, sin(a) * 1.7 + 6.0) - 0.5) * 54.0
			var d := off.length()
			var bump := (noise.fbm(p.x * 0.03, p.y * 0.03) - 0.35) * 5.0 * smoothstep(2.0, 22.0, Clearance.live_distance(p.x, p.y))
			var land := maxf(bump, float(doc.data.water_level) + 0.5)
			doc.heights[j * res + i] = minf(lerpf(land, -7.0, smoothstep(coast - 12.0, coast + 14.0, d)), limits[j * res + i])
	_paint(doc, noise, 30.0, 0.62, 1.2)
	_scatter(doc, rng, noise, ["tree_young", "tree_oak"], 18, 24.0, 62.0, 0.36, 1.0)
	_scatter(doc, rng, noise, ["shrub_low", "shrub_wild", "shrub_round"], 60, 16.0, 70.0, 0.3, 1.0)
	_scatter(doc, rng, noise, ["grass", "fern", "dandelion"], 300, 15.0, 70.0, 0.2, 1.0)
	_scatter(doc, rng, noise, ["stone", "boulder"], 28, 18.0, 90.0, 0.0, 1.0)

## How far past the canyon floor a point is: behind the Yard, or out to either side.
static func _canyon_reach(p: Vector2, noise: ValueNoise) -> float:
	var up := Clearance._ground_up()
	var wobble := (noise.fbm(p.x * 0.02 + 5.0, p.y * 0.02 + 2.0) - 0.5) * 18.0
	return maxf(p.dot(up) - 20.0, absf(p.dot(Vector2(-up.y, up.x))) - 27.0) + wobble

static func _canyon(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	doc.data.water_level = -11.0
	var res := WorldDoc.TERRAIN_RES
	var limits := Clearance.terrain_limits()
	var up := Clearance._ground_up()
	const LEDGE := 7.0
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var near := smoothstep(2.0, 24.0, Clearance.live_distance(p.x, p.y))
			var reach := _canyon_reach(p, noise)
			var cliff := 20.0 * smoothstep(0.0, 12.0, reach) + 34.0 * smoothstep(12.0, 52.0, reach)
			var layer := floorf(cliff / LEDGE)
			var h := (layer + smoothstep(0.0, 0.3, cliff / LEDGE - layer)) * LEDGE
			var broken := (noise.fbm(p.x * 0.06 + 3.0, p.y * 0.06) - 0.5) * 2.0
			h = (h + broken * lerpf(3.0, 12.0, smoothstep(0.0, 18.0, reach))) * near
			var gorge := absf(p.dot(up) + 62.0 + (noise.fbm(p.x * 0.015 + 9.0, p.y * 0.015) - 0.5) * 16.0)
			doc.heights[j * res + i] = minf(lerpf(h, -14.0, 1.0 - smoothstep(9.0, 22.0, gorge)), limits[j * res + i])
	_paint(doc, noise, 14.0, 0.5, 0.3, 1, 3)
	var placed := 0
	for attempt in 800:
		if placed >= 80:
			break
		var a := rng.range_f(0.0, TAU)
		var r := rng.range_f(22.0, 130.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if absf(_canyon_reach(Vector2(x, z), noise) - 6.0) < 12.0 and _try(doc, rng, "rock_face" if rng.next() < 0.6 else "rock_wall", x, z, rng.range_f(1.1, 2.0)):
			placed += 1
	_scatter(doc, rng, noise, ["boulder"], 90, 20.0, 170.0, 0.0, 1.2)
	_scatter(doc, rng, noise, ["stone"], 70, 16.0, 110.0, 0.0, 1.0)
	_scatter(doc, rng, noise, ["tree_fir", "snag"], 110, 30.0, 190.0, 0.4, 1.0)
	_scatter(doc, rng, noise, ["shrub_wild", "shrub_low", "fern"], 160, 16.0, 150.0, 0.3, 1.0)

## Gentle ground near the Yard, rising to hills, and flat wherever crews stand.
static func _shape(doc: WorldDoc, noise: ValueNoise, swell: float, hills: float) -> void:
	var res := WorldDoc.TERRAIN_RES
	var limits := Clearance.terrain_limits()
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var d := Clearance.live_distance(p.x, p.y)
			var near := smoothstep(2.0, 28.0, d)
			var far := smoothstep(60.0, 240.0, p.length())
			var h := (noise.fbm(p.x * 0.02, p.y * 0.02) - 0.5) * 2.0 * swell * near
			h += far * far * hills * noise.fbm(p.x * 0.008 + 11.0, p.y * 0.008 + 5.0)
			doc.heights[j * res + i] = minf(h, limits[j * res + i])

static func _lake(doc: WorldDoc, centre: Vector2, radii: Vector2, depth: float) -> void:
	var res := WorldDoc.TERRAIN_RES
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var e := ((p - centre) / radii).length()
			if e < 1.25 and Clearance.live_distance(p.x, p.y) > 3.0:
				var o := j * res + i
				doc.heights[o] = lerpf(doc.heights[o], -depth, 1.0 - smoothstep(0.55, 1.25, e))

static func _above_water(doc: WorldDoc, centre: Vector2, radii: Vector2) -> void:
	var res := WorldDoc.TERRAIN_RES
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			if ((p - centre) / radii).length() >= 1.25 or Clearance.live_distance(p.x, p.y) <= 3.0:
				doc.heights[o] = maxf(doc.heights[o], float(doc.data.water_level) + 0.5)

## Grass, with forest floor under the wooded parts and rock on steep or high land.
static func _paint(doc: WorldDoc, noise: ValueNoise, rock_above: float, wood_cut: float, shore := 0.3, base_kind := 0, patch_kind := 1) -> void:
	var res := WorldDoc.TERRAIN_RES
	var step := WorldDoc.TERRAIN_SIZE / (res - 1)
	for j in range(1, res - 1):
		for i in range(1, res - 1):
			var o := j * res + i
			var p := WorldDoc.cell_to_world(i, j)
			var slope := Vector2(doc.heights[o + 1] - doc.heights[o - 1], doc.heights[o + res] - doc.heights[o - res]).length() / (2.0 * step)
			var kind := base_kind
			if noise.fbm(p.x * 0.012 + 3.0, p.y * 0.012 + 8.0) > wood_cut and Clearance.live_distance(p.x, p.y) > 20.0:
				kind = patch_kind
			if doc.heights[o] > rock_above or slope > 0.55:
				kind = 2
			if doc.heights[o] < doc.data.water_level + shore and doc.data.water_level > -50.0:
				kind = 3
			doc.ground[o] = kind

## Dresses the Yard's edge: lanterns along the paving, low planting against it, and
## trees close behind, where they can't rise over the crews.
static func _frame(doc: WorldDoc, rng: Rng, tall: Array, tall_count: int) -> void:
	for i in 14:
		var a := PI * 0.62 + TAU * 0.78 * i / 13.0
		_try(doc, rng, "lantern", cos(a) * 15.6, sin(a) * 15.6, 2.0)
	for z in [8.0, 16.0, 24.0, 31.0]:
		for side in [-1.0, 1.0]:
			_try(doc, rng, "lantern", side * 14.2, z, 2.0)
	var low := ["grass", "fern", "grass", "dandelion", "celandine", "stone"]
	for i in 420:
		var kind: String = low[int(rng.next() * low.size()) % low.size()]
		var x: float
		var z: float
		if rng.next() < 0.5:
			var a := rng.range_f(0.0, TAU)
			var r := rng.range_f(15.0, 24.0)
			x = cos(a) * r
			z = sin(a) * r
		else:
			x = (1.0 if rng.next() < 0.5 else -1.0) * rng.range_f(14.5, 22.0)
			z = rng.range_f(-2.0, 38.0)
		_try(doc, rng, kind, x, z, rng.range_f(0.9, 1.5))
	var placed := 0
	var tries := 0
	var spots := []
	while placed < tall_count and tries < tall_count * 60:
		tries += 1
		var a := rng.range_f(0.0, TAU)
		var r := rng.range_f(19.0, 52.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var clash := false
		for p in spots:
			if p.distance_to(Vector2(x, z)) < 6.5:
				clash = true
				break
		if clash:
			continue
		if _try(doc, rng, tall[int(rng.next() * tall.size()) % tall.size()], x, z, rng.range_f(0.85, 1.25)):
			spots.append(Vector2(x, z))
			placed += 1

static func _try(doc: WorldDoc, rng: Rng, kind: String, x: float, z: float, s: float) -> bool:
	var height: float = float(WorldScene.load_kit().get("models", {}).get(kind, {}).get("height", 1.0)) * s
	if Clearance.refuse(x, z, doc.height_at(x, z) + height) != "":
		return false
	if float(doc.data.water_level) > -50.0 and doc.height_at(x, z) < float(doc.data.water_level) + 0.2:
		return false
	doc.add_thing(kind, x, z, rng.range_f(0.0, TAU), s)
	return true

## Places things in loose clumps, keeping every placement rule.
static func _scatter(doc: WorldDoc, rng: Rng, noise: ValueNoise, kinds: Array, count: int, inner: float, outer: float, clump: float, scale: float) -> void:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var placed := 0
	var tries := 0
	var taken := []
	while placed < count and tries < count * 40:
		tries += 1
		var a := rng.range_f(0.0, TAU)
		var r := sqrt(rng.range_f(inner * inner, outer * outer))
		var x := cos(a) * r
		var z := sin(a) * r
		if noise.fbm(x * 0.012 + 3.0, z * 0.012 + 8.0) < clump:
			continue
		var kind: String = kinds[int(rng.next() * kinds.size()) % kinds.size()]
		var info: Dictionary = models.get(kind, {})
		var s := scale * rng.range_f(0.8, 1.25)
		var height: float = float(info.get("height", 1.0)) * s
		if Clearance.refuse(x, z, doc.height_at(x, z) + height) != "":
			continue
		if doc.data.water_level > -50.0 and doc.height_at(x, z) < doc.data.water_level + 0.2:
			continue
		var spacing: float = float(info.get("spacing", 2.0)) * s
		var clash := false
		for t in taken:
			if Vector2(t.x - x, t.y - z).length() < (t.z + spacing) * 0.5:
				clash = true
				break
		if clash:
			continue
		taken.append(Vector3(x, z, spacing))
		doc.add_thing(kind, x, z, rng.range_f(0.0, TAU), s)
		placed += 1

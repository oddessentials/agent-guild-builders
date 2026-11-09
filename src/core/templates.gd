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
	"mars": {"label": "Red Planet", "note": "Rust dunes, craters and layered mesas under a butterscotch sky"},
	"moon": {"label": "Starfield Dock", "note": "A cratered moon at the edge of open space"},
	"garden": {"label": "Zen Garden", "note": "Raked gravel, koi ponds and stone lanterns under cherry blossom"},
	"volcano": {"label": "Volcanic Caldera", "note": "Black basalt above glowing rivers of lava"},
	"salt": {"label": "Salt Flats", "note": "White salt crust and turquoise brine pools below distant peaks"},
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
		"mars":
			_mars(doc, rng, noise)
			return doc
		"moon":
			_moon(doc, rng, noise)
			return doc
		"garden":
			_garden(doc, rng, noise)
			return doc
		"volcano":
			_volcano(doc, rng, noise)
			return doc
		"salt":
			_salt(doc, rng, noise)
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

## The last word on any land shape: flat where crews stand, easing out from there,
## and never high enough to hide the Yard.
static func _clear_the_yard(doc: WorldDoc) -> void:
	var res := WorldDoc.TERRAIN_RES
	var limits := Clearance.terrain_limits()
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			doc.heights[o] = minf(doc.heights[o], limits[o]) * smoothstep(2.0, 24.0, Clearance.live_distance(p.x, p.y))

static func _blank(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	_shape(doc, noise, 2.5, 6.0)
	_paint(doc, noise, 1000.0, 0.62)
	_scatter(doc, rng, noise, ["stone"], 12, 18.0, 110.0, 0.0, 1.0)

static func _island(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	doc.data.water_level = -0.6
	var res := WorldDoc.TERRAIN_RES
	var centre := Vector2(0.0, 10.0)
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var off := p - centre
			var a := off.angle()
			var coast := 66.0 + (noise.fbm(cos(a) * 1.7 + 4.0, sin(a) * 1.7 + 6.0) - 0.5) * 54.0
			var d := off.length()
			var bump := (noise.fbm(p.x * 0.03, p.y * 0.03) - 0.35) * 5.0
			var land := maxf(bump, float(doc.data.water_level) + 0.5)
			doc.heights[j * res + i] = lerpf(land, -7.0, smoothstep(coast - 12.0, coast + 14.0, d))
	_clear_the_yard(doc)
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
	var up := Clearance._ground_up()
	const LEDGE := 7.0
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var reach := _canyon_reach(p, noise)
			var cliff := 20.0 * smoothstep(0.0, 12.0, reach) + 34.0 * smoothstep(12.0, 52.0, reach)
			var layer := floorf(cliff / LEDGE)
			var h := (layer + smoothstep(0.0, 0.3, cliff / LEDGE - layer)) * LEDGE
			var broken := (noise.fbm(p.x * 0.06 + 3.0, p.y * 0.06) - 0.5) * 2.0
			h += broken * lerpf(3.0, 12.0, smoothstep(0.0, 18.0, reach))
			var gorge := absf(p.dot(up) + 62.0 + (noise.fbm(p.x * 0.015 + 9.0, p.y * 0.015) - 0.5) * 16.0)
			doc.heights[j * res + i] = lerpf(h, -14.0, 1.0 - smoothstep(9.0, 22.0, gorge))
	_clear_the_yard(doc)
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

static func _surface(doc: WorldDoc, land: String) -> void:
	doc.data["land"] = land
	doc.data.plaza = {"ground": str(WorldScene.load_kit().get("lands", {}).get(land, {}).get("plaza", "cobble"))}

static func _mood(doc: WorldDoc, light: Array, dark: Array) -> void:
	for pair in [["light", light], ["dark", dark]]:
		var m: Dictionary = doc.data.mood[pair[0]]
		m.sky = pair[1][0]
		m.strength = pair[1][1]
		m.sun_energy = pair[1][2]
		m.sun_color = pair[1][3]

static func _crater(p: Vector2, centre: Vector2, radius: float, depth: float) -> float:
	var d := p.distance_to(centre) / radius
	if d > 2.4:
		return 0.0
	var rim := depth * 0.45
	var bowl := -depth * (1.0 - d * d) if d < 1.0 else 0.0
	var lip := rim * exp(-pow((d - 1.0) / 0.22, 2.0)) + (rim * 0.5 * exp(-(d - 1.0) * 2.2) if d > 1.0 else 0.0)
	var peak := depth * 0.5 * exp(-pow(d / 0.16, 2.0)) if radius > 30.0 else 0.0
	return bowl + lip + peak

static func _ridged(noise: ValueNoise, x: float, y: float) -> float:
	var r := 1.0 - absf(noise.fbm(x, y) * 2.0 - 1.0)
	return r * r

static func _slope(doc: WorldDoc, i: int, j: int) -> float:
	var res := WorldDoc.TERRAIN_RES
	var step := WorldDoc.TERRAIN_SIZE / (res - 1)
	var l := doc.heights[j * res + maxi(i - 1, 0)]
	var r := doc.heights[j * res + mini(i + 1, res - 1)]
	var d := doc.heights[maxi(j - 1, 0) * res + i]
	var u := doc.heights[mini(j + 1, res - 1) * res + i]
	return Vector2(r - l, u - d).length() / (2.0 * step)

static func _accents(doc: WorldDoc, rng: Rng, spots: Array) -> void:
	for s in spots:
		_try(doc, rng, s[0], s[1], s[2], s[3] if s.size() > 3 else 1.0)

static func _mars(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	_surface(doc, "mars")
	_mood(doc, ["mars_day", 0.9, 2.8, [1.0, 0.93, 0.86]], ["mars_dusk", 1.3, 2.4, [0.76, 0.86, 1.0]])
	var res := WorldDoc.TERRAIN_RES
	var up := Clearance._ground_up()
	var side := Vector2(-up.y, up.x)
	var wind := Vector2(0.82, 0.57)
	var craters := [
		[Vector2(-62.0, -58.0) + Vector2(rng.range_f(-8, 8), rng.range_f(-8, 8)), rng.range_f(20.0, 26.0), 7.0],
		[Vector2(38.0, -22.0) + Vector2(rng.range_f(-4, 4), rng.range_f(-4, 4)), rng.range_f(8.0, 10.0), 3.0],
		[Vector2(-34.0, 42.0) + Vector2(rng.range_f(-4, 4), rng.range_f(-4, 4)), rng.range_f(7.0, 9.0), 2.6],
		[Vector2(rng.range_f(-160, -120), rng.range_f(60, 110)), rng.range_f(36.0, 48.0), 9.0],
		[Vector2(rng.range_f(90, 140), rng.range_f(80, 140)), rng.range_f(30.0, 40.0), 8.0],
	]
	var dunes := PackedFloat32Array()
	dunes.resize(res * res)
	var limits := Clearance.terrain_limits()
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var h := (noise.fbm(p.x * 0.009, p.y * 0.009) - 0.5) * 7.0
			var field := smoothstep(0.42, 0.62, noise.fbm(p.x * 0.012 + 7.0, p.y * 0.012 + 2.0))
			var phase := p.dot(wind) / 11.0 + noise.fbm(p.x * 0.018 + 3.0, p.y * 0.018) * 5.0
			var f := phase - floorf(phase)
			h += smoothstep(0.0, 0.72, f) * (1.0 - smoothstep(0.72, 1.0, f)) * 2.4 * field
			dunes[o] = field
			var edge := p.dot(up) - 92.0 + (noise.fbm(p.x * 0.011 + 3.0, p.y * 0.011 + 9.0) - 0.5) * 120.0 + absf(p.dot(side)) * 0.18
			var mesa := 26.0 * smoothstep(0.0, 6.0, edge) + 22.0 * smoothstep(22.0, 27.0, edge) + 16.0 * smoothstep(46.0, 50.0, edge)
			mesa += (noise.fbm(p.x * 0.05, p.y * 0.05) - 0.5) * 3.0 * smoothstep(0.0, 4.0, edge)
			var butte := smoothstep(0.73, 0.78, noise.fbm(p.x * 0.016 + 11.0, p.y * 0.016 + 4.0)) * smoothstep(120.0, 150.0, p.length())
			h = maxf(h, maxf(mesa, butte * 30.0 + h))
			for c in craters:
				h += _crater(p, c[0], c[1], c[2])
			doc.heights[o] = minf(h, limits[o])
	_clear_the_yard(doc)
	for j in range(1, res - 1):
		for i in range(1, res - 1):
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var kind := 1
			if dunes[o] > 0.5 or noise.fbm(p.x * 0.03 + 5.0, p.y * 0.03) > 0.6:
				kind = 0
			for c in craters:
				var q: Vector2 = p - c[0]
				var streak: float = q.dot(wind) / c[1]
				if q.length() < c[1] * 0.85 or (streak > 0.0 and streak < 5.0 and absf(q.dot(Vector2(-wind.y, wind.x))) < c[1] * (0.9 - streak * 0.12)):
					kind = 3
			if _slope(doc, i, j) > 0.5 or doc.heights[o] > 24.0:
				kind = 2
			doc.ground[o] = kind
	_accents(doc, rng, [["space_dish", -31.0, -9.0], ["space_shuttle", -40.0, 18.0], ["space_crane", 24.0, -40.0, 1.2], ["space_dish", 46.0, -54.0, 0.8]])
	_scatter(doc, rng, noise, ["stone"], 50, 16.0, 140.0, 0.4, 1.4)

static func _moon(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	_surface(doc, "moon")
	_mood(doc, ["orbit_day", 1.0, 4.2, [1.0, 0.98, 0.95]], ["orbit_dusk", 3.0, 2.4, [0.78, 0.86, 1.0]])
	var res := WorldDoc.TERRAIN_RES
	var up := Clearance._ground_up()
	var craters := []
	for k in 26:
		var a := rng.range_f(0.0, TAU)
		var radius := rng.range_f(4.0, 16.0) * (1.6 if k < 4 else 1.0)
		craters.append([Vector2(cos(a), sin(a)) * rng.range_f(30.0, 200.0), radius, radius * 0.32])
	craters.append([up * 70.0 + Vector2(rng.range_f(-10, 10), rng.range_f(-10, 10)), 26.0, 9.0])
	var limits := Clearance.terrain_limits()
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var behind := p.dot(up)
			var a := p.angle()
			var edge := 24.0 + (noise.fbm(cos(a) * 2.2 + 4.0, sin(a) * 2.2 + 6.0) - 0.5) * 22.0 + maxf(behind, 0.0) * 1.1
			var h := (noise.fbm(p.x * 0.015, p.y * 0.015) - 0.5) * 3.0
			h += smoothstep(30.0, 110.0, behind) * 30.0 * _ridged(noise, p.x * 0.012 + 2.0, p.y * 0.012)
			for c in craters:
				h += _crater(p, c[0], c[1], c[2])
			var out := smoothstep(edge, edge + 9.0, Clearance.live_distance(p.x, p.y) + (noise.fbm(p.x * 0.08, p.y * 0.08) - 0.5) * 6.0)
			h = lerpf(h, -96.0 + floorf(out * 4.0) * 1.5, pow(out, 0.6))
			doc.heights[o] = minf(h, limits[o])
	_clear_the_yard(doc)
	for j in range(1, res - 1):
		for i in range(1, res - 1):
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var kind := 0
			for c in craters:
				var dd: float = p.distance_to(c[0]) / c[1]
				if dd > 1.0 and dd < 1.9 and noise.fbm(p.x * 0.06, p.y * 0.06) > 0.45:
					kind = 1
			if noise.fbm(p.x * 0.02 + 8.0, p.y * 0.02 + 1.0) > 0.62:
				kind = 1
			if _slope(doc, i, j) > 0.45:
				kind = 2
			if doc.heights[o] < -40.0:
				kind = 3
			doc.ground[o] = kind
	_accents(doc, rng, [["space_crane", -34.0, -14.0, 1.3], ["space_crane", 36.0, -30.0, 1.3], ["space_shuttle", -36.0, 14.0, 1.2],
		["space_dish", 28.0, -54.0], ["space_dish", -56.0, -40.0, 0.8]])
	_scatter(doc, rng, noise, ["moon_boulder"], 70, 18.0, 160.0, 0.35, 1.2)
	_scatter(doc, rng, noise, ["moon_rock"], 260, 15.0, 120.0, 0.3, 1.3)

static func _garden(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	_surface(doc, "garden")
	_mood(doc, ["overcast", 0.9, 3.1, [1.0, 0.92, 0.8]], ["dusk", 0.5, 2.3, [1.0, 0.56, 0.3]])
	doc.data.water_level = -0.45
	var res := WorldDoc.TERRAIN_RES
	var up := Clearance._ground_up()
	var ponds := [[Vector2(-36.0, 20.0), Vector2(11.0, 7.0)], [Vector2(30.0, -32.0), Vector2(15.0, 10.0)], [Vector2(-70.0, -60.0), Vector2(22.0, 14.0)]]
	for pond in ponds:
		pond[0] += Vector2(rng.range_f(-4, 4), rng.range_f(-4, 4))
	var peak := up * rng.range_f(190.0, 220.0) + Vector2(rng.range_f(-30, 30), 0.0)
	var limits := Clearance.terrain_limits()
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var h := (noise.fbm(p.x * 0.02, p.y * 0.02) - 0.5) * 2.0
			h += smoothstep(40.0, 150.0, p.dot(up)) * 26.0 * noise.fbm(p.x * 0.01 + 4.0, p.y * 0.01)
			h += 95.0 * pow(maxf(0.0, 1.0 - p.distance_to(peak) / 120.0), 1.6)
			for pond in ponds:
				var e: float = ((p - pond[0]) / pond[1]).length() + (noise.fbm(p.x * 0.08, p.y * 0.08) - 0.5) * 0.5
				if e < 1.3:
					h = lerpf(h, -2.2, 1.0 - smoothstep(0.7, 1.3, e))
			doc.heights[o] = minf(h, limits[o])
	_clear_the_yard(doc)
	_above_water_except(doc, ponds)
	for j in range(1, res - 1):
		for i in range(1, res - 1):
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var kind := 0
			var wobble := (noise.fbm(p.x * 0.05 + 3.0, p.y * 0.05 + 7.0) - 0.5) * 6.0
			var ring := Clearance.live_distance(p.x, p.y) + wobble
			var shore := INF
			for pond in ponds:
				shore = minf(shore, (((p - pond[0]) / pond[1]).length() - 1.0) * pond[1].x)
			if (ring > 2.5 and ring < 13.0) or (shore + wobble * 0.5 > 0.0 and shore + wobble * 0.5 < 5.0):
				kind = 1
			if doc.heights[o] < doc.data.water_level + 0.12:
				kind = 3
			if _slope(doc, i, j) > 0.5:
				kind = 2
			doc.ground[o] = kind
	for k in 10:
		var a := PI * 0.55 + TAU * 0.8 * k / 9.0
		_try(doc, rng, "stone_lantern", cos(a) * 17.5, sin(a) * 17.5, 1.0)
	for pond in ponds:
		for k in 4:
			var a := rng.range_f(0.0, TAU)
			_try(doc, rng, "stone_lantern", pond[0].x + cos(a) * (pond[1].x + 3.0), pond[0].y + sin(a) * (pond[1].y + 3.0), 1.0)
	_garden_islands(doc, rng, noise)
	_scatter(doc, rng, noise, ["tree_blossom"], 9, 19.0, 55.0, 0.3, 0.9)
	_scatter(doc, rng, noise, ["tree_blossom"], 16, 55.0, 160.0, 0.4, 1.0)
	_scatter(doc, rng, noise, ["tree_fir"], 160, 30.0, 230.0, 0.45, 0.85)
	_scatter(doc, rng, noise, ["shrub_round"], 120, 15.0, 80.0, 0.3, 1.2)
	_scatter(doc, rng, noise, ["fern", "grass"], 300, 15.0, 70.0, 0.3, 1.0)

static func _garden_islands(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	var placed := 0
	for attempt in 600:
		if placed >= 9:
			return
		var a := rng.range_f(0.0, TAU)
		var r := rng.range_f(16.0, 40.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if doc.ground[_cell(x, z)] != 1:
			continue
		if _try(doc, rng, "moon_boulder", x, z, rng.range_f(0.6, 0.9)):
			placed += 1
			for k in 2:
				_try(doc, rng, "moon_rock", x + rng.range_f(-2.5, 2.5), z + rng.range_f(-2.5, 2.5), rng.range_f(0.8, 1.3))

static func _cell(x: float, z: float) -> int:
	var step := WorldDoc.TERRAIN_SIZE / (WorldDoc.TERRAIN_RES - 1)
	var i := clampi(roundi((x + WorldDoc.TERRAIN_SIZE / 2.0) / step), 0, WorldDoc.TERRAIN_RES - 1)
	var j := clampi(roundi((z + WorldDoc.TERRAIN_SIZE / 2.0) / step), 0, WorldDoc.TERRAIN_RES - 1)
	return j * WorldDoc.TERRAIN_RES + i

static func _above_water_except(doc: WorldDoc, basins: Array) -> void:
	var res := WorldDoc.TERRAIN_RES
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var inside := false
			for b in basins:
				if ((p - b[0]) / b[1]).length() < 1.35:
					inside = true
			if not inside:
				var o := j * res + i
				doc.heights[o] = maxf(doc.heights[o], float(doc.data.water_level) + 0.3)

static func _volcano(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	_surface(doc, "volcano")
	_mood(doc, ["haze", 0.9, 2.6, [1.0, 0.82, 0.64]], ["fire", 0.8, 2.0, [1.0, 0.45, 0.22]])
	const LAVA := -3.0
	var res := WorldDoc.TERRAIN_RES
	var up := Clearance._ground_up()
	var lake := Vector2(52.0, -50.0) + Vector2(rng.range_f(-6, 6), rng.range_f(-6, 6))
	var course := [lake, Vector2(40.0, -12.0), Vector2(rng.range_f(30, 36), 22.0), Vector2(8.0, rng.range_f(46, 52)), Vector2(-34.0, rng.range_f(52, 60)), Vector2(-90.0, 46.0), Vector2(-170.0, 74.0), Vector2(-270.0, 60.0)]
	var cones := []
	for k in 5:
		cones.append([up.rotated(rng.range_f(-1.1, 1.1)) * rng.range_f(70.0, 150.0), rng.range_f(18.0, 30.0), rng.range_f(10.0, 22.0)])
	var limits := Clearance.terrain_limits()
	var molten := PackedFloat32Array()
	molten.resize(res * res)
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var h := (noise.fbm(p.x * 0.02, p.y * 0.02) - 0.5) * 4.0
			h += smoothstep(25.0, 90.0, p.dot(up)) * 18.0 * noise.fbm(p.x * 0.015 + 5.0, p.y * 0.015)
			h += _ridged(noise, p.x * 0.03 + 1.0, p.y * 0.03 + 6.0) * 7.0 * smoothstep(22.0, 40.0, Clearance.live_distance(p.x, p.y))
			h += smoothstep(150.0, 205.0, p.distance_to(up * 30.0) + (noise.fbm(p.x * 0.01, p.y * 0.01) - 0.5) * 60.0) * 85.0
			for c in cones:
				var d: float = p.distance_to(c[0]) / c[1]
				if d < 1.0:
					h = maxf(h, c[2] * (1.0 - d) - (c[2] * 0.5 * (1.0 - d / 0.3) if d < 0.3 else 0.0))
			var river := INF
			for k in course.size() - 1:
				river = minf(river, _to_segment(p, course[k], course[k + 1]))
			river += (noise.fbm(p.x * 0.03, p.y * 0.03) - 0.5) * 8.0
			var width := 5.0 + noise.fbm(p.x * 0.02 + 9.0, p.y * 0.02) * 6.0
			var lava := 1.0 - smoothstep(width, width + 5.0, river)
			var e := ((p - lake) / Vector2(24.0, 17.0)).length() + (noise.fbm(p.x * 0.05, p.y * 0.05) - 0.5) * 0.4
			lava = maxf(lava, 1.0 - smoothstep(0.9, 1.25, e)) * smoothstep(4.0, 10.0, Clearance.live_distance(p.x, p.y))
			molten[o] = lava
			doc.heights[o] = minf(lerpf(h, LAVA, lava), limits[o])
	_clear_the_yard(doc)
	for j in range(1, res - 1):
		for i in range(1, res - 1):
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var h := doc.heights[o]
			var kind := 0
			var cone := false
			for c in cones:
				cone = cone or p.distance_to(c[0]) < c[1] * 1.15
			if (noise.fbm(p.x * 0.04 + 2.0, p.y * 0.04) > 0.66 and Clearance.live_distance(p.x, p.y) > 30.0) or molten[o] > 0.05 or cone:
				kind = 1
			if _slope(doc, i, j) > 0.42 and molten[o] < 0.5:
				kind = 2
			if molten[o] > 0.6:
				kind = 3
				doc.heights[o] = minf(h, LAVA)
			doc.ground[o] = kind
	_scatter(doc, rng, noise, ["trunk_old", "stump_old"], 60, 24.0, 200.0, 0.4, 1.2)
	_scatter(doc, rng, noise, ["boulder", "stone"], 120, 18.0, 150.0, 0.3, 1.0)

static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0))

static func _salt(doc: WorldDoc, rng: Rng, noise: ValueNoise) -> void:
	_surface(doc, "salt")
	_mood(doc, ["clear", 0.9, 3.6, [1.0, 0.97, 0.92]], ["sunset", 0.45, 2.8, [1.0, 0.55, 0.4]])
	doc.data.water_level = -0.12
	var res := WorldDoc.TERRAIN_RES
	var up := Clearance._ground_up()
	var hills := [[up.rotated(rng.range_f(0.5, 0.8)) * rng.range_f(58.0, 70.0), 13.0, 9.0], [up.rotated(rng.range_f(-0.9, -0.6)) * rng.range_f(62.0, 76.0), 10.0, 7.0]]
	for k in 4:
		var a := rng.range_f(0.0, TAU)
		hills.append([Vector2(cos(a), sin(a)) * rng.range_f(90.0, 150.0), rng.range_f(10.0, 18.0), rng.range_f(6.0, 12.0)])
	var limits := Clearance.terrain_limits()
	for j in res:
		for i in res:
			var p := WorldDoc.cell_to_world(i, j)
			var o := j * res + i
			var dry := smoothstep(0.44, 0.56, noise.fbm(p.x * 0.03, p.y * 0.03))
			var h := lerpf(-0.95, -0.04, dry)
			var reach := p.dot(up) + (noise.fbm(p.x * 0.012 + 6.0, p.y * 0.012) - 0.5) * 70.0
			h += smoothstep(80.0, 170.0, reach) * 95.0 * _ridged(noise, p.x * 0.011 + 3.0, p.y * 0.011 + 1.0)
			h += smoothstep(195.0, 255.0, p.length()) * 55.0 * _ridged(noise, p.x * 0.014 + 9.0, p.y * 0.014 + 4.0)
			for hill in hills:
				var d: float = p.distance_to(hill[0]) / hill[1]
				var crag := _ridged(noise, p.x * 0.09 + 5.0, p.y * 0.09 + 2.0)
				d += (noise.fbm(p.x * 0.07, p.y * 0.07) - 0.5) * 0.5
				if d < 1.0:
					h = maxf(h, hill[2] * pow(1.0 - d, 0.7) * (0.45 + crag * 1.1))
			doc.heights[o] = minf(h, limits[o])
	_clear_the_yard(doc)
	for j in range(1, res - 1):
		for i in range(1, res - 1):
			var o := j * res + i
			var h := doc.heights[o]
			var kind := 0
			if h < -0.1:
				kind = 1
			if h > 0.25:
				kind = 3
			if _slope(doc, i, j) > 0.3 or h > 1.2:
				kind = 2
			doc.ground[o] = kind
	_scatter(doc, rng, noise, ["stone"], 30, 20.0, 120.0, 0.4, 1.0)

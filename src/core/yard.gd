class_name Yard
extends RefCounted
## The Yard's fixed facts, from data/yard_layout.json (tools/gen_layout.mjs):
## its camera, sun, hall places and the plate tile grid every world fills.

const MAX_TILE := 4096
const THEMES := ["light", "dark"]
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/yard_layout.json"))
	return _data

static func axes() -> Dictionary:
	var b: Dictionary = data().basis
	return {"right": _v(b.right), "up": _v(b.up), "forward": _v(b.forward)}

static func sun(theme: String) -> Vector3:
	return _v(data().sun[theme])

static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

## A ground point in view-plane coordinates, as the renderer places plates.
static func to_plate(p: Vector3) -> Vector2:
	var a := axes()
	return Vector2(p.dot(a.right), p.dot(a.up))

## The layers every world's plates fill: name, pixels per unit, and the
## view-plane rectangle each covers.
static func layers() -> Array:
	var d := data()
	var cam: Dictionary = d.camera
	var a := axes()
	var half: float = cam.height / 2.0
	var pan: Dictionary = cam.pan
	var y: float = cam.target[1]
	var corners := []
	for x in [pan.minX, pan.maxX]:
		for z in [pan.minZ, pan.maxZ]:
			corners.append(Vector3(x, y, z))
	var detail := _around(corners, a, half * 16.0 / 9.0, half)
	var live := []
	for x in [-14.0, 14.0]:
		for z in [-14.0, 22.0]:
			live.append(Vector3(x, 0, z))
	var close := _around(live, a, 2.0, 0.0)
	close.up[1] += 6.0
	close.up[0] -= 2.0
	return [
		{"name": "base", "density": 20.0, "right": d.extent.right, "up": d.extent.up},
		{"name": "detail", "density": 40.0, "right": detail.right, "up": detail.up},
		{"name": "close", "density": 80.0, "right": close.right, "up": close.up},
	]

static func _around(points: Array, a: Dictionary, half_w: float, half_h: float) -> Dictionary:
	var r := []
	var u := []
	for p in points:
		r.append(p.dot(a.right))
		u.append(p.dot(a.up))
	return {"right": [r.min() - half_w, r.max() + half_w], "up": [u.min() - half_h, u.max() + half_h]}

## A rectangle's tiles on a whole-pixel grid.
static func tiles(layer: Dictionary) -> Array:
	var out := []
	var density: float = layer.density
	var right: Array = layer.right
	var up: Array = layer.up
	var width := ceili((right[1] - right[0]) * density)
	var height := ceili((up[1] - up[0]) * density)
	var cols := ceili(float(width) / MAX_TILE)
	var rows := ceili(float(height) / MAX_TILE)
	var tw := ceili(float(width) / cols)
	var th := ceili(float(height) / rows)
	for row in rows:
		for col in cols:
			var r0: float = right[0] + col * tw / density
			var u1: float = up[1] - row * th / density
			out.append({"name": "%s-%d-%d" % [layer.name, col, row], "density": density, "width": tw, "height": th,
				"right": [r0, r0 + tw / density], "up": [u1 - th / density, u1]})
	return out

## plates.json for one set of tiles, in the form the Yard reads.
static func manifest(prefix: String) -> Dictionary:
	var d := data()
	var themes := {}
	for theme in THEMES:
		var list := []
		for layer in layers():
			var tiles_out := []
			for t in tiles(layer):
				tiles_out.append({"file": "%s/%s-%s.webp" % [prefix, theme, t.name], "right": t.right, "up": t.up, "width": t.width, "height": t.height})
			list.append({"name": layer.name, "density": layer.density, "tiles": tiles_out})
		themes[theme] = list
	return {"camera": d.camera, "sun": d.sun, "themes": themes}

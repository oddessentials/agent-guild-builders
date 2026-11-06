class_name BakeSky
extends RefCounted
## Splits a sky image the way the light really arrives: a compact bright source
## (a sun or moon disk painted into the picture) becomes a shadow-casting light,
## and the rest is sampled over the hemisphere. Skies are equirectangular, in
## Blender's layout, so the shipped worlds' HDRIs behave as they do in Cycles.

const CUT := 200.0
const PEAK_ANGLE := 1.0 # degrees of softness on the sky's own disk

var image: Image
var original: Image
var strength := 1.0
## Direction to the source (glTF axes), and its irradiance, or none.
var source_dir := Vector3.ZERO
var source_rgb := Color.BLACK

static func direction(u: float, v: float) -> Vector3:
	var theta := v * PI
	var phi := (0.5 - u) * TAU
	var bx := sin(theta) * cos(phi)
	var by := sin(theta) * sin(phi)
	var bz := cos(theta)
	return Vector3(bx, bz, -by)

static func uv(d: Vector3) -> Vector2:
	var bx := d.x
	var by := -d.z
	var bz := d.y
	return Vector2(0.5 - atan2(by, bx) / TAU, acos(clampf(bz, -1.0, 1.0)) / PI)

## Loads an HDR image and takes the bright source out of it.
static func from_file(path: String, sky_strength: float) -> BakeSky:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBF)
	var sky := BakeSky.new()
	sky.image = img
	sky.original = img.duplicate()
	sky.strength = sky_strength
	sky._split()
	return sky

func _split() -> void:
	var w := image.get_width()
	var h := image.get_height()
	var sum := Vector3.ZERO
	var rgb := Vector3.ZERO
	var data := image.get_data().to_float32_array()
	for y in h:
		var solid := sin((y + 0.5) / h * PI) * (PI / h) * (TAU / w)
		for x in w:
			var o := (y * w + x) * 3
			var l: float = (data[o] + data[o + 1] + data[o + 2]) / 3.0
			if l > CUT:
				var d := direction((x + 0.5) / w, (y + 0.5) / h)
				sum += d * l * solid
				rgb += Vector3(data[o], data[o + 1], data[o + 2]) * solid
				var k := CUT / l
				data[o] *= k
				data[o + 1] *= k
				data[o + 2] *= k
	if sum.length() > 0.0:
		source_dir = sum.normalized()
		source_rgb = Color(rgb.x * strength, rgb.y * strength, rgb.z * strength)
		image = Image.create_from_data(w, h, false, Image.FORMAT_RGBF, data.to_byte_array())

## The sky's radiance towards `d`, averaged over a patch, scaled by strength.
func radiance(d: Vector3, patch: int) -> Color:
	var w := image.get_width()
	var h := image.get_height()
	var p := uv(d)
	var px := int(p.x * w)
	var py := int(p.y * h)
	var c := Color(0, 0, 0)
	var n := 0
	var step := maxi(1, patch / 4)
	for ky in range(-patch, patch + 1, step):
		for kx in range(-patch, patch + 1, step):
			var q := image.get_pixel(posmod(px + kx, w), clampi(py + ky, 0, h - 1))
			c.r += q.r
			c.g += q.g
			c.b += q.b
			n += 1
	return Color(c.r / n * strength, c.g / n * strength, c.b / n * strength)

func average_color() -> Color:
	var data := image.get_data().to_float32_array()
	var sum := Vector3.ZERO
	var n := data.size() / 3
	for i in n:
		sum += Vector3(data[i * 3], data[i * 3 + 1], data[i * 3 + 2])
	return Color(sum.x / n, sum.y / n, sum.z / n)

## The image the reflection pass sees, source removed, strength applied.
func reflection_image() -> Image:
	var data := image.get_data().to_float32_array()
	for i in data.size():
		data[i] *= strength
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBF, data.to_byte_array())

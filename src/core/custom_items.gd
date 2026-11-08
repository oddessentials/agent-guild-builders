class_name CustomItems
extends RefCounted
## Models and pictures people upload, kept only on this computer in
## user://custom/<id>/ and placed as kinds named custom:<id>.

const PREFIX := "custom:"
const GROUP := "custom"
const ITEM_FILE := "item.json"
const THUMB := "thumb.webp"
const MB := 1024 * 1024
const MODEL_BYTES := 50 * MB
const MODEL_TRIANGLES := 150000
const MODEL_SUGGESTED := 60000
const IMAGE_BYTES := 20 * MB
const LARGEST_PICTURE := 8192
const TEXTURE_SIDE := 2048
const WIDEST_SHAPE := 4.0
const MOST_ENTRIES := 65536
const NAME_FITS := "Giant gold bauble"
const NAME_FONT_SIZE := 13
const LONGEST_NAME := 40
const LOWEST := 0.1
const TALLEST := 40.0
const DISPLAYS := {"sign": "Sign board", "banner": "Banner"}
const DISPLAY_HEIGHT := {"sign": 2.0, "banner": 3.0}
const UPRIGHTS := {"": "As made", "x90": "Tip forward (X +90°)", "x-90": "Tip back (X −90°)", "z90": "Roll left (Z +90°)", "z-90": "Roll right (Z −90°)"}
const MODEL_RULES := [
	"One .glb file (glTF 2.0 binary), 50 MB or less.",
	"Up to 150,000 triangles. Over 60,000 works, but slows the editor.",
	"No Draco or meshopt compression.",
	"Everything inside the file: no separate .bin or texture files.",
	"Textures up to 8,192 px. Larger than 2,048 px are scaled down to 2,048.",
	"It stands still: animations and rigs are ignored.",
]
const IMAGE_RULES := [
	"A PNG, JPG or WebP picture, 20 MB or less.",
	"Up to 8,192 px on each side. It's scaled down to 2,048 px.",
	"No wider or taller than 4 to 1. The sign or banner takes the picture's shape.",
]
const SHARED_RULES := [
	"A name short enough to fit its button.",
	"Confirm you made it or have the rights to use it.",
]
const BLOCKED_EXTENSIONS := {
	"KHR_draco_mesh_compression": "Draco mesh compression",
	"EXT_meshopt_compression": "meshopt compression",
	"KHR_meshopt_compression": "meshopt compression",
}
const COMPONENT_BYTES := {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
const TYPE_COMPONENTS := {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
const GLB_MAGIC := 0x46546C67
const CHUNK_JSON := 0x4E4F534A
const CHUNK_BIN := 0x004E4942

static var root_override := ""

static func root() -> String:
	return root_override if root_override != "" else OS.get_user_data_dir().path_join("custom")

static func is_custom(kind: String) -> bool:
	return kind.begins_with(PREFIX)

static func id_of(kind: String) -> String:
	return kind.trim_prefix(PREFIX)

static func folder(id: String) -> String:
	return root().path_join(id)

static func thumb_path(kind: String) -> String:
	return folder(id_of(kind)).path_join(THUMB)

static func valid_id(id: String) -> bool:
	return id.is_valid_identifier()

static func item(kind: String) -> Dictionary:
	var file := folder(id_of(kind)).path_join(ITEM_FILE)
	if not is_custom(kind) or not valid_id(id_of(kind)) or not FileAccess.file_exists(file):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not parsed is Dictionary or not _valid_item(parsed, id_of(kind)):
		return {}
	return parsed

static func _valid_item(d: Dictionary, id: String) -> bool:
	if d.get("id") != id or d.get("type") not in ["model", "image"] or not d.get("label") is String or name_problem(d.label) != "":
		return false
	for key in ["height", "radius"]:
		if not WorldDoc._number(d.get(key)) or float(d[key]) <= 0.0:
			return false
	if d.type == "image" and d.get("display") not in DISPLAYS:
		return false
	if d.type == "model" and d.get("upright", "") not in UPRIGHTS:
		return false
	return d.get("source") is String and d.source.is_valid_filename() and FileAccess.file_exists(folder(id).path_join(d.source))

## Every upload as kit entries, ready to merge into the kit's models.
static func models() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(root()):
		return out
	for id in DirAccess.get_directories_at(root()):
		var kind: String = PREFIX + id
		var info := item(kind)
		if not info.is_empty():
			out[kind] = entry(info)
	return out

static func entry(info: Dictionary) -> Dictionary:
	var radius := float(info.radius)
	var made := {"label": info.label, "group": GROUP, "height": float(info.height), "radius": radius,
		"spacing": maxf(1.0, snappedf(radius * 2.0, 0.5)), "triangles": int(info.get("triangles", 0)),
		"licence": "Uploaded on this computer", "custom": info.type,
		"bytes": int(info.get("bytes", 1))}
	if info.get("seated", false):
		made.seated = true
	return made

## Things in this world whose upload isn't on this computer.
static func missing_in(doc: WorldDoc) -> Array:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	return doc.data.things.filter(func(t): return is_custom(t.kind) and not models.has(t.kind))

## Saved worlds that place this kind, by title.
static func worlds_using(kind: String, skip_path := "") -> Array:
	var out := []
	for w in WorldLibrary.list():
		if skip_path != "" and w.path.simplify_path() == skip_path.simplify_path():
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(w.path.path_join("world.json")))
		if parsed is Dictionary and parsed.get("things") is Array and parsed.things.any(func(t): return t is Dictionary and t.get("kind") == kind):
			out.append(w.title)
	return out

static func _font() -> Font:
	return ProTheme.text_font()

## Why this name can't be used, or "" if it can.
static func name_problem(label: String) -> String:
	var text := label.strip_edges()
	if text == "":
		return "Give it a name."
	var room := _font().get_string_size(NAME_FITS, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x
	if text.length() <= LONGEST_NAME and _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x <= room:
		return ""
	var fits := mini(text.length(), LONGEST_NAME)
	while fits > 0 and _font().get_string_size(text.left(fits), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x > room:
		fits -= 1
	var over := text.length() - fits
	return "Name too long for its button: shorten it by %d %s." % [over, "letter" if over == 1 else "letters"]

static func number(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out

static func megabytes(bytes: int) -> String:
	return "%.1f MB" % (bytes / float(MB))

static func _too_large(bytes: int, limit: int) -> String:
	return "Too large: %s, %s over the %d MB limit." % [megabytes(bytes), megabytes(bytes - limit), limit / MB]

## The picture's size from its header, without decoding it.
static func picture_size(b: PackedByteArray) -> Vector2i:
	if b.size() >= 24 and b.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return Vector2i((b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19], (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23])
	if b.size() >= 30 and b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
		return WorldPackage._webp_size(b)
	if b.size() >= 4 and b[0] == 0xFF and b[1] == 0xD8:
		var at := 2
		while at + 9 < b.size():
			if b[at] != 0xFF:
				return Vector2i.ZERO
			var marker := b[at + 1]
			if marker == 0xFF:
				at += 1
				continue
			if marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7):
				at += 2
				continue
			var length := (b[at + 2] << 8) | b[at + 3]
			if marker >= 0xC0 and marker <= 0xCF and marker not in [0xC4, 0xC8, 0xCC]:
				return Vector2i((b[at + 7] << 8) | b[at + 8], (b[at + 5] << 8) | b[at + 6])
			if length < 2:
				return Vector2i.ZERO
			at += 2 + length
	return Vector2i.ZERO

static func picture_kind(b: PackedByteArray) -> String:
	if b.size() >= 8 and b.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return "png"
	if b.size() >= 12 and b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	if b.size() >= 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF:
		return "jpg"
	return ""

static func _too_big_picture(what: String, size: Vector2i) -> String:
	var over := maxi(size.x, size.y) - LARGEST_PICTURE
	return "%s is %s × %s px, %s px over the %s px limit." % [what, number(size.x), number(size.y), number(over), number(LARGEST_PICTURE)]

## The parts of a .glb: {json, bin, error}. Nothing in it is trusted.
static func glb_parts(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 20:
		return {"error": "Not a .glb file: it's too short to hold a glTF binary header."}
	if bytes.decode_u32(0) != GLB_MAGIC:
		return {"error": "Not a .glb file: it doesn't start with the glTF binary header. Export it as glTF Binary (.glb)."}
	if bytes.decode_u32(4) != 2:
		return {"error": "Unsupported glTF version %d. Export it as glTF 2.0." % bytes.decode_u32(4)}
	var length := bytes.decode_u32(8)
	if length != bytes.size():
		var gap := absi(bytes.size() - length)
		return {"error": "Damaged .glb: its header says %s bytes, but the file has %s (%s %s)." % [number(length), number(bytes.size()), number(gap), "bytes missing" if bytes.size() < length else "extra bytes"]}
	var at := 12
	var json_text := ""
	var bin := PackedByteArray()
	var has_bin := false
	var index := 0
	while at < bytes.size():
		if at + 8 > bytes.size():
			return {"error": "Damaged .glb: chunk %d's header is cut off." % index}
		var size := bytes.decode_u32(at)
		var type := bytes.decode_u32(at + 4)
		if at + 8 + size > bytes.size():
			return {"error": "Damaged .glb: chunk %d runs %s bytes past the end of the file." % [index, number(at + 8 + size - bytes.size())]}
		if index == 0:
			if type != CHUNK_JSON:
				return {"error": "Damaged .glb: it doesn't begin with its JSON chunk."}
			json_text = bytes.slice(at + 8, at + 8 + size).get_string_from_utf8()
		elif index == 1 and type == CHUNK_BIN:
			bin = bytes.slice(at + 8, at + 8 + size)
			has_bin = true
		at += 8 + size
		index += 1
	if index == 0:
		return {"error": "Damaged .glb: it has no JSON chunk."}
	var parser := JSON.new()
	if parser.parse(json_text) != OK or not parser.data is Dictionary:
		var why := parser.get_error_message() if parser.get_error_message() != "" else "it isn't an object"
		return {"error": "Damaged .glb: its JSON can't be read (line %d: %s)." % [parser.get_error_line(), why]}
	return {"json": parser.data, "bin": bin, "has_bin": has_bin, "error": ""}

static func _int(v: Variant, lowest := 0) -> bool:
	return WorldDoc._integer(v) and int(v) >= lowest

static func _list(json: Dictionary, key: String) -> Variant:
	var v = json.get(key, [])
	return v if v is Array and v.size() <= MOST_ENTRIES and v.all(func(e): return e is Dictionary) else null

## Checks a .glb's structure and counts before Godot reads it:
## {error, warning, triangles}.
static func check_glb(bytes: PackedByteArray) -> Dictionary:
	var out := {"error": "", "warning": "", "triangles": 0}
	if bytes.size() > MODEL_BYTES:
		out.error = _too_large(bytes.size(), MODEL_BYTES)
		return out
	var parts := glb_parts(bytes)
	if parts.error != "":
		out.error = parts.error
		return out
	out.error = _glb_problem(parts.json, parts.bin, parts.has_bin, out)
	if out.error == "":
		if out.triangles > MODEL_TRIANGLES:
			out.error = "Too many triangles: %s, %s over the %s limit. Simplify it (Decimate in Blender) and export it again." % [number(out.triangles), number(out.triangles - MODEL_TRIANGLES), number(MODEL_TRIANGLES)]
		elif out.triangles == 0:
			out.error = "Nothing to show: this file has no triangles."
		elif out.triangles > MODEL_SUGGESTED:
			out.warning = "Heavy model: %s triangles, %s over the %s we suggest. It works, but many copies slow the editor." % [number(out.triangles), number(out.triangles - MODEL_SUGGESTED), number(MODEL_SUGGESTED)]
	return out

static func _glb_problem(json: Dictionary, bin: PackedByteArray, has_bin: bool, out: Dictionary) -> String:
	var asset = json.get("asset")
	if not asset is Dictionary or not str(asset.get("version", "")).begins_with("2"):
		return "Unsupported glTF version: export it as glTF 2.0."
	for key in ["extensionsUsed", "extensionsRequired"]:
		var used = json.get(key, [])
		if not used is Array:
			return "Damaged .glb: %s isn't a list." % key
		for name in used:
			if BLOCKED_EXTENSIONS.has(name):
				return "Uses %s (%s), which isn't supported. Export it without mesh compression." % [BLOCKED_EXTENSIONS[name], name]
	var lists := {}
	for key in ["buffers", "bufferViews", "accessors", "images", "meshes", "nodes", "scenes"]:
		var found = _list(json, key)
		if found == null:
			return "Damaged .glb: its %s can't be read." % key
		lists[key] = found
	var buffer_sizes := []
	for i in lists.buffers.size():
		var buffer: Dictionary = lists.buffers[i]
		if buffer.has("uri"):
			var uri := str(buffer.uri)
			if uri.begins_with("data:"):
				return "Buffer %d is a data: link. Export it as a single .glb with its data in the binary chunk." % i
			return "Uses an external buffer file (%s). Export it as a single .glb with everything embedded." % uri.get_file()
		if i > 0 or not _int(buffer.get("byteLength")):
			return "Damaged .glb: buffer %d has no data of its own." % i
		if not has_bin or bin.size() < int(buffer.byteLength):
			return "Damaged .glb: buffer 0 says %s bytes, but the binary chunk has %s." % [number(int(buffer.byteLength)), number(bin.size())]
		buffer_sizes.append(int(buffer.byteLength))
	var views: Array = lists.bufferViews
	for i in views.size():
		var view: Dictionary = views[i]
		if not _int(view.get("buffer")) or int(view.buffer) >= buffer_sizes.size() or not _int(view.get("byteLength")) or not _int(view.get("byteOffset", 0)):
			return "Damaged .glb: buffer view %d can't be read." % i
		if int(view.get("byteOffset", 0)) + int(view.byteLength) > buffer_sizes[int(view.buffer)]:
			return "Damaged .glb: buffer view %d reads past the end of its buffer." % i
		if view.has("byteStride") and (not _int(view.byteStride, 4) or int(view.byteStride) > 252):
			return "Damaged .glb: buffer view %d has an impossible stride." % i
	for i in lists.images.size():
		var image: Dictionary = lists.images[i]
		if image.has("uri"):
			var uri := str(image.uri)
			if uri.begins_with("data:"):
				return "Image %d is a data: link. Export it with its images stored in the .glb's binary chunk." % i
			return "Uses an external image file (%s). Export it with its images embedded in the .glb." % uri.get_file()
		if not _int(image.get("bufferView")) or int(image.bufferView) >= views.size():
			return "Damaged .glb: image %d has no data." % i
		var view: Dictionary = views[int(image.bufferView)]
		var start := int(view.get("byteOffset", 0))
		var picture := bin.slice(start, start + int(view.byteLength))
		if picture_kind(picture) == "":
			return "Image %d isn't a PNG, JPG or WebP picture." % i
		var size := picture_size(picture)
		if size.x <= 0 or size.y <= 0:
			return "Damaged .glb: image %d's size can't be read." % i
		if maxi(size.x, size.y) > LARGEST_PICTURE:
			return _too_big_picture("Texture %d" % i, size)
	var accessors: Array = lists.accessors
	for i in accessors.size():
		var problem := _accessor_problem(accessors[i], views)
		if problem != "":
			return "Damaged .glb: accessor %d %s." % [i, problem]
	var mesh_triangles := []
	for m in lists.meshes.size():
		var primitives = lists.meshes[m].get("primitives")
		if not primitives is Array or primitives.is_empty():
			return "Damaged .glb: mesh %d has no parts." % m
		var count := 0
		for p in primitives:
			if not p is Dictionary or not p.get("attributes") is Dictionary:
				return "Damaged .glb: a part of mesh %d can't be read." % m
			var extensions = p.get("extensions", {})
			if extensions is Dictionary:
				for name in extensions:
					if BLOCKED_EXTENSIONS.has(name):
						return "Uses %s (%s), which isn't supported. Export it without mesh compression." % [BLOCKED_EXTENSIONS[name], name]
			var position = p.attributes.get("POSITION")
			if not _int(position) or int(position) >= accessors.size():
				return "Damaged .glb: a part of mesh %d has no positions." % m
			for attribute in p.attributes.values():
				if not _int(attribute) or int(attribute) >= accessors.size():
					return "Damaged .glb: a part of mesh %d names a missing accessor." % m
			var n := int(accessors[int(position)].get("count", 0))
			if p.has("indices"):
				if not _int(p.indices) or int(p.indices) >= accessors.size():
					return "Damaged .glb: a part of mesh %d names missing indices." % m
				n = int(accessors[int(p.indices)].get("count", 0))
			var mode := int(p.get("mode", 4)) if _int(p.get("mode", 4)) else -1
			if mode < 0 or mode > 6:
				return "Damaged .glb: a part of mesh %d has an unknown drawing mode." % m
			count += n / 3 if mode == 4 else (maxi(n - 2, 0) if mode >= 5 else 0)
		mesh_triangles.append(count)
	var nodes: Array = lists.nodes
	var children_of := {}
	for i in nodes.size():
		var node: Dictionary = nodes[i]
		if node.has("mesh") and (not _int(node.mesh) or int(node.mesh) >= mesh_triangles.size()):
			return "Damaged .glb: node %d names a missing mesh." % i
		var children = node.get("children", [])
		if not children is Array or not children.all(func(c): return _int(c) and int(c) < nodes.size()):
			return "Damaged .glb: node %d names a missing child." % i
		for c in children:
			if children_of.has(int(c)):
				return "Damaged .glb: node %d appears more than once in the hierarchy." % int(c)
			children_of[int(c)] = i
	var roots := []
	if not lists.scenes.is_empty():
		var chosen = json.get("scene", 0)
		if not _int(chosen) or int(chosen) >= lists.scenes.size():
			return "Damaged .glb: its chosen scene is missing."
		roots = lists.scenes[int(chosen)].get("nodes", [])
		if not roots is Array or not roots.all(func(r): return _int(r) and int(r) < nodes.size()):
			return "Damaged .glb: its scene names a missing node."
	else:
		for i in nodes.size():
			if not children_of.has(i):
				roots.append(i)
	var seen := {}
	var stack: Array = roots.map(func(r): return int(r))
	var triangles := 0
	while not stack.is_empty():
		var at: int = stack.pop_back()
		if seen.has(at):
			return "Damaged .glb: node %d appears more than once in the hierarchy." % at
		seen[at] = true
		if nodes[at].has("mesh"):
			triangles += mesh_triangles[int(nodes[at].mesh)]
		for c in nodes[at].get("children", []):
			stack.append(int(c))
	out.triangles = triangles
	return ""

static func _accessor_problem(a: Dictionary, views: Array) -> String:
	if not COMPONENT_BYTES.has(int(a.get("componentType", 0)) if _int(a.get("componentType", 0)) else 0) or not TYPE_COMPONENTS.has(str(a.get("type", ""))):
		return "has an unknown type"
	if not _int(a.get("count")) or not _int(a.get("byteOffset", 0)):
		return "has an impossible count"
	var element: int = COMPONENT_BYTES[int(a.componentType)] * TYPE_COMPONENTS[str(a.type)]
	var count := int(a.count)
	if a.has("bufferView"):
		if not _int(a.bufferView) or int(a.bufferView) >= views.size():
			return "names a missing buffer view"
		var view: Dictionary = views[int(a.bufferView)]
		var stride := int(view.get("byteStride", element))
		if count > 0 and int(a.get("byteOffset", 0)) + stride * (count - 1) + element > int(view.byteLength):
			return "reads past the end of its data"
	if a.has("sparse"):
		var sparse = a.sparse
		if not sparse is Dictionary or not _int(sparse.get("count"), 1) or int(sparse.count) > count or not sparse.get("indices") is Dictionary or not sparse.get("values") is Dictionary:
			return "has damaged sparse data"
		var index_type = sparse.indices.get("componentType", 0)
		var index_bytes: int = COMPONENT_BYTES.get(int(index_type) if _int(index_type) else 0, 0)
		for part in [[sparse.indices, index_bytes], [sparse.values, element]]:
			var block: Dictionary = part[0]
			if not _int(block.get("bufferView")) or int(block.bufferView) >= views.size() or not _int(block.get("byteOffset", 0)) or int(part[1]) <= 0:
				return "has damaged sparse data"
			if int(block.get("byteOffset", 0)) + int(part[1]) * int(sparse.count) > int(views[int(block.bufferView)].byteLength):
				return "has sparse data past the end of its buffer"
	return ""

## Checks a model file: {error, warning, triangles, bytes}.
static func check_model_file(path: String) -> Dictionary:
	if not path.get_extension().to_lower() == "glb":
		return {"error": "Choose a .glb file (glTF 2.0 binary).", "warning": "", "triangles": 0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "That file can't be read (%s)." % error_string(FileAccess.get_open_error()), "warning": "", "triangles": 0}
	var length := f.get_length()
	if length > MODEL_BYTES:
		f.close()
		return {"error": _too_large(length, MODEL_BYTES), "warning": "", "triangles": 0}
	var bytes := f.get_buffer(length)
	f.close()
	var checked := check_glb(bytes)
	checked.bytes = bytes
	return checked

## Checks a picture file: {error, image, size}. The image is already scaled to fit.
static func check_image_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "That file can't be read (%s)." % error_string(FileAccess.get_open_error())}
	var length := f.get_length()
	if length > IMAGE_BYTES:
		f.close()
		return {"error": _too_large(length, IMAGE_BYTES)}
	var bytes := f.get_buffer(length)
	f.close()
	return check_image(bytes)

static func check_image(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > IMAGE_BYTES:
		return {"error": _too_large(bytes.size(), IMAGE_BYTES)}
	var kind := picture_kind(bytes)
	if kind == "":
		return {"error": "Not a PNG, JPG or WebP picture."}
	var size := picture_size(bytes)
	if size.x <= 0 or size.y <= 0:
		return {"error": "Damaged picture: its size can't be read."}
	if maxi(size.x, size.y) > LARGEST_PICTURE:
		return {"error": _too_big_picture("The picture", size)}
	var shape := maxf(size.x, size.y) / minf(size.x, size.y)
	if shape > WIDEST_SHAPE:
		return {"error": "Too %s: %.1f to 1, over the 4 to 1 limit by %.1f." % ["wide" if size.x > size.y else "tall", shape, shape - WIDEST_SHAPE]}
	var image := decode_picture(bytes)
	if image == null:
		return {"error": "Damaged picture: it can't be decoded."}
	return {"error": "", "image": image, "size": size, "kind": kind, "bytes": bytes}

static func decode_picture(bytes: PackedByteArray) -> Image:
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match picture_kind(bytes):
		"png":
			err = image.load_png_from_buffer(bytes)
		"jpg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
	if err != OK or image.is_empty():
		return null
	return fit_picture(image)

static func fit_picture(image: Image) -> Image:
	if image.is_compressed():
		image.decompress()
	var side := maxi(image.get_width(), image.get_height())
	if side > TEXTURE_SIDE:
		var factor := float(TEXTURE_SIDE) / side
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	return image

static func fit_textures(material: BaseMaterial3D, done: Dictionary) -> void:
	for slot in BaseMaterial3D.TEXTURE_MAX:
		var tex: Texture2D = material.get_texture(slot)
		if tex == null:
			continue
		if not done.has(tex):
			var img := tex.get_image()
			done[tex] = tex if img == null or maxi(img.get_width(), img.get_height()) <= TEXTURE_SIDE else ImageTexture.create_from_image(fit_picture(img))
		material.set_texture(slot, done[tex])

## A model as uploaded, upright, centred and standing on the ground.
static func model_mesh(bytes: PackedByteArray, upright: String) -> ArrayMesh:
	if check_glb(bytes).error != "":
		return ArrayMesh.new()
	return stand(WorldScene.glb_mesh(bytes, true), upright)

static func stand(mesh: ArrayMesh, upright: String) -> ArrayMesh:
	var turn := Basis()
	match upright:
		"x90":
			turn = Basis(Vector3.RIGHT, PI / 2.0)
		"x-90":
			turn = Basis(Vector3.RIGHT, -PI / 2.0)
		"z90":
			turn = Basis(Vector3.BACK, PI / 2.0)
		"z-90":
			turn = Basis(Vector3.BACK, -PI / 2.0)
	var turned := _moved(mesh, Transform3D(turn, Vector3.ZERO))
	var box := turned.get_aabb()
	return _moved(turned, Transform3D(Basis(), Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)))

static func _moved(mesh: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		WorldScene._transform_arrays(arrays, xf)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out

## Where the picture and its frame go for a display piece this tall, in metres.
static func display_layout(display: String, shape: float, height: float) -> Dictionary:
	if display == "banner":
		var pole := maxf(0.05, 0.025 * height)
		var cloth := Vector2(0.7 * height * shape, 0.7 * height)
		var top := height - pole * 1.5
		return {"picture": cloth, "picture_centre": Vector3(0.0, top - cloth.y / 2.0, 0.0), "pole": pole,
			"poles": [-(cloth.x / 2.0 + pole), cloth.x / 2.0 + pole]}
	var rim := maxf(0.03, 0.02 * height)
	var board := Vector2(0.62 * height * shape, 0.62 * height)
	var thick := maxf(0.04, 0.03 * height)
	var post := maxf(0.06, 0.04 * height)
	return {"picture": board, "picture_centre": Vector3(0.0, height - rim - board.y / 2.0, thick / 2.0 + 0.002), "rim": rim,
		"thick": thick, "post": post, "posts": [-(board.x / 2.0 + rim - post / 2.0), board.x / 2.0 + rim - post / 2.0]}

## A sign board or banner showing the picture, at its real height.
static func display_mesh(image: Image, display: String, height: float) -> ArrayMesh:
	var shape := float(image.get_width()) / image.get_height()
	var at := display_layout(display, shape, height)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.29, 0.18)
	wood.roughness = 0.85
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.33, 0.34, 0.36)
	metal.metallic = 0.6
	metal.roughness = 0.45
	var painted := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	painted.fill(Color.WHITE)
	var source := image.duplicate() as Image
	source.convert(Image.FORMAT_RGBA8)
	painted.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	painted.convert(Image.FORMAT_RGB8)
	painted.generate_mipmaps()
	var picture := StandardMaterial3D.new()
	picture.albedo_texture = ImageTexture.create_from_image(painted)
	picture.roughness = 0.7
	var mesh := ArrayMesh.new()
	var size: Vector2 = at.picture
	var centre: Vector3 = at.picture_centre
	if display == "banner":
		var frame := SurfaceTool.new()
		frame.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pole: float = at.pole
		for x in at.poles:
			_box(frame, Vector3(x, height / 2.0, 0.0), Vector3(pole, height, pole))
		_box(frame, Vector3(0.0, height - pole / 2.0, 0.0), Vector3(size.x + pole * 3.0, pole, pole))
		_commit(mesh, frame, metal)
		var cloth := SurfaceTool.new()
		cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(cloth, centre + Vector3(0, 0, 0.004), size, false)
		_quad(cloth, centre - Vector3(0, 0, 0.004), size, true)
		_commit(mesh, cloth, picture)
	else:
		var frame := SurfaceTool.new()
		frame.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rim: float = at.rim
		var thick: float = at.thick
		var post: float = at.post
		_box(frame, Vector3(0.0, centre.y, 0.0), Vector3(size.x + rim * 2.0, size.y + rim * 2.0, thick))
		for x in at.posts:
			_box(frame, Vector3(x, (height - rim) / 2.0, -thick / 2.0 - post / 2.0), Vector3(post, height - rim, post))
		_commit(mesh, frame, wood)
		var face := SurfaceTool.new()
		face.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(face, centre, size, false)
		_commit(mesh, face, picture)
	return mesh

static func _commit(mesh: ArrayMesh, st: SurfaceTool, material: Material) -> void:
	st.generate_tangents()
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

static func _quad(st: SurfaceTool, centre: Vector3, size: Vector2, back: bool) -> void:
	var facing := Vector3.BACK if not back else Vector3.FORWARD
	var right := Vector3.RIGHT if not back else Vector3.LEFT
	var h := size / 2.0
	var corners := [centre - right * h.x - Vector3.UP * h.y, centre + right * h.x - Vector3.UP * h.y, centre + right * h.x + Vector3.UP * h.y, centre - right * h.x + Vector3.UP * h.y]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(facing)
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])

static func _box(st: SurfaceTool, centre: Vector3, size: Vector3) -> void:
	var h := size / 2.0
	for axis in 3:
		for sign_value in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign_value
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := n.cross(u)
			var c := centre + n * h[axis]
			var hu: float = h[(axis + 1) % 3]
			var hv: float = absf(v.dot(h))
			var corners := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n)
				st.set_uv(Vector2(0.5, 0.5))
				st.add_vertex(corners[i])

## The mesh a stored upload draws with, before it's scaled to its height.
static func mesh_for(kind: String) -> ArrayMesh:
	var info := item(kind)
	if info.is_empty():
		return ArrayMesh.new()
	var source := folder(info.id).path_join(info.source)
	if info.type == "model":
		return model_mesh(FileAccess.get_file_as_bytes(source), str(info.get("upright", "")))
	var image := decode_picture(FileAccess.get_file_as_bytes(source))
	if image == null:
		return ArrayMesh.new()
	return display_mesh(image, info.display, float(info.height))

static func new_id(bytes: PackedByteArray, tag: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(tag.to_utf8_buffer())
	h.update(bytes)
	return "u" + h.finish().hex_encode().left(16)

## Stores an upload: {error, kind}. `settings` holds type, label, height, rights,
## and upright and seated for a model or display for a picture.
static func add(path: String, settings: Dictionary) -> Dictionary:
	var type := str(settings.get("type", ""))
	if type not in ["model", "image"]:
		return {"error": "Choose a 3D model or an image."}
	var named := name_problem(str(settings.get("label", "")))
	if named != "":
		return {"error": named}
	if not settings.get("rights", false):
		return {"error": "Confirm you made it or have the rights to use it."}
	var height := float(settings.get("height", 0.0))
	if height < LOWEST or height > TALLEST:
		return {"error": "Height must be between %.1f and %.0f m." % [LOWEST, TALLEST]}
	var checked := check_model_file(path) if type == "model" else check_image_file(path)
	if checked.error != "":
		return {"error": checked.error}
	var bytes: PackedByteArray = checked.bytes
	var display := str(settings.get("display", "sign"))
	if type == "image" and display not in DISPLAYS:
		return {"error": "Choose a sign board or a banner."}
	var upright := str(settings.get("upright", ""))
	if type == "model" and upright not in UPRIGHTS:
		return {"error": "Choose how to stand it upright."}
	var id := new_id(bytes, type if type == "model" else display)
	var kind := PREFIX + id
	var existing := item(kind)
	if not existing.is_empty():
		return {"error": "This file is already in Custom as “%s”." % existing.label}
	var mesh := model_mesh(bytes, upright) if type == "model" else display_mesh(checked.image, display, height)
	var box := mesh.get_aabb()
	if mesh.get_surface_count() == 0 or box.size.y <= 0.0:
		return {"error": "Nothing to show: it has no visible shape."}
	var factor := height / box.end.y
	var info := {"format": 1, "id": id, "type": type, "label": str(settings.label).strip_edges(), "height": height,
		"radius": snappedf(maxf(box.size.x, box.size.z) / 2.0 * factor, 0.01), "bytes": bytes.size(),
		"source": "model.glb" if type == "model" else "image." + str(checked.kind)}
	if type == "model":
		info.triangles = int(checked.triangles)
		info.upright = upright
		info.seated = bool(settings.get("seated", false))
	else:
		info.display = display
		info.triangles = 0
		info.shape = float(checked.size.x) / checked.size.y
	var dir := folder(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var err := _write(dir.path_join(info.source), bytes)
	if err == OK:
		err = plain_icon(type).save_webp(dir.path_join(THUMB), true, 0.82)
	if err == OK:
		err = _write(dir.path_join(ITEM_FILE), (JSON.stringify(info, " ") + "\n").to_utf8_buffer())
	if err != OK:
		remove(kind)
		return {"error": "The upload couldn't be saved (%s)." % error_string(err)}
	return {"error": "", "kind": kind}

static func _write(path: String, bytes: PackedByteArray) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	var err := f.get_error()
	f.close()
	return err

static func rename(kind: String, label: String) -> String:
	var info := item(kind)
	if info.is_empty():
		return "That upload can't be found."
	var named := name_problem(label)
	if named != "":
		return named
	info.label = label.strip_edges()
	var err := _write(folder(info.id).path_join(ITEM_FILE), (JSON.stringify(info, " ") + "\n").to_utf8_buffer())
	return "" if err == OK else "It couldn't be renamed (%s)." % error_string(err)

static func remove(kind: String) -> Error:
	if not is_custom(kind) or not valid_id(id_of(kind)):
		return ERR_INVALID_PARAMETER
	var dir := folder(id_of(kind))
	if not DirAccess.dir_exists_absolute(dir):
		return ERR_DOES_NOT_EXIST
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	return DirAccess.remove_absolute(dir)

static func save_thumb(kind: String, image: Image) -> Error:
	if item(kind).is_empty() or image == null or image.is_empty():
		return ERR_INVALID_PARAMETER
	image.convert(Image.FORMAT_RGB8)
	return image.save_webp(thumb_path(kind), true, 0.82)

## A plain picture for when a thumbnail can't be rendered.
static func plain_icon(type: String) -> Image:
	var size := ThumbStage.ITEM
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.94, 0.96))
	var ink := Color(0.37, 0.41, 0.47)
	var cx := size.x / 2
	if type == "image":
		img.fill_rect(Rect2i(cx - 46, 40, 92, 58), ink)
		img.fill_rect(Rect2i(cx - 40, 46, 80, 46), Color(0.85, 0.87, 0.9))
		img.fill_rect(Rect2i(cx - 38, 98, 6, 30), ink)
		img.fill_rect(Rect2i(cx + 32, 98, 6, 30), ink)
	else:
		img.fill_rect(Rect2i(cx - 34, 52, 68, 68), ink)
		img.fill_rect(Rect2i(cx - 26, 60, 52, 52), Color(0.85, 0.87, 0.9))
		img.fill_rect(Rect2i(cx - 34, 40, 80, 12), ink)
		img.fill_rect(Rect2i(cx + 34, 40, 12, 80), ink)
	return img

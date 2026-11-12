class_name WorldPackage
extends RefCounted
## A .agworld file: an inert gzipped tar of plates, skies and a manifest, in the form
## agent-guild#378 reads. No code, shaders or engine resources. `check` treats any
## file as hostile, because worlds travel between people and the Yard's page holds a
## token that controls real terminals.

const FORMAT := 1
const KIND := "yard-environment"
const EXT := ".agworld"
const MANIFEST := "world.json"
const PREVIEW := "preview.jpg"
const MAX_PACKAGE := 64 * 1024 * 1024
const MAX_UNPACKED := 64 * 1024 * 1024
const MAX_ENTRY := 16 * 1024 * 1024
const MAX_RATIO := 20
const RATIO_FROM := 8 * 1024 * 1024
const MAX_SIDE := 4096
const BLOCK := 512
const PUBLISH_SCRIPT := "try { [System.IO.File]::Move($env:AGB_PUBLISH_FROM, $env:AGB_PUBLISH_TO); exit 0 } catch { exit 1 }"

## Every name a package may hold, besides the manifest. Anything else is refused.
static func allowed_names() -> Array:
	var names := [PREVIEW, "web/sky-light.hdr", "web/sky-dark.hdr"]
	names += plate_names()
	return names

static func plate_names() -> Array:
	var names := []
	for theme in Yard.THEMES:
		for layer in Yard.layers():
			for t in Yard.tiles(layer):
				names.append("web/%s-%s.webp" % [theme, t.name])
	return names

## A hash over everything plates depend on, computed from the Yard's own model by
## tools/gen_layout.mjs, so it matches what Agent Guild computes.
static func environment_abi() -> String:
	return str(Yard.data().environment)

## The Radiance .hdr the Yard lights its halls with: flat RGBE, unscaled.
static func hdr_bytes(image: Image) -> PackedByteArray:
	var w := image.get_width()
	var h := image.get_height()
	var out := ("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % [h, w]).to_ascii_buffer()
	var start := out.size()
	out.resize(start + w * h * 4)
	var o := start
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			var m: float = max(c.r, c.g, c.b)
			if m >= 1e-32:
				var e := ceili(log(m) / log(2.0) + 1e-6)
				var scale := 256.0 / pow(2.0, e)
				out[o] = clampi(int(c.r * scale), 0, 255)
				out[o + 1] = clampi(int(c.g * scale), 0, 255)
				out[o + 2] = clampi(int(c.b * scale), 0, 255)
				out[o + 3] = clampi(e + 128, 0, 255)
			o += 4
	return out

## Colours for the halls under this mood: the sun's own colour and a sky-fill colour
## from the sky's average, in the form the Yard's WORLDS table uses.
static func hall_lights(doc: WorldDoc, skies: Dictionary) -> Dictionary:
	var out := {}
	for theme in Yard.THEMES:
		var c: Array = doc.data.mood[theme].sun_color
		var sky: BakeSky = skies[theme]
		var fill := sky.average_color()
		var peak: float = max(fill.r, fill.g, fill.b, 0.0001)
		out[theme] = {
			"sun": _hex(Color(c[0], c[1], c[2]).linear_to_srgb()),
			"hemi": _hex(Color(fill.r / peak, fill.g / peak, fill.b / peak).linear_to_srgb()),
		}
	return out

static func _hex(c: Color) -> int:
	return (c.r8 << 16) | (c.g8 << 8) | c.b8

static func sha256(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

## One ustar entry. `type` is "0" for a file; tests use others to build bad packages.
static func _tar_entry(name: String, bytes: PackedByteArray, type := "0") -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(BLOCK)
	var put := func(at: int, text: String):
		var b := text.to_ascii_buffer()
		for i in b.size():
			header[at + i] = b[i]
	put.call(0, name)
	put.call(100, "0000644")
	put.call(108, "0000000")
	put.call(116, "0000000")
	put.call(124, "%011o" % bytes.size())
	put.call(136, "00000000000")
	put.call(148, "        ")
	put.call(156, type)
	put.call(257, "ustar")
	put.call(263, "00")
	var sum := 0
	for v in header:
		sum += v
	put.call(148, "%06o" % sum)
	header[154] = 0
	header[155] = 32
	var out := header
	out.append_array(bytes)
	var pad := (BLOCK - bytes.size() % BLOCK) % BLOCK
	if pad > 0:
		var zero := PackedByteArray()
		zero.resize(pad)
		out.append_array(zero)
	return out

## `entries` is an ordered list of [name, bytes] or [name, bytes, type].
static func tar_gz(entries: Array) -> PackedByteArray:
	var tar := PackedByteArray()
	for e in entries:
		tar.append_array(_tar_entry(e[0], e[1], e[2] if e.size() > 2 else "0"))
	var end := PackedByteArray()
	end.resize(BLOCK * 2)
	tar.append_array(end)
	return tar.compress(FileAccess.COMPRESSION_GZIP)

## Packs a baked folder of plates. `out_path` is written through a temporary file.
static func write(doc: WorldDoc, plates_dir: String, skies: Dictionary, preview: Image, out_path: String, report := {}) -> Error:
	var content := []
	for theme in Yard.THEMES:
		var sky: BakeSky = skies[theme]
		var small := sky.original.duplicate()
		small.resize(512, 256, Image.INTERPOLATE_BILINEAR)
		content.append(["web/sky-%s.hdr" % theme, hdr_bytes(small)])
	for name in plate_names():
		var bytes := FileAccess.get_file_as_bytes(plates_dir.path_join(name.get_file()))
		if bytes.is_empty():
			return ERR_FILE_NOT_FOUND
		content.append([name, bytes])
	if preview:
		content.append([PREVIEW, preview.save_jpg_to_buffer(0.85)])
	var listing := {}
	for e in content:
		listing[e[0]] = {"size": e[1].size(), "sha256": sha256(e[1])}
	var meta := {
		"format": FORMAT, "kind": KIND, "title": str(doc.data.title), "base": str(doc.data.base),
		"environment": environment_abi(), "generator": WorldDoc.GENERATOR,
		"lights": hall_lights(doc, skies), "files": listing,
	}
	var entries := [[MANIFEST, StrictJson.stringify(meta, " ").to_utf8_buffer()]]
	entries.append_array(content)
	return _write_package(tar_gz(entries), out_path, report)

static func prepare_destination(out_path: String, report := {}, replace := true) -> Error:
	if out_path.is_empty() or DirAccess.dir_exists_absolute(out_path):
		return _write_error(report, ERR_INVALID_PARAMETER, "write to a file", out_path)
	var tmp := out_path + ".tmp"
	var backup := out_path + ".previous"
	if FileAccess.file_exists(backup):
		var destination := WorldDoc.recovery_path(out_path) if FileAccess.file_exists(out_path) else out_path
		var restored := DirAccess.rename_absolute(backup, destination)
		if restored != OK:
			return _write_error(report, restored, "recover the previous export", backup)
	for staging in [tmp, backup]:
		if DirAccess.dir_exists_absolute(staging):
			return _write_error(report, ERR_ALREADY_EXISTS, "prepare temporary export files", staging)
	if not replace and FileAccess.file_exists(out_path):
		return _occupied(report, out_path)
	if FileAccess.file_exists(tmp):
		var recovered := WorldDoc.recovery_path(tmp)
		var moved := DirAccess.rename_absolute(tmp, recovered)
		if moved != OK:
			return _write_error(report, moved, "preserve an interrupted export", tmp)
	var probe := FileAccess.open(tmp, FileAccess.WRITE)
	if probe == null:
		return _write_error(report, FileAccess.get_open_error(), "write the temporary export", tmp)
	probe.store_8(0)
	probe.flush()
	var checked := probe.get_error()
	probe.close()
	var removed := DirAccess.remove_absolute(tmp)
	if checked != OK or removed != OK:
		return _write_error(report, checked if checked != OK else removed, "prepare temporary export files", tmp)
	return OK

static func publish(source: String, out_path: String, report := {}, replace := true) -> Error:
	if ProjectSettings.globalize_path(source).simplify_path() == ProjectSettings.globalize_path(out_path).simplify_path():
		return _write_error(report, ERR_INVALID_PARAMETER, "replace the recovery copy with itself", out_path)
	var checked := check(source)
	if not accepted(checked):
		report.error = explanation(checked)
		return ERR_FILE_CORRUPT
	return _write_package(FileAccess.get_file_as_bytes(source), out_path, report, replace)

static func _write_package(bytes: PackedByteArray, out_path: String, report := {}, replace := true) -> Error:
	var prepared := prepare_destination(out_path, report, replace)
	if prepared != OK:
		return prepared
	var tmp := out_path + ".tmp"
	var backup := out_path + ".previous"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _write_error(report, FileAccess.get_open_error(), "write the temporary export", tmp)
	f.store_buffer(bytes)
	f.flush()
	var written := f.get_error()
	f.close()
	if written != OK:
		DirAccess.remove_absolute(tmp)
		return _write_error(report, written, "write the temporary export", tmp)
	if not accepted(check(tmp)):
		DirAccess.remove_absolute(tmp)
		return _write_error(report, ERR_FILE_CORRUPT, "validate the temporary export", tmp)
	if not replace:
		return _publish_new(tmp, out_path, report)
	var had_previous := FileAccess.file_exists(out_path)
	if had_previous:
		var moved := DirAccess.rename_absolute(out_path, backup)
		if moved != OK:
			DirAccess.remove_absolute(tmp)
			return _write_error(report, moved, "preserve the previous export", out_path)
	return _publish_staged(tmp, out_path, had_previous, report)

static func _publish_staged(tmp: String, out_path: String, had_previous: bool, report := {}) -> Error:
	var backup := out_path + ".previous"
	var published := DirAccess.rename_absolute(tmp, out_path)
	if published != OK:
		var restored := OK
		if had_previous:
			restored = DirAccess.rename_absolute(backup, out_path)
		DirAccess.remove_absolute(tmp)
		return _write_error(report, published, "publish the new export; previous file remains at " + backup if restored != OK else "publish the new export", out_path)
	var cleaned := DirAccess.remove_absolute(backup) if had_previous else OK
	if cleaned != OK:
		report.notice = "Exported successfully. The previous export remains at " + backup
	return OK

## Publishes without ever replacing, which a rename can't promise: Windows'
## plain File.Move and a hard link both fail atomically if the name is taken.
## Paths never pass through a shell or script text: on Windows they go through
## the environment, and elsewhere ln is started directly, because OS.execute
## runs its command through a shell on macOS.
static func _publish_new(tmp: String, out_path: String, report: Dictionary) -> Error:
	var bytes := FileAccess.get_file_as_bytes(tmp)
	var output := []
	var moved: int
	if OS.get_name() == "Windows":
		OS.set_environment("AGB_PUBLISH_FROM", _extended_path(tmp))
		OS.set_environment("AGB_PUBLISH_TO", _extended_path(out_path))
		moved = OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", PUBLISH_SCRIPT], output, true)
		OS.unset_environment("AGB_PUBLISH_FROM")
		OS.unset_environment("AGB_PUBLISH_TO")
	else:
		moved = _hard_link(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(out_path))
	var published := moved == 0 and FileAccess.file_exists(out_path) and FileAccess.get_file_as_bytes(out_path) == bytes
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	if published:
		return OK
	if FileAccess.file_exists(out_path) or DirAccess.dir_exists_absolute(out_path):
		return _occupied(report, out_path)
	return _write_error(report, FAILED, "publish the export without risking a replacement", out_path)

## /bin/ln with its own pipes, so the paths reach it as they are and it never
## shares stdin or stdout, which carry MCP. Returns ln's exit code, or -1.
static func _hard_link(from: String, to: String) -> int:
	var started := OS.execute_with_pipe("/bin/ln", [from, to], false)
	var pid: int = started.get("pid", -1)
	if pid <= 0:
		return -1
	while OS.is_process_running(pid):
		OS.delay_msec(1)
	return OS.get_process_exit_code(pid)

## Windows' extended-length form: no 260-character limit, and taken literally.
static func _extended_path(path: String) -> String:
	var p := ProjectSettings.globalize_path(path).simplify_path().replace("/", "\\")
	if p.begins_with("\\\\?\\"):
		return p
	if p.begins_with("\\\\"):
		return "\\\\?\\UNC\\" + p.substr(2)
	return "\\\\?\\" + p

static func _occupied(report: Dictionary, out_path: String) -> Error:
	report.error = "%s already exists, so it wasn't replaced." % out_path
	return ERR_ALREADY_EXISTS

static func _write_error(report: Dictionary, err: Error, operation: String, path: String) -> Error:
	report.error = "Couldn't %s: %s (%s)." % [operation, path, error_string(err)]
	return err

## Reads a tar without trusting it. Returns {entries: [[name, bytes]...], problem: ""}.
static func read_tar(tar: PackedByteArray) -> Dictionary:
	var entries := []
	var at := 0
	while at + BLOCK <= tar.size():
		var header := tar.slice(at, at + BLOCK)
		if header.count(0) == BLOCK:
			return {"entries": entries, "problem": ""}
		var name := header.slice(0, 100).get_string_from_ascii()
		var size_text := header.slice(124, 136).get_string_from_ascii().strip_edges()
		if size_text.is_empty() or not _octal(size_text):
			return {"entries": entries, "problem": "%s has a broken header." % name}
		var size := _from_octal(size_text)
		var type := char(header[156]) if header[156] != 0 else "0"
		if type != "0":
			return {"entries": entries, "problem": "%s isn't a plain file." % name}
		if size > MAX_ENTRY or at + BLOCK + size > tar.size():
			return {"entries": entries, "problem": "%s is too large or cut short." % name}
		entries.append([name, tar.slice(at + BLOCK, at + BLOCK + size)])
		at += BLOCK + ceili(size / float(BLOCK)) * BLOCK
	return {"entries": entries, "problem": "The file ends early."}

static func _octal(t: String) -> bool:
	for c in t:
		if not c in "01234567":
			return false
	return true

static func _from_octal(t: String) -> int:
	var v := 0
	for c in t:
		v = v * 8 + c.to_int()
	return v

static func check(path: String) -> Dictionary:
	var problems := []
	var valid := _check(path, problems)
	if not valid and problems.is_empty():
		problems.append("The world file couldn't be fully checked.")
	return {"valid": valid, "problems": problems}

static func accepted(result: Variant) -> bool:
	return result is Dictionary and result.get("valid") is bool and result.valid and result.get("problems") is Array and result.problems.is_empty()

static func explanation(result: Variant) -> String:
	if result is Dictionary and result.get("problems") is Array and not result.problems.is_empty():
		return "; ".join(result.problems)
	return "The world file couldn't be fully checked."

static func _reject(problems: Array, message: String) -> bool:
	problems.append(message)
	return false

static func _check(path: String, problems: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _reject(problems, "The file can't be read.")
	var length := file.get_length()
	if length > MAX_PACKAGE:
		file.close()
		return _reject(problems, "The file is larger than a world can be.")
	var raw := file.get_buffer(length)
	var read_error := file.get_error()
	file.close()
	if raw.is_empty() or read_error != OK:
		return _reject(problems, "The file can't be read.")
	if raw.size() < 2 or raw[0] != 0x1f or raw[1] != 0x8b:
		return _reject(problems, "This isn't a world file.")
	var tar := raw.decompress_dynamic(MAX_UNPACKED + 1, FileAccess.COMPRESSION_GZIP)
	if tar.is_empty():
		return _reject(problems, "This isn't a world file, or it expands too far.")
	if tar.size() > MAX_UNPACKED:
		return _reject(problems, "The world unpacks to more than it may.")
	if tar.size() > RATIO_FROM and tar.size() / raw.size() > MAX_RATIO:
		return _reject(problems, "The file expands far more than a world should.")
	var read := read_tar(tar)
	if not read.has("problem") or not read.get("entries") is Array:
		return false
	if read.problem != "":
		return _reject(problems, read.problem)
	var entries: Array = read.entries
	if entries.is_empty() or entries[0][0] != MANIFEST:
		return _reject(problems, "The world's details must come first.")
	var meta = JSON.parse_string((entries[0][1] as PackedByteArray).get_string_from_utf8())
	if not _check_meta(meta, problems):
		return false
	var allowed := allowed_names()
	var listing: Dictionary = meta.files
	var seen := {}
	for e in entries.slice(1):
		var name: String = e[0]
		if not _check_name(name, problems):
			return false
		if seen.has(name.to_lower()):
			problems.append("%s appears twice." % name)
			continue
		seen[name.to_lower()] = true
		if not allowed.has(name):
			problems.append("%s doesn't belong in a world file." % name)
			continue
		var bytes: PackedByteArray = e[1]
		if not listing.has(name):
			problems.append("%s isn't in the world's list of files." % name)
			continue
		var want = listing[name]
		if int(want.size) != bytes.size() or want.sha256 != sha256(bytes):
			problems.append("%s doesn't match the world's list of files." % name)
			continue
		if not _check_content(name, bytes, problems):
			return false
	for name in listing:
		if not seen.has(str(name).to_lower()):
			problems.append("%s is listed but missing." % name)
	for name in allowed:
		if name != PREVIEW and not seen.has(name.to_lower()):
			problems.append("%s is missing." % name)
	return problems.is_empty()

static func _check_name(name: String, problems: Array) -> bool:
	if name.is_empty() or name.begins_with("/") or name.contains("\\") or name.contains(":") or name.contains("..") or name.contains("%") or name.ends_with("/"):
		return _reject(problems, "%s: the name is unsafe." % name)
	for part in name.split("/"):
		var stem := part.get_slice(".", 0).to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "LPT1", "LPT2", "LPT3"]:
			return _reject(problems, "%s: the name is reserved." % name)
	return true

static func _check_content(name: String, b: PackedByteArray, problems: Array) -> bool:
	if name.ends_with(".webp"):
		if b.size() < 30 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WEBP":
			return _reject(problems, "%s isn't a WebP image." % name)
		var side := _webp_size(b)
		if side.x <= 0 or side.y <= 0 or side.x > MAX_SIDE or side.y > MAX_SIDE:
			return _reject(problems, "%s has an unsafe image size." % name)
	elif name.ends_with(".hdr"):
		if b.size() < 10 or b.slice(0, 10).get_string_from_ascii() != "#?RADIANCE":
			return _reject(problems, "%s isn't a sky image." % name)
	elif name.ends_with(".jpg"):
		if b.size() < 3 or b[0] != 0xff or b[1] != 0xd8 or b[2] != 0xff:
			return _reject(problems, "%s isn't a JPEG image." % name)
	return true

static func _webp_size(b: PackedByteArray) -> Vector2i:
	var chunk := b.slice(12, 16).get_string_from_ascii()
	if chunk == "VP8 " and b.size() >= 30:
		return Vector2i((b[26] | (b[27] << 8)) & 0x3fff, (b[28] | (b[29] << 8)) & 0x3fff)
	if chunk == "VP8L" and b.size() >= 25:
		var v := b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)
		return Vector2i((v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1)
	if chunk == "VP8X" and b.size() >= 30:
		return Vector2i((b[24] | (b[25] << 8) | (b[26] << 16)) + 1, (b[27] | (b[28] << 8) | (b[29] << 16)) + 1)
	return Vector2i.ZERO

static func _check_meta(meta: Variant, out: Array) -> bool:
	if not meta is Dictionary:
		return _reject(out, "The world's details can't be read.")
	var format: Variant = meta.get("format", 0)
	if not WorldDoc._integer(format) or format < 1:
		out.append("The world's format is missing.")
	elif int(format) > FORMAT:
		out.append("This world needs a newer Agent Guild: Builders.")
	if not meta.get("kind") is String or meta.kind != KIND:
		out.append("This isn't a Yard environment.")
	if not meta.get("base") is String or not WorldDoc.BASES.has(meta.base):
		out.append("The world names a base that doesn't exist.")
	var title = meta.get("title", "")
	if not title is String or title.strip_edges().is_empty() or title.length() > WorldDoc.MAX_TITLE:
		out.append("The world's title is missing or too long.")
	if not meta.get("environment") is String or meta.environment != environment_abi():
		out.append("This world was made for a different Yard layout, so it wouldn't line up.")
	if not meta.get("files", null) is Dictionary:
		out.append("The world's list of files is missing.")
	else:
		var allowed := allowed_names()
		for name in meta.files:
			if not name is String or not allowed.has(name):
				out.append("The world's list contains an unknown file.")
				continue
			var file = meta.files[name]
			if not file is Dictionary or not WorldDoc._integer(file.get("size")) or file.size < 0 or file.size > MAX_ENTRY:
				out.append("%s has an invalid file size." % name)
				continue
			if not file.get("sha256") is String or file.sha256.length() != 64 or not file.sha256.is_valid_hex_number(false):
				out.append("%s has an invalid file hash." % name)
	if meta.has("generator") and (not WorldDoc._integer(meta.generator) or meta.generator < 1):
		out.append("The world's generator is invalid.")
	var lights = meta.get("lights", null)
	if lights is Dictionary:
		for theme in Yard.THEMES:
			var t = lights.get(theme, null)
			if not t is Dictionary or not _colour(t.get("sun")) or not _colour(t.get("hemi")):
				out.append("The world's light colours aren't valid.")
				break
	elif meta.has("lights"):
		out.append("The world's light colours aren't valid.")
	return out.is_empty()

static func _colour(v: Variant) -> bool:
	return (v is float or v is int) and float(v) >= 0.0 and float(v) <= 16777215.0 and float(v) == floorf(float(v))

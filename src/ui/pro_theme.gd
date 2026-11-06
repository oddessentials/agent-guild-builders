class_name ProTheme
extends RefCounted
## Agent Guild's Professional skin in Godot: the tokens of
## web/skins/professional/skin.css, a neutral slate palette, quiet flat surfaces,
## one blue accent and 8 px corners, in light and dark.

const LIGHT := {
	"bg": "#f5f6f8", "surface": "#ffffff", "surface-2": "#f2f4f7", "border": "#e2e5ea",
	"text": "#1a1f2b", "muted": "#5f6877", "heading": "#111827", "accent": "#2563eb",
	"accent-fill": "#2563eb", "accent-text": "#ffffff", "danger": "#c0362c", "ok": "#16794a",
	"warn": "#a15c07", "focus": "#2563eb",
}
const DARK := {
	"bg": "#0d1015", "surface": "#151921", "surface-2": "#1b2029", "border": "#272d38",
	"text": "#e4e7ec", "muted": "#98a1b0", "heading": "#f2f4f7", "accent": "#7aa2ff",
	"accent-fill": "#2f6bed", "accent-text": "#ffffff", "danger": "#f2726a", "ok": "#3ccf8e",
	"warn": "#f0b44c", "focus": "#7aa2ff",
}
const RADIUS := 8
const FONT_SIZE := 14

static var dark := false
static var _thumbs := {}

static func color(token: String) -> Color:
	return Color((DARK if dark else LIGHT)[token])

static func box(fill: Color, edge: Color = Color.TRANSPARENT, radius := RADIUS, pad_x := 12, pad_y := 7) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	if edge.a > 0.0:
		s.border_color = edge
		s.set_border_width_all(1)
	s.anti_aliasing = true
	return s

static func make() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Variable Text", "Segoe UI", "SF Pro Text", "Roboto", "Noto Sans", "sans-serif"])
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	t.default_font = font
	t.default_font_size = FONT_SIZE
	var text := color("text")
	var muted := color("muted")
	var surface := color("surface")
	var inset := color("surface-2")
	var border := color("border")
	var accent := color("accent")
	var fill := color("accent-fill")
	var focus := box(Color.TRANSPARENT, color("focus"))
	focus.set_border_width_all(2)

	t.set_stylebox("panel", "Panel", box(surface, border, RADIUS, 0, 0))
	t.set_stylebox("panel", "PanelContainer", box(surface, border, RADIUS, 12, 12))
	for label in ["Label", "CheckBox", "CheckButton", "OptionButton", "Button", "LineEdit", "SpinBox", "MenuButton", "PopupMenu", "RichTextLabel"]:
		t.set_color("font_color", label, text)
		t.set_color("default_color", label, text)
		t.set_color("font_hover_color", label, text)
		t.set_color("font_focus_color", label, text)
		t.set_color("font_pressed_color", label, text)
		t.set_color("font_disabled_color", label, muted)

	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(surface, border))
		t.set_stylebox("hover", type, box(inset, border))
		t.set_stylebox("pressed", type, box(inset, accent))
		t.set_stylebox("disabled", type, box(inset, border))
		t.set_stylebox("focus", type, focus)
		t.set_color("icon_normal_color", type, text)
		t.set_color("font_hover_pressed_color", type, accent)
	t.set_stylebox("normal", "LineEdit", box(surface, border))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("caret_color", "LineEdit", text)
	t.set_color("selection_color", "LineEdit", Color(accent, 0.3))
	t.set_stylebox("panel", "PopupMenu", box(surface, border, RADIUS, 4, 4))
	t.set_stylebox("hover", "PopupMenu", box(inset, Color.TRANSPARENT, 6, 8, 4))
	t.set_stylebox("panel", "PopupPanel", box(surface, border))
	t.set_stylebox("panel", "AcceptDialog", box(surface, border, RADIUS, 16, 16))
	t.set_stylebox("embedded_border", "Window", box(surface, border, RADIUS, 0, 28))
	t.set_stylebox("slider", "HSlider", box(border, Color.TRANSPARENT, 3, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", box(fill, Color.TRANSPARENT, 3, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(fill, Color.TRANSPARENT, 3, 0, 2))
	var handle := _dot(9, fill, surface)
	t.set_icon("grabber", "HSlider", handle)
	t.set_icon("grabber_highlight", "HSlider", _dot(10, fill, surface))
	t.set_icon("grabber_disabled", "HSlider", _dot(9, border, surface))
	t.set_icon("checked", "CheckBox", _tick_box(fill, fill, color("accent-text")))
	t.set_icon("unchecked", "CheckBox", _tick_box(surface, muted, Color.TRANSPARENT))
	var plain := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", plain)
	t.set_stylebox("panel", "TooltipPanel", box(surface, border, 6, 8, 4))
	t.set_color("font_color", "TooltipLabel", text)
	t.set_color("title_color", "Window", text)
	t.set_color("font_disabled_color", "Label", muted)
	t.set_stylebox("background", "ProgressBar", box(inset, Color.TRANSPARENT, 4, 0, 3))
	t.set_stylebox("fill", "ProgressBar", box(fill, Color.TRANSPARENT, 4, 0, 3))
	t.set_stylebox("separator", "HSeparator", box(border, Color.TRANSPARENT, 0, 0, 0))
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("h_separation", "GridContainer", 8)
	t.set_constant("v_separation", "GridContainer", 8)
	t.set_stylebox("read_only", "LineEdit", box(inset, border))
	t.set_color("font_uneditable_color", "LineEdit", muted)
	return t

## A filled circle with a ring, drawn here so controls need no image files.
static func _dot(radius: int, fill: Color, edge: Color) -> ImageTexture:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(radius - 0.5, radius - 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(centre)
			var c := fill if d < radius - 2.0 else edge
			c.a = clampf(radius - d, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _tick_box(fill: Color, edge: Color, tick: Color) -> ImageTexture:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var rim := x < 1 or y < 1 or x >= size - 1 or y >= size - 1
			var corner := (x < 1 or x >= size - 1) and (y < 1 or y >= size - 1)
			img.set_pixel(x, y, Color.TRANSPARENT if corner else (edge if rim else fill))
	if tick.a > 0.0:
		for i in 3:
			img.fill_rect(Rect2i(4 + i, 8 + i, 2, 2), tick)
		for i in 5:
			img.fill_rect(Rect2i(7 + i, 9 - i, 2, 2), tick)
	return ImageTexture.create_from_image(img)

## A small picture of a kit item or template, if one has been made.
static func brand(name: String, height: float) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = load("res://data/brand/%s.webp" % name)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(height * picture.texture.get_width() / picture.texture.get_height(), height)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture

static func thumb(name: String) -> Texture2D:
	if _thumbs.has(name):
		return _thumbs[name]
	var path := "res://data/thumbs/%s.webp" % name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_thumbs[name] = tex
	return tex

## Shows a button's icon in its own colours rather than tinted like text.
static func picture_button(button: Button) -> void:
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.5))

## The main action on a screen.
static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(color("accent-fill")))
	button.add_theme_stylebox_override("hover", box(color("accent-fill").lightened(0.08)))
	button.add_theme_stylebox_override("pressed", box(color("accent-fill").darkened(0.08)))
	button.add_theme_stylebox_override("disabled", box(color("surface-2"), color("border")))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(c, color("accent-text"))

## A toggle in a tool list: quiet until chosen.
static func tool_button(button: Button) -> void:
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_stylebox_override("normal", box(Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", box(color("surface-2")))
	var on := box(Color(color("accent"), 0.12), Color(color("accent"), 0.45))
	button.add_theme_stylebox_override("pressed", on)
	button.add_theme_stylebox_override("hover_pressed", on)

static func heading(text: String, size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color("heading"))
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI Variable Display", "Segoe UI", "SF Pro Display", "Roboto", "sans-serif"])
	f.font_weight = 600
	l.add_theme_font_override("font", f)
	return l

static func note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color("muted"))
	l.add_theme_font_size_override("font_size", 13)
	return l

class_name CustomDialog
extends ConfirmationDialog
## Uploads a 3D model or a picture into the Custom group.

signal added(kind: String)

const FIGURE_HEIGHT := 1.8
const PREVIEW := Vector2(420, 320)
const FORM_WIDTH := 380

var type := "model"
var file_path := ""
var _checked := {}
var _raw: ArrayMesh
var _natural := 0.0
var _image: Image
var _type_buttons := {}
var _rules: Label
var _file_label: Label
var _message: Label
var _why: Label
var _name: LineEdit
var _height: SpinBox
var _upright: OptionButton
var _seated: CheckBox
var _display: OptionButton
var _rights: CheckBox
var _model_rows: VBoxContainer
var _image_rows: VBoxContainer
var _stage: SubViewport
var _shown: Node3D
var _caption: Label

func _init() -> void:
	title = "Custom uploads"
	ok_button_text = "Add to Custom"
	dialog_hide_on_ok = false
	exclusive = true
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	add_child(body)
	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(FORM_WIDTH, 0)
	form.add_theme_constant_override("separation", 6)
	body.add_child(form)
	var types := HBoxContainer.new()
	types.add_theme_constant_override("separation", 4)
	form.add_child(types)
	for entry in [["model", "3D model"], ["image", "Image"]]:
		var b := Button.new()
		b.text = entry[1]
		ProTheme.tool_button(b)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chosen: String = entry[0]
		b.pressed.connect(func(): set_type(chosen))
		types.add_child(b)
		_type_buttons[chosen] = b
	_rules = _note("", FORM_WIDTH)
	form.add_child(_rules)
	var pick := Button.new()
	pick.name = "Choose"
	pick.text = "Choose a file…"
	pick.pressed.connect(_choose_file)
	form.add_child(pick)
	_file_label = _note("No file chosen.", FORM_WIDTH)
	form.add_child(_file_label)
	_message = _note("", FORM_WIDTH)
	_message.visible = false
	form.add_child(_message)
	form.add_child(ProTheme.heading("Name", 13))
	_name = LineEdit.new()
	_name.max_length = CustomItems.LONGEST_NAME
	_name.placeholder_text = "Name it"
	_name.text_changed.connect(func(_t): _refresh_ok())
	form.add_child(_name)
	var height_row := HBoxContainer.new()
	var height_label := _note("Height in metres")
	height_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_row.add_child(height_label)
	_height = SpinBox.new()
	_height.min_value = CustomItems.LOWEST
	_height.max_value = CustomItems.TALLEST
	_height.step = 0.05
	_height.value = 2.0
	_height.value_changed.connect(func(_v): _refresh_preview())
	height_row.add_child(_height)
	form.add_child(height_row)
	_model_rows = VBoxContainer.new()
	form.add_child(_model_rows)
	var upright_row := HBoxContainer.new()
	var upright_label := _note("Upright fix")
	upright_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upright_row.add_child(upright_label)
	_upright = OptionButton.new()
	for key in CustomItems.UPRIGHTS:
		_upright.add_item(CustomItems.UPRIGHTS[key])
	_upright.tooltip_text = "Turn it a quarter if it was made lying down."
	_upright.item_selected.connect(func(_i): _on_upright())
	upright_row.add_child(_upright)
	_model_rows.add_child(upright_row)
	_seated = CheckBox.new()
	_seated.text = "Stands on a flat base"
	_seated.tooltip_text = "Like a building: it sits on the lowest ground under it, and steep spots are refused."
	_seated.button_pressed = true
	_model_rows.add_child(_seated)
	_image_rows = VBoxContainer.new()
	form.add_child(_image_rows)
	var display_row := HBoxContainer.new()
	var display_label := _note("Show it on")
	display_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_row.add_child(display_label)
	_display = OptionButton.new()
	for key in CustomItems.DISPLAYS:
		_display.add_item(CustomItems.DISPLAYS[key])
	_display.item_selected.connect(func(_i):
		_height.value = CustomItems.DISPLAY_HEIGHT[display()]
		_refresh_preview())
	display_row.add_child(_display)
	_image_rows.add_child(display_row)
	_rights = CheckBox.new()
	_rights.text = "I made this or have the rights to use it."
	_rights.toggled.connect(func(_on): _refresh_ok())
	form.add_child(_rights)
	_why = _note("", FORM_WIDTH)
	form.add_child(_why)
	var look := VBoxContainer.new()
	body.add_child(look)
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = PREVIEW
	frame.stretch = true
	look.add_child(frame)
	_stage = ThumbStage.make(frame)
	_caption = _note("", int(PREVIEW.x))
	look.add_child(_caption)
	confirmed.connect(_add)
	canceled.connect(queue_free)
	set_type("model")

func _note(text: String, width := 0) -> Label:
	var label := ProTheme.note(text)
	if width > 0:
		label.custom_minimum_size = Vector2(width, 0)
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

func display() -> String:
	return CustomItems.DISPLAYS.keys()[maxi(_display.selected, 0)]

func upright() -> String:
	return CustomItems.UPRIGHTS.keys()[maxi(_upright.selected, 0)]

func set_type(chosen: String) -> void:
	type = chosen
	for key in _type_buttons:
		_type_buttons[key].set_pressed_no_signal(key == chosen)
	var rules: Array = (CustomItems.MODEL_RULES if chosen == "model" else CustomItems.IMAGE_RULES) + CustomItems.SHARED_RULES
	_rules.text = "\n".join(rules.map(func(r): return "• " + r))
	_model_rows.visible = chosen == "model"
	_image_rows.visible = chosen == "image"
	file_path = ""
	_checked = {}
	_raw = null
	_image = null
	_file_label.text = "No file chosen."
	_say("", "")
	if chosen == "image":
		_height.set_value_no_signal(CustomItems.DISPLAY_HEIGHT[display()])
	_refresh_preview()
	_refresh_ok()

func _choose_file() -> void:
	var d := FileDialog.new()
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.filters = PackedStringArray(["*.glb ; glTF Binary"] if type == "model" else ["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	d.use_native_dialog = true
	d.file_selected.connect(func(chosen):
		d.queue_free()
		use_file(chosen))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 500))

## Checks a chosen file and shows it, or says exactly why it can't be used.
func use_file(chosen: String) -> void:
	file_path = chosen
	_file_label.text = chosen.get_file()
	_raw = null
	_image = null
	_say("", "")
	if type == "model":
		_checked = CustomItems.check_model_file(chosen)
		if _checked.error == "":
			_raw = WorldScene.glb_mesh(_checked.bytes, true)
			if _raw.get_surface_count() == 0:
				_checked.error = "Damaged .glb: it passed the checks, but no shape could be read from it."
		if _checked.error == "":
			_natural = CustomItems.stand(_raw, upright()).get_aabb().size.y
			_height.set_value_no_signal(clampf(snappedf(_natural, 0.05), CustomItems.LOWEST, CustomItems.TALLEST))
			var unusual := "" if _natural >= CustomItems.LOWEST and _natural <= CustomItems.TALLEST else "As made it's %.2f m tall. Set its real height." % _natural
			var notes := " ".join([_checked.warning, unusual].filter(func(n): return n != ""))
			_say(CustomItems.summary(_checked) + (" " + notes if notes != "" else ""), "warn" if notes != "" else "")
	else:
		_checked = CustomItems.check_image_file(chosen)
		if _checked.error == "":
			_image = _checked.image
			_say(CustomItems.summary(_checked), "")
	if _checked.error != "":
		_say(_checked.error, "danger")
	elif _name.text.strip_edges() == "":
		var plain := chosen.get_file().get_basename().replace("_", " ").replace("-", " ").strip_edges()
		_name.text = _fitted_name(plain.left(1).to_upper() + plain.substr(1))
	_refresh_preview()
	_refresh_ok()

func _fitted_name(text: String) -> String:
	while text.length() > 0 and CustomItems.name_problem(text) != "":
		text = text.left(text.length() - 1).strip_edges()
	return text

func _say(text: String, tone: String) -> void:
	_message.text = text
	_message.visible = text != ""
	_message.add_theme_color_override("font_color", ProTheme.color(tone if tone != "" else "muted"))

func _on_upright() -> void:
	if _raw:
		_natural = CustomItems.stand(_raw, upright()).get_aabb().size.y
		_height.set_value_no_signal(clampf(snappedf(_natural, 0.05), CustomItems.LOWEST, CustomItems.TALLEST))
	_refresh_preview()

## Why it can't be added yet, or "" if it can.
func why_not() -> String:
	if file_path == "":
		return "Choose a file."
	if _checked.get("error", "") != "":
		return "Choose another file."
	var named := CustomItems.name_problem(_name.text)
	if named != "":
		return named
	if not _rights.button_pressed:
		return "Confirm you made it or have the rights to use it."
	return ""

func _refresh_ok() -> void:
	var why := why_not()
	get_ok_button().disabled = why != ""
	_why.text = why

func _refresh_preview() -> void:
	if _shown:
		_shown.free()
		_shown = null
	_caption.text = ""
	var meshes := []
	var scale := 1.0
	if _raw:
		var stood := CustomItems.stand(_raw, upright())
		var top := stood.get_aabb().end.y
		scale = _height.value / top if top > 0.0 else 1.0
		meshes.append(stood)
	elif _image:
		meshes.append(CustomItems.display_mesh(_image, display(), _height.value))
	if meshes.is_empty():
		return
	_shown = Node3D.new()
	_stage.add_child(_shown)
	var part := MeshInstance3D.new()
	part.mesh = meshes[0]
	part.scale = Vector3.ONE * scale
	_shown.add_child(part)
	var box: AABB = meshes[0].get_aabb()
	var left := box.position.x * scale - 0.6
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.45
	body.mesh = capsule
	body.position = Vector3(left - 0.22, 0.725, 0.0)
	_shown.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	head.mesh = sphere
	head.position = Vector3(left - 0.22, FIGURE_HEIGHT - 0.13, 0.0)
	_shown.add_child(head)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.37, 0.41, 0.47)
	body.material_override = skin
	head.material_override = skin
	ThumbStage.frame(_stage, ThumbStage.bounds(_shown), Vector2i(PREVIEW))
	_caption.text = "%.2f m tall, beside a %.1f m person." % [_height.value, FIGURE_HEIGHT]

func settings() -> Dictionary:
	var out := {"type": type, "label": _name.text.strip_edges(), "height": _height.value, "rights": _rights.button_pressed}
	if type == "model":
		out.upright = upright()
		out.seated = _seated.button_pressed
	else:
		out.display = display()
	return out

func _add() -> void:
	if why_not() != "":
		_refresh_ok()
		return
	var result := CustomItems.add(file_path, settings())
	if result.error != "":
		_say(result.error, "danger")
		return
	added.emit(result.kind)
	hide()
	queue_free()

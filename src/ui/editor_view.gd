extends Control

signal closed

enum Tool { LOOK, LAND, GROUND, SCATTER, ERASE, WATER, MOOD, ARRANGE }
const AUTOSAVE_SECONDS := 2.0
const SAVE_RETRY_SECONDS := 10.0
const BRUSH_FLOW := 0.35
const HOLD_SECONDS := 0.08
const LAND_BUDGET_MS := 6.0
const SETTLE_SECONDS := 0.25
const COMMIT_SECONDS := 0.35
const ZONE_RES := 131
const DEFAULT_ZOOM := 1.02
const WIDE_ZOOM := 0.45
const PLACED_RING_SECONDS := 1.4
const PLACED_QUIET_PIXELS := 6.0
const NO_POINTER := Vector2(-1, -1)
const DRAG_PIXELS := 6.0
const PICK_PIXELS := 10.0
const TURN_STEP := PI / 12.0
const SMALLEST_SIZE := 0.5
const LARGEST_SIZE := 2.0
const WATER_LOWEST := -20.0
const PLACE_GROUPS := [["trees", "Trees"], ["plants", "Plants"], ["rocks", "Rocks & logs"], ["lights", "Lights"], ["props", "Props"], ["furniture", "Furniture"], ["statues", "Statues"], ["landmarks", "Landmarks"], ["city", "City"], ["medieval", "Medieval"], ["gnomes", "Gnomes"], ["goblins", "Goblins"], ["forest", "Forest folk"], ["space", "Space"], ["holiday", "Holiday"]]
const TOOL_KEYS := {KEY_M: Tool.ARRANGE, KEY_P: Tool.SCATTER, KEY_C: Tool.ERASE, KEY_L: Tool.LAND, KEY_G: Tool.GROUND, KEY_W: Tool.WATER, KEY_S: Tool.MOOD, KEY_V: Tool.LOOK}

var doc: WorldDoc
var path := ""
var history: History
var tool: int = Tool.SCATTER
var theme_name := "light"
var brush_radius := 8.0
var land_mode := "raise"
var ground_kind := 1
var place_mode := "one"
var place_kind := "fern"
var paint_choice := "fern"
var _scene: WorldScene
var _viewport: SubViewport
var _camera: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _brush: MeshInstance3D
var _brush_material: StandardMaterial3D
var _ghost: MeshInstance3D
var _wide_ring: TorusMesh
var _spot_ring: TorusMesh
var _placed_ring: MeshInstance3D
var _selected_ring: MeshInstance3D
var _selected_id := -1
var _drag := {}
var _panel_stale := false
var _place_group := ""
var _place_search := ""
var _place_items: VBoxContainer
var _placed_ring_until := 0.0
var _placed_pointer := NO_POINTER
var _click_pointer := NO_POINTER
var _placed_note := ""
var _zones: Decal
var _zone_masks := {}
var _zone_wanted := -1.0
var _zone_task := -1
var _zone_task_key := -1.0
var _zone_version := 0
var _zone_task_version := 0
var _raised_land := false
var _zone_result := []
var _problems := []
var _problem_index := -1
var _problem_row: HBoxContainer
var _problem_label: Label
var _problem_button: Button
var _problem_markers: Node3D
var _problem_zones: Decal
var _track_problems := false
var _problems_pending := false
var _options: VBoxContainer
var _options_header: VBoxContainer
var _options_scroll: ScrollContainer
var _slider_finishes: Array[Callable] = []
var _slider_states: Array[Dictionary] = []
var _finishing_edits := false
var _leave_dialog: ConfirmationDialog
var _status: Label
var _save_label: Label
var _save_failure := ""
var _hint: PanelContainer
var _hint_text: Label
var _tools := {}
var _item_buttons := {}
var _day_button: Button
var _dusk_button: Button
var _undo_button: Button
var _redo_button: Button
var _title_box: LineEdit
var _quality_pick: OptionButton
var _dirty_at := -1.0
var _stroke: Dictionary = {}
var _stroke_added: Array = []
var _stroke_removed: Array = []
var _stroke_skipped := 0
var _land_constraints := {}
var _land_constraints_ready := false
var _painting := false
var _panning := false
var _last_brush := Vector3.ZERO
var _last_dab := 0.0
var _last_settle := 0.0
var _target := Vector3(0, 1, 0)
var _zoom := DEFAULT_ZOOM
var _rng := Templates.Rng.new(12345)
var _next_scale := 1.0
var _next_turn := 0.0
var _progress: ProgressBar
var _exporting := false
var _job: BakeJob
var _job_started := 0
var _after_job := Callable()
var _quality := "final"
var _cancel: Button
var _result_button: Button
var _result_path := ""
var _save_rendered_button: Button
var _recovery_path := ""
var _export_button: Button
var _preview_button: Button
var _stage: SubViewportContainer
var _stage_holder: Control
var _lock: PanelContainer
var _frozen: TextureRect
var _overlay: Control
var _redraw_frames := 0
var _own_commit := false
var _applied_sky := ""
var _lamp_theme := "light"

func open(document: WorldDoc, at: String) -> void:
	doc = document
	path = at
	history = History.new(doc)
	history.changed.connect(_on_changed)
	history.steps_changed.connect(_on_steps_changed)
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		_quality = "draft"
	_build_ui()
	_build_world()
	_update_raised_land()
	_roll_next()
	_select_tool(tool)
	_update_undo_buttons()
	if path == "" or doc.water_adjusted:
		_mark_dirty()
	else:
		_save_label.text = "Saved"
		_save_label.tooltip_text = path
	_set_status(doc.notice if doc.notice != "" else ("Water was lowered to keep the Yard dry." if doc.water_adjusted else "Ready. Use Preview to check rendered lighting."))
	_refresh_problems()

func _build_ui() -> void:
	var page := PanelContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("bg"), Color.TRANSPARENT, 0, 0, 0))
	add_child(page)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	page.add_child(column)

	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("surface"), Color.TRANSPARENT, 0, 14, 8))
	column.add_child(bar)
	var top := HBoxContainer.new()
	bar.add_child(top)
	var home := Button.new()
	home.text = "‹ Worlds"
	home.tooltip_text = "Save and go back to your worlds"
	home.pressed.connect(func(): request_leave(func(): closed.emit()))
	top.add_child(home)
	_title_box = LineEdit.new()
	_title_box.text = str(doc.data.title)
	_title_box.custom_minimum_size = Vector2(220, 0)
	_title_box.max_length = 128
	_title_box.tooltip_text = "Previewing with halls and crews from " + str(Yard.data().worlds[doc.data.base].title)
	_title_box.text_submitted.connect(func(_t):
		_commit_title()
		_title_box.release_focus())
	_title_box.focus_exited.connect(_commit_title)
	_title_box.text_changed.connect(func(_text): _refresh_save_label())
	top.add_child(_title_box)
	_save_label = ProTheme.note("")
	_save_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(_save_label)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_undo_button = Button.new()
	_undo_button.text = "Undo"
	_undo_button.pressed.connect(_undo)
	top.add_child(_undo_button)
	_redo_button = Button.new()
	_redo_button.text = "Redo"
	_redo_button.pressed.connect(_redo)
	top.add_child(_redo_button)
	var times := ButtonGroup.new()
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 0)
	top.add_child(time_row)
	_day_button = Button.new()
	_day_button.text = "Day"
	_day_button.tooltip_text = "See and edit your world by day"
	_dusk_button = Button.new()
	_dusk_button.text = "Dusk"
	_dusk_button.tooltip_text = "See and edit your world at dusk"
	for b in [_day_button, _dusk_button]:
		ProTheme.tool_button(b)
		b.button_group = times
		time_row.add_child(b)
	_day_button.button_pressed = true
	_day_button.pressed.connect(func(): _set_time("light"))
	_dusk_button.pressed.connect(func(): _set_time("dark"))
	_preview_button = Button.new()
	_preview_button.text = "Preview"
	_preview_button.tooltip_text = "Render the area round the Yard as it will look in your world"
	_preview_button.pressed.connect(_show_preview)
	top.add_child(_preview_button)
	_quality_pick = OptionButton.new()
	_quality_pick.add_item("Draft")
	_quality_pick.add_item("Final")
	_quality_pick.selected = 0 if _quality == "draft" else 1
	_quality_pick.tooltip_text = "Draft is much faster. Final gives the best picture, and is best on a dedicated graphics card."
	_quality_pick.item_selected.connect(func(i): _quality = "draft" if i == 0 else "final")
	top.add_child(_quality_pick)
	_export_button = Button.new()
	_export_button.text = "Export world…"
	_export_button.tooltip_text = "Render and save a world file"
	ProTheme.primary(_export_button)
	_export_button.pressed.connect(_export_dialog)
	top.add_child(_export_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(170, 0)
	left.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("surface"), Color.TRANSPARENT, 0, 10, 12))
	body.add_child(left)
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	left.add_child(tools)
	tools.add_child(ProTheme.heading("Tools"))
	for entry in [[Tool.SCATTER, "Place things", "P"], [Tool.ARRANGE, "Move things", "M"], [Tool.ERASE, "Clear things", "C"], [Tool.LAND, "Shape land", "L"], [Tool.GROUND, "Paint ground", "G"], [Tool.WATER, "Water", "W"], [Tool.MOOD, "Sky and light", "S"], [Tool.LOOK, "Just look", "V"]]:
		var b := Button.new()
		b.text = entry[1]
		b.tooltip_text = "%s (%s)" % [entry[1], entry[2]]
		ProTheme.tool_button(b)
		var id: int = entry[0]
		b.pressed.connect(func(): _select_tool(id))
		tools.add_child(b)
		_tools[id] = b
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	tools.add_child(ProTheme.note("Scroll to zoom. Drag with the right mouse button to move around."))
	var reset := Button.new()
	reset.text = "Reset view"
	reset.tooltip_text = "Back to the Yard's own view (Home)"
	reset.pressed.connect(_reset_view)
	tools.add_child(reset)

	_stage_holder = Control.new()
	_stage_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_holder.clip_contents = true
	body.add_child(_stage_holder)
	_stage = SubViewportContainer.new()
	_stage.stretch = true
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.gui_input.connect(_on_stage_input)
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.mouse_exited.connect(func():
		_finish_edits()
		_on_stage_left())
	_stage.resized.connect(_redraw)
	_stage_holder.add_child(_stage)
	_frozen = TextureRect.new()
	_frozen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frozen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frozen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_frozen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frozen.visible = false
	_stage_holder.add_child(_frozen)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_stage.add_child(_viewport)
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("surface"), ProTheme.color("border"), 6, 8, 4))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_hint_text = Label.new()
	_hint_text.add_theme_font_size_override("font_size", 13)
	_hint_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(_hint_text)
	_stage_holder.add_child(_hint)
	_lock = PanelContainer.new()
	_lock.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("surface"), ProTheme.color("border"), 8, 12, 6))
	_lock.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lock.position.y = 12
	_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock.visible = false
	var lock_text := ProTheme.note("Rendering. Editing is paused until it finishes.")
	lock_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_lock.add_child(lock_text)
	_stage_holder.add_child(_lock)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(304, 0)
	right.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("surface"), Color.TRANSPARENT, 0, 14, 12))
	body.add_child(right)
	var options_column := VBoxContainer.new()
	right.add_child(options_column)
	_options_header = VBoxContainer.new()
	_options_header.visible = false
	options_column.add_child(_options_header)
	var scroll := ScrollContainer.new()
	_options_scroll = scroll
	scroll.resized.connect(_schedule_reveal_choice)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_column.add_child(scroll)
	_options = VBoxContainer.new()
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_options)

	var foot := PanelContainer.new()
	foot.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("surface"), Color.TRANSPARENT, 0, 14, 6))
	column.add_child(foot)
	var foot_content := VBoxContainer.new()
	foot_content.add_theme_constant_override("separation", 2)
	foot.add_child(foot_content)
	_problem_row = HBoxContainer.new()
	_problem_row.visible = false
	foot_content.add_child(_problem_row)
	_problem_label = ProTheme.note("")
	_problem_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_problem_row.add_child(_problem_label)
	_problem_button = Button.new()
	_problem_button.text = "Show problem"
	_problem_button.pressed.connect(_show_problem)
	_problem_row.add_child(_problem_button)
	var foot_row := HBoxContainer.new()
	foot_content.add_child(foot_row)
	_status = ProTheme.note("")
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot_row.add_child(_status)
	_result_button = Button.new()
	_result_button.text = "Show in folder"
	_result_button.visible = false
	_result_button.pressed.connect(func(): OS.shell_show_in_file_manager(_result_path))
	foot_row.add_child(_result_button)
	_save_rendered_button = Button.new()
	_save_rendered_button.text = "Save rendered world…"
	_save_rendered_button.tooltip_text = "Save the completed export without rendering again. Later edits are not included."
	_save_rendered_button.visible = false
	_save_rendered_button.pressed.connect(_save_rendered_dialog)
	foot_row.add_child(_save_rendered_button)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(220, 8)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.show_percentage = false
	_progress.visible = false
	foot_row.add_child(_progress)
	_cancel = Button.new()
	_cancel.text = "Stop"
	_cancel.visible = false
	_cancel.pressed.connect(func():
		if _job:
			_cancel.disabled = true
			_cancel.text = "Stopping…"
			_job.cancel())
	foot_row.add_child(_cancel)

func _build_world() -> void:
	_scene = WorldScene.new()
	_viewport.add_child(_scene)
	_scene.build(doc)
	_add_hall_markers()
	_env = Environment.new()
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = _env
	_viewport.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_viewport.add_child(_sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.far = 900.0
	_viewport.add_child(_camera)
	_camera.current = true
	_place_camera()
	_brush = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.97
	ring.outer_radius = 1.0
	ring.rings = 64
	_brush.mesh = ring
	_wide_ring = ring
	_spot_ring = TorusMesh.new()
	_spot_ring.inner_radius = 0.86
	_spot_ring.outer_radius = 1.0
	_spot_ring.rings = 64
	_brush_material = StandardMaterial3D.new()
	_brush_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brush_material.albedo_color = ProTheme.color("accent")
	_brush_material.no_depth_test = true
	_brush.material_override = _brush_material
	_brush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush.visible = false
	_viewport.add_child(_brush)
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.transparency = 0.25
	_ghost.visible = false
	_viewport.add_child(_ghost)
	_placed_ring = MeshInstance3D.new()
	_placed_ring.mesh = _spot_ring
	var placed_material: StandardMaterial3D = _brush_material.duplicate()
	placed_material.albedo_color = ProTheme.color("ok")
	_placed_ring.material_override = placed_material
	_placed_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_placed_ring.visible = false
	_viewport.add_child(_placed_ring)
	_selected_ring = MeshInstance3D.new()
	_selected_ring.mesh = _spot_ring
	_selected_ring.material_override = _brush_material.duplicate()
	_selected_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selected_ring.visible = false
	_viewport.add_child(_selected_ring)
	_zones = Decal.new()
	_zones.size = Vector3(WorldDoc.TERRAIN_SIZE, 400.0, WorldDoc.TERRAIN_SIZE)
	_zones.modulate = Color(ProTheme.color("danger"), 0.28)
	_zones.albedo_mix = 1.0
	_zones.upper_fade = 0.0
	_zones.lower_fade = 0.0
	_zones.normal_fade = 0.0
	_zones.visible = false
	_viewport.add_child(_zones)
	_problem_markers = Node3D.new()
	_viewport.add_child(_problem_markers)
	_problem_zones = Decal.new()
	_problem_zones.size = _zones.size
	_problem_zones.modulate = Color(ProTheme.color("danger"), 0.4)
	_problem_zones.albedo_mix = 1.0
	_problem_zones.upper_fade = 0.0
	_problem_zones.lower_fade = 0.0
	_problem_zones.normal_fade = 0.0
	_problem_zones.visible = false
	_viewport.add_child(_problem_zones)
	_apply_mood()

func _add_hall_markers() -> void:
	var d := Yard.data()
	var real := _real_halls()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(ProTheme.LIGHT["accent"], 0.32)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for id in d.halls:
		var p: Dictionary = d.halls[id]
		if real.has(id):
			real[id].position = Vector3(p.x, 0, p.z)
			continue
		var half: float = d.hall.docker if id == "docker" else d.hall.half
		var height: float = d.hall.dockerHeight if id == "docker" else d.hall.height
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(half * 2.0, height, half * 2.0)
		block.mesh = box
		block.position = Vector3(p.x, height / 2.0, p.z)
		block.material_override = mat
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_viewport.add_child(block)

func _real_halls() -> Dictionary:
	var out := {}
	var root: Node3D = WorldScene.halls_scene(doc.data.base)
	if root == null:
		return out
	_viewport.add_child(root)
	for child in root.get_children():
		var n := String(child.name)
		if n.begins_with("hall_") and n.count("_") == 1:
			out[n.trim_prefix("hall_")] = child
		elif child is Node3D:
			child.visible = false
	return out

func _redraw() -> void:
	_redraw_frames = 2

func _place_camera() -> void:
	var cam: Dictionary = Yard.data().camera
	var offset := Vector3(cam.offset[0], cam.offset[1], cam.offset[2]) * 6.0
	_camera.size = cam.height / _zoom
	_camera.look_at_from_position(_target + offset, _target, Vector3.UP)
	_redraw()

func _reset_view() -> void:
	_target = Vector3(0, 1, 0)
	_zoom = DEFAULT_ZOOM
	_place_camera()

func _apply_mood() -> void:
	var m: Dictionary = doc.data.mood[theme_name]
	if _applied_sky != m.sky:
		_applied_sky = m.sky
		var sky := Sky.new()
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = WorldScene.sky_texture(m.sky)
		sky.sky_material = mat
		_env.sky = sky
		_env.sky_rotation = Vector3(0, PI / 2, 0)
		_env.background_mode = Environment.BG_SKY
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.background_energy_multiplier = sqrt(float(m.strength))
	var c: Array = m.sun_color
	_sun.light_color = Color(c[0], c[1], c[2]).linear_to_srgb()
	_sun.light_energy = float(m.sun_energy) / PI
	_sun.look_at_from_position(Yard.sun(theme_name), Vector3.ZERO, Vector3.UP)
	if _lamp_theme != theme_name:
		_lamp_theme = theme_name
		_scene.refresh_things(theme_name)
	_redraw()

func _set_time(theme: String) -> void:
	if theme_name == theme or _exporting:
		return
	_finish_edits()
	_dismiss_preview()
	theme_name = theme
	_day_button.set_pressed_no_signal(theme == "light")
	_dusk_button.set_pressed_no_signal(theme == "dark")
	_apply_mood()
	if tool == Tool.MOOD:
		_build_options()

func _toggle_time() -> void:
	_set_time("dark" if theme_name == "light" else "light")

func _select_tool(id: int) -> void:
	if _exporting:
		return
	_finish_edits()
	_dismiss_preview()
	tool = id
	_selected_id = -1
	_show_selection()
	for k in _tools:
		_tools[k].button_pressed = k == id
	_stage.mouse_default_cursor_shape = Control.CURSOR_DRAG if id in [Tool.LOOK, Tool.WATER, Tool.MOOD] else (Control.CURSOR_ARROW if id == Tool.ARRANGE else Control.CURSOR_CROSS)
	_build_options()
	_on_stage_left()
	_update_zones()

func _clear_options() -> void:
	_finish_edits()
	_slider_finishes.clear()
	_slider_states.clear()
	_item_buttons.clear()
	_options_header.visible = false
	for box in [_options_header, _options]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()

func _build_options() -> void:
	_clear_options()
	if _exporting:
		_options.add_child(ProTheme.heading("Rendering"))
		_options.add_child(ProTheme.note("Your tools will be back when this finishes. Stop it from the bar at the bottom."))
		var butler := ProTheme.brand("bot-butler", 210)
		butler.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_options.add_child(butler)
		return
	match tool:
		Tool.SCATTER:
			_build_place_options()
		Tool.ARRANGE:
			_build_arrange_options()
		Tool.ERASE:
			_options.add_child(ProTheme.heading("Clear things"))
			_options.add_child(ProTheme.note("Drag over anything you've placed to remove it."))
			_brush_slider()
		Tool.LAND:
			_options.add_child(ProTheme.heading("Shape land"))
			_options.add_child(ProTheme.note("Hold to keep shaping. The ground where your crews stand, shaded red, always stays flat."))
			_brush_slider()
			for mode in [["raise", "Raise"], ["lower", "Lower"], ["smooth", "Smooth"]]:
				var b := Button.new()
				b.text = mode[1]
				ProTheme.tool_button(b)
				b.button_pressed = land_mode == mode[0]
				b.pressed.connect(func():
					land_mode = mode[0]
					_build_options())
				_options.add_child(b)
		Tool.GROUND:
			_options.add_child(ProTheme.heading("Paint ground"))
			_options.add_child(ProTheme.note("Drag to paint the chosen ground."))
			_brush_slider()
			var grid := _item_grid()
			for i in WorldScene.GROUND_ORDER.size():
				var key: String = WorldScene.GROUND_ORDER[i]
				var label: String = WorldScene.load_kit().get("grounds", {}).get(key, {}).get("label", key)
				var index: int = i
				var b := _item_button(label, "ground_" + key, ground_kind == i, func():
					ground_kind = index
					_build_options())
				grid.add_child(b)
		Tool.WATER:
			_options.add_child(ProTheme.heading("Water"))
			_options.add_child(ProTheme.note("Water fills lower land. Lower some land to make a lake; the Yard stays dry."))
			var on := CheckBox.new()
			on.text = "This world has water"
			on.button_pressed = float(doc.data.water_level) > -50.0
			_options.add_child(on)
			var level := doc.safe_water_level() if on.button_pressed else -0.6
			var s := _slider("Water level", minf(WATER_LOWEST, floorf(level)), WorldDoc.MAX_WATER_LEVEL, 0.1, level, "%.1f m",
				func(v):
					doc.data.water_level = v
					_scene.refresh_water()
					_redraw(),
				func(v, was): _commit_value("Water level", doc.data, "water_level", v, was))
			s.editable = on.button_pressed
			on.toggled.connect(func(v):
				_finish_edits()
				s.editable = v
				_commit_value("Water", doc.data, "water_level", s.value if v else -100.0, null)
				if v:
					_set_status("Water enabled. It appears wherever land is below %.1f m." % s.value))
		Tool.MOOD:
			_build_mood_options()
		_:
			_options.add_child(ProTheme.heading("Just look"))
			_options.add_child(ProTheme.note("Drag to move around. Scroll to zoom. Use Preview to check rendered lighting."))

func _build_mood_options() -> void:
	var m: Dictionary = doc.data.mood[theme_name]
	var time_name := "Day" if theme_name == "light" else "Dusk"
	_options.add_child(ProTheme.heading("Sky and light: " + time_name))
	_options.add_child(ProTheme.note("You're editing %s. Use the Day and Dusk buttons above to switch. The sun's direction is fixed, because the Yard's live shadows must match it." % time_name.to_lower()))
	_options.add_child(ProTheme.heading("Season", 13))
	var seasons := HBoxContainer.new()
	seasons.name = "Seasons"
	seasons.add_theme_constant_override("separation", 4)
	_options.add_child(seasons)
	for season in WorldDoc.SEASONS:
		var b := Button.new()
		b.text = season.capitalize()
		b.tooltip_text = "Dress the whole world for %s, by day and at dusk. Your things stay where they are." % season
		ProTheme.tool_button(b)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.button_pressed = doc.season() == season
		b.pressed.connect(func(): _set_season(season))
		seasons.add_child(b)
	_options.add_child(ProTheme.heading("Sky and sun", 13))
	var skies: Dictionary = WorldScene.load_kit().get("skies", {})
	var pick := OptionButton.new()
	var keys := skies.keys()
	for i in keys.size():
		pick.add_item(skies[keys[i]].label)
		if keys[i] == m.sky:
			pick.selected = i
	pick.item_selected.connect(func(i):
		_finish_edits()
		history.set_values("Sky", m, {"sky": keys[i], "strength": float(skies[keys[i]].strength)}))
	_options.add_child(pick)
	_slider("Sun strength", 0.5, 5.0, 0.1, float(m.sun_energy), "%.1f",
		func(v):
			m.sun_energy = v
			_apply_mood(),
		func(v, was): _commit_value("Sun strength", m, "sun_energy", v, was))
	_slider("Sky strength", 0.1, 1.5, 0.05, float(m.strength), "%.2f",
		func(v):
			m.strength = v
			_apply_mood(),
		func(v, was): _commit_value("Sky strength", m, "strength", v, was))

func _set_season(season: String) -> void:
	_finish_edits()
	_dismiss_preview()
	if doc.season() == season:
		_build_options()
		return
	history.set_value("Season", doc.data, "season", season, doc.season())
	_set_status("%s. Preview shows how it renders." % season.capitalize())

func _build_place_options() -> void:
	_options_header.visible = true
	_options_header.add_child(ProTheme.heading("Place things"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	_options_header.add_child(modes)
	for entry in [["one", "Place one"], ["paint", "Paint an area"]]:
		var b := Button.new()
		b.text = entry[1]
		ProTheme.tool_button(b)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = place_mode == entry[0]
		var mode: String = entry[0]
		b.pressed.connect(func():
			place_mode = mode
			_build_options()
			_update_zones())
		modes.add_child(b)
	if place_mode == "one":
		_options.add_child(ProTheme.note("Choose something, then click where it goes. Q and E turn it first."))
		var turns := HBoxContainer.new()
		turns.name = "Turns"
		turns.add_theme_constant_override("separation", 4)
		_options.add_child(turns)
		for entry in [["Turn (Q)", -1.0, "Turns it clockwise"], ["Turn (E)", 1.0, "Turns it anticlockwise"]]:
			var b := Button.new()
			b.text = entry[0]
			b.tooltip_text = entry[2]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 13)
			var direction: float = entry[1]
			b.pressed.connect(func(): _turn_next(direction))
			turns.add_child(b)
	else:
		_options.add_child(ProTheme.note("Drag to paint. A mix paints several things together."))
		_brush_slider()
		_options.add_child(ProTheme.heading("Mixes", 13))
		var mixes := _item_grid()
		for key in Placing.MIXES:
			var mix_key: String = "mix:" + key
			mixes.add_child(_choice_button(mix_key, Placing.MIXES[key].label, "mix_" + key))
	var tall_note := ProTheme.note("Tall things only fit further out, where they can't hide the Yard. Red shows where they can't go.")
	tall_note.name = "TallNote"
	_options.add_child(tall_note)
	var wider := Button.new()
	wider.name = "Wider"
	wider.text = "Zoom out to see more"
	wider.pressed.connect(func():
		_zoom = WIDE_ZOOM
		_place_camera())
	_options.add_child(wider)
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	if models.has(_chosen()):
		_place_group = models[_chosen()].group
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search items"
	search.clear_button_enabled = true
	search.text = _place_search
	search.text_changed.connect(func(text):
		_place_search = text
		_fill_place_items())
	_options.add_child(search)
	var groups := GridContainer.new()
	groups.name = "Groups"
	groups.columns = 3
	groups.add_theme_constant_override("h_separation", 4)
	groups.add_theme_constant_override("v_separation", 4)
	_options.add_child(groups)
	for entry in PLACE_GROUPS:
		var group: String = entry[0]
		if not models.values().any(func(m): return m.group == group):
			continue
		var b := Button.new()
		b.text = entry[1]
		ProTheme.tool_button(b)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.button_pressed = _place_group == group
		b.pressed.connect(func():
			_place_group = group
			for other in groups.get_children():
				other.button_pressed = other == b
			if _place_search != "":
				_place_search = ""
				search.text = ""
			_fill_place_items())
		groups.add_child(b)
	_place_items = VBoxContainer.new()
	_options.add_child(_place_items)
	_fill_place_items()
	_refresh_tall_note()
	_schedule_reveal_choice.call_deferred()

func _fill_place_items() -> void:
	for key in _item_buttons.keys():
		if not key.begins_with("mix:"):
			_item_buttons.erase(key)
	for c in _place_items.get_children():
		_place_items.remove_child(c)
		c.queue_free()
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var wanted := _place_search.strip_edges().to_lower()
	var grid := _item_grid(_place_items)
	for key in models:
		var fits: bool = str(models[key].label).to_lower().contains(wanted) if wanted != "" else models[key].group == _place_group
		if fits:
			grid.add_child(_choice_button(key, models[key].label, key))
	if grid.get_child_count() == 0:
		_place_items.add_child(ProTheme.note("Nothing matches that."))

func _schedule_reveal_choice() -> void:
	if not get_tree().process_frame.is_connected(_reveal_choice):
		get_tree().process_frame.connect(_reveal_choice, CONNECT_ONE_SHOT)

func _reveal_choice() -> void:
	if _item_buttons.has(_chosen()):
		_options_scroll.ensure_control_visible(_item_buttons[_chosen()])

func _item_grid(parent: Control = null) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	(parent if parent else _options).add_child(grid)
	return grid

func _item_button(label: String, thumb: String, selected: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	ProTheme.tool_button(b)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = true
	b.clip_text = true
	b.icon = ProTheme.thumb(thumb)
	ProTheme.picture_button(b)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(128, 104 if b.icon else 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = label
	b.button_pressed = selected
	b.pressed.connect(on_press)
	return b

func _choice_button(key: String, label: String, thumb: String) -> Button:
	var selected := _chosen() == key
	var b := _item_button(label, thumb, selected, func(): _choose(key))
	_item_buttons[key] = b
	return b

func _chosen() -> String:
	return place_kind if place_mode == "one" else paint_choice

func _choose(key: String) -> void:
	_finish_edits()
	_dismiss_preview()
	if place_mode == "one":
		place_kind = key
	else:
		paint_choice = key
		if not key.begins_with("mix:"):
			place_kind = key
	for k in _item_buttons:
		_item_buttons[k].button_pressed = k == key
	_refresh_tall_note()
	_update_zones()
	_roll_next()
	_load_chosen()

func _refresh_tall_note() -> void:
	var tall := _chosen_is_tall()
	for n in ["TallNote", "Wider"]:
		var node := _options.get_node_or_null(n)
		if node:
			node.visible = tall

func _chosen_kinds() -> Array:
	if place_mode == "paint":
		return Placing.kinds_of(paint_choice)
	return [place_kind]

func _tallest_chosen() -> float:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var top := 0.0
	for kind in _chosen_kinds():
		top = maxf(top, float(models.get(kind, {}).get("height", 1.0)))
	return top

## Whether anything chosen could stand tall enough to be refused for its height,
## at the largest size it may be placed.
func _chosen_is_tall() -> bool:
	return _tallest_chosen() * (Placing.SMALLEST if place_mode == "one" else Placing.LARGEST) > 1.0

func _brush_slider() -> void:
	_slider("Brush size", 1.0, 40.0, 0.5, brush_radius, "%.1f m", func(v):
		brush_radius = v
		_set_brush_ring(v), Callable())

func _commit_value(label: String, holder: Dictionary, key: String, value: Variant, was: Variant) -> void:
	_own_commit = true
	history.set_value(label, holder, key, value, was)
	_own_commit = false

func _slider(label: String, lo: float, hi: float, step: float, value: float, format: String, live: Callable, commit: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var name_label := ProTheme.note(label)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var readout := ProTheme.note(format % value)
	readout.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(readout)
	_options.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	var state := {"start": s.value, "exact": value, "touched": false, "dragging": false, "pending": false}
	_slider_states.append(state)
	var settle := Timer.new()
	settle.one_shot = true
	settle.wait_time = COMMIT_SECONDS
	s.add_child(settle)
	var finish := func():
		settle.stop()
		state.dragging = false
		state.pending = false
		if not commit.is_valid():
			return
		if s.value != state.start:
			var was: float = state.exact
			state.start = s.value
			state.exact = s.value
			state.touched = false
			commit.call(s.value, was)
		elif state.touched:
			state.touched = false
			live.call(state.exact)
	_slider_finishes.append(finish)
	settle.timeout.connect(finish)
	s.drag_started.connect(func(): state.dragging = true)
	s.drag_ended.connect(func(_changed):
		state.dragging = false
		finish.call())
	s.value_changed.connect(func(v):
		_dismiss_preview()
		for i in _slider_states.size():
			if not is_same(_slider_states[i], state) and _slider_states[i].touched:
				_slider_finishes[i].call()
		state.touched = true
		state.pending = v != state.start
		readout.text = format % v
		live.call(v)
		if commit.is_valid():
			_mark_dirty()
		if not state.dragging:
			settle.start())
	_options.add_child(s)
	return s

func _finish_edits() -> void:
	if _finishing_edits or history == null:
		return
	_finishing_edits = true
	_painting = false
	_panning = false
	_finish_stroke()
	_finish_drag()
	for finish in _slider_finishes.duplicate():
		finish.call()
	_finishing_edits = false
	if _panel_stale:
		_panel_stale = false
		_build_options()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and (_painting or not _drag.is_empty()):
			_finish_edits()
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and history != null:
		_finish_edits()
		_on_stage_left()

func _dismiss_preview() -> void:
	if _overlay:
		_overlay.hide()
		_overlay.queue_free()
		_overlay = null
		_redraw()

## Where the pointer meets the land, by walking along its ray.
func _ground_at(pos: Vector2) -> Variant:
	var o := _camera.project_ray_origin(pos)
	var d := _camera.project_ray_normal(pos)
	var t := 0.0
	var dt := 2.0
	for i in 800:
		var p := o + d * t
		if p.y <= doc.height_at(p.x, p.z):
			if i == 0:
				return p
			var above := t - dt
			var below := t
			for step in 12:
				var middle := (above + below) / 2.0
				var q := o + d * middle
				if q.y <= doc.height_at(q.x, q.z):
					below = middle
				else:
					above = middle
			return o + d * below
		t += dt
	return null

func _pan_by(pixels: Vector2, metres_per_pixel: float) -> void:
	var a := Yard.axes()
	var flat_up: Vector3 = (a.up as Vector3)
	flat_up.y = 0.0
	flat_up = flat_up.normalized() / maxf(0.01, a.up.dot(flat_up.normalized()))
	_target -= (a.right as Vector3) * pixels.x * metres_per_pixel
	_target += flat_up * pixels.y * metres_per_pixel
	_target.x = clampf(_target.x, -150.0, 150.0)
	_target.z = clampf(_target.z, -150.0, 150.0)

## Zooms so the ground under the pointer stays under the pointer.
func _zoom_at(pos: Vector2, zoom: float) -> void:
	var before: float = _camera.size / float(_viewport.size.y)
	_zoom = zoom
	var cam: Dictionary = Yard.data().camera
	var after: float = cam.height / _zoom / float(_viewport.size.y)
	_pan_by(Vector2(_viewport.size) / 2.0 - pos, before - after)
	_place_camera()

func _on_stage_input(event: InputEvent) -> void:
	if _exporting:
		return
	if event is InputEventMouseButton:
		if event.pressed:
			get_viewport().gui_release_focus()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, minf(_zoom * 1.1, 3.8))
			_update_cursor(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, maxf(_zoom / 1.1, 0.25))
			_update_cursor(event.position)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and tool in [Tool.LOOK, Tool.WATER, Tool.MOOD]):
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				_finish_edits()
			elif tool == Tool.ARRANGE:
				_press_thing(event.position)
			else:
				_begin_stroke(event.position)
	elif event is InputEventMouseMotion:
		if _panning:
			_pan_by(event.relative, _camera.size / float(_viewport.size.y))
			_place_camera()
		if _painting:
			_continue_stroke(event.position)
		if not _drag.is_empty():
			_drag_thing(event.position)
		_update_cursor(event.position)

func _on_stage_left() -> void:
	if _brush == null:
		return
	if _brush.visible or _ghost.visible:
		_redraw()
	_brush.visible = false
	_ghost.visible = false
	_hint.visible = false

func _set_brush_ring(radius: float) -> void:
	if _brush:
		_brush.scale = Vector3.ONE * radius
		_redraw()

func _show_hint(text: String, at: Vector2) -> void:
	_hint.visible = text != ""
	if text == "":
		return
	_hint_text.text = text
	_hint.reset_size()
	var spot := at + Vector2(18, 18)
	var room := _stage_holder.size - _hint.size - Vector2(4, 4)
	_hint.position = Vector2(minf(spot.x, room.x), minf(spot.y, room.y))

## What the pointer would do here: where it lands, what it would look like, and
## why it would be refused.
func _update_cursor(pos: Vector2) -> void:
	if tool == Tool.ARRANGE:
		_arrange_cursor(pos)
		return
	var hit = _ground_at(pos)
	var shows_brush := tool in [Tool.LAND, Tool.GROUND, Tool.SCATTER, Tool.ERASE]
	if hit == null or not shows_brush:
		_on_stage_left()
		return
	if tool == Tool.SCATTER and place_mode == "one":
		hit = Placing.snapped(doc, place_kind, hit)
	_brush.visible = true
	_brush.mesh = _spot_ring if tool == Tool.SCATTER and place_mode == "one" else _wide_ring
	_brush.position = hit + Vector3.UP * 0.1
	_redraw()
	var colour := ProTheme.color("accent")
	var text := ""
	match tool:
		Tool.SCATTER:
			if place_mode == "one":
				if _placed_pointer != NO_POINTER:
					if pos.distance_to(_placed_pointer) <= PLACED_QUIET_PIXELS:
						_on_stage_left()
						return
					_placed_pointer = NO_POINTER
				text = _why_not_place(hit)
				var fitted := Placing.fitted_scale(doc, place_kind, hit.x, hit.z, _next_scale)
				_brush.scale = Vector3.ONE * _footprint(place_kind, fitted)
				_ghost.visible = text == "" and WorldScene.mesh_ready(place_kind)
				if text == "":
					if _ghost.visible:
						_ghost.mesh = _scene.mesh_for(place_kind)
					_ghost.transform = _scene.transform_of({"x": hit.x, "z": hit.z, "turn": _next_turn, "scale": fitted})
					var behind := Placing.hidden_behind(doc, place_kind, hit.x, hit.z, fitted)
					if behind != "":
						text = "Behind the %s: this may be hidden from view." % behind
				else:
					colour = ProTheme.color("danger")
			else:
				_ghost.visible = false
				_brush.scale = Vector3.ONE * brush_radius
		Tool.ERASE:
			_brush.scale = Vector3.ONE * brush_radius
			colour = ProTheme.color("danger")
		Tool.LAND:
			_brush.scale = Vector3.ONE * brush_radius
			if Clearance.must_be_flat(hit.x, hit.z):
				text = "This ground stays flat: your crews stand here."
			elif land_mode == "raise" and hit.y >= Clearance.max_elevation(hit.x, hit.z) - 0.1:
				text = "Higher land here would hide the Yard."
		_:
			_brush.scale = Vector3.ONE * brush_radius
	_brush_material.albedo_color = colour
	_show_hint(text, pos)

func _why_not_place(hit: Vector3) -> String:
	var why := Placing.why_not_one(doc, place_kind, hit.x, hit.z)
	if why == "" and WorldScene.mesh_of(place_kind).get_surface_count() == 0:
		return "%s couldn't be loaded. Extract the complete app ZIP, including its kits folder." % _thing_name(place_kind)
	return why

## Shows that a model is loading before the pause it takes, the first time it's chosen.
func _load_chosen() -> void:
	var waiting: Array = _chosen_kinds().filter(func(kind): return not WorldScene.mesh_ready(kind))
	if waiting.is_empty():
		return
	var said := _status.text
	_set_status("Loading %s…" % _thing_name(waiting[0]))
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for kind in waiting:
		WorldScene.mesh_of(kind)
	_set_status(said)

func _build_arrange_options() -> void:
	_options.add_child(ProTheme.heading("Move things"))
	_options.add_child(ProTheme.note("Click something to choose it, then drag it somewhere new. Q and E turn it. Delete removes it."))
	var thing := _selected()
	if thing.is_empty():
		return
	_options.add_child(ProTheme.heading(_thing_name(thing.kind), 13))
	var exact_turn: float = thing.turn
	var shown_turn := rad_to_deg(wrapf(exact_turn, 0.0, TAU))
	var modular := Placing.modular(thing.kind)
	_slider("Turn", 0.0, 270.0 if modular else 360.0, 90.0 if modular else 1.0, shown_turn, "%.0f°",
		func(v): _preview_selected("turn", exact_turn if v == shown_turn else deg_to_rad(v)),
		func(_v, was): _commit_selected("Turn", "turn", exact_turn if was == shown_turn else deg_to_rad(was)))
	if not modular:
		_size_slider(thing)
	var remove := Button.new()
	remove.text = "Remove"
	remove.pressed.connect(_remove_selected)
	_options.add_child(remove)

func _size_slider(thing: Dictionary) -> void:
	var room := floorf(Placing.largest_scale(doc, thing.kind, thing.x, thing.z) * 100.0) / 100.0
	_slider("Size", SMALLEST_SIZE, maxf(float(thing.scale), minf(LARGEST_SIZE, room)), 0.01, float(thing.scale), "%.2f×",
		func(v): _preview_selected("scale", v),
		func(_v, was): _commit_selected("Resize", "scale", was))

func _selected() -> Dictionary:
	if _selected_id >= 0:
		for t in doc.data.things:
			if int(t.id) == _selected_id:
				return t
	return {}

## Everything shown about the chosen thing depends on where it stands, so any
## change to the world redraws it, once the edit in progress has finished.
func _refresh_selection() -> void:
	var thing := _selected()
	if thing.is_empty() or WorldScene.gone_in(thing.kind, doc.season()):
		_selected_id = -1
	_show_selection()
	if _finishing_edits:
		_panel_stale = true
	else:
		_build_options()

func _select_thing(id: int) -> void:
	_finish_edits()
	_selected_id = id
	_show_selection()
	_build_options()

func _show_selection() -> void:
	if _selected_ring == null:
		return
	var thing := _selected()
	_selected_ring.visible = not thing.is_empty()
	if _selected_ring.visible:
		_selected_ring.position = Vector3(thing.x, doc.height_at(thing.x, thing.z) + 0.1, thing.z)
		_selected_ring.scale = Vector3.ONE * _footprint(thing.kind, float(thing.scale))
	_redraw()

func _preview_selected(field: String, value: Variant) -> void:
	var thing := _selected()
	if thing.is_empty():
		return
	var changed: Dictionary = thing.duplicate()
	changed[field] = value
	doc.data.things[doc.data.things.find(thing)] = changed
	_scene.update_things([changed], [thing])
	_show_selection()

func _commit_selected(label: String, field: String, was: Variant) -> void:
	var thing := _selected()
	if thing.is_empty():
		return
	var before: Dictionary = thing.duplicate()
	before[field] = was
	history.things_edit("%s %s" % [label, _thing_name(thing.kind)], [thing], [before], true)

func _turn_next(direction: float) -> void:
	_next_turn = wrapf(_next_turn + direction * _turn_step(place_kind), 0.0, TAU)
	_update_cursor(_stage.get_local_mouse_position())

func _turn_step(kind: String) -> float:
	return PI / 2.0 if Placing.modular(kind) else TURN_STEP

func _turn_selected(by: float) -> void:
	_finish_edits()
	var thing := _selected()
	if thing.is_empty():
		return
	var changed: Dictionary = thing.duplicate()
	changed.turn = wrapf(float(thing.turn) + by, 0.0, TAU)
	history.things_edit("Turn " + _thing_name(thing.kind), [changed], [thing])

func _remove_selected() -> void:
	_finish_edits()
	var thing := _selected()
	if thing.is_empty():
		return
	_set_status("Removed %s." % _thing_name(thing.kind))
	history.things_edit("Remove " + _thing_name(thing.kind), [], [thing])

## What's under the pointer. Things are judged by their whole upright shape on
## screen, and the closest fit wins, so a fern can be chosen under a tree.
func _thing_at(pos: Vector2) -> Dictionary:
	var models: Dictionary = WorldScene.load_kit().get("models", {})
	var a := Yard.axes()
	var right: Vector3 = a.right
	var up: Vector3 = a.up
	var per_pixel: float = _camera.size / float(_viewport.size.y)
	var origin := _camera.unproject_position(Vector3.ZERO)
	var best := {}
	var best_fit := 1.0
	for t in doc.data.things:
		if WorldScene.gone_in(t.kind, doc.season()):
			continue
		var info: Dictionary = models.get(t.kind, {})
		var s := float(t.scale)
		var radius := maxf(float(info.get("radius", 0.5)) * s * 0.7 / per_pixel, PICK_PIXELS)
		var base_x: float = origin.x + (float(t.x) * right.x + float(t.z) * right.z) / per_pixel
		if absf(base_x - pos.x) >= radius:
			continue
		var base := Vector3(t.x, doc.height_at(t.x, t.z), t.z)
		var from := origin + Vector2(base.dot(right), -base.dot(up)) / per_pixel
		var to := from + Vector2(0.0, -float(info.get("height", 1.0)) * s * up.y / per_pixel)
		var fit := Geometry2D.get_closest_point_to_segment(pos, from, to).distance_to(pos) / radius
		if fit < best_fit:
			best_fit = fit
			best = t
	return best

func _press_thing(pos: Vector2) -> void:
	_dismiss_preview()
	var over := _thing_at(pos)
	_select_thing(int(over.id) if not over.is_empty() else -1)
	if not over.is_empty():
		var base := _camera.unproject_position(Vector3(over.x, doc.height_at(over.x, over.z), over.z))
		_drag = {"from": pos, "grip": (base - pos) * _camera.size / float(_viewport.size.y), "moving": false, "why": "", "hit": null}

func _drag_thing(pos: Vector2) -> void:
	var thing := _selected()
	if thing.is_empty():
		_drag = {}
		return
	if not _drag.moving:
		if pos.distance_to(_drag.from) < DRAG_PIXELS:
			return
		_drag.moving = true
		_scene.update_things([], [thing])
		_selected_ring.visible = false
	var hit = _ground_at(pos + _drag.grip * float(_viewport.size.y) / _camera.size)
	if hit != null:
		hit = Placing.snapped(doc, thing.kind, hit)
		_drag.hit = hit
		_drag.why = Placing.why_not_moved(doc, thing, hit.x, hit.z)

func _arrange_cursor(pos: Vector2) -> void:
	var colour := ProTheme.color("accent")
	var text := ""
	if not _drag.is_empty() and _drag.moving:
		var thing := _selected()
		if _drag.hit == null or thing.is_empty():
			return
		var moved: Dictionary = thing.duplicate()
		moved.x = _drag.hit.x
		moved.z = _drag.hit.z
		_ghost.mesh = _scene.mesh_for(thing.kind)
		_ghost.transform = _scene.transform_of(moved)
		_ghost.visible = true
		_brush.position = _drag.hit + Vector3.UP * 0.1
		_brush.scale = Vector3.ONE * _footprint(thing.kind, float(thing.scale))
		text = _drag.why
		if text != "":
			colour = ProTheme.color("danger")
	else:
		var over := _thing_at(pos)
		if over.is_empty():
			_on_stage_left()
			return
		_ghost.visible = false
		_brush.position = Vector3(over.x, doc.height_at(over.x, over.z) + 0.1, over.z)
		_brush.scale = Vector3.ONE * _footprint(over.kind, float(over.scale))
		text = _thing_name(over.kind)
	_brush.mesh = _spot_ring
	_brush.visible = true
	_brush_material.albedo_color = colour
	_show_hint(text, pos)
	_redraw()

func _finish_drag() -> void:
	if _drag.is_empty():
		return
	var moving: bool = _drag.moving
	var hit = _drag.hit
	var why: String = _drag.why
	_drag = {}
	var thing := _selected()
	if not moving or thing.is_empty():
		return
	_ghost.visible = false
	if hit == null or why != "":
		_scene.update_things([thing], [])
		_show_selection()
		if why != "":
			_set_status(why)
		return
	var moved: Dictionary = thing.duplicate()
	moved.x = hit.x
	moved.z = hit.z
	history.things_edit("Move " + _thing_name(thing.kind), [moved], [thing])
	_set_status("Moved %s." % _thing_name(thing.kind))
	_show_selection()

func _footprint(kind: String, scale: float) -> float:
	return maxf(float(WorldScene.load_kit().get("models", {}).get(kind, {}).get("radius", 0.5)) * scale, 0.8)

func _roll_next() -> void:
	if Placing.modular(place_kind):
		_next_scale = 1.0
		_next_turn = wrapf(snappedf(_next_turn, PI / 2.0), 0.0, TAU)
	else:
		_next_scale = _rng.range_f(Placing.SMALLEST, Placing.LARGEST)
		_next_turn = _rng.range_f(0.0, TAU)
	_update_zones()

func _begin_stroke(pos: Vector2) -> void:
	_finish_edits()
	_dismiss_preview()
	_click_pointer = pos
	_placed_pointer = NO_POINTER
	var hit = _ground_at(pos)
	if hit == null:
		return
	_painting = true
	_stroke = {}
	_stroke_added = []
	_stroke_removed = []
	_stroke_skipped = 0
	_last_brush = hit
	_last_dab = Time.get_ticks_msec() / 1000.0
	_apply_brush(hit, true)

func _brush_spacing() -> float:
	match tool:
		Tool.SCATTER:
			return maxf(brush_radius * 0.35, 1.0)
		Tool.ERASE:
			return maxf(brush_radius * 0.5, 0.5)
		_:
			return maxf(brush_radius * 0.25, WorldDoc.TERRAIN_SIZE / (WorldDoc.TERRAIN_RES - 1))

## Fills the gap between mouse events, so a fast drag leaves a line, not dots.
func _continue_stroke(pos: Vector2) -> void:
	var hit = _ground_at(pos)
	if hit == null:
		return
	if tool == Tool.SCATTER and place_mode == "one":
		return
	var gap: float = (hit - _last_brush).length()
	var spacing := _brush_spacing()
	if gap < spacing:
		return
	var steps := ceili(gap / spacing)
	var from := _last_brush
	for i in range(1, steps + 1):
		_apply_brush(from.lerp(hit, float(i) / steps), false)
	_last_brush = hit
	_last_dab = Time.get_ticks_msec() / 1000.0

func _apply_brush(hit: Vector3, first: bool) -> void:
	match tool:
		Tool.SCATTER:
			_scatter_at(hit, first)
		Tool.ERASE:
			_erase_at(hit)
		Tool.LAND:
			_land_at(hit)
		Tool.GROUND:
			_ground_paint_at(hit)

func _scatter_at(hit: Vector3, first: bool) -> void:
	if place_mode == "one":
		hit = Placing.snapped(doc, place_kind, hit)
		var why := _why_not_place(hit)
		if why != "":
			_set_status(why)
			_update_cursor(_click_pointer)
			return
		var fitted := Placing.fitted_scale(doc, place_kind, hit.x, hit.z, _next_scale)
		var behind := Placing.hidden_behind(doc, place_kind, hit.x, hit.z, fitted)
		_placed_note = " It's behind the %s, so it may be hidden from view." % behind if behind != "" else ""
		_add_stroke_thing(place_kind, hit.x, hit.z, _next_turn, fitted)
		_show_placed_ring(hit, fitted)
		_placed_pointer = _click_pointer
		_on_stage_left()
		_roll_next()
		return
	var kinds := _chosen_kinds()
	for attempt in (1 if first else 2):
		var kind: String = kinds[int(_rng.next() * kinds.size()) % kinds.size()]
		var s := _rng.range_f(Placing.SMALLEST, Placing.LARGEST)
		var a := _rng.range_f(0.0, TAU)
		var r: float = sqrt(_rng.next()) * brush_radius
		var spot := Placing.snapped(doc, kind, Vector3(hit.x + cos(a) * r, 0.0, hit.z + sin(a) * r))
		if Placing.modular(kind):
			s = 1.0
		if Placing.why_not(doc, kind, spot.x, spot.z, s) != "":
			_stroke_skipped += 1
			continue
		var turn := _rng.range_f(0.0, TAU)
		_add_stroke_thing(kind, spot.x, spot.z, snappedf(turn, PI / 2.0) if Placing.modular(kind) else turn, s)

func _show_placed_ring(hit: Vector3, scale: float) -> void:
	_placed_ring.position = hit + Vector3.UP * 0.1
	_placed_ring.scale = Vector3.ONE * _footprint(place_kind, scale)
	_placed_ring.visible = true
	_placed_ring_until = Time.get_ticks_msec() / 1000.0 + PLACED_RING_SECONDS
	_redraw()

func _add_stroke_thing(kind: String, x: float, z: float, turn: float, s: float) -> void:
	var thing := doc.add_thing(kind, x, z, turn, s)
	_stroke_added.append(thing)
	_scene.update_things([thing], [])
	_mark_dirty()
	_redraw()

func _erase_at(hit: Vector3) -> void:
	var near: Array = doc.data.things.filter(func(t): return not WorldScene.gone_in(t.kind, doc.season()) and Vector2(float(t.x) - hit.x, float(t.z) - hit.z).length() < brush_radius)
	if near.is_empty():
		return
	doc.remove_things(near)
	_scene.update_things([], near)
	_stroke_removed.append_array(near)
	_mark_dirty()
	_redraw()

func _cells_near(hit: Vector3) -> Array:
	var res := WorldDoc.TERRAIN_RES
	var step := WorldDoc.TERRAIN_SIZE / (res - 1)
	var c := Vector2i(roundi((hit.x + WorldDoc.TERRAIN_SIZE / 2.0) / step), roundi((hit.z + WorldDoc.TERRAIN_SIZE / 2.0) / step))
	var n := ceili(brush_radius / step)
	var out := []
	for j in range(maxi(c.y - n, 1), mini(c.y + n + 1, res - 1)):
		for i in range(maxi(c.x - n, 1), mini(c.x + n + 1, res - 1)):
			var p := WorldDoc.cell_to_world(i, j)
			var d := Vector2(p.x - hit.x, p.y - hit.z).length() / brush_radius
			if d < 1.0:
				out.append([j * res + i, 1.0 - d * d * (3.0 - 2.0 * d), p])
	return out

func _land_at(hit: Vector3) -> void:
	var res := WorldDoc.TERRAIN_RES
	var touched := []
	if not _land_constraints_ready:
		_land_constraints = Clearance.land_constraints(doc)
		_land_constraints_ready = true
	var limited := false
	for cell in _cells_near(hit):
		var o: int = cell[0]
		var weight: float = cell[1]
		var h := doc.heights[o]
		match land_mode:
			"raise":
				h += BRUSH_FLOW * weight
			"lower":
				h -= BRUSH_FLOW * weight
			_:
				var avg := (doc.heights[o - 1] + doc.heights[o + 1] + doc.heights[o - res] + doc.heights[o + res]) / 4.0
				h = lerpf(h, avg, 0.4 * weight)
		var allowed := Clearance.limit_land(doc, o, h, _land_constraints)
		limited = limited or allowed != h
		h = allowed
		if h == doc.heights[o]:
			continue
		if not _stroke.has(o):
			_stroke[o] = [doc.heights[o], doc.ground[o]]
		doc.heights[o] = h
		touched.append(o)
	_scene.mark_land(touched)
	if not touched.is_empty():
		_mark_dirty()
		_set_status("Land updated.")
	if limited:
		_set_status("Some land stayed at its limit to keep the Yard visible.")

func _ground_paint_at(hit: Vector3) -> void:
	var touched := []
	for cell in _cells_near(hit):
		var o: int = cell[0]
		if cell[1] < 0.25 or doc.ground[o] == ground_kind:
			continue
		if not _stroke.has(o):
			_stroke[o] = [doc.heights[o], doc.ground[o]]
		doc.ground[o] = ground_kind
		touched.append(o)
	_scene.mark_land(touched, true)
	if not touched.is_empty():
		_mark_dirty()

## Records a finished stroke as one undo step: it has already been drawn.
func _finish_stroke() -> void:
	_land_constraints_ready = false
	_land_constraints.clear()
	if not _stroke.is_empty():
		_invalidate_zones()
		var after := {}
		for o in _stroke:
			after[o] = [doc.heights[o], doc.ground[o]]
		history.land_stroke("Shape land" if tool == Tool.LAND else "Paint ground", after, _stroke)
		_stroke = {}
	if not _stroke_added.is_empty():
		var label := "Place " + _thing_name(_stroke_added[0].kind) if _stroke_added.size() == 1 and place_mode == "one" else "Paint %d things" % _stroke_added.size()
		history.things_edit(label, _stroke_added, [], true)
		var skipped := " Some spots were skipped by the placement rules." if _stroke_skipped > 3 else ""
		_set_status(("Placed " + _thing_name(_stroke_added[0].kind) if label.begins_with("Place ") else label) + "." + skipped + _placed_note)
		_placed_note = ""
		_stroke_added = []
	elif tool == Tool.SCATTER and place_mode == "paint" and _stroke_skipped > 0:
		_set_status("Nothing fits here: too close to the Yard or to other things.")
	if not _stroke_removed.is_empty():
		var removed := "Clear %d %s" % [_stroke_removed.size(), "thing" if _stroke_removed.size() == 1 else "things"]
		history.things_edit(removed, [], _stroke_removed, true)
		_set_status(removed + ".")
		_stroke_removed = []
	_stroke_skipped = 0

func _thing_name(kind: String) -> String:
	return str(WorldScene.load_kit().get("models", {}).get(kind, {}).get("label", kind))

func _undo() -> void:
	if _exporting:
		return
	_finish_edits()
	if not history.can_undo():
		return
	var label := history.undo_label()
	history.undo()
	_set_status("Undid: %s." % label)

func _redo() -> void:
	if _exporting:
		return
	_finish_edits()
	if not history.can_redo():
		return
	var label := history.redo_label()
	history.redo()
	_set_status("Redid: %s." % label)

func _on_changed(part: int, detail: Variant) -> void:
	_dismiss_preview()
	_redraw()
	if _scene == null:
		return
	match part:
		History.Part.THINGS:
			_scene.update_things(detail.added, detail.removed)
		History.Part.LAND:
			_scene.mark_land(detail)
			_invalidate_zones()
		History.Part.VALUE:
			_scene.refresh_water()
			_scene.refresh_season()
			_apply_mood()
			if detail.has("title"):
				_title_box.text = str(doc.data.title)
			if not _own_commit and tool in [Tool.WATER, Tool.MOOD]:
				_build_options()
	if tool == Tool.ARRANGE:
		_refresh_selection()

func _on_steps_changed() -> void:
	_mark_dirty()
	_update_undo_buttons()
	if _track_problems and not _problems_pending:
		_problems_pending = true
		_refresh_problems.call_deferred()

func _refresh_problems() -> bool:
	_problems_pending = false
	var checked := Clearance.check_world(doc)
	_problems = checked.get("issues", [])
	_problem_index = -1
	_problem_button.text = "Show problem"
	_problem_row.visible = not checked.get("valid", false)
	_problem_button.visible = not _problems.is_empty()
	_problem_label.text = checked.get("summary", checked.get("problem", ""))
	_track_problems = _track_problems or not _problems.is_empty()
	for child in _problem_markers.get_children():
		child.free()
	var ring := TorusMesh.new()
	ring.inner_radius = 2.7
	ring.outer_radius = 3.0
	ring.rings = 32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ProTheme.color("danger")
	mat.no_depth_test = true
	for issue in _problems:
		var marker := MeshInstance3D.new()
		marker.mesh = ring
		marker.material_override = mat
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var p: Vector2 = issue.position
		var h := doc.height_at(p.x, p.y)
		marker.position = Vector3(p.x, h + 0.2 if is_finite(h) else 0.2, p.y)
		_problem_markers.add_child(marker)
	var land: PackedInt32Array = checked.get("land", PackedInt32Array())
	_problem_zones.visible = not land.is_empty()
	if not land.is_empty():
		var pixels := PackedByteArray()
		pixels.resize(WorldDoc.TERRAIN_RES * WorldDoc.TERRAIN_RES * 2)
		for index in land:
			pixels[index * 2] = 255
			pixels[index * 2 + 1] = 255
		_problem_zones.texture_albedo = ImageTexture.create_from_image(Image.create_from_data(WorldDoc.TERRAIN_RES, WorldDoc.TERRAIN_RES, false, Image.FORMAT_LA8, pixels))
	_redraw()
	return checked.get("valid", false)

func _show_problem() -> void:
	if _exporting or _problems.is_empty():
		return
	_dismiss_preview()
	_problem_index = (_problem_index + 1) % _problems.size()
	var issue: Dictionary = _problems[_problem_index]
	var p: Vector2 = issue.position
	var h := doc.height_at(p.x, p.y)
	_target = Vector3(p.x, h if is_finite(h) else 0.0, p.y)
	_zoom = maxf(_zoom, DEFAULT_ZOOM)
	_place_camera()
	_problem_button.text = "Next problem" if _problems.size() > 1 else "Show problem"
	_set_status("Problem %d of %d. %s" % [_problem_index + 1, _problems.size(), "Lower or smooth the marked land to keep the Yard clear." if issue.kind == "land" else issue.message])

func _update_undo_buttons() -> void:
	var locked := _exporting
	_undo_button.disabled = locked or not history.can_undo()
	_redo_button.disabled = locked or not history.can_redo()
	_undo_button.tooltip_text = "Undo: %s (Ctrl+Z)" % history.undo_label() if history.can_undo() else "Nothing to undo"
	_redo_button.tooltip_text = "Redo: %s (Ctrl+Y)" % history.redo_label() if history.can_redo() else "Nothing to redo"

func _mark_dirty() -> void:
	_dirty_at = Time.get_ticks_msec() / 1000.0
	_refresh_save_label()
	_result_button.visible = false

func _refresh_save_label() -> void:
	_save_label.add_theme_color_override("font_color", ProTheme.color("danger" if _save_failure != "" else "muted"))
	_save_label.tooltip_text = _save_failure + " Trying again shortly." if _save_failure != "" else path
	_save_label.text = "Couldn't save" if _save_failure != "" else ("Unsaved title" if _title_box.text != str(doc.data.title) else ("Unsaved changes" if _dirty_at >= 0.0 else "Saved"))

func _commit_title() -> void:
	if not _finishing_edits:
		_finish_edits()
	var text := _title_box.text.strip_edges()
	if text == "":
		_title_box.text = str(doc.data.title)
	elif text != str(doc.data.title):
		history.set_value("Rename", doc.data, "title", text)
	else:
		_title_box.text = text
	_refresh_save_label()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
			KEY_S:
				if _save_now():
					_set_status("Saved.")
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if _exporting:
		return
	if TOOL_KEYS.has(event.keycode):
		_select_tool(TOOL_KEYS[event.keycode])
	elif event.keycode == KEY_Q or event.keycode == KEY_E:
		var step := _turn_step(_selected().get("kind", "") if tool == Tool.ARRANGE else place_kind)
		var by := step if event.keycode == KEY_E else -step
		if tool == Tool.ARRANGE:
			_turn_selected(by)
		elif tool == Tool.SCATTER and place_mode == "one":
			_turn_next(signf(by))
		else:
			return
	elif tool == Tool.ARRANGE and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE):
		_remove_selected()
	elif tool == Tool.ARRANGE and event.keycode == KEY_ESCAPE:
		_select_thing(-1)
	elif event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_BRACKETRIGHT:
		brush_radius = clampf(brush_radius * (0.8 if event.keycode == KEY_BRACKETLEFT else 1.25), 1.0, 40.0)
		_set_brush_ring(brush_radius)
		if tool in [Tool.LAND, Tool.GROUND, Tool.ERASE] or (tool == Tool.SCATTER and place_mode == "paint"):
			_build_options()
	elif event.keycode == KEY_HOME:
		_reset_view()
	else:
		return
	get_viewport().set_input_as_handled()

func _update_zones() -> void:
	if _zones == null:
		return
	var wanted := -1.0
	if tool == Tool.LAND:
		wanted = 0.0
	elif tool == Tool.SCATTER and (_chosen_is_tall() or _raised_land):
		wanted = ceilf(_tallest_chosen() * (Placing.SMALLEST if place_mode == "one" else Placing.LARGEST) * 10.0) / 10.0
	_zone_wanted = wanted
	_show_zone()

func _show_zone() -> void:
	if _zone_wanted < 0.0:
		_zones.visible = false
		_redraw()
		return
	if _zone_masks.has(_zone_wanted):
		_zones.texture_albedo = _zone_masks[_zone_wanted]
		_zones.visible = true
		_redraw()
	elif _zone_task < 0:
		var height := _zone_wanted
		var heights := doc.heights.duplicate()
		var result := []
		_zone_result = result
		_zone_task_key = height
		_zone_task_version = _zone_version
		_zone_task = WorkerThreadPool.add_task(func(): result.append(Clearance.mask(height, ZONE_RES, heights)))

func _invalidate_zones() -> void:
	_update_raised_land()
	_zone_version += 1
	_zone_masks.clear()
	_zones.visible = false
	_show_zone()

func _update_raised_land() -> void:
	_raised_land = false
	for h in doc.heights:
		if h > 0.0:
			_raised_land = true
			break

func _check_zone_task() -> void:
	if _zone_task < 0 or not WorkerThreadPool.is_task_completed(_zone_task):
		return
	WorkerThreadPool.wait_for_task_completion(_zone_task)
	_zone_task = -1
	if _zone_task_version != _zone_version:
		_show_zone()
		return
	if _zone_result.is_empty():
		return
	var img := Image.create_from_data(ZONE_RES, ZONE_RES, false, Image.FORMAT_LA8, _zone_result[0])
	_zone_masks[_zone_task_key] = ImageTexture.create_from_image(img)
	_show_zone()

func _exit_tree() -> void:
	_slider_finishes.clear()
	_slider_states.clear()
	if history:
		history.dispose()
		history = null
	if _zone_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_zone_task)
		_zone_task = -1

func _process(_delta: float) -> void:
	if _scene == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_check_zone_task()
	if _placed_ring.visible and now >= _placed_ring_until:
		_placed_ring.visible = false
		_redraw()
	if _redraw_frames > 0 and not _exporting:
		_redraw_frames -= 1
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _painting and tool == Tool.LAND and now - _last_dab > HOLD_SECONDS:
		_last_dab = now
		_land_at(_last_brush)
	if _scene.land_pending() and not _exporting:
		_scene.flush_land(LAND_BUDGET_MS)
		_redraw()
	if not _painting or now - _last_settle > SETTLE_SECONDS:
		if not _scene.land_pending():
			_last_settle = now
			_scene.settle_things()
	if _dirty_at > 0.0 and now - _dirty_at > AUTOSAVE_SECONDS and not _in_gesture():
		_save_now(false)

func _in_gesture() -> bool:
	return _painting or not _drag.is_empty() or _slider_states.any(func(s): return s.dragging or s.pending)

func _project_folder() -> String:
	return path if path != "" else WorldLibrary.folder_for(str(doc.data.title))

func _save_now(commit_title := true) -> bool:
	var retrying := _save_failure != ""
	_finish_edits()
	if commit_title:
		_commit_title()
	var folder := _project_folder()
	var err := doc.save(folder)
	if err == OK:
		path = folder
		_dirty_at = -1.0
		_save_failure = ""
		_refresh_save_label()
		if doc.notice != "":
			_set_status(doc.notice)
		elif retrying:
			_set_status("Saved.")
		return true
	_dirty_at = Time.get_ticks_msec() / 1000.0 + SAVE_RETRY_SECONDS - AUTOSAVE_SECONDS
	_save_failure = doc.save_error
	_refresh_save_label()
	_set_status(_save_label.tooltip_text)
	return false

func _capture_thumbnail() -> void:
	if path == "" or DisplayServer.get_name() == "headless":
		return
	var tex := _viewport.get_texture()
	var img: Image = tex.get_image() if tex else null
	if img == null or img.is_empty():
		return
	var cut := mini(img.get_width(), int(img.get_height() * 16.0 / 9.0))
	var tall := int(cut * 9.0 / 16.0)
	var cropped := img.get_region(Rect2i((img.get_width() - cut) / 2, (img.get_height() - tall) / 2, cut, tall))
	cropped.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	cropped.convert(Image.FORMAT_RGB8)
	cropped.save_webp(path.path_join(WorldDoc.THUMB), true, 0.8)

func request_leave(then: Callable) -> void:
	if _leave_dialog:
		_leave_dialog.grab_focus()
		return
	if not _exporting:
		_on_stage_left()
		if not _save_now():
			_show_save_error(then)
			return
		_capture_thumbnail()
		then.call()
		return
	var ask := ConfirmationDialog.new()
	_leave_dialog = ask
	ask.title = "Rendering is still running"
	ask.dialog_text = "Stop it and leave? Anything rendered so far won't be saved."
	ask.ok_button_text = "Stop and leave"
	ask.cancel_button_text = "Keep rendering"
	add_child(ask)
	ask.confirmed.connect(func():
		_close_leave_dialog()
		_after_job = func(): request_leave(then)
		if _job:
			_cancel.disabled = true
			_cancel.text = "Stopping…"
			_job.cancel())
	ask.canceled.connect(_close_leave_dialog)
	ask.popup_centered()

func _close_leave_dialog() -> void:
	if _leave_dialog:
		_leave_dialog.hide()
		_leave_dialog.queue_free()
		_leave_dialog = null

func _show_save_error(then: Callable) -> void:
	var ask := ConfirmationDialog.new()
	_leave_dialog = ask
	ask.title = "Your changes couldn't be saved"
	ask.dialog_autowrap = true
	ask.dialog_text = "Your changes are still open. Retry saving, or keep editing.\n" + _save_label.tooltip_text
	ask.ok_button_text = "Retry"
	ask.cancel_button_text = "Keep editing"
	ask.add_button("Leave without saving", false, "discard")
	add_child(ask)
	ask.confirmed.connect(func():
		_close_leave_dialog()
		request_leave(then))
	ask.canceled.connect(_close_leave_dialog)
	ask.custom_action.connect(func(action):
		if action == "discard":
			_close_leave_dialog()
			then.call())
	ask.popup_centered(Vector2i(540, 180))
	ask.get_cancel_button().grab_focus()

func _set_status(text: String) -> void:
	if _status:
		_status.text = text
		_status.tooltip_text = text

func _begin_job(message: String) -> void:
	_finish_edits()
	_commit_title()
	_dismiss_preview()
	_exporting = true
	_painting = false
	_panning = false
	_on_stage_left()
	_job_started = Time.get_ticks_msec()
	_freeze_view(true)
	_progress.value = 0.0
	_progress.max_value = 1.0
	_progress.visible = true
	_cancel.text = "Stop"
	_cancel.disabled = false
	_cancel.visible = true
	_result_button.visible = false
	_save_rendered_button.visible = false
	_lock.visible = true
	_set_controls_enabled(false)
	_build_options()
	_set_status(message)
	_job = BakeJob.new()
	add_child(_job)
	_job.progress.connect(_on_job_progress)

## Rendering needs the GPU, so the live view stops and a still picture stands in.
func _freeze_view(on: bool) -> void:
	if on and DisplayServer.get_name() != "headless":
		var img := _viewport.get_texture().get_image()
		if img and not img.is_empty():
			_frozen.texture = ImageTexture.create_from_image(img)
			_frozen.visible = true
			_stage.visible = false
	elif not on:
		_frozen.visible = false
		_frozen.texture = null
		_stage.visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _on_job_progress(done: int, total: int) -> void:
	_progress.max_value = total
	_progress.value = done
	var elapsed := (Time.get_ticks_msec() - _job_started) / 1000.0
	var left := elapsed / maxf(done, 1) * (total - done)
	_set_status("Rendering: %d%%, %s." % [roundi(100.0 * done / total), time_left(left) if elapsed > 3.0 else "working out how long this will take"])

static func time_left(seconds: float) -> String:
	if seconds < 60.0:
		return "less than a minute left"
	var minutes := ceili(seconds / 60.0)
	return "about %d %s left" % [minutes, "minute" if minutes == 1 else "minutes"]

func _end_job() -> void:
	if not _exporting:
		return
	_exporting = false
	_progress.visible = false
	_cancel.visible = false
	_lock.visible = false
	_freeze_view(false)
	if _job:
		_job.queue_free()
	_job = null
	_set_controls_enabled(true)
	_save_rendered_button.visible = _recovery_path != ""
	_build_options()
	_update_undo_buttons()
	_redraw()
	if _after_job.is_valid():
		var next := _after_job
		_after_job = Callable()
		next.call()

func _set_controls_enabled(on: bool) -> void:
	_problem_button.disabled = not on
	for k in _tools:
		_tools[k].disabled = not on
	for c: Control in [_preview_button, _export_button, _quality_pick, _day_button, _dusk_button, _undo_button, _redo_button]:
		c.set("disabled", not on)
	_title_box.editable = on

func _show_preview() -> void:
	if _exporting:
		return
	_begin_job("Rendering a preview…")
	var img: Image = await _job.preview(doc, theme_name)
	var error := _job.error
	var leaving := _after_job.is_valid()
	var stopped := img == null
	_end_job()
	if leaving:
		return
	if stopped:
		_set_status("Preview stopped." if error == "" else "Couldn't render a preview: " + error)
		return
	_set_status("Preview ready.")
	_dismiss_preview()
	var cover := PanelContainer.new()
	cover.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("bg"), Color.TRANSPARENT, 0, 10, 10))
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_holder.add_child(cover)
	var stack := VBoxContainer.new()
	cover.add_child(stack)
	var head := HBoxContainer.new()
	stack.add_child(head)
	var note := ProTheme.note("%s preview, without the Yard's live halls and crews." % ("Day" if theme_name == "light" else "Dusk"))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(note)
	var close := Button.new()
	close.text = "Back to editing"
	close.pressed.connect(_dismiss_preview)
	head.add_child(close)
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(img)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(picture)
	_overlay = cover

func _export_dialog() -> void:
	_finish_edits()
	_commit_title()
	if not _refresh_problems():
		return
	var d := FileDialog.new()
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.filters = PackedStringArray(["*.agworld ; Agent Guild world"])
	d.current_file = str(doc.data.title).validate_filename() + WorldPackage.EXT
	d.use_native_dialog = true
	d.file_selected.connect(func(to):
		d.queue_free()
		_export_to(to))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 500))

func _export_to(to: String) -> void:
	if not _save_now():
		return
	if not _refresh_problems():
		return
	_begin_job("Getting ready to render by day and at dusk…")
	_job.finished.connect(func(e):
		var leaving := _after_job.is_valid()
		if _job.recovery_path != "" or e == "":
			_recovery_path = _job.recovery_path
		var notice := _job.notice
		_end_job()
		if leaving:
			return
		if e == BakeJob.CANCELLED:
			_set_status("Export stopped. Your project is saved; no new world file was exported.")
		elif e == "":
			_result_path = to
			_result_button.visible = true
			_set_status(notice if notice != "" else "Exported %s." % to.get_file())
		else:
			if _recovery_path != "":
				_result_path = _recovery_path
				_result_button.visible = true
			_set_status("That didn't export: " + e))
	_job.run(doc, to, _quality)

func _save_rendered_dialog() -> void:
	var d := FileDialog.new()
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.filters = PackedStringArray(["*.agworld ; Agent Guild world"])
	d.current_file = "Rendered world.agworld"
	d.use_native_dialog = true
	d.file_selected.connect(func(to):
		d.queue_free()
		_save_rendered_to(to))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 500))

func _save_rendered_to(to: String) -> void:
	var report := {}
	if BakeJob.save_rendered(_recovery_path, to, report) != OK:
		_set_status(report.get("error", "Couldn't save the rendered world.") + " Recovery copy: " + _recovery_path)
		return
	_recovery_path = ""
	_save_rendered_button.visible = false
	_result_path = to
	_result_button.visible = true
	_set_status(report.get("notice", "Exported %s." % to.get_file()))

extends Control
## The app: a start screen, then the editor. Also runs from the command line:
##   --new=meadow --base=guild --seed=7 --title=Name --save=folder
##   --export=folder --to=file.agworld
##   --check=file.agworld
##   --shot=picture.png [--open=folder] [--dark]

const EditorView := preload("res://src/ui/editor_view.gd")
const CONTENT_WIDTH := 960.0
const DEFAULT_TITLE := "My world"
const HERO_WIDTH := 1440.0
const HERO_HEIGHT := 330.0
const HERO_MAX_HEIGHT := 480.0
const HERO_CREW_STARTS := 0.51
const STAMP_TURN := -8.0
const STAMP_GAP := 22.0

var _args := {}
var _gui := false
var _view: Control
var _loader: WorldLoader
var _quit_after_load := false
var _notice := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	ProTheme.dark = _args.has("dark")
	theme = ProTheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _args.has("check"):
		_cli_check(_args.check)
	elif _args.has("new"):
		_cli_new()
	elif _args.has("export"):
		await _cli_export()
	else:
		_gui = true
		get_tree().auto_accept_quit = false
		get_window().min_size = Vector2i(1120, 640)
		OS.low_processor_usage_mode = not _args.has("shot")
		if _args.has("open"):
			_load_world(func(): return WorldDoc.open(_args.open), _args.open, "Opening your world")
		else:
			_start_screen()
	if _args.has("shot"):
		while _loader:
			await get_tree().process_frame
		for i in 30:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args.shot)
		get_tree().quit()

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST or not _gui:
		return
	if _loader:
		_quit_after_load = true
	elif _view:
		_view.request_leave(func(): get_tree().quit())
	else:
		get_tree().quit()

func _cli_check(path: String) -> void:
	var result := WorldPackage.check(path)
	if WorldPackage.accepted(result):
		print("OK: this world file passes the package checks.")
	else:
		printerr(WorldPackage.explanation(result))
	get_tree().quit(0 if WorldPackage.accepted(result) else 1)

func _cli_new() -> void:
	var doc := Templates.create(_args.new, _args.get("base", "guild"), _args.get("title", "My world"), int(_args.get("seed", "1")))
	var err := doc.save(_args.get("save", "world"))
	print("things ", doc.data.things.size(), " saved ", error_string(err))
	if not _args.has("shot"):
		get_tree().quit(0 if err == OK else 1)

func _cli_export() -> void:
	var report := {}
	var doc := WorldDoc.open(_args.export, report)
	if doc == null:
		printerr(report.get("error", "That project can't be opened."))
		get_tree().quit(1)
		return
	var job := BakeJob.new()
	add_child(job)
	var t0 := Time.get_ticks_msec()
	job.progress.connect(func(d, t): print("BAKE %d/%d %ds" % [d, t, (Time.get_ticks_msec() - t0) / 1000]))
	job.finished.connect(func(e):
		if e == "":
			print("EXPORTED ", _args.to, " in ", (Time.get_ticks_msec() - t0) / 1000, "s")
			if job.notice != "":
				print(job.notice)
		else:
			printerr(e)
		get_tree().quit(0 if e == "" else 1))
	job.run(doc, _args.to, _args.get("quality", "final"))

func _clear() -> void:
	for c in get_children():
		c.queue_free()

func _start_screen() -> void:
	_clear()
	_view = null
	if DirAccess.dir_exists_absolute(OS.get_user_data_dir().path_join("bakes")):
		BakeJob.clean_leftovers()
	var page := PanelContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("bg"), Color.TRANSPARENT, 0, 0, 0))
	add_child(page)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	scroll.add_child(stack)
	stack.add_child(_hero())
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stack.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	if BakeJob.has_recovered_export():
		col.add_child(ProTheme.note("Rendered files from an unfinished export have been kept. A world.agworld file can be copied to your chosen folder."))
		var recovered := Button.new()
		recovered.text = "Show recovered exports"
		recovered.pressed.connect(func(): OS.shell_open(OS.get_user_data_dir().path_join("bakes")))
		col.add_child(recovered)
	if _notice != "":
		var warn := ProTheme.note(_notice)
		warn.add_theme_color_override("font_color", ProTheme.color("danger"))
		col.add_child(warn)
		_notice = ""
	if WorldScene.kits_dir() == "":
		var missing := ProTheme.note("The Meadow kit is missing. Extract the complete app ZIP, including its kits folder, before opening a world.")
		missing.add_theme_color_override("font_color", ProTheme.color("warn"))
		col.add_child(missing)
	_add_new_world(col)
	_add_your_worlds(col)
	var open := Button.new()
	open.text = "Open a world from another folder…"
	open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open.pressed.connect(_open_dialog)
	col.add_child(open)

func _hero() -> Control:
	var hero := Control.new()
	hero.clip_contents = true
	hero.custom_minimum_size = Vector2(0, HERO_HEIGHT)
	var picture := TextureRect.new()
	picture.texture = load("res://data/brand/hero-%s.webp" % ("dark" if ProTheme.dark else "light"))
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(picture)
	hero.resized.connect(func():
		var tall := clampf(hero.size.x * HERO_HEIGHT / HERO_WIDTH, HERO_HEIGHT, HERO_MAX_HEIGHT)
		if hero.custom_minimum_size.y != tall:
			hero.custom_minimum_size.y = tall
		var wide := tall * HERO_WIDTH / HERO_HEIGHT
		picture.position = Vector2(hero.size.x - wide, 0)
		picture.size = Vector2(wide, tall))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(center)
	var words := VBoxContainer.new()
	words.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
	words.add_theme_constant_override("separation", 2)
	center.add_child(words)
	var eyebrow := ProTheme.heading("AGENT GUILD", 13)
	eyebrow.add_theme_color_override("font_color", ProTheme.color("accent"))
	words.add_child(eyebrow)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	title.add_child(ProTheme.heading("Builders", 54))
	var stamp_spot := Control.new()
	stamp_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(stamp_spot)
	var stamp := ProTheme.stamp("BETA")
	stamp.name = "BetaStamp"
	stamp.rotation_degrees = STAMP_TURN
	stamp_spot.add_child(stamp)
	stamp.resized.connect(func(): stamp.pivot_offset = stamp.size / 2.0)
	stamp_spot.resized.connect(func(): stamp.position = Vector2(STAMP_GAP, (stamp_spot.size.y - stamp.size.y) / 2.0))
	words.add_child(title)
	var line := ProTheme.note("Build an environment for your Agent Guild Yard.")
	line.add_theme_font_size_override("font_size", 17)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	words.add_child(line)
	hero.resized.connect(func():
		var wide := clampf(hero.size.x * HERO_HEIGHT / HERO_WIDTH, HERO_HEIGHT, HERO_MAX_HEIGHT) * HERO_WIDTH / HERO_HEIGHT
		var crew_starts := hero.size.x - wide * HERO_CREW_STARTS
		line.custom_minimum_size.x = clampf(crew_starts - (hero.size.x - CONTENT_WIDTH) / 2.0 - 16.0, 240.0, 460.0))
	return hero

func _add_new_world(col: VBoxContainer) -> void:
	col.add_child(ProTheme.heading("Start a new world", 17))
	var form := HBoxContainer.new()
	col.add_child(form)
	var name_box := LineEdit.new()
	name_box.text = WorldLibrary.unique_title(DEFAULT_TITLE)
	name_box.placeholder_text = "Name your world"
	name_box.max_length = 128
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(name_box)
	var base_label := ProTheme.note("Preview with halls and crews from")
	base_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	form.add_child(base_label)
	var base := OptionButton.new()
	for b in WorldDoc.BASES:
		base.add_item(Yard.data().worlds[b].title)
	base.tooltip_text = "You'll see this world's halls and crews while you build. In Agent Guild, your world shows the halls and crews of the Yard it replaces."
	form.add_child(base)
	var grid := GridContainer.new()
	grid.columns = 3
	col.add_child(grid)
	for key in Templates.LIST:
		var info: Dictionary = Templates.LIST[key]
		var card := Button.new()
		card.text = "%s\n%s" % [info.label, info.note]
		card.custom_minimum_size = Vector2(0, 248)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.expand_icon = true
		card.icon = ProTheme.thumb("template_" + key)
		ProTheme.picture_button(card)
		var template: String = key
		card.pressed.connect(func():
			var title := name_box.text.strip_edges()
			var chosen: String = WorldDoc.BASES[base.selected]
			var seed_value := randi() % 100000
			_load_world(func(): return Templates.create(template, chosen, title if title != "" else DEFAULT_TITLE, seed_value), "", "Building your world"))
		grid.add_child(card)

func _add_your_worlds(col: VBoxContainer) -> void:
	col.add_child(ProTheme.heading("Your worlds", 17))
	var worlds := WorldLibrary.list()
	if worlds.is_empty():
		var empty := HBoxContainer.new()
		empty.add_theme_constant_override("separation", 12)
		empty.add_child(ProTheme.brand("bot-concierge", 112))
		var waiting := ProTheme.note("Worlds you build will appear here, and they save themselves as you work.")
		waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		waiting.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		empty.add_child(waiting)
		col.add_child(empty)
		return
	var grid := GridContainer.new()
	grid.columns = 4
	col.add_child(grid)
	for w in worlds:
		grid.add_child(_world_card(w))

func _world_card(w: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(232, 0)
	box.add_theme_constant_override("separation", 4)
	var open := Button.new()
	open.text = w.title
	open.tooltip_text = "Open " + w.title
	open.clip_text = true
	open.custom_minimum_size = Vector2(0, 170)
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	open.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	open.expand_icon = true
	ProTheme.picture_button(open)
	if w.thumb != "":
		var img := Image.load_from_file(w.thumb)
		if img:
			open.icon = ImageTexture.create_from_image(img)
	open.pressed.connect(func(): _load_world(func(): return WorldDoc.open(w.path), w.path, "Opening your world"))
	box.add_child(open)
	var row := HBoxContainer.new()
	box.add_child(row)
	var when := ProTheme.note(edited_text(int(w.modified), int(Time.get_unix_time_from_system()), Time.get_time_zone_from_system().bias))
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(when)
	var more := MenuButton.new()
	more.text = "⋯"
	more.tooltip_text = "More for " + w.title
	more.flat = false
	var menu := more.get_popup()
	menu.add_item("Rename…", 0)
	menu.add_item("Duplicate", 1)
	menu.add_item("Move to Recycle Bin…", 2)
	menu.id_pressed.connect(func(id): _on_world_menu(id, w))
	row.add_child(more)
	return box

func _on_world_menu(id: int, w: Dictionary) -> void:
	match id:
		0:
			_rename_dialog(w)
		1:
			if WorldLibrary.duplicate_world(w.path) == "":
				_notice = "That world couldn't be duplicated."
			_start_screen()
		2:
			_delete_dialog(w)

static func edited_text(modified: int, now: int, bias_minutes: int) -> String:
	var offset := bias_minutes * 60
	var then := Time.get_datetime_dict_from_unix_time(modified + offset)
	var clock := "%02d:%02d" % [then.hour, then.minute]
	var day_of := func(t: int) -> int: return floori((t + offset) / 86400.0)
	var days: int = day_of.call(now) - day_of.call(modified)
	if days == 0:
		return "Today, " + clock
	if days == 1:
		return "Yesterday, " + clock
	return "%d-%02d-%02d" % [then.year, then.month, then.day]

func _rename_dialog(w: Dictionary) -> void:
	var ask := ConfirmationDialog.new()
	ask.title = "Rename world"
	ask.ok_button_text = "Rename"
	var box := LineEdit.new()
	box.text = w.title
	box.max_length = 128
	ask.add_child(box)
	ask.register_text_enter(box)
	add_child(ask)
	ask.confirmed.connect(func():
		var title := box.text.strip_edges()
		if title != "" and WorldLibrary.rename(w.path, title) != OK:
			_notice = "That world couldn't be renamed."
		_start_screen())
	ask.canceled.connect(ask.queue_free)
	ask.popup_centered(Vector2i(420, 120))
	box.grab_focus()
	box.select_all()

func _delete_dialog(w: Dictionary) -> void:
	var ask := ConfirmationDialog.new()
	ask.title = "Move to Recycle Bin"
	ask.dialog_text = "Move “%s” to the Recycle Bin?" % w.title
	ask.ok_button_text = "Move to Recycle Bin"
	add_child(ask)
	ask.confirmed.connect(func():
		if WorldLibrary.delete_world(w.path) != OK:
			_notice = "That world couldn't be moved to the Recycle Bin."
		_start_screen())
	ask.canceled.connect(ask.queue_free)
	ask.popup_centered()

func _open_dialog() -> void:
	var d := FileDialog.new()
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	d.use_native_dialog = true
	d.dir_selected.connect(func(path): _load_world(func(): return WorldDoc.open(path), path, "Opening your world"))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 500))

## Shows progress at once, prepares the world off the main thread, then opens it.
func _load_world(make: Callable, path: String, heading: String) -> void:
	_clear()
	var page := PanelContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_stylebox_override("panel", ProTheme.box(ProTheme.color("bg"), Color.TRANSPARENT, 0, 0, 0))
	add_child(page)
	var center := CenterContainer.new()
	page.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(420, 0)
	center.add_child(col)
	var courier := ProTheme.brand("bot-courier", 170)
	courier.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(courier)
	col.add_child(ProTheme.heading(heading, 20))
	var step := ProTheme.note("Starting…")
	col.add_child(step)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 1.0
	col.add_child(bar)
	_loader = WorldLoader.new()
	add_child(_loader)
	_loader.step.connect(func(label, fraction):
		step.text = label
		bar.value = fraction)
	_loader.done.connect(func(doc): _on_world_ready(doc, path, page))
	await get_tree().process_frame
	_loader.start(make, path)

func _on_world_ready(doc: WorldDoc, path: String, loading_page: Control) -> void:
	var error := _loader.error
	_loader.queue_free()
	_loader = null
	if _quit_after_load:
		get_tree().quit()
		return
	if doc == null:
		_notice = error
		_start_screen()
		return
	_edit(doc, path)
	move_child(loading_page, get_child_count() - 1)
	for i in 3:
		await get_tree().process_frame
	loading_page.queue_free()

func _edit(doc: WorldDoc, path: String) -> void:
	_view = EditorView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	_view.open(doc, path)
	_view.closed.connect(_start_screen)

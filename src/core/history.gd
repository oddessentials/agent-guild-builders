class_name History
extends RefCounted
## Undo and redo for a document. Every edit is a named do/undo pair; a land
## stroke keeps only the cells it changed. `changed` says what to redraw.

enum Part { THINGS, LAND, VALUE }
const UNSET := &"__unset__"

signal changed(part: int, detail: Variant)
signal steps_changed

var doc: WorldDoc
var _undo := UndoRedo.new()
## Rises on every recorded edit, undo and redo, unlike UndoRedo's version,
## which returns to earlier numbers after an undo.
var revision := 0

func _init(document: WorldDoc) -> void:
	doc = document
	_undo.max_steps = 200
	_undo.version_changed.connect(func():
		revision += 1
		steps_changed.emit())

func place(kind: String, x: float, z: float, turn: float, scale: float) -> void:
	things_edit("Place " + kind, [doc.make_thing(kind, x, z, turn, scale)], [])

func remove(id: int) -> void:
	var found: Array = doc.data.things.filter(func(t): return int(t.id) == id)
	if not found.is_empty():
		things_edit("Remove", [], found)

## One undo step for many things. With `already_applied`, the document and the
## drawing already show the edit, as they do at the end of a stroke.
func things_edit(label: String, added: Array, removed: Array, already_applied := false) -> bool:
	if _repeats(added) or _repeats(removed):
		push_error("Not recorded: \"%s\" lists an item twice." % label)
		return false
	_undo.create_action(label)
	_undo.add_do_method(func(): _swap_things(added, removed))
	_undo.add_undo_method(func(): _swap_things(removed, added))
	_undo.commit_action(not already_applied)
	return true

## Each side of an edit holds an item at most once: undo and redo swap whole
## items by id, so a repeat would leave two items with one id.
static func _repeats(things: Array) -> bool:
	var seen := {}
	for t in things:
		if seen.has(int(t.id)):
			return true
		seen[int(t.id)] = true
	return false

func _swap_things(added: Array, removed: Array) -> void:
	doc.remove_things(removed)
	doc.data.things.append_array(added)
	changed.emit(Part.THINGS, {"added": added, "removed": removed})

## `cells` maps a land cell to its new height and ground kind, as [height, kind].
## Passing `before` says the stroke is already applied and only records it.
func land_stroke(label: String, cells: Dictionary, before := {}) -> void:
	var already_applied := not before.is_empty()
	var was := before
	if not already_applied:
		for i in cells:
			was[i] = [doc.heights[i], doc.ground[i]]
	_undo.create_action(label)
	_undo.add_do_method(func(): _apply(cells))
	_undo.add_undo_method(func(): _apply(was))
	_undo.commit_action(not already_applied)

func _apply(cells: Dictionary) -> void:
	for i in cells:
		doc.heights[i] = cells[i][0]
		doc.ground[i] = cells[i][1]
	changed.emit(Part.LAND, cells.keys())

## `was` is the value before a live preview changed it.
func set_value(label: String, holder: Dictionary, key: String, value: Variant, was: Variant = null) -> void:
	set_values(label, holder, {key: value}, {} if was == null else {key: was})

func set_values(label: String, holder: Dictionary, values: Dictionary, was := {}) -> void:
	var before := was.duplicate()
	for key in values:
		if not before.has(key):
			before[key] = holder.get(key)
	_undo.create_action(label)
	_undo.add_do_method(func(): _set_all(holder, values))
	_undo.add_undo_method(func(): _set_all(holder, before))
	_undo.commit_action()

func set_many(label: String, changes: Array) -> void:
	var befores := []
	for change in changes:
		var before := {}
		for key in change[1]:
			before[key] = change[0].get(key, UNSET)
		befores.append([change[0], before])
	_undo.create_action(label)
	_undo.add_do_method(func(): _set_each(changes))
	_undo.add_undo_method(func(): _set_each(befores))
	_undo.commit_action()

func _set_each(changes: Array) -> void:
	var keys := []
	for change in changes:
		for key in change[1]:
			if is_same(change[1][key], UNSET):
				change[0].erase(key)
			else:
				change[0][key] = change[1][key]
		keys.append_array(change[1].keys())
	changed.emit(Part.VALUE, keys)

func _set_all(holder: Dictionary, values: Dictionary) -> void:
	for key in values:
		holder[key] = values[key]
	changed.emit(Part.VALUE, values.keys())

func undo() -> bool:
	return _undo.undo()

func redo() -> bool:
	return _undo.redo()

func can_undo() -> bool:
	return _undo.has_undo()

func can_redo() -> bool:
	return _undo.has_redo()

func undo_label() -> String:
	return _undo.get_current_action_name() if _undo.has_undo() else ""

func redo_label() -> String:
	return _undo.get_action_name(_undo.get_current_action() + 1) if _undo.has_redo() else ""

func dispose() -> void:
	if _undo:
		_undo.free()
		_undo = null

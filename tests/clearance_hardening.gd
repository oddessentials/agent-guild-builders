extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL ", label)

func _run() -> void:
	check(_geometry(), "geometry checks complete")
	check(_land(), "land checks complete")
	check(await _preflight(), "preflight checks complete")
	check(_templates(), "template checks complete")
	check(await _guidance(), "clearance guidance checks complete")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _geometry() -> bool:
	check(Clearance.tall_clear(0, 48, 8), "short geometry remains allowed")
	check(not Clearance.tall_clear(0, 48, 12), "geometry crossing live area refused")
	check(not Clearance.tall_clear(0, 48, 136), "very tall geometry cannot skip live area")
	check(Clearance.tall_clear(-120, -120, 4096), "height behind Yard is not arbitrarily capped")
	for p in [Vector2(0, 48), Vector2(40, 45), Vector2(-20, 50), Vector2(60, 90)]:
		var limit := Clearance.max_elevation(p.x, p.y)
		if is_finite(limit) and limit > 0.0:
			check(Clearance.tall_clear(p.x, p.y, limit) and not Clearance.tall_clear(p.x, p.y, limit + 0.1), "clearance has one continuous boundary")
			check(not Clearance.tall_clear(p.x, p.y, limit + 10000), "height cannot become safe again")
	return true

func _land() -> bool:
	WorldScene.load_kit()
	var doc := WorldDoc.create("guild", "Clearance", 7)
	var thing := doc.add_thing("tree_elm", 0, 48, 0, 1)
	var constraints := Clearance.land_constraints(doc)
	check(constraints.size() > 0, "existing object constrains land beneath it")
	for index in constraints:
		doc.heights[index] = Clearance.limit_land(doc, index, 136.0, constraints)
	check(Clearance.check_world(doc).get("valid", false), "raising beneath existing tree preserves clearance")
	var top := doc.height_at(thing.x, thing.z) + 8.0
	check(Clearance.tall_clear(thing.x, thing.z, top), "tree height includes interpolated ground")
	var o := int((48 + WorldDoc.TERRAIN_SIZE / 2.0) / (WorldDoc.TERRAIN_SIZE / (WorldDoc.TERRAIN_RES - 1))) * WorldDoc.TERRAIN_RES + WorldDoc.TERRAIN_RES / 2
	doc.data.things.clear()
	for index in [o, o + 1, o + WorldDoc.TERRAIN_RES, o + WorldDoc.TERRAIN_RES + 1]:
		doc.heights[index] = 136.0
	check(Placing.why_not(doc, "fern", 0, 48, 1) != "", "small plant on tall mound refused")
	check(not Clearance.check_world(doc).get("valid", false), "unsafe terrain fails preflight")
	check(Clearance.limit_land(doc, o, 140, {}) == 136.0, "old unsafe terrain cannot be raised further")
	check(Clearance.limit_land(doc, o, 135, {}) == 135.0, "old unsafe terrain can be lowered gradually")
	var centre := (WorldDoc.TERRAIN_RES * WorldDoc.TERRAIN_RES) / 2
	check(Clearance.limit_land(doc, centre, 1, {}) == 0.0 and Clearance.limit_land(doc, centre, -1, {}) == 0.0, "protected ground stays flat")
	doc.heights[centre] = 2.0
	check(Clearance.limit_land(doc, centre, 1.0, {}) == 1.0, "old raised protected ground can be corrected")
	var flat_mask := Clearance.mask(0.7, 17)
	var empty := true
	for i in range(1, flat_mask.size(), 2):
		empty = empty and flat_mask[i] == 0
	check(empty, "low planting does not shade flat terrain")
	return true

func _preflight() -> bool:
	var doc := WorldDoc.create("guild", "Unsafe", 7)
	doc.heights[(WorldDoc.TERRAIN_RES * WorldDoc.TERRAIN_RES) / 2] = 136.0
	var before := doc.heights.duplicate()
	var job := BakeJob.new()
	root.add_child(job)
	job.run(doc, "user://must-not-export.agworld")
	var error: String = await job.finished
	check(error.contains("Land near") and job._baker == null, "unsafe world rejected before GPU work")
	check(doc.heights == before, "preflight never changes the user's world")
	job.queue_free()
	await process_frame
	return true

func _templates() -> bool:
	for key in Templates.LIST:
		for seed_value in [7, 42]:
			var doc := Templates.create(key, "guild", "Template", seed_value)
			var result := Clearance.check_world(doc)
			check(result.get("valid", false), "%s seed %d passes export clearance: %s" % [key, seed_value, result.get("problem", "")])
	return true

func _guidance() -> bool:
	var doc := WorldDoc.create("guild", "Old world", 7)
	var centre := (WorldDoc.TERRAIN_RES * WorldDoc.TERRAIN_RES) / 2
	doc.heights[centre] = 5.0
	doc.heights[centre + 1] = 5.0
	doc.heights[centre + WorldDoc.TERRAIN_RES * 3] = 5.0
	var item := doc.add_thing("tree_elm", 0, 0, 0, 1)
	var result := Clearance.check_world(doc)
	check(result.issues.size() == 3 and result.land.size() == 3, "all invalid items and separate terrain areas reported together")
	check(result.summary.contains("2 areas") and result.summary.contains("1 item"), "adjacent terrain vertices form one actionable area")
	var view := preload("res://src/ui/editor_view.gd").new()
	root.add_child(view)
	view.open(doc, "")
	view.set_process(false)
	var initial: Vector3 = view._target
	check(view._problem_row.visible and view._problem_markers.get_child_count() == 3, "older world opens with marked problems")
	check(view._target == initial and view._problem_zones.visible, "guidance highlights terrain without moving the camera")
	view._show_problem()
	check(view._problem_index == 0 and view._target.y == 5.0, "show problem centers the affected terrain")
	view._show_problem()
	check(view._problem_index == 1 and view._target.z != initial.z, "next problem moves to the next distinct area")
	view._show_problem()
	check(view._problem_index == 2 and view._status.text.contains("Spreading tree"), "item problem identifies the affected model")
	var focus: Vector3 = view._target
	doc.heights.fill(0.0)
	doc.remove_thing(item.id)
	view._on_steps_changed()
	await process_frame
	check(view._problems.is_empty() and not view._problem_row.visible and not view._problem_zones.visible, "completed edits clear resolved problems without another export")
	check(view._target == focus, "rechecking problems never jumps the camera")
	view.free()
	return true

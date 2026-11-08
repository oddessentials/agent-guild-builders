class_name ThumbStage
extends RefCounted
## The plain studio every item's thumbnail is shot in.

const ITEM := Vector2i(232, 160)

static func make(parent: Node) -> SubViewport:
	var v := SubViewport.new()
	v.size = ITEM * 2
	v.own_world_3d = true
	v.msaa_3d = Viewport.MSAA_4X
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(v)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.94, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	v.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.look_at_from_position(Vector3(1, 2, 1.5), Vector3.ZERO, Vector3.UP)
	v.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	v.add_child(cam)
	cam.current = true
	v.set_meta("camera", cam)
	return v

## Meshes side by side, as one group.
static func arrange(stage: SubViewport, meshes: Array) -> Node3D:
	var holder := Node3D.new()
	stage.add_child(holder)
	var x := 0.0
	for mesh: Mesh in meshes:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		var aabb := mesh.get_aabb()
		part.position.x = x - aabb.position.x
		holder.add_child(part)
		x += aabb.size.x * 0.9
	return holder

static func bounds(holder: Node3D) -> AABB:
	var box := AABB()
	for part in holder.get_children():
		if part is MeshInstance3D and part.mesh:
			var aabb: AABB = part.mesh.get_aabb()
			var placed := AABB(aabb.position * part.scale + part.position, aabb.size * part.scale)
			box = placed if box.size == Vector3.ZERO else box.merge(placed)
	return box

static func frame(stage: SubViewport, box: AABB, picture := ITEM) -> void:
	var cam: Camera3D = stage.get_meta("camera")
	var centre := box.get_center()
	var dir := Vector3(0.45, 0.45, 1.0).normalized()
	cam.size = maxf(box.size.y * 1.12, maxf(box.size.x, box.size.z) * 1.05 * float(picture.y) / picture.x)
	var reach := box.size.length() + 10.0
	cam.far = reach * 3.0
	cam.look_at_from_position(centre + dir * reach, centre, Vector3.UP)

static func shoot(stage: SubViewport, meshes: Array) -> Image:
	var holder := arrange(stage, meshes)
	frame(stage, bounds(holder))
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := stage.get_texture().get_image()
	holder.free()
	if img == null or img.is_empty():
		return null
	img.resize(ITEM.x, ITEM.y, Image.INTERPOLATE_LANCZOS)
	return img

static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"

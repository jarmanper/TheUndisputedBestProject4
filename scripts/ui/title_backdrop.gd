extends Node3D
## Animated 3D backdrop for the title screen: a grandfather clock in a dark,
## foggy room, lit by a failing bulb, with a slow drifting camera.

const GRANDFATHER := preload("res://assets/models/props/grandfather_clock.glb")
const WALL_CLOCK := preload("res://assets/models/props/wall_clock.glb")

var _cam: Camera3D
var _bulb: OmniLight3D
var _rim: SpotLight3D
var _t := 0.0
var _flicker_cd := 2.0
var _bulb_base := 2.8


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_props()
	_build_lights()
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.current = true
	add_child(_cam)
	_update_camera()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.006, 0.007)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.09, 0.09)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.025, 0.025)
	env.fog_density = 0.06
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_room() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.09, 0.075, 0.07)
	floor_mat.roughness = 0.85
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.11, 0.085, 0.08)
	wall_mat.roughness = 0.95
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30, 10, 0.2)
	wall.mesh = box
	wall.material_override = wall_mat
	wall.position = Vector3(0, 5, -1.2)
	add_child(wall)


## Instance a model and scale it so its height matches `height`, feet on y=0.
func _place(scene: PackedScene, height: float, pos: Vector3, yaw: float) -> Node3D:
	var holder := Node3D.new()
	var inst := scene.instantiate() as Node3D
	holder.add_child(inst)
	add_child(holder)
	var aabb := _aabb(inst, Transform3D.IDENTITY)
	if aabb.size.y > 0.001:
		var s := height / aabb.size.y
		inst.scale = Vector3.ONE * s
		inst.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


func _aabb(node: Node, xf: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is VisualInstance3D:
		var a: AABB = local * (node as VisualInstance3D).get_aabb()
		result = a
		first = false
	for c in node.get_children():
		var ca := _aabb(c, local)
		if ca.size != Vector3.ZERO:
			result = ca if first else result.merge(ca)
			first = false
	return result


func _build_props() -> void:
	_place(GRANDFATHER, 2.3, Vector3(1.1, 0, -0.6), deg_to_rad(-12))
	var wc := _place(WALL_CLOCK, 0.45, Vector3(2.55, 2.15, -1.05), 0.0)
	wc.rotation.z = deg_to_rad(4)


func _build_lights() -> void:
	_bulb = OmniLight3D.new()
	_bulb.light_color = Color(1.0, 0.72, 0.48)
	_bulb.light_energy = _bulb_base
	_bulb.omni_range = 6.0
	_bulb.shadow_enabled = true
	_bulb.position = Vector3(0.3, 2.7, 1.1)
	add_child(_bulb)

	_rim = SpotLight3D.new()
	_rim.light_color = Color(0.85, 0.12, 0.08)
	_rim.light_energy = 3.0
	_rim.spot_range = 8.0
	_rim.spot_angle = 30.0
	_rim.position = Vector3(3.2, 1.2, 1.4)
	add_child(_rim)
	_rim.look_at(Vector3(1.1, 1.2, -0.6))


func _process(delta: float) -> void:
	_t += delta
	_update_camera()
	_flicker_cd -= delta
	if _flicker_cd <= 0.0:
		_flicker_cd = randf_range(1.5, 6.0)
		_flicker()
	_rim.light_energy = 1.4 + sin(_t * 0.7) * 0.4


func _update_camera() -> void:
	var drift := Vector3(sin(_t * 0.11) * 0.35, sin(_t * 0.17) * 0.12, cos(_t * 0.09) * 0.25)
	_cam.position = Vector3(-0.2, 1.45, 3.6) + drift
	_cam.look_at(Vector3(0.05 + sin(_t * 0.07) * 0.1, 1.35, -0.6))
	_cam.rotate_object_local(Vector3.FORWARD, sin(_t * 0.13) * 0.012)


func _flicker() -> void:
	var tw := create_tween()
	for i in randi_range(2, 5):
		tw.tween_property(_bulb, "light_energy", randf_range(0.0, 0.6), randf_range(0.02, 0.06))
		tw.tween_property(_bulb, "light_energy", _bulb_base * randf_range(0.8, 1.15), randf_range(0.03, 0.1))
	tw.tween_property(_bulb, "light_energy", _bulb_base, 0.2)

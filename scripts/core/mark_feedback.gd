extends Node3D
## Presentation observes Target; neither targeting nor timers depend on visuals.
const OUTLINE = preload("res://assets/materials/fx_marked_outline.tres")
const HOLOGRAM = preload("res://assets/materials/fx_tracker_hologram.tres")
var icon: MeshInstance3D
var meshes: Array[MeshInstance3D] = []
var previous_overlays: Array[Material] = []
var outline: ShaderMaterial
@onready var target: Target = get_parent() as Target

func _ready() -> void:
	outline = OUTLINE.duplicate()
	# Generated materials contain null overrides. Set defaults on local copies.
	outline.set_shader_parameter("color", Color(1.0, 0.25, 0.08, 1.0))
	outline.set_shader_parameter("width", 0.018)
	outline.set_shader_parameter("pulse_speed", 2.0)
	outline.set_shader_parameter("intensity", 1.6)
	for child in target.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		meshes.append(child)
		previous_overlays.append(child.material_overlay)
	icon = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	var material: ShaderMaterial = HOLOGRAM.duplicate()
	material.set_shader_parameter("color", Color(1.0, 0.3, 0.1, 1.0))
	material.set_shader_parameter("intensity", 2.5)
	material.set_shader_parameter("spin", 0.6)
	quad.material = material
	icon.mesh = quad
	icon.position.y = 2.55
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(icon)
	target.mark_changed.connect(_show_mark)
	_show_mark(target.marked)

func _show_mark(active: bool) -> void:
	icon.visible = active
	for i in meshes.size():
		meshes[i].material_overlay = outline if active else previous_overlays[i]

func _process(_delta: float) -> void:
	if not target.marked:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	icon.look_at(camera.global_position, Vector3.UP, true)
	# Depth-testing the existing shaders hides covered fragments. Also suppress
	# the floating icon when the target's center is occluded by level geometry.
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target.center(), 1)
	icon.visible = target.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

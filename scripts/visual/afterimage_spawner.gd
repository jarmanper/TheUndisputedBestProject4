extends Node
## Suspend visual helper: leaves fading cyan "ghost" copies of a (skinned)
## mesh at its current pose. Visual only — call spawn() from your own code.
##   var ghosts = preload("res://scripts/visual/afterimage_spawner.gd").new()
##   add_child(ghosts); ghosts.spawn($Model/.../MeshInstance3D)

const GHOST_MAT := preload("res://assets/materials/fx_afterimage.tres")

@export var lifetime := 0.8


func spawn(source: MeshInstance3D) -> MeshInstance3D:
	var ghost := MeshInstance3D.new()
	# freeze the current animated pose into a static mesh
	ghost.mesh = source.bake_mesh_from_current_skeleton_pose() if source.skeleton != NodePath() else source.mesh
	ghost.material_override = GHOST_MAT.duplicate()
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ghost)
	ghost.global_transform = source.global_transform
	var mat: ShaderMaterial = ghost.material_override
	var tw := ghost.create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, lifetime)
	tw.tween_callback(ghost.queue_free)
	return ghost

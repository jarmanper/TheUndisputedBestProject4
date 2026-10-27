extends Node3D
## Rotates this node around its local Z axis (clock rings, fans, gears).

@export var speed_deg := 10.0
@export var axis := Vector3(0, 0, 1)


func _process(delta: float) -> void:
	rotate_object_local(axis.normalized(), deg_to_rad(speed_deg) * delta)

class_name Player
extends CharacterBody3D
signal health_changed(hp: int)
signal died

const MAX_HP := 100
const UPPER_BODY_HEIGHT := 1.4
const MOVE_SPEED := 4.0 # Prototype traversal choice; not a Team 3 mechanic number.
const MOUSE_SENSITIVITY := 0.0025
const GEOMETRY_MASK := 1
const TARGETING_MASK := 5
var hp := MAX_HP

@onready var body_collider: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

func _ready() -> void:
	spring_arm.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.1, 1.1)

func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(input.x, 0.0, input.y)
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func upper_body_point() -> Vector3:
	# Upright capsule bottom, independent of the root's placement above the floor.
	var capsule := body_collider.shape as CapsuleShape3D
	return body_collider.global_position + Vector3.UP * (UPPER_BODY_HEIGHT - capsule.height * 0.5)

func has_line_of_sight(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(upper_body_point(), point, GEOMETRY_MASK, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func crosshair_target(range_m: float) -> Target:
	if hp <= 0 or range_m < 0.0:
		return null
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(screen_center)
	var direction := camera.project_ray_normal(screen_center)
	# Extend past the range sphere: distance is measured from the upper body,
	# not the third-person camera or the first collider surface it intersects.
	var length := origin.distance_to(upper_body_point()) + range_m + 2.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * length, TARGETING_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var target := hit.collider as Target
	if target == null or not target.is_alive():
		return null
	if upper_body_point().distance_squared_to(target.center()) > range_m * range_m:
		return null
	return target if has_line_of_sight(target.center()) else null

func take_hit(amount: int) -> void:
	if hp <= 0 or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	health_changed.emit(hp)
	if hp == 0:
		velocity = Vector3.ZERO
		died.emit()

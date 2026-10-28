class_name TimbukPlayer
extends CharacterBody3D
## Assignment controls only; ranges originate at the upper-body point.
signal health_changed(value, max_value)
signal died
const MAX_HP := 100
const UPPER_BODY_HEIGHT := 1.4
const MOVE_SPEED := 4.0
const DEFAULT_SENSITIVITY := 0.0022
const SETTINGS_PATH := "user://settings.cfg"
var health := 100.0
var max_health := 100.0
var dead := false
var mouse_sensitivity := DEFAULT_SENSITIVITY
var base_fov := 75.0
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/SpringArm3D/Camera3D
@onready var body: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 5
	floor_snap_length = 0.3
	$Head/SpringArm3D.add_excluded_object(get_rid())
	reload_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func reload_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var value := float(cfg.get_value("input", "mouse_sensitivity", DEFAULT_SENSITIVITY))
		mouse_sensitivity = value if value <= 0.05 else value * DEFAULT_SENSITIVITY

func _unhandled_input(event: InputEvent) -> void:
	if dead or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sensitivity, -1.1, 1.1)

func _physics_process(delta: float) -> void:
	if dead:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(input.x, 0, input.y)
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()

func upper_body_point() -> Vector3:
	return body.global_position + Vector3.UP * (UPPER_BODY_HEIGHT - (body.shape as CapsuleShape3D).height * 0.5)

func visible_point(point: Vector3) -> bool:
	return clear_line(upper_body_point(), point)

func clear_line(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func crosshair_target(range_m: float) -> TimbukEnemy:
	if dead or range_m < 0:
		return null
	var screen := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var length := origin.distance_to(upper_body_point()) + range_m + 2.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * length, 5, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var target := hit.collider as TimbukEnemy
	if target == null or target.is_dead():
		return null
	if upper_body_point().distance_squared_to(target.center()) > range_m * range_m:
		return null
	return target if visible_point(target.center()) else null

func damage(amount: float) -> void:
	if dead or amount <= 0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health == 0:
		dead = true
		velocity = Vector3.ZERO
		died.emit()

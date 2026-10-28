class_name TimbukPlayer
extends CharacterBody3D
## First-person player: mouse look, walk/sprint, footsteps, health,
## flashlight, E-to-interact and the pause key. The four team mechanics
## (Combat, Marking, Suspend, Explosion) are separate child nodes.

signal health_changed(value, max_value)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2  # player is on 1 + 2 so Area3D story triggers see it
const LAYER_ENEMY := 4

@export var walk_speed := 3.2
@export var sprint_speed := 5.6
@export var accel := 12.0
@export var mouse_sensitivity := 0.0022
@export var max_health := 100.0
@export var interact_range := 2.6
@export var step_distance := 2.1
@export var sprint_noise_radius := 12.0
@export var walk_noise_radius := 4.0

var health := 100.0
var dead := false
var hovered: Node = null

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _step_accum := 0.0
var _steps: AudioStreamPlayer3D
var _concrete: Array[AudioStream] = []
var _metal: Array[AudioStream] = []
var _hurt_cd := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = LAYER_WORLD | LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	health = max_health
	_ensure_input_actions()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = "SFX"
	_steps.volume_db = -6.0
	add_child(_steps)
	for i in 4:
		_concrete.append(load("res://assets/audio/sfx/footstep_concrete_%d.wav" % i))
		_metal.append(load("res://assets/audio/sfx/footstep_metal_%d.wav" % i))


func _unhandled_input(event: InputEvent) -> void:
	if dead or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact") and hovered and hovered.has_method("interact"):
		hovered.interact(self)
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not dead:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toggle_pause"):
			hud.toggle_pause()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	if dead:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var sprinting := Input.is_action_pressed("sprint") and input.y < 0.0
	var speed := sprint_speed if sprinting else walk_speed
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta * speed)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta * speed)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	# fell out of the level: put back on the last floor
	if global_position.y < -40.0:
		damage(max_health)

	var flat := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat > 0.5:
		_step_accum += flat * delta
		if _step_accum >= step_distance * (1.25 if sprinting else 1.0) * 0.5:
			_step_accum = 0.0
			_footstep(sprinting)
	_update_hover()


func _footstep(sprinting: bool) -> void:
	var pool := _metal if global_position.y < -3.0 else _concrete
	_steps.stream = pool.pick_random()
	_steps.pitch_scale = randf_range(0.9, 1.1)
	_steps.volume_db = -2.0 if sprinting else -8.0
	_steps.play()
	make_noise(sprint_noise_radius if sprinting else walk_noise_radius)


func _update_hover() -> void:
	var hit := aim(interact_range, LAYER_WORLD)
	var c: Node = hit.get("collider")
	hovered = c if c and c.has_method("interact") else null


## Ray from the camera centre. Returns intersect_ray's dictionary
## (position, normal, collider, ...) or {} on a miss.
func aim(distance: float, mask: int = LAYER_WORLD | LAYER_ENEMY) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * distance
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func aim_point(distance: float) -> Vector3:
	var hit := aim(distance)
	if hit.is_empty():
		return camera.global_position - camera.global_transform.basis.z * distance
	return hit.position


## Alerts enemies within `radius` (the Twin hears everything).
func make_noise(radius: float) -> void:
	get_tree().call_group("enemy", "hear_noise", global_position, radius)


func damage(amount: float) -> void:
	if dead:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("flash_damage"):
		hud.flash_damage()
	if health <= 0.0:
		_die()


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


func _die() -> void:
	dead = true
	velocity = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.3, 0.8).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(head, "rotation:z", 0.8, 0.8)
	var tree := get_tree()
	tree.create_timer(1.2).timeout.connect(_lose.bind(tree))


static func _lose(tree: SceneTree) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if TimbukFx.game_state(tree):
		TimbukFx.state_call(tree, "lose")
	else:
		tree.reload_current_scene()


## Adds any missing input actions so the scene works even if project.godot
## lost its [input] section.
static func _ensure_input_actions() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "interact": KEY_E, "suspend": KEY_Q, "explode": KEY_F,
		"reload": KEY_R, "pause": KEY_ESCAPE, "flashlight": KEY_T,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)
	var buttons := {"fire": MOUSE_BUTTON_LEFT, "mark": MOUSE_BUTTON_RIGHT}
	for action in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mb := InputEventMouseButton.new()
			mb.button_index = buttons[action]
			InputMap.action_add_event(action, mb)

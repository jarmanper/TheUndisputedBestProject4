class_name TimbukPlayer
extends CharacterBody3D
## First-person player: mouse look, walk/sprint/crouch with stamina,
## head bob + footsteps, landing dip, sprint FOV kick, camera shake
## (add_trauma), health, flashlight, E-to-interact and the pause key.
## The four team mechanics (Combat, Marking, Suspend, Explosion) are
## separate child nodes.

signal health_changed(value, max_value)
signal stamina_changed(value, max_value)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2  # player is on 1 + 2 so Area3D story triggers see it
const LAYER_ENEMY := 4
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.0022

@export_group("Movement")
@export var walk_speed := 3.2
@export var sprint_speed := 5.6
@export var crouch_speed := 1.7
@export var accel := 12.0  ## ground acceleration (units/s^2 per unit of speed)
@export var decel := 14.0  ## ground braking when there is no input
@export var air_control := 0.25
@export var mouse_sensitivity := DEFAULT_SENSITIVITY

@export_group("Stamina")
@export var max_stamina := 100.0
@export var stamina_drain := 18.0  ## per second while sprinting
@export var stamina_regen := 14.0  ## per second when not sprinting
@export var stamina_regen_delay := 0.9
@export var stamina_min_to_sprint := 20.0  ## needed to start sprinting again after running dry

@export_group("Crouch")
@export var stand_height := 1.75
@export var crouch_height := 1.15
@export var stand_eye := 1.6
@export var crouch_eye := 1.02

@export_group("Camera feel")
@export var bob_amount := 0.045
@export var bob_sway := 0.025
@export var sprint_fov_kick := 7.0
@export var max_shake_offset := 0.08
@export var max_shake_angle := 0.05  ## radians
@export var trauma_decay := 1.4

@export_group("Gameplay")
@export var max_health := 100.0
@export var interact_range := 2.6
@export var step_distance := 2.1  ## metres per full stride (two footsteps)
@export var sprint_noise_radius := 12.0
@export var walk_noise_radius := 4.0
@export var crouch_noise_radius := 1.2

var health := 100.0
var stamina := 100.0
var dead := false
var hovered: Node = null
var crouching := false
var sprinting := false
var base_fov := 75.0  ## FOV without the sprint kick; settings may change it

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _steps: AudioStreamPlayer3D
var _concrete: Array[AudioStream] = []
var _metal: Array[AudioStream] = []
var _hurt_cd := 0.0
var _exhausted := false
var _regen_wait := 0.0
var _bob_phase := 0.0
var _bob_weight := 0.0
var _land_dip := 0.0
var _land_vel := 0.0
var _air_speed := 0.0
var _was_on_floor := true
var _trauma := 0.0
var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _eye := 1.6


func _ready() -> void:
	add_to_group("player")
	collision_layer = LAYER_WORLD | LAYER_PLAYER
	collision_mask = LAYER_WORLD | LAYER_ENEMY
	health = max_health
	stamina = max_stamina
	_ensure_input_actions()
	reload_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	base_fov = camera.fov
	stand_eye = head.position.y
	_eye = stand_eye
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _shape and _shape.shape is CapsuleShape3D:
		_capsule = _shape.shape.duplicate()  # don't edit the shared sub-resource
		_shape.shape = _capsule
		stand_height = _capsule.height
	_noise.seed = randi()
	_noise.frequency = 2.5
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = "SFX"
	_steps.volume_db = -6.0
	add_child(_steps)
	for i in 4:
		_concrete.append(load("res://assets/audio/sfx/footstep_concrete_%d.wav" % i))
		_metal.append(load("res://assets/audio/sfx/footstep_metal_%d.wav" % i))


## Re-reads user://settings.cfg [input] mouse_sensitivity. The value is either
## raw radians per pixel (<= 0.05) or a multiplier of the default (1.0 = default).
func reload_settings() -> void:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(SETTINGS_PATH) or cfg.load(SETTINGS_PATH) != OK:
		return
	var v := float(cfg.get_value("input", "mouse_sensitivity", 0.0))
	if v > 0.05:
		mouse_sensitivity = DEFAULT_SENSITIVITY * v
	elif v > 0.0:
		mouse_sensitivity = v


func _unhandled_input(event: InputEvent) -> void:
	if dead or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact") and is_instance_valid(hovered) and hovered.has_method("interact"):
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
		_update_camera(delta, 0.0)
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	_update_crouch(delta)
	_update_sprint(delta, input)
	var speed := walk_speed
	if crouching:
		speed = crouch_speed
	elif sprinting:
		speed = sprint_speed

	var on_floor := is_on_floor()
	var target := dir * speed
	var rate := (accel if dir != Vector3.ZERO else decel) * speed * delta
	if not on_floor:
		rate *= air_control
	velocity.x = move_toward(velocity.x, target.x, rate)
	velocity.z = move_toward(velocity.z, target.z, rate)
	if not on_floor:
		velocity.y -= _gravity * delta
		_air_speed = maxf(_air_speed, -velocity.y)
	move_and_slide()

	on_floor = is_on_floor()
	if on_floor and not _was_on_floor:
		_on_landed(_air_speed)
	if on_floor:
		_air_speed = 0.0
	_was_on_floor = on_floor

	# fell out of the level
	if global_position.y < -40.0:
		damage(max_health)

	var flat := Vector2(velocity.x, velocity.z).length()
	_update_bob(delta, flat, on_floor)
	_update_camera(delta, flat)
	_update_hover()


func _update_sprint(delta: float, input: Vector2) -> void:
	var wants := Input.is_action_pressed("sprint") and input.y < -0.1 and not crouching
	if _exhausted and stamina >= stamina_min_to_sprint:
		_exhausted = false
	sprinting = wants and not _exhausted and stamina > 0.0 and is_on_floor()
	var before := stamina
	if sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
		_regen_wait = stamina_regen_delay
		if stamina <= 0.0:
			_exhausted = true
	else:
		_regen_wait = maxf(0.0, _regen_wait - delta)
		if _regen_wait <= 0.0:
			stamina = minf(max_stamina, stamina + stamina_regen * delta)
	if stamina != before:
		stamina_changed.emit(stamina, max_stamina)


func _update_crouch(delta: float) -> void:
	var wants := InputMap.has_action("crouch") and Input.is_action_pressed("crouch")
	if wants and not crouching:
		crouching = true
	elif not wants and crouching and _can_stand():
		crouching = false
	var eye_target := crouch_eye if crouching else stand_eye
	_eye = lerpf(_eye, eye_target, 1.0 - exp(-12.0 * delta))
	if _capsule:
		var h := crouch_height if crouching else stand_height
		if not is_equal_approx(_capsule.height, h):
			_capsule.height = move_toward(_capsule.height, h, delta * 4.0)
			_shape.position.y = _capsule.height * 0.5


func _can_stand() -> bool:
	if _capsule == null:
		return true
	return not test_move(global_transform, Vector3.UP * (stand_height - _capsule.height + 0.05))


func _update_bob(delta: float, flat: float, on_floor: bool) -> void:
	var moving := on_floor and flat > 0.4
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, delta * 4.0)
	if not moving:
		return
	# one footstep per half stride; phase advances PI per footstep
	var stride := step_distance * 0.5
	if sprinting:
		stride *= 1.25
	elif crouching:
		stride *= 0.8
	var prev := _bob_phase
	_bob_phase += flat * delta / stride * PI
	if floori(_bob_phase / PI) != floori(prev / PI):
		_footstep()
	if _bob_phase > TAU * 64.0:
		_bob_phase = fmod(_bob_phase, TAU)


func _on_landed(fall_speed: float) -> void:
	if fall_speed < 2.0:
		return
	_land_vel = -clampf(fall_speed * 0.35, 0.6, 3.5)
	_footstep(clampf(fall_speed / 8.0, 0.0, 1.0) * 4.0)
	if fall_speed > 6.0:
		add_trauma(clampf((fall_speed - 6.0) * 0.06, 0.0, 0.5))


func _update_camera(delta: float, flat: float) -> void:
	# landing dip: damped spring back to 0
	_land_vel += (-_land_dip * 140.0 - _land_vel * 16.0) * delta
	_land_dip = clampf(_land_dip + _land_vel * delta, -0.3, 0.05)
	if not dead:
		head.position.y = _eye

	var bob_scale := 1.4 if sprinting else (0.6 if crouching else 1.0)
	var bob_y := (absf(sin(_bob_phase)) - 0.5) * bob_amount * bob_scale * _bob_weight
	var bob_x := sin(_bob_phase) * bob_sway * bob_scale * _bob_weight

	_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	var shake := _trauma * _trauma
	_noise_t += delta * 60.0
	var sx := max_shake_offset * shake * _noise.get_noise_2d(_noise_t, 0.0)
	var sy := max_shake_offset * shake * _noise.get_noise_2d(0.0, _noise_t)
	camera.position = Vector3(bob_x + sx, bob_y + _land_dip + sy, 0.0)
	camera.rotation = Vector3(
		max_shake_angle * shake * _noise.get_noise_2d(_noise_t, 100.0),
		max_shake_angle * shake * _noise.get_noise_2d(100.0, _noise_t),
		max_shake_angle * shake * _noise.get_noise_2d(_noise_t, _noise_t) + bob_x * -0.4)

	var fov_target := base_fov
	if sprinting and flat > walk_speed * 0.9:
		fov_target += sprint_fov_kick
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-6.0 * delta))


## Camera shake. `amount` 0..1 is added to the current trauma (clamped to 1);
## the shake strength is trauma squared and decays over time.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func get_trauma() -> float:
	return _trauma


func stamina_fraction() -> float:
	return stamina / max_stamina if max_stamina > 0.0 else 1.0


func _footstep(boost := 0.0) -> void:
	var pool := _metal if global_position.y < -3.0 else _concrete
	_steps.stream = pool.pick_random()
	_steps.pitch_scale = randf_range(0.9, 1.1)
	var vol := -8.0
	var radius := walk_noise_radius
	if sprinting:
		vol = -2.0
		radius = sprint_noise_radius
	elif crouching:
		vol = -16.0
		radius = crouch_noise_radius
	_steps.volume_db = vol + boost
	_steps.play()
	make_noise(radius + boost)


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
	if dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	add_trauma(clampf(amount / 60.0, 0.15, 0.6))
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
	sprinting = false
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
## lost its [input] section. A value may be one key or an array of keys.
static func _ensure_input_actions() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "interact": KEY_E, "suspend": KEY_Q, "explode": KEY_F,
		"reload": KEY_R, "pause": KEY_ESCAPE, "flashlight": KEY_T,
		"crouch": [KEY_C, KEY_CTRL],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var list: Array = keys[action] if keys[action] is Array else [keys[action]]
			for k in list:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(action, ev)
	var buttons := {"fire": MOUSE_BUTTON_LEFT, "mark": MOUSE_BUTTON_RIGHT}
	for action in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mb := InputEventMouseButton.new()
			mb.button_index = buttons[action]
			InputMap.action_add_event(action, mb)

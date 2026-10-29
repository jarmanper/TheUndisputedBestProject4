class_name TimbukEnemy
extends CharacterBody3D
## Shared 100 HP target and exact Team 3 navigation/attack state machine.
signal died(enemy)
enum State { IDLE, CHASE, WINDUP, DEAD }
const MAX_HP := 100
const SPEED := 2.5
const TRIGGER_RANGE := 8.0
const ATTACK_RANGE := 2.0
const WINDUP := 0.75
const DAMAGE := 10
const ATTACK_COOLDOWN := 2.0
const MARK_OUTLINE = preload("res://assets/materials/fx_marked_outline.tres")
const TRACKER = preload("res://assets/materials/fx_tracker_hologram.tres")
@export var model_scene: PackedScene
var health := 100.0
var state := State.IDLE
var model: Node3D
var marked := false
var suspended := false
var suspend_fraction := 1.0
var suspend_duration := 2.0
var attack_cooldown_left := 0.0
var windup_left := 0.0
var alerted := false
var navigation_enabled := true
var _defeat_emitted := false
var body: CollisionShape3D
var agent: NavigationAgent3D
var _player: TimbukPlayer
var _outline: ShaderMaterial
var _blue: StandardMaterial3D
var _icon: MeshInstance3D
var _ring: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 3
	floor_snap_length = 0.3
	body = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 2.2
	body.shape = capsule
	body.position.y = 1.1
	add_child(body)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.25
	agent.target_desired_distance = 0.2
	agent.radius = 0.35
	add_child(agent)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Visual"
		# No unbudgeted random speech; retain non-verbal breathing/groans.
		var audio := model.get_node_or_null("CreatureAudio")
		if audio:
			var no_lines: Array[AudioStream] = []
			audio.set("lines", no_lines)
			audio.set("word_chance", 0.0)
		add_child(model)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(mesh)
		_build_feedback()

func center() -> Vector3:
	return body.global_position

func is_dead() -> bool:
	return health <= 0

func is_marked() -> bool:
	return marked

func is_suspended() -> bool:
	return suspended

func set_marked(value: bool) -> void:
	marked = value and not is_dead()
	_update_overlay()

func set_suspended(value: bool) -> void:
	suspended = value and not is_dead()
	if suspended:
		if state == State.WINDUP:
			windup_left = 0
			attack_cooldown_left = ATTACK_COOLDOWN
			state = State.CHASE
		velocity = Vector3.ZERO
		suspend_fraction = 1.0
	if model:
		var animation := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation:
			animation.speed_scale = 0.0 if suspended else 1.0
	_update_overlay()

func apply_damage(amount: int, resolve_defeat := true) -> void:
	if is_dead() or amount <= 0:
		return
	health = maxf(0, health - amount)
	if resolve_defeat:
		finish_defeat()

func damage(amount: float) -> void:
	apply_damage(int(amount))

func finish_defeat() -> void:
	if not is_dead() or _defeat_emitted:
		return
	_defeat_emitted = true
	marked = false
	suspended = false
	windup_left = 0
	state = State.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	body.set_deferred("disabled", true)
	hide()
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED
	died.emit(self)

func player_visible() -> bool:
	return is_instance_valid(_player) and _player.clear_line(center(), _player.upper_body_point())

func can_attack() -> bool:
	return is_instance_valid(_player) and not _player.dead and center().distance_squared_to(_player.upper_body_point()) <= ATTACK_RANGE * ATTACK_RANGE and player_visible()

func _physics_process(delta: float) -> void:
	if is_dead():
		return
	attack_cooldown_left = maxf(0, attack_cooldown_left - delta)
	if attack_cooldown_left < 0.000001:
		attack_cooldown_left = 0
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as TimbukPlayer
	if suspended:
		velocity = Vector3.ZERO
		return
	if not is_instance_valid(_player) or _player.dead:
		velocity = Vector3.ZERO
		return
	if not alerted:
		alerted = center().distance_squared_to(_player.upper_body_point()) <= TRIGGER_RANGE * TRIGGER_RANGE
	if state == State.WINDUP:
		windup_left = maxf(0, windup_left - delta)
		velocity = Vector3.ZERO
		if windup_left < 0.000001:
			if can_attack():
				_player.damage(DAMAGE)
			attack_cooldown_left = ATTACK_COOLDOWN
			state = State.CHASE
		return
	if alerted and attack_cooldown_left <= 0 and can_attack():
		state = State.WINDUP
		windup_left = WINDUP
		velocity = Vector3.ZERO
		_play("react")
		return
	var direction := Vector3.ZERO
	if alerted:
		state = State.CHASE
		if navigation_enabled and NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0:
			agent.target_position = _player.global_position
			if not agent.is_navigation_finished():
				direction = agent.get_next_path_position() - global_position
				direction.y = 0
				direction = direction.normalized()
		if direction.length_squared() > 0.001:
			look_at(global_position + direction, Vector3.UP, true)
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0
	move_and_slide()
	_play("walk" if direction != Vector3.ZERO else "idle")

func _play(animation: String) -> void:
	if model and model.has_method("play_visual"):
		model.play_visual(animation)

func _build_feedback() -> void:
	_outline = MARK_OUTLINE.duplicate()
	_outline.set_shader_parameter("color", Color(1, 0.25, 0.08))
	_outline.set_shader_parameter("width", 0.018)
	_outline.set_shader_parameter("pulse_speed", 2.0)
	_outline.set_shader_parameter("intensity", 1.6)
	_blue = StandardMaterial3D.new()
	_blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blue.albedo_color = Color(0.1, 0.5, 1, 0.3)
	_icon = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	var hologram: ShaderMaterial = TRACKER.duplicate()
	hologram.set_shader_parameter("color", Color(1, 0.3, 0.1))
	hologram.set_shader_parameter("intensity", 2.5)
	hologram.set_shader_parameter("spin", 0.6)
	quad.material = hologram
	_icon.mesh = quad
	var top := 2.2
	for mesh in _meshes:
		var bounds: AABB = (global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		top = maxf(top, bounds.end.y)
	_icon.position.y = top + 0.35
	add_child(_icon)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.5
	_ring.mesh = torus
	_ring.material_override = _blue
	_ring.position.y = 0.04
	add_child(_ring)
	_update_overlay()

func _update_overlay() -> void:
	for mesh in _meshes:
		mesh.material_overlay = _outline if marked else (_blue if suspended else null)
	if _icon:
		_icon.visible = marked
	if _ring:
		_ring.visible = suspended

func _process(_delta: float) -> void:
	if _ring and suspended:
		_ring.scale = Vector3.ONE * maxf(0.01, suspend_fraction)
	if not marked or _icon == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_icon.look_at(camera.global_position, Vector3.UP, true)
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, center(), 1)
	_icon.visible = get_world_3d().direct_space_state.intersect_ray(query).is_empty()

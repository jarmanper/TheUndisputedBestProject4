class_name TimbukEnemy
extends CharacterBody3D
## Patient enemy: idle/wander -> chase (sight or noise) -> attack -> dead.
## Gameplay hooks used by the mechanics: damage(), mark(), unmark(),
## is_marked(), suspend(), is_suspended(), hear_noise(), apply_knockback().
## Hit zones: the body collider is sized at runtime from the model's mesh
## AABB + skeleton (head/neck bones). Shape 0 = body capsule, shape 1 = head
## sphere. damage(amount, hit_position) applies headshot_mult when the hit
## point is above the neck; get_hit_multiplier() exposes the same lookup.

signal died(enemy)

enum State { IDLE, WANDER, CHASE, ATTACK, DEAD }

const HIT_FLASH := preload("res://assets/materials/fx_hit_flash.tres")
const MARK_OUTLINE := preload("res://assets/materials/fx_marked_outline.tres")
const TRACKER := "res://scenes/effects/tracking_indicator.tscn"

@export var model_scene: PackedScene
@export var max_health := 75.0
@export var walk_speed := 1.2
@export var chase_speed := 3.2
@export var sight_range := 14.0
@export var attack_range := 1.8
@export var attack_damage := 15.0
@export var attack_interval := 1.2
@export var marked_damage_mult := 2.0
## <= 0 means "derive from the model" (recommended).
@export var capsule_radius := 0.0
@export var capsule_height := 0.0
@export var headshot_mult := 2.0
## Soft push-apart between enemies so they don't stack/overlap.
@export var separation_radius := 0.9
@export var forget_time := 6.0

var health: float
var state := State.IDLE
var model: Node3D
var _anim: AnimationPlayer
var _player: Node3D
var _state_time := 0.0
var _wander_dir := Vector3.ZERO
var _attack_cd := 0.0
var _mark_time := 0.0
var _suspend_time := 0.0
var _tracker: Node3D
var _alert_time := 0.0
var _last_known := Vector3.ZERO
var _knockback := Vector3.ZERO
var _cur_anim := ""
var _flash_mat: ShaderMaterial
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
## Local-space height (above the feet) where the head zone starts / its centre.
var head_min_y := 1.65
var head_center := Vector3(0, 1.8, 0)
var head_radius := 0.16
var _body_shape: CollisionShape3D
var _head_shape: CollisionShape3D


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1 | 2
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	wall_min_slide_angle = deg_to_rad(5.0)
	max_slides = 6
	safe_margin = 0.02
	if model_scene:
		model = model_scene.instantiate()
		add_child(model)
		_anim = model.find_child("AnimationPlayer", true, false)
	_build_hitboxes()
	_play("idle")


func _rel_xform(n: Node, top: Node) -> Transform3D:
	var t := Transform3D()
	while n and n != top:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Measure the model (rest pose) and fit the body capsule + head sphere to it.
func _build_hitboxes() -> void:
	var box := AABB(Vector3(-0.3, 0, -0.2), Vector3(0.6, 2.0, 0.4))
	var neck_y := -1.0
	var head_y := -1.0
	if model:
		var first := true
		for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var a := _rel_xform(m, self) * m.get_aabb()
			box = a if first else box.merge(a)
			first = false
		for sk: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
			var sx := _rel_xform(sk, self)
			var ni := sk.find_bone("neck")
			var hi := sk.find_bone("head")
			if ni >= 0:
				neck_y = (sx * sk.get_bone_global_rest(ni)).origin.y
			if hi >= 0:
				head_y = (sx * sk.get_bone_global_rest(hi)).origin.y
		# feet on the floor: lift the model so its lowest vertex sits at y=0
		if absf(box.position.y) < 0.25:
			model.position.y -= box.position.y
			box.position.y = 0.0
	var top := box.end.y
	if neck_y < 0.0:
		neck_y = top * 0.83
	if head_y < 0.0:
		head_y = lerpf(neck_y, top, 0.45)
	# torso depth (Z) is the reliable width; X includes the rest-pose arms
	var r := capsule_radius if capsule_radius > 0.0 else clampf(maxf(box.size.z * 0.5, 0.16) + 0.12, 0.25, 0.6)
	var body_top := neck_y + 0.04
	var h := capsule_height if capsule_height > 0.0 else maxf(body_top, r * 2.0)
	_body_shape = CollisionShape3D.new()
	_body_shape.name = "BodyHitbox"
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	_body_shape.shape = cap
	_body_shape.position.y = h * 0.5
	add_child(_body_shape)
	head_min_y = neck_y + 0.02
	head_radius = clampf((top - neck_y) * 0.5 + 0.03, 0.12, 0.3)
	head_center = Vector3(0, (neck_y + top) * 0.5, box.get_center().z + 0.02)
	_head_shape = CollisionShape3D.new()
	_head_shape.name = "HeadHitbox"
	var sph := SphereShape3D.new()
	sph.radius = head_radius
	_head_shape.shape = sph
	_head_shape.position = head_center
	add_child(_head_shape)
	capsule_radius = r
	capsule_height = h


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _mark_time > 0.0:
		_mark_time -= delta
		if _mark_time <= 0.0:
			unmark()
	if _suspend_time > 0.0:
		_suspend_time -= delta
		if _suspend_time <= 0.0:
			_set_anim_paused(false)
		velocity = Vector3.ZERO
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_alert_time = maxf(0.0, _alert_time - delta)
	_state_time += delta
	_think()
	var move := Vector3.ZERO
	match state:
		State.WANDER:
			move = _wander_dir * walk_speed
			if is_on_wall():
				_wander_dir = -_wander_dir
		State.CHASE:
			move = _flat_dir_to(_target_pos()) * _chase_speed()
		State.ATTACK:
			_face(_target_pos())
			if _attack_cd <= 0.0 and _player and _player.has_method("damage"):
				_attack_cd = attack_interval
				_play("react")
				_player.damage(attack_damage)
	if move.length() > 0.01:
		_face(global_position + move)
		move += _separation() * move.length()
	velocity.x = move.x + _knockback.x
	velocity.z = move.z + _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, 12.0 * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif _knockback.y > 0.0:
		velocity.y = _knockback.y
		_knockback.y = 0.0
	move_and_slide()


func _think() -> void:
	var sees := _can_see_player()
	if sees:
		_alert_time = forget_time
		_last_known = _player.global_position
	var dist := global_position.distance_to(_target_pos())
	if _alert_time > 0.0:
		if sees and dist <= attack_range:
			_set_state(State.ATTACK)
		elif state != State.ATTACK or dist > attack_range * 1.3:
			_set_state(State.CHASE)
		if state == State.CHASE and not sees and global_position.distance_to(_last_known) < 1.0:
			_alert_time = 0.0
	else:
		if state in [State.CHASE, State.ATTACK] or (state == State.WANDER and _state_time > 4.0):
			_set_state(State.IDLE)
		elif state == State.IDLE and _state_time > randf_range(2.0, 5.0):
			var a := randf() * TAU
			_wander_dir = Vector3(cos(a), 0, sin(a))
			_set_state(State.WANDER)


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	_state_time = 0.0
	match s:
		State.IDLE: _play("idle")
		State.WANDER, State.CHASE: _play("walk")
		State.ATTACK: _play("twitch")


func _chase_speed() -> float:
	return chase_speed


func _target_pos() -> Vector3:
	return _last_known


func _can_see_player() -> bool:
	if _player == null:
		return false
	var to := _player.global_position - global_position
	if to.length() > sight_range:
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.6, _player.global_position + Vector3.UP * 1.5, 1)
	q.exclude = [get_rid(), (_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Push-apart vector from nearby living enemies (they don't physically
## collide with each other, so this keeps groups from merging into one blob).
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not (e is Node3D) or (e.has_method("is_dead") and e.is_dead()):
			continue
		var d: Vector3 = global_position - (e as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		var other_r: float = e.get("capsule_radius") if e.get("capsule_radius") else 0.3
		var min_d: float = separation_radius + other_r
		if l < min_d and l > 0.001:
			push += d / l * (1.0 - l / min_d)
	return push.limit_length(0.6)


func _flat_dir_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


func _face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		# models face +Z
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 0.2)


func _play(anim: String) -> void:
	if _cur_anim == anim:
		return
	_cur_anim = anim
	if model and model.has_method("play_visual"):
		model.play_visual(anim)


func _meshes() -> Array:
	return model.find_children("*", "MeshInstance3D", true, false) if model else []


func _set_overlay(mat: Material) -> void:
	for m in _meshes():
		m.material_overlay = mat


func _set_anim_paused(p: bool) -> void:
	if _anim:
		_anim.speed_scale = 0.0 if p else 1.0


# ---------------------------------------------------------------- API

## Something made noise at `where`; alert if it's within `radius`.
func hear_noise(where: Vector3, radius: float) -> void:
	if state == State.DEAD:
		return
	if global_position.distance_to(where) <= radius:
		_alert_time = forget_time
		_last_known = where


## Damage API. `hit_position` (world space) is optional; when given and it
## lands in the head zone, headshot_mult is applied. When omitted for a
## pistol shot fired this frame, the hit point is recovered from the
## player's aim ray so headshots work with the existing combat call.
func damage(amount: float, hit_position: Vector3 = Vector3.INF) -> void:
	if state == State.DEAD:
		return
	if hit_position == Vector3.INF:
		hit_position = _infer_shot_position()
	take_hit(amount, hit_position, is_headshot(hit_position))


## Same as damage() but the caller decides whether it was a headshot.
func take_hit(amount: float, hit_position: Vector3 = Vector3.INF, headshot := false) -> void:
	if state == State.DEAD:
		return
	if headshot:
		amount *= headshot_mult
	if is_marked():
		amount *= marked_damage_mult
	health -= amount
	_flash()
	if _player:
		hear_noise(_player.global_position, INF)
	if health <= 0.0:
		_die()


## True if the world-space point is in this enemy's head zone.
func is_headshot(hit_position: Vector3) -> bool:
	if hit_position == Vector3.INF or not hit_position.is_finite():
		return false
	var local := to_local(hit_position)
	return local.y >= head_min_y


## Damage multiplier for a hit, from a world-space hit position (Vector3)
## or a collider shape index from a ray result (int: 1 = head).
func get_hit_multiplier(where: Variant) -> float:
	if where is int:
		return headshot_mult if shape_owner_get_owner(shape_find_owner(where)) == _head_shape else 1.0
	if where is Vector3:
		return headshot_mult if is_headshot(where) else 1.0
	return 1.0


func _infer_shot_position() -> Vector3:
	if _player == null or not _player.has_method("aim"):
		return Vector3.INF
	var c := _player.get_node_or_null("Combat")
	if c == null or c.get("_cd") == null or c.get("fire_interval") == null:
		return Vector3.INF
	if float(c.get("_cd")) < float(c.get("fire_interval")) - 0.0001:
		return Vector3.INF  # not a shot fired this frame (e.g. explosion)
	var hit: Dictionary = _player.aim(float(c.get("max_range")) if c.get("max_range") else 60.0)
	if hit.get("collider") == self:
		return hit.position
	return Vector3.INF


func apply_knockback(v: Vector3) -> void:
	if state != State.DEAD and _suspend_time <= 0.0:
		_knockback += v


func mark(duration: float) -> void:
	if state == State.DEAD:
		return
	_mark_time = duration
	_set_overlay(MARK_OUTLINE)
	if _tracker == null:
		_tracker = TimbukFx.spawn(get_tree(), TRACKER, global_position, false)
		if _tracker:
			_tracker.reparent(self)
			_tracker.position = Vector3(0, 0.05, 0)


func unmark() -> void:
	_mark_time = 0.0
	_set_overlay(null)
	if is_instance_valid(_tracker):
		_tracker.queue_free()
	_tracker = null


func is_marked() -> bool:
	return _mark_time > 0.0


func suspend(duration: float) -> void:
	if state == State.DEAD:
		return
	_suspend_time = maxf(_suspend_time, duration)
	_knockback = Vector3.ZERO
	_set_anim_paused(true)


func is_suspended() -> bool:
	return _suspend_time > 0.0


func is_dead() -> bool:
	return state == State.DEAD


func _flash() -> void:
	if _flash_mat == null:
		_flash_mat = HIT_FLASH.duplicate()
	var keep: Material = MARK_OUTLINE if is_marked() else null
	_set_overlay(_flash_mat)
	var tw := create_tween()
	tw.tween_method(func(v: float): _flash_mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.18)
	tw.tween_callback(func():
		if state != State.DEAD:
			_set_overlay(MARK_OUTLINE if is_marked() else keep))


func _die() -> void:
	unmark()
	state = State.DEAD
	_set_anim_paused(false)
	collision_layer = 0
	collision_mask = 1
	died.emit(self)
	_on_death()
	_play("react")
	var tw := create_tween()
	if model:
		tw.tween_property(model, "rotation:x", -PI / 2, 0.6).set_ease(Tween.EASE_IN)
		tw.tween_property(model, "scale", Vector3.ONE * 0.01, 1.5).set_delay(2.0)
	tw.tween_callback(queue_free)


## Override in subclasses.
func _on_death() -> void:
	pass

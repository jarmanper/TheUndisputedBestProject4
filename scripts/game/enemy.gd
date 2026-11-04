class_name TimbukEnemy
extends CharacterBody3D
## Patient enemy, to the assignment's exact rules.
## Every enemy - the Twin included - has the same HEALTH, SPEED and attack.
## It idles until the player comes within SIGHT (flat metres, inclusive) and
## is visible; from then on it is alerted for good and never loses the scent.
## Within ATTACK_RANGE it starts a WINDUP wind-up, and the blow only lands if
## the player is STILL visible and in range when the wind-up finishes. Landing
## it or missing it both start the same ATTACK_WAIT wait.
## There is no hunting by sound, no headshot bonus and no boss phase.
##
## Shared API used by the mechanics (Rhaiyn's contract):
##   center(), is_alive(), is_dead(), apply_damage()
##   marked / set_marked(), suspended / set_suspended()
##   mark_changed, defeated, died

signal died(enemy)
signal defeated(enemy)
signal mark_changed(enemy)

enum State { IDLE, CHASE, WINDUP, DEAD }

## Assignment constants. These are the rules, so they are not @export vars:
## no scene and no subclass may quietly give one enemy better numbers.
const HEALTH := 100.0
const SPEED := 2.5
const SIGHT := 8.0
const ATTACK_RANGE := 2.0
const WINDUP := 0.75
const ATTACK_DAMAGE := 10.0
const ATTACK_WAIT := 2.0
## Height above the node origin that counts as this enemy's centre for every
## range, blast and line-of-sight test.
const CENTER_HEIGHT := 1.1

## Hit flinch: how far the model leans away from a shot (radians, about 8
## degrees) and how long it takes to spring back. Visual only.
const FLINCH_ANGLE := 0.14
const FLINCH_TIME := 0.15

const HIT_FLASH := preload("res://assets/materials/fx_hit_flash.tres")
const MARK_OUTLINE := preload("res://assets/materials/fx_marked_outline.tres")
const TRACKER := "res://scenes/effects/tracking_indicator.tscn"

@export var model_scene: PackedScene
@export var capsule_radius := 0.0
@export var capsule_height := 0.0
@export var separation_radius := 0.9
## Tests and staged set pieces switch this off to hold an enemy in place.
@export var navigation_enabled := true

var health := HEALTH
var state := State.IDLE
var marked := false
var suspended := false
var alerted := false
var windup_left := 0.0
var attack_cooldown_left := 0.0
var model: Node3D

var _anim: AnimationPlayer
var _player: Node3D
var _tracker: Node3D
var _cur_anim := ""
var _flash_mat: ShaderMaterial
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _body_shape: CollisionShape3D
var _head_shape: CollisionShape3D
var _model_rest := Basis.IDENTITY
var _flinch_tween: Tween

var head_min_y := 1.65
var head_center := Vector3(0, 1.8, 0)
var head_radius := 0.16


func _ready() -> void:
	health = HEALTH
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
	if model:
		_model_rest = model.basis
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
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	# the wait between attacks keeps running even while frozen
	attack_cooldown_left = TimbukFx.tick(attack_cooldown_left, delta)
	if suspended:
		velocity = Vector3.ZERO
		return
	_update_alert()
	if state == State.WINDUP:
		_tick_windup(delta)
		return
	if attack_cooldown_left <= 0.0 and _can_attack():
		_begin_windup()
		return
	_move(delta)


## Once alerted, always alerted: the assignment gives the chase no memory limit.
func _update_alert() -> void:
	if alerted or _player == null:
		return
	if _flat_distance_to_player() <= SIGHT and _can_see_player():
		alerted = true
		_set_state(State.CHASE)


func _begin_windup() -> void:
	_set_state(State.WINDUP)
	windup_left = WINDUP
	_face(_player.global_position)


## The blow lands only if the player is still a valid target at the very end.
## A miss costs the same wait as a hit, so backing out of range is a real out.
func _tick_windup(delta: float) -> void:
	_face(_player.global_position)
	windup_left = TimbukFx.tick(windup_left, delta)
	if windup_left > 0.0:
		return
	attack_cooldown_left = ATTACK_WAIT
	_set_state(State.CHASE)
	if _can_attack() and _player.has_method("damage"):
		_play("react")
		_player.damage(ATTACK_DAMAGE)


func _can_attack() -> bool:
	if _player == null:
		return false
	return _flat_distance_to_player() <= ATTACK_RANGE and _can_see_player()


func _move(delta: float) -> void:
	var move := Vector3.ZERO
	if alerted and navigation_enabled and _player:
		move = _flat_dir_to(_player.global_position) * SPEED
	if move.length() > 0.01:
		_face(global_position + move)
		move += _separation() * move.length()
	velocity.x = move.x
	velocity.z = move.z
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	match s:
		State.IDLE: _play("idle")
		State.CHASE: _play("walk")
		State.WINDUP: _play("twitch")


## Flat (XZ) distance: the assignment's ranges are floor distances, so a
## target's height never pushes it out of reach.
func _flat_distance_to_player() -> float:
	if _player == null:
		return INF
	var d := _player.global_position - global_position
	d.y = 0.0
	return d.length()


## Only world geometry blocks sight; other enemies never do.
func _can_see_player() -> bool:
	if _player == null:
		return false
	var to: Vector3 = _player.global_position + Vector3.UP * 1.4
	var q := PhysicsRayQueryParameters3D.create(center(), to, 1)
	q.exclude = [get_rid(), (_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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

## The point every mechanic measures: range, blast radius and line of sight.
func center() -> Vector3:
	return global_position + Vector3.UP * CENTER_HEIGHT


func is_alive() -> bool:
	return state != State.DEAD


func is_dead() -> bool:
	return state == State.DEAD


## The only damage path. Flat amount: no headshot bonus and no mark multiplier,
## because the mark's whole job is to unlock Suspend and Explosion instead.
func apply_damage(amount: float) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_flash()
	if health <= 0.0:
		_die()


## Kept so existing callers and generated scenes still resolve.
func damage(amount: float, _hit_position: Vector3 = Vector3.INF) -> void:
	apply_damage(amount)


func take_hit(amount: float, _hit_position: Vector3 = Vector3.INF, _headshot := false) -> void:
	apply_damage(amount)


## Hit reaction, visual only: the model leans away from `from` and springs
## back. The body, hitboxes, AI state and wind-up never move, so there is no
## knockback and no timing change. A suspended enemy stays frozen.
func flinch(from: Vector3) -> void:
	if model == null or state == State.DEAD or suspended:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.01:
		return
	# turning UP about UP x away leans the top toward `away`; in our own frame
	var axis := (global_basis.inverse() * Vector3.UP.cross(away.normalized())).normalized()
	if _flinch_tween:
		_flinch_tween.kill()
	var lean := func(a: float): model.basis = Basis(axis, a) * _model_rest
	_flinch_tween = create_tween()
	_flinch_tween.tween_method(lean, 0.0, FLINCH_ANGLE, FLINCH_TIME * 0.3).set_ease(Tween.EASE_OUT)
	_flinch_tween.tween_method(lean, FLINCH_ANGLE, 0.0, FLINCH_TIME * 0.7).set_ease(Tween.EASE_IN_OUT)


## Marking owns the timer; the enemy only carries the flag and the visuals.
func set_marked(on: bool) -> void:
	if on and state == State.DEAD:
		return
	marked = on
	if on:
		_set_overlay(MARK_OUTLINE)
		if _tracker == null:
			_tracker = TimbukFx.spawn(get_tree(), TRACKER, global_position, false)
			if _tracker:
				_tracker.reparent(self)
				_tracker.position = Vector3(0, 0.05, 0)
	else:
		_set_overlay(null)
		if is_instance_valid(_tracker):
			_tracker.queue_free()
		_tracker = null
	mark_changed.emit(self)


## A wall hides the floating icon without touching the mark itself.
func set_mark_icon_visible(v: bool) -> void:
	if is_instance_valid(_tracker):
		_tracker.visible = v


func is_marked() -> bool:
	return marked


## Suspend owns the timer. Freezing cancels a wind-up and starts the normal
## wait, which then keeps counting down while the enemy is held.
func set_suspended(on: bool) -> void:
	if on and state == State.DEAD:
		return
	suspended = on
	_set_anim_paused(on)
	if not on:
		return
	velocity = Vector3.ZERO
	if state == State.WINDUP:
		windup_left = 0.0
		attack_cooldown_left = ATTACK_WAIT
		_set_state(State.CHASE)


func is_suspended() -> bool:
	return suspended


func _flash() -> void:
	if _flash_mat == null:
		_flash_mat = HIT_FLASH.duplicate()
	var keep: Material = MARK_OUTLINE if is_marked() else null
	_set_overlay(_flash_mat)
	var tw := create_tween()
	tw.tween_method(func(v: float): _flash_mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.18)
	tw.tween_callback(func():
		if state != State.DEAD:
			_set_overlay(MARK_OUTLINE if marked else keep))


func _die() -> void:
	set_marked(false)
	suspended = false
	state = State.DEAD
	_set_anim_paused(false)
	# collision goes immediately so a corpse never blocks a shot or a blast
	collision_layer = 0
	collision_mask = 0
	died.emit(self)
	defeated.emit(self)
	_on_death()
	_play("react")
	# the fall starts from the rest pose, not from halfway through a flinch
	if _flinch_tween:
		_flinch_tween.kill()
	if model:
		model.basis = _model_rest
	var tw := create_tween()
	if model:
		tw.tween_property(model, "rotation:x", -PI / 2, 0.6).set_ease(Tween.EASE_IN)
		tw.tween_property(model, "scale", Vector3.ONE * 0.01, 1.5).set_delay(2.0)
	tw.tween_callback(queue_free)


## Override in subclasses.
func _on_death() -> void:
	pass

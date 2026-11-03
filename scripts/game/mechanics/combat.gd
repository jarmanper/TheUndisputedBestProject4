extends Node
## COMBAT (Rickey) - assignment rules.
## Left Mouse hits the single target under the crosshair when it is visible and
## within RANGE (inclusive): exactly DAMAGE, with no multiplier, ammo or reload.
## A hit on a marked target takes SUSPEND_RELIEF off Suspend's remaining
## cooldown, including when the hit is lethal. The mark is never consumed.
## Invalid activation costs nothing: no damage, no cooldown.
## Kept as polish only: muzzle flash, gun kick, impact spark and hit sounds.
## Pulling the trigger with nothing in reach still flashes, cracks and marks the
## wall. That is feedback, not a rule: a miss deals no damage, starts no
## cooldown, touches no mark or suspension, and cannot defeat anything, which is
## exactly what "an invalid activation does nothing" requires. Without it the
## gun felt broken, because the only honest answer to a trigger pull was
## silence unless a target happened to be within 3 m.

const DAMAGE := 20.0
const RANGE := 3.0
const COOLDOWN := 0.6
const SUSPEND_RELIEF := 1.0
## How far a missed shot is drawn before it gives up looking for a wall.
const MISS_TRACE := 60.0
## Cosmetic-only spacing between miss effects. It gates no rule - damage,
## cooldown and targeting never consult it - it just stops a mashed trigger
## stacking sixty muzzle flashes in a second.
const MISS_FX_INTERVAL := 0.12
const MAX_HOLES := 48

@export var muzzle_path: NodePath

var cooldown_left := 0.0

var _miss_fx_cd := 0.0
var _holes: Array[Node3D] = []
var _sfx: AudioStreamPlayer
var _flesh: AudioStream = preload("res://assets/audio/sfx/hit_flesh.wav")

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.max_polyphony = 3
	add_child(_sfx)


func is_ready() -> bool:
	return cooldown_left <= 0.0


func _physics_process(delta: float) -> void:
	cooldown_left = TimbukFx.tick(cooldown_left, delta)
	_miss_fx_cd = maxf(0.0, _miss_fx_cd - delta)
	if player.dead or get_tree().paused:
		return
	# new press only: holding the button does not repeat
	if Input.is_action_just_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# fire() fails either because the gun is still cooling down or because
		# nothing valid is in reach; only the second deserves a miss
		if not fire() and is_ready():
			_fire_at_nothing()


## Fires at the crosshair target. Returns true only when a shot landed.
func fire() -> bool:
	if player.dead or not is_ready():
		return false
	var target := player.crosshair_target(RANGE)
	if target == null:
		return false
	cooldown_left = COOLDOWN
	var was_marked: bool = target.marked
	_shot_fx(target)
	target.apply_damage(DAMAGE)
	if was_marked:
		_relieve_suspend()
	return true


## A marked hit shortens Suspend's remaining cooldown. This is the only
## cross-mechanic effect in Combat; it never changes the mark itself.
func _relieve_suspend() -> void:
	var s: Node = player.get_node_or_null("Suspend")
	if s:
		s.reduce_cooldown(SUSPEND_RELIEF)


## Muzzle flash, recoil kick and report - everything a shot does regardless of
## whether it found anything.
func _muzzle_fx() -> void:
	var muzzle := _muzzle()
	var flash := TimbukFx.spawn(get_tree(), "res://scenes/effects/muzzle_flash.tscn", muzzle.global_position, true, player.camera.global_transform.basis)
	if flash and muzzle != player.camera:
		flash.reparent(muzzle, true)  # flash follows the barrel while it fades
	var gun := _gun()
	if gun and gun.has_method("kick"):
		gun.kick()
	player.add_trauma(0.06)


func _shot_fx(target: Node3D) -> void:
	_muzzle_fx()
	var where: Vector3 = target.center()
	TimbukFx.spawn(get_tree(), "res://scenes/effects/impact_sparks.tscn", where, true)
	_play_at(_flesh, where, randf_range(0.9, 1.1))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_hit_marker"):
		hud.show_hit_marker(false)


## A shot that hits nothing: everything the eye and ear expect, and no rule.
func _fire_at_nothing() -> void:
	if _miss_fx_cd > 0.0:
		return
	_miss_fx_cd = MISS_FX_INTERVAL
	_muzzle_fx()
	var hit := player.aim(MISS_TRACE, TimbukPlayer.LAYER_WORLD)
	if hit.is_empty():
		return
	var basis := TimbukFx.basis_from_normal(hit.normal).rotated(hit.normal.normalized(), randf() * TAU)
	TimbukFx.spawn(get_tree(), "res://scenes/effects/impact_sparks.tscn", hit.position, true, basis)
	_punch_hole(hit, basis)


## Bullet holes are pooled: the oldest goes when the pool is full, so a player
## who stands still and empties the trigger into one wall cannot grow the scene.
func _punch_hole(hit: Dictionary, basis: Basis) -> void:
	var hole := TimbukFx.spawn(get_tree(), "res://scenes/effects/bullet_hole.tscn",
			hit.position + hit.normal * 0.005, false, basis)
	if hole == null:
		return
	var s := randf_range(0.8, 1.2)
	hole.scale = Vector3(s, 1.0, s)
	var target: Node = hit.collider
	if target is Node3D and not (target is StaticBody3D):
		hole.reparent(target, true)  # stick to moving props and doors
	_holes.append(hole)
	get_tree().create_timer(30.0).timeout.connect(hole.queue_free)
	while _holes.size() > MAX_HOLES:
		var old: Node3D = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _play_at(stream: AudioStream, pos: Vector3, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.pitch_scale = pitch
	p.unit_size = 3.0
	p.max_distance = 30.0
	var parent: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _gun() -> Node3D:
	return get_node_or_null(muzzle_path) as Node3D


func _muzzle() -> Node3D:
	var m := _gun()
	if m:
		var tip := m.find_child("MUZZLE", true, false) as Node3D
		return tip if tip else m
	return player.camera


## Accessors so the HUD never has to reach for a script constant.
func cooldown_total() -> float:
	return COOLDOWN


func effective_range() -> float:
	return RANGE


func ready_fraction() -> float:
	return clampf(1.0 - cooldown_left / COOLDOWN, 0.0, 1.0)

extends Node
## COMBAT (Rickey) - assignment rules.
## Left Mouse hits the single target under the crosshair when it is visible and
## within RANGE (inclusive): exactly DAMAGE, with no multiplier, ammo or reload.
## A hit on a marked target takes SUSPEND_RELIEF off Suspend's remaining
## cooldown, including when the hit is lethal. The mark is never consumed.
## Invalid activation costs nothing: no damage, no cooldown.
## Kept as polish only: muzzle flash, gun kick, impact spark and hit sounds.

const DAMAGE := 20.0
const RANGE := 3.0
const COOLDOWN := 0.6
const SUSPEND_RELIEF := 1.0

@export var muzzle_path: NodePath

var cooldown_left := 0.0

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
	if player.dead or get_tree().paused:
		return
	# new press only: holding the button does not repeat
	if Input.is_action_just_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		fire()


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
	if s and s.cooldown_left > 0.0:
		s.cooldown_left = maxf(0.0, s.cooldown_left - SUSPEND_RELIEF)


func _shot_fx(target: Node3D) -> void:
	var muzzle := _muzzle()
	var flash := TimbukFx.spawn(get_tree(), "res://scenes/effects/muzzle_flash.tscn", muzzle.global_position, true, player.camera.global_transform.basis)
	if flash and muzzle != player.camera:
		flash.reparent(muzzle, true)  # flash follows the barrel while it fades
	var gun := _gun()
	if gun and gun.has_method("kick"):
		gun.kick()
	var where: Vector3 = target.center()
	TimbukFx.spawn(get_tree(), "res://scenes/effects/impact_sparks.tscn", where, true)
	_play_at(_flesh, where, randf_range(0.9, 1.1))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_hit_marker"):
		hud.show_hit_marker(false)


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

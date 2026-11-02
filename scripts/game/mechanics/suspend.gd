extends Node
## SUSPEND (Jarman) - assignment rules.
## E freezes the single target under the crosshair when it is visible and
## within RANGE (inclusive). It holds for DURATION, or MARKED_DURATION when
## the target was marked AT THE MOMENT of activation - gaining or losing the
## mark afterwards never changes a running suspension. Exactly one target is
## frozen at a time, so a new activation releases the previous one, and
## re-suspending replaces the remaining time instead of stacking.
## A frozen target keeps solid, damageable collision and cannot move.
## Invalid activation costs nothing: no freeze, no cooldown.
## Kept as polish only: the field effect, afterimages, particles and sounds.

signal activated(target: Node)
signal ready_again

const DURATION := 2.0
const MARKED_DURATION := 4.0
const RANGE := 12.0
const COOLDOWN := 7.0

const Afterimage := preload("res://scripts/visual/afterimage_spawner.gd")
const ACTIVATE_SFX := preload("res://assets/audio/sfx/suspend_activate.wav")
const LOOP_SFX := preload("res://assets/audio/sfx/suspend_loop.wav")

var current_target: Node = null
var duration_left := 0.0
var cooldown_left := 0.0

var _ghosts: Node

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	_ghosts = Afterimage.new()
	_ghosts.lifetime = 1.2
	add_child(_ghosts)


func is_ready() -> bool:
	return cooldown_left <= 0.0


func _physics_process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = TimbukFx.tick(cooldown_left, delta)
		if cooldown_left <= 0.0:
			ready_again.emit()
	_tick_duration(delta)
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("suspend"):
		activate()


func _tick_duration(delta: float) -> void:
	if current_target == null:
		return
	if not is_instance_valid(current_target) or current_target.is_dead():
		end_suspension()
		return
	duration_left = TimbukFx.tick(duration_left, delta)
	if duration_left <= 0.0:
		end_suspension()


## Freezes the crosshair target. Returns true only when one was frozen.
func activate() -> bool:
	if player.dead or not is_ready():
		return false
	var target := player.crosshair_target(RANGE)
	if target == null:
		return false
	# the mark only matters at this instant
	var marked_now: bool = target.marked
	_release_current()
	current_target = target
	duration_left = MARKED_DURATION if marked_now else DURATION
	cooldown_left = COOLDOWN
	target.set_suspended(true)
	_freeze_fx(target, duration_left)
	activated.emit(target)
	return true


## Combat's reward for hitting a marked target. The relief cannot be banked:
## with Suspend already off cooldown it does nothing.
func reduce_cooldown(seconds: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - seconds)


## Releases the frozen target, if any. Suspend's cooldown is untouched.
func end_suspension() -> void:
	_release_current()
	current_target = null
	duration_left = 0.0


func _release_current() -> void:
	if current_target != null and is_instance_valid(current_target):
		current_target.set_suspended(false)


func _freeze_fx(target: Node3D, life: float) -> void:
	var tree := get_tree()
	var center: Vector3 = target.center()
	var field := TimbukFx.spawn(tree, "res://scenes/effects/suspend_field.tscn", center, false)
	if field:
		field.scale = Vector3.ONE * 0.1
		var tw := field.create_tween()
		tw.tween_property(field, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(maxf(0.0, life - 0.7))
		tw.tween_property(field, "scale", Vector3.ONE * 0.05, 0.35).set_ease(Tween.EASE_IN)
		tw.tween_callback(field.queue_free)
	_sound(ACTIVATE_SFX, center, 0.0, 0.0)
	_sound(LOOP_SFX, center, -6.0, life)
	player.add_trauma(0.18)
	var parts := TimbukFx.spawn(tree, "res://scenes/effects/suspended_particles.tscn", center, false)
	if parts:
		tree.create_timer(life).timeout.connect(parts.queue_free)
	if DisplayServer.get_name() == "headless":
		return  # no renderer to bake the pose with
	for mi in target.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.mesh and (mi.skeleton == NodePath() or mi.skin != null):
			_ghosts.spawn(mi)


## One-shot (life <= 0) or looping-for-`life`-seconds positional sound.
func _sound(stream: AudioStream, where: Vector3, vol: float, life: float) -> void:
	var tree := get_tree()
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	var snd := AudioStreamPlayer3D.new()
	snd.stream = stream
	snd.bus = "SFX"
	snd.volume_db = vol
	snd.max_distance = 50.0
	parent.add_child(snd)
	snd.global_position = where
	snd.play()
	if life > 0.0:
		var tw := snd.create_tween()
		tw.tween_interval(maxf(0.0, life - 0.4))
		tw.tween_property(snd, "volume_db", -40.0, 0.4)
		tw.tween_callback(snd.queue_free)
	else:
		snd.finished.connect(snd.queue_free)


func ready_fraction() -> float:
	return clampf(1.0 - cooldown_left / COOLDOWN, 0.0, 1.0)


func cooldown_total() -> float:
	return COOLDOWN


func effective_range() -> float:
	return RANGE

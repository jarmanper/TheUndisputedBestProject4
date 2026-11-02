extends Node
## MARKING (Rhaiyn) - assignment rules, matching the owner's prototype.
## Q marks the single target under the crosshair when it is visible and within
## RANGE (inclusive). Exactly one mark exists at a time: marking a new target
## replaces the old one, and re-marking the same target refreshes it to the
## full DURATION. Marking never damages, never moves and never changes a
## suspension. An existing mark is NOT lost when the target leaves range or
## goes behind a wall - only the floating icon is hidden.
## Invalid activation costs nothing: no mark, no cooldown.
## Kept as polish only: the lock sound, outline material and tracker hologram.

signal marked_enemy(enemy)
signal mark_changed(enemy)

const DURATION := 8.0
const RANGE := 15.0
const COOLDOWN := 3.0
const LOCK_SFX := preload("res://assets/audio/sfx/tracker_lock.wav")

var current_target: Node = null
var duration_left := 0.0
var cooldown_left := 0.0

var _ping: AudioStreamPlayer

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	_ping = AudioStreamPlayer.new()
	_ping.stream = LOCK_SFX
	_ping.bus = "SFX"
	add_child(_ping)


func is_ready() -> bool:
	return cooldown_left <= 0.0


func _physics_process(delta: float) -> void:
	cooldown_left = TimbukFx.tick(cooldown_left, delta)
	_tick_duration(delta)
	if player.dead or get_tree().paused:
		return
	# new press only: holding Q does not re-mark
	if Input.is_action_just_pressed("mark"):
		try_mark()


func _tick_duration(delta: float) -> void:
	if current_target == null:
		return
	if not is_instance_valid(current_target) or current_target.is_dead():
		clear_mark()
		return
	duration_left = TimbukFx.tick(duration_left, delta)
	if duration_left <= 0.0:
		clear_mark()
		return
	# a wall hides the icon but keeps the mark
	if current_target.has_method("set_mark_icon_visible"):
		current_target.set_mark_icon_visible(player.has_clear_line(current_target.center()))


## Marks the crosshair target. Returns true only when a mark was applied.
func try_mark() -> bool:
	if player.dead or not is_ready():
		return false
	var target := player.crosshair_target(RANGE)
	if target == null:
		return false
	var refresh := target == current_target
	if not refresh:
		_release_current()
	current_target = target
	duration_left = DURATION
	cooldown_left = COOLDOWN
	target.set_marked(true)
	_ping.pitch_scale = 1.15 if refresh else 1.0
	_ping.play()
	marked_enemy.emit(target)
	mark_changed.emit(target)
	return true


## Explosion calls this after it has snapshotted the target it needs.
func consume_mark() -> void:
	clear_mark()


func clear_mark() -> void:
	_release_current()
	current_target = null
	duration_left = 0.0
	mark_changed.emit(null)


func _release_current() -> void:
	if current_target != null and is_instance_valid(current_target):
		current_target.set_marked(false)


func has_mark() -> bool:
	return current_target != null and is_instance_valid(current_target)


func duration_fraction() -> float:
	return clampf(duration_left / DURATION, 0.0, 1.0)


func cooldown_total() -> float:
	return COOLDOWN


func effective_range() -> float:
	return RANGE


func ready_fraction() -> float:
	return clampf(1.0 - cooldown_left / COOLDOWN, 0.0, 1.0)

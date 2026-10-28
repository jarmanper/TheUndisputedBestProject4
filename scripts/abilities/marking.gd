extends Node
## Owns mark state/lifetime only. Explosion calls consume_mark() after validation.
signal current_target_changed(target: Target)

const RANGE := 15.0
const DURATION := 8.0
const COOLDOWN := 3.0
var cooldown_left := 0.0
var duration_left := 0.0
var current_target: Target

@onready var player: Player = get_parent().get_parent() as Player

func _physics_process(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if cooldown_left < 0.000001:
		cooldown_left = 0.0
	if is_instance_valid(current_target):
		if not current_target.is_alive() or not current_target.marked:
			clear_mark()
		else:
			duration_left = maxf(0.0, duration_left - delta)
			if duration_left < 0.000001:
				clear_mark()
	elif current_target != null:
		clear_mark()
	if Input.is_action_just_pressed("mark") and is_ready():
		try_activate()

func is_ready() -> bool:
	return cooldown_left <= 0.0

func try_activate() -> bool:
	if not is_ready() or player.hp <= 0:
		return false
	var selected := player.crosshair_target(RANGE)
	if selected == null:
		return false
	clear_mark()
	current_target = selected
	current_target.defeated.connect(_on_target_defeated)
	current_target.marked = true
	duration_left = DURATION
	cooldown_left = COOLDOWN
	current_target_changed.emit(current_target)
	return true

func clear_mark() -> void:
	if is_instance_valid(current_target):
		if current_target.defeated.is_connected(_on_target_defeated):
			current_target.defeated.disconnect(_on_target_defeated)
		current_target.marked = false
	current_target = null
	duration_left = 0.0
	current_target_changed.emit(null)

func consume_mark() -> void:
	clear_mark()

func _on_target_defeated(_target: Target) -> void:
	clear_mark()

func _exit_tree() -> void:
	clear_mark()

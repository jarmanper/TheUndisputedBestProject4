extends Node
const RANGE := 12.0
const DURATION := 2.0
const MARKED_DURATION := 4.0
const COOLDOWN := 7.0
var cooldown_left := 0.0
var duration_left := 0.0
var current_target: TimbukEnemy
@onready var player: TimbukPlayer = get_parent()

func _physics_process(delta: float) -> void:
	cooldown_left = maxf(0, cooldown_left - delta)
	if cooldown_left < 0.000001:
		cooldown_left = 0
	if is_instance_valid(current_target):
		if current_target.is_dead():
			end_suspension()
		else:
			duration_left = maxf(0, duration_left - delta)
			current_target.suspend_fraction = duration_left / current_target.suspend_duration
			if duration_left < 0.000001:
				end_suspension()
	elif current_target != null:
		end_suspension()
	if Input.is_action_just_pressed("suspend"):
		activate()

func is_ready() -> bool:
	return cooldown_left <= 0

func activate() -> bool:
	if not is_ready() or player.dead:
		return false
	var target := player.crosshair_target(RANGE)
	if target == null:
		return false
	end_suspension()
	current_target = target
	duration_left = MARKED_DURATION if target.is_marked() else DURATION
	target.suspend_duration = duration_left
	target.set_suspended(true)
	target.died.connect(_on_defeat)
	cooldown_left = COOLDOWN
	return true

func reduce_cooldown(seconds: float) -> void:
	cooldown_left = maxf(0, cooldown_left - seconds)

func end_suspension(target: TimbukEnemy = null) -> void:
	if target != null and target != current_target:
		return
	if is_instance_valid(current_target):
		if current_target.died.is_connected(_on_defeat):
			current_target.died.disconnect(_on_defeat)
		current_target.set_suspended(false)
	current_target = null
	duration_left = 0

func _on_defeat(_enemy: TimbukEnemy) -> void:
	end_suspension()

func _exit_tree() -> void:
	end_suspension()

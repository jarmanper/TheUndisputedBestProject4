extends Node
## MARKING — Rhaiyn Newby. Integrated sibling ability; never owns suspension.
signal marked_enemy(enemy)
const RANGE := 15.0
const DURATION := 8.0
const COOLDOWN := 3.0
var cooldown_left := 0.0
var duration_left := 0.0
var current_target: TimbukEnemy
@onready var player: TimbukPlayer = get_parent()

func _physics_process(delta: float) -> void:
	cooldown_left = maxf(0, cooldown_left - delta)
	if cooldown_left < 0.000001:
		cooldown_left = 0
	if is_instance_valid(current_target):
		if current_target.is_dead() or not current_target.is_marked():
			clear_mark()
		else:
			duration_left = maxf(0, duration_left - delta)
			if duration_left < 0.000001:
				clear_mark()
	elif current_target != null:
		clear_mark()
	if Input.is_action_just_pressed("mark"):
		try_mark()

func is_ready() -> bool:
	return cooldown_left <= 0

func try_mark() -> bool:
	if not is_ready() or player.dead or get_tree().paused:
		return false
	var target := player.crosshair_target(RANGE)
	if target == null:
		return false
	clear_mark()
	current_target = target
	target.died.connect(_on_defeat)
	target.tree_exiting.connect(_on_target_exiting)
	target.set_marked(true)
	duration_left = DURATION
	cooldown_left = COOLDOWN
	marked_enemy.emit(target)
	return true

func clear_mark() -> void:
	# Drop our reference before notifying the target, including teardown. A
	# target exiting the level must not leave a stale reference for Explosion.
	var previous := current_target
	current_target = null
	duration_left = 0
	if is_instance_valid(previous):
		if previous.died.is_connected(_on_defeat):
			previous.died.disconnect(_on_defeat)
		if previous.tree_exiting.is_connected(_on_target_exiting):
			previous.tree_exiting.disconnect(_on_target_exiting)
		previous.set_marked(false)

func consume_mark() -> void:
	clear_mark()

func _on_defeat(_enemy: TimbukEnemy) -> void:
	clear_mark()

func _on_target_exiting() -> void:
	clear_mark()

func _exit_tree() -> void:
	clear_mark()

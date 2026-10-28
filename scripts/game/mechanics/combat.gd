extends Node
const DAMAGE := 20
const RANGE := 3.0
const COOLDOWN := 0.6
var cooldown_left := 0.0
@onready var player: TimbukPlayer = get_parent()

func _physics_process(delta: float) -> void:
	cooldown_left = maxf(0, cooldown_left - delta)
	if cooldown_left < 0.000001:
		cooldown_left = 0
	if Input.is_action_just_pressed("attack"):
		fire()

func is_ready() -> bool:
	return cooldown_left <= 0

func fire() -> bool:
	if not is_ready() or player.dead:
		return false
	var target := player.crosshair_target(RANGE)
	if target == null:
		return false
	var was_marked := target.is_marked()
	# Defer only the defeat notification until the specified hit order completes.
	target.apply_damage(DAMAGE, false)
	cooldown_left = COOLDOWN
	if was_marked:
		player.get_node("Suspend").reduce_cooldown(1.0)
	target.finish_defeat()
	if target.model != null:
		TimbukFx.spawn(get_tree(), "res://scenes/effects/impact_sparks.tscn", target.center())
	return true

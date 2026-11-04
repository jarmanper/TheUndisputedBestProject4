extends Node
## Daniel: instantaneous, geometry-occluded blast; feedback never changes damage.
signal detonated(origin: Vector3, hits: int)
const RANGE := 15.0
const RADIUS := 4.0
const DAMAGE := 40
const SUSPENDED_DAMAGE := 60
const COOLDOWN := 5.0
var cooldown_left := 0.0
@onready var player: TimbukPlayer = get_parent()

func _physics_process(delta: float) -> void:
	cooldown_left = maxf(0, cooldown_left - delta)
	if cooldown_left < 0.000001:
		cooldown_left = 0
	if Input.is_action_just_pressed("explode"):
		detonate()

func is_ready() -> bool:
	return cooldown_left <= 0

func can_detonate() -> bool:
	if not is_ready() or player.dead or get_tree().paused:
		return false
	var marking := player.get_node("Marking")
	var primary: TimbukEnemy = marking.current_target
	if not is_instance_valid(primary) or primary.is_dead() or not primary.is_marked():
		return false
	return player.upper_body_point().distance_squared_to(primary.center()) <= RANGE * RANGE and player.visible_point(primary.center())

func detonate() -> bool:
	if not can_detonate():
		return false
	var marking := player.get_node("Marking")
	var primary: TimbukEnemy = marking.current_target
	var origin := primary.center()
	var affected: Array[TimbukEnemy] = []
	var suspended: Array[bool] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var target := node as TimbukEnemy
		if target == null or target.is_dead() or origin.distance_squared_to(target.center()) > RADIUS * RADIUS:
			continue
		if target != primary and not player.clear_line(origin, target.center()):
			continue
		affected.append(target)
		suspended.append(target.is_suspended())
	marking.consume_mark()
	for i in affected.size():
		affected[i].apply_damage(SUSPENDED_DAMAGE if suspended[i] else DAMAGE, false)
	for target in affected:
		player.get_node("Suspend").end_suspension(target)
		target.set_suspended(false)
	for target in affected:
		target.finish_defeat()
	cooldown_left = COOLDOWN
	detonated.emit(origin, affected.size())
	# Visuals also work for collider-only targets, independently of their model.
	if DisplayServer.get_name() != "headless":
		TimbukFx.spawn(get_tree(), "res://scenes/effects/explosion_blue.tscn", origin)
	return true

extends SceneTree
## The assignment's mechanic rules as executable checks: real physics queries
## plus deterministic active-gameplay timers driven at the exact boundaries.
## Adapted from the rules audited on `playtest-integration` to this branch's
## player/enemy API. Run headless:
##   godot --headless --path . --script tests/assignment_mechanics.gd

var checks := 0
var failures := 0
var world: Node3D
var player: TimbukPlayer
var mark: Node
var combat: Node
var suspend: Node
var explosion: Node
var targets: Array[TimbukEnemy] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
		printerr("FAIL: ", message)


func settle() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame


func target_at(center: Vector3) -> TimbukEnemy:
	var target := TimbukEnemy.new()
	target.position = center - Vector3.UP * TimbukEnemy.CENTER_HEIGHT
	target.navigation_enabled = false
	world.add_child(target)
	target.set_physics_process(false)
	targets.append(target)
	return target


func reset() -> void:
	mark.clear_mark()
	suspend.end_suspension()
	for ability in [mark, combat, suspend, explosion]:
		ability.cooldown_left = 0.0
	for target in targets:
		if is_instance_valid(target):
			target.free()
	targets.clear()
	player.position = Vector3.ZERO
	player.health = 100.0
	player.dead = false


## Points the (world-parented) camera at a target from behind the aim point.
func aim_at(target: TimbukEnemy) -> void:
	player.camera.global_position = player.upper_body_point() + Vector3(0, 0, 3)
	player.camera.look_at(target.center())


func advance(delta: float) -> void:
	for ability in [mark, combat, suspend, explosion]:
		ability._physics_process(delta)


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	player = load("res://scenes/game/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.camera.reparent(world)
	mark = player.get_node("Marking")
	combat = player.get_node("Combat")
	suspend = player.get_node("Suspend")
	explosion = player.get_node("Explosion")
	for ability in [mark, combat, suspend, explosion]:
		ability.set_physics_process(false)

	# ---------------------------------------------------------------- player
	check(player.health == 100 and player.max_health == 100, "player starts at 100 HP")
	check(player.upper_body_point() == Vector3(0, 1.4, 0), "aim point exactly 1.4 m above the collider bottom")
	check(mark.is_ready() and combat.is_ready() and suspend.is_ready() and explosion.is_ready(), "all four abilities start ready")

	# --------------------------------------------------------------- Marking
	var first := target_at(Vector3(0, 1.4, -15))
	aim_at(first)
	await settle()
	check(mark.try_mark(), "Marking accepts exactly 15 m")
	check(mark.duration_left == 8 and mark.cooldown_left == 3, "Marking starts an 8 s mark and a 3 s cooldown")
	check(first.health == 100, "Marking causes no damage")
	check(not mark.try_mark(), "Marking ignores activation during its cooldown")
	advance(2.999)
	check(not mark.is_ready(), "Marking cooldown still running before 3 s")
	advance(0.001)
	check(mark.is_ready(), "Marking cooldown ends at exactly 3 s")
	check(mark.try_mark() and mark.duration_left == 8, "re-marking the same target refreshes it to 8 s")
	advance(3)
	first.position.z = -15.001
	await settle()
	check(not mark.try_mark() and mark.cooldown_left == 0 and first.marked, "15.001 m is invalid, costs no cooldown, and the live mark survives")
	first.position.z = -5
	var second := target_at(Vector3(3, 1.4, -5))
	aim_at(second)
	await settle()
	check(mark.try_mark() and second.marked and not first.marked, "exactly one mark exists; the new target replaces the old")
	advance(3)
	var wall := _wall(Vector3(0, 1.4, -2.5), Vector3(12, 4, 0.2))
	await settle()
	check(not mark.try_mark() and mark.is_ready() and second.marked, "a wall blocks a NEW mark without erasing the live one or starting a cooldown")
	advance(4.999)
	check(second.marked, "the mark is still live just before 8 s")
	advance(0.001)
	check(not second.marked and mark.current_target == null, "the mark expires at exactly 8 s")
	wall.free()
	reset()

	# ---------------------------------------------------------------- Combat
	first = target_at(Vector3(0, 1.4, -3))
	aim_at(first)
	await settle()
	check(combat.fire() and first.health == 80, "Combat at exactly 3 m deals exactly 20 damage")
	check(combat.cooldown_left == 0.6 and not combat.fire(), "Combat sets a 0.6 s cooldown and rejects a repeat")
	advance(0.599)
	check(not combat.is_ready(), "Combat not ready before 0.6 s")
	advance(0.001)
	check(combat.is_ready(), "Combat ready at exactly 0.6 s")
	first.position.z = -3.001
	await settle()
	check(not combat.fire() and combat.is_ready(), "Combat beyond 3 m is invalid and starts no cooldown")
	first.position.z = -2
	await settle()
	mark.try_mark()
	suspend.cooldown_left = 5
	check(combat.fire() and first.health == 60 and first.marked and suspend.cooldown_left == 4, "a marked hit stays 20 damage, keeps the mark and takes 1 s off Suspend")
	advance(0.6)
	first.health = 20
	check(combat.fire() and first.health == 0 and is_equal_approx(suspend.cooldown_left, 2.4), "a lethal marked hit still shortens Suspend's cooldown")
	check(first.collision_layer == 0 and first.collision_mask == 0 and not first.marked and not first.suspended, "defeat drops collision and clears both effects at once")
	reset()

	# --------------------------------------------------------------- Suspend
	first = target_at(Vector3(0, 1.4, -12))
	aim_at(first)
	await settle()
	check(suspend.activate() and suspend.duration_left == 2 and suspend.cooldown_left == 7, "Suspend at exactly 12 m holds 2 s on a 7 s cooldown")
	advance(1.999)
	check(first.suspended, "an unmarked suspension is still running before 2 s")
	advance(0.001)
	check(not first.suspended, "an unmarked suspension ends at exactly 2 s")
	advance(5)
	check(suspend.is_ready(), "Suspend is ready again at exactly 7 s")
	first.position.z = -12.001
	await settle()
	check(not suspend.activate() and suspend.is_ready(), "Suspend beyond 12 m is invalid and costs no cooldown")
	first.position.z = -2
	aim_at(first)
	await settle()
	mark.try_mark()
	check(suspend.activate() and suspend.duration_left == 4, "marked AT activation gives exactly 4 s")
	var before := first.global_position
	first.velocity = Vector3(1, -9, 0)
	first._physics_process(0.1)
	check(first.global_position == before and first.velocity == Vector3.ZERO and first.collision_layer == 4, "a frozen target cannot move and stays solid")
	mark.consume_mark()
	check(suspend.duration_left == 4 and first.suspended, "losing the mark does not change a running suspension")
	mark.cooldown_left = 0
	mark.try_mark()
	check(suspend.duration_left == 4, "gaining a mark does not change a running suspension")
	combat.fire()
	check(first.health == 80 and first.suspended, "a frozen target still takes damage without being released")
	advance(3.999)
	check(first.suspended, "a marked suspension survives until just before 4 s")
	advance(0.001)
	check(not first.suspended, "a marked suspension ends at exactly 4 s")
	second = target_at(Vector3(3, 1.4, -2))
	suspend.cooldown_left = 0
	aim_at(first)
	suspend.activate()
	suspend.cooldown_left = 0  # stands in for Combat-earned relief, never a player action
	aim_at(second)
	await settle()
	check(suspend.activate() and second.suspended and not first.suspended, "a new Suspend releases the old target; only one is ever frozen")
	suspend.cooldown_left = 0
	check(suspend.activate() and suspend.duration_left == 2, "re-suspending replaces the remaining time instead of stacking")
	reset()

	# ------------------------------------------------------------- Explosion
	first = target_at(Vector3(0, 1.4, -5))
	second = target_at(Vector3(4, 1.4, -5))
	var outside := target_at(Vector3(-4.001, 1.4, -5))
	var frozen := target_at(Vector3(0, 1.4, -8))
	frozen.set_suspended(true)
	aim_at(first)
	await settle()
	mark.try_mark()
	check(explosion.detonate(), "Explosion fires off the live mark")
	check(first.health == 60 and second.health == 60 and frozen.health == 40 and outside.health == 100, "40 normal / 60 total suspended, exactly 4 m included and 4.001 m excluded")
	check(not first.marked and mark.current_target == null and not frozen.suspended, "the blast consumes the mark and ends the suspensions it touched")
	check(explosion.cooldown_left == 5 and player.health == 100 and frozen.velocity == Vector3.ZERO, "5 s cooldown, no player damage and no knockback")
	advance(4.999)
	check(not explosion.is_ready(), "Explosion not ready before 5 s")
	advance(0.001)
	check(explosion.is_ready() and not explosion.detonate() and explosion.cooldown_left == 0, "ready at 5 s, and with no mark the activation is invalid and free")
	reset()

	first = target_at(Vector3(0, 1.4, -5))
	second = target_at(Vector3(3, 1.4, -5))
	frozen = target_at(Vector3(1, 1.4, -5))
	wall = _wall(Vector3(2, 1.4, -5), Vector3(0.2, 4, 3))
	aim_at(first)
	await settle()
	mark.try_mark()
	check(explosion.detonate() and second.health == 100 and frozen.health == 60, "geometry blocks the blast; other targets never shield anyone")
	wall.free()
	reset()

	first = target_at(Vector3(0, 1.4, -15))
	aim_at(first)
	await settle()
	mark.try_mark()
	first.position.z = -15.001
	await settle()
	check(not explosion.detonate() and first.marked and explosion.cooldown_left == 0, "an out-of-range blast keeps both the mark and the cooldown")
	first.position.z = -15
	await settle()
	check(explosion.detonate(), "Explosion includes the 15 m boundary")
	reset()

	# ----------------------------------------------------------------- enemy
	first = target_at(Vector3(0, 1.4, -1.5))
	aim_at(first)
	await settle()
	first._player = player
	first._physics_process(0)
	check(first.state == TimbukEnemy.State.WINDUP and first.windup_left == 0.75, "a visible player within 2 m starts a 0.75 s wind-up")
	first._physics_process(0.749)
	check(player.health == 100, "the wind-up does no damage early")
	first._physics_process(0.001)
	check(player.health == 90 and first.attack_cooldown_left == 2, "the blow lands for exactly 10 after 0.75 s, then waits 2 s")
	first.attack_cooldown_left = 0
	first._physics_process(0)
	first.set_suspended(true)
	check(first.state != TimbukEnemy.State.WINDUP and first.attack_cooldown_left == 2, "freezing cancels the wind-up and starts the 2 s wait")
	first._physics_process(1)
	check(first.attack_cooldown_left == 1 and player.health == 90, "the attack wait keeps running while frozen")
	first.set_suspended(false)
	first._physics_process(1)
	check(first.state == TimbukEnemy.State.WINDUP and first.windup_left == 0.75, "release starts a fresh wind-up once the wait is done")
	player.position.z = 4
	first._physics_process(0.75)
	check(player.health == 90, "stepping out of range during the wind-up is a clean miss")
	player.position = Vector3.ZERO
	first.position = Vector3(0, 0.3, -8.001)
	first.alerted = false
	first.state = TimbukEnemy.State.IDLE
	first._physics_process(0)
	check(not first.alerted, "the chase does not trigger beyond 8 m")
	first.position.z = -8
	first._physics_process(0)
	check(first.alerted and TimbukEnemy.SPEED == 2.5, "8 m is inclusive and the chase speed is 2.5 m/s")
	reset()

	# ------------------------------------------------------- signature combo
	first = target_at(Vector3(0, 1.4, -2))
	aim_at(first)
	await settle()
	check(mark.try_mark() and suspend.activate() and combat.fire(), "the combo opens with Mark, Suspend and the first Combat hit")
	advance(0.6)
	check(combat.fire() and explosion.detonate() and first.health == 0, "two Combat hits plus a suspended Explosion kill exactly 100 HP")
	reset()

	# ------------------------------------------------------------ pause/loss
	first = target_at(Vector3(0, 1.4, -2))
	aim_at(first)
	await settle()
	mark.try_mark()
	mark.set_physics_process(true)
	var dur: float = mark.duration_left
	var cd: float = mark.cooldown_left
	paused = true
	await settle()
	check(mark.duration_left == dur and mark.cooldown_left == cd, "pausing freezes the live timers")
	paused = false
	mark.set_physics_process(false)
	player.damage(100)
	check(player.dead and player.health == 0 and not combat.fire() and not suspend.activate(), "zero HP is a loss and blocks every ability")
	reset()

	world.queue_free()
	await process_frame
	print("ASSIGNMENT MECHANICS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _wall(where: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = where
	world.add_child(body)
	return body

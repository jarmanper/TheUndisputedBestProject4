extends SceneTree
## Actual physics queries plus deterministic active-gameplay timer checks.
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
		push_error(message)

func settle() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func target_at(center: Vector3) -> TimbukEnemy:
	var target := TimbukEnemy.new()
	target.position = center - Vector3.UP * 1.1
	target.navigation_enabled = false
	world.add_child(target)
	target.set_physics_process(false)
	targets.append(target)
	return target

func reset() -> void:
	mark.clear_mark()
	suspend.end_suspension()
	for ability in [mark, combat, suspend, explosion]:
		ability.cooldown_left = 0
	for target in targets:
		target.free()
	targets.clear()
	player.position = Vector3.ZERO
	player.health = 100
	player.dead = false

func aim(target: TimbukEnemy) -> void:
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
	check(player.health == 100 and player.max_health == 100, "player starts at 100 HP")
	check(player.upper_body_point() == Vector3(0, 1.4, 0), "upper body exactly 1.4 m above collider bottom")
	check(mark.is_ready() and combat.is_ready() and suspend.is_ready() and explosion.is_ready(), "all four abilities start ready")
	var first := target_at(Vector3(0, 1.4, -15))
	aim(first)
	await settle()
	check(mark.try_mark(), "Marking accepts exactly 15 m")
	check(mark.duration_left == 8 and mark.cooldown_left == 3, "Marking starts 8 s duration and 3 s cooldown")
	check(first.health == 100, "Marking causes no damage")
	check(not mark.try_mark(), "Marking ignores activation during cooldown")
	advance(2.999)
	check(not mark.is_ready(), "Marking cooldown remains before 3 s")
	advance(0.001)
	check(mark.is_ready(), "Marking cooldown ends at exactly 3 s")
	check(mark.try_mark() and mark.duration_left == 8, "same-target re-mark resets duration to 8 s")
	advance(3)
	first.position.z = -15.001
	await settle()
	check(not mark.try_mark() and mark.cooldown_left == 0 and first.marked, "15.001 m invalid; no cooldown; active mark survives range loss")
	first.position.z = -5
	var second := target_at(Vector3(3, 1.4, -5))
	aim(second)
	await settle()
	check(mark.try_mark() and second.marked and not first.marked, "only one marked target; successful replacement")
	advance(3)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1.4, -2.5)
	world.add_child(wall)
	await settle()
	check(not mark.try_mark() and mark.is_ready() and second.marked, "wall blocks NEW marking but does not erase existing mark or start cooldown")
	advance(4.999)
	check(second.marked, "mark remains just before 8 s")
	advance(0.001)
	check(not second.marked and mark.current_target == null, "mark expires at exactly 8 s")
	wall.free()
	reset()
	first = target_at(Vector3(0, 1.4, -3))
	aim(first)
	await settle()
	check(combat.fire() and first.health == 80, "Combat at 3 m deals exactly 20 damage")
	check(combat.cooldown_left == 0.6 and not combat.fire(), "Combat cooldown 0.6 s; repeat rejected")
	advance(0.599)
	check(not combat.is_ready(), "Combat not ready before 0.6 s")
	advance(0.001)
	check(combat.is_ready(), "Combat ready at exactly 0.6 s")
	first.position.z = -3.001
	await settle()
	check(not combat.fire() and combat.is_ready(), "Combat beyond 3 m invalid and starts no cooldown")
	first.position.z = -2
	await settle()
	mark.try_mark()
	suspend.cooldown_left = 5
	check(combat.fire() and first.health == 60 and first.marked and suspend.cooldown_left == 4, "marked Combat stays 20 damage, preserves mark and reduces Suspend by 1 s")
	advance(0.6)
	first.health = 20
	check(combat.fire() and first.health == 0 and is_equal_approx(suspend.cooldown_left, 2.4), "lethal marked hit still reduces Suspend cooldown")
	check(first.collision_layer == 0 and first.collision_mask == 0 and not first.marked and not first.suspended, "defeat immediately disables collision and effects")
	reset()
	first = target_at(Vector3(0, 1.4, -12))
	aim(first)
	await settle()
	check(suspend.activate() and suspend.duration_left == 2 and suspend.cooldown_left == 7, "Suspend at 12 m: 2 s normal duration, 7 s cooldown")
	advance(1.999)
	check(first.suspended, "normal suspension remains before 2 s")
	advance(0.001)
	check(not first.suspended, "normal suspension ends at exactly 2 s")
	advance(5)
	check(suspend.is_ready(), "Suspend ready at exactly 7 s")
	first.position.z = -12.001
	await settle()
	check(not suspend.activate() and suspend.is_ready(), "Suspend beyond 12 m invalid with no cooldown")
	first.position.z = -2
	aim(first)
	await settle()
	mark.try_mark()
	check(suspend.activate() and suspend.duration_left == 4, "marked AT activation gives exactly 4 s")
	var position_before := first.global_position
	first.velocity = Vector3(1, -9, 0)
	first._physics_process(0.1)
	check(first.global_position == position_before and first.velocity == Vector3.ZERO and first.collision_layer == 4, "suspended target remains fixed and solid")
	mark.consume_mark()
	check(suspend.duration_left == 4 and first.suspended, "removing mark does not change active suspension")
	mark.cooldown_left = 0
	mark.try_mark()
	check(suspend.duration_left == 4, "applying mark does not change active suspension")
	combat.fire()
	check(first.health == 80 and first.suspended, "Combat deals 20 to suspended target without releasing it")
	advance(3.999)
	check(first.suspended, "marked suspension survives until just before 4 s")
	advance(0.001)
	check(not first.suspended, "marked suspension ends at exactly 4 s")
	second = target_at(Vector3(3, 1.4, -2))
	suspend.cooldown_left = 0
	aim(first)
	suspend.activate()
	suspend.cooldown_left = 0 # Represents Combat-earned reduction, never a player action.
	aim(second)
	await settle()
	check(suspend.activate() and second.suspended and not first.suspended, "new Suspend releases old target; only one suspension")
	suspend.cooldown_left = 0
	check(suspend.activate() and suspend.duration_left == 2, "re-suspend replaces duration instead of stacking")
	reset()
	first = target_at(Vector3(0, 1.4, -5))
	second = target_at(Vector3(4, 1.4, -5))
	var outside := target_at(Vector3(-4.001, 1.4, -5))
	var frozen := target_at(Vector3(0, 1.4, -8))
	frozen.set_suspended(true)
	aim(first)
	await settle()
	mark.try_mark()
	check(explosion.detonate(), "Explosion succeeds using existing mark")
	check(first.health == 60 and second.health == 60 and frozen.health == 40 and outside.health == 100, "Explosion includes primary and exactly 4 m, excludes 4.001 m; 40 normal / 60 TOTAL suspended")
	check(not first.marked and mark.current_target == null and not frozen.suspended, "Explosion consumes mark and ends affected suspension")
	check(explosion.cooldown_left == 5 and player.health == 100 and frozen.velocity == Vector3.ZERO, "Explosion 5 s cooldown, no player damage or knockback")
	advance(4.999)
	check(not explosion.is_ready(), "Explosion not ready before 5 s")
	advance(0.001)
	check(explosion.is_ready() and not explosion.detonate() and explosion.cooldown_left == 0, "Explosion ready at 5 s; no-mark activation invalid without cooldown")
	reset()
	first = target_at(Vector3(0, 1.4, -5))
	second = target_at(Vector3(3, 1.4, -5))
	frozen = target_at(Vector3(1, 1.4, -5))
	wall = StaticBody3D.new()
	shape = CollisionShape3D.new()
	box = BoxShape3D.new()
	box.size = Vector3(0.2, 4, 3)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(2, 1.4, -5)
	world.add_child(wall)
	aim(first)
	await settle()
	mark.try_mark()
	check(explosion.detonate() and second.health == 100 and frozen.health == 60, "geometry blocks secondary blast; targets never block blast")
	wall.free()
	reset()
	first = target_at(Vector3(0, 1.4, -15))
	aim(first)
	await settle()
	mark.try_mark()
	first.position.z = -15.001
	await settle()
	check(not explosion.detonate() and first.marked and explosion.cooldown_left == 0, "invalid out-of-range Explosion preserves mark and cooldown")
	first.position.z = -15
	await settle()
	check(explosion.detonate(), "Explosion 15 m boundary included")
	reset()
	first = target_at(Vector3(0, 1.4, -1.5))
	aim(first)
	await settle()
	first._player = player
	first._physics_process(0)
	check(first.state == first.State.WINDUP and first.windup_left == 0.75, "enemy within visible 2 m begins 0.75 s wind-up")
	first._physics_process(0.749)
	check(player.health == 100, "enemy wind-up does not damage early")
	first._physics_process(0.001)
	check(player.health == 90 and first.attack_cooldown_left == 2, "enemy hit exactly 10 damage after wind-up; 2 s wait")
	first.attack_cooldown_left = 0
	first._physics_process(0)
	first.set_suspended(true)
	check(first.state != first.State.WINDUP and first.attack_cooldown_left == 2, "Suspend cancels attack and starts 2 s wait")
	first._physics_process(1)
	check(first.attack_cooldown_left == 1 and player.health == 90, "enemy attack cooldown continues during suspension")
	first.set_suspended(false)
	first._physics_process(1)
	check(first.state == first.State.WINDUP and first.windup_left == 0.75, "release starts fresh wind-up only when cooldown done")
	player.position.z = 4
	first._physics_process(0.75)
	check(player.health == 90, "enemy misses when player leaves range during wind-up")
	player.position = Vector3.ZERO
	first.position = Vector3(0, 0.3, -8.001)
	first.alerted = false
	first.state = first.State.IDLE
	first.set_suspended(false)
	first._physics_process(0)
	check(not first.alerted, "enemy does not trigger beyond 8 m")
	first.position.z = -8
	first._physics_process(0)
	check(first.alerted and first.SPEED == 2.5, "8 m inclusive chase trigger and 2.5 m/s speed")
	reset()
	first = target_at(Vector3(0, 1.4, -2))
	aim(first)
	await settle()
	check(mark.try_mark() and suspend.activate() and combat.fire(), "signature combo starts Mark, Suspend and first Combat")
	advance(0.6)
	check(combat.fire() and explosion.detonate() and first.health == 0, "signature combo two Combat hits plus suspended Explosion kills 100 HP")
	reset()
	first = target_at(Vector3(0, 1.4, -2))
	aim(first)
	await settle()
	mark.try_mark()
	mark.set_physics_process(true)
	var duration_before: float = mark.duration_left
	var cooldown_before: float = mark.cooldown_left
	paused = true
	await settle()
	check(mark.duration_left == duration_before and mark.cooldown_left == cooldown_before, "pause freezes active timers")
	paused = false
	mark.set_physics_process(false)
	player.damage(100)
	check(player.dead and player.health == 0 and not combat.fire() and not suspend.activate(), "zero player HP is loss and blocks abilities")
	reset()
	world.queue_free()
	await process_frame
	print("ASSIGNMENT MECHANICS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

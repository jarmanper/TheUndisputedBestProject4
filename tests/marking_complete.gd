extends SceneTree
## Rhaiyn Newby's complete Marking acceptance suite, using integrated classes.
var checks := 0
var failures := 0
var world: Node3D
var player: TimbukPlayer
var marking: Node
var combat: Node
var suspend: Node
var explosion: Node
var targets: Array[TimbukEnemy] = []
var activations := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if value:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func ticks(count := 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func key_q(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func target_at(point: Vector3) -> TimbukEnemy:
	var enemy := TimbukEnemy.new()
	enemy.position = point - Vector3.UP * 1.1
	enemy.navigation_enabled = false
	world.add_child(enemy)
	enemy.set_physics_process(false)
	targets.append(enemy)
	return enemy

func aim(enemy: TimbukEnemy) -> void:
	player.camera.global_position = player.upper_body_point() + Vector3(0, 0, 3)
	player.camera.look_at(enemy.center())

func reset() -> void:
	key_q(false)
	marking.set_physics_process(false)
	marking.clear_mark()
	suspend.end_suspension()
	for ability in [marking, combat, suspend, explosion]:
		ability.cooldown_left = 0
	for enemy in targets:
		if is_instance_valid(enemy):
			enemy.free()
	targets.clear()
	player.position = Vector3.ZERO
	player.health = 100
	player.dead = false

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	player = load("res://scenes/game/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.camera.reparent(world)
	marking = player.get_node("Marking")
	combat = player.get_node("Combat")
	suspend = player.get_node("Suspend")
	explosion = player.get_node("Explosion")
	for ability in [marking, combat, suspend, explosion]:
		ability.set_physics_process(false)
	marking.marked_enemy.connect(func(_enemy): activations += 1)
	var input := InputMap.action_get_events("mark")
	check(input.size() == 1 and input[0] is InputEventKey and input[0].physical_keycode == KEY_Q, "Marking binds physical Q only")
	check(marking.RANGE == 15 and marking.DURATION == 8 and marking.COOLDOWN == 3 and marking.is_ready(), "15 m / 8 s / 3 s named constants; ready on first frame")
	var first := target_at(Vector3(0, 1.4, -15))
	aim(first)
	await ticks()
	check(player.crosshair_target(15) == first and marking.try_mark(), "center-screen first living target at exactly 15 m succeeds")
	check(marking.current_target == first and first.marked and marking.duration_left == 8 and marking.cooldown_left == 3, "successful activation starts one mark with exactly 8 s and 3 s")
	marking._physics_process(2.999)
	check(not marking.is_ready(), "cooldown remains active at 2.999 s")
	marking._physics_process(0.001)
	check(marking.is_ready(), "cooldown becomes ready at exactly 3 s")
	check(marking.try_mark() and marking.duration_left == 8, "same-target re-mark resets to 8 s without stacking")
	marking._physics_process(3)
	first.position.z = -15.001
	await ticks()
	var remaining: float = marking.duration_left
	check(not marking.try_mark() and marking.is_ready() and first.marked and marking.duration_left == remaining, "15.001 m invalid: no cooldown, no mark removal or timer reset")
	marking._physics_process(4.999)
	check(first.marked, "existing mark survives range loss and remains active at 7.999 s")
	marking._physics_process(0.001)
	check(not first.marked and marking.current_target == null and marking.duration_left == 0, "mark ends at exactly 8 active seconds")
	first.position.z = -5
	aim(first)
	await ticks()
	marking.try_mark()
	marking._physics_process(3)
	var second := target_at(Vector3(3, 1.4, -5))
	aim(second)
	await ticks()
	check(marking.try_mark() and second.marked and not first.marked and marking.current_target == second, "successful replacement leaves only the selected target marked")
	marking._physics_process(3)
	player.camera.look_at(player.camera.global_position + Vector3(0, 1, 0.1))
	remaining = marking.duration_left
	check(not marking.try_mark() and marking.is_ready() and second.marked and marking.duration_left == remaining, "empty crosshair preserves old mark and duration, with no cooldown")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1.4, -2.5)
	world.add_child(wall)
	aim(first)
	await ticks()
	check(not marking.try_mark() and marking.is_ready() and second.marked and marking.current_target == second, "wall blocks NEW marking and invalid attempt preserves the old mark")
	marking._physics_process(1)
	check(second.marked, "existing mark persists behind level geometry")
	wall.free()
	reset()
	first = target_at(Vector3(0, 1.4, -4))
	second = target_at(Vector3(0, 1.4, -7))
	aim(second)
	await ticks()
	check(marking.try_mark() and marking.current_target == first, "nearest living collider wins over a farther crosshair target")
	first.apply_damage(100)
	check(marking.current_target == null and not first.marked and marking.duration_left == 0, "target defeat immediately clears mark and owner reference")
	marking._physics_process(3)
	await ticks()
	check(marking.try_mark() and marking.current_target == second, "defeated collider does not block the next living target")
	second.free()
	check(marking.current_target == null and marking.duration_left == 0, "target leaving the level clears its reference before it is freed")
	reset()
	first = target_at(Vector3(0, 1.4, -2))
	aim(first)
	await ticks()
	first.state = first.State.WINDUP
	first.windup_left = 0.5
	first.attack_cooldown_left = 0.75
	first.velocity = Vector3(2.5, 0, 0)
	check(marking.try_mark() and first.health == 100 and first.state == first.State.WINDUP and first.windup_left == 0.5 and first.attack_cooldown_left == 0.75 and first.velocity == Vector3(2.5, 0, 0), "Marking causes no damage and never interrupts movement or attack state")
	suspend.cooldown_left = 5
	check(combat.fire() and first.health == 80 and first.marked and suspend.cooldown_left == 4, "nonlethal Combat preserves mark, deals 20, and reduces Suspend cooldown by 1")
	combat.cooldown_left = 0
	first.health = 20
	check(combat.fire() and first.health == 0 and suspend.cooldown_left == 3 and marking.current_target == null, "lethal marked Combat still grants reduction before defeat clears the mark")
	reset()
	first = target_at(Vector3(0, 1.4, -2))
	aim(first)
	await ticks()
	check(suspend.activate() and suspend.duration_left == 2, "unmarked-at-activation Suspend lasts 2 s")
	check(marking.try_mark() and suspend.duration_left == 2 and first.suspended, "marking an already-suspended target does not extend its 2 s duration")
	marking.clear_mark()
	check(suspend.duration_left == 2 and first.suspended, "removing a mark never changes the active suspension")
	suspend.end_suspension()
	suspend.cooldown_left = 0
	marking.cooldown_left = 0
	marking.try_mark()
	check(suspend.activate() and suspend.duration_left == 4, "marked-at-activation Suspend lasts 4 s")
	marking._physics_process(3)
	check(marking.try_mark() and suspend.duration_left == 4, "refreshing a mark does not alter an existing 4 s suspension")
	marking._physics_process(8)
	check(not first.marked and suspend.duration_left == 4 and first.suspended, "mark expiration never changes active suspension")
	marking.try_mark()
	wall = StaticBody3D.new()
	shape = CollisionShape3D.new()
	box = BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1.4, -1)
	world.add_child(wall)
	await ticks()
	check(not explosion.detonate() and explosion.is_ready() and first.marked and marking.current_target == first, "invalid occluded Explosion leaves active mark intact and starts no cooldown")
	wall.free()
	await ticks()
	player.camera.look_at(player.camera.global_position + Vector3(0, 1, 0.1))
	check(explosion.detonate() and not first.marked and marking.current_target == null and marking.duration_left == 0 and first.health == 40, "successful Explosion uses existing mark without aiming, deals 60 suspended damage and consumes mark")
	reset()
	first = target_at(Vector3(0, 1.4, -2))
	aim(first)
	await ticks()
	paused = true
	check(not marking.try_mark() and marking.is_ready() and not first.marked, "public activation cannot create a mark while gameplay is paused")
	paused = false
	# Real Q edges, including a press made during cooldown and held past expiry.
	activations = 0
	marking.set_physics_process(true)
	await physics_frame
	key_q(true)
	await ticks()
	check(first.marked and activations == 1, "physical Q press activates Marking in the physics loop")
	key_q(false)
	await ticks(30)
	key_q(true)
	await ticks()
	check(activations == 1, "Q pressed during cooldown is ignored")
	await ticks(190)
	check(marking.is_ready() and activations == 1 and marking.duration_left < 5, "holding ignored Q past cooldown does not queue or repeat a mark")
	key_q(false)
	await ticks()
	key_q(true)
	await ticks()
	check(activations == 2 and marking.duration_left > 7.9, "a new Q press after cooldown re-marks and resets duration")
	key_q(false)
	remaining = marking.duration_left
	var cooldown_before: float = marking.cooldown_left
	paused = true
	await ticks(5)
	check(marking.duration_left == remaining and marking.cooldown_left == cooldown_before, "pause freezes both mark duration and cooldown")
	paused = false
	marking.set_physics_process(false)
	world.remove_child(player)
	check(not first.marked and marking.current_target == null, "player/level teardown clears the active mark immediately")
	player.free()
	world.queue_free()
	await process_frame
	print("COMPLETE MARKING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

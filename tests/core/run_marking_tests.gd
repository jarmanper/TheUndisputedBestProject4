extends SceneTree
## Run: Godot --headless --path . --script tests/core/run_marking_tests.gd
## Real physics queries/input plus deterministic active-gameplay timer checks.
var failures := 0
var checks := 0
var world: Node3D
var player: Player
var marking: Node
var first: Target
var second: Target
var wall: StaticBody3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
	else:
		print("PASS: ", description)

func settle() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func aim(target: Target) -> void:
	player.camera.global_position = player.upper_body_point() + Vector3(0, 0, 3)
	player.camera.look_at(target.center())

func make_target(at: Vector3) -> Target:
	var target := Target.new()
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 2.0
	collider.shape = shape
	target.add_child(collider)
	target.collision_layer = 4
	target.collision_mask = 0
	target.position = at
	world.add_child(target)
	return target

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	player = load("res://scenes/game/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.spring_arm.set_physics_process(false)
	player.camera.reparent(world)
	marking = player.get_node("Abilities/Marking")
	marking.set_physics_process(false)
	first = make_target(Vector3(0, 1.4, -5))
	second = make_target(Vector3(3, 1.4, -5))
	aim(first)
	await settle()
	check(is_equal_approx(player.upper_body_point().y, 1.4), "upper-body point exactly 1.4 m above capsule bottom")
	check(player.hp == 100 and first.hp == 100 and marking.is_ready(), "100 HP and Marking ready at start")
	check(player.crosshair_target(15.0) == first, "crosshair selects living collider")
	check(marking.try_activate(), "valid activation succeeds")
	check(first.marked and marking.current_target == first, "activation sets the mark")
	check(marking.duration_left == 8.0 and marking.cooldown_left == 3.0, "activation starts exactly 8 s duration and 3 s cooldown")
	check(first.hp == 100, "Marking deals no damage")
	check(not marking.try_activate(), "cooldown activation ignored")
	marking._physics_process(2.999)
	check(not marking.is_ready(), "cooldown not ready before 3 seconds")
	marking._physics_process(0.001)
	check(marking.is_ready(), "cooldown ready at exactly 3 seconds")
	first.suspended = true
	first.velocity = Vector3(2.5, 0, 0)
	check(marking.try_activate(), "same-target refresh succeeds")
	check(marking.duration_left == 8.0 and first.suspended and first.velocity.x == 2.5, "refresh resets to 8 s without altering suspension or motion")
	marking._physics_process(3.0)
	aim(second)
	check(marking.try_activate(), "different-target activation succeeds")
	check(second.marked and not first.marked and first.suspended, "only one mark; replacement preserves suspension")
	marking._physics_process(3.0)
	player.camera.look_at(player.camera.global_position + Vector3(0, 1, 0.1))
	check(not marking.try_activate() and marking.is_ready() and second.marked, "empty crosshair preserves old mark and starts no cooldown")
	player.position.x = 25.0
	marking._physics_process(1.0)
	check(second.marked, "leaving range does not erase active mark")
	aim(second)
	check(not marking.try_activate() and marking.is_ready(), "outside 15 m cannot start a new mark")
	player.position = Vector3.ZERO
	marking.clear_mark()
	first.position = Vector3(0, 1.4, -15)
	aim(first)
	await settle()
	check(player.crosshair_target(15.0) == first, "15 m boundary included, measured collider center to upper body")
	first.position.z = -15.001
	await settle()
	check(player.crosshair_target(15.0) == null, "center beyond 15 m excluded even when collider surface is closer")
	first.position.z = -5
	aim(first)
	await settle()
	check(marking.try_activate(), "mark before occlusion succeeds")
	marking._physics_process(3.0)
	wall = StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 4, 0.2)
	collider.shape = box
	wall.add_child(collider)
	wall.position = Vector3(0, 1.4, -2.5)
	world.add_child(wall)
	await settle()
	check(player.crosshair_target(15.0) == null, "solid geometry blocks crosshair selection")
	check(not marking.try_activate() and marking.is_ready() and first.marked, "wall prevents NEW mark but preserves existing mark and cooldown")
	# A shoulder camera may see around cover while the upper body cannot.
	box.size = Vector3(0.3, 4, 0.2)
	player.camera.global_position += Vector3(3, 0, 0)
	player.camera.look_at(first.center())
	await settle()
	var screen_center := root.get_visible_rect().size * 0.5
	var origin := player.camera.project_ray_origin(screen_center)
	var ray := PhysicsRayQueryParameters3D.create(origin, first.center(), 5, [player.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == first and player.crosshair_target(15) == null, "upper-body visibility blocks marking even when shoulder camera sees around cover")
	marking._physics_process(4.999)
	check(first.marked, "mark survives until just before 8 s")
	marking._physics_process(0.001)
	check(not first.marked and marking.current_target == null, "mark ends at exactly 8 s")
	wall.queue_free()
	await settle()
	# First collider wins even if another living target is behind it.
	second.position = Vector3(0, 1.4, -8)
	aim(first)
	await settle()
	check(player.crosshair_target(15.0) == first, "first target blocks selection of a farther target")
	check(marking.try_activate(), "mark before death succeeds")
	first.apply_damage(1000)
	check(first.hp == 0 and not first.marked and not first.suspended and marking.current_target == null, "defeat clamps HP and immediately clears effects/current mark")
	check(first.collision_layer == 0 and first.collision_mask == 0 and first.velocity == Vector3.ZERO, "defeated target cannot block or move")
	first.marked = true
	first.suspended = true
	check(not first.marked and not first.suspended, "defeated targets reject effects")
	await settle()
	aim(second)
	check(player.crosshair_target(15.0) == second, "defeated collider does not block targeting")
	marking._physics_process(3.0)
	check(marking.try_activate(), "mark remaining living target")
	marking.consume_mark()
	check(not second.marked and marking.current_target == null, "Explosion integration can consume mark")
	marking._physics_process(3.0)
	# Real input and physics: held Q does not queue a refresh at cooldown end.
	marking.set_physics_process(true)
	# Submit just after a physics tick so the next physics tick reads this edge.
	await physics_frame
	var press := InputEventAction.new()
	press.action = "mark"
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await settle()
	check(second.marked, "Q action just_pressed path marks a target")
	marking.set_physics_process(false)
	marking._physics_process(3.0)
	marking.set_physics_process(true)
	await settle()
	check(marking.duration_left < 6.0, "holding Q across cooldown never repeats or queues")
	Input.action_release("mark")
	marking.set_physics_process(false)
	marking.clear_mark()
	marking.cooldown_left = 0.0
	marking.try_activate()
	marking.set_physics_process(true)
	var before_duration: float = marking.duration_left
	var before_cooldown: float = marking.cooldown_left
	paused = true
	await settle()
	check(marking.duration_left == before_duration and marking.cooldown_left == before_cooldown, "pause freezes duration and cooldown")
	paused = false
	marking.set_physics_process(false)
	world.remove_child(player)
	check(not second.marked, "level/player teardown clears mark")
	player.free()
	world.queue_free()
	await process_frame
	print("MARKING TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

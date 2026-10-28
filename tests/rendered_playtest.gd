extends SceneTree
## Exercise title transition, real mapped ability inputs and live enemy AI.
var checks := 0
var failures := 0
var level: Node3D
var player: TimbukPlayer

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func press(action: String) -> void:
	await physics_frame
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await ticks(2)
	Input.action_release(action)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/captures")
	root.get_texture().get_image().save_png("res://.godot/captures/live_%s.png" % label)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var title: Control = load("res://scenes/ui/title_screen.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await ticks(120)
	await capture("title")
	title.get_node("%NewGame").pressed.emit()
	await ticks(100)
	level = current_scene
	check(level.scene_file_path == "res://scenes/game/main.tscn", "title New Game loads playable game")
	player = level.get_node("Player")
	var target: TimbukEnemy = level.required_targets[0]
	var camera_before := player.head.rotation.x
	if DisplayServer.get_name() != "headless":
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0, 15)
		player._unhandled_input(motion)
		check(player.head.rotation.x != camera_before, "captured mouse controls shoulder camera")
		player.head.rotation.x = camera_before
	await capture("start")
	await press("mark")
	check(target.marked, "live Q marks crosshair target")
	await press("suspend")
	check(target.suspended and player.get_node("Suspend").duration_left > 3.8, "live E freezes marked target for 4 s")
	await capture("frozen")
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 4, 0.2)
	collider.shape = box
	wall.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	wall.add_child(mesh)
	wall.position = Vector3(0.55, 1.8, 1.8)
	level.add_child(wall)
	await ticks(3)
	check(target.marked and not target.get("_icon").visible and player.crosshair_target(15) == null, "level geometry hides tracking icon and blocks selection while preserving mark")
	await capture("occluded")
	wall.queue_free()
	await ticks(3)
	await press("attack")
	check(target.health == 80 and target.suspended, "live Left Mouse deals 20 without ending suspension")
	await ticks(38)
	await press("attack")
	check(target.health == 60, "second new Left Mouse press deals 20")
	await press("explode")
	check(target.health == 0 and not target.marked and not target.suspended, "live R completes 100 HP signature combo")
	await capture("explosion")
	# Exercise live AI against a stationary player using the real damage method.
	player.set_physics_process(false)
	for enemy in level.required_targets:
		if enemy == target:
			continue
		enemy.set_physics_process(false)
	# Walk a visible corridor enemy into attack range on real navigation.
	var attacker: TimbukEnemy = level.required_targets[3]
	player.global_position = Vector3(0, 0.001, -6.8)
	attacker.set_physics_process(true)
	await ticks(180)
	check(attacker.alerted and attacker.global_position.z > -9, "live enemy triggers at 8 m and navigates toward player")
	check(player.health < 100 and int(player.health) % 10 == 0, "live enemy attacks for 10 damage")
	await capture("attack")
	# A clear existing floor area in containment isolates the enemy attack
	# from decorative props while exercising repeated attacks and real loss.
	player.global_position = Vector3(0, 0.001, -33)
	attacker.global_position = Vector3(0, 0.001, -34.3)
	attacker.velocity = Vector3.ZERO
	attacker.state = attacker.State.CHASE
	attacker.attack_cooldown_left = 0
	for frame in 60 * 33:
		await ticks(1)
		if current_scene != level or player.dead:
			break
	check(current_scene != level or player.dead, "live enemy can kill player; loss/restart occurs")
	await capture("loss")
	for frame in 130:
		await ticks(1)
		if is_instance_valid(current_scene) and current_scene != level:
			break
	level = current_scene
	player = level.get_node("Player")
	check(player.health == 100 and level.required_targets.all(func(e): return e.health == 100), "live loss restarts with full HP and original targets")
	await capture("restart")
	level.queue_free()
	await process_frame
	OS.delay_msec(100)
	await process_frame
	print("LIVE PLAYTEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

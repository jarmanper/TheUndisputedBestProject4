extends SceneTree
## Rhaiyn's acceptance test in the actual title/main/final-chamber scenes.
var checks := 0
var failures := 0
var level: Node3D
var player: TimbukPlayer
var marking: Node

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

func press(action: String) -> void:
	await physics_frame
	var event: InputEvent
	if action == "attack":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = true
		event = mouse
	else:
		var key := InputEventKey.new()
		key.physical_keycode = {"mark": KEY_Q, "suspend": KEY_E, "explode": KEY_R}[action]
		key.pressed = true
		event = key
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await ticks()
	event = event.duplicate()
	event.set("pressed", false)
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/captures")
	root.get_texture().get_image().save_png("res://.godot/captures/marking_final_%s.png" % label)

func freeze_test_enemies() -> void:
	for target in level.required_targets:
		target.set_physics_process(false)
	player = level.get_node("Player")
	marking = player.get_node("Marking")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var title_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var title: Control = load(title_path).instantiate()
	root.add_child(title)
	current_scene = title
	await ticks(100)
	title.get_node("%NewGame").pressed.emit()
	await ticks(100)
	level = current_scene
	check(level.scene_file_path == "res://scenes/game/main.tscn", "F5 title New Game loads actual integrated main scene")
	freeze_test_enemies()
	var first: TimbukEnemy = level.required_targets[0]
	check(marking.get_script().resource_path == "res://scripts/game/mechanics/marking.gd", "actual game uses Rhaiyn's integrated Marking script")
	await press("mark")
	check(marking.current_target == first and first.marked, "physical Q marks a living target in the actual facility")
	check(level.required_targets.filter(func(target): return target.marked).size() == 1, "actual level has exactly one mark")
	var meshes: Array[MeshInstance3D] = first.get("_meshes")
	var icon: MeshInstance3D = first.get("_icon")
	check(not meshes.is_empty() and meshes.all(func(mesh): return mesh.material_overlay == first.get("_outline")), "bright existing marked-outline material applied to all creature meshes")
	var top := 2.2
	for mesh in meshes:
		var bounds: AABB = (first.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		top = maxf(top, bounds.end.y)
	check(icon.visible and icon.position.y > top and (icon.mesh as QuadMesh).size.x <= 0.55, "small tracking icon is visible above the creature's visual bounds")
	check(not String(first.get("_outline").shader.code).contains("depth_test_disabled") and not String((icon.mesh as QuadMesh).material.shader.code).contains("depth_test_disabled"), "outline and tracker shaders retain level-geometry depth testing")
	await capture("marked")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	var wall_mesh := MeshInstance3D.new()
	var mesh_box := BoxMesh.new()
	mesh_box.size = box.size
	wall_mesh.mesh = mesh_box
	wall.add_child(wall_mesh)
	wall.position = Vector3(0.55, 1.8, 1.8)
	level.add_child(wall)
	await ticks(3)
	check(first.marked and marking.current_target == first and not icon.visible and player.crosshair_target(15) == null, "actual wall hides tracker and blocks selection without erasing existing mark")
	await capture("occluded")
	wall.queue_free()
	await ticks(3)
	check(icon.visible and first.marked, "tracker reappears after cover is removed without re-marking")
	await press("attack")
	check(first.health == 80 and first.marked and marking.current_target == first, "actual Combat deals 20 and leaves Marking active")
	await press("suspend")
	check(first.suspended and player.get_node("Suspend").duration_left > 3.8, "actual marked-at-activation Suspend receives 4 seconds")
	await capture("suspended")
	await press("explode")
	check(first.health == 20 and not first.marked and marking.current_target == null and marking.duration_left == 0, "actual Explosion consumes active mark and applies 60 suspended damage")
	# Explicit restart with a LIVE mark, without routing through death cleanup.
	marking.cooldown_left = 0 # Test fixture only: avoid waiting another 3 s.
	await press("mark")
	check(first.marked and marking.current_target == first, "live mark present immediately before actual level restart")
	var old_marking := marking
	reload_current_scene()
	await scene_changed
	level = current_scene
	freeze_test_enemies()
	await ticks()
	check(not is_instance_valid(old_marking) and marking.current_target == null and marking.duration_left == 0 and marking.cooldown_left == 0, "actual restart frees old Marking state and restores ready empty state")
	check(level.required_targets.all(func(target): return not target.marked and target.health == 100), "actual restart clears every mark and restores enemies")
	first = level.required_targets[0]
	await press("mark")
	check(first.marked and marking.current_target == first, "Q works immediately in restarted level")
	await capture("restarted")
	# Clear all required targets to exercise real transition/end cleanup.
	for target in level.required_targets:
		target.apply_damage(100)
	await scene_changed
	level = current_scene
	freeze_test_enemies()
	check(level.final_chamber and marking.current_target == null and marking.is_ready() and level.required_targets.all(func(target): return not target.marked), "real level completion starts final chamber with no leaked mark or cooldown")
	var twin: TimbukEnemy = level.required_targets[0]
	# Aim the shoulder-camera crosshair, accounting for its lateral offset.
	# Turning only the player's body toward the target does not aim the ray.
	for adjustment in 3:
		var direction := twin.center() - player.camera.global_position
		player.rotation.y = atan2(-direction.x, -direction.z)
		player.head.rotation.x = atan2(direction.y, Vector2(direction.x, direction.z).length())
		await ticks(3)
	await press("mark")
	check(twin.marked and marking.current_target == twin, "same Q Marking works on the actual Twin target")
	await capture("twin")
	twin.apply_damage(100)
	check(marking.current_target == null and not twin.marked, "Twin defeat clears its mark immediately")
	await ticks()
	level.queue_free()
	await process_frame
	OS.delay_msec(100)
	await process_frame
	print("FINAL GAME MARKING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

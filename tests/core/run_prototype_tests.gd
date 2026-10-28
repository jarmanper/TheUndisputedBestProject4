extends SceneTree
## Run with --headless for integration, or without it and -- --capture for PNGs.
var checks := 0
var failures := 0
var scene: Node3D
var player: Player
var marking: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/captures")
	root.get_texture().get_image().save_png("res://.godot/captures/prototype_%s.png" % label)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/game/marking_prototype.tscn", "F5 main scene is playable prototype")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "project uses Compatibility")
	for action in ["move_forward", "move_back", "move_left", "move_right", "attack", "mark", "suspend", "explode", "pause"]:
		check(InputMap.has_action(action), "input exists: " + action)
	scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	marking = player.get_node("Abilities/Marking")
	scene.get_node("PauseController").set_paused(false)
	await ticks(60)
	var start := player.global_position
	print("SPAWN: ", start, " camera: ", player.camera.global_position)
	check(player.is_on_floor() and absf(start.y) < 0.2, "player settles on existing facility collision")
	check(scene.get_node("Facility/Graphics/Areas/AreaAEntrance") != null, "instances original graphics map")
	check(scene.required_targets.size() == 3, "all three targets exist at level start")
	var target: Target = scene.get_node("TestTargets/LobbyTarget")
	check(player.crosshair_target(15) == target, "initial shoulder camera crosshair aims at lobby target")
	await capture("start")
	await physics_frame
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	Input.parse_input_event(q)
	Input.flush_buffered_events()
	await ticks(2)
	q = InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = false
	Input.parse_input_event(q)
	Input.flush_buffered_events()
	check(marking.current_target == target and target.marked, "physical Q input marks target in facility")
	var feedback := target.get_node("MarkFeedback")
	check(feedback.icon.visible and feedback.icon.global_position.y > target.center().y + 1.0, "tracking icon is above target")
	check(feedback.meshes.size() > 0 and feedback.meshes[0].material_overlay == feedback.outline, "existing outline material applied to creature")
	await capture("marked")
	# Test occlusion in this rendered scene with a temporary test-only wall.
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 4.0, 0.2)
	collider.shape = box
	wall.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	wall.add_child(mesh)
	wall.position = Vector3(0.55, 1.8, 1.8)
	scene.add_child(wall)
	await ticks(3)
	check(target.marked and not feedback.icon.visible and player.crosshair_target(15) == null, "wall hides icon and blocks new selection without removing mark")
	await capture("occluded")
	wall.queue_free()
	await ticks(2)
	check(feedback.icon.visible and target.marked, "icon returns after occlusion without re-marking")
	# Use the actual map's collision and player movement code.
	Input.action_press("move_left")
	await ticks(60)
	Input.action_release("move_left")
	check(player.global_position.x < start.x - 3.5, "WASD moves player through lobby")
	check(player.is_on_floor(), "player remains on map floor while walking")
	Input.action_press("move_left")
	await ticks(120)
	Input.action_release("move_left")
	check(player.global_position.x > -8.0, "existing lobby wall/props stop movement")
	print("WALL STOP: ", player.global_position)
	player.global_position = start
	player.velocity = Vector3.ZERO
	await ticks(3)
	# Mouse camera responds without adding an action.
	if DisplayServer.get_name() != "headless":
		var previous_yaw := player.rotation.y
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(30, 10)
		player._unhandled_input(motion)
		check(player.rotation.y != previous_yaw, "mouse motion rotates third-person camera")
	player.rotation.y = 0
	player.camera_pivot.rotation.x = 0
	var duration: float = marking.duration_left
	var cooldown: float = marking.cooldown_left
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	Input.flush_buffered_events()
	await ticks(10)
	check(paused, "Esc pauses gameplay")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pause releases mouse")
	check(marking.duration_left == duration and marking.cooldown_left == cooldown, "Esc pause freezes active gameplay timers")
	await capture("paused")
	esc = InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = false
	Input.parse_input_event(esc)
	Input.flush_buffered_events()
	esc = InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	Input.flush_buffered_events()
	await ticks(2)
	check(not paused, "Esc resumes gameplay")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "resume captures mouse")
	Input.action_release("pause")
	# Verify lifecycle hooks without implementing teammates' attacks.
	for required in scene.required_targets:
		required.apply_damage(100)
	check(scene.outcome == scene.Outcome.VICTORY, "last required target defeat triggers victory immediately")
	player.take_hit(100)
	check(scene.outcome == scene.Outcome.LOSS, "same-step player death overrides victory")
	await ticks(125)
	check(current_scene != scene and current_scene.get_node("Player").hp == 100, "loss auto-restarts with restored player and targets")
	check(current_scene.get_node("Player/Abilities/Marking").is_ready(), "restart restores ready Marking")
	check(current_scene.required_targets.size() == 3 and current_scene.required_targets[0].hp == 100, "restart restores all required target HP")
	print("PROTOTYPE TESTS: %d checks, %d failures" % [checks, failures])
	current_scene.queue_free()
	await process_frame
	# Fixed-fps headless tests can exit faster than the audio mixing thread can
	# release the original map's hundreds of looping playback references.
	OS.delay_msec(100)
	await process_frame
	quit(0 if failures == 0 else 1)

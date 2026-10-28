extends SceneTree
var checks := 0
var failures := 0
var level: Node3D
var player: TimbukPlayer
var victory_count := 0

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

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/captures")
	root.get_texture().get_image().save_png("res://.godot/captures/playtest_%s.png" % label)

func load_level(path: String) -> void:
	level = load(path).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	for enemy in level.required_targets:
		enemy.set_physics_process(false)
	await ticks(10)

func clean_level() -> void:
	level.queue_free()
	await process_frame
	OS.delay_msec(100)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "Compatibility configured")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/title_screen.tscn", "title screen is main scene")
	var preset := ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK and preset.get_value("preset.0", "platform") == "Web" and preset.get_value("preset.0", "export_path") == "docs/index.html", "Web preset exports into docs/index.html")
	check(preset.get_value("preset.0.options", "variant/thread_support") == false and FileAccess.file_exists("res://docs/.gdignore"), "web threads disabled and docs/.gdignore exists")
	var controls := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "mark": KEY_Q, "suspend": KEY_E, "explode": KEY_R, "pause": KEY_ESCAPE}
	for action in controls:
		var events := InputMap.action_get_events(action)
		check(events.size() == 1 and events[0] is InputEventKey and events[0].physical_keycode == controls[action], "exact binding: " + action)
	check(InputMap.action_get_events("attack")[0].button_index == MOUSE_BUTTON_LEFT, "Left Mouse binds Combat")
	for forbidden in ["sprint", "interact", "reload", "flashlight", "inventory", "jump", "crouch", "fire"]:
		check(not InputMap.has_action(forbidden), "no forbidden/conflicting action: " + forbidden)
	var title: Control = load("res://scenes/ui/title_screen.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await ticks(100)
	await capture("title")
	title.queue_free()
	await process_frame
	await load_level("res://scenes/game/main.tscn")
	check(player.is_on_floor(), "player starts on existing facility floor")
	check(level.required_targets.size() == 12, "12 required targets exist before gameplay")
	check(level.region.navigation_mesh.get_polygon_count() > 0, "navigation mesh baked from existing solid geometry")
	print("NAV polygons: ", level.region.navigation_mesh.get_polygon_count())
	if OS.get_cmdline_user_args().has("--save-nav"):
		ResourceSaver.save(level.region.navigation_mesh, "res://scenes/game/nav_main.tres")
	var map: RID = level.region.get_navigation_map()
	for enemy in level.required_targets:
		var path := NavigationServer3D.map_get_path(map, player.global_position, enemy.global_position, true)
		var reachable := path.size() > 1 and path[-1].distance_to(enemy.global_position) < 1.0
		check(reachable, "nav route reaches " + String(enemy.name))
		if not reachable:
			print("UNREACHABLE: ", enemy.name, " position ", enemy.global_position, " path ", path)
	var words := 0
	for label in level.find_children("*", "Label3D", true, false):
		words += String(label.text).split(" ", false).size()
	check(words == 48, "visible documents exactly 48 budgeted words")
	for enemy in level.required_targets:
		check(enemy.health == 100, String(enemy.name) + " starts at 100 HP")
		for audio in enemy.model.find_children("CreatureAudio", "Node3D", true, false):
			check(audio.lines.is_empty(), String(enemy.name) + " disables unbudgeted speech")
	check(level.region.find_children("FailedContainmentDevice*", "Node3D", true, false).size() > 0, "failed containment device preserved as non-interactive found moment")
	check(level.region.find_children("*", "MeshInstance3D", true, false).filter(func(mesh): return String(mesh.name).begins_with("BlankSign")).size() == 8, "eight unbudgeted legacy sign areas blanked with visual-only panels")
	await capture("start")
	# Physical mapped input, no direct activation shortcuts.
	await physics_frame
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	Input.parse_input_event(q)
	Input.flush_buffered_events()
	await ticks(3)
	check(player.get_node("Marking").current_target == level.required_targets[0], "physical Q marks initial crosshair target")
	await capture("marked")
	# Held Q never refreshes when cooldown becomes ready.
	var remaining_before: float = player.get_node("Marking").duration_left
	await ticks(190)
	check(player.get_node("Marking").duration_left < remaining_before - 3, "held Q does not repeat or queue")
	Input.action_release("mark")
	var start := player.global_position
	Input.action_press("move_left")
	await ticks(60)
	Input.action_release("move_left")
	check(player.global_position.x < start.x - 3.5 and player.is_on_floor(), "WASD walks on facility collision")
	Input.action_press("move_left")
	await ticks(120)
	Input.action_release("move_left")
	check(player.global_position.x > -8, "existing wall/props block player")
	player.global_position = start
	player.velocity = Vector3.ZERO
	await ticks(3)
	var mark := player.get_node("Marking")
	var duration_before: float = mark.duration_left
	level.get_node("HUD").toggle_pause()
	await ticks(10)
	check(paused and mark.duration_left == duration_before, "pause freezes gameplay timers")
	await capture("pause")
	level.get_node("HUD").toggle_pause()
	# Follow the geometry-derived nav route using actual WASD movement;
	# target collision is disabled in this traversal-only fixture (not the game).
	for enemy in level.required_targets:
		enemy.collision_layer = 0
	player.global_position = Vector3(0, 0.05, 3)
	var route := NavigationServer3D.map_get_path(map, player.global_position, Vector3(0, 0, -47), true)
	for waypoint in route:
		for frame in 360:
			var direction := waypoint - player.global_position
			direction.y = 0
			if direction.length() < 0.3:
				break
			player.rotation.y = atan2(-direction.x, -direction.z)
			Input.action_press("move_forward")
			await ticks(1)
	Input.action_release("move_forward")
	print("CENTRAL WALK END: ", player.global_position)
	check(player.global_position.z < -35 and player.is_on_floor(), "physical traversal reaches containment without interact/keys")
	await capture("containment")
	# Check exact end-of-level accounting and same-step loss priority.
	level.victory.connect(func(): victory_count += 1)
	for enemy in level.required_targets:
		enemy.apply_damage(100)
	check(level.outcome == level.Outcome.VICTORY, "last required target death records instant victory")
	player.damage(100)
	check(level.outcome == level.Outcome.LOSS, "same-step final kill/player death records LOSS")
	await ticks(1)
	check(victory_count == 0, "same-step loss prevents victory notification/progression")
	await ticks(125)
	level = current_scene
	player = level.get_node("Player")
	for enemy in level.required_targets:
		enemy.set_physics_process(false)
	check(player.health == 100 and level.required_targets.size() == 12, "loss auto-restarts in 2 active seconds with player and enemies restored")
	check(level.required_targets.all(func(e): return e.health == 100 and not e.marked and not e.suspended), "restart restores target HP and clears all effects")
	check(player.get_node("Marking").is_ready() and player.get_node("Suspend").is_ready() and player.get_node("Explosion").is_ready() and player.get_node("Combat").is_ready(), "restart restores all cooldowns")
	for enemy in level.required_targets:
		enemy.apply_damage(100)
	await ticks(5)
	level = current_scene
	player = level.get_node("Player")
	check(level.final_chamber and level.required_targets.size() == 1, "clearing first level automatically loads separate Twin level")
	var twin: TimbukEnemy = level.required_targets[0]
	twin.set_physics_process(false)
	await ticks(10)
	if OS.get_cmdline_user_args().has("--save-nav"):
		ResourceSaver.save(level.region.navigation_mesh, "res://scenes/game/nav_final.tres")
	var twin_path := NavigationServer3D.map_get_path(level.region.get_navigation_map(), player.global_position, twin.global_position, true)
	check(twin.health == 100 and twin.SPEED == 2.5 and twin.DAMAGE == 10 and twin_path.size() > 1 and twin_path[-1].distance_to(twin.global_position) < 1, "Twin has normal 100 HP/stats and a navigable chamber")
	await capture("twin")
	twin.apply_damage(100)
	await ticks(2)
	check(level.outcome == level.Outcome.VICTORY and not player.dead, "defeating every required final target wins while alive")
	await clean_level()
	print("PLAYTEST INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

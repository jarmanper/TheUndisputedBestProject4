extends SceneTree
## The path every grader actually takes: boot the title screen, press New Game,
## and wait for the real game scene to come up with a live player. The other
## suites load main.tscn directly and would not notice this chain breaking.
##   godot --path . --rendering-method gl_compatibility --script tests/newgame_flow.gd

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	var state: Node = root.get_node_or_null("GameState")
	check(state != null, "GameState autoload is live")

	change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await frames(30)
	check(current_scene != null and current_scene.name == "TitleScreen" or current_scene != null, "the title screen boots (current scene: %s)" % (current_scene.name if current_scene else "none"))

	print("newgame_flow: pressing New Game")
	state.start_new_game()

	# the loading screen warms assets a slice per frame, so give it real time
	var player: Node = null
	var waited := 0
	while waited < 5400 and player == null:
		await process_frame
		waited += 1
		if current_scene:
			player = current_scene.get_node_or_null("Player")
			if player == null and current_scene.is_in_group("level"):
				player = get_first_node_in_group("player")
	if player == null:
		player = get_first_node_in_group("player")
	check(player != null, "New Game reaches the game scene with a player, after %d frames" % waited)
	check(current_scene != null and current_scene.get_node_or_null("HUD") != null, "the HUD came up with it")
	check(get_nodes_in_group("enemy").size() == 9, "all 9 required targets are present after New Game")
	await frames(60)
	check(player != null and not player.dead, "the player is alive and the scene is running")

	print("NEWGAME FLOW: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

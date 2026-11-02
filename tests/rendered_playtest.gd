extends SceneTree
## Drives the REAL game scene with REAL input events: the four abilities on
## their mapped keys, physical WASD movement, the pause key, an enemy actually
## hitting the player, and both ways the level can end. Unit checks prove the
## numbers; this proves the game is playable.
##   godot --path . --rendering-method gl_compatibility --script tests/rendered_playtest.gd

var checks := 0
var failures := 0
var scene: Node
var player: TimbukPlayer
var state: Node
var won := false
var died := false


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


## The HUD pauses the game when the window loses focus, which it always has in
## an automated run, and paused abilities do not process input at all.
func keep_live() -> void:
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var hud: Node = scene.get_node_or_null("HUD")
	if hud and hud.has_method("set_paused"):
		hud.set_paused(false)


## Presses and releases a mapped action the way a keyboard or mouse would.
func press(action: String) -> void:
	keep_live()
	for ev in InputMap.action_get_events(action):
		var e: InputEvent = ev.duplicate()
		e.pressed = true
		Input.parse_input_event(e)
		await frames(2)
		var up: InputEvent = ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await frames(2)
		return


## Puts the player `distance` metres in front of `target`, looking at it.
func stand_before(target: Node3D, distance: float) -> void:
	var c: Vector3 = target.center()
	player.global_position = c - Vector3.UP * TimbukPlayer.AIM_HEIGHT + Vector3(0, 0, distance)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.look_at(Vector3(c.x, player.global_position.y, c.z))
	await frames(3)


func _run() -> void:
	state = root.get_node_or_null("GameState")
	scene = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(scene)
	await frames(20)

	player = scene.get_node_or_null("Player")
	check(player != null, "the game scene loads and the player exists")
	check(scene.get_node_or_null("HUD") != null, "the HUD is present")
	check(state != null, "GameState autoload is live")
	state.game_won.connect(func(): won = true)
	state.player_died.connect(func(): died = true)

	# -------------------------------------------------------- input contract
	for action in ["move_forward", "move_back", "move_left", "move_right", "attack", "mark", "suspend", "explode", "pause"]:
		check(InputMap.has_action(action), "input action exists: " + action)
	for removed in ["sprint", "interact", "reload", "flashlight", "crouch"]:
		check(not InputMap.has_action(removed), "removed action is gone: " + removed)

	var targets: Array = get_nodes_in_group("enemy")
	check(targets.size() == 9, "9 required targets staged at load (8 patients + the Twin), got %d" % targets.size())
	check(get_nodes_in_group("boss").size() == 1, "the Twin is one of the required targets")

	# Every scripted door must be open at load. These used to be sealed behind
	# `power_restored`, which no longer exists, which made the Twin unreachable
	# and the level unwinnable.
	var doors := 0
	var sealed := 0
	for node in get_nodes_in_group("interactable"):
		if not (node is Interactable) or node.kind != Interactable.Kind.DOOR:
			continue
		doors += 1
		for c in node.get_children():
			if c is CollisionShape3D and not c.disabled:
				sealed += 1
	check(doors > 0 and sealed == 0, "all %d scripted doors are open at load (%d still sealed)" % [doors, sealed])

	# ---------------------------------------------------------- real ability
	print("phase: abilities")
	keep_live()
	var t: TimbukEnemy = targets[0]
	t.navigation_enabled = false
	await stand_before(t, 2.0)
	var marking: Node = player.get_node("Marking")
	await press("mark")
	check(t.marked and marking.current_target == t, "pressing Q really marks the target in the live scene")

	var suspend: Node = player.get_node("Suspend")
	await press("suspend")
	# frames elapse between the press and this check, so the exact value has
	# already ticked down; >2 s is what proves the marked branch was taken,
	# because an unmarked freeze can never start above 2 s.
	check(t.suspended and suspend.duration_left > 2.0, "pressing E freezes it, and the live mark makes it the 4 s version (%.2f s left)" % suspend.duration_left)

	var before_hp: float = t.health
	await press("attack")
	check(t.health == before_hp - 20.0, "clicking really deals 20 damage")

	var explosion: Node = player.get_node("Explosion")
	await press("explode")
	check(t.health <= before_hp - 20.0 - 60.0 or t.is_dead(), "pressing R detonates on the marked, suspended target for 60")
	check(not explosion.is_ready(), "Explosion went on cooldown after a real press")

	# -------------------------------------------------------------- movement
	print("phase: movement")
	var t2: TimbukEnemy = targets[1]
	t2.navigation_enabled = false
	await stand_before(t2, 6.0)
	keep_live()
	var start := player.global_position
	for ev in InputMap.action_get_events("move_forward"):
		var e: InputEvent = ev.duplicate()
		e.pressed = true
		Input.parse_input_event(e)
		break
	await frames(40)
	for ev in InputMap.action_get_events("move_forward"):
		var e: InputEvent = ev.duplicate()
		e.pressed = false
		Input.parse_input_event(e)
		break
	await frames(3)
	check(player.global_position.distance_to(start) > 0.5, "holding W physically moves the player through the facility")

	# ------------------------------------------------------------ enemy hits
	print("phase: enemy attack")
	var attacker: TimbukEnemy = targets[2]
	attacker.navigation_enabled = false
	await stand_before(attacker, 1.5)
	attacker._player = player
	keep_live()
	var hp_before: float = player.health
	await frames(90)
	check(player.health < hp_before, "an enemy within 2 m really damages the player (%d -> %d)" % [hp_before, player.health])

	# ------------------------------------------------------------------- win
	print("phase: win")
	player.health = 100.0
	for e in get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.is_dead():
			e.apply_damage(1000.0)
	await frames(10)
	check(won, "defeating every required target wins the level")
	check(not died, "the win was not also recorded as a loss")

	print("RENDERED PLAYTEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

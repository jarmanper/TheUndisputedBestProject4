extends SceneTree
## Daniel's HUD cues from main (7c20a81), in this build's wordless meters: the
## Explosion meter glows exactly when R would detonate, the Marking meter while
## a mark is live, and a blast flashes the screen. None of it is a word.
## Run headless:
##   godot --headless --path . --script tests/hud_glow.gd

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
		push_error("FAIL: " + message)
		printerr("FAIL: ", message)


## Visible text on the HUD right now, by node path.
func text_nodes(hud: Node) -> Array:
	var out := []
	for n in hud.find_children("*", "", true, false):
		if (n is Label or n is RichTextLabel or n is Button) and n.is_visible_in_tree() and str(n.get("text")).strip_edges() != "":
			out.append(str(n.get_path()))
	return out


func settle() -> void:
	for i in 3:
		await physics_frame
		await process_frame


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player: TimbukPlayer = load("res://scenes/game/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.camera.reparent(world)
	var marking := player.get_node("Marking")
	var explosion := player.get_node("Explosion")
	for ability in ["Marking", "Combat", "Suspend", "Explosion"]:
		player.get_node(ability).set_physics_process(false)
	var hud: CanvasLayer = load("res://scripts/game/hud.gd").new()
	hud.player_path = hud.get_path_to(player) if hud.is_inside_tree() else NodePath()
	world.add_child(hud)
	hud.player = player

	var target := TimbukEnemy.new()
	target.position = Vector3(0, 0, -5)
	target.navigation_enabled = false
	world.add_child(target)
	target.set_physics_process(false)
	player.camera.global_position = player.upper_body_point() + Vector3(0, 0, 0.5)
	player.camera.look_at(target.center())
	await settle()
	var baseline := text_nodes(hud)

	check(not hud.is_glowing("Explosion") and not hud.is_glowing("Marking"), "no mark: neither meter glows")
	check(marking.try_mark(), "fixture: the target is marked")
	await settle()
	check(hud.is_glowing("Marking"), "a live mark lights the Marking meter")
	check(hud.is_glowing("Explosion") == explosion.can_detonate() and hud.is_glowing("Explosion"), "the Explosion meter glows when R would detonate")
	paused = true
	check(not hud.is_glowing("Explosion"), "paused, R would do nothing, so the meter does not glow")
	paused = false
	check(hud.is_glowing("Combat") == false and hud.is_glowing("Suspend") == false, "Combat and Suspend never glow")

	check(explosion.detonate(), "fixture: the blast resolves")
	await process_frame
	check(hud.blast_flash() > 0.0, "a blast flashes the screen")
	check(not hud.is_glowing("Explosion"), "after the blast the meter goes dark (mark consumed, cooling down)")
	await create_timer(0.6).timeout
	check(is_zero_approx(hud.blast_flash()), "the flash fades within 0.6 s")

	check(text_nodes(hud) == baseline, "the glow and the flash add no words to the HUD")

	world.queue_free()
	await process_frame
	print("HUD GLOW: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

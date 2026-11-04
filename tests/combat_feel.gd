extends SceneTree
## Combat feedback (blood, flinch, shake, kill marker) as executable checks,
## plus the rules that feedback must never bend: 20 damage on the same frame,
## a 0.6 s cooldown, no knockback, and a wind-up that a hit does not cancel.
## Run headless:
##   godot --headless --path . --script tests/combat_feel.gd

const MODEL := "res://scenes/characters/tall_patient_a.tscn"
const SPARKS := "res://scenes/effects/impact_sparks.tscn"

var checks := 0
var failures := 0
var world: Node3D
var player: TimbukPlayer
var combat: Node
var suspend: Node
var hud: Node
var targets: Array[TimbukEnemy] = []


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


func settle() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## A real patient model, so the flinch has a mesh to move.
func target_at(center: Vector3) -> TimbukEnemy:
	var target := TimbukEnemy.new()
	target.model_scene = load(MODEL)
	target.position = center - Vector3.UP * TimbukEnemy.CENTER_HEIGHT
	target.navigation_enabled = false
	world.add_child(target)
	target.set_physics_process(false)
	targets.append(target)
	return target


func aim_at(target: TimbukEnemy) -> void:
	player.camera.global_position = player.upper_body_point() + Vector3(0, 0, 3)
	player.camera.look_at(target.center())


func reset() -> void:
	suspend.end_suspension()
	combat.cooldown_left = 0.0
	combat.set("_miss_fx_cd", 0.0)
	player.set("_trauma", 0.0)
	hud.last = null
	for target in targets:
		if is_instance_valid(target):
			target.free()
	targets.clear()


func count_group(group: String) -> int:
	return root.get_tree().get_nodes_in_group(group).size()


func count_sparks() -> int:
	var n := 0
	for c in root.get_children():
		if c.scene_file_path == SPARKS:
			n += 1
	return n


## How far the model's up axis leans from the enemy's up axis, in degrees.
func tilt_deg(target: TimbukEnemy) -> float:
	return rad_to_deg(target.model.basis.y.angle_to(Vector3.UP))


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	player = load("res://scenes/game/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.camera.reparent(world)
	combat = player.get_node("Combat")
	suspend = player.get_node("Suspend")
	for ability in [player.get_node("Marking"), combat, suspend, player.get_node("Explosion")]:
		ability.set_physics_process(false)
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar last = null\nfunc show_hit_marker(kill := false) -> void:\n\tlast = kill\n"
	stub.reload()
	hud = Node.new()
	hud.set_script(stub)
	hud.add_to_group("hud")
	world.add_child(hud)

	# -------------------------------------------------------- rules still hold
	var t := target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	check(combat.fire() and t.health == 80, "a hit with feedback still deals exactly 20 on the same frame")
	check(combat.cooldown_left == 0.6, "feedback leaves the 0.6 s cooldown exact")
	reset()

	# ------------------------------------------------------------------ flinch
	t = target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	check(t.has_method("flinch"), "enemies can flinch")
	var body_before := t.global_position
	var hitbox_before: Vector3 = t.get_node("BodyHitbox").global_position
	combat.fire()
	await wait(0.03)
	check(tilt_deg(t) > 1.0, "a hit tilts the enemy's model")
	var up_world: Vector3 = t.global_basis * t.model.basis.y
	check(up_world.z < 0.0, "the model tilts away from the player")
	check(t.global_position == body_before and t.get_node("BodyHitbox").global_position == hitbox_before,
			"the flinch moves no body and no hitbox (no knockback)")
	await wait(0.4)
	check(tilt_deg(t) < 0.5, "the model springs back to its rest pose")
	reset()

	t = target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	t.set("_player", player)
	t._begin_windup()
	t.windup_left = 0.5
	combat.fire()
	check(t.state == TimbukEnemy.State.WINDUP and t.windup_left == 0.5, "a hit leaves a wind-up running untouched")
	reset()

	t = target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	t.set_suspended(true)
	combat.fire()
	await wait(0.03)
	check(tilt_deg(t) < 0.01 and t.health == 80, "a suspended enemy takes the hit but stays frozen")
	reset()

	# ------------------------------------------------------------------- blood
	t = target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	var sprays := count_group("blood_spray")
	var sparks := count_sparks()
	combat.fire()
	check(count_group("blood_spray") > sprays, "a landed hit sprays blood")
	check(count_sparks() == sparks, "a landed hit makes no wall sparks")
	reset()

	sprays = count_group("blood_spray")
	var splats := count_group("blood_splat")
	combat._fire_at_nothing()
	check(count_group("blood_spray") == sprays and count_group("blood_splat") == splats, "a miss leaves no blood")
	reset()

	t = target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	t.health = 20
	splats = count_group("blood_splat")
	combat.fire()
	check(t.is_dead() and count_group("blood_splat") > splats, "a kill leaves blood on the floor")
	reset()

	# ------------------------------------------------------ shake and markers
	combat._fire_at_nothing()
	var miss_shake: float = player.get_trauma()
	reset()
	t = target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	combat.fire()
	var hit_shake: float = player.get_trauma()
	check(hud.last == false, "a normal hit shows the normal hit marker")
	reset()
	t = target_at(Vector3(0, 1.4, -2))
	aim_at(t)
	await settle()
	t.health = 20
	combat.fire()
	var kill_shake: float = player.get_trauma()
	check(hud.last == true, "a kill shows the kill marker")
	check(hit_shake > miss_shake, "a landed hit shakes harder than a miss")
	check(kill_shake > hit_shake, "a kill shakes harder than a hit")
	reset()

	world.queue_free()
	await process_frame
	print("COMBAT FEEL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

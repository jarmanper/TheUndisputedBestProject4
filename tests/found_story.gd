extends SceneTree
## The story you find in the world (scenes/game/found_story.tscn) as
## executable checks: Mom's recorders sit where her voice plays and run when it
## does, Dad's flashlight still points down the stairs, the twins' room and the
## chamber carry the family, and none of it adds a word, a rule or a blocker.
## Run headless:
##   godot --headless --path . --script tests/found_story.gd

const FAMILY_PHOTO := "res://assets/materials/photo_family.tres"
const PHOTO := "res://scenes/props/photo_frame.tscn"
const GURNEY := "res://scenes/props/covered_gurney.tscn"
## Twin chamber dais, where the boss fight happens (build_facility area_e).
const DAIS_CENTER := Vector3(14.7, -6.0, -106.8)
const DAIS_RADIUS := 7.0

var checks := 0
var failures := 0
var level: Node
var found: Node
var space: PhysicsDirectSpaceState3D
var gs: Node


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


func in_box(p: Vector3, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> bool:
	return p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1 and p.z >= z0 and p.z <= z1


## Distance from `p` down to the first world surface below it (INF if none).
func drop_to_floor(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.25, p + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	return INF if hit.is_empty() else p.y - hit.position.y


func family_photos_in(node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in node.find_children("*", "Node3D", true, false):
		if n.scene_file_path == PHOTO and n.get("material") and n.material.resource_path == FAMILY_PHOTO:
			out.append(n)
	return out


func _run() -> void:
	level = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	for i in 20:
		await physics_frame
	space = level.get_viewport().world_3d.direct_space_state
	gs = root.get_node("GameState")
	found = level.get_node_or_null("FoundStory")
	check(found != null, "the level instances the found-story layer")
	if found == null:
		_finish()
		return

	# ------------------------------------------------------------ no words
	var wordy := 0
	for n in found.find_children("*", "", true, false):
		if n is Label3D or n is Control or n is Area3D:
			wordy += 1
		elif n.get_script() and n.get_script().resource_path.ends_with("interactable.gd"):
			wordy += 1
	check(wordy == 0, "the found layer adds no text, no trigger and no interactable")

	# ----------------------------------------------------------- recorders
	var triggers := {}
	for t in level.find_children("*", "Area3D", true, false):
		if t.get("trigger_id") != null:
			triggers[t.trigger_id] = t
	var moms: Array[String] = []
	for id in triggers:
		for line: String in triggers[id].lines:
			if line.begins_with("Mom:") and not moms.has(id):
				moms.append(id)
	check(moms.size() == 4, "four story triggers carry Mom's voice (found %d)" % moms.size())

	var recorders := get_nodes_in_group("story_recorder")
	for id in moms:
		var mine := recorders.filter(func(r): return r.trigger_id == id)
		check(mine.size() == 1, "exactly one recorder plays the '%s' recording" % id)
		if mine.size() != 1:
			continue
		var r: Node3D = mine[0]
		var t: Node3D = triggers[id]
		var flat := Vector2(r.global_position.x - t.global_position.x, r.global_position.z - t.global_position.z)
		check(flat.length() <= 9.0 and absf(r.global_position.y - t.global_position.y) < 2.5,
				"the '%s' recorder is in the room where it plays (%.1f m away)" % [id, flat.length()])
		check(drop_to_floor(r.global_position) < 0.08, "the '%s' recorder rests on a surface" % id)

	var last := recorders.filter(func(r): return r.dead)
	check(last.size() == 1 and in_box(last[0].global_position, 1.7, 27.7, -6.5, -3.0, -118.3, -92.3),
			"one dead recorder lies in the twin chamber")

	# A recording plays when its trigger fires: reels turn, a sound starts.
	var intro: Node3D = recorders.filter(func(r): return r.trigger_id == "intro")[0] if moms.has("intro") else null
	if intro:
		gs.flags.erase("seen_intro")
		intro.stop()
		var reel: Node3D = intro.get_node("ReelLeft")
		var before := reel.rotation
		for i in 10:
			await process_frame
		check(reel.rotation.is_equal_approx(before), "an idle recorder's reels stay still")
		gs.set_flag("seen_intro")
		await create_timer(0.3).timeout
		check(not reel.rotation.is_equal_approx(before), "the recorder's reels turn when Mom's line plays")
		check(intro.is_playing() and intro.get_node("Tape").playing, "the recorder runs its tape sound while it plays")
		var dead: Node3D = last[0] if last.size() == 1 else null
		if dead:
			var dead_reel: Node3D = dead.get_node("ReelLeft")
			var r0 := dead_reel.rotation
			dead.play()
			await create_timer(0.2).timeout
			check(dead_reel.rotation.is_equal_approx(r0) and not dead.is_playing(), "the dead recorder never runs")

	# ---------------------------------------------------- Dad's flashlight
	var torch := found.find_child("DadsFlashlight", true, false) as Node3D
	check(torch != null and in_box(torch.global_position, -1.3, 1.3, -6.2, 0.2, -62.6, -50.6),
			"Dad's flashlight lies on the lower stairs")
	if torch:
		var beam := torch.find_children("*", "SpotLight3D", true, false)
		check(beam.size() == 1 and beam[0].light_energy > 0.0, "the flashlight is still on")
		if beam.size() == 1:
			var aim: Vector3 = -beam[0].global_basis.z
			check(aim.y < -0.1 and aim.z < -0.5, "its beam points down the stairs, the way he went")
		# The stairs collide only on a smooth hidden ramp below the step noses,
		# so measure against the visible treads build_facility makes: 24 steps
		# of 0.5 m run and 0.25 m rise down from z = -50.6.
		var k := floori((-torch.global_position.z - 50.6) / 0.5)
		var gap := torch.global_position.y - (-0.25 * k)
		check(gap >= 0.0 and gap < 0.06, "the flashlight rests on a step (%.3f m above the tread)" % gap)

	# ------------------------------------------------------- twins' room
	var room_photos := family_photos_in(found).filter(func(p): return in_box(p.global_position, 3.5, 12.5, -6.2, -3.0, -75.7, -66.0))
	check(room_photos.size() == 1, "the family photograph is in the twins' room")
	var marks := found.find_child("GrowthMarks", true, false)
	check(marks != null and marks.get_child_count() == 12, "twelve growth marks, one per year")
	if marks and marks.get_child_count() == 12:
		var ok := true
		var prev := -INF
		for m: Node3D in marks.get_children():
			var p := m.global_position
			ok = ok and in_box(p, 3.4, 12.6, -5.5, -4.0, -75.8, -65.9) and p.y > prev
			prev = p.y
		check(ok, "the marks climb a wall of the twins' room, each above the last")

	# ------------------------------------------------------------ chamber
	var gurneys: Array[Node3D] = []
	for n in found.find_children("*", "Node3D", true, false):
		if n.scene_file_path == GURNEY:
			gurneys.append(n)
	var clear := gurneys.all(func(g):
		var d := Vector2(g.global_position.x - DAIS_CENTER.x, g.global_position.z - DAIS_CENTER.z).length()
		return in_box(g.global_position, 1.7, 27.7, -6.5, -5.0, -118.3, -92.3) and d > DAIS_RADIUS + 1.0)
	check(gurneys.size() == 2 and clear, "two covered bodies lie in the chamber, off the Twin's dais")
	var chamber_photos := family_photos_in(found).filter(func(p): return in_box(p.global_position, 1.7, 27.7, -6.5, -3.0, -118.3, -92.3))
	check(chamber_photos.size() == 1, "the family photograph is with them")

	# Only the gurneys collide: recorders, photos, marks and the torch are
	# scenery the player and enemies walk straight through.
	var bodies := found.find_children("*", "CollisionObject3D", true, false)
	check(bodies.all(func(b): return gurneys.any(func(g): return g.is_ancestor_of(b))),
			"nothing in the found layer collides except the two gurneys")

	_finish()


func _finish() -> void:
	if level:
		level.queue_free()
	await process_frame
	print("FOUND STORY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

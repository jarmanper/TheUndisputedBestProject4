extends SceneTree
## The browser build's render budget. The Compatibility renderer (the only one
## WebGL 2 runs) has no occlusion culling here, so without limits it processes
## the whole 120 m facility every frame: measured on Nov 4 at the spawn, 11,600
## draw calls, 5 M triangles and 116 ms a frame on an Apple laptop, from 141
## shadowed lights, 36 particle systems and 16 enemies of ~217k triangles.
## TimbukCompat.adapt() caps it by distance. Gameplay never reads any of this.
## Run on the browser's renderer:
##   godot --path . --rendering-method gl_compatibility --script tests/compat_budget.gd

const LIGHT_REACH := 25.0       # a light is gone by this distance from the camera
const CAMERA_FAR := 60.0
const PARTICLE_REACH := 25.0
const MARKING_RANGE := 15.0     # the longest targeting range (Team 3)
const SPAWN_DRAW_BUDGET := 3000

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


func _run() -> void:
	check(TimbukCompat.is_compatibility(), "running on the Compatibility renderer, as the browser does")
	var level: Node = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	for i in 30:
		await process_frame

	var lights := level.find_children("*", "Light3D", true, false)
	var positional := lights.filter(func(l): return not (l is DirectionalLight3D))
	check(positional.size() > 100, "the facility's lights are all there (%d)" % positional.size())
	check(positional.all(func(l): return not l.shadow_enabled), "no room light renders a shadow map")
	check(positional.all(func(l): return l.distance_fade_enabled and l.distance_fade_begin + l.distance_fade_length <= LIGHT_REACH),
			"every room light fades out within %d m of the camera" % LIGHT_REACH)
	var moons := lights.filter(func(l): return l is DirectionalLight3D)
	check(moons.all(func(d): return d.shadow_enabled and d.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL and d.directional_shadow_max_distance <= 30.0),
			"the moonlight keeps one cheap shadow pass, so it still cannot shine through ceilings")

	var player: TimbukPlayer = level.get_node("Player")
	check(player.camera.far <= CAMERA_FAR, "the player camera stops drawing at %d m (fog hides it)" % CAMERA_FAR)

	var particles := level.find_children("*", "GPUParticles3D", true, false)
	check(particles.all(func(p): return p.visibility_range_end > 0.0 and p.visibility_range_end <= PARTICLE_REACH),
			"all %d particle systems stop drawing beyond %d m" % [particles.size(), PARTICLE_REACH])

	var enemy_meshes: Array = []
	for e in get_nodes_in_group("enemy"):
		enemy_meshes.append_array(e.find_children("*", "GeometryInstance3D", true, false))
	check(not enemy_meshes.is_empty() and enemy_meshes.all(func(m): return m.visibility_range_end >= MARKING_RANGE * 2.0),
			"every enemy stays drawn to at least twice the longest ability range")
	check(enemy_meshes.all(func(m): return m.visibility_range_end > 0.0 and m.visibility_range_end <= 30.0),
			"enemies past 30 m are not drawn")

	# the spawn view, the worst one measured, is now inside the budget
	player.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_nodes_in_group("enemy"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
	player.camera.global_position = Vector3(0, 1.6, 3.0)
	player.camera.look_at(Vector3(0, 1.4, -5))
	for i in 20:
		await process_frame
	var draws := 0.0
	for i in 30:
		await process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	draws /= 30.0
	check(draws < SPAWN_DRAW_BUDGET, "the spawn view draws under %d calls (%d; was 11,600)" % [SPAWN_DRAW_BUDGET, int(draws)])

	level.queue_free()
	await process_frame
	print("COMPAT BUDGET: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

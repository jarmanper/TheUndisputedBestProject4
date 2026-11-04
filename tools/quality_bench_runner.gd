extends Node
## Helper for tools/quality_bench.gd (needs to be a Node so it can await frames).

var scene_path := ""
var wanted: Array = []
var shots := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/captures")
	print("GPU: ", RenderingServer.get_video_adapter_name())
	var scene: Node = load(scene_path).instantiate()
	add_child(scene)
	for other in scene.find_children("*", "Camera3D", true, false):
		other.current = false
		other.process_mode = Node.PROCESS_MODE_DISABLED
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var cam := Camera3D.new()
	cam.fov = 70
	cam.far = 300
	add_child(cam)
	cam.current = true
	var views := scene.find_children("VIEW__*", "Node3D", true, false)
	views.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	for level in 3:
		# UiSettings walks the WorldEnvironment of tree.current_scene; our scene is
		# parented under this runner, so drive the same code path by hand.
		UiSettings.apply_quality(get_tree(), level)
		for we in scene.find_children("*", "WorldEnvironment", true, false):
			var env: Environment = we.environment
			if env:
				env.volumetric_fog_enabled = level > UiSettings.Quality.LOW
				env.ssil_enabled = level > UiSettings.Quality.LOW
				env.ssr_enabled = level > UiSettings.Quality.LOW
		for n in get_tree().get_nodes_in_group("game_grade"):
			if n.has_method("set_quality"):
				n.set_quality(level)
		for v in views:
			var vname := String(v.name).trim_prefix("VIEW__")
			if not wanted.is_empty() and not wanted.has(vname):
				continue
			cam.global_transform = v.global_transform
			for i in 60:
				await get_tree().process_frame
			if shots:
				get_viewport().get_texture().get_image().save_png(
					"res://.godot/captures/%s_q%d.png" % [vname, level])
			var gpu := 0.0
			for i in 30:
				await get_tree().process_frame
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			print("q%d %-18s GPU %.2f ms" % [level, vname, gpu / 30.0])
	get_tree().quit()

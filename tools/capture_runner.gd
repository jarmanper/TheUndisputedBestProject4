extends Node
## Helper for tools/capture.gd (needs to be a Node so it can await frames).

var scene_path := ""
var wanted: Array = []
## If > 0: re-trigger every effect (vfx_player.play) this many seconds before each shot.
var fx_delay := 0.0
## Seconds to let the scene run (animations, sequences) before the first shot.
var wait := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/captures")
	print("GPU: ", RenderingServer.get_video_adapter_name(), " / ", RenderingServer.get_video_adapter_api_version())
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
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	var views := scene.find_children("VIEW__*", "Node3D", true, false)
	views.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for v in views:
		var vname := String(v.name).trim_prefix("VIEW__")
		if not wanted.is_empty() and not wanted.has(vname):
			continue
		cam.global_transform = v.global_transform
		for i in 45:   # let SSAO/SSIL/volumetric fog/probes settle
			await get_tree().process_frame
		if fx_delay > 0.0:
			for n in scene.find_children("*", "Node3D", true, false):
				if n.has_method("play") and n.get("loop") != null:
					n.set("loop", false)
					n.play()
			await get_tree().create_timer(fx_delay).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://.godot/captures/%s.png" % vname)
		var vp_rid := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
		var t0 := Time.get_ticks_usec()
		var gpu := 0.0
		for i in 20:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		var ms := (Time.get_ticks_usec() - t0) / 20000.0
		print("captured %s  GPU %.1f ms (frame %.1f ms, window may be throttled)" % [vname, gpu / 20.0, ms])
	get_tree().quit()

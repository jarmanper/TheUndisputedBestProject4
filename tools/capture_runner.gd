extends Node
## Helper for tools/capture.gd (needs to be a Node so it can await frames).

var scene_path := ""
var wanted: Array = []


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
	var views := scene.find_children("VIEW__*", "Node3D", true, false)
	views.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for v in views:
		var vname := String(v.name).trim_prefix("VIEW__")
		if not wanted.is_empty() and not wanted.has(vname):
			continue
		cam.global_transform = v.global_transform
		for i in 45:   # let SSAO/SSIL/volumetric fog/probes settle
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://.godot/captures/%s.png" % vname)
		var t0 := Time.get_ticks_usec()
		for i in 20:
			await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - t0) / 20000.0
		print("captured %s  %.1f ms/frame (%.0f fps)" % [vname, ms, 1000.0 / ms])
	get_tree().quit()

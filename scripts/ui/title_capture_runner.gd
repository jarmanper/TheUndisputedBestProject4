extends Node
## Helper for scripts/ui/title_capture.gd. Loads the title screen, lets it run,
## and saves a PNG at each requested time (seconds since load).

var times: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/captures")
	print("GPU: ", RenderingServer.get_video_adapter_name())
	var args: Array = []
	var only_menu := false
	var click: Array = []
	for a in times:
		var s := String(a)
		if s.begins_with("--click="):
			click.append(s.trim_prefix("--click="))
		else:
			args.append(float(s))
	if args.is_empty():
		args = [1.0, 3.0, 6.0, 10.0]
	var scene: Node = load("res://scenes/ui/title_screen.tscn").instantiate()
	add_child(scene)
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var elapsed := 0.0
	for t: float in args:
		var wait: float = maxf(t - elapsed, 0.05)
		await get_tree().create_timer(wait).timeout
		elapsed = t
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://.godot/captures/title_%.1f.png" % t)
		var gpu := 0.0
		for i in 20:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		print("captured title_%.1f  GPU %.2f ms" % [t, gpu / 20.0])
	# Optional: click named buttons (unique names) and shoot the result.
	for name_str: String in click:
		var btn := scene.find_child(name_str, true, false)
		if btn is BaseButton:
			(btn as BaseButton).emit_signal("pressed")
			await get_tree().create_timer(0.8).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					"res://.godot/captures/title_click_%s.png" % name_str)
			print("captured title_click_%s" % name_str)
		else:
			push_warning("no button named %s" % name_str)
	get_tree().quit()

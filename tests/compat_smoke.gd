extends SceneTree
## Runs the real game scene on the renderer the browser will use, so fog or
## environment features the web build cannot compile fail here, on a desktop,
## instead of in a grader's browser. Needs a window - not --headless:
##   godot --path . --rendering-method gl_compatibility --script tests/compat_smoke.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("compat_smoke: renderer has RenderingDevice = ", RenderingServer.get_rendering_device() != null)
	print("compat_smoke: is_compatibility = ", TimbukCompat.is_compatibility())
	var scene: Node = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(scene)
	var player := scene.get_node_or_null("Player")
	print("compat_smoke: player found = ", player != null)
	var enemies: int = scene.get_node("Enemies").get_child_count()
	print("compat_smoke: enemies staged = ", enemies)
	# let it actually draw a few seconds of frames
	for i in 180:
		await process_frame
	var remaining_fog: int = scene.find_children("*", "FogVolume", true, false).size()
	print("compat_smoke: fog volumes left in tree = ", remaining_fog)
	print("compat_smoke: survived 180 rendered frames")
	quit(0)

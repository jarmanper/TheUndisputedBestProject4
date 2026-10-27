extends SceneTree
## Render screenshots from VIEW__ markers inside the real Godot renderer.
## Run (needs a window, not --headless):
##   tools/godot.sh --resolution 1280x720 --script res://tools/capture.gd -- <scene> [view ...]
## Images go to res://.godot/captures/<view>.png

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://scenes/environments/timbuk_facility.tscn"
	var runner := Node.new()
	runner.set_script(load("res://tools/capture_runner.gd"))
	var wanted := []
	var fx_delay := 0.0
	for a in args.slice(1):
		if a.begins_with("--fx-delay="):
			fx_delay = float(a.trim_prefix("--fx-delay="))
		elif a.begins_with("--wait="):
			runner.set("wait", float(a.trim_prefix("--wait=")))
		else:
			wanted.append(a)
	runner.set("scene_path", scene_path)
	runner.set("wanted", wanted)
	runner.set("fx_delay", fx_delay)
	root.add_child.call_deferred(runner)

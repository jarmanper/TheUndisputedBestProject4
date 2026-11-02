extends SceneTree
## Measures GPU ms (and optionally screenshots) at every quality preset.
## Needs a window, not --headless:
##   tools/godot.sh --resolution 1600x900 --script res://tools/quality_bench.gd -- <scene> [view ...]
## Add --shots to also write res://.godot/captures/<view>_q<level>.png
## Companion to tools/capture.gd, which only measures the project defaults.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://scenes/environments/timbuk_facility.tscn"
	var runner := Node.new()
	runner.set_script(load("res://tools/quality_bench_runner.gd"))
	var wanted := []
	var shots := false
	for a in args.slice(1):
		if a == "--shots":
			shots = true
		else:
			wanted.append(a)
	runner.set("scene_path", scene_path)
	runner.set("wanted", wanted)
	runner.set("shots", shots)
	root.add_child.call_deferred(runner)

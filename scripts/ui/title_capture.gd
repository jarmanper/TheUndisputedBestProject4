extends SceneTree
## Screenshot helper for the title screen (needs a real window, not --headless).
##   tools/godot.sh --resolution 1600x900 --script res://scripts/ui/title_capture.gd -- 1 3 6 10
## Saves res://.godot/captures/title_<seconds>.png for each time given.

func _init() -> void:
	var runner := Node.new()
	runner.set_script(load("res://scripts/ui/title_capture_runner.gd"))
	runner.set("times", OS.get_cmdline_user_args())
	root.add_child.call_deferred(runner)

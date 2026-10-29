extends SceneTree
var loaded := 0
var failures := 0

func _initialize() -> void:
	_scan("res://scripts")
	print("SCRIPT RESOURCE AUDIT: %d scripts loaded, %d failures" % [loaded, failures])
	quit(0 if failures == 0 else 1)

func _scan(path: String) -> void:
	var directory := DirAccess.open(path)
	for file in directory.get_files():
		if file.ends_with(".gd"):
			var script := load(path.path_join(file)) as GDScript
			if script == null or not script.can_instantiate():
				failures += 1
				push_error("Cannot compile " + path.path_join(file))
			loaded += 1
	for child in directory.get_directories():
		_scan(path.path_join(child))

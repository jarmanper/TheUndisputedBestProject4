extends SceneTree
## Loads every gameplay/UI script and scene so a typo cannot reach a playtest.

func _initialize() -> void:
	var failures := 0
	var checked := 0
	var dirs: Array[String] = ["res://scripts", "res://scenes/game", "res://scenes/ui"]
	var queue := dirs.duplicate()
	while not queue.is_empty():
		var dir: String = queue.pop_front()
		for sub in DirAccess.get_directories_at(dir):
			queue.append(dir.path_join(sub))
		for f in DirAccess.get_files_at(dir):
			if not (f.ends_with(".gd") or f.ends_with(".tscn")):
				continue
			var path := dir.path_join(f)
			checked += 1
			if f.ends_with(".gd"):
				# reload() re-parses and returns the real error, which a plain
				# load() hides behind a cached resource
				var sc := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
				# An autoload's script cannot be reloaded while its instance
				# lives, so fall back to can_instantiate(), which a script with
				# a parse error always fails.
				if sc == null or (sc.reload() != OK and not sc.can_instantiate()):
					failures += 1
					printerr("FAIL: parse error in " + path)
				continue
			if ResourceLoader.load(path) == null:
				failures += 1
				printerr("FAIL: could not load " + path)
	print("VALIDATE RESOURCES: %d loaded, %d failures" % [checked, failures])
	quit(0 if failures == 0 else 1)

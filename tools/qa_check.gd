extends SceneTree
## Visual QA: loads every scene under res://scenes and reports
## - meshes using materials that are not from the shared library
## - surfaces with no material at all
## - triangle counts, light counts and shadow-casting lights per scene
## Run: tools/godot.sh script res://tools/qa_check.gd

var issues := 0


func _init() -> void:
	var files := []
	_collect("res://scenes", files)
	files.sort()
	for f in files:
		_check(f)
	print("QA done: %d scenes, %d issues" % [files.size(), issues])
	quit()


func _collect(dir: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir + "/" + f)


func _check(path: String) -> void:
	var root: Node = load(path).instantiate()
	var tris := 0
	var lights := 0
	var shadows := 0
	var bad := {}
	for n in root.find_children("*", "", true, false):
		if n is MeshInstance3D and n.mesh:
			for i in n.mesh.get_surface_count():
				var arr = n.mesh.surface_get_arrays(i)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				var m: Material = n.get_active_material(i)
				if m == null:
					bad["(no material) " + String(n.name)] = true
				elif m is StandardMaterial3D and m.resource_path.contains(".glb::"):
					bad["(embedded) %s on %s" % [m.resource_name, n.name]] = true
		elif n is Light3D:
			lights += 1
			if n.shadow_enabled:
				shadows += 1
	print("%-58s tris %8d  lights %3d  shadowed %2d" % [path.trim_prefix("res://scenes/"), tris, lights, shadows])
	for k in bad:
		print("    ISSUE: ", k)
		issues += 1
	root.free()

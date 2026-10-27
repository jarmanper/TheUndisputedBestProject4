extends SceneTree
## Print the node tree of a scene with mesh materials and collision shapes.
## Run: tools/godot.sh script res://tools/inspect_scene.gd -- res://path.tscn
func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var root: Node = load(path).instantiate()
	_walk(root, 0)
	quit()

func _walk(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + "%s (%s)" % [n.name, n.get_class()]
	if n is MeshInstance3D and n.mesh:
		var mats := []
		for i in n.mesh.get_surface_count():
			var m: Material = n.get_active_material(i)
			mats.append(m.resource_path.get_file() if m and m.resource_path else str(m))
		line += " mats=%s aabb=%s" % [mats, n.mesh.get_aabb().size]
	elif n is CollisionShape3D and n.shape:
		line += " shape=%s" % n.shape.get_class()
	print(line)
	if depth < 6:
		for c in n.get_children():
			_walk(c, depth + 1)

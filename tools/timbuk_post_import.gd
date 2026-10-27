@tool
extends EditorScenePostImport
## Runs after Godot imports one of our Blender GLBs.
## Blender exports placeholder materials named after entries in
## source/materials.json (e.g. "concrete", "brass.001"); here each one is
## swapped for the real res://assets/materials/<name>.tres so every model
## shares the same tuned materials.


func _post_import(scene: Node) -> Object:
	_remap(scene)
	return scene


func _remap(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var old := mesh.surface_get_material(i)
			if old == null:
				continue
			var key := old.resource_name.get_slice(".", 0)
			var path := "res://assets/materials/%s.tres" % key
			if ResourceLoader.exists(path):
				mesh.surface_set_material(i, load(path))
			else:
				push_warning("TIMBUK import: no material for '%s' in %s" % [key, get_source_file()])
	for child in node.get_children():
		_remap(child)

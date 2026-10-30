extends Node3D
## Re-skins one surface of an instanced prop without touching the generated prop
## scene or the Blender generator.
##
## Props from `scenes/props/` are a single merged MeshInstance3D with one surface
## per material (see tools/inspect_scene.gd). Attaching this script to an
## instanced prop root and setting `surface` + `material` swaps that surface only,
## so the same prop can be re-used to mean something different in the story.
##
## Example: `locker_row` ships with a blood-soaked coat on surface 3. Retinting
## surface 3 to `labcoat.tres` turns it into a clean lab coat left hanging.

## Indices of the surfaces to replace, as printed by tools/inspect_scene.gd.
@export var surfaces: PackedInt32Array = PackedInt32Array()

## Material to put on those surfaces. Null leaves the prop untouched.
@export var material: Material


func _ready() -> void:
	if material == null or surfaces.is_empty():
		return
	var mesh_instance := _first_mesh(self)
	if mesh_instance == null:
		push_warning("prop_retint: no MeshInstance3D under %s" % name)
		return
	if mesh_instance.mesh == null:
		return
	var count := mesh_instance.mesh.get_surface_count()
	for surface in surfaces:
		if surface < 0 or surface >= count:
			push_warning("prop_retint: %s has no surface %d" % [name, surface])
			continue
		mesh_instance.set_surface_override_material(surface, material)


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null

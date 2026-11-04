extends SceneTree
## Physics check for the wall-mounted detail added by source/blender/build_facility.py.
##
## Every pilaster, cornice, conduit, junction box and vent is built as DETAIL
## (structural=False), so it must carry no collision at all. The walls are a
## concave trimesh, so a shape query fully inside a solid reports nothing --
## this raycasts at the detail instead and checks WHERE the ray stops. A ray
## aimed at a pilaster must stop at the bare wall plane behind it, not 9 cm
## early on the pilaster's own face.
##   tools/godot.sh script res://tools/collision_probe.gd
##
## Points are Godot-space (Blender x,y,z -> x, z, -y).

# [label, ray origin, ray end, expected hit coordinate, axis index, detail face]
const RAYS := [
	["lobby pilaster  north wall x=-7.2", Vector3(-7.2, 2.00, -3.0), Vector3(-7.2, 2.00, -6.6), -6.0, 2, -5.91],
	["lobby pilaster  x=-8 y=-3.6",   Vector3(-4.0, 2.00, 3.6),    Vector3(-8.6, 2.00, 3.6),    -8.0, 0, -7.91],
	["lobby pilaster  x=+8 y=0",      Vector3(4.0, 2.00, 0.0),     Vector3(8.6, 2.00, 0.0),     8.0, 0, 7.91],
	["lobby conduit   x=-8 z=-2",     Vector3(-4.0, 4.16, -2.0),   Vector3(-8.6, 4.16, -2.0),   -8.0, 0, -7.915],
	["lobby cornice   x=-8 z=2",      Vector3(-4.0, 4.43, 2.0),    Vector3(-8.6, 4.43, 2.0),    -8.0, 0, -7.89],
	["corridor pilaster x=-1.5 z=-10.8", Vector3(0.0, 1.60, -10.8), Vector3(-2.2, 1.60, -10.8), -1.5, 0, -1.41],
	["corridor pilaster x=+1.5 z=-14.4", Vector3(0.0, 1.60, -14.4), Vector3(2.2, 1.60, -14.4),  1.5, 0, 1.41],
	["corridor jbox     x=-1.5 z=-10.8", Vector3(0.0, 1.95, -10.8), Vector3(-2.2, 1.95, -10.8), -1.5, 0, -1.38],
]


func _init() -> void:
	var scene: Node = load("res://scenes/environments/timbuk_facility.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var space := root.world_3d.direct_space_state
	var bad := 0
	for r in RAYS:
		var q := PhysicsRayQueryParameters3D.create(r[1], r[2])
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("%-36s NO HIT -- probe aimed at nothing, result meaningless" % r[0])
			bad += 1
			continue
		var axis: int = r[4]
		var got: float = (hit["position"] as Vector3)[axis]
		var wall: float = r[3]
		var face: float = r[5]
		var on_detail := absf(got - face) < absf(got - wall)
		print("%-36s stops at %.3f (bare wall %.2f, detail face %.2f) -> %s"
			% [r[0], got, wall, face, "DETAIL HAS COLLISION" if on_detail else "wall only, detail is collision-free"])
		if on_detail:
			bad += 1
	print("collision probe: %d problem(s)" % bad)
	quit()

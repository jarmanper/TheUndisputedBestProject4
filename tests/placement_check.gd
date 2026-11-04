extends SceneTree
## Every added enemy has to stand in an open room, not inside a wall and not
## over a hole. Checks each required target for floor beneath it and for world
## geometry overlapping where its body will be.
##   godot --path . --script tests/placement_check.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await physics_frame
	var space := scene.get_viewport().world_3d.direct_space_state
	var bad := 0
	var targets := get_nodes_in_group("enemy")
	for e in targets:
		var at: Vector3 = e.global_position
		# floor within 4 m below?
		var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 4.0, 1)
		down.exclude = [e.get_rid()]
		var floor_hit := space.intersect_ray(down)
		# is the chest volume clear of geometry?
		var q := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.28
		shape.height = 1.4
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
		q.collision_mask = 1
		q.exclude = [e.get_rid()]
		var stuck := space.intersect_shape(q, 1)
		var ok := not floor_hit.is_empty() and stuck.is_empty()
		if not ok:
			bad += 1
			printerr("FAIL: %s at %v - floor=%s stuck=%s" % [e.name, at, not floor_hit.is_empty(), not stuck.is_empty()])
		else:
			print("PASS: %s stands clear" % e.name)
	print("PLACEMENT: %d targets, %d bad" % [targets.size(), bad])
	quit(0 if bad == 0 else 1)

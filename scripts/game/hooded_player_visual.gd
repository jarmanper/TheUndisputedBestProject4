extends Node3D
## Cosmetic character only. The player's existing capsule owns all collision.
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var stride := 0.0
var blend := 0.0
# Visual durations only; Explosion applies damage before it emits detonated.
const EXTEND_TIME := 0.10
const HOLD_TIME := 0.12
const LOWER_TIME := 0.23
var explosion_pose_elapsed := -1.0

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func part(parent: Node3D, label: String, mesh: Mesh, at: Vector3, surface: Material, size := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = surface
	instance.position = at
	instance.scale = size
	parent.add_child(instance)
	return instance

func rounded(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	return mesh

func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _ready() -> void:
	var cloth := material(Color("303b45"))
	var seams := material(Color("475561"))
	var pants := material(Color("20252e"))
	var leather := material(Color("11161d"))
	var skin := material(Color("9c7056"))
	var shadow := material(Color("302522"))
	# Broad shoulders, a tapered sweatshirt, ribbed hem and front pouch.
	part(self, "Sweatshirt", rounded(0.24, 0.65), Vector3(0, 1.13, 0), cloth, Vector3(1.12, 1, 0.72))
	var hem := CylinderMesh.new()
	hem.top_radius = 0.23
	hem.bottom_radius = 0.23
	hem.height = 0.10
	hem.radial_segments = 12
	part(self, "Hem", hem, Vector3(0, 0.87, 0), seams, Vector3(1, 1, 0.72))
	part(self, "Pouch", box(Vector3(0.29, 0.13, 0.045)), Vector3(0, 1.01, -0.174), seams)
	part(self, "Neck", rounded(0.075, 0.16), Vector3(0, 1.43, -0.015), skin)
	part(self, "Head", rounded(0.125, 0.3), Vector3(0, 1.59, -0.04), skin, Vector3(0.92, 1, 0.9))
	part(self, "Beard", rounded(0.116, 0.232), Vector3(0, 1.49, -0.065), shadow, Vector3(1, 0.56, 0.88))
	part(self, "Nose", rounded(0.027, 0.075), Vector3(0, 1.57, -0.157), skin)
	for side in [-1.0, 1.0]:
		part(self, "Eye", box(Vector3(0.033, 0.014, 0.009)), Vector3(side * 0.047, 1.625, -0.145), leather)
		var cord := part(self, "HoodCord", rounded(0.009, 0.21), Vector3(side * 0.085, 1.31, -0.179), seams)
		cord.rotation.z = side * 0.09
	_build_hood(cloth, seams)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegLeft" if side < 0 else "LegRight"
		leg.position = Vector3(side * 0.125, 0.86, 0)
		add_child(leg)
		legs.append(leg)
		part(leg, "TrouserLeg", rounded(0.102, 0.73), Vector3(0, -0.35, 0), pants, Vector3(1, 1, 0.92))
		part(leg, "Boot", rounded(0.11, 0.28), Vector3(0, -0.76, -0.055), leather, Vector3(0.92, 0.64, 1.5))
		part(leg, "Sole", box(Vector3(0.2, 0.045, 0.31)), Vector3(0, -0.835, -0.055), pants)
		var arm := Node3D.new()
		arm.name = "ArmLeft" if side < 0 else "ArmRight"
		arm.position = Vector3(side * 0.285, 1.36, 0)
		arm.rotation.z = side * 0.09
		add_child(arm)
		arms.append(arm)
		part(arm, "Sleeve", rounded(0.094, 0.49), Vector3(0, -0.19, 0), cloth)
		part(arm, "Cuff", rounded(0.078, 0.09), Vector3(0, -0.42, 0), seams)
		part(arm, "Hand", rounded(0.065, 0.16), Vector3(0, -0.51, -0.005), skin, Vector3(0.85, 1, 0.8))

	get_parent().get_node("Explosion").detonated.connect(_on_detonated)

func _on_detonated(_origin: Vector3, _hits: int) -> void:
	# No gameplay calls, awaits, movement locks or animation-completion callbacks.
	explosion_pose_elapsed = 0.0

func _explosion_weight(delta: float) -> float:
	if explosion_pose_elapsed < 0:
		return 0.0
	explosion_pose_elapsed += delta
	if explosion_pose_elapsed < EXTEND_TIME:
		return smoothstep(0.0, EXTEND_TIME, explosion_pose_elapsed)
	if explosion_pose_elapsed < EXTEND_TIME + HOLD_TIME:
		return 1.0
	if explosion_pose_elapsed < EXTEND_TIME + HOLD_TIME + LOWER_TIME - 0.000001:
		return 1.0 - smoothstep(0.0, LOWER_TIME, explosion_pose_elapsed - EXTEND_TIME - HOLD_TIME)
	explosion_pose_elapsed = -1.0
	return 0.0

func _build_hood(cloth: Material, trim: Material) -> void:
	# An open-front shell, rather than a solid sphere over the face.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := [Vector3(0.10, 1.40, 0.13), Vector3(0.21, 1.48, 0.20), Vector3(0.22, 1.66, 0.22), Vector3(0.16, 1.77, 0.17), Vector3(0.01, 1.81, 0.01)]
	var rows: Array[PackedVector3Array] = []
	for level in levels:
		var row := PackedVector3Array()
		for i in 17:
			var angle := lerpf(0.72, TAU - 0.72, float(i) / 16.0)
			row.append(Vector3(sin(angle) * level.x, level.y, -cos(angle) * level.z + 0.025))
		rows.append(row)
	for j in levels.size() - 1:
		for i in 16:
			for vertex in [rows[j][i], rows[j + 1][i], rows[j][i + 1], rows[j][i + 1], rows[j + 1][i], rows[j + 1][i + 1]]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	var hood_material := cloth.duplicate() as StandardMaterial3D
	hood_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	part(self, "Hood", surface.commit(), Vector3.ZERO, hood_material)
	# Raised rim follows the opening on each side of the face.
	for edge in [0, 16]:
		for j in levels.size() - 1:
			var a := rows[j][edge]
			var b := rows[j + 1][edge]
			var rim := part(self, "HoodRim", rounded(0.019, a.distance_to(b) + 0.025), (a + b) * 0.5, trim)
			rim.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func _process(delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null:
		return
	var moving := Vector2(player.velocity.x, player.velocity.z).length() / 4.0
	blend = move_toward(blend, clampf(moving, 0, 1), delta * 6)
	stride += delta * 9 * clampf(moving, 0, 1)
	var explosion_weight := _explosion_weight(delta)
	for i in legs.size():
		var swing := sin(stride + i * PI) * blend
		legs[i].rotation.x = swing * 0.48
		arms[i].rotation.x = -swing * 0.32
		if i == 1:
			# Blend the right arm toward a forward, open-hand detonation gesture.
			arms[i].rotation.x = lerpf(arms[i].rotation.x, PI * 0.5, explosion_weight)
			arms[i].rotation.z = lerpf(0.09, -0.12, explosion_weight)
	position.y = absf(sin(stride)) * blend * 0.025

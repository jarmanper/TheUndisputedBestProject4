extends RigidBody3D
## The thrown charge for the Explosion mechanic. Blinks faster and faster,
## then detonates after `fuse` seconds or when it touches an enemy.

const CLINK_SFX := preload("res://assets/audio/sfx/impact_concrete.wav")

var fuse := 2.0
var owner_mechanic: Node
var _light: OmniLight3D
var _clink: AudioStreamPlayer3D
var _clink_cd := 0.0
var _t := 0.0
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	mass = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.8
	physics_material_override = pm
	angular_damp = 2.0
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.12
	shape.shape = sph
	add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mi.mesh = mesh
	if ResourceLoader.exists("res://assets/materials/hazard.tres"):
		mi.material_override = load("res://assets/materials/hazard.tres")
	add_child(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.3, 0.1)
	_light.omni_range = 2.0
	add_child(_light)
	_clink = AudioStreamPlayer3D.new()
	_clink.stream = CLINK_SFX
	_clink.bus = "SFX"
	_clink.max_distance = 25.0
	add_child(_clink)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	_clink_cd = maxf(0.0, _clink_cd - delta)
	_light.light_energy = 2.5 if fmod(_t * (2.0 + _t * 4.0), 1.0) < 0.5 else 0.0
	if _t >= fuse or global_position.y < -40.0:
		_boom()


func _on_body(b: Node) -> void:
	var n := b
	while n:
		if n.is_in_group("enemy"):
			_boom()
			return
		n = n.get_parent()
	# bounced off the world
	var spd := linear_velocity.length()
	if _clink_cd <= 0.0 and spd > 1.0:
		_clink_cd = 0.12
		_clink.pitch_scale = randf_range(1.6, 2.0)
		_clink.volume_db = linear_to_db(clampf(spd / 10.0, 0.1, 1.0)) - 8.0
		_clink.play()


func _boom() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(owner_mechanic) and owner_mechanic.is_inside_tree():
		owner_mechanic.detonate(global_position)
	queue_free()

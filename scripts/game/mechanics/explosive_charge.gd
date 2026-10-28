extends RigidBody3D
## The thrown charge for the Explosion mechanic. Blinks, then detonates
## after `fuse` seconds or when it touches an enemy.

var fuse := 2.0
var owner_mechanic: Node
var _light: OmniLight3D
var _t := 0.0
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	mass = 0.6
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
	mi.material_override = load("res://assets/materials/hazard.tres")
	add_child(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.3, 0.1)
	_light.omni_range = 2.0
	add_child(_light)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = 2.0 if fmod(_t * (2.0 + _t * 4.0), 1.0) < 0.5 else 0.0
	if _t >= fuse:
		_boom()


func _on_body(b: Node) -> void:
	if b.is_in_group("enemy"):
		_boom()


func _boom() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(owner_mechanic):
		owner_mechanic.detonate(global_position)
	queue_free()

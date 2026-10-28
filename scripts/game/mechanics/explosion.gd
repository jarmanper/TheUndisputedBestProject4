extends Node
## EXPLOSION (Daniel): F throws a charge that blows after `fuse` seconds or
## on hitting an enemy. Radial damage with falloff + knockback. Marked
## enemies caught in the blast chain-detonate a smaller green explosion.
## `max_charges` charges, each recharges in `recharge_time` seconds.

const Charge := preload("res://scripts/game/mechanics/explosive_charge.gd")

@export var max_charges := 3
@export var recharge_time := 12.0
@export var throw_speed := 12.0
@export var fuse := 2.0
@export var damage := 60.0
@export var radius := 5.0
@export var knockback := 8.0
@export var chain_damage := 30.0
@export var chain_radius := 3.0

var charges := 3
var _recharge := 0.0

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	charges = max_charges


func _process(delta: float) -> void:
	if charges < max_charges:
		_recharge += delta
		if _recharge >= recharge_time:
			_recharge = 0.0
			charges += 1
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("explode") and charges > 0:
		throw()


func throw() -> void:
	charges -= 1
	var c := Charge.new()
	c.fuse = fuse
	c.owner_mechanic = self
	c.add_collision_exception_with(player)
	get_tree().current_scene.add_child(c)
	var cam := player.camera
	var fwd := -cam.global_transform.basis.z
	c.global_position = cam.global_position + fwd * 0.6
	c.linear_velocity = fwd * throw_speed + Vector3.UP * 2.0 + player.velocity * 0.5


func recharge_fraction() -> float:
	return _recharge / recharge_time


## Blast at `where`. `chain` explosions are smaller and green.
func detonate(where: Vector3, chain := false) -> void:
	var r := chain_radius if chain else radius
	var dmg := chain_damage if chain else damage
	var fx := "res://scenes/effects/explosion_green.tscn" if chain else "res://scenes/effects/explosion_orange.tscn"
	TimbukFx.spawn(get_tree(), fx, where)
	_scorch(where)
	player.make_noise(30.0)
	# player is hurt by their own blast too (half)
	var pd := player.global_position.distance_to(where)
	if pd < r:
		player.damage(dmg * 0.5 * (1.0 - pd / r))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.is_dead():
			continue
		var d: float = e.global_position.distance_to(where)
		if d > r:
			continue
		var was_marked: bool = e.is_marked()
		var push: Vector3 = (e.global_position - where)
		push.y = 0.0
		e.apply_knockback(push.normalized() * knockback * (1.0 - d / r) + Vector3.UP * 3.0)
		e.damage(dmg * (1.0 - d / r * 0.7))
		if was_marked and is_instance_valid(e):
			e.unmark()
			var p: Vector3 = e.global_position + Vector3.UP
			get_tree().create_timer(0.25).timeout.connect(detonate.bind(p, true))


func _scorch(where: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(where + Vector3.UP * 0.5, where + Vector3.DOWN * 3.0, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var s := TimbukFx.spawn(get_tree(), "res://scenes/effects/scorch_mark.tscn", hit.position + hit.normal * 0.02, false, TimbukFx.basis_from_normal(hit.normal))
	if s:
		get_tree().create_timer(45.0).timeout.connect(s.queue_free)

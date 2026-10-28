extends Node
## EXPLOSION (Daniel): F throws a charge that blows after `fuse` seconds or
## on hitting an enemy. Radial damage with falloff + knockback (walls block
## most of it). Marked enemies caught in the blast chain-detonate a smaller
## green explosion. `max_charges` charges, each recharges in `recharge_time`.

signal detonated(where: Vector3, chain: bool)

const Charge := preload("res://scripts/game/mechanics/explosive_charge.gd")

@export var max_charges := 3
@export var recharge_time := 12.0
@export var throw_speed := 12.0
@export var throw_cooldown := 0.35
@export var fuse := 2.0
@export var damage := 60.0
@export var radius := 5.0
@export var knockback := 8.0
@export var chain_damage := 30.0
@export var chain_radius := 3.0
@export var cover_factor := 0.3  ## damage multiplier when a wall is between blast and target
@export var shake_range := 18.0  ## camera shake reaches this far

var charges := 3
var _recharge := 0.0
var _throw_cd := 0.0

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	charges = max_charges


func _process(delta: float) -> void:
	_throw_cd = maxf(0.0, _throw_cd - delta)
	if charges < max_charges:
		_recharge += delta
		if _recharge >= recharge_time:
			_recharge = 0.0
			charges += 1
	else:
		_recharge = 0.0
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("explode") and charges > 0 and _throw_cd <= 0.0:
		throw()


func throw() -> void:
	if charges <= 0:
		return
	charges -= 1
	_throw_cd = throw_cooldown
	var c := Charge.new()
	c.fuse = fuse
	c.owner_mechanic = self
	c.add_collision_exception_with(player)
	var cam := player.camera
	var fwd := -cam.global_transform.basis.z
	var start := cam.global_position + fwd * 0.6
	# don't spawn inside a wall when standing right against it
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, start + fwd * 0.15, 1)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		start = hit.position - fwd * 0.2
	var parent: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	parent.add_child(c)
	c.global_position = start
	c.linear_velocity = fwd * throw_speed + Vector3.UP * 2.0 + player.velocity * 0.5
	c.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


func recharge_fraction() -> float:
	if charges >= max_charges or recharge_time <= 0.0:
		return 1.0
	return clampf(_recharge / recharge_time, 0.0, 1.0)


## Blast at `where`. `chain` explosions are smaller and green.
func detonate(where: Vector3, chain := false) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var r := chain_radius if chain else radius
	var dmg := chain_damage if chain else damage
	var fx := "res://scenes/effects/explosion_green.tscn" if chain else "res://scenes/effects/explosion_orange.tscn"
	TimbukFx.spawn(tree, fx, where)
	_scorch(where)
	player.make_noise(30.0)
	detonated.emit(where, chain)

	# camera shake for everyone in earshot, player hurt by own blast (half)
	var pd := player.global_position.distance_to(where)
	if player.has_method("add_trauma") and pd < shake_range:
		player.add_trauma((0.45 if chain else 0.75) * (1.0 - pd / shake_range))
	if pd < r and not player.dead:
		var f := 1.0 - pd / r
		if not _clear(where, player.global_position + Vector3.UP):
			f *= cover_factor
		player.damage(dmg * 0.5 * f)
		var away := player.global_position - where
		away.y = 0.0
		player.velocity += away.normalized() * knockback * 0.4 * f

	for e in tree.get_nodes_in_group("enemy"):
		if not (e is Node3D) or (e.has_method("is_dead") and e.is_dead()):
			continue
		var d: float = e.global_position.distance_to(where)
		if d > r:
			continue
		var f := 1.0 - d / r
		if not _clear(where, e.global_position + Vector3.UP):
			f *= cover_factor
		var was_marked: bool = e.has_method("is_marked") and e.is_marked()
		var push: Vector3 = e.global_position - where
		push.y = 0.0
		if e.has_method("apply_knockback"):
			e.apply_knockback(push.normalized() * knockback * f + Vector3.UP * 3.0 * f)
		if e.has_method("damage"):
			e.damage(dmg * (0.3 + 0.7 * f))
		if was_marked and is_instance_valid(e):
			if e.has_method("unmark"):
				e.unmark()
			var p: Vector3 = e.global_position + Vector3.UP
			tree.create_timer(0.25, false).timeout.connect(detonate.bind(p, true))


## True when no world geometry is between `a` and `b`.
func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 0.2, b, 1)
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _scorch(where: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(where + Vector3.UP * 0.5, where + Vector3.DOWN * 3.0, 1)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var s := TimbukFx.spawn(get_tree(), "res://scenes/effects/scorch_mark.tscn", hit.position + hit.normal * 0.02, false, TimbukFx.basis_from_normal(hit.normal))
	if s:
		get_tree().create_timer(45.0).timeout.connect(s.queue_free)

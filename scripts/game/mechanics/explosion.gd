extends Node
## EXPLOSION (Daniel) - assignment rules.
## R detonates an instant sphere centred on the CURRENTLY MARKED target, which
## must be alive, visible and within RANGE (inclusive). The sphere reaches
## exactly RADIUS (inclusive) and deals flat DAMAGE - no falloff, no knockback,
## no player damage, no projectile, no chain reaction and no lingering fire.
## A target that is suspended when the blast resolves takes SUSPENDED_DAMAGE in
## total instead. Only world geometry blocks the blast; other targets never do,
## and the marked target at the centre is always hit. Each target is hit once.
## Suspension is snapshotted BEFORE the mark is consumed and the damage lands,
## then every affected suspension ends.
## Invalid activation costs nothing: the mark and the cooldown are preserved.
## Kept as polish only: the orange blast effect, scorch decal and camera shake.

signal detonated(where: Vector3)

const DAMAGE := 40.0
const SUSPENDED_DAMAGE := 60.0
const RADIUS := 4.0
const RANGE := 15.0
const COOLDOWN := 5.0
const SHAKE_RANGE := 18.0

var cooldown_left := 0.0

@onready var player: TimbukPlayer = get_parent()


func is_ready() -> bool:
	return cooldown_left <= 0.0


func _physics_process(delta: float) -> void:
	cooldown_left = TimbukFx.tick(cooldown_left, delta)
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("explode"):
		detonate()


## Would R detonate right now? Every rule check, no side effects: the HUD
## reads it every frame to light the Explosion meter (Daniel, main 7c20a81).
func can_detonate() -> bool:
	return _primary() != null


## The marked target a blast would centre on, or null if activation is invalid.
func _primary() -> Node:
	if player.dead or not is_ready() or get_tree().paused:
		return null
	var marking: Node = player.get_node_or_null("Marking")
	if marking == null:
		return null
	var target: Node = marking.current_target
	if target == null or not is_instance_valid(target) or target.is_dead():
		return null
	if player.upper_body_point().distance_to(target.center()) > RANGE:
		return null
	if not player.has_clear_line(target.center()):
		return null
	return target


## Detonates on the marked target. Returns true only when a blast resolved.
func detonate() -> bool:
	var target := _primary()
	if target == null:
		return false
	var marking: Node = player.get_node("Marking")

	var where: Vector3 = target.center()
	# every target the blast will touch, with its suspension read BEFORE
	# the mark is consumed and before any damage is applied
	var caught: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or e.is_dead():
			continue
		if e != target:
			if where.distance_to(e.center()) > RADIUS:
				continue
			if not _geometry_clear(where, e.center()):
				continue  # only world geometry blocks the blast
		caught.append({"target": e, "suspended": bool(e.suspended)})

	cooldown_left = COOLDOWN
	marking.consume_mark()
	_blast_fx(where)

	for entry in caught:
		var e: Node = entry["target"]
		if not is_instance_valid(e):
			continue
		e.apply_damage(SUSPENDED_DAMAGE if entry["suspended"] else DAMAGE)
	# the blast breaks any suspension it touched
	var suspend: Node = player.get_node_or_null("Suspend")
	for entry in caught:
		var e: Node = entry["target"]
		if not entry["suspended"] or not is_instance_valid(e):
			continue
		if suspend and suspend.current_target == e:
			suspend.end_suspension()
		else:
			e.set_suspended(false)
	detonated.emit(where)
	return true


## True when no world geometry lies between `a` and `b`.
func _geometry_clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, TimbukPlayer.LAYER_WORLD)
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _blast_fx(where: Vector3) -> void:
	TimbukFx.spawn(get_tree(), "res://scenes/effects/explosion_orange.tscn", where)
	_scorch(where)
	var pd := player.global_position.distance_to(where)
	if pd < SHAKE_RANGE:
		player.add_trauma(0.75 * (1.0 - pd / SHAKE_RANGE))


func _scorch(where: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(where + Vector3.UP * 0.5, where + Vector3.DOWN * 3.0, TimbukPlayer.LAYER_WORLD)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var s := TimbukFx.spawn(get_tree(), "res://scenes/effects/scorch_mark.tscn", hit.position + hit.normal * 0.02, false, TimbukFx.basis_from_normal(hit.normal))
	if s:
		get_tree().create_timer(45.0).timeout.connect(s.queue_free)


func ready_fraction() -> float:
	return clampf(1.0 - cooldown_left / COOLDOWN, 0.0, 1.0)


func cooldown_total() -> float:
	return COOLDOWN


func effective_range() -> float:
	return RANGE

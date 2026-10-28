extends TimbukEnemy
## The Twin: tougher, faster, hunts by sound. Any sprint step or gunshot
## anywhere tells it where the player is. Phase 2 at 50% health.

@export var phase2_speed_mult := 1.5
@export var phase2_attack_interval := 0.8

var phase := 1


func _ready() -> void:
	max_health = 400.0
	chase_speed = 4.2
	sight_range = 22.0
	attack_damage = 25.0
	attack_range = 2.4
	# hitbox is auto-fitted to the twin model (enemy.gd); just a bit bulkier
	# and the head (clock/gauge cluster) is a smaller weak point
	headshot_mult = 1.6
	capsule_radius = 0.36
	separation_radius = 1.2
	super._ready()
	add_to_group("boss")
	_play("idle")


func hear_noise(where: Vector3, _radius: float) -> void:
	# the Twin hears everything, once the chamber has power (before that it
	# waits behind the sealed door)
	if TimbukFx.state_call(get_tree(), "has_flag", ["power_restored"]) or global_position.distance_to(where) < sight_range:
		super.hear_noise(where, INF)


func take_hit(amount: float, hit_position: Vector3 = Vector3.INF, headshot := false) -> void:
	super.take_hit(amount, hit_position, headshot)
	if phase == 1 and health > 0.0 and health <= max_health * 0.5:
		phase = 2
		chase_speed *= phase2_speed_mult
		attack_interval = phase2_attack_interval
		if model and model.has_method("play_visual"):
			model.play_visual("wire_vibrate")
		TimbukFx.spawn(get_tree(), "res://scenes/effects/explosion_purple.tscn", global_position + Vector3.UP)


func _set_state(s: State) -> void:
	super._set_state(s)
	match s:
		State.IDLE: _play("eye_scan")
		State.WANDER, State.CHASE: _play("walk_slow")
		State.ATTACK: _play("twitch")


func _on_death() -> void:
	TimbukFx.state_call(get_tree(), "set_flag", ["twin_defeated"])
	# GameState.set_flag("twin_defeated") triggers the win by itself


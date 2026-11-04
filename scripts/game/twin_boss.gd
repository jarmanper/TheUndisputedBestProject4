extends TimbukEnemy
## The Twin: the final target, and mechanically an ordinary enemy.
## The assignment gives every enemy the same 100 HP, speed, reach and attack,
## so the boss gets no extra health, no phase change and no hunting by sound.
## What still makes him the boss is his size, his animations and the fact that
## defeating him ends the game - all of which live in the art, not the rules.

func _ready() -> void:
	# the hitbox is auto-fitted to the Twin model (enemy.gd); he is only bulkier
	capsule_radius = 0.36
	separation_radius = 1.2
	super._ready()
	add_to_group("boss")
	_play("idle")


func _set_state(s: State) -> void:
	super._set_state(s)
	match s:
		State.IDLE: _play("eye_scan")
		State.CHASE: _play("walk_slow")
		State.WINDUP: _play("twitch")


func _on_death() -> void:
	TimbukFx.state_call(get_tree(), "set_flag", ["twin_defeated"])
	# GameState.set_flag("twin_defeated") triggers the win by itself

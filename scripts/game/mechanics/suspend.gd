extends Node
## SUSPEND (Jarman): Q freezes every enemy within `radius` of the point you
## look at for `duration` seconds. AI and animation stop; a ghost
## afterimage is left behind. Cooldown `cooldown` seconds.

const Afterimage := preload("res://scripts/visual/afterimage_spawner.gd")

@export var radius := 10.0
@export var duration := 4.0
@export var cooldown := 10.0
@export var max_range := 30.0

var cooldown_left := 0.0
var _ghosts: Node

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	_ghosts = Afterimage.new()
	_ghosts.lifetime = 1.2
	add_child(_ghosts)


func _process(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("suspend") and cooldown_left <= 0.0:
		activate()


func activate() -> void:
	cooldown_left = cooldown
	var center := player.aim_point(max_range)
	var field := TimbukFx.spawn(get_tree(), "res://scenes/effects/suspend_field.tscn", center, false)
	if field:
		field.scale = Vector3.ONE * 0.1
		var tw := field.create_tween()
		tw.tween_property(field, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_interval(duration - 0.7)
		tw.tween_property(field, "scale", Vector3.ONE * 0.05, 0.35)
		tw.tween_callback(field.queue_free)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = load("res://assets/audio/sfx/suspend_activate.wav")
	get_tree().current_scene.add_child(snd)
	snd.global_position = center
	snd.play()
	snd.finished.connect(snd.queue_free)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.is_dead() or e.global_position.distance_to(center) > radius:
			continue
		e.suspend(duration)
		var parts := TimbukFx.spawn(get_tree(), "res://scenes/effects/suspended_particles.tscn", e.global_position + Vector3.UP, false)
		if parts:
			get_tree().create_timer(duration).timeout.connect(parts.queue_free)
		if DisplayServer.get_name() == "headless":
			continue  # no renderer to bake the pose with
		for mi in e.find_children("*", "MeshInstance3D", true, false):
			if mi.visible and mi.mesh and (mi.skeleton == NodePath() or mi.skin != null):
				_ghosts.spawn(mi)


func ready_fraction() -> float:
	return 1.0 - cooldown_left / cooldown

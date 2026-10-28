extends Node
## SUSPEND (Jarman): Q freezes every enemy within `radius` of the point you
## look at for `duration` seconds. AI and animation stop; a ghost
## afterimage is left behind. Cooldown `cooldown` seconds.

signal activated(center: Vector3, count: int)
signal ready_again

const Afterimage := preload("res://scripts/visual/afterimage_spawner.gd")
const ACTIVATE_SFX := preload("res://assets/audio/sfx/suspend_activate.wav")
const LOOP_SFX := preload("res://assets/audio/sfx/suspend_loop.wav")

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
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)
		if cooldown_left <= 0.0:
			ready_again.emit()
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("suspend") and cooldown_left <= 0.0:
		activate()


## Returns how many enemies were frozen.
func activate() -> int:
	cooldown_left = cooldown
	var tree := get_tree()
	var center := player.aim_point(max_range)
	var field := TimbukFx.spawn(tree, "res://scenes/effects/suspend_field.tscn", center, false)
	if field:
		field.scale = Vector3.ONE * 0.1
		var tw := field.create_tween()
		tw.tween_property(field, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(maxf(0.0, duration - 0.7))
		tw.tween_property(field, "scale", Vector3.ONE * 0.05, 0.35).set_ease(Tween.EASE_IN)
		tw.tween_callback(field.queue_free)
	_sound(ACTIVATE_SFX, center, 0.0, 0.0)
	_sound(LOOP_SFX, center, -6.0, duration)
	player.add_trauma(0.18)
	var hits := 0
	for e in tree.get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("suspend"):
			continue
		if (e.has_method("is_dead") and e.is_dead()) or e.global_position.distance_to(center) > radius:
			continue
		e.suspend(duration)
		hits += 1
		var parts := TimbukFx.spawn(tree, "res://scenes/effects/suspended_particles.tscn", e.global_position + Vector3.UP, false)
		if parts:
			tree.create_timer(duration).timeout.connect(parts.queue_free)
		if DisplayServer.get_name() == "headless":
			continue  # no renderer to bake the pose with
		for mi in e.find_children("*", "MeshInstance3D", true, false):
			if mi.is_visible_in_tree() and mi.mesh and (mi.skeleton == NodePath() or mi.skin != null):
				_ghosts.spawn(mi)
	activated.emit(center, hits)
	return hits


## One-shot (life <= 0) or looping-for-`life`-seconds positional sound.
func _sound(stream: AudioStream, where: Vector3, vol: float, life: float) -> void:
	var tree := get_tree()
	var parent: Node = tree.current_scene if tree.current_scene else tree.root
	var snd := AudioStreamPlayer3D.new()
	snd.stream = stream
	snd.bus = "SFX"
	snd.volume_db = vol
	snd.max_distance = 50.0
	parent.add_child(snd)
	snd.global_position = where
	snd.play()
	if life > 0.0:
		var tw := snd.create_tween()
		tw.tween_interval(maxf(0.0, life - 0.4))
		tw.tween_property(snd, "volume_db", -40.0, 0.4)
		tw.tween_callback(snd.queue_free)
	else:
		snd.finished.connect(snd.queue_free)


func ready_fraction() -> float:
	return 1.0 if cooldown <= 0.0 else clampf(1.0 - cooldown_left / cooldown, 0.0, 1.0)

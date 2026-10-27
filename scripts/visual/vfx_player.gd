extends Node3D
## Plays a visual effect: restarts every particle system under this node,
## flashes child lights and animates "Shockwave"/"Flash" meshes. Visual only:
## teammates call play() from their mechanic code when they want the effect.

@export var autoplay := true
## Re-trigger every `loop_interval` seconds (for previews/ambient effects).
@export var loop := false
@export var loop_interval := 2.5
## Free the node after it finishes (one-shot effects spawned at runtime).
@export var free_when_done := false
@export var duration := 2.0

var _lights := {}
var _timer := 0.0


func _ready() -> void:
	for l in find_children("*", "Light3D", true, false):
		_lights[l] = l.light_energy
		l.light_energy = 0.0
	if autoplay:
		play()


func play() -> void:
	_timer = 0.0
	for p in find_children("*", "GPUParticles3D", true, false):
		p.restart()
		p.emitting = true
	for l in _lights:
		var tw := create_tween()
		l.light_energy = _lights[l]
		tw.tween_property(l, "light_energy", 0.0, l.get_meta("fade", 0.35)).set_ease(Tween.EASE_OUT)
	for m in find_children("Shockwave*", "MeshInstance3D", true, false):
		m.scale = Vector3.ONE * 0.1
		m.visible = true
		var tw := create_tween().set_parallel()
		tw.tween_property(m, "scale", Vector3.ONE * m.get_meta("max_scale", 4.0), 0.45).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "transparency", 1.0, 0.45).from(0.0)
	for m in find_children("Flash*", "MeshInstance3D", true, false):
		m.visible = true
		var tw := create_tween()
		tw.tween_property(m, "transparency", 1.0, m.get_meta("fade", 0.08)).from(0.0)
		tw.tween_callback(func(): m.visible = false)


func _process(delta: float) -> void:
	_timer += delta
	if loop and _timer >= loop_interval:
		play()
	elif free_when_done and _timer >= duration:
		queue_free()

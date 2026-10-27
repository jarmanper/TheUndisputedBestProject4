extends Node3D
## Twin reveal presentation (visual only): the creature lifts its head while
## the camera pushes in from the chamber entrance to a framed close-up of the
## clock face and eye. Restarts every `loop_time` seconds for preview.

@export var twin_path: NodePath
@export var camera_path: NodePath
@export var loop_time := 16.0
@export var auto_loop := true

## Camera keyframes: [time, position, look-at target]. Filled by the builder.
@export var shots: Array = []

var _t := 0.0
var _twin: Node3D
var _cam: Camera3D


func _ready() -> void:
	_twin = get_node(twin_path)
	_cam = get_node(camera_path)
	_cam.current = true
	restart()


func restart() -> void:
	_t = 0.0
	if _twin and _twin.has_method("play_visual"):
		_twin.play_visual("reveal", 0.0)


func _process(delta: float) -> void:
	_t += delta
	if shots.size() >= 2:
		var i := 0
		while i < shots.size() - 2 and _t > float(shots[i + 1][0]):
			i += 1
		var a: Array = shots[i]
		var b: Array = shots[i + 1]
		var u := clampf((_t - float(a[0])) / max(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		var pos: Vector3 = (a[1] as Vector3).lerp(b[1], u)
		var tgt: Vector3 = (a[2] as Vector3).lerp(b[2], u)
		_cam.global_transform = Transform3D(Basis.looking_at(tgt - pos, Vector3.UP), pos)
	if _twin and _t > 6.5 and _twin.has_method("play_visual") and _twin.get("animation") != "eye_scan":
		_twin.set("animation", "eye_scan")
		_twin.play_visual("eye_scan", 0.6)
	if auto_loop and _t > loop_time:
		_twin.set("animation", "reveal")
		restart()

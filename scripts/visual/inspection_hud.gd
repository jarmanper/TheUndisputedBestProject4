extends CanvasLayer
## On-screen help + FPS for the visual inspection scene.

@export var camera_path: NodePath
@onready var _label: Label = $Label
var _cam: Camera3D


func _ready() -> void:
	_cam = get_node(camera_path)


func _process(_delta: float) -> void:
	if not visible:
		return
	var names: PackedStringArray = _cam.get_view_names()
	var listing := ""
	for i in names.size():
		var key := str((i + 1) % 10) if i < 10 else "Tab"
		listing += "  %s  %s\n" % [key, names[i]]
	_label.text = ("TIMBUK visual inspection   %d FPS\nview: %s\n\n" % [Engine.get_frames_per_second(), _cam.current_view_name()]
		+ "WASD move · mouse look · Q/E down/up · Shift fast\nTab next view · F flashlight · G fog · H hide help\n\n" + listing)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		visible = not visible

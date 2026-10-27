extends Camera3D
## Free-look camera for the visual inspection scene (visual testing only).
## Mouse: look | WASD: move | Q/E: down/up | Shift: fast | 1-9,0: viewpoints
## F: flashlight | G: volumetric fog | Tab: next viewpoint | Esc: release mouse

@export var speed := 4.0
@export var sensitivity := 0.0025

var _yaw := 0.0
var _pitch := 0.0
var _views: Array[Node3D] = []
var _view_index := -1
@onready var _flashlight: SpotLight3D = $Flashlight


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_yaw = rotation.y
	_pitch = rotation.x
	for n in get_tree().root.find_children("VIEW__*", "Node3D", true, false):
		_views.append(n)
	_views.sort_custom(func(a, b): return String(a.name) < String(b.name))


func get_view_names() -> PackedStringArray:
	var out := PackedStringArray()
	for v in _views:
		out.append(String(v.name).trim_prefix("VIEW__"))
	return out


func go_to_view(i: int) -> void:
	if _views.is_empty():
		return
	_view_index = wrapi(i, 0, _views.size())
	var v := _views[_view_index]
	global_transform = v.global_transform
	_yaw = global_rotation.y
	_pitch = global_rotation.x


func current_view_name() -> String:
	if _view_index < 0:
		return "free"
	return String(_views[_view_index].name).trim_prefix("VIEW__")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * sensitivity
		_pitch = clamp(_pitch - event.relative.y * sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				_flashlight.visible = not _flashlight.visible
			KEY_G:
				var env := get_world_3d().environment
				if env:
					env.volumetric_fog_enabled = not env.volumetric_fog_enabled
			KEY_TAB:
				go_to_view(_view_index + 1)
			_:
				if event.keycode >= KEY_0 and event.keycode <= KEY_9:
					var n: int = event.keycode - KEY_1
					if event.keycode == KEY_0:
						n = 9
					go_to_view(n)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += transform.basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	var s := speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if dir != Vector3.ZERO:
		global_position += dir.normalized() * s * delta

extends CanvasLayer
## Always processes so Esc can both pause and resume. No new gameplay action.
var overlay: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.03, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	overlay = shade
	for x in [-16, 6]:
		var bar := ColorRect.new()
		bar.color = Color.WHITE
		bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		bar.position = Vector2(x, -20)
		bar.size = Vector2(10, 40)
		shade.add_child(bar)
	overlay.hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func set_paused(value: bool) -> void:
	get_tree().paused = value
	overlay.visible = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(overlay):
		set_paused(true)

func _exit_tree() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

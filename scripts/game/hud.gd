extends CanvasLayer
## Wordless health, crosshair, cooldowns, pause, victory and loss feedback.
@export var player_path: NodePath
var player: TimbukPlayer
var paused_overlay: ColorRect
var display: Control

func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node(player_path)
	display = Control.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	display.draw.connect(_draw_hud)
	paused_overlay = ColorRect.new()
	paused_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paused_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paused_overlay.color = Color(0.01, 0.02, 0.03, 0.65)
	add_child(paused_overlay)
	paused_overlay.hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	paused_overlay.visible = get_tree().paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	display.queue_redraw()

func _draw_hud() -> void:
	var size := display.size
	var point := size * 0.5
	display.draw_circle(point, 2.0, Color.WHITE)
	for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		display.draw_line(point + offset * 6, point + offset * 10, Color.WHITE, 1.5)
	display.draw_rect(Rect2(24, size.y - 40, 180, 12), Color(0.03, 0.04, 0.05, 0.9))
	display.draw_rect(Rect2(24, size.y - 40, 180 * player.health / 100, 12), Color(0.3, 0.85, 0.65))
	var names := ["Combat", "Marking", "Suspend", "Explosion"]
	var colors := [Color.CORAL, Color.ORANGE, Color.SKY_BLUE, Color.MEDIUM_PURPLE]
	for i in names.size():
		var ability := player.get_node(names[i])
		point = Vector2(size.x - 200 + i * 48, size.y - 36)
		display.draw_circle(point, 17, Color(0.02, 0.03, 0.04, 0.9))
		display.draw_circle(point, 4 + i, colors[i])
		var fraction := 1.0 - clampf(float(ability.cooldown_left) / float(ability.get("COOLDOWN")), 0, 1)
		display.draw_arc(point, 17, -PI / 2, -PI / 2 + TAU * fraction, 48, colors[i], 3)
	var main := player.get_parent()
	if main.get("outcome") == 2:
		display.draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0, 0, 0.35))
	elif main.get("outcome") == 1:
		display.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0.25, 0.12, 0.25))

func _exit_tree() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

extends CanvasLayer
## Controls stay visible while the player learns the mark/freeze/blast combo.
@export var player_path: NodePath
var player: TimbukPlayer
var paused_overlay: ColorRect
var hit_flash := 0.0
var blast_flash := 0.0
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
	_build_controls()
	player.get_node("Combat").hit_confirmed.connect(func(): hit_flash = 0.18)
	player.get_node("Explosion").detonated.connect(func(_origin: Vector3, _hits: int): blast_flash = 0.35)
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

func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.04, 0.88)
	style.border_color = Color(0.45, 0.65, 0.8, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	display.add_child(panel)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.text = "WASD Move   |   Mouse Aim   |   Esc Pause\nLeft click: Attack within 3m\nQ: Mark within 15m; lasts 8s\nE: Freeze within 12m; marked targets freeze longer\nR: Detonate mark within 15m; walls block blasts\nBlast: 4m radius, 40 damage; frozen targets take 60\nCombo: Q, E, two close attacks, R\nRelease and press again; rings show cooldowns."
	panel.add_child(label)

func _process(delta: float) -> void:
	if not get_tree().paused:
		hit_flash = maxf(0, hit_flash - delta)
		blast_flash = maxf(0, blast_flash - delta)
	display.queue_redraw()

func _draw_hud() -> void:
	var size := display.size
	var point := size * 0.5
	if blast_flash > 0:
		display.draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.65, 1.0, blast_flash * 0.3))
	if hit_flash > 0:
		for diagonal in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			display.draw_line(point + diagonal * 12, point + diagonal * 18, Color.CORAL, 2)
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
		var active := i == 1 and is_instance_valid(player.get_node("Marking").current_target)
		active = active or (i == 3 and player.get_node("Explosion").can_detonate())
		if active:
			display.draw_circle(point, 21, Color(colors[i], 0.35))
		display.draw_circle(point, 4 + i, colors[i])
		display.draw_string(ThemeDB.fallback_font, point + Vector2(-13, -25), ["LMB", "Q", "E", "R"][i], HORIZONTAL_ALIGNMENT_CENTER, 28, 14, Color.WHITE)
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

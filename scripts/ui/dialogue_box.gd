extends CanvasLayer
## Story UI: typewriter dialogue at the bottom, objective at the top-left,
## and full-screen death / ending overlays. Built in code so the scene is
## self-contained: drop res://scenes/ui/dialogue_box.tscn into any level.

const CHARS_PER_SEC := 45.0
const AUTO_ADVANCE_BASE := 2.5      # seconds a finished line stays up...
const AUTO_ADVANCE_PER_CHAR := 0.04 # ...plus a bit per character

var _queue: Array = []
var _full_text := ""
var _shown := 0.0
var _hold := 0.0
var _active := false

var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _hint: Label
var _objective_box: VBoxContainer
var _objective_label: Label
var _overlay: ColorRect
var _overlay_title: Label
var _overlay_sub: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.dialogue_requested.connect(_on_dialogue_requested)
	GameState.objective_changed.connect(_on_objective_changed)
	GameState.player_died.connect(_on_player_died)
	GameState.game_won.connect(_on_game_won)
	if GameState.objective != "":
		_on_objective_changed(GameState.objective)


# ---------------------------------------------------------------- dialogue

func _on_dialogue_requested(lines: Array) -> void:
	for line in lines:
		if line is Dictionary:
			_queue.append(line)
	if not _active:
		_next_line()


func _next_line() -> void:
	if _queue.is_empty():
		_active = false
		_panel.visible = false
		return
	var line: Dictionary = _queue.pop_front()
	_active = true
	_panel.visible = true
	var who := str(line.get("speaker", ""))
	_speaker.text = who.to_upper()
	_speaker.visible = who != ""
	_speaker.add_theme_color_override("font_color", _speaker_color(who))
	_full_text = str(line.get("text", ""))
	_text.text = _full_text
	_text.visible_characters = 0
	_shown = 0.0
	_hold = 0.0


func _speaker_color(who: String) -> Color:
	match who.to_lower():
		"reyes": return Color(0.85, 0.85, 0.8)
		"dr. hale", "hale": return Color(0.55, 0.8, 0.75)
		"the twin", "twin", "???": return Color(0.9, 0.2, 0.15)
		_: return Color(0.9, 0.7, 0.35)   # recordings, logs, notes


func _process(delta: float) -> void:
	if not _active:
		return
	if _text.visible_characters < _full_text.length():
		_shown += delta * CHARS_PER_SEC
		_text.visible_characters = mini(int(_shown), _full_text.length())
	else:
		_hold += delta
		if _hold >= AUTO_ADVANCE_BASE + _full_text.length() * AUTO_ADVANCE_PER_CHAR:
			_next_line()


func _advance() -> void:
	if _text.visible_characters < _full_text.length():
		_text.visible_characters = _full_text.length()   # finish typing first
	else:
		_next_line()


func _input(event: InputEvent) -> void:
	if not _active or not event.is_pressed() or event.is_echo():
		return
	var advance := false
	if event is InputEventKey:
		advance = event.physical_keycode in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	elif event is InputEventMouseButton:
		advance = event.button_index == MOUSE_BUTTON_LEFT
	if advance:
		_advance()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- objective

func _on_objective_changed(text: String) -> void:
	_objective_label.text = text
	_objective_box.visible = text != ""
	_objective_box.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_objective_box, "modulate", Color(1.6, 1.3, 1.0, 1), 0.4)
	tw.tween_property(_objective_box, "modulate", Color(1, 1, 1, 1), 1.2)


# ---------------------------------------------------------------- overlays

func _on_player_died() -> void:
	_show_overlay(Color(0.25, 0.0, 0.0, 0.0), Color(0.25, 0.0, 0.0, 0.92),
		"YOUR CLOCK STOPPED", "It heard you.", Color(0.95, 0.2, 0.15))


func _on_game_won() -> void:
	_show_overlay(Color(0, 0, 0, 0), Color(0, 0, 0, 1),
		"THE CLOCK IS SILENT",
		"The Twin is still. For the first time in eleven years, nothing in TIMBUK is ticking.\n\nReyes walked out at dawn. Dr. Hale never answered the radio again.\n\nSomewhere below, a second hand twitched.",
		Color(0.9, 0.85, 0.7))


func _show_overlay(from: Color, to: Color, title: String, sub: String, title_color: Color) -> void:
	_queue.clear()
	_active = false
	_panel.visible = false
	_overlay.visible = true
	_overlay.color = from
	_overlay_title.text = title
	_overlay_title.add_theme_color_override("font_color", title_color)
	_overlay_sub.text = sub
	_overlay_title.modulate.a = 0.0
	_overlay_sub.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_overlay, "color", to, 1.2)
	tw.tween_property(_overlay_title, "modulate:a", 1.0, 0.8)
	tw.tween_property(_overlay_sub, "modulate:a", 1.0, 1.5)


# ---------------------------------------------------------------- build

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Objective, top-left.
	_objective_box = VBoxContainer.new()
	_objective_box.position = Vector2(28, 24)
	_objective_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_box.visible = false
	root.add_child(_objective_box)
	var obj_head := Label.new()
	obj_head.text = "OBJECTIVE"
	obj_head.add_theme_font_size_override("font_size", 13)
	obj_head.add_theme_color_override("font_color", Color(0.75, 0.3, 0.25))
	_objective_box.add_child(obj_head)
	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 20)
	_objective_label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	_objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_objective_label.add_theme_constant_override("shadow_offset_x", 2)
	_objective_label.add_theme_constant_override("shadow_offset_y", 2)
	_objective_box.add_child(_objective_label)

	# Dialogue panel, bottom-centre.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -190
	_panel.offset_bottom = -36
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.025, 0.86)
	sb.border_color = Color(0.45, 0.12, 0.1, 0.9)
	sb.border_width_top = 2
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	root.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 16)
	vb.add_child(_speaker)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("font_size", 22)
	_text.add_theme_color_override("font_color", Color(0.9, 0.88, 0.84))
	vb.add_child(_text)
	_hint = Label.new()
	_hint.text = "[E] continue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vb.add_child(_hint)

	# Full-screen overlay for death / ending.
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	root.add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var ovb := VBoxContainer.new()
	ovb.custom_minimum_size = Vector2(760, 0)
	ovb.add_theme_constant_override("separation", 24)
	center.add_child(ovb)
	_overlay_title = Label.new()
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 64)
	ovb.add_child(_overlay_title)
	_overlay_sub = Label.new()
	_overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_sub.add_theme_font_size_override("font_size", 22)
	_overlay_sub.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	ovb.add_child(_overlay_sub)

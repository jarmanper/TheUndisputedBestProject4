extends CanvasLayer
## HUD: crosshair, health, ammo, marks, suspend cooldown, charges,
## the "E - interact" prompt and the pause menu. Built in code; reads the
## player and its mechanic nodes every frame.

@export var player_path: NodePath

var player: TimbukPlayer
var _health_bar: ProgressBar
var _info: Label
var _prompt: Label
var _damage: ColorRect
var _pause: Control


func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node_or_null(player_path)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.modulate = Color(1, 1, 1, 0.7)
	add_child(cross)

	_damage = ColorRect.new()
	_damage.color = Color(0.6, 0, 0, 0)
	_damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_damage)

	var box := VBoxContainer.new()
	box.position = Vector2(24, 24)
	add_child(box)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(220, 18)
	_health_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.7, 0.08, 0.08)
	_health_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_health_bar)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	box.add_child(_info)

	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.position.y += 48
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_prompt)

	_build_pause()


func _build_pause() -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0, 0, 0, 0.7)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	add_child(_pause)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_theme_constant_override("separation", 12)
	_pause.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(toggle_pause)
	v.add_child(resume)
	var quit := Button.new()
	quit.text = "Quit to title"
	quit.pressed.connect(_quit)
	v.add_child(quit)


func toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	_pause.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED


func _quit() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var gs := TimbukFx.game_state(get_tree())
	if gs and gs.has_method("go_to_title"):
		gs.go_to_title()
	else:
		get_tree().quit()


func flash_damage() -> void:
	_damage.color.a = 0.35
	create_tween().tween_property(_damage, "color:a", 0.0, 0.5)


func _process(_delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	_health_bar.max_value = player.max_health
	_health_bar.value = player.health
	var lines: PackedStringArray = ["HP %d" % ceili(player.health)]
	var combat := player.get_node_or_null("Combat")
	if combat:
		lines.append("AMMO %d / %d%s" % [combat.ammo, combat.reserve_ammo, "  (reloading)" if combat.reloading else ""])
	var marking := player.get_node_or_null("Marking")
	if marking:
		lines.append("MARKS %d / %d" % [marking.count(), marking.max_marks])
	var suspend := player.get_node_or_null("Suspend")
	if suspend:
		lines.append("SUSPEND " + ("READY" if suspend.cooldown_left <= 0.0 else "%.1fs" % suspend.cooldown_left))
	var boom := player.get_node_or_null("Explosion")
	if boom:
		lines.append("CHARGES %d / %d" % [boom.charges, boom.max_charges])
	_info.text = "\n".join(lines)
	var h: Node = player.hovered
	_prompt.text = h.get_prompt() if h and h.has_method("get_prompt") else ""

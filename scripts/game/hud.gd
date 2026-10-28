extends CanvasLayer
## HUD: crosshair (kicks on fire, hit marker), health bar with smooth drain,
## ammo counter, mechanic status, "[E] ..." interaction prompt, damage
## vignette and the pause menu (Resume / Settings / Quit to title).
## Built in code; reads the player and its mechanic nodes every frame.
##
## Public API (group "hud"):
##   show_hit_marker(headshot: bool)  - flash the hit marker
##   pulse_crosshair(amount := 1.0)   - kick the crosshair outward
##   flash_damage()                   - red vignette flash
##   toggle_pause() / set_paused(on: bool) / is_paused() -> bool

@export var player_path: NodePath

var player: TimbukPlayer
var _root: Control
var _cross: UiCrosshair
var _health_bar: ProgressBar
var _health_lag: ProgressBar
var _health_label: Label
var _ammo: Label
var _ammo_sub: Label
var _info: Label
var _prompt: Label
var _vignette: TextureRect
var _hurt := 0.0
var _shown_health := -1.0
var _lag_health := -1.0
var _lag_wait := 0.0
var _last_ammo := -1
var _pause: ColorRect
var _pause_main: VBoxContainer
var _settings: UiSettingsPanel
var _resume_btn: Button


func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node_or_null(player_path) as TimbukPlayer

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_vignette = TextureRect.new()
	_vignette.texture = _make_vignette()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1, 1, 1, 0)
	_root.add_child(_vignette)

	_cross = UiCrosshair.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_cross.size = Vector2(80, 80)
	_cross.position -= _cross.size * 0.5
	_root.add_child(_cross)

	_prompt = UiStyle.label("", 20)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = 46
	_prompt.offset_bottom = 76
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt)

	_build_health()
	_build_ammo()
	_build_pause()


func _build_health() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 28
	box.offset_top = -78
	box.offset_bottom = -28
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_health_label = UiStyle.label("HEALTH", 13, Color(0.75, 0.3, 0.25))
	box.add_child(_health_label)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(260, 16)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stack)
	_health_lag = _bar(Color(0.95, 0.85, 0.75, 0.85), Color(0.03, 0.03, 0.03, 0.75))
	stack.add_child(_health_lag)
	_health_bar = _bar(Color(0.72, 0.07, 0.06), Color(0, 0, 0, 0))
	stack.add_child(_health_bar)


func _bar(fill_color: Color, bg_color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.step = 0.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	b.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	if bg_color.a > 0.0:
		bg.border_color = Color(0.4, 0.4, 0.42, 0.6)
		bg.set_border_width_all(1)
	b.add_theme_stylebox_override("background", bg)
	return b


func _build_ammo() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -320
	box.offset_right = -28
	box.offset_top = -200
	box.offset_bottom = -24
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_info = UiStyle.label("", 14, Color(0.75, 0.75, 0.72))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_info)
	_ammo = UiStyle.label("", 40)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_ammo)
	_ammo_sub = UiStyle.label("", 14, Color(0.75, 0.3, 0.25))
	_ammo_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_ammo_sub)


func _build_pause() -> void:
	# Own layer so the menu sits above the dialogue box (layer 10).
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 20
	add_child(menu_layer)
	_pause = ColorRect.new()
	_pause.color = Color(0, 0, 0, 0.8)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	menu_layer.add_child(_pause)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	_pause_main = VBoxContainer.new()
	_pause_main.add_theme_constant_override("separation", 12)
	_pause_main.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_pause_main)
	var title := UiStyle.label("PAUSED", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_main.add_child(title)
	_resume_btn = UiStyle.button("Resume")
	_resume_btn.pressed.connect(set_paused.bind(false))
	_pause_main.add_child(_resume_btn)
	var settings := UiStyle.button("Settings")
	settings.pressed.connect(_open_settings)
	_pause_main.add_child(settings)
	var quit := UiStyle.button("Quit to title")
	quit.pressed.connect(_quit)
	_pause_main.add_child(quit)
	_settings = UiSettingsPanel.new()
	_settings.visible = false
	_settings.back_pressed.connect(_close_settings)
	center.add_child(_settings)


# ------------------------------------------------------------ public API

func show_hit_marker(headshot: bool = false) -> void:
	_cross.hit(headshot)


func pulse_crosshair(amount: float = 1.0) -> void:
	_cross.kick(amount)


func flash_damage() -> void:
	_hurt = 1.0


func is_paused() -> bool:
	return _pause.visible


func toggle_pause() -> void:
	set_paused(not _pause.visible)


func set_paused(on: bool) -> void:
	if on and (_game_over() or get_tree().paused):
		return   # end screens own the pause state
	if on == _pause.visible:
		return
	get_tree().paused = on
	_pause.visible = on
	_close_settings()
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_resume_btn.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ internals

func _game_over() -> bool:
	return bool(TimbukFx.state_call(get_tree(), "is_game_over"))


func _open_settings() -> void:
	_settings.refresh()
	_pause_main.visible = false
	_settings.visible = true
	_settings.focus_first()


func _close_settings() -> void:
	if _settings.visible:
		_settings.visible = false
		_pause_main.visible = true
		_resume_btn.grab_focus()


func _quit() -> void:
	_pause.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var gs := TimbukFx.game_state(get_tree())
	if gs and gs.has_method("go_to_title"):
		gs.go_to_title()
	else:
		get_tree().quit()


func _input(event: InputEvent) -> void:
	# While paused the player is frozen, so the HUD handles Esc itself.
	if not _pause.visible or not event.is_action_pressed("pause"):
		return
	if _settings.visible:
		_close_settings()
	else:
		set_paused(false)
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and player and not player.dead:
		set_paused(true)


func _process(delta: float) -> void:
	_hurt = maxf(0.0, _hurt - delta * 1.6)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as TimbukPlayer
		if player == null:
			_root.visible = false
			return
	var over := _game_over() or player.dead
	_root.visible = not _pause.visible and not (over and player.dead)
	_update_health(delta)
	_update_ammo()
	_update_info()
	var h: Node = player.hovered
	if is_instance_valid(h) and h.has_method("get_prompt") and not over:
		_prompt.text = h.get_prompt()
	else:
		_prompt.text = ""
	_cross.highlight = _prompt.text != ""
	_cross.visible = not over


func _update_health(delta: float) -> void:
	var mx := maxf(1.0, player.max_health)
	var hp := clampf(player.health, 0.0, mx)
	if _shown_health < 0.0:
		_shown_health = hp
		_lag_health = hp
	if hp < _shown_health - 0.5:
		_lag_wait = 0.45
	_shown_health = lerpf(_shown_health, hp, 1.0 - exp(-delta * 14.0))
	if _lag_health < _shown_health:
		_lag_health = _shown_health   # healing: catch up immediately
	elif _lag_wait > 0.0:
		_lag_wait -= delta
	else:
		_lag_health = move_toward(_lag_health, _shown_health, mx * 0.6 * delta)
	_health_bar.max_value = mx
	_health_lag.max_value = mx
	_health_bar.value = _shown_health
	_health_lag.value = _lag_health
	var frac := hp / mx
	_health_label.text = "HEALTH  %d" % ceili(hp)
	# Vignette: hit flash plus a slow pulse when health is low.
	var low := 0.0
	if frac < 0.35 and hp > 0.0:
		low = (0.35 - frac) / 0.35 * (0.45 + 0.15 * sin(Time.get_ticks_msec() * 0.006))
	_vignette.modulate.a = clampf(maxf(_hurt * 0.85, low), 0.0, 1.0)


func _update_ammo() -> void:
	var combat := player.get_node_or_null("Combat")
	if combat == null:
		_ammo.text = ""
		_ammo_sub.text = ""
		return
	var a: int = combat.ammo
	if _last_ammo >= 0 and a < _last_ammo:
		_cross.kick()
	_last_ammo = a
	_ammo.text = "%d / %d" % [a, combat.reserve_ammo]
	_ammo.add_theme_color_override("font_color", Color(0.95, 0.3, 0.25) if a <= 2 else UiStyle.TEXT)
	if combat.reloading:
		_ammo_sub.text = "RELOADING"
	elif a == 0 and combat.reserve_ammo == 0:
		_ammo_sub.text = "NO AMMO"
	elif a <= 2:
		_ammo_sub.text = "[R] RELOAD"
	else:
		_ammo_sub.text = ""


func _update_info() -> void:
	var lines: PackedStringArray = []
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


static func _make_vignette() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0.55, 0, 0, 0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.5, 0, 0, 0.95))
	g.add_point(0.55, Color(0.55, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.15, 0.5)
	t.width = 256
	t.height = 256
	return t

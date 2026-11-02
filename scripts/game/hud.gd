extends CanvasLayer
## HUD: crosshair (kicks on fire, hit marker), health bar with smooth drain,
## wordless ability cooldown meters, damage
## vignette and the pause menu (Resume / Settings / Quit to title).
## Built in code; reads the player and its mechanic nodes every frame.
##
## Also owns the always-on cinematic grade (film grain + vignette + a touch of
## chromatic aberration) on its own canvas layer underneath every UI element,
## so the 3D image reads as filmed while the HUD stays clean.
##
## Public API (group "hud"):
##   show_hit_marker(headshot: bool)  - flash the hit marker
##   pulse_crosshair(amount := 1.0)   - kick the crosshair outward
##   flash_damage()                   - red vignette flash
##   toggle_pause() / set_paused(on: bool) / is_paused() -> bool
## Public API (group "game_grade"):
##   set_quality(level: int)          - 0 Low / 1 Medium / 2 High

const GRADE_SHADER := "res://assets/shaders/game_grade.gdshader"
## Per quality level: grain amplitude, vignette strength, edge aberration.
## Tuned by eye at 1920x1080: aberration above ~0.002 reads as a rainbow on
## vertical edges instead of as a lens, and grain above ~0.035 reads as noise.
const GRADE_PRESETS := [
	{"grain": 0.020, "vignette": 0.22, "aberration": 0.0},
	{"grain": 0.024, "vignette": 0.26, "aberration": 0.0007},
	{"grain": 0.025, "vignette": 0.26, "aberration": 0.0008},
]

@export var player_path: NodePath

var player: TimbukPlayer
var _root: Control
var _cross: UiCrosshair
var _health_bar: ProgressBar
var _health_lag: ProgressBar
var _health_label: Label
var _ability_bars := {}
var _pips: Array[ColorRect] = []
var _pip_row: HBoxContainer
var _pips_total := 0
var _vignette: TextureRect
var _hurt := 0.0
var _shown_health := -1.0
var _lag_health := -1.0
var _lag_wait := 0.0
var _pause: ColorRect
var _pause_main: VBoxContainer
var _settings: UiSettingsPanel
var _resume_btn: Button
var _grade: ColorRect


func _ready() -> void:
	add_to_group("hud")
	add_to_group("game_grade")
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node_or_null(player_path) as TimbukPlayer

	_build_grade()

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

	_build_health()
	_build_abilities()
	_build_pause()


## Full-screen cinematic pass. Its own CanvasLayer at a negative layer index:
## that draws over the 3D viewport but under the HUD (1), the dialogue box (10)
## and the pause menu (20), so no UI element ever picks up grain.
func _build_grade() -> void:
	if not ResourceLoader.exists(GRADE_SHADER):
		return
	var layer := CanvasLayer.new()
	layer.name = "GradeLayer"
	layer.layer = -1
	add_child(layer)
	var mat := ShaderMaterial.new()
	mat.shader = load(GRADE_SHADER)
	_grade = ColorRect.new()
	_grade.name = "Grade"
	_grade.material = mat
	_grade.color = Color.WHITE
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_grade)
	set_quality(UiSettings.quality())


## Called by UiSettings.apply_quality (group "game_grade"). 0 Low / 1 Med / 2 High.
func set_quality(level: int) -> void:
	if _grade == null:
		return
	var p: Dictionary = GRADE_PRESETS[clampi(level, 0, GRADE_PRESETS.size() - 1)]
	var mat := _grade.material as ShaderMaterial
	for k in p:
		mat.set_shader_parameter(k, p[k])


func _build_health() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 28
	box.offset_top = -78
	box.offset_bottom = -28
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_health_label = UiStyle.label("", 13, Color(0.75, 0.3, 0.25))
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


## Wordless ability readout: one meter per ability node, in a fixed order, each
## filling as its cooldown runs out. Rhaiyn's shared contract says the HUD finds
## the ability nodes by name and reads `cooldown_left` and `COOLDOWN` itself, so
## nothing here needs to know what any individual mechanic does.
const ABILITY_ORDER := ["Combat", "Marking", "Suspend", "Explosion"]
const ABILITY_COLORS := {
	"Combat": Color(0.82, 0.22, 0.18),
	"Marking": Color(0.95, 0.55, 0.15),
	"Suspend": Color(0.35, 0.75, 0.9),
	"Explosion": Color(0.95, 0.82, 0.3),
}


func _build_abilities() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -220
	box.offset_right = -28
	box.offset_top = -104
	box.offset_bottom = -28
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_pip_row = HBoxContainer.new()
	_pip_row.alignment = BoxContainer.ALIGNMENT_END
	_pip_row.add_theme_constant_override("separation", 4)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_pip_row)
	for name in ABILITY_ORDER:
		var stack := Control.new()
		stack.custom_minimum_size = Vector2(192, 10)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(stack)
		var bar := _bar(ABILITY_COLORS[name], Color(0.03, 0.03, 0.03, 0.75))
		bar.max_value = 1.0
		stack.add_child(bar)
		_ability_bars[name] = bar


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
	_update_abilities()
	_update_pips()
	_cross.highlight = _has_target()
	_cross.visible = not over


## The crosshair brightens when Combat could actually land, which replaces the
## old "[E]" prompt with a cue that needs no words.
func _has_target() -> bool:
	var combat: Node = player.get_node_or_null("Combat")
	if combat == null:
		return false
	return player.crosshair_target(combat.call("effective_range")) != null


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
	_health_label.text = "%d" % ceili(hp)
	# Vignette: hit flash plus a slow pulse when health is low.
	var low := 0.0
	if frac < 0.35 and hp > 0.0:
		low = (0.35 - frac) / 0.35 * (0.45 + 0.15 * sin(Time.get_ticks_msec() * 0.006))
	_vignette.modulate.a = clampf(maxf(_hurt * 0.85, low), 0.0, 1.0)


## One mark per required target, so the player can see that the level ends when
## the last of them is gone and not when the Twin alone is. Wordless on purpose:
## the 150-word cap counts labels on the screen, and this needs no label.
func _update_pips() -> void:
	var targets := get_tree().get_nodes_in_group("enemy")
	if _pips_total == 0:
		if targets.is_empty():
			return  # the enemies join the group after the HUD is ready
		_pips_total = targets.size()
		for i in _pips_total:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(10, 10)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pip_row.add_child(pip)
			_pips.append(pip)
	var alive := 0
	for t in targets:
		if is_instance_valid(t) and not t.is_dead():
			alive += 1
	for i in _pips.size():
		var lit := i < alive
		_pips[i].color = Color(0.82, 0.22, 0.18, 0.95) if lit else Color(1, 1, 1, 0.12)


## Each meter reads 1.0 when the ability is ready. Marking also shows how much
## of its mark is left: a live mark drains the same bar back down, so one meter
## carries both facts without a word of text.
func _update_abilities() -> void:
	for name in _ability_bars:
		var node: Node = player.get_node_or_null(name)
		var bar: ProgressBar = _ability_bars[name]
		if node == null:
			bar.visible = false
			continue
		var frac: float = node.call("ready_fraction")
		if name == "Marking" and node.call("has_mark"):
			frac = node.call("duration_fraction")
		bar.value = clampf(frac, 0.0, 1.0)
		bar.modulate.a = 1.0 if frac >= 1.0 else 0.65


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

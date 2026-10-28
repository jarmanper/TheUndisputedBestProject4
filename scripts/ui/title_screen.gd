extends Control
## Title screen for TIMBUK: Second Hand. Layout lives in title_screen.tscn,
## the 3D backdrop in title_backdrop.gd. This script wires the menu, settings,
## UI sounds and the fade transitions.
##
## Settings are stored in user://settings.cfg:
##   [audio] master_volume (0..1 linear)
##   [input] mouse_sensitivity (radians per pixel, read by the player)
##   [video] fullscreen (bool)

const SETTINGS_PATH := "user://settings.cfg"
const BASE_SENSITIVITY := 0.0022  # player.gd default mouse_sensitivity

const CONTROLS := [
	["WASD", "Move"],
	["Shift", "Sprint"],
	["Mouse", "Look"],
	["E", "Interact"],
	["Left mouse", "Fire  (Combat)"],
	["Right mouse", "Mark target  (Marking)"],
	["Q", "Suspend  (Suspend)"],
	["F", "Throw charge  (Explosion)"],
	["Esc", "Pause"],
]

@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
@onready var tick_label: Label = %Tick
@onready var menu: VBoxContainer = %Menu
@onready var controls_panel: PanelContainer = %ControlsPanel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var new_game_btn: Button = %NewGame
@onready var settings_btn: Button = %Settings
@onready var controls_btn: Button = %Controls
@onready var quit_btn: Button = %Quit
@onready var back_btn: Button = %Back
@onready var settings_back_btn: Button = %SettingsBack
@onready var controls_list: GridContainer = %List
@onready var volume_slider: HSlider = %Volume
@onready var volume_value: Label = %VolValue
@onready var sens_slider: HSlider = %Sensitivity
@onready var sens_value: Label = %SensValue
@onready var fullscreen_toggle: CheckButton = %Fullscreen
@onready var fade: ColorRect = %Fade
@onready var ambience: AudioStreamPlayer = %Ambience
@onready var tick_loop: AudioStreamPlayer = %TickLoop
@onready var sting: AudioStreamPlayer = %Sting
@onready var ui_sfx: AudioStreamPlayer = %UiSfx

var _tick := 0
var _leaving := false
var _loading_settings := false
var _hover_snd: AudioStreamWAV
var _confirm_snd: AudioStreamWAV
var _back_snd: AudioStreamWAV
var _cfg := ConfigFile.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	controls_panel.visible = false
	settings_panel.visible = false
	_hover_snd = _make_click(2400.0, 0.035, 0.5)
	_confirm_snd = _make_click(700.0, 0.12, 0.9)
	_back_snd = _make_click(1200.0, 0.07, 0.6)
	_fill_controls()
	_load_settings()

	new_game_btn.pressed.connect(_start_game)
	settings_btn.pressed.connect(_show_panel.bind(settings_panel))
	controls_btn.pressed.connect(_show_panel.bind(controls_panel))
	back_btn.pressed.connect(_show_panel.bind(null))
	settings_back_btn.pressed.connect(_show_panel.bind(null))
	quit_btn.pressed.connect(_quit)
	volume_slider.value_changed.connect(_on_volume_changed)
	sens_slider.value_changed.connect(_on_sens_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)

	for b in [new_game_btn, settings_btn, controls_btn, quit_btn, back_btn, settings_back_btn]:
		_wire_button(b)
	for c in [volume_slider, sens_slider, fullscreen_toggle]:
		# Row label sits just before the control in the 3-column grid.
		var row_label := c.get_parent().get_child(c.get_index() - 1) as Label
		c.focus_entered.connect(func() -> void:
			_play(_hover_snd, 0.8)
			row_label.add_theme_color_override("font_color", Color(1, 0.55, 0.42)))
		c.focus_exited.connect(row_label.remove_theme_color_override.bind("font_color"))
		c.mouse_entered.connect(c.grab_focus)

	# Fade in from black, ambience swells in.
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE)
	ambience.play()
	tick_loop.play()
	_fade_in_audio(ambience, -14.0)
	_fade_in_audio(tick_loop, -20.0)
	_intro_reveal()
	new_game_btn.grab_focus.call_deferred()

	# One "tick" per second: subtitle and second-hand jolt, title stutters now and then.
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if event.is_action_pressed("ui_cancel"):
		if controls_panel.visible or settings_panel.visible:
			_show_panel(null)
			get_viewport().set_input_as_handled()


# --- Menu ---------------------------------------------------------------------

func _wire_button(b: Button) -> void:
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void:
		if not _leaving:
			b.grab_focus())
	b.focus_entered.connect(func() -> void:
		_play(_hover_snd, randf_range(0.9, 1.1))
		b.pivot_offset = b.size * Vector2(0.0, 0.5)
		var tw := b.create_tween()
		tw.tween_property(b, "self_modulate", Color(1.25, 1.1, 1.05), 0.06)
		tw.tween_property(b, "self_modulate", Color.WHITE, 0.25))
	b.pressed.connect(func() -> void:
		var back := b == back_btn or b == settings_back_btn
		_play(_back_snd if back else _confirm_snd, 1.0))


func _show_panel(panel: PanelContainer) -> void:
	var was_settings := settings_panel.visible
	for p in [controls_panel, settings_panel]:
		p.visible = p == panel
	menu.visible = panel == null
	if panel:
		panel.modulate.a = 0.0
		create_tween().tween_property(panel, "modulate:a", 1.0, 0.25)
		if panel == settings_panel:
			volume_slider.grab_focus()
		else:
			back_btn.grab_focus()
	else:
		menu.modulate.a = 0.0
		create_tween().tween_property(menu, "modulate:a", 1.0, 0.25)
		(settings_btn if was_settings else controls_btn).grab_focus()


func _start_game() -> void:
	if _leaving:
		return
	_leaving = true
	_set_menu_enabled(false)
	sting.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fade, "color:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(ambience, "volume_db", -60.0, 1.4)
	tw.tween_property(tick_loop, "volume_db", -60.0, 1.0)
	tw.tween_property(title, "scale", Vector2(1.04, 1.04), 1.4)
	await tw.finished
	GameState.start_new_game()


func _quit() -> void:
	if _leaving:
		return
	_leaving = true
	_set_menu_enabled(false)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fade, "color:a", 1.0, 0.6)
	tw.tween_property(ambience, "volume_db", -60.0, 0.6)
	await tw.finished
	get_tree().quit()


func _set_menu_enabled(on: bool) -> void:
	for b in [new_game_btn, settings_btn, controls_btn, quit_btn]:
		b.disabled = not on
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP


# --- Settings -----------------------------------------------------------------

func _load_settings() -> void:
	_loading_settings = true
	_cfg.load(SETTINGS_PATH)  # Missing file is fine; defaults below.
	var vol: float = _cfg.get_value("audio", "master_volume", 0.8)
	var sens: float = _cfg.get_value("input", "mouse_sensitivity", BASE_SENSITIVITY)
	var fs: bool = _cfg.get_value("video", "fullscreen",
			DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	volume_slider.value = vol
	sens_slider.value = sens / BASE_SENSITIVITY
	fullscreen_toggle.button_pressed = fs
	_apply_volume(vol)
	_update_labels()
	_loading_settings = false


func _save_settings() -> void:
	if _loading_settings:
		return
	_cfg.set_value("audio", "master_volume", volume_slider.value)
	_cfg.set_value("input", "mouse_sensitivity", sens_slider.value * BASE_SENSITIVITY)
	_cfg.set_value("video", "fullscreen", fullscreen_toggle.button_pressed)
	_cfg.save(SETTINGS_PATH)


func _on_volume_changed(v: float) -> void:
	_apply_volume(v)
	_update_labels()
	if not _loading_settings:
		_play(_hover_snd, 1.0)
	_save_settings()


func _on_sens_changed(_v: float) -> void:
	_update_labels()
	_save_settings()


func _on_fullscreen_toggled(on: bool) -> void:
	if not _loading_settings:
		_play(_confirm_snd, 1.2)
		DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()


func _apply_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(bus, v <= 0.001)


func _update_labels() -> void:
	volume_value.text = "%d%%" % roundi(volume_slider.value * 100.0)
	sens_value.text = "%.2fx" % sens_slider.value


# --- Atmosphere ---------------------------------------------------------------

func _intro_reveal() -> void:
	var items: Array[Control] = [title, subtitle]
	for b in menu.get_children():
		items.append(b)
	var delay := 0.6
	for c in items:
		c.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(c, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
		delay += 0.12


func _fade_in_audio(p: AudioStreamPlayer, target_db: float) -> void:
	p.volume_db = -50.0
	create_tween().tween_property(p, "volume_db", target_db, 3.0)


func _on_tick() -> void:
	if _leaving:
		return
	_tick += 1
	tick_label.text = "tick" if _tick % 2 == 1 else "tock"
	var tw := create_tween()
	tw.tween_property(subtitle, "modulate", Color(1.5, 0.35, 0.3, 1), 0.05)
	tw.tween_property(subtitle, "modulate", Color(0.8, 0.8, 0.8, 1), 0.6)
	tick_label.modulate.a = 0.7
	create_tween().tween_property(tick_label, "modulate:a", 0.0, 0.9)
	if randf() < 0.25:
		_flicker_title()


func _flicker_title() -> void:
	var tw := create_tween()
	for i in randi_range(2, 4):
		tw.tween_property(title, "modulate:a", randf_range(0.1, 0.4), 0.04)
		tw.tween_property(title, "modulate:a", 1.0, randf_range(0.03, 0.08))


func _fill_controls() -> void:
	for pair in CONTROLS:
		var key := Label.new()
		key.text = pair[0].to_upper()
		key.add_theme_color_override("font_color", Color(0.95, 0.82, 0.6))
		controls_list.add_child(key)
		var action := Label.new()
		action.text = pair[1]
		controls_list.add_child(action)


func _play(stream: AudioStream, pitch: float) -> void:
	if _loading_settings or not is_inside_tree():
		return
	ui_sfx.stream = stream
	ui_sfx.pitch_scale = pitch
	ui_sfx.play()


## Synthesize a short mechanical click (decaying sine + noise transient) so the
## menu has UI sounds without needing extra audio assets.
func _make_click(freq: float, length: float, noise: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * (6.0 / length))
		var s := sin(TAU * freq * t) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise * exp(-t * 900.0)
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

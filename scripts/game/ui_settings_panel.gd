class_name UiSettingsPanel
extends VBoxContainer
## In-game settings (pause menu): mouse sensitivity, master volume, fullscreen.
## Saves to user://settings.cfg in the same keys the title screen uses and
## applies immediately through UiSettings.

signal back_pressed

var _sens: HSlider
var _sens_value: Label
var _vol: HSlider
var _vol_value: Label
var _fs: CheckButton
var _raw_sensitivity := false   # keep the stored format the title screen chose


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UiStyle.label("SETTINGS", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	_sens = _slider_row("Mouse sensitivity", 0.2, 3.0, 0.05)
	_sens_value = _sens.get_meta("value_label")
	_vol = _slider_row("Master volume", 0.0, 1.0, 0.01)
	_vol_value = _vol.get_meta("value_label")
	_fs = CheckButton.new()
	_fs.text = "Fullscreen"
	_fs.add_theme_font_size_override("font_size", 18)
	add_child(_fs)
	var back := UiStyle.button("Back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	refresh()
	_sens.value_changed.connect(_on_changed.unbind(1))
	_vol.value_changed.connect(_on_changed.unbind(1))
	_fs.toggled.connect(_on_changed.unbind(1))


func _slider_row(text: String, lo: float, hi: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var l := UiStyle.label(text, 18)
	l.custom_minimum_size.x = 190
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(220, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := UiStyle.label("", 18)
	v.custom_minimum_size.x = 56
	row.add_child(v)
	s.set_meta("value_label", v)
	return s


## Reload the controls from disk (called each time the panel opens).
func refresh() -> void:
	var cfg := UiSettings.load_cfg()
	var raw := float(cfg.get_value("input", "mouse_sensitivity", 1.0))
	_raw_sensitivity = raw > 0.0 and raw <= 0.05
	_sens.set_value_no_signal(raw / UiSettings.DEFAULT_SENSITIVITY if _raw_sensitivity else raw)
	_vol.set_value_no_signal(clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0))
	_fs.set_pressed_no_signal(bool(cfg.get_value("video", "fullscreen", false)))
	_update_labels()


func focus_first() -> void:
	_sens.grab_focus()


func _update_labels() -> void:
	_sens_value.text = "%.2fx" % _sens.value
	_vol_value.text = "%d%%" % roundi(_vol.value * 100.0)


func _on_changed() -> void:
	_update_labels()
	var cfg := UiSettings.load_cfg()
	var sens := _sens.value * UiSettings.DEFAULT_SENSITIVITY if _raw_sensitivity else _sens.value
	cfg.set_value("input", "mouse_sensitivity", sens)
	cfg.set_value("audio", "master_volume", _vol.value)
	cfg.set_value("video", "fullscreen", _fs.button_pressed)
	cfg.save(UiSettings.PATH)
	UiSettings.apply(get_tree())

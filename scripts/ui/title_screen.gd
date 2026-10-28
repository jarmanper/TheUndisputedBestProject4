extends Control
## Title screen for TIMBUK: Second Hand. The UI lives in title_screen.tscn;
## this script wires the buttons and runs the "ticking" flicker.

@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
@onready var tick_label: Label = %Tick
@onready var menu: VBoxContainer = %Menu
@onready var controls_panel: PanelContainer = %ControlsPanel
@onready var new_game_btn: Button = %NewGame
@onready var controls_btn: Button = %Controls
@onready var quit_btn: Button = %Quit
@onready var back_btn: Button = %Back
@onready var controls_list: GridContainer = %List

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

var _tick := 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	controls_panel.visible = false
	_fill_controls()
	new_game_btn.pressed.connect(GameState.start_new_game)
	controls_btn.pressed.connect(_show_controls.bind(true))
	back_btn.pressed.connect(_show_controls.bind(false))
	quit_btn.pressed.connect(get_tree().quit)
	new_game_btn.grab_focus()

	# Fade in from black.
	modulate = Color(0, 0, 0, 1)
	create_tween().tween_property(self, "modulate", Color.WHITE, 2.0)

	# One "tick" per second: subtitle and second-hand jolt, title stutters now and then.
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


func _on_tick() -> void:
	_tick += 1
	tick_label.text = "tick" if _tick % 2 == 1 else "tock"
	var tw := create_tween()
	tw.tween_property(subtitle, "modulate", Color(1.5, 0.35, 0.3, 1), 0.05)
	tw.tween_property(subtitle, "modulate", Color(0.8, 0.8, 0.8, 1), 0.6)
	tick_label.modulate.a = 0.7
	create_tween().tween_property(tick_label, "modulate:a", 0.0, 0.9)
	if randf() < 0.3:
		_flicker_title()


func _flicker_title() -> void:
	var tw := create_tween()
	for i in randi_range(2, 4):
		tw.tween_property(title, "modulate:a", randf_range(0.1, 0.4), 0.04)
		tw.tween_property(title, "modulate:a", 1.0, randf_range(0.03, 0.08))


func _show_controls(show_it: bool) -> void:
	controls_panel.visible = show_it
	menu.visible = not show_it
	if show_it:
		back_btn.grab_focus()
	else:
		controls_btn.grab_focus()


func _fill_controls() -> void:
	for pair in CONTROLS:
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
		controls_list.add_child(key)
		var action := Label.new()
		action.text = pair[1]
		controls_list.add_child(action)

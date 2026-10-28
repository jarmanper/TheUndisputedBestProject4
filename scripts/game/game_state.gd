extends Node
## Global story/game state. Registered as the autoload "GameState".
## Other scripts talk to the UI and story through these signals and functions.

signal dialogue_requested(lines: Array)   # Array of {"speaker": String, "text": String}
signal objective_changed(text: String)
signal flag_changed(flag_name: String, value: Variant)
signal player_died
signal game_won

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const GAME_SCENE := "res://scenes/game/main.tscn"
const DEATH_DELAY := 3.0
const ENDING_DELAY := 12.0

var objective: String = ""
var flags: Dictionary = {}
var _game_over := false


func _ready() -> void:
	# Keep running while the tree is paused (pause menu, death screen).
	process_mode = Node.PROCESS_MODE_ALWAYS


## Show one or more dialogue lines. Each line: {"speaker": "...", "text": "..."}.
func say(lines: Array) -> void:
	if lines.is_empty():
		return
	dialogue_requested.emit(lines)


func set_objective(text: String) -> void:
	objective = text
	objective_changed.emit(text)


func set_flag(flag_name: String, value: Variant = true) -> void:
	flags[flag_name] = value
	flag_changed.emit(flag_name, value)
	# The story ends the moment the Twin is stopped.
	if flag_name == "twin_defeated" and bool(value):
		win()


func has_flag(flag_name: String) -> bool:
	return flags.has(flag_name) and bool(flags[flag_name])


## Player died: show the death overlay, then return to the title.
func lose() -> void:
	if _game_over:
		return
	_game_over = true
	player_died.emit()
	await get_tree().create_timer(DEATH_DELAY, true).timeout
	go_to_title()


## Twin defeated: show the ending, then return to the title.
func win() -> void:
	if _game_over:
		return
	_game_over = true
	game_won.emit()
	await get_tree().create_timer(ENDING_DELAY, true).timeout
	go_to_title()


func start_new_game() -> void:
	_reset()
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_title() -> void:
	_reset()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


func _reset() -> void:
	objective = ""
	flags.clear()
	_game_over = false

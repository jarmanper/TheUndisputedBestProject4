extends Node
## Title transitions only. Level outcome and active-gameplay timers live in main.
signal player_died
signal game_won
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const GAME_SCENE := "res://scenes/game/main.tscn"

func start_new_game() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)

func go_to_title() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)

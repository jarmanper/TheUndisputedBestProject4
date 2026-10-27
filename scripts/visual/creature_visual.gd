extends Node3D
## Visual-only animation driver for creature models (no AI, no gameplay).
## Plays `animation` on loop. Teammates can call play_visual("walk") etc.
## from their own scripts. Available: idle, walk, react, twitch.

@export var animation := "idle"
@export var speed := 1.0
## Random start offset so groups of the same creature don't move in sync.
@export var desync := true

var _player: AnimationPlayer


func _ready() -> void:
	_player = find_child("AnimationPlayer", true, false)
	if _player == null:
		return
	for anim_name in _player.get_animation_list():
		var a := _player.get_animation(anim_name)
		a.loop_mode = Animation.LOOP_NONE if anim_name == "react" else Animation.LOOP_LINEAR
	play_visual(animation)
	if desync and _player.current_animation != "":
		_player.seek(randf() * _player.current_animation_length, true)


func play_visual(anim_name: String, blend := 0.25) -> void:
	if _player and _player.has_animation(anim_name):
		_player.play(anim_name, blend, speed)

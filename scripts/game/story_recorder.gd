extends Node3D
## One of Mom's tape recorders. Her lines in scenes/game/story_layer.tscn are
## recordings she left for her child, so each one has a recorder sitting in
## the room where it plays: the voice is something the player finds, not a
## narrator. While idle the record light blinks to catch the eye; when the
## matching StoryTrigger fires, the play key drops, the reels turn and the
## tape hisses for `play_time` seconds.
##
## Scenery only. No words (the lines it "plays" are already counted in the
## story layer), no collision, no interaction, no rule. It reads the trigger's
## "seen_<trigger_id>" flag and never sets anything. Every timer runs in
## _process, so the pause menu freezes it like everything else.

## The StoryTrigger whose lines this tape holds.
@export var trigger_id := ""
## The last tape, in the twin chamber: the battery is gone and it never runs.
@export var dead := false
## How long the reels turn once the recording starts.
@export var play_time := 6.0

const REEL_SPEED := 7.0  # rad/s, about one turn a second
const BLINK_PERIOD := 1.2
const BLINK_ON := 0.3
const KEY_DROP := 0.004

var _left := 0.0
var _t := 0.0

@onready var _reels: Array[Node3D] = [$ReelLeft, $ReelRight]
@onready var _led: MeshInstance3D = $Led
@onready var _glow: OmniLight3D = $Led/Glow
@onready var _key: Node3D = $PlayKey
@onready var _tape: AudioStreamPlayer3D = $Tape
@onready var _clunk: AudioStreamPlayer3D = $Clunk
@onready var _key_rest := _key.position
@onready var _glow_energy := _glow.light_energy


func _ready() -> void:
	add_to_group("story_recorder")
	_t = fmod(absf(global_position.x * 1.7 + global_position.z), BLINK_PERIOD)
	if dead:
		_led.material_override = preload("res://assets/materials/black_cavity.tres")
		_glow.visible = false
		set_process(false)
		return
	var state := get_node_or_null("/root/GameState")
	if state == null or trigger_id == "":
		return
	state.flag_changed.connect(_on_flag_changed)
	if state.has_flag("seen_" + trigger_id):
		play()


func _on_flag_changed(flag_name: String, value: Variant) -> void:
	if flag_name == "seen_" + trigger_id and value:
		play()


func play() -> void:
	if dead:
		return
	_left = play_time
	_key.position = _key_rest + Vector3.DOWN * KEY_DROP
	_clunk.play()
	_tape.play()


func stop() -> void:
	var was_playing := _left > 0.0
	_left = 0.0
	_key.position = _key_rest
	_tape.stop()
	if was_playing:
		_clunk.play()


func is_playing() -> bool:
	return _left > 0.0


func _process(delta: float) -> void:
	_t += delta
	if _left > 0.0:
		for reel in _reels:
			reel.rotate_object_local(Vector3.UP, -REEL_SPEED * delta)
		_glow.light_energy = _glow_energy
		_led.visible = true
		_left -= delta
		if _left <= 0.0:
			stop()
		return
	var lit := fmod(_t, BLINK_PERIOD) < BLINK_ON
	_led.visible = lit
	_glow.light_energy = _glow_energy if lit else 0.0

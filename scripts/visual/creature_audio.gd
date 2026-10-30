extends Node3D
## Creature sound (visual/audio only, no AI): a constant breathing/mechanical
## loop plus, every few seconds, either a non-verbal sound or a spoken line.
## Teammates can call say("mother") or vocalize() from their own code.

## Word budget (AGENTS.md rule 4 / section 4.5). tools/build_scenes.gd fills
## `lines` by globbing every res://assets/audio/voices/<prefix>_*.wav, so the
## generated character scenes reference more spoken lines than the 150-word cap
## allows. The budget is enforced here instead: any line whose file name is not
## listed below is dropped when the creature loads. Keep this list in sync with
## source/audio/voice_lines.txt (the surplus .wav files stay on disk so the
## generated scenes keep valid resource paths -- they are simply never played).
const BUDGETED_LINES := [
	"failed_where_are_you",   # "where are you"    3 words
	"failed_mother",          # "mother"           1 word
	"twin_brother",           # "brother"          1 word
	"twin_tick_tock",         # "tick tock"        2 words
	"twin_you_left_me_here",  # "you left me here" 4 words
]                             # total: 11 words

@export var loop_sound: AudioStream
@export var noises: Array[AudioStream] = []
@export var lines: Array[AudioStream] = []
## Chance that a vocalisation is words instead of a groan/glitch.
@export_range(0.0, 1.0) var word_chance := 0.45
@export var min_gap := 10.0
@export var max_gap := 25.0
@export var loudness_db := 0.0

var _loop: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _timer := 0.0


func _ready() -> void:
	lines = _within_budget(lines)
	_loop = AudioStreamPlayer3D.new()
	_loop.stream = loop_sound
	_loop.bus = "Voices"
	_loop.unit_size = 3.0
	_loop.max_distance = 18.0
	_loop.volume_db = loudness_db - 6.0
	_loop.position = Vector3(0, 1.6, 0)
	add_child(_loop)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "Voices"
	_voice.unit_size = 4.0
	_voice.max_distance = 30.0
	_voice.volume_db = loudness_db
	_voice.position = Vector3(0, 1.65, 0)
	add_child(_voice)
	if loop_sound:
		_loop.play(randf() * 2.0)
	_timer = randf_range(3.0, max_gap)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		vocalize()
		_timer = randf_range(min_gap, max_gap)


## Drop any spoken line that is not in BUDGETED_LINES. A creature left with no
## lines at all (the augmented patient) simply falls back to its noises, which
## vocalize() already handles.
func _within_budget(src: Array[AudioStream]) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for s in src:
		if s == null:
			continue
		var file := s.resource_path.get_file().get_basename()
		for allowed in BUDGETED_LINES:
			if file == allowed or s.resource_path.contains(allowed):
				out.append(s)
				break
	return out


func vocalize() -> void:
	var pool := lines if (randf() < word_chance and not lines.is_empty()) or noises.is_empty() else noises
	if pool.is_empty():
		return
	_voice.stream = pool.pick_random()
	_voice.pitch_scale = randf_range(0.93, 1.05)
	_voice.play()


## Play a specific spoken line by (partial) file name, e.g. say("brother").
func say(name_part: String) -> void:
	for s in lines:
		if s.resource_path.get_file().contains(name_part):
			_voice.stream = s
			_voice.play()
			return

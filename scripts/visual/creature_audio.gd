extends Node3D
## Creature sound (visual/audio only, no AI): a constant breathing/mechanical
## loop plus, every few seconds, either a non-verbal sound or a spoken line.
## Teammates can call say("help_me") or vocalize() from their own code.

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

extends Node
## MARKING (Rhaiyn): RMB tags an enemy for `mark_duration` seconds.
## Marked enemies glow through the dark, get a tracking ring at their feet
## and take double damage. Max `max_marks` at once (oldest is dropped).

@export var mark_duration := 15.0
@export var max_marks := 3
@export var max_range := 40.0
@export var cooldown := 0.4

var marked: Array = []
var _cd := 0.0

@onready var player: TimbukPlayer = get_parent()


func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	marked = marked.filter(func(e): return is_instance_valid(e) and e.is_marked())
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("mark") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _cd <= 0.0:
		_cd = cooldown
		try_mark()


func try_mark() -> void:
	var hit := player.aim(max_range)
	var e: Node = hit.get("collider")
	if e == null or not e.is_in_group("enemy") or e.is_dead():
		return
	marked.erase(e)
	while marked.size() >= max_marks:
		var oldest = marked.pop_front()
		if is_instance_valid(oldest):
			oldest.unmark()
	e.mark(mark_duration)
	marked.append(e)
	var ping := AudioStreamPlayer.new()
	ping.stream = load("res://assets/audio/sfx/tracker_lock.wav")
	ping.bus = "SFX"
	add_child(ping)
	ping.play()
	ping.finished.connect(ping.queue_free)


func count() -> int:
	return marked.size()

extends Node
## MARKING (Rhaiyn): RMB tags an enemy for `mark_duration` seconds.
## Marked enemies glow through the dark, get a tracking ring at their feet
## and take double damage. Max `max_marks` at once (oldest is dropped).

signal marked_enemy(enemy)

const LOCK_SFX := preload("res://assets/audio/sfx/tracker_lock.wav")

@export var mark_duration := 15.0
@export var max_marks := 3
@export var max_range := 40.0
@export var cooldown := 0.4

var marked: Array = []
var _cd := 0.0
var _ping: AudioStreamPlayer

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	_ping = AudioStreamPlayer.new()
	_ping.stream = LOCK_SFX
	_ping.bus = "SFX"
	add_child(_ping)


func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	marked = marked.filter(_still_marked)
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("mark") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _cd <= 0.0:
		_cd = cooldown
		try_mark()


static func _still_marked(e) -> bool:
	return is_instance_valid(e) and e.has_method("is_marked") and e.is_marked() \
		and not (e.has_method("is_dead") and e.is_dead())


## Marks the enemy under the crosshair. Returns true on success.
func try_mark() -> bool:
	var hit := player.aim(max_range)
	var e: Node = _enemy_from(hit.get("collider"))
	if e == null or not e.has_method("mark") or (e.has_method("is_dead") and e.is_dead()):
		return false
	var refresh := marked.has(e)
	marked.erase(e)
	while marked.size() >= max_marks:
		var oldest = marked.pop_front()
		if is_instance_valid(oldest) and oldest.has_method("unmark"):
			oldest.unmark()
	e.mark(mark_duration)
	marked.append(e)
	_ping.pitch_scale = 1.15 if refresh else 1.0
	_ping.play()
	marked_enemy.emit(e)
	return true


## Collider may be the enemy itself or a child (hitbox / mesh body).
static func _enemy_from(c: Node) -> Node:
	while c:
		if c.is_in_group("enemy"):
			return c
		c = c.get_parent()
	return null


func count() -> int:
	return marked.size()

class_name StoryTrigger
extends Area3D
## Invisible box that plays story lines when the player walks into it.
## Lines are written as "Speaker: text". A line with no colon has no speaker.

@export var trigger_id: String = ""
@export var lines: Array[String] = []
@export var objective: String = ""
@export var once := true
## If set, this trigger only fires once that flag is true.
@export var requires_flag: String = ""
## If set, this flag becomes true when the trigger fires.
@export var sets_flag: String = ""

var _fired := false


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if once and _fired:
		return
	if requires_flag != "" and not GameState.has_flag(requires_flag):
		return
	_fired = true
	if trigger_id != "":
		GameState.set_flag("seen_" + trigger_id)
	if not lines.is_empty():
		GameState.say(_parse_lines())
	if objective != "":
		GameState.set_objective(objective)
	if sets_flag != "":
		GameState.set_flag(sets_flag)


func _parse_lines() -> Array:
	var out: Array = []
	for raw in lines:
		var idx := raw.find(":")
		if idx > 0 and idx < 24:
			out.append({"speaker": raw.substr(0, idx).strip_edges(), "text": raw.substr(idx + 1).strip_edges()})
		else:
			out.append({"speaker": "", "text": raw.strip_edges()})
	return out

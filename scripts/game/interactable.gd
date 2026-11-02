class_name Interactable
extends StaticBody3D
## Props that used to be used with E. Team 3's rules allow no interact action,
## no keys and no door unlocking, so interact() is no longer called by anything:
## the keycard and the generator are now set dressing the player finds but does
## not operate, and every DOOR is opened at load by main.gd instead of by a
## flag. The flag plumbing is kept because the prop models and placements hang
## off it, and because the story still happens in these rooms.
##   PICKUP: set dressing (keycard).
##   SWITCH: set dressing (generator).
##   DOOR:   opened by main.gd via open_now() at load.

signal used(player)

enum Kind { PICKUP, SWITCH, DOOR }

@export var kind := Kind.PICKUP
@export var prompt := ""
@export var required_flag := ""
@export var grants_flag := ""
@export var locked_text := "It won't budge."
@export var used_text := ""
@export var objective_after := ""
@export var model_scene: PackedScene
@export var model_offset := Vector3.ZERO
@export var box_size := Vector3(0.5, 0.5, 0.5)
@export var show_box := false
@export var box_material: Material
@export var open_offset := Vector3(0, 3.2, 0)

var done := false
var _poll := 0.0


func _ready() -> void:
	add_to_group("interactable")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	add_child(shape)
	if show_box:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box_size
		mi.mesh = bm
		mi.material_override = box_material
		add_child(mi)
	if model_scene:
		var m: Node3D = model_scene.instantiate()
		m.position = model_offset
		add_child(m)


func _process(delta: float) -> void:
	if kind != Kind.DOOR or done or required_flag == "":
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		if _has(required_flag):
			_open()


func get_prompt() -> String:
	if done:
		return ""
	if kind == Kind.DOOR:
		return "[E] Try door"
	return "[E] " + prompt.left(1).to_upper() + prompt.substr(1)


func interact(player: Node) -> void:
	if done:
		return
	if required_flag != "" and not _has(required_flag):
		_say(locked_text)
		return
	match kind:
		Kind.DOOR:
			_open()
		_:
			done = true
			if grants_flag != "":
				TimbukFx.state_call(get_tree(), "set_flag", [grants_flag])
			if used_text != "":
				_say(used_text)
			if objective_after != "":
				TimbukFx.state_call(get_tree(), "set_objective", [objective_after])
			used.emit(player)
			if kind == Kind.PICKUP:
				queue_free()


## Opens a door immediately, with no tween, so nothing can be standing in a
## closing door or reach it before it moves. Used by main.gd at load.
func open_now() -> void:
	done = true
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	position += open_offset


func _open() -> void:
	done = true
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(self, "position", position + open_offset, 1.5).set_trans(Tween.TRANS_SINE)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = load("res://assets/audio/sfx/blast_door_groan.wav")
	add_child(snd)
	snd.play()
	used.emit(null)


func _has(flag: String) -> bool:
	return bool(TimbukFx.state_call(get_tree(), "has_flag", [flag]))


func _say(text: String) -> void:
	if text == "":
		return
	if TimbukFx.game_state(get_tree()):
		TimbukFx.state_call(get_tree(), "say", [[{"speaker": "", "text": text}]])
	else:
		print(text)

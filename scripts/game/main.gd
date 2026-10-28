extends Node3D
## Game scene glue: makes sure the facility has collision, loads the story
## layer / dialogue box if they exist, and opens the facility's own
## security + blast doors once the keycard is picked up.

const STORY_LAYER := "res://scenes/game/story_layer.tscn"
const DIALOGUE_BOX := "res://scenes/ui/dialogue_box.tscn"

@export var facility_path: NodePath = ^"TimbukFacility"
@export var keycard_path: NodePath = ^"Interactables/Keycard"
## Meshes with an AABB smaller than this (longest side, metres) get no
## generated collision. Only used if the facility has no collision at all.
@export var min_collision_size := 0.6

var _keycard_doors: Array[Node3D] = []
var _doors_open := false
var _poll := 0.0


func _ready() -> void:
	var facility := get_node(facility_path)
	_ensure_collision(facility)
	_hide_duplicate_keycards(facility)
	for n in facility.find_children("SecurityDoor*", "", true, false) + facility.find_children("BlastDoor*", "", true, false):
		_keycard_doors.append(n)
	for path in [STORY_LAYER, DIALOGUE_BOX]:
		if ResourceLoader.exists(path):
			add_child(load(path).instantiate())
	# Fresh run: never start paused, always start with the mouse captured,
	# and apply the title screen's saved settings (sensitivity, volume, fullscreen).
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	UiSettings.apply(get_tree())


func _process(delta: float) -> void:
	if _doors_open:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	if TimbukFx.state_call(get_tree(), "has_flag", ["has_keycard"]):
		_doors_open = true
		for d in _keycard_doors:
			_open_prop_door(d)


func _ensure_collision(facility: Node) -> void:
	var bodies := facility.find_children("*", "StaticBody3D", true, false)
	if bodies.size() > 20:
		print("main: facility has %d static bodies" % bodies.size())
		return
	var n := 0
	for mi in facility.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.get_aabb().get_longest_axis_size() < min_collision_size:
			continue
		mi.create_trimesh_collision()
		n += 1
	print("main: generated trimesh collision for %d meshes" % n)


func _hide_duplicate_keycards(facility: Node) -> void:
	var mine := get_node_or_null(keycard_path) as Node3D
	if mine == null:
		return
	for k in facility.find_children("Keycard*", "", true, false):
		if k is Node3D and k.global_position.distance_to(mine.global_position) < 1.5:
			k.visible = false


func _open_prop_door(d: Node3D) -> void:
	for c in d.find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
	var tw := d.create_tween()
	tw.tween_property(d, "position:y", d.position.y + 3.0, 1.6).set_trans(Tween.TRANS_SINE)

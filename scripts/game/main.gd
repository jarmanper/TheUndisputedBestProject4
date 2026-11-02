extends Node3D
## Game scene glue: makes sure the facility has collision, loads the story
## layer / dialogue box if they exist, and opens the facility's own security +
## blast doors.
## The assignment has no keys, pickups or door unlocking, so every door on the
## required route is simply open from the start. The keycard prop stays in the
## world as set dressing - it is something the player finds, not something the
## player uses.

const STORY_LAYER := "res://scenes/game/story_layer.tscn"
const DIALOGUE_BOX := "res://scenes/ui/dialogue_box.tscn"

@export var facility_path: NodePath = ^"TimbukFacility"
@export var keycard_path: NodePath = ^"Interactables/Keycard"
## Meshes with an AABB smaller than this (longest side, metres) get no
## generated collision. Only used if the facility has no collision at all.
@export var min_collision_size := 0.6



func _ready() -> void:
	var facility := get_node(facility_path)
	_ensure_collision(facility)
	_hide_duplicate_keycards(facility)
	for n in facility.find_children("SecurityDoor*", "", true, false) + facility.find_children("BlastDoor*", "", true, false):
		_open_prop_door(n)
	for path in [STORY_LAYER, DIALOGUE_BOX]:
		if ResourceLoader.exists(path):
			add_child(load(path).instantiate())
	# Fresh run: never start paused, always start with the mouse captured,
	# and apply the title screen's saved settings (sensitivity, volume, fullscreen).
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	UiSettings.apply(get_tree())


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


## Slides a prop door up and takes its collision out of the way for good.
func _open_prop_door(d: Node3D) -> void:
	for c in d.find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
	d.position.y += 3.0

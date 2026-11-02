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

## Every target that has to die for the level to be won. The rules require the
## full set to exist when the level begins, so this is filled once, at load,
## and never added to.
var _required: Array[Node] = []
var _win_pending := false



func _ready() -> void:
	var facility := get_node(facility_path)
	# must happen before the first frame: Compatibility cannot compile the
	# fog shaders the facility ships with
	TimbukCompat.adapt(self)
	_ensure_collision(facility)
	_hide_duplicate_keycards(facility)
	for n in facility.find_children("SecurityDoor*", "", true, false) + facility.find_children("BlastDoor*", "", true, false):
		_open_prop_door(n)
	_open_required_doors()
	for path in [STORY_LAYER, DIALOGUE_BOX]:
		if ResourceLoader.exists(path):
			add_child(load(path).instantiate())
	# Fresh run: never start paused, always start with the mouse captured,
	# and apply the title screen's saved settings (sensitivity, volume, fullscreen).
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	UiSettings.apply(get_tree())
	_register_required_targets()


## The Twin's chamber used to be sealed behind `power_restored`, which came from
## the generator, which needed the keycard. With no interact action none of that
## can be set, which would leave the Twin permanently unreachable and the level
## impossible to win - so every scripted door opens at load.
func _open_required_doors() -> void:
	var opened := 0
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Interactable and node.kind == Interactable.Kind.DOOR:
			node.open_now()
			opened += 1
	print("main: opened %d scripted doors" % opened)


func _register_required_targets() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		_required.append(e)
		e.defeated.connect(_on_target_defeated)
	print("main: %d required targets registered" % _required.size())


func _on_target_defeated(target: Node) -> void:
	_required.erase(target)
	if not _required.is_empty() or _win_pending:
		return
	_win_pending = true
	# The player and the last target can die in the same step, and the rules
	# say loss wins that tie, so let the player's death land before deciding.
	_resolve_win.call_deferred()


func _resolve_win() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.dead:
		return  # loss wins the tie
	TimbukFx.state_call(get_tree(), "win")


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

extends Node3D
## Lifecycle hooks for teammates. Prototype targets have no attacks or damage input.
signal victory
signal loss
const RESTART_DELAY := 2.0
enum Outcome { PLAYING, VICTORY, LOSS }
var outcome := Outcome.PLAYING
var restart_left := 0.0
var required_targets: Array[Target] = []
@onready var player: Player = $Player

func _ready() -> void:
	player.died.connect(_on_player_died)
	for node in get_tree().get_nodes_in_group("targets"):
		var target := node as Target
		required_targets.append(target)
		target.defeated.connect(_on_target_defeated)

func _physics_process(delta: float) -> void:
	if outcome == Outcome.LOSS:
		restart_left -= delta
		if restart_left <= 0.0:
			get_tree().reload_current_scene()

func _on_player_died() -> void:
	# Loss can override victory in the same simulation step.
	outcome = Outcome.LOSS
	restart_left = RESTART_DELAY
	_clear_effects()
	loss.emit()

func _on_target_defeated(_target: Target) -> void:
	if outcome != Outcome.PLAYING or player.hp <= 0:
		return
	for target in required_targets:
		if is_instance_valid(target) and target.is_alive():
			return
	outcome = Outcome.VICTORY
	_clear_effects()
	# Record the win immediately, but let same-step player damage take priority
	# before a listener can load a next level from the victory signal.
	_emit_victory_if_still_won.call_deferred()

func _emit_victory_if_still_won() -> void:
	if outcome == Outcome.VICTORY and player.hp > 0:
		victory.emit()

func _clear_effects() -> void:
	player.get_node("Abilities/Marking").clear_mark()

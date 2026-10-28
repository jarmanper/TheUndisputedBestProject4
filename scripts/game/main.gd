extends Node3D
## Two authored playtest levels; all required targets exist before gameplay.
signal victory
signal loss
enum Outcome { PLAYING, VICTORY, LOSS }
const RESTART_DELAY := 2.0
const NEWSPAPER := "TIMBUK RESEARCH FACILITY SHUT DOWN FOLLOWING UNEXPLAINED DISAPPEARANCES. Officials have yet to release information regarding the missing employees or the experiments conducted inside."
const REPORT := "Experiment 024: Subject has demonstrated an unusual ability to manipulate time. Further testing is required. Similar abilities may be present in the subject's biological relatives."
@export var final_chamber := false
var outcome := Outcome.PLAYING
var restart_left := 0.0
var required_targets: Array[TimbukEnemy] = []
var region: NavigationRegion3D
var _fallbacks: Array[Material] = []
var _transition_pending := false
@onready var player: TimbukPlayer = $Player

func _ready() -> void:
	_load_facility()
	player.died.connect(_on_player_died)
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as TimbukEnemy
		required_targets.append(enemy)
		enemy.died.connect(_on_enemy_died)

func _load_facility() -> void:
	# FogMaterial compiles an unsupported shader upon construction in GL.
	# These process-local cache substitutions never alter generated assets.
	for suffix in ["outdoor", "industrial", "lower", "chamber"]:
		var placeholder := ShaderMaterial.new()
		placeholder.take_over_path("res://assets/materials/fog_%s.tres" % suffix)
		_fallbacks.append(placeholder)
	region = NavigationRegion3D.new()
	region.name = "Navigation"
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.2)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.1)
	add_child(region)
	var facility: Node3D = load("res://scenes/environments/timbuk_facility.tscn").instantiate()
	facility.name = "Facility"
	var keep := ["AreaETwinChamber"] if final_chamber else ["AreaAEntrance", "AreaBResearch", "AreaCContainment"]
	for area in facility.get_node("Areas").get_children():
		if not keep.has(String(area.name)):
			area.free()
	for volume in facility.find_children("*", "FogVolume", true, false):
		volume.free()
	# Required doors are already open, with no interaction or flags.
	for door in facility.find_children("SecurityDoor*", "", true, false) + facility.find_children("BlastDoor*", "", true, false) + facility.find_children("SecurityGate*", "", true, false):
		door.free()
	var world := facility.get_node("WorldEnvironment") as WorldEnvironment
	var environment: Environment = world.environment.duplicate()
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.volumetric_fog_enabled = false
	environment.glow_enabled = false
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_energy = 0.65
	world.environment = environment
	world.camera_attributes = null
	region.add_child(facility)
	if not final_chamber:
		# Lettering is merged into the imported detail mesh. Blank these eight
		# sign areas with visual-only panels; do not edit generated geometry.
		_blank_sign(Vector3(0, 6.45, 7.25), Vector3(16, 2.0, 0.3))
		_blank_sign(Vector3(0, 5.15, 7.25), Vector3(12, 0.7, 0.3))
		_blank_sign(Vector3(-0.8, 3.45, -5.88), Vector3(5.6, 1.2, 0.3))
		_blank_sign(Vector3(-8.05, 2.6, -1.6), Vector3(0.3, 0.6, 2.4))
		_blank_sign(Vector3(1.47, 2.2, -9.8), Vector3(0.3, 0.5, 3.5))
		_blank_sign(Vector3(-1.47, 2.2, -22.6), Vector3(0.3, 0.5, 3.0))
		_blank_sign(Vector3(0, 6.0, -30.62), Vector3(10, 1.0, 0.3))
		_blank_sign(Vector3(0, 3.6, -49.98), Vector3(5, 0.6, 0.3))
	if final_chamber:
		_seal(Vector3(14.7, -4.5, -92.15), Vector3(2.1, 3.2, 0.3))
		_seal(Vector3(1.55, -4.5, -105.2), Vector3(0.3, 3.2, 2.0))
	else:
		_seal(Vector3(0, 1.5, 6.15), Vector3(3.3, 3.2, 0.3))
		_seal(Vector3(-1.65, 1.5, -13.3), Vector3(0.3, 3.2, 2))
		_seal(Vector3(1.65, 1.5, -21.3), Vector3(0.3, 3.2, 2.3))
		_seal(Vector3(-11.15, 1.5, -34), Vector3(0.3, 3.2, 2))
		_seal(Vector3(11.15, 1.5, -46.8), Vector3(0.3, 3.2, 2))
		_seal(Vector3(0, 1.5, -50.45), Vector3(2.7, 3.2, 0.3))
		_document(NEWSPAPER, Vector3(1.8, 1.6, 1.3))
		_document(REPORT, Vector3(0.0, 1.7, -17.5))
	_build_navigation()

func _seal(at: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.position = at
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	wall.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = load("res://assets/materials/painted_metal.tres")
	wall.add_child(mesh)
	region.add_child(wall)

func _blank_sign(at: Vector3, size: Vector3) -> void:
	var panel := MeshInstance3D.new()
	panel.name = "BlankSign"
	var box := BoxMesh.new()
	box.size = size
	panel.mesh = box
	panel.material_override = load("res://assets/materials/painted_metal.tres")
	panel.position = at
	region.add_child(panel, true)

func _document(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 34
	label.pixel_size = 0.003
	label.outline_size = 5
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = 580
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _build_navigation() -> void:
	var path := "res://scenes/game/nav_final.tres" if final_chamber else "res://scenes/game/nav_main.tres"
	if ResourceLoader.exists(path):
		region.navigation_mesh = load(path)
		return
	var mesh := NavigationMesh.new()
	mesh.agent_height = 2.2
	mesh.agent_radius = 0.4
	mesh.cell_size = 0.2
	mesh.cell_height = 0.1
	mesh.agent_max_climb = 0.3
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.filter_baking_aabb = AABB(Vector3(1, -6.2, -119), Vector3(28, 4, 27)) if final_chamber else AABB(Vector3(-16.5, -0.2, -50.5), Vector3(39, 3, 57))
	region.navigation_mesh = mesh
	region.bake_navigation_mesh(false)

func _on_player_died() -> void:
	outcome = Outcome.LOSS
	restart_left = RESTART_DELAY
	_clear_effects()
	loss.emit()

func _on_enemy_died(_enemy: TimbukEnemy) -> void:
	if outcome != Outcome.PLAYING or player.dead:
		return
	for target in required_targets:
		if not target.is_dead():
			return
	outcome = Outcome.VICTORY
	_clear_effects()
	# Loss in the same simulation step overrides notification/progression.
	_complete_win.call_deferred()

func _complete_win() -> void:
	if outcome != Outcome.VICTORY or player.dead:
		return
	victory.emit()
	_transition_pending = true

func _physics_process(delta: float) -> void:
	if outcome == Outcome.LOSS:
		restart_left -= delta
		if restart_left < 0.000001:
			set_physics_process(false)
			get_tree().reload_current_scene()
	elif _transition_pending:
		_transition_pending = false
		# A visual-only level transition, never a new player action.
		if final_chamber:
			GameState.game_won.emit()
		else:
			get_tree().change_scene_to_file("res://scenes/game/final_chamber.tscn")

func _clear_effects() -> void:
	player.get_node("Marking").clear_mark()
	player.get_node("Suspend").end_suspension()

extends Node3D
## Instances Jarman's map unchanged, adapting unsupported visuals in memory.
@export_file("*.tscn") var scene_path := "res://scenes/environments/timbuk_facility.tscn"
var _compatibility_materials: Array[Material] = []

func _ready() -> void:
	var compatibility: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if DisplayServer.get_name() == "headless":
		compatibility = ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility"
	if compatibility:
		# Constructing FogMaterial compiles a fog shader that OpenGL rejects,
		# even before a FogVolume enters the tree. Supply inert cached materials
		# for these four visual-only resources before loading the original map.
		# take_over_path changes this process's resource cache, never disk files.
		for suffix in ["outdoor", "industrial", "lower", "chamber"]:
			var placeholder := ShaderMaterial.new()
			placeholder.take_over_path("res://assets/materials/fog_%s.tres" % suffix)
			_compatibility_materials.append(placeholder)
	var graphics: Node3D = load(scene_path).instantiate()
	graphics.name = "Graphics"
	if compatibility:
		for volume in graphics.find_children("*", "FogVolume", true, false):
			volume.free()
		var world_environment := graphics.get_node("WorldEnvironment") as WorldEnvironment
		var environment: Environment = world_environment.environment.duplicate()
		environment.ssao_enabled = false
		environment.ssil_enabled = false
		environment.volumetric_fog_enabled = false
		environment.glow_enabled = false
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		# Compatibility has no auto-exposure. Keep existing lights/sky and give
		# the ambient fill a fixed readable level instead of exposure adaptation.
		environment.ambient_light_energy = 0.65
		world_environment.environment = environment
		world_environment.camera_attributes = null
	add_child(graphics)

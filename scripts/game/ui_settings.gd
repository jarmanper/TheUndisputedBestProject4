class_name UiSettings
extends RefCounted
## Reads user://settings.cfg (written by the title screen) and applies it.
##   [input] mouse_sensitivity  - either a raw radians-per-pixel value (<= 0.05)
##                                or a multiplier of the player's default (1.0 = default)
##   [audio] master_volume      - linear 0..1
##   [video] fullscreen         - bool
##   [video] quality            - 0 Low / 1 Medium / 2 High (see apply_quality)
##
## Quality is the performance safety valve for the classroom playtest. The
## project defaults in project.godot [rendering] are the High preset; Medium and
## Low walk the expensive parts back at runtime through the Viewport and
## RenderingServer, and switch off volumetric fog on the WorldEnvironment.

const PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.0022

enum Quality { LOW, MEDIUM, HIGH }

const QUALITY_NAMES := ["Low", "Medium", "High"]
## Medium, not High: the grading machine is unknown and High costs 13 ms a
## frame. A grader who sees a stutter never changes the setting.
const DEFAULT_QUALITY := Quality.MEDIUM


static func load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(PATH):
		cfg.load(PATH)
	return cfg


## Converts the stored value to radians per pixel.
static func mouse_sensitivity(cfg: ConfigFile = null) -> float:
	if cfg == null:
		cfg = load_cfg()
	var v := float(cfg.get_value("input", "mouse_sensitivity", DEFAULT_SENSITIVITY))
	if v <= 0.0:
		return DEFAULT_SENSITIVITY
	if v > 0.05:
		return DEFAULT_SENSITIVITY * v
	return v


## 0 Low / 1 Medium / 2 High.
static func quality(cfg: ConfigFile = null) -> int:
	if cfg == null:
		cfg = load_cfg()
	return clampi(int(cfg.get_value("video", "quality", DEFAULT_QUALITY)), 0, 2)


## Applies audio + video settings, and mouse sensitivity to the player (if any).
static func apply(tree: SceneTree) -> void:
	var cfg := load_cfg()
	var vol := clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.0001)))
		AudioServer.set_bus_mute(bus, vol <= 0.0001)
	if DisplayServer.get_name() != "headless":
		var fs := bool(cfg.get_value("video", "fullscreen", false))
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
		var cur := DisplayServer.window_get_mode()
		var cur_fs := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fs != cur_fs:
			DisplayServer.window_set_mode(want)
	apply_quality(tree, quality(cfg))
	var player := tree.get_first_node_in_group("player")
	if player and "mouse_sensitivity" in player:
		player.mouse_sensitivity = mouse_sensitivity(cfg)


## Retunes the expensive renderer settings for the chosen quality level.
## Safe to call every time the setting changes; nothing here is a gameplay value.
static func apply_quality(tree: SceneTree, level: int) -> void:
	level = clampi(level, 0, 2)
	var vp := tree.root as Viewport
	if vp:
		match level:
			Quality.LOW:
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.use_taa = false
				# TAA is off, so FXAA is now worth its (small) cost for edges.
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
				vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
				vp.positional_shadow_atlas_size = 2048
				vp.use_debanding = false
			Quality.MEDIUM:
				vp.msaa_3d = Viewport.MSAA_2X
				vp.use_taa = true
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
				vp.positional_shadow_atlas_size = 4096
				vp.use_debanding = true
			_:
				vp.msaa_3d = Viewport.MSAA_4X
				vp.use_taa = true
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
				vp.positional_shadow_atlas_size = 8192
				vp.use_debanding = true

	var shadow: int = [RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH][level]
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow)
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow)

	# Screen-space AO / indirect light. half_size roughly halves their cost.
	var ao_q: int = [RenderingServer.ENV_SSAO_QUALITY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		RenderingServer.ENV_SSAO_QUALITY_HIGH][level]
	var il_q: int = [RenderingServer.ENV_SSIL_QUALITY_LOW,
		RenderingServer.ENV_SSIL_QUALITY_LOW,
		RenderingServer.ENV_SSIL_QUALITY_HIGH][level]
	var half := level < Quality.HIGH
	RenderingServer.environment_set_ssao_quality(ao_q, half,
		float(ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target", 0.5)),
		int(ProjectSettings.get_setting("rendering/environment/ssao/blur_passes", 2)),
		float(ProjectSettings.get_setting("rendering/environment/ssao/fadeout_from", 50.0)),
		float(ProjectSettings.get_setting("rendering/environment/ssao/fadeout_to", 300.0)))
	RenderingServer.environment_set_ssil_quality(il_q, half,
		float(ProjectSettings.get_setting("rendering/environment/ssil/adaptive_target", 0.5)),
		int(ProjectSettings.get_setting("rendering/environment/ssil/blur_passes", 4)),
		float(ProjectSettings.get_setting("rendering/environment/ssil/fadeout_from", 50.0)),
		float(ProjectSettings.get_setting("rendering/environment/ssil/fadeout_to", 300.0)))

	# Volumetric fog is the single most expensive thing in the scene, and SSIL
	# is the second. Low drops both; the room fog volumes stay, so the areas
	# still read as hazy, just without the light shafts.
	for we in _world_environments(tree):
		var env: Environment = we.environment
		if env == null:
			continue
		env.volumetric_fog_enabled = level > Quality.LOW
		env.ssil_enabled = level > Quality.LOW
		env.ssao_enabled = true
		# Screen-space reflections: the wet-floor cue. Applied here as well as in
		# tools/build_scenes.gd so it is correct even against an environment
		# resource generated before SSR was turned back on.
		env.ssr_enabled = level > Quality.LOW
		env.ssr_max_steps = 32
		env.ssr_fade_in = 0.3

	# Cinematic grade (assets/shaders/game_grade.gdshader), if it is in the tree.
	for node in tree.get_nodes_in_group("game_grade"):
		if node.has_method("set_quality"):
			node.set_quality(level)


static func _world_environments(tree: SceneTree) -> Array:
	var scene := tree.current_scene
	if scene == null:
		return []
	var found := scene.find_children("*", "WorldEnvironment", true, false)
	if scene is WorldEnvironment:
		found.append(scene)
	return found

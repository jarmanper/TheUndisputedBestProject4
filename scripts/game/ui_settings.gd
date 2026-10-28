class_name UiSettings
extends RefCounted
## Reads user://settings.cfg (written by the title screen) and applies it.
##   [input] mouse_sensitivity  - either a raw radians-per-pixel value (<= 0.05)
##                                or a multiplier of the player's default (1.0 = default)
##   [audio] master_volume      - linear 0..1
##   [video] fullscreen         - bool

const PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.0022


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
	var player := tree.get_first_node_in_group("player")
	if player and "mouse_sensitivity" in player:
		player.mouse_sensitivity = mouse_sensitivity(cfg)

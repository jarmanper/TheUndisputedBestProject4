extends Control
## Loading screen shown between the title screen and the game.
##
## WHY THIS EXISTS
## `get_tree().change_scene_to_file("res://scenes/game/main.tscn")` loads the
## whole facility in one blocking call. Measured on a native Windows build,
## headless, with a warm cache, that call takes about 22-30 seconds (490
## meshes, 2044 collision shapes, 129 textures, 80 materials, 69 prop types).
## The Web export is single-threaded WebAssembly, so the same call freezes the
## browser tab for minutes with nothing on screen. Two Oct-28 playtesters hit
## exactly that and reported the game "hangs after pressing New Game".
##
## WHAT IT DOES INSTEAD
## It walks the asset library one file at a time, spending a fixed slice of
## each frame on loading and giving the frame back to the engine in between.
## Everything lands in the resource cache, so the final `change_scene_to_file`
## is effectively free (measured: 0 ms once its dependencies are warm). The
## total wait is the same, but the page keeps painting and the bar keeps
## moving, which is the difference between "slow" and "broken".
##
## Threads are deliberately off in the Web export preset: a threaded Godot 4
## build needs SharedArrayBuffer, which needs COOP/COEP response headers, and
## GitHub Pages cannot set response headers. So `load_threaded_request` is not
## an option here - this frame-sliced loader is.

const GAME_SCENE := "res://scenes/game/main.tscn"
const SETTINGS_PATH := "user://settings.cfg"

## Folders walked before the game scene, in the order they are needed.
## Each entry is [folder, [extensions]]. Missing folders are skipped.
const STAGES: Array = [
	["res://assets/textures", [".png"]],
	["res://assets/materials", [".tres"]],
	["res://scenes/props", [".tscn"]],
	["res://scenes/characters", [".tscn"]],
	["res://scenes/effects", [".tscn"]],
	["res://scenes/environments", [".tscn"]],
]

## Scenes main.gd and the boss pull in at runtime rather than through main.tscn.
## Warming them here keeps the first dialogue and the twin reveal from
## stuttering mid-game.
const EXTRA := [
	"res://scenes/game/story_layer.tscn",
	"res://scenes/ui/dialogue_box.tscn",
	"res://scenes/cinematics/twin_reveal.tscn",
]

## Milliseconds of loading per frame. Small enough that the browser keeps
## repainting, large enough that per-frame overhead stays negligible.
const SLICE_MS := 24

@onready var bar: ColorRect = %BarFill
@onready var bar_track: Control = %BarTrack
@onready var percent: Label = %Percent
@onready var hint: Label = %Hint
@onready var tick: Label = %Tick

# Loaded resources are held here so the resource cache cannot drop them before
# the game scene asks for them.
var _keep: Array = []
var _tick := 0
var _reported := -1
var _start_ms := 0


func _ready() -> void:
	# The game captures the mouse itself once it is running.
	print("loading: screen up")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_web_quality_default()
	percent.text = "0%"
	bar.size.x = 0.0
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_on_tick)
	add_child(t)
	_run.call_deferred()


func _on_tick() -> void:
	_tick += 1
	tick.text = "'" if _tick % 2 == 0 else "."


## The Web export runs the Compatibility (WebGL 2) renderer in a single thread.
## The project's [rendering] defaults are tuned for a desktop GPU, and several
## of them (TAA, SSIL, volumetric fog) are not even supported there - the
## engine logs "TAA is only available when using the Forward+ renderer".
## UiSettings already has a Low preset, so point the web build at it unless the
## player has chosen a level themselves.
func _web_quality_default() -> void:
	if not OS.has_feature("web"):
		return
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(SETTINGS_PATH):
		cfg.load(SETTINGS_PATH)
	if cfg.has_section_key("video", "quality"):
		return
	cfg.set_value("video", "quality", 0)  # UiSettings.Quality.LOW
	cfg.save(SETTINGS_PATH)


func _run() -> void:
	_start_ms = Time.get_ticks_msec()
	# Two frames so the screen is actually painted before any loading starts.
	await get_tree().process_frame
	await get_tree().process_frame

	var files := _collect()
	var total := files.size() + 1  # +1 for the game scene itself
	var done := 0
	var budget := Time.get_ticks_msec() + SLICE_MS

	for path in files:
		# ResourceLoader.exists() keeps a stale folder listing from erroring out.
		if ResourceLoader.exists(path):
			var res := ResourceLoader.load(path)
			if res != null:
				_keep.append(res)
		done += 1
		if Time.get_ticks_msec() >= budget:
			_show(float(done) / float(total))
			await get_tree().process_frame
			budget = Time.get_ticks_msec() + SLICE_MS

	_show(float(done) / float(total))
	await get_tree().process_frame

	# Every dependency is warm by now, so this is the cheap part.
	var scene := ResourceLoader.load(GAME_SCENE)
	_show(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_keep.clear()
	if scene is PackedScene:
		get_tree().change_scene_to_packed(scene)
	else:
		push_error("loading_screen: could not load %s" % GAME_SCENE)
		get_tree().change_scene_to_file(GAME_SCENE)


func _show(fraction: float) -> void:
	fraction = clampf(fraction, 0.0, 1.0)
	bar.size.x = bar_track.size.x * fraction
	var whole := roundi(fraction * 100.0)
	percent.text = "%d%%" % whole
	# One line per 10%: the only way to see how a browser build is doing.
	var decile := whole / 10
	if decile > _reported:
		_reported = decile
		print("loading: %3d%%  %.1f s" % [whole, (Time.get_ticks_msec() - _start_ms) / 1000.0])


## Lists every resource under STAGES. Exported builds keep the original
## res:// paths next to a ".import" or ".remap" stub, so strip those suffixes
## and load by the source path - ResourceLoader follows the stub.
func _collect() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for stage in STAGES:
		var folder: String = stage[0]
		var exts: Array = stage[1]
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for raw in dir.get_files():
			var name := raw
			for stub in [".import", ".remap"]:
				if name.ends_with(stub):
					name = name.substr(0, name.length() - stub.length())
			var matched := false
			for e in exts:
				if name.ends_with(e):
					matched = true
			if not matched:
				continue
			var path := folder + "/" + name
			if seen.has(path):
				continue
			seen[path] = true
			out.append(path)
	for path in EXTRA:
		if not seen.has(path):
			seen[path] = true
			out.append(path)
	return out

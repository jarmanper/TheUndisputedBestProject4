extends SceneTree
## Screenshot the real first-person view so the gun can be judged by eye.
##   godot --path . --resolution 1280x720 --script tests/viewmodel_shot.gd
## Writes user://viewmodel.png

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(scene)
	for i in 70:
		await process_frame
	var player: Node = scene.get_node_or_null("Player")
	var hud: Node = scene.get_node_or_null("HUD")
	if hud and hud.has_method("set_paused"):
		hud.set_paused(false)
	paused = false
	# stand in the lobby looking down the room
	if player:
		player.global_position = Vector3(0, 1.0, 6.0)
		player.rotation = Vector3.ZERO
		player.head.rotation = Vector3.ZERO
	for i in 40:
		await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://viewmodel.png"
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
	quit(0)

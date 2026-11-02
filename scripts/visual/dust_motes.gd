extends GPUParticles3D
## Ambient dust hanging in a room's air. Visual only -- no collision, no logic.
##
## Placed automatically by tools/build_scenes.gd, one per ROOM__ marker that is
## big enough to be worth it, sized to the room.
##
## The node joins the "game_grade" group so the existing quality switch in
## scripts/game/ui_settings.gd drives it (that switch already calls
## set_quality() on every node in that group). Low turns the dust off entirely,
## Medium thins it out. Nothing here is a gameplay value.

func _ready() -> void:
	add_to_group("game_grade")
	# Read it once ourselves too, in case the scene is loaded after
	# UiSettings.apply() has already run (the inspection and capture scenes
	# never call it at all, and then this is the Medium default).
	set_quality(UiSettings.quality())


func set_quality(level: int) -> void:
	level = clampi(level, 0, 2)
	var on := level > 0
	visible = on
	emitting = on
	amount_ratio = [0.0, 0.55, 1.0][level]

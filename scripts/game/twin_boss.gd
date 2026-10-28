extends TimbukEnemy
## The Twin is visually distinct; all HP, speed and attack numbers are identical.
func _ready() -> void:
	super()
	add_to_group("boss")

func _play(animation: String) -> void:
	super("walk_slow" if animation == "walk" else animation)


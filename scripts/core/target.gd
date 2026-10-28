class_name Target
extends CharacterBody3D
## Common target data only. Rickey supplies movement, navigation and attacks.
signal defeated(target: Target)
signal mark_changed(active: bool)

const MAX_HP := 100
var hp := MAX_HP
var marked := false:
	set(value):
		var next := value and is_alive()
		if marked != next:
			marked = next
			mark_changed.emit(marked)
var suspended := false:
	set(value):
		suspended = value and is_alive()

@onready var body_collider: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("targets")

func center() -> Vector3:
	return body_collider.global_position

func is_alive() -> bool:
	return hp > 0

func apply_damage(amount: int) -> void:
	if not is_alive() or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	if hp == 0:
		marked = false
		suspended = false
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		body_collider.set_deferred("disabled", true)
		set_physics_process(false)
		set_process(false)
		# Also stop visual/audio child processing on a defeated wrapper.
		process_mode = Node.PROCESS_MODE_DISABLED
		hide()
		defeated.emit(self)

extends Control
## Wordless HUD. Future ability nodes only need cooldown_left and COOLDOWN.
const ABILITY_NAMES := ["Combat", "Marking", "Suspend", "Explosion"]
const ABILITY_COLORS := [Color.CORAL, Color.ORANGE, Color.SKY_BLUE, Color.MEDIUM_PURPLE]
@export var player_path: NodePath
@onready var player: Player = get_node(player_path) as Player

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var middle := size * 0.5
	draw_circle(middle, 2.0, Color.WHITE)
	for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(middle + offset * 6.0, middle + offset * 10.0, Color.WHITE, 1.5)
	var health_origin := Vector2(28, size.y - 48)
	draw_rect(Rect2(health_origin, Vector2(180, 12)), Color(0.03, 0.04, 0.05, 0.9))
	draw_rect(Rect2(health_origin, Vector2(180 * float(player.hp) / Player.MAX_HP, 12)), Color(0.3, 0.85, 0.65))
	# A heart beside the bar; four distinct geometric icons require no words.
	draw_circle(health_origin + Vector2(4, -12), 4, Color(0.3, 0.85, 0.65))
	draw_circle(health_origin + Vector2(10, -12), 4, Color(0.3, 0.85, 0.65))
	draw_colored_polygon(PackedVector2Array([health_origin + Vector2(0, -11), health_origin + Vector2(14, -11), health_origin + Vector2(7, -3)]), Color(0.3, 0.85, 0.65))
	for i in ABILITY_NAMES.size():
		var point := Vector2(size.x - 200 + i * 48, size.y - 42)
		var ability := player.get_node_or_null("Abilities/" + ABILITY_NAMES[i])
		var color: Color = ABILITY_COLORS[i] if ability != null else Color(0.25, 0.28, 0.32)
		draw_circle(point, 17, Color(0.03, 0.04, 0.05, 0.9))
		match i:
			0: draw_line(point + Vector2(-5, 5), point + Vector2(5, -5), color, 3)
			1:
				draw_arc(point, 7, 0, TAU, 24, color, 2)
				draw_circle(point, 2, color)
			2: draw_rect(Rect2(point - Vector2(5, 6), Vector2(10, 12)), color, false, 2)
			3: draw_colored_polygon(PackedVector2Array([point + Vector2(0, -8), point + Vector2(7, 5), point + Vector2(-7, 5)]), color)
		if ability != null:
			var fraction := 1.0 - clampf(float(ability.cooldown_left) / float(ability.get("COOLDOWN")), 0.0, 1.0)
			draw_arc(point, 17, -PI * 0.5, -PI * 0.5 + TAU * fraction, 48, color, 3)

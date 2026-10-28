class_name UiCrosshair
extends Control
## Four-line crosshair that kicks outward when firing and settles back,
## plus an X hit marker (white for a body hit, red for a headshot).

const GAP := 5.0
const LEN := 8.0
const MAX_SPREAD := 18.0

var spread := 0.0
var highlight := false   # brighter when aiming at something usable
var _hit_t := 0.0
var _hit_head := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(80, 80)


func kick(amount := 1.0) -> void:
	spread = minf(MAX_SPREAD, spread + 9.0 * amount)
	queue_redraw()


func hit(headshot: bool) -> void:
	_hit_t = 0.35 if headshot else 0.25
	_hit_head = headshot
	queue_redraw()


func _process(delta: float) -> void:
	if spread > 0.01 or _hit_t > 0.0:
		spread = lerpf(spread, 0.0, 1.0 - exp(-delta * 10.0))
		if spread < 0.05:
			spread = 0.0
		_hit_t = maxf(0.0, _hit_t - delta)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.9 if highlight else 0.7)
	var shadow := Color(0, 0, 0, 0.5)
	var g := GAP + spread
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a: Vector2 = c + d * g
		var b: Vector2 = c + d * (g + LEN)
		draw_line(a + Vector2(1, 1), b + Vector2(1, 1), shadow, 2.0)
		draw_line(a, b, col, 2.0)
	draw_circle(c, 1.2, col)
	if _hit_t > 0.0:
		var t := _hit_t / (0.35 if _hit_head else 0.25)
		var hc := Color(1, 0.15, 0.1, t) if _hit_head else Color(1, 1, 1, t)
		var r0 := 7.0 + (1.0 - t) * 3.0
		var r1 := r0 + (9.0 if _hit_head else 7.0)
		var w := 3.0 if _hit_head else 2.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			draw_line(c + n * r0, c + n * r1, hc, w)

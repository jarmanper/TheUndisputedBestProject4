extends Light3D
## Visual-only light animation: random fluorescent flicker and/or a slow
## emergency pulse. No gameplay logic. Set from the facility builder.

## 0 = steady, 1 = constantly failing tube.
@export_range(0.0, 1.0) var flicker := 0.0
## Pulses per second for emergency beacons (0 = off).
@export var pulse := 0.0

var _base := 1.0
var _t := 0.0
var _off_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_base = light_energy
	_rng.seed = hash(global_position)
	_t = _rng.randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	var e := _base
	if pulse > 0.0:
		var s := 0.5 + 0.5 * sin(_t * pulse * TAU)
		e *= 0.15 + 0.85 * s * s
	if flicker > 0.0:
		if _off_timer > 0.0:
			_off_timer -= delta
			e *= 0.04
		elif _rng.randf() < flicker * delta * 3.0:
			_off_timer = _rng.randf_range(0.03, 0.12 + 0.5 * flicker)
		else:
			e *= 1.0 - flicker * 0.15 * _rng.randf()
	light_energy = e

## Procedural mechanical gun sounds (dry-fire click, mag out/in, slide rack).
## The project has no dedicated clips for these, so they are synthesised once
## into AudioStreamWAVs and cached.

const RATE := 22050
static var _cache := {}


static func get_stream(kind: String) -> AudioStreamWAV:
	if not _cache.has(kind):
		_cache[kind] = _build(kind)
	return _cache[kind]


static func _build(kind: String) -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	match kind:
		"dry":
			_click(buf, 0.0, 0.03, 3200.0, 0.9, 260.0)
			_click(buf, 0.012, 0.025, 1500.0, 0.5, 300.0)
		"mag_out":
			_click(buf, 0.0, 0.05, 900.0, 0.7, 120.0)
			_click(buf, 0.03, 0.08, 420.0, 0.4, 60.0)
		"mag_in":
			_click(buf, 0.0, 0.06, 600.0, 1.0, 90.0)
			_click(buf, 0.02, 0.04, 2400.0, 0.6, 200.0)
		"rack":
			_click(buf, 0.0, 0.05, 1800.0, 0.8, 140.0)
			_click(buf, 0.09, 0.06, 1200.0, 1.0, 120.0)
			_click(buf, 0.10, 0.03, 3600.0, 0.5, 260.0)
		_:
			_click(buf, 0.0, 0.03, 2000.0, 0.8, 200.0)
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Adds a decaying metallic click: filtered noise + a damped tone.
static func _click(buf: PackedFloat32Array, start: float, length: float, freq: float, gain: float, decay: float) -> void:
	var s0 := int(start * RATE)
	var n := int(length * RATE)
	if buf.size() < s0 + n:
		buf.resize(s0 + n)
	var lp := 0.0
	var a := clampf(freq / RATE * 2.0, 0.02, 0.9)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay)
		lp += a * (randf_range(-1.0, 1.0) - lp)
		var tone := sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 2.71 * t) * 0.25
		buf[s0 + i] += (lp * 0.8 + tone * 0.5) * env * gain

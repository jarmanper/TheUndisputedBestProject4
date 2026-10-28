extends Node3D
## First-person pistol viewmodel: renders the gun "in front" of the world
## (BaseMaterial3D z-clip scale, so it never clips into walls), and animates
## mouse-look sway, walk bob, recoil kick and the reload motion.
## Combat calls kick() and play_reload(time). Animation lives on the "Pivot"
## child so this node's transform (set in main.tscn) stays the rest pose.

@export var z_clip_scale := 0.08
@export var sway_amount := 0.0009
@export var sway_max := 0.06
@export var sway_smooth := 9.0
@export var bob_amount := Vector2(0.012, 0.009)
@export var bob_speed := 1.9
@export var recoil_back := 0.055
@export var recoil_pitch := 0.22

@onready var pivot: Node3D = $Pivot

var _player: CharacterBody3D
var _mouse := Vector2.ZERO
var _sway := Vector2.ZERO
var _bob_t := 0.0
var _bob_w := 0.0
var _recoil := 0.0  # 0..1, decays
var _recoil_roll := 0.0
var _reload_tw: Tween
var _reload_pos := Vector3.ZERO
var _reload_rot := Vector3.ZERO


func _ready() -> void:
	var n: Node = get_parent()
	while n and not (n is CharacterBody3D):
		n = n.get_parent()
	_player = n as CharacterBody3D
	for m in find_children("*", "MeshInstance3D", true, false):
		_make_viewmodel(m)


func _make_viewmodel(m: MeshInstance3D) -> void:
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m.mesh == null:
		return
	for i in m.mesh.get_surface_count():
		var src := m.get_active_material(i) as BaseMaterial3D
		if src == null:
			continue
		var mat := src.duplicate() as BaseMaterial3D
		mat.use_z_clip_scale = true
		mat.z_clip_scale = z_clip_scale
		m.set_surface_override_material(i, mat)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += event.relative


func _process(delta: float) -> void:
	# --- sway: gun lags behind the look direction
	var target := Vector2(
		clampf(-_mouse.x * sway_amount, -sway_max, sway_max),
		clampf(_mouse.y * sway_amount, -sway_max, sway_max))
	_mouse = Vector2.ZERO
	_sway = _sway.lerp(target, 1.0 - exp(-sway_smooth * delta))

	# --- walk bob
	var speed := 0.0
	var grounded := true
	if _player:
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
		grounded = _player.is_on_floor()
	var moving := grounded and speed > 0.4
	_bob_w = move_toward(_bob_w, clampf(speed / 3.2, 0.0, 1.6) if moving else 0.0, delta * 4.0)
	_bob_t += delta * bob_speed * TAU * clampf(speed / 3.2, 0.6, 1.5) if moving else delta * 0.6
	var bob := Vector3(
		sin(_bob_t) * bob_amount.x * _bob_w,
		-absf(cos(_bob_t)) * bob_amount.y * _bob_w,
		0.0)
	var breathe := sin(Time.get_ticks_msec() * 0.0012) * 0.0025

	# --- recoil decays
	_recoil = move_toward(_recoil, 0.0, delta * 7.0)
	var r := ease(_recoil, 0.6)

	pivot.position = Vector3(_sway.x * 0.35, _sway.y * 0.35 + breathe, 0.0) + bob \
		+ Vector3(0.0, r * 0.012, r * recoil_back) + _reload_pos
	pivot.rotation = Vector3(
		_sway.y + r * recoil_pitch,
		_sway.x * 1.4,
		_sway.x * 0.8 + sin(_bob_t * 0.5) * 0.012 * _bob_w + r * _recoil_roll) + _reload_rot


## Recoil kick (call once per shot).
func kick() -> void:
	_recoil = 1.0
	_recoil_roll = randf_range(-0.08, 0.08)


## Reload motion: dip & tilt, mag out, mag in, slide rack, back up.
## `on_step` is called with "mag_out" / "mag_in" / "rack" for sounds.
func play_reload(duration: float, on_step: Callable = Callable()) -> void:
	if _reload_tw:
		_reload_tw.kill()
	var d := maxf(duration, 0.4)
	_reload_tw = create_tween()
	_reload_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# dip down, tilt to show the mag well
	_seg(Vector3(0.0, -0.07, 0.02), Vector3(0.35, 0.2, 0.55), d * 0.22)
	_reload_tw.tween_callback(_step.bind(on_step, "mag_out"))
	_reload_tw.tween_interval(d * 0.22)
	# mag slapped in: small upward jolt
	_reload_tw.tween_callback(_step.bind(on_step, "mag_in"))
	_seg(Vector3(0.0, -0.05, 0.02), Vector3(0.25, 0.2, 0.5), d * 0.08)
	# rotate for the slide rack
	_seg(Vector3(-0.02, -0.04, 0.0), Vector3(0.1, -0.15, -0.35), d * 0.18)
	_reload_tw.tween_callback(_step.bind(on_step, "rack"))
	_seg(Vector3(-0.02, -0.035, 0.05), Vector3(0.05, -0.15, -0.3), d * 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# back to rest
	_seg(Vector3.ZERO, Vector3.ZERO, d * 0.24)


var _seg_pos := Vector3.ZERO
var _seg_rot := Vector3.ZERO


## Appends one segment: capture the current offset, then lerp it to the target.
func _seg(to_pos: Vector3, to_rot: Vector3, time: float) -> MethodTweener:
	_reload_tw.tween_callback(func():
		_seg_pos = _reload_pos
		_seg_rot = _reload_rot)
	return _reload_tw.tween_method(_set_reload.bind(to_pos, to_rot), 0.0, 1.0, time)


func _set_reload(t: float, to_pos: Vector3, to_rot: Vector3) -> void:
	_reload_pos = _seg_pos.lerp(to_pos, t)
	_reload_rot = _seg_rot.lerp(to_rot, t)


func _step(cb: Callable, what: String) -> void:
	if cb.is_valid():
		cb.call(what)

extends Node
## COMBAT (Rickey): hitscan pistol. LMB fires, R reloads.
## The gun at `muzzle_path` is a WeaponViewmodel (scenes/props/pistol.tscn):
## it gets kick() on every shot and play_reload() synced to reload_time.

const MAX_HOLES := 48
const WeaponSfx := preload("res://scripts/game/weapon_sfx.gd")

@export var damage := 25.0
@export var max_range := 60.0
@export var mag_size := 8
@export var reserve_ammo := 48
@export var fire_interval := 0.28
@export var reload_time := 1.4
@export var shot_noise_radius := 25.0
@export var muzzle_path: NodePath

var ammo := 8
var reloading := false
var _cd := 0.0
var _holes: Array[Node3D] = []
var _sfx: AudioStreamPlayer
var _flesh: AudioStream = preload("res://assets/audio/sfx/hit_flesh.wav")

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	ammo = mag_size
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.max_polyphony = 3
	add_child(_sfx)


func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if player.dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("reload"):
		reload()
	if Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		fire()


func fire() -> void:
	if _cd > 0.0 or reloading:
		return
	if ammo <= 0:
		if reserve_ammo > 0:
			reload()
		else:
			_dry_fire()
		return
	_cd = fire_interval
	ammo -= 1
	var muzzle := _muzzle()
	var flash := TimbukFx.spawn(get_tree(), "res://scenes/effects/muzzle_flash.tscn", muzzle.global_position, true, player.camera.global_transform.basis)
	if flash and muzzle != player.camera:
		flash.reparent(muzzle, true)  # flash follows the barrel while it fades
	var gun := _gun()
	if gun and gun.has_method("kick"):
		gun.kick()
	player.make_noise(shot_noise_radius)
	var hit := player.aim(max_range)
	if not hit.is_empty():
		_impact(hit)
	if ammo == 0 and reserve_ammo > 0:
		get_tree().create_timer(fire_interval).timeout.connect(reload)


func _impact(hit: Dictionary) -> void:
	var target: Node = hit.collider
	var basis := TimbukFx.basis_from_normal(hit.normal).rotated(hit.normal.normalized(), randf() * TAU)
	if target.has_method("damage") and target.is_in_group("enemy"):
		# enemy.gd detects headshots from the world hit position
		var headshot: bool = target.has_method("is_headshot") and target.is_headshot(hit.position)
		target.damage(damage, hit.position)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_hit_marker"):
			hud.show_hit_marker(headshot)
		_play_at(_flesh, hit.position, randf_range(0.9, 1.1))
		return
	TimbukFx.spawn(get_tree(), "res://scenes/effects/impact_sparks.tscn", hit.position, true, basis)
	var hole := TimbukFx.spawn(get_tree(), "res://scenes/effects/bullet_hole.tscn", hit.position + hit.normal * 0.005, false, basis)
	if hole:
		var s := randf_range(0.8, 1.2)
		hole.scale = Vector3(s, 1.0, s)
		if target is Node3D and not (target is StaticBody3D):
			hole.reparent(target, true)  # stick to moving props / doors
		_holes.append(hole)
		get_tree().create_timer(30.0).timeout.connect(hole.queue_free)
		while _holes.size() > MAX_HOLES:
			var old: Node3D = _holes.pop_front()
			if is_instance_valid(old):
				old.queue_free()


func reload() -> void:
	if reloading or ammo >= mag_size or reserve_ammo <= 0 or player.dead:
		return
	reloading = true
	var gun := _gun()
	if gun and gun.has_method("play_reload"):
		gun.play_reload(reload_time, _reload_sound)
	await get_tree().create_timer(reload_time).timeout
	var need := mag_size - ammo
	var take := mini(need, reserve_ammo)
	ammo += take
	reserve_ammo -= take
	reloading = false


func _dry_fire() -> void:
	_cd = 0.35
	_play(WeaponSfx.get_stream("dry"), randf_range(0.95, 1.05))
	var gun := _gun()
	if gun and gun.has_method("kick"):
		gun.set("_recoil", 0.15)


func _reload_sound(step: String) -> void:
	_play(WeaponSfx.get_stream(step), randf_range(0.95, 1.05), -4.0)


func _play(stream: AudioStream, pitch := 1.0, db := -2.0) -> void:
	_sfx.stream = stream
	_sfx.pitch_scale = pitch
	_sfx.volume_db = db
	_sfx.play()


func _play_at(stream: AudioStream, pos: Vector3, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.pitch_scale = pitch
	p.unit_size = 3.0
	p.max_distance = 30.0
	var parent: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _gun() -> Node3D:
	return get_node_or_null(muzzle_path) as Node3D


func _muzzle() -> Node3D:
	var m := _gun()
	if m:
		var tip := m.find_child("MUZZLE", true, false) as Node3D
		return tip if tip else m
	return player.camera

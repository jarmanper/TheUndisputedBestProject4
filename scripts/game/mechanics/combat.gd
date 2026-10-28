extends Node
## COMBAT (Rickey): hitscan pistol. LMB fires, R reloads.

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

@onready var player: TimbukPlayer = get_parent()


func _ready() -> void:
	ammo = mag_size


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
		reload()
		return
	_cd = fire_interval
	ammo -= 1
	var muzzle := _muzzle()
	TimbukFx.spawn(get_tree(), "res://scenes/effects/muzzle_flash.tscn", muzzle.global_position, true, muzzle.global_transform.basis)
	_kick()
	player.make_noise(shot_noise_radius)
	var hit := player.aim(max_range)
	if hit.is_empty():
		return
	var target: Node = hit.collider
	var basis := TimbukFx.basis_from_normal(hit.normal)
	TimbukFx.spawn(get_tree(), "res://scenes/effects/impact_sparks.tscn", hit.position, true, basis)
	if target.has_method("damage") and target.is_in_group("enemy"):
		target.damage(damage)
	else:
		var hole := TimbukFx.spawn(get_tree(), "res://scenes/effects/bullet_hole.tscn", hit.position + hit.normal * 0.01, false, basis)
		if hole:
			get_tree().create_timer(30.0).timeout.connect(hole.queue_free)
	if ammo == 0:
		reload()


func reload() -> void:
	if reloading or ammo >= mag_size or reserve_ammo <= 0:
		return
	reloading = true
	await get_tree().create_timer(reload_time).timeout
	var need := mag_size - ammo
	var take := mini(need, reserve_ammo)
	ammo += take
	reserve_ammo -= take
	reloading = false


func _muzzle() -> Node3D:
	var m := get_node_or_null(muzzle_path) as Node3D
	if m:
		var tip := m.find_child("MUZZLE", true, false) as Node3D
		return tip if tip else m
	return player.camera


func _kick() -> void:
	var gun := get_node_or_null(muzzle_path) as Node3D
	if gun == null:
		return
	var tw := gun.create_tween()
	tw.tween_property(gun, "rotation:x", 0.15, 0.04)
	tw.tween_property(gun, "rotation:x", 0.0, 0.15)

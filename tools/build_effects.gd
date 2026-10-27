extends SceneTree
## Builds the reusable visual-effect scenes in res://scenes/effects/ and the
## shader material resources in res://assets/materials/fx_*.tres.
## Visual only: no damage, cooldowns, targeting or other mechanic logic.
## Teammates instance a scene and call play() (scripts/visual/vfx_player.gd).
## Run: tools/godot.sh script res://tools/build_effects.gd

const VFX := "res://assets/textures/vfx/%s.png"
const PLAYER := preload("res://scripts/visual/vfx_player.gd")
const FLICKER := preload("res://scripts/visual/light_flicker.gd")

const PALETTES := {
	"orange": [Color(1.0, 0.95, 0.8), Color(1.0, 0.55, 0.15), Color(0.6, 0.15, 0.03)],
	"green": [Color(0.9, 1.0, 0.85), Color(0.35, 1.0, 0.25), Color(0.05, 0.4, 0.05)],
	"blue": [Color(0.85, 0.95, 1.0), Color(0.25, 0.55, 1.0), Color(0.05, 0.1, 0.5)],
	"purple": [Color(1.0, 0.85, 1.0), Color(0.75, 0.3, 1.0), Color(0.25, 0.05, 0.4)],
}

var made: Array[String] = []


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/effects")
	save_materials()
	var mf := muzzle_flash()
	sfx(mf, "gunshot", false, 6.0, 60.0)
	save("muzzle_flash", mf)
	var im := impact_sparks()
	sfx(im, "impact_ricochet", false, 2.0, 25.0)
	save("impact_sparks", im)
	save("bullet_hole", decal_scene("bullet_hole", 0.12))
	save("scorch_mark", decal_scene("scorch", 2.4))
	var ti := tracking_indicator()
	sfx(ti, "tracker_ping_loop", true, 1.5, 12.0, -6.0)
	save("tracking_indicator", ti)
	var sf := suspend_field()
	sfx(sf, "suspend_loop", true, 3.0, 20.0)
	save("suspend_field", sf)
	save("suspended_particles", suspended_particles())
	for c in PALETTES:
		var ex := explosion(c)
		sfx(ex, "explosion", false, 10.0, 90.0, 3.0)
		save("explosion_%s" % c, ex)
		var fi := fire(c)
		sfx(fi, "fire_loop", true, 2.0, 15.0, -3.0)
		save("fire_%s" % c, fi)
	build_gallery()
	print("built %d effects: %s" % [made.size(), ", ".join(made)])
	quit()


# ------------------------------------------------------------------ helpers

func sfx(root: Node3D, file: String, autoplay: bool, unit := 3.0, max_d := 30.0, vol := 0.0) -> void:
	var a := AudioStreamPlayer3D.new()
	a.name = "Sfx_" + file
	a.stream = load("res://assets/audio/sfx/%s.wav" % file)
	a.bus = "SFX"
	a.unit_size = unit
	a.max_distance = max_d
	a.volume_db = vol
	a.autoplay = autoplay
	root.add_child(a)


func save(name: String, root: Node3D) -> void:
	root.name = name.to_pascal_case()
	for c in root.get_children():
		_own(c, root)
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, "res://scenes/effects/%s.tscn" % name)
	root.free()
	made.append(name)


func _own(n: Node, root: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_own(c, root)


func fx_root(autoplay := true, duration := 2.0, loop := false) -> Node3D:
	var r := Node3D.new()
	r.set_script(PLAYER)
	r.set("autoplay", autoplay)
	r.set("duration", duration)
	r.set("loop", loop)
	return r


func ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true    # allow >1 colours so fire cores bloom
	return t


func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var t := CurveTexture.new()
	t.curve = c
	return t


func sprite_mat(tex: String, additive: bool, align_velocity := false, atlas := 1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load(VFX % tex)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if align_velocity else BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = not additive
	m.proximity_fade_distance = 0.4
	if atlas > 1:
		m.particles_anim_h_frames = atlas
		m.particles_anim_v_frames = atlas
		m.particles_anim_loop = false
	return m


func particles(name: String, amount: int, lifetime: float, tex: String, additive: bool, size: float,
		pm: ParticleProcessMaterial, one_shot := true, align_velocity := false, atlas := 1) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.emitting = not one_shot
	p.process_material = pm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 14, 16))
	if align_velocity:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		pm.particle_flag_align_y = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size * (4.0 if align_velocity else 1.0))
	q.material = sprite_mat(tex, additive, align_velocity, atlas)
	p.draw_pass_1 = q
	return p


func pmat(dir: Vector3, spread: float, v_min: float, v_max: float, gravity: Vector3, damping := 0.0) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = dir
	m.spread = spread
	m.initial_velocity_min = v_min
	m.initial_velocity_max = v_max
	m.gravity = gravity
	m.damping_min = damping
	m.damping_max = damping
	return m


func flash_light(color: Color, energy: float, rng: float, fade: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "FlashLight"
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.set_meta("fade", fade)
	return l


# ------------------------------------------------------------------ materials

func save_materials() -> void:
	var mk := func(shader: String, params: Dictionary, out: String) -> void:
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/%s.gdshader" % shader)
		for k in params:
			m.set_shader_parameter(k, params[k])
		ResourceSaver.save(m, "res://assets/materials/%s.tres" % out)
	mk.call("hit_flash", {}, "fx_hit_flash")
	mk.call("marked_outline", {}, "fx_marked_outline")
	mk.call("afterimage", {}, "fx_afterimage")
	mk.call("temporal_distortion", {"clock_tex": load(VFX % "clock_ring")}, "fx_temporal_distortion")
	mk.call("hologram", {"mask": load(VFX % "reticle")}, "fx_tracker_hologram")


# ------------------------------------------------------------------ combat

func muzzle_flash() -> Node3D:
	var r := fx_root(true, 0.3)
	for k in 2:   # two crossed flash cards facing along -Z (the barrel)
		var mi := MeshInstance3D.new()
		mi.name = "Flash%d" % k
		var q := QuadMesh.new()
		q.size = Vector2(0.22, 0.22)
		var m := sprite_mat("muzzle", true)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		m.albedo_color = Color(1.0, 0.8, 0.5) * 2.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = m
		mi.mesh = q
		mi.rotation_degrees = Vector3(0, 90 * k, 0) if k == 1 else Vector3(0, 0, 0)
		mi.position = Vector3(0, 0, -0.06)
		mi.set_meta("fade", 0.06)
		mi.visible = false
		r.add_child(mi)
	var sp := particles("Sparks", 12, 0.25, "spark", true, 0.012,
		pmat(Vector3(0, 0, -1), 18.0, 4.0, 9.0, Vector3(0, -6, 0)), true, true)
	sp.process_material.color_ramp = ramp([[0.0, Color(1, 0.9, 0.6)], [1.0, Color(1, 0.3, 0.05, 0)]])
	r.add_child(sp)
	var sm := particles("Smoke", 6, 0.9, "smoke_atlas", false, 0.18,
		pmat(Vector3(0, 0.3, -1), 25.0, 0.3, 0.8, Vector3(0, 0.4, 0), 1.5), true, false, 2)
	sm.process_material.color_ramp = ramp([[0.0, Color(0.6, 0.58, 0.55, 0.35)], [1.0, Color(0.5, 0.5, 0.5, 0.0)]])
	sm.process_material.scale_curve = curve([[0.0, 0.4], [1.0, 1.6]])
	sm.process_material.anim_offset_max = 1.0
	r.add_child(sm)
	r.add_child(flash_light(Color(1.0, 0.7, 0.35), 6.0, 4.0, 0.06))
	return r


func impact_sparks() -> Node3D:
	## Surface normal = local +Y. Sparks, dust, concrete chips, flash, bullet hole.
	var r := fx_root(true, 1.2)
	var sp := particles("Sparks", 40, 0.5, "spark", true, 0.01,
		pmat(Vector3(0, 1, 0), 55.0, 2.5, 7.0, Vector3(0, -9.8, 0)), true, true)
	sp.process_material.color_ramp = ramp([[0.0, Color(1, 0.95, 0.75)], [0.5, Color(1, 0.55, 0.1)], [1.0, Color(0.8, 0.2, 0.0, 0)]])
	sp.process_material.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	sp.process_material.collision_bounce = 0.3
	r.add_child(sp)
	var dust := particles("Dust", 8, 1.2, "smoke_atlas", false, 0.25,
		pmat(Vector3(0, 1, 0), 40.0, 0.3, 1.2, Vector3(0, -0.2, 0), 2.0), true, false, 2)
	dust.process_material.color_ramp = ramp([[0.0, Color(0.55, 0.52, 0.48, 0.5)], [1.0, Color(0.5, 0.48, 0.45, 0.0)]])
	dust.process_material.scale_curve = curve([[0.0, 0.3], [1.0, 1.5]])
	dust.process_material.anim_offset_max = 1.0
	r.add_child(dust)
	var chips := GPUParticles3D.new()
	chips.name = "Chips"
	chips.amount = 10
	chips.lifetime = 1.0
	chips.one_shot = true
	chips.explosiveness = 1.0
	chips.emitting = false
	var cm := pmat(Vector3(0, 1, 0), 45.0, 1.5, 4.0, Vector3(0, -9.8, 0))
	cm.angular_velocity_min = -720.0
	cm.angular_velocity_max = 720.0
	cm.scale_min = 0.5
	cm.scale_max = 1.2
	chips.process_material = cm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.015, 0.01, 0.012)
	bm.material = load("res://assets/materials/concrete.tres")
	chips.draw_pass_1 = bm
	r.add_child(chips)
	r.add_child(flash_light(Color(1.0, 0.75, 0.4), 2.5, 2.0, 0.08))
	var hole := decal_node("bullet_hole", 0.12)
	r.add_child(hole)
	return r


func decal_node(tex: String, size: float) -> Decal:
	var d := Decal.new()
	d.name = "Decal"
	d.texture_albedo = load(VFX % tex)
	d.size = Vector3(size, 0.2, size)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1
	return d


func decal_scene(tex: String, size: float) -> Node3D:
	var r := Node3D.new()
	r.add_child(decal_node(tex, size))
	return r


# ------------------------------------------------------------------ marking

func tracking_indicator() -> Node3D:
	## Floats above a marked target (place at the target's origin; the
	## reticle sits at `height`). Looping, no logic.
	var r := Node3D.new()
	var holo := MeshInstance3D.new()
	holo.name = "Reticle"
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	q.material = load("res://assets/materials/fx_tracker_hologram.tres")
	holo.mesh = q
	holo.position = Vector3(0, 2.25, 0)
	r.add_child(holo)
	var bill := holo.duplicate()
	bill.name = "ReticleFlat"
	bill.rotation_degrees = Vector3(-90, 0, 0)
	bill.position = Vector3(0, 0.03, 0)
	bill.scale = Vector3.ONE * 2.2
	r.add_child(bill)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.01
	cyl.bottom_radius = 0.03
	cyl.height = 2.1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(1.0, 0.3, 0.1, 0.5)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material = bm
	beam.mesh = cyl
	beam.position = Vector3(0, 1.1, 0)
	r.add_child(beam)
	var motes := particles("Motes", 24, 1.6, "flare", true, 0.04,
		pmat(Vector3(0, 1, 0), 10.0, 0.4, 0.9, Vector3.ZERO), false)
	motes.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motes.process_material.emission_ring_radius = 0.5
	motes.process_material.emission_ring_inner_radius = 0.45
	motes.process_material.emission_ring_height = 0.02
	motes.process_material.emission_ring_axis = Vector3.UP
	motes.process_material.color_ramp = ramp([[0.0, Color(1, 0.35, 0.1, 0)], [0.2, Color(1, 0.35, 0.1, 1)], [1.0, Color(1, 0.2, 0.05, 0)]])
	r.add_child(motes)
	var l := OmniLight3D.new()
	l.name = "Glow"
	l.light_color = Color(1.0, 0.3, 0.1)
	l.light_energy = 0.8
	l.omni_range = 2.5
	l.position = Vector3(0, 0.3, 0)
	l.set_script(FLICKER)
	l.set("pulse", 1.5)
	r.add_child(l)
	return r


# ------------------------------------------------------------------ suspend

func suspend_field() -> Node3D:
	## Time-slowed bubble around a target: refraction sphere, rotating clock
	## numerals, frozen motes, cold light. Fade with the shader's `strength`.
	var r := Node3D.new()
	var sphere := MeshInstance3D.new()
	sphere.name = "Distortion"
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 2.6
	sm.radial_segments = 48
	sm.rings = 24
	sm.material = load("res://assets/materials/fx_temporal_distortion.tres")
	sphere.mesh = sm
	sphere.position = Vector3(0, 1.0, 0)
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(sphere)
	for k in 2:
		var ring := MeshInstance3D.new()
		ring.name = "ClockRing%d" % k
		var q := QuadMesh.new()
		q.size = Vector2(2.6 + k * 0.6, 2.6 + k * 0.6)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = load(VFX % "clock_ring")
		m.albedo_color = Color(0.5, 0.85, 1.0, 0.8 - k * 0.35)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = m
		ring.mesh = q
		ring.rotation_degrees = Vector3(-90, 0, 0)
		ring.position = Vector3(0, 0.05 + k * 1.9, 0)
		ring.set_script(load("res://scripts/visual/spin.gd"))
		ring.set("speed_deg", 6.0 if k == 0 else -4.0)
		r.add_child(ring)
	var motes := particles("FrozenMotes", 80, 6.0, "flare", true, 0.025,
		pmat(Vector3(0, 1, 0), 180.0, 0.01, 0.05, Vector3.ZERO, 0.0), false)
	motes.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motes.process_material.emission_sphere_radius = 1.2
	motes.process_material.color_ramp = ramp([[0.0, Color(0.5, 0.9, 1, 0)], [0.15, Color(0.5, 0.9, 1, 1)], [0.85, Color(0.5, 0.9, 1, 1)], [1.0, Color(0.5, 0.9, 1, 0)]])
	motes.position = Vector3(0, 1.0, 0)
	r.add_child(motes)
	var l := OmniLight3D.new()
	l.name = "ColdLight"
	l.light_color = Color(0.45, 0.8, 1.0)
	l.light_energy = 1.2
	l.omni_range = 4.0
	l.position = Vector3(0, 1.2, 0)
	r.add_child(l)
	return r


func suspended_particles() -> Node3D:
	## Dust and debris hanging in the air, barely drifting (ambient, looping).
	var r := Node3D.new()
	var dust := particles("Dust", 120, 10.0, "flare", true, 0.012,
		pmat(Vector3(0, 1, 0), 180.0, 0.005, 0.02, Vector3.ZERO), false)
	dust.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust.process_material.emission_box_extents = Vector3(1.5, 1.0, 1.5)
	dust.process_material.color_ramp = ramp([[0.0, Color(0.8, 0.9, 1, 0)], [0.2, Color(0.8, 0.9, 1, 0.8)], [0.8, Color(0.8, 0.9, 1, 0.8)], [1.0, Color(0.8, 0.9, 1, 0)]])
	dust.position = Vector3(0, 1.2, 0)
	dust.preprocess = 10.0
	r.add_child(dust)
	var debris := GPUParticles3D.new()
	debris.name = "Debris"
	debris.amount = 18
	debris.lifetime = 12.0
	debris.preprocess = 12.0
	var dm := pmat(Vector3(0, 1, 0), 180.0, 0.0, 0.02, Vector3.ZERO)
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(1.2, 0.8, 1.2)
	dm.angular_velocity_min = -8.0
	dm.angular_velocity_max = 8.0
	dm.scale_min = 0.4
	dm.scale_max = 1.5
	debris.process_material = dm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.03, 0.05)
	bm.material = load("res://assets/materials/concrete_damaged.tres")
	debris.draw_pass_1 = bm
	debris.position = Vector3(0, 1.2, 0)
	r.add_child(debris)
	return r


# ------------------------------------------------------------------ explosion & fire

func explosion(color: String) -> Node3D:
	var pal: Array = PALETTES[color]
	var r := fx_root(true, 4.0)
	var fb := particles("Fireball", 48, 1.1, "fire", true, 1.7,
		pmat(Vector3(0, 1, 0), 180.0, 0.8, 3.2, Vector3(0, 1.8, 0), 3.0), true)
	fb.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fb.process_material.emission_sphere_radius = 0.45
	fb.process_material.color_ramp = ramp([[0.0, pal[0] * 2.2], [0.18, pal[1] * 1.6], [0.55, pal[2] * 0.9], [1.0, Color(0, 0, 0, 0)]])
	fb.process_material.scale_curve = curve([[0.0, 0.5], [0.25, 1.0], [1.0, 1.4]])
	var core := MeshInstance3D.new()
	core.name = "FlashCore"
	var cq := QuadMesh.new()
	cq.size = Vector2(3.5, 3.5)
	var cmat := sprite_mat("flare", true)
	cmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	cmat.albedo_color = pal[1] * 1.6
	cq.material = cmat
	core.mesh = cq
	core.position = Vector3(0, 0.8, 0)
	core.set_meta("fade", 0.18)
	core.visible = false
	r.add_child(core)
	fb.process_material.angle_min = -180.0
	fb.process_material.angle_max = 180.0
	r.add_child(fb)
	var smoke := particles("Smoke", 28, 3.5, "smoke_atlas", false, 1.6,
		pmat(Vector3(0, 1, 0), 70.0, 0.8, 2.5, Vector3(0, 0.8, 0), 1.2), true, false, 2)
	smoke.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke.process_material.emission_sphere_radius = 0.5
	smoke.process_material.color_ramp = ramp([[0.0, Color(0.1, 0.09, 0.08, 0.0)], [0.12, Color(0.12, 0.11, 0.1, 0.85)], [1.0, Color(0.2, 0.2, 0.2, 0.0)]])
	smoke.process_material.scale_curve = curve([[0.0, 0.4], [1.0, 2.0]])
	smoke.process_material.anim_offset_max = 1.0
	smoke.process_material.angle_min = -180.0
	smoke.process_material.angle_max = 180.0
	r.add_child(smoke)
	var sparks := particles("Sparks", 60, 1.4, "spark", true, 0.02,
		pmat(Vector3(0, 1, 0), 75.0, 5.0, 14.0, Vector3(0, -9.8, 0), 0.5), true, true)
	sparks.process_material.color_ramp = ramp([[0.0, pal[0] * 2.0], [0.6, pal[1]], [1.0, Color(pal[2].r, pal[2].g, pal[2].b, 0)]])
	r.add_child(sparks)
	var debris := GPUParticles3D.new()
	debris.name = "Debris"
	debris.amount = 16
	debris.lifetime = 2.0
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.emitting = false
	var dm := pmat(Vector3(0, 1, 0), 60.0, 4.0, 9.0, Vector3(0, -9.8, 0))
	dm.angular_velocity_min = -540.0
	dm.angular_velocity_max = 540.0
	dm.scale_min = 0.5
	dm.scale_max = 1.6
	debris.process_material = dm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.05, 0.06)
	bm.material = load("res://assets/materials/rust.tres")
	debris.draw_pass_1 = bm
	r.add_child(debris)
	var ring := MeshInstance3D.new()
	ring.name = "Shockwave"
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	var m := sprite_mat("shockwave", true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.albedo_color = pal[1] * 1.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	ring.mesh = q
	ring.rotation_degrees = Vector3(-90, 0, 0)
	ring.position = Vector3(0, 0.1, 0)
	ring.set_meta("max_scale", 4.0)
	r.add_child(ring)
	r.add_child(flash_light(pal[1], 7.0, 10.0, 0.7, true))
	var scorch := decal_node("scorch", 3.0)
	scorch.name = "Scorch"
	r.add_child(scorch)
	return r


func fire(color: String) -> Node3D:
	var pal: Array = PALETTES[color]
	var r := Node3D.new()
	var flames := particles("Flames", 40, 1.0, "fire", true, 0.55,
		pmat(Vector3(0, 1, 0), 12.0, 0.6, 1.4, Vector3(0, 1.2, 0), 0.5), false)
	flames.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	flames.process_material.emission_sphere_radius = 0.25
	flames.process_material.color_ramp = ramp([[0.0, Color(pal[0].r, pal[0].g, pal[0].b, 0) * 2.5], [0.1, pal[0] * 2.5], [0.45, pal[1] * 1.6], [1.0, Color(pal[2].r, pal[2].g, pal[2].b, 0)]])
	flames.process_material.scale_curve = curve([[0.0, 0.6], [0.4, 1.0], [1.0, 0.2]])
	flames.process_material.angle_min = -30.0
	flames.process_material.angle_max = 30.0
	r.add_child(flames)
	var smoke := particles("Smoke", 16, 3.0, "smoke_atlas", false, 0.8,
		pmat(Vector3(0, 1, 0), 10.0, 0.5, 1.0, Vector3(0, 0.6, 0)), false, false, 2)
	smoke.process_material.color_ramp = ramp([[0.0, Color(0.1, 0.1, 0.1, 0)], [0.3, Color(0.1, 0.1, 0.1, 0.5)], [1.0, Color(0.2, 0.2, 0.2, 0)]])
	smoke.process_material.scale_curve = curve([[0.0, 0.5], [1.0, 2.2]])
	smoke.process_material.anim_offset_max = 1.0
	smoke.position = Vector3(0, 0.6, 0)
	r.add_child(smoke)
	var embers := particles("Embers", 20, 2.0, "flare", true, 0.03,
		pmat(Vector3(0, 1, 0), 25.0, 0.8, 2.2, Vector3(0, 0.6, 0)), false)
	embers.process_material.turbulence_enabled = true
	embers.process_material.turbulence_noise_strength = 2.0
	embers.process_material.color_ramp = ramp([[0.0, pal[0] * 2.0], [1.0, Color(pal[1].r, pal[1].g, pal[1].b, 0)]])
	r.add_child(embers)
	var l := OmniLight3D.new()
	l.name = "FireLight"
	l.light_color = pal[1]
	l.light_energy = 2.5
	l.omni_range = 6.0
	l.shadow_enabled = false   # enable per-instance if needed; omni shadows are costly
	l.position = Vector3(0, 0.6, 0)
	l.set_script(FLICKER)
	l.set("flicker", 0.25)
	r.add_child(l)
	return r


# ------------------------------------------------------------------ gallery

func build_gallery() -> void:
	## Dark test room with every effect looping and labelled (visual QA only).
	var root := Node3D.new()
	root.name = "EffectsGallery"
	var we := WorldEnvironment.new()
	we.environment = load("res://assets/materials/env_facility.tres")
	root.add_child(we)
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 16)
	var fm: StandardMaterial3D = load("res://assets/materials/concrete.tres").duplicate()
	fm.uv1_triplanar = true
	fm.uv1_world_triplanar = true
	pm.material = fm
	floor.mesh = pm
	root.add_child(floor)
	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	var wm := BoxMesh.new()
	wm.size = Vector3(60, 8, 0.3)
	var wmat: StandardMaterial3D = load("res://assets/materials/concrete_damaged.tres").duplicate()
	wmat.uv1_triplanar = true
	wmat.uv1_world_triplanar = true
	wm.material = wmat
	wall.mesh = wm
	wall.position = Vector3(0, 4, -4)
	root.add_child(wall)
	var key := DirectionalLight3D.new()
	key.light_energy = 0.15
	key.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(key)
	var row := [["muzzle_flash", 1.2], ["impact_sparks", 0.0], ["tracking_indicator", 0.0], ["suspend_field", 0.0],
		["suspended_particles", 0.0], ["explosion_orange", 0.0], ["explosion_green", 0.0], ["explosion_blue", 0.0],
		["explosion_purple", 0.0], ["fire_orange", 0.0], ["fire_green", 0.0], ["fire_blue", 0.0], ["fire_purple", 0.0]]
	var x := -24.0
	for item in row:
		var name: String = item[0]
		var fx: Node3D = load("res://scenes/effects/%s.tscn" % name).instantiate()
		fx.position = Vector3(x, item[1], -1.0)
		if fx.get_script() == PLAYER:
			fx.set("loop", true)
			fx.set("loop_interval", 2.5 if not name.begins_with("explosion") else 4.0)
		if name == "muzzle_flash":
			fx.rotation_degrees = Vector3(0, -90, 0)
		root.add_child(fx)
		var label := Label3D.new()
		label.text = name.replace("_", " ")
		label.font_size = 48
		label.pixel_size = 0.004
		label.position = Vector3(x, 0.05, 0.6)
		label.rotation_degrees = Vector3(-60, 0, 0)
		label.modulate = Color(0.85, 0.85, 0.8)
		root.add_child(label)
		var view := Node3D.new()
		view.name = "VIEW__fx_%s" % name
		var small: bool = name in ["muzzle_flash", "impact_sparks"]
		var eye := Vector3(x, 1.2, 0.8) if small else Vector3(x, 1.7, 4.5)
		var look := Vector3(x, item[1] * 0.9 + 0.1, -1.0) if small else Vector3(x, 1.0, -1.0)
		view.transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
		root.add_child(view)
		x += 5.0 if name.begins_with("explosion") else 3.0
	var overview := Node3D.new()
	overview.name = "VIEW__fx_overview"
	var oe := Vector3(0, 7, 22)
	overview.transform = Transform3D(Basis.looking_at(Vector3(0, 1, -1) - oe, Vector3.UP), oe)
	root.add_child(overview)
	for c in root.get_children():
		c.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, "res://scenes/effects/effects_gallery.tscn")
	root.free()

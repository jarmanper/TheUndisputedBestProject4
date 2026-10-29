extends Node3D
## Title screen backdrop: the inside of a clock.
##
## The camera sits amongst the movement of a huge, still-running clock -- brass
## wheels in layers of depth, a swinging pendulum, dust in a raking light. The
## word TIMBUK is real extruded geometry standing in the mechanism, so the key
## light rakes across the letters and the foreground wheels pass in front of
## them. Far behind it all, barely resolvable and out of focus, something is
## standing in the dark.
##
## Everything here is generated in code (see title_clockwork.gd for the gear
## meshes). Visual only -- no gameplay, no scene files to collide over.

const TITLE_TEXT := "TIMBUK"
const TitleClockwork := preload("res://scripts/ui/title_clockwork.gd")
const TWIN := preload("res://assets/models/characters/twin_monster.glb")
const DUST_TEX := preload("res://assets/textures/vfx/spark.png")

## One entry per wheel in the mechanism:
##   teeth, module, thickness, spokes, position, rpm (negative = other way), material
const FIELD := [
	# --- main movement: lower right, in the key light, roughly in focus ------
	{"t": 46, "m": 0.040, "th": 0.055, "sp": 6, "p": Vector3(1.42, -0.62, -3.80), "rpm": -0.55, "mat": "brass"},
	{"t": 22, "m": 0.040, "th": 0.050, "sp": 5, "p": Vector3(1.42, -0.62, -3.80), "rpm": 1.15, "mat": "gold"},
	{"t": 30, "m": 0.040, "th": 0.048, "sp": 5, "p": Vector3(0.70, -1.02, -4.00), "rpm": 0.84, "mat": "brass"},
	{"t": 64, "m": 0.040, "th": 0.060, "sp": 6, "p": Vector3(2.44, -0.18, -4.25), "rpm": -0.33, "mat": "brass"},
	{"t": 18, "m": 0.040, "th": 0.044, "sp": 0, "p": Vector3(1.94, -1.22, -3.62), "rpm": 1.70, "mat": "steel"},
	{"t": 36, "m": 0.040, "th": 0.050, "sp": 5, "p": Vector3(2.82, -1.08, -4.45), "rpm": -0.70, "mat": "brass"},
	# --- deeper layer, softer, slower, further from the light ----------------
	{"t": 80, "m": 0.040, "th": 0.070, "sp": 7, "p": Vector3(0.95, -1.60, -5.50), "rpm": 0.21, "mat": "gold"},
	{"t": 52, "m": 0.040, "th": 0.060, "sp": 6, "p": Vector3(-1.45, -0.30, -6.10), "rpm": -0.29, "mat": "brass"},
	{"t": 34, "m": 0.040, "th": 0.050, "sp": 5, "p": Vector3(-0.35, -1.25, -6.40), "rpm": 0.46, "mat": "gold"},
	{"t": 96, "m": 0.040, "th": 0.080, "sp": 8, "p": Vector3(3.10, 0.95, -7.10), "rpm": -0.17, "mat": "copper"},
	{"t": 44, "m": 0.040, "th": 0.055, "sp": 6, "p": Vector3(-2.60, -1.30, -6.20), "rpm": 0.33, "mat": "brass"},
	{"t": 60, "m": 0.040, "th": 0.060, "sp": 6, "p": Vector3(0.20, 1.55, -7.60), "rpm": -0.24, "mat": "brass"},
	# --- out-of-focus foreground, framing the corners ------------------------
	{"t": 46, "m": 0.034, "th": 0.075, "sp": 6, "p": Vector3(1.52, -1.12, -1.95), "rpm": 0.24, "mat": "brass"},
	{"t": 40, "m": 0.034, "th": 0.070, "sp": 6, "p": Vector3(-1.80, 1.02, -2.30), "rpm": -0.31, "mat": "gold"},
]

var _cam: Camera3D
var _key: SpotLight3D
var _rim: SpotLight3D
var _practical: OmniLight3D
var _title_root: Node3D
var _letters: Array[Node3D] = []
var _wheels: Array[Dictionary] = []
var _escape: Node3D
var _escape_target := 0.0
var _pendulum: Node3D
var _pend_amp := 0.19
var _twin: Node3D
var _twin_light: OmniLight3D
var _t := 0.0
var _speed := 1.0
var _push := 0.0
var _dial_hands: Array[Node3D] = []


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_backwall()
	_build_wheels()
	_build_escapement()
	_build_pendulum()
	_build_lights()
	_build_dust()
	_build_twin()
	_build_title()
	_update_camera(0.0)


# --- world --------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.007, 0.010)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.15, 0.16)
	env.ambient_light_energy = 0.16
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.tonemap_exposure = 1.0
	# Aerial perspective: each layer of wheels sits further back in the haze.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.062, 0.055, 0.052)
	env.fog_light_energy = 1.0
	env.fog_density = 0.028
	env.fog_depth_begin = 2.0
	env.fog_depth_end = 16.0
	env.fog_sky_affect = 0.0
	# Only the hot speculars on the brass bloom.
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_strength = 0.95
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.45
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Cheap contact shadows between the layers of wheels.
	env.ssao_enabled = true
	env.ssao_radius = 0.45
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_light_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 0.78
	env.adjustment_brightness = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 38.0          # long lens: flat, cinematic, little distortion
	_cam.near = 0.05
	_cam.far = 40.0
	_cam.current = true
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 4.6
	attr.dof_blur_far_transition = 3.0
	attr.dof_blur_near_enabled = true
	attr.dof_blur_near_distance = 2.0
	attr.dof_blur_near_transition = 1.0
	attr.dof_blur_amount = 0.07
	_cam.attributes = attr
	add_child(_cam)


## Far wall + the ghost of a giant dial, so the deep background is not empty black.
func _build_backwall() -> void:
	var wall := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(44, 30)
	plane.orientation = PlaneMesh.FACE_Z
	wall.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.040, 0.038, 0.036)
	m.roughness = 1.0
	m.albedo_texture = load("res://assets/textures/concrete_albedo.png")
	m.uv1_scale = Vector3(7, 5, 1)
	wall.mesh.material = m
	wall.position = Vector3(0, 0, -14.0)
	add_child(wall)

	# A huge dial hanging in the dark behind the movement.
	var dial := MeshInstance3D.new()
	dial.mesh = TitleClockwork.disc(1.75, 0.10, 64)
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = load("res://assets/textures/clock_face_albedo.png")
	dm.albedo_color = Color(0.30, 0.24, 0.17)
	dm.roughness = 0.75
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.76, 0.42)
	dm.emission_energy_multiplier = 0.07
	dial.mesh.surface_set_material(0, dm)
	dial.position = Vector3(3.30, 0.55, -10.6)
	add_child(dial)

	var hand_mat := StandardMaterial3D.new()
	hand_mat.albedo_color = Color(0.02, 0.02, 0.02)
	hand_mat.roughness = 0.5
	for spec in [[1.30, 0.038], [0.88, 0.058]]:
		var pivot := Node3D.new()
		pivot.position = Vector3(3.30, 0.55, -10.45)
		add_child(pivot)
		var hand := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(spec[1], spec[0], 0.04)
		hand.mesh = box
		hand.mesh.surface_set_material(0, hand_mat)
		hand.position = Vector3(0, spec[0] * 0.42, 0)
		pivot.add_child(hand)
		_dial_hands.append(pivot)
	_dial_hands[0].rotation.z = deg_to_rad(-37.0)
	_dial_hands[1].rotation.z = deg_to_rad(118.0)


func _metal(kind: String) -> StandardMaterial3D:
	var names := {
		"brass": "brass_aged", "gold": "tarnished_gold",
		"copper": "copper_oxidized", "steel": "brushed_steel",
	}
	var base: String = names.get(kind, "brass_aged")
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_albedo.png" % base)
	m.metallic = 1.0
	m.metallic_texture = load("res://assets/textures/%s_metal.png" % base)
	m.roughness = 1.0
	m.roughness_texture = load("res://assets/textures/%s_rough.png" % base)
	m.normal_enabled = true
	m.normal_scale = 0.6
	m.normal_texture = load("res://assets/textures/%s_normal.png" % base)
	m.uv1_scale = Vector3(1.4, 1.4, 1)
	# Metal with nothing to reflect reads as black or, worse, as whatever colour
	# the fill light happens to be. Warming the albedo and backing off full
	# metallic is what makes these read as brass rather than mouldy tin.
	m.albedo_color = {
		"brass": Color(1.00, 0.96, 0.80),
		"gold": Color(1.06, 0.99, 0.76),
		"copper": Color(0.95, 0.81, 0.64),
		"steel": Color(0.90, 0.91, 0.95),
	}.get(kind, Color(1.00, 0.96, 0.80))
	m.metallic = 0.42
	m.metallic_specular = 0.75
	m.roughness = 0.52
	return m


func _build_wheels() -> void:
	var mats := {}
	for spec in FIELD:
		var kind: String = spec["mat"]
		if not mats.has(kind):
			mats[kind] = _metal(kind)
		var mi := MeshInstance3D.new()
		mi.mesh = TitleClockwork.wheel(spec["t"], spec["m"], spec["th"], spec["sp"])
		mi.mesh.surface_set_material(0, mats[kind])
		mi.position = spec["p"]
		mi.rotation.z = randf() * TAU
		# Wheels in the deep layer cast no shadow: cheaper, and the haze hides it.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
				if spec["p"].z > -5.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_wheels.append({"node": mi, "rpm": spec["rpm"]})

		# Arbor: a short shaft through the middle so wheels are not floating plates.
		var shaft := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = spec["m"] * 1.1
		cyl.bottom_radius = cyl.top_radius
		cyl.height = spec["th"] * 5.0
		cyl.radial_segments = 12
		shaft.mesh = cyl
		shaft.mesh.surface_set_material(0, mats["steel"] if mats.has("steel") else mats[kind])
		shaft.rotation.x = PI * 0.5
		shaft.position = spec["p"]
		add_child(shaft)


## The escape wheel: the one part that moves in steps, once per tick.
func _build_escapement() -> void:
	_escape = Node3D.new()
	_escape.position = Vector3(2.62, -0.46, -3.42)
	add_child(_escape)
	var mi := MeshInstance3D.new()
	mi.mesh = TitleClockwork.wheel(30, 0.030, 0.022, 4, true)
	mi.mesh.surface_set_material(0, _metal("steel"))
	_escape.add_child(mi)

	# Anchor: two arms angled down from a pivot, each ending in a pallet that
	# hangs over the escape wheel's teeth.
	var fork := Node3D.new()
	fork.position = Vector3(2.62, -0.04, -3.38)
	fork.scale = Vector3.ONE * 0.78
	add_child(fork)
	var fm := _metal("brass")
	var parts := [
		{"size": Vector3(0.40, 0.034, 0.026), "pos": Vector3(-0.15, -0.09, 0), "rot": 0.42},
		{"size": Vector3(0.40, 0.034, 0.026), "pos": Vector3(0.15, -0.09, 0), "rot": -0.42},
		{"size": Vector3(0.05, 0.075, 0.030), "pos": Vector3(-0.30, -0.20, 0), "rot": 0.42},
		{"size": Vector3(0.05, 0.075, 0.030), "pos": Vector3(0.30, -0.20, 0), "rot": -0.42},
		{"size": Vector3(0.055, 0.22, 0.026), "pos": Vector3(0.0, 0.08, 0), "rot": 0.0},
	]
	for part in parts:
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part["size"]
		arm.mesh = box
		arm.mesh.surface_set_material(0, fm)
		arm.position = part["pos"]
		arm.rotation.z = part["rot"]
		fork.add_child(arm)
	_escape.set_meta("fork", fork)


func _build_pendulum() -> void:
	_pendulum = Node3D.new()
	_pendulum.position = Vector3(-1.62, 1.92, -2.65)
	add_child(_pendulum)
	var rod := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.016
	cyl.bottom_radius = 0.014
	cyl.height = 2.5
	cyl.radial_segments = 10
	rod.mesh = cyl
	rod.mesh.surface_set_material(0, _metal("steel"))
	rod.position = Vector3(0, -1.25, 0)
	_pendulum.add_child(rod)
	var bob := MeshInstance3D.new()
	bob.mesh = TitleClockwork.disc(0.30, 0.055, 48)
	bob.mesh.surface_set_material(0, _metal("gold"))
	bob.position = Vector3(0, -2.46, 0)
	_pendulum.add_child(bob)


func _build_lights() -> void:
	# Key: a hard warm raking light from the upper right, the way a desk lamp
	# falls into an opened clock case. This is what makes the brass read.
	_key = SpotLight3D.new()
	_key.light_color = Color(1.0, 0.90, 0.76)
	_key.light_energy = 13.0
	_key.light_specular = 1.0
	_key.spot_range = 11.5
	_key.spot_angle = 48.0
	_key.spot_angle_attenuation = 0.9
	_key.spot_attenuation = 1.1
	_key.shadow_enabled = true
	_key.shadow_bias = 0.03
	_key.shadow_normal_bias = 1.4
	_key.position = Vector3(3.3, 2.5, -0.6)
	add_child(_key)
	_key.look_at(Vector3(1.5, -0.7, -4.2))

	# Cold fill from deep left: separates the layers and keeps the shadows blue.
	_rim = SpotLight3D.new()
	_rim.light_color = Color(0.40, 0.58, 0.86)
	_rim.light_energy = 3.6
	_rim.light_specular = 0.9
	_rim.spot_range = 18.0
	_rim.spot_angle = 55.0
	_rim.spot_angle_attenuation = 1.0
	_rim.position = Vector3(-4.2, 1.0, -7.4)
	add_child(_rim)
	_rim.look_at(Vector3(0.2, 0.0, -3.6))

	# A practical buried in the movement, breathing like a dying bulb.
	_practical = OmniLight3D.new()
	_practical.light_color = Color(1.0, 0.76, 0.48)
	_practical.light_energy = 1.5
	_practical.omni_range = 3.4
	_practical.position = Vector3(1.75, -0.95, -4.5)
	add_child(_practical)

	# A controlled pool on the far wall, behind the movement only, so the deep
	# wheels have something to be silhouetted against.
	var backglow := OmniLight3D.new()
	backglow.light_color = Color(1.0, 0.70, 0.40)
	backglow.light_energy = 2.3
	backglow.omni_range = 9.5
	backglow.position = Vector3(2.8, 0.1, -12.2)
	add_child(backglow)

	# Warm bounce from below so the undersides of the wheels are not dead black.
	var bounce := OmniLight3D.new()
	bounce.light_color = Color(0.95, 0.72, 0.50)
	bounce.light_energy = 1.6
	bounce.omni_range = 9.0
	bounce.position = Vector3(0.8, -2.6, -3.4)
	add_child(bounce)

	# Dedicated soft light for the lettering so the title never falls into mud.
	var title_light := SpotLight3D.new()
	title_light.light_color = Color(0.95, 0.90, 0.86)
	title_light.light_energy = 6.0
	title_light.light_specular = 1.4
	title_light.spot_range = 7.0
	title_light.spot_angle = 42.0
	title_light.spot_angle_attenuation = 1.2
	title_light.position = Vector3(-1.1, 2.1, -0.8)
	add_child(title_light)
	title_light.look_at(Vector3(-0.25, 0.45, -2.9))


func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 150
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.explosiveness = 0.0
	p.position = Vector3(1.5, 0.1, -3.2)
	p.visibility_aabb = AABB(Vector3(-5, -4, -5), Vector3(10, 8, 10))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(2.6, 2.0, 1.8)
	mat.direction = Vector3(-0.3, 1.0, 0.0)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.012
	mat.initial_velocity_max = 0.055
	mat.gravity = Vector3(0.0, -0.006, 0.0)
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.06
	mat.turbulence_noise_scale = 2.0
	mat.scale_min = 0.5
	mat.scale_max = 1.6
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.009, 0.009)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_texture = DUST_TEX
	dm.albedo_color = Color(1.0, 0.86, 0.66, 0.16)
	dm.disable_receive_shadows = true
	quad.material = dm
	p.draw_pass_1 = quad
	add_child(p)


# --- the twin in the dark -----------------------------------------------------

## Instanced read-only from the shared character model. He is deliberately hard
## to see: far back, out of focus, lit only enough to be noticed on a second look.
func _build_twin() -> void:
	var inst := TWIN.instantiate() as Node3D
	if inst == null:
		return
	_twin = Node3D.new()
	_twin.add_child(inst)
	add_child(_twin)
	var aabb := _aabb(inst, Transform3D.IDENTITY)
	if aabb.size.y > 0.001:
		var s := 3.3 / aabb.size.y
		inst.scale = Vector3.ONE * s
		inst.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)
	_twin.position = Vector3(-0.30, -2.55, -11.6)
	_twin.rotation.y = PI          # models face +Z, so turn him towards the camera
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Lit from behind only, so he is a cut-out against a faint warm patch of
	# wall rather than a figure you can read. You notice him on a second look.
	_twin_light = OmniLight3D.new()
	_twin_light.light_color = Color(1.0, 0.74, 0.46)
	_twin_light.light_energy = 5.5
	_twin_light.omni_range = 7.5
	_twin_light.position = Vector3(-0.30, 0.3, -13.3)
	add_child(_twin_light)


func _aabb(node: Node, xf: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is VisualInstance3D:
		result = local * (node as VisualInstance3D).get_aabb()
		first = false
	for c in node.get_children():
		var ca := _aabb(c, local)
		if ca.size != Vector3.ZERO:
			result = ca if first else result.merge(ca)
			first = false
	return result


# --- the title ----------------------------------------------------------------

func _build_title() -> void:
	# Bundled, not SystemFont: the web export has no system fonts to fall back on.
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/CormorantGaramond.ttf")
	font.variation_opentype = {"wght": 700}

	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.86, 0.84, 0.78)
	face.roughness = 0.38
	face.metallic = 0.0
	face.metallic_specular = 0.85
	face.emission_enabled = true          # floor, so a letter never goes pure black
	face.emission = Color(0.62, 0.60, 0.56)
	face.emission_energy_multiplier = 0.07

	_title_root = Node3D.new()
	add_child(_title_root)

	var px := 0.0035
	var size := 150
	var tracking := 0.055
	var x := 0.0
	var widths: Array[float] = []
	for ch in TITLE_TEXT:
		var w: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * px
		widths.append(w)
	var total := 0.0
	for w in widths:
		total += w + tracking
	total -= tracking

	for i in TITLE_TEXT.length():
		var tm := TextMesh.new()
		tm.text = TITLE_TEXT[i]
		tm.font = font
		tm.font_size = size
		tm.pixel_size = px
		tm.depth = 0.075
		tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tm.material = face
		var holder := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(mi)
		holder.position = Vector3(x + widths[i] * 0.5 - total * 0.5, 0, 0)
		_title_root.add_child(holder)
		_letters.append(holder)
		x += widths[i] + tracking

	_title_root.position = Vector3(-0.19, 0.56, -2.92)
	_title_root.rotation.y = deg_to_rad(5.0)


## Letters fall into place one tick at a time, like a mechanical flip board.
func reveal_title() -> void:
	for i in _letters.size():
		var holder := _letters[i]
		var home := holder.position
		holder.position = home + Vector3(0, 0.16, 0)
		holder.rotation.x = deg_to_rad(-72.0)
		holder.scale = Vector3(1, 1, 1)
		var mi := holder.get_child(0) as MeshInstance3D
		mi.transparency = 1.0
		var tw := holder.create_tween().set_parallel(true)
		var d := 0.22 + i * 0.085
		tw.tween_property(mi, "transparency", 0.0, 0.35).set_delay(d)
		tw.tween_property(holder, "rotation:x", 0.0, 0.52).set_delay(d) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(holder, "position", home, 0.52).set_delay(d) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Called once a second by the title screen, in time with the tick.
func tick() -> void:
	_escape_target += TAU / 30.0
	_pend_amp = 0.19
	if randf() < 0.12:
		_stutter()


## The mechanism winds up and the camera pushes into it as the game starts.
func wind_up() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: _speed = v, 1.0, 9.0, 1.3) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float) -> void: _push = v, 0.0, 1.0, 1.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_key, "light_energy", 22.0, 1.4)


## A half-beat where the whole mechanism catches, as if time slipped.
func _stutter() -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _speed = v, 1.0, 0.04, 0.10)
	tw.tween_interval(0.16)
	tw.tween_method(func(v: float) -> void: _speed = v, 0.04, 1.0, 0.30)


# --- animation ----------------------------------------------------------------

func _process(delta: float) -> void:
	var d := delta * _speed
	_t += d
	for w in _wheels:
		(w["node"] as Node3D).rotation.z += (w["rpm"] as float) * TAU / 60.0 * d * 6.0
	for i in _dial_hands.size():
		_dial_hands[i].rotation.z -= d * (0.06 if i == 0 else 0.005)

	# Escape wheel snaps to its next tooth, then sits dead still.
	_escape.rotation.z = lerp_angle(_escape.rotation.z, _escape_target, clampf(d * 26.0, 0.0, 1.0))
	var fork := _escape.get_meta("fork") as Node3D
	if fork:
		fork.rotation.z = sin(_t * PI) * 0.09

	# Pendulum: one swing per second, amplitude decaying between ticks.
	_pend_amp = lerpf(_pend_amp, 0.155, clampf(d * 0.4, 0.0, 1.0))
	_pendulum.rotation.z = sin(_t * PI) * _pend_amp

	_practical.light_energy = 1.5 + sin(_t * 1.7) * 0.35 + sin(_t * 5.3) * 0.08
	_rim.light_energy = 3.6 + sin(_t * 0.43) * 0.6
	if _twin_light:
		_twin_light.light_energy = 5.2 + sin(_t * 0.31) * 1.3
	_update_camera(d)


func _update_camera(_d: float) -> void:
	# Slow, shallow drift. Restraint is what makes it read as expensive.
	var drift := Vector3(
		sin(_t * 0.085) * 0.14 + sin(_t * 0.031) * 0.06,
		sin(_t * 0.061) * 0.075,
		cos(_t * 0.047) * 0.10)
	_cam.position = Vector3(0.0, 0.05, 0.6) + drift + Vector3(0, 0, -2.6) * _push
	_cam.look_at(Vector3(0.52 + sin(_t * 0.039) * 0.05, 0.04, -4.2))
	_cam.rotate_object_local(Vector3.FORWARD, sin(_t * 0.055) * 0.009)
	var attr := _cam.attributes as CameraAttributesPractical
	attr.dof_blur_far_distance = 4.6 - _push * 1.6

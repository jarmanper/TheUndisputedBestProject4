class_name TimbukCompat
## Makes the facility survive the Compatibility renderer, which is the only
## one WebGL 2 can run and therefore the only one the browser build gets.
##
## Compatibility cannot draw screen-space reflections, SSAO, SSIL, SDFGI or
## volumetric fog, and it cannot even compile FogMaterial - the 52 FogVolumes
## in the eight area scenes are a hard shader error there, not a warning.
## Rather than strip that work out of the shared scenes and lose it on desktop,
## this detaches it at load time, and only when the renderer needs it detached.
## The desktop build still gets the full Forward+ look.

## Compatibility has no RenderingDevice; Forward+ and Mobile both do.
static func is_compatibility() -> bool:
	return RenderingServer.get_rendering_device() == null


## Call from _ready() of any scene that instances facility geometry, before the
## first frame is drawn. Safe (and free) to call on desktop.
static func adapt(root: Node) -> void:
	if not is_compatibility():
		return
	var volumes := 0
	for fv in root.find_children("*", "FogVolume", true, false):
		fv.queue_free()
		volumes += 1
	var envs := 0
	for we: WorldEnvironment in root.find_children("*", "WorldEnvironment", true, false):
		if _soften(we):
			envs += 1
	print("compat: Compatibility renderer - dropped %d fog volumes, softened %d environments" % [volumes, envs])
	_budget(root)


## The browser's render budget, by distance. Compatibility has no occlusion
## culling here, so with no limits it processed the whole 120 m facility every
## frame, through walls: measured on Nov 4 at the spawn, 11,600 draw calls and
## 5 M triangles - 141 shadow-mapped lights, 60 particle systems and 16 enemies
## of ~217k triangles each - for 116 ms a frame on an Apple laptop, and worse
## in a browser. Capping it by distance from the camera brought the measured
## spots from 24-116 ms to 14-46 ms. Visual only: no rule reads any of this,
## and every target in ability range (15 m at most) stays drawn.
const LIGHT_FADE_BEGIN := 20.0
const LIGHT_FADE_LENGTH := 5.0
const MOON_SHADOW_REACH := 30.0
const CAMERA_FAR := 60.0        # the Compatibility fog has hidden ~75% by here
const PARTICLE_REACH := 25.0
const CHARACTER_REACH := 30.0   # twice Marking's 15 m, the longest ability range


static func _budget(root: Node) -> void:
	var lights := 0
	for l: Light3D in root.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D:
			# one orthogonal pass instead of four cascades; the shadow itself
			# stays, because it is what keeps moonlight off indoor floors
			var d := l as DirectionalLight3D
			d.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			d.directional_shadow_max_distance = minf(d.directional_shadow_max_distance, MOON_SHADOW_REACH)
			continue
		# a shadow map per light was most of the draw calls
		l.shadow_enabled = false
		if not (l.distance_fade_enabled and l.distance_fade_begin + l.distance_fade_length <= LIGHT_FADE_BEGIN + LIGHT_FADE_LENGTH):
			l.distance_fade_enabled = true
			l.distance_fade_begin = LIGHT_FADE_BEGIN
			l.distance_fade_length = LIGHT_FADE_LENGTH
		lights += 1
	for c: Camera3D in root.find_children("*", "Camera3D", true, false):
		c.far = minf(c.far, CAMERA_FAR)
	for p: GPUParticles3D in root.find_children("*", "GPUParticles3D", true, false):
		p.visibility_range_end = PARTICLE_REACH
	var characters := 0
	if root.is_inside_tree():
		for e in root.get_tree().get_nodes_in_group("enemy"):
			for m: GeometryInstance3D in e.find_children("*", "GeometryInstance3D", true, false):
				m.visibility_range_end = CHARACTER_REACH
				characters += 1
	print("compat: render budget - %d lights unshadowed and faded at %d m, camera far %d m, %d enemy meshes culled at %d m" % [lights, int(LIGHT_FADE_BEGIN + LIGHT_FADE_LENGTH), int(CAMERA_FAR), characters, int(CHARACTER_REACH)])


## Replaces the environment with a copy that keeps the mood (sky, tonemap,
## glow, depth fog and the colour grade all work in Compatibility) and drops
## what does not. Ambient light is lifted because nothing bounces light any
## more, so without it the facility reads as black instead of dark.
static func _soften(we: WorldEnvironment) -> bool:
	if we.environment == null:
		return false
	var env: Environment = we.environment.duplicate()
	env.ssr_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	# stand in for the light the volumetric fog and SSIL used to carry
	env.ambient_light_energy = maxf(env.ambient_light_energy, 0.5)
	env.fog_enabled = true
	env.fog_light_color = Color(0.58, 0.62, 0.70)
	env.fog_density = 0.022
	we.environment = env
	# auto-exposure is also unsupported, and leaving it on pumps the image
	var ca := we.camera_attributes
	if ca:
		ca = ca.duplicate()
		ca.auto_exposure_enabled = false
		we.camera_attributes = ca
	return true

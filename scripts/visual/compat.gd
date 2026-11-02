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

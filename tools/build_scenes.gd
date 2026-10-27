extends SceneTree
## Assembles TIMBUK's Godot scenes from the Blender exports.
##   scenes/props/<prop>.tscn          one per assets/models/props/*.glb (+ its lights)
##   scenes/environments/<area>.tscn   area GLB + lights + prop instances
##   scenes/environments/timbuk_facility.tscn   all areas + environment, fog, probes
##   scenes/visual_inspection.tscn     facility + free-look camera + HUD
## Run: tools/godot.sh script res://tools/build_scenes.gd
##
## Markers inside the GLBs (Blender empties):
##   L__<kind>__n   light (extras: energy, range, color, spot, shadow, flicker, pulse, aim)
##   P__<prop>__n   prop instance
##   ROOM__<name>   room bounds (extras: size, style) -> reflection probe / fog volume
##   VIEW__<name>   inspection camera viewpoint
##   REVEAL__monster  where the twin monster stands for the reveal

const PROPS_DIR := "res://assets/models/props/"
const ENV_DIR := "res://assets/models/environment/"
const FLICKER := preload("res://scripts/visual/light_flicker.gd")

# kind -> [type, color, energy, range, shadow, spot_angle_deg (0 = omni), points down]
const LIGHTS := {
	"fluor": ["omni", Color(0.82, 0.9, 1.0), 0.95, 5.5, false, 0, false],
	"fluor_hanging": ["omni", Color(0.8, 0.92, 1.0), 1.2, 5.0, true, 0, false],
	"highbay": ["spot", Color(0.78, 0.9, 1.0), 4.0, 11.0, false, 75, true],
	"sodium": ["spot", Color(1.0, 0.62, 0.3), 6.0, 18.0, true, 70, true],
	"spot": ["spot", Color(0.75, 0.85, 1.0), 3.0, 7.0, true, 60, true],
	"surgical": ["spot", Color(1.0, 0.95, 0.85), 8.0, 5.0, true, 40, true],
	"red": ["omni", Color(1.0, 0.08, 0.04), 2.0, 7.0, false, 0, false],
	"beacon": ["omni", Color(1.0, 0.08, 0.04), 1.6, 7.0, false, 0, false],
	"cage": ["omni", Color(1.0, 0.62, 0.32), 0.9, 5.0, false, 0, false],
	"sign": ["omni", Color(1.0, 0.12, 0.06), 1.2, 4.5, false, 0, false],
	"screen": ["omni", Color(0.35, 1.0, 0.6), 0.35, 1.6, false, 0, false],
	"keypad": ["omni", Color(1.0, 0.1, 0.05), 0.15, 1.0, false, 0, false],
	"tracker": ["omni", Color(1.0, 0.2, 0.1), 0.2, 0.8, false, 0, false],
	"desk_lamp": ["omni", Color(1.0, 0.75, 0.45), 0.6, 3.0, false, 0, false],
	"chem": ["omni", Color(0.4, 1.0, 0.3), 0.5, 2.5, false, 0, false],
	"tank": ["omni", Color(0.3, 1.0, 0.65), 1.2, 4.0, false, 0, false],
	"core": ["omni", Color(1.0, 0.45, 0.15), 3.0, 8.0, true, 0, false],
	"emitter": ["omni", Color(1.0, 0.35, 0.08), 3.0, 10.0, false, 0, false],
	"chamber_spill": ["omni", Color(1.0, 0.45, 0.15), 2.0, 6.0, false, 0, false],
	"reveal_key": ["spot", Color(1.0, 0.86, 0.72), 14.0, 20.0, true, 28, false],
	"reveal_rim": ["spot", Color(0.4, 0.75, 1.0), 10.0, 14.0, true, 35, false],
	"reveal_fill": ["omni", Color(1.0, 0.45, 0.2), 1.4, 7.0, false, 0, false],
	"clock_wash": ["spot", Color(1.0, 0.8, 0.55), 6.0, 14.0, false, 55, false],
	"uplight": ["spot", Color(1.0, 0.6, 0.3), 3.0, 10.0, false, 50, false],
	"chamber_high": ["omni", Color(0.6, 0.72, 0.9), 1.6, 16.0, false, 0, false],
}


func _init() -> void:
	var prop_scenes := build_props()
	var areas := build_areas(prop_scenes)
	build_facility(areas)
	var characters := build_characters()
	build_inspection(characters)
	if characters.has("twin_monster"):
		build_reveal(characters["twin_monster"])
	print("TIMBUK scenes built: %d props, %d areas" % [prop_scenes.size(), areas.size()])
	quit()


# ------------------------------------------------------------------ helpers

static func pascal(s: String) -> String:
	return s.to_pascal_case()


static func blender_to_godot(v: Array) -> Vector3:
	return Vector3(v[0], v[2], -v[1])


func save_scene(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	assert(err == OK, "pack failed for %s" % path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(packed, path)
	root.free()


func own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for c in node.get_children():
		own(c, owner_node)


## Transform of `n` relative to `stop` (works outside the scene tree).
func rel_xform(n: Node, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := n
	while cur and cur != stop:
		if cur is Node3D:
			t = cur.transform * t
		cur = cur.get_parent()
	return t


func markers(root: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in root.find_children(prefix + "*", "", true, false):
		out.append(n)
	return out


func extras(n: Node) -> Dictionary:
	return n.get_meta("extras", {}) if n.has_meta("extras") else {}


func make_light(kind: String, ex: Dictionary, xf: Transform3D) -> Light3D:
	var d: Array = LIGHTS.get(kind, LIGHTS["fluor"])
	var spot_deg: float = ex.get("spot", d[5])
	var light: Light3D
	if spot_deg > 0.0:
		var s := SpotLight3D.new()
		s.spot_angle = spot_deg * 0.5
		s.spot_range = ex.get("range", d[3])
		s.spot_attenuation = 0.8
		s.spot_angle_attenuation = 1.6
		light = s
	else:
		var o := OmniLight3D.new()
		o.omni_range = ex.get("range", d[3])
		o.omni_attenuation = 1.2
		light = o
	light.name = "%s_light" % kind
	light.light_color = d[1]
	if ex.has("color"):
		var c: Array = ex["color"]
		light.light_color = Color(c[0], c[1], c[2])
	light.light_energy = ex.get("energy", d[2])
	light.shadow_enabled = ex.get("shadow", d[4])
	light.shadow_blur = 1.5
	light.light_volumetric_fog_energy = 1.5
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 10.0
	light.distance_fade_shadow = 18.0
	light.transform = xf
	if spot_deg > 0.0:
		if ex.has("aim"):
			var target := blender_to_godot(ex["aim"])
			light.transform = Transform3D(Basis.looking_at(target - xf.origin, Vector3.UP), xf.origin)
		elif d[6] or kind in ["sodium", "highbay", "spot", "surgical"]:
			light.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), xf.origin)
	var flick: float = ex.get("flicker", 0.0)
	var pulse: float = ex.get("pulse", 0.0)
	if flick > 0.0 or pulse > 0.0:
		light.set_script(FLICKER)
		light.set("flicker", flick)
		light.set("pulse", pulse)
	return light


## Instances a GLB under a new root and converts its L__ markers into lights.
func glb_root(glb_path: String, root_name: String) -> Array:
	var root := Node3D.new()
	root.name = root_name
	var inst: Node3D = load(glb_path).instantiate()
	inst.name = "Model"
	root.add_child(inst)
	inst.owner = root
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	lights.owner = root
	for m in markers(inst, "L__"):
		var kind := String(m.name).get_slice("__", 1)
		var light := make_light(kind, extras(m), rel_xform(m, root))
		lights.add_child(light, true)
		light.owner = root
	return [root, inst]


# ------------------------------------------------------------------ props

func build_props() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(PROPS_DIR):
		if not f.ends_with(".glb"):
			continue
		var name := f.get_basename()
		var pair := glb_root(PROPS_DIR + f, pascal(name))
		var root: Node3D = pair[0]
		if root.get_node("Lights").get_child_count() == 0:
			root.get_node("Lights").free()
		var path := "res://scenes/props/%s.tscn" % name
		save_scene(root, path)
		out[name] = path
	return out


# ------------------------------------------------------------------ areas

func build_areas(prop_scenes: Dictionary) -> Array:
	var out := []
	var files := DirAccess.get_files_at(ENV_DIR)
	files.sort()
	for f in files:
		if not f.ends_with(".glb"):
			continue
		var name := f.get_basename()
		var pair := glb_root(ENV_DIR + f, pascal(name))
		var root: Node3D = pair[0]
		var inst: Node3D = pair[1]
		var props := Node3D.new()
		props.name = "Props"
		root.add_child(props)
		props.owner = root
		var missing := {}
		for m in markers(inst, "P__"):
			var pname := String(m.name).get_slice("__", 1)
			if not prop_scenes.has(pname):
				missing[pname] = true
				continue
			var p: Node3D = load(prop_scenes[pname]).instantiate()
			p.transform = rel_xform(m, root)
			props.add_child(p, true)
			p.owner = root
		for m in markers(inst, "FX__"):
			var ename := String(m.name).get_slice("__", 1)
			var epath := "res://scenes/effects/%s.tscn" % ename
			if not ResourceLoader.exists(epath):
				missing["fx:" + ename] = true
				continue
			var e: Node3D = load(epath).instantiate()
			e.transform = rel_xform(m, root)
			props.add_child(e, true)
			e.owner = root
		if missing:
			push_warning("%s: missing prop scenes %s" % [name, missing.keys()])
		add_room_extras(root, inst)
		var path := "res://scenes/environments/%s.tscn" % name
		save_scene(root, path)
		out.append(path)
	return out


func add_room_extras(root: Node3D, inst: Node3D) -> void:
	var probes := Node3D.new()
	probes.name = "ReflectionProbes"
	root.add_child(probes)
	probes.owner = root
	var fogs := Node3D.new()
	fogs.name = "FogVolumes"
	root.add_child(fogs)
	fogs.owner = root
	for m in markers(inst, "ROOM__"):
		var ex := extras(m)
		if not ex.has("size"):
			continue
		var size := Vector3(ex["size"][0], ex["size"][2], ex["size"][1])
		var style: String = ex.get("style", "lab")
		var xf := rel_xform(m, root)
		if style != "outdoor":
			var probe := ReflectionProbe.new()
			probe.name = String(m.name).trim_prefix("ROOM__") + "_probe"
			probe.size = size + Vector3(0.2, 0.2, 0.2)
			probe.box_projection = true
			probe.interior = true
			probe.update_mode = ReflectionProbe.UPDATE_ONCE
			probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
			probe.ambient_color = Color(0.05, 0.06, 0.07)
			probe.ambient_color_energy = 0.4
			probe.position = xf.origin
			probes.add_child(probe, true)
			probe.owner = root
		var density: float = {"lab": 0.0, "lobby": 0.0, "industrial": 0.02, "lower": 0.05, "chamber": 0.035, "outdoor": 0.015}.get(style, 0.0)
		if density > 0.0:
			var fog := FogVolume.new()
			fog.name = String(m.name).trim_prefix("ROOM__") + "_fog"
			fog.size = size
			fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
			fog.material = fog_material(style, density)
			fog.position = xf.origin
			fogs.add_child(fog, true)
			fog.owner = root


func fog_material(style: String, density: float) -> FogMaterial:
	var path := "res://assets/materials/fog_%s.tres" % style
	if ResourceLoader.exists(path):
		return load(path)
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = {"industrial": Color(0.75, 0.8, 0.82), "lower": Color(0.7, 0.66, 0.58),
		"chamber": Color(0.8, 0.72, 0.65), "outdoor": Color(0.55, 0.62, 0.72)}.get(style, Color.WHITE)
	fm.height_falloff = 0.15 if style != "outdoor" else 0.35
	fm.edge_fade = 0.3
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var tex := NoiseTexture3D.new()
	tex.width = 64
	tex.height = 64
	tex.depth = 64
	tex.seamless = true
	tex.noise = noise
	fm.density_texture = tex
	ResourceSaver.save(fm, path)
	return load(path)


# ------------------------------------------------------------------ facility

func make_environment() -> Environment:
	var path := "res://assets/materials/env_facility.tres"
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.025, 0.045)
	sky_mat.sky_horizon_color = Color(0.07, 0.07, 0.09)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.012)
	sky_mat.ground_horizon_color = Color(0.06, 0.06, 0.07)
	sky_mat.sun_angle_max = 2.0
	sky_mat.energy_multiplier = 0.6
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_energy = 0.16
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssil_enabled = true
	env.ssil_intensity = 0.8
	# SSR off: it smears additive VFX into glossy floors/walls; probes handle reflections
	env.ssr_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 0.6)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(5, 0.6)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.7, 0.74, 0.8)
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.88
	ResourceSaver.save(env, path)
	return load(path)


func build_facility(areas: Array) -> void:
	var root := Node3D.new()
	root.name = "TimbukFacility"
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = make_environment()
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.3
	cam_attr.auto_exposure_speed = 0.8
	# narrow range: dark areas get a little help but stay dark, bright labs dim slightly
	cam_attr.auto_exposure_min_sensitivity = 70.0
	cam_attr.auto_exposure_max_sensitivity = 220.0
	we.camera_attributes = cam_attr
	root.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.28
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	moon.rotation_degrees = Vector3(-30, -20, 0)   # shines onto the facade
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	root.add_child(moon)
	var areas_node := Node3D.new()
	areas_node.name = "Areas"
	root.add_child(areas_node)
	for p in areas:
		var a: Node3D = load(p).instantiate()
		areas_node.add_child(a, true)
	own_shallow(root)
	save_scene(root, "res://scenes/environments/timbuk_facility.tscn")


## Owner for direct nodes we created; instanced scenes keep their own internals.
func own_shallow(root: Node) -> void:
	for c in root.get_children():
		c.owner = root
		if c.scene_file_path == "":
			own_shallow_inner(c, root)


func own_shallow_inner(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		if c.scene_file_path == "":
			own_shallow_inner(c, root)


# ------------------------------------------------------------------ characters

const CHAR_DIR := "res://assets/models/characters/"
const CREATURE_SCRIPT := preload("res://scripts/visual/creature_visual.gd")


func build_characters() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(CHAR_DIR):
		return out
	for f in DirAccess.get_files_at(CHAR_DIR):
		if not f.ends_with(".glb"):
			continue
		var name := f.get_basename()
		var pair := glb_root(CHAR_DIR + f, pascal(name))
		var root: Node3D = pair[0]
		if root.get_node("Lights").get_child_count() == 0:
			root.get_node("Lights").free()
		root.set_script(CREATURE_SCRIPT)
		var path := "res://scenes/characters/%s.tscn" % name
		save_scene(root, path)
		out[name] = path
	return out


# ------------------------------------------------------------------ reveal

func bpos(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


func build_reveal(twin_scene: String) -> void:
	var root := Node3D.new()
	root.name = "TwinReveal"
	root.set_script(load("res://scripts/visual/reveal_sequence.gd"))
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = load("res://assets/materials/env_facility.tres")
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 9.0
	cam_attr.dof_blur_far_transition = 6.0
	cam_attr.dof_blur_amount = 0.06
	we.camera_attributes = cam_attr
	root.add_child(we)
	var chamber: Node3D = load("res://scenes/environments/area_e_twin_chamber.tscn").instantiate()
	root.add_child(chamber)
	var twin: Node3D = load(twin_scene).instantiate()
	twin.name = "Twin"
	twin.position = bpos(Vector3(14.7, 106.8, -5.1))
	twin.rotation.y = 0.0      # faces +Z = towards the chamber entrance
	twin.set("animation", "reveal")
	twin.set("desync", false)
	root.add_child(twin)
	# face key light + soft fill so the face always reads (never lost in darkness)
	var face_c := bpos(Vector3(14.7, 106.65, -3.22))
	var key := SpotLight3D.new()
	key.name = "FaceKey"
	key.light_color = Color(1.0, 0.88, 0.75)
	key.light_energy = 6.0
	key.spot_range = 6.0
	key.spot_angle = 14.0
	key.shadow_enabled = true
	var kp := face_c + Vector3(-1.2, 1.4, 2.4)
	key.transform = Transform3D(Basis.looking_at(face_c - kp, Vector3.UP), kp)
	root.add_child(key)
	var rim := SpotLight3D.new()
	rim.name = "FaceRim"
	rim.light_color = Color(0.45, 0.75, 1.0)
	rim.light_energy = 5.0
	rim.spot_range = 5.0
	rim.spot_angle = 18.0
	var rp := face_c + Vector3(1.4, 1.0, -1.6)
	rim.transform = Transform3D(Basis.looking_at(face_c - rp, Vector3.UP), rp)
	root.add_child(rim)
	var cam := Camera3D.new()
	cam.name = "RevealCamera"
	cam.fov = 50
	root.add_child(cam)
	root.set("twin_path", NodePath("Twin"))
	root.set("camera_path", NodePath("RevealCamera"))
	root.set("shots", [
		[0.0, bpos(Vector3(14.7, 93.6, -4.3)), bpos(Vector3(14.7, 106.8, -4.0))],
		[3.0, bpos(Vector3(14.9, 99.0, -4.2)), bpos(Vector3(14.7, 106.8, -3.6))],
		[6.5, bpos(Vector3(15.0, 104.4, -3.4)), face_c],
		[11.0, bpos(Vector3(14.78, 105.95, -3.18)), face_c],
		[16.0, bpos(Vector3(14.66, 106.08, -3.16)), face_c],
	])
	for i in 6:   # inspection/capture viewpoints along the sequence
		pass
	var v1 := Node3D.new()
	v1.name = "VIEW__reveal_wide"
	var e1 := bpos(Vector3(14.7, 99.0, -4.2))
	v1.transform = Transform3D(Basis.looking_at(bpos(Vector3(14.7, 106.8, -3.6)) - e1, Vector3.UP), e1)
	root.add_child(v1)
	var v2 := Node3D.new()
	v2.name = "VIEW__reveal_face"
	var e2 := bpos(Vector3(14.76, 105.55, -3.15))
	v2.transform = Transform3D(Basis.looking_at(face_c - e2, Vector3.UP), e2)
	root.add_child(v2)
	var v3 := Node3D.new()
	v3.name = "VIEW__reveal_threeq"
	var e3 := bpos(Vector3(15.9, 104.6, -3.6))
	v3.transform = Transform3D(Basis.looking_at(bpos(Vector3(14.7, 106.8, -3.9)) - e3, Vector3.UP), e3)
	root.add_child(v3)
	var v4 := Node3D.new()
	v4.name = "VIEW__reveal_portrait"
	var e4 := bpos(Vector3(14.7, 106.05, -3.17))
	v4.transform = Transform3D(Basis.looking_at(face_c + Vector3(0, 0.03, 0) - e4, Vector3.UP), e4)
	root.add_child(v4)
	own_shallow(root)
	save_scene(root, "res://scenes/cinematics/twin_reveal.tscn")


# ------------------------------------------------------------------ inspection

## Where each creature stands in the inspection scene (Blender coords, facing yaw deg)
const SHOWCASE := {
	"failed_humanoid": [Vector3(-10.6, 22.2, 0.0), 0.0, "idle", Vector3(-9.3, 21.5, 1.6)],
	"augmented_subject": [Vector3(5.2, 45.6, 0.0), 0.0, "twitch", Vector3(4.6, 44.3, 1.65)],
	"chemical_subject": [Vector3(0.1, 70.5, -6.0), 0.0, "idle", Vector3(0.05, 69.1, -4.4)],
	"twin_monster": [Vector3(14.7, 106.8, -5.1), 0.0, "idle", Vector3(14.7, 102.6, -3.6)],
}


func build_inspection(characters: Dictionary = {}) -> void:
	var root := Node3D.new()
	root.name = "VisualInspection"
	var fac: Node3D = load("res://scenes/environments/timbuk_facility.tscn").instantiate()
	root.add_child(fac)
	var showcase := Node3D.new()
	showcase.name = "CreatureShowcase"
	root.add_child(showcase)
	for cname in characters:
		if not SHOWCASE.has(cname):
			continue
		var spec: Array = SHOWCASE[cname]
		var c: Node3D = load(characters[cname]).instantiate()
		var bp: Vector3 = spec[0]
		c.position = Vector3(bp.x, bp.z, -bp.y)
		var vp: Vector3 = spec[3]
		var eye := Vector3(vp.x, vp.z, -vp.y)
		# models face +Z: turn toward the viewpoint, plus an optional offset
		var to_eye := eye - c.position
		c.rotation.y = atan2(to_eye.x, to_eye.z) + deg_to_rad(spec[1])
		c.set("animation", spec[2])
		showcase.add_child(c, true)
		var view := Node3D.new()
		view.name = "VIEW__creature_%s" % cname
		var target := c.position + Vector3(0, 1.3, 0)
		view.transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
		showcase.add_child(view)
	var cam := Camera3D.new()
	cam.name = "FreeLookCamera"
	cam.set_script(load("res://scripts/visual/free_look_camera.gd"))
	cam.position = Vector3(0, 1.7, 21)
	cam.fov = 70
	cam.current = true
	root.add_child(cam)
	var fl := SpotLight3D.new()
	fl.name = "Flashlight"
	fl.visible = false
	fl.light_energy = 3.0
	fl.spot_range = 18.0
	fl.spot_angle = 24.0
	fl.shadow_enabled = true
	fl.light_color = Color(1.0, 0.95, 0.85)
	fl.position = Vector3(0.15, -0.1, 0)
	cam.add_child(fl)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/visual/inspection_hud.gd"))
	root.add_child(hud)
	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(16, 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 15)
	hud.add_child(label)
	hud.set("camera_path", NodePath("../FreeLookCamera"))
	own_shallow(root)
	save_scene(root, "res://scenes/visual_inspection.tscn")

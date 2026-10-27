extends SceneTree
## Builds res://assets/materials/*.tres from source/materials.json.
## Run:  godot --headless --path . --script res://tools/build_materials.gd

const SPEC := "res://source/materials.json"
const TEX := "res://assets/textures/%s_%s.png"
const OUT := "res://assets/materials/%s.tres"


func _init() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var count := 0
	for name in spec:
		if name.begins_with("_"):
			continue
		var mat := build(name, spec[name])
		ResourceSaver.save(mat, OUT % name)
		count += 1
	print("built %d materials" % count)
	quit()


func tex(base: String, kind: String) -> Texture2D:
	var path := TEX % [base, kind]
	return load(path) if ResourceLoader.exists(path) else null


func build(name: String, d: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	var base: String = d.get("tex", "")
	var repeat: float = d.get("repeat", 1.0)
	m.uv1_scale = Vector3.ONE / repeat

	if d.has("albedo"):
		var a: Array = d["albedo"]
		m.albedo_color = Color(a[0], a[1], a[2])
	m.roughness = d.get("roughness", 1.0)
	m.metallic = d.get("metallic", 0.0)
	m.metallic_specular = d.get("specular", 0.5)

	if base != "":
		m.albedo_texture = tex(base, "albedo")
		var r := tex(base, "rough")
		if r:
			m.roughness_texture = r
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		var mt := tex(base, "metal")
		if mt:
			m.metallic = d.get("metallic", 1.0)
			m.metallic_texture = mt
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		var nm := tex(base, "normal")
		if nm:
			m.normal_enabled = true
			m.normal_texture = nm
			m.normal_scale = d.get("normal", 1.0)
		var em := tex(base, "emit")
		if em:
			m.emission_enabled = true
			m.emission = Color.BLACK
			m.emission_texture = em
			m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
			m.emission_energy_multiplier = d.get("emission_energy", 1.0)

	if d.has("emission"):
		var e: Array = d["emission"]
		m.emission_enabled = true
		m.emission = Color(e[0], e[1], e[2])
		m.emission_energy_multiplier = d.get("emission_energy", 1.0)

	if d.get("transparent", false):
		# plain alpha blending: glass and fluids never render into shadow maps,
		# so lights shine through tanks and windows
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if d.get("no_shadow", false) else BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.albedo_color.a = d.get("alpha", 0.5)
	if d.get("double_sided", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if d.has("sss"):
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = d["sss"]
		m.subsurf_scatter_skin_mode = true
		m.backlight_enabled = true
		var c: Array = d.get("sss_color", [0.8, 0.3, 0.3])
		m.backlight = Color(c[0], c[1], c[2]) * 0.25
	if d.has("clearcoat"):
		m.clearcoat_enabled = true
		m.clearcoat = d["clearcoat"]
		m.clearcoat_roughness = 0.35
	if d.get("unshaded", false):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

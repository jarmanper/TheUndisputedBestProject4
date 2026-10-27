shader_type spatial;
// Suspend visual: translucent cyan ghost left behind by a moving/frozen body.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.0);
	float scan = 0.75 + 0.25 * sin(FRAGCOORD.y * 0.8 + TIME * 12.0);
	ALBEDO = color.rgb * (0.12 + fres * 1.2) * scan * fade;
}

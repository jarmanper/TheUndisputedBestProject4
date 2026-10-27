shader_type spatial;
// Combat visual: brief additive flash on a hit target. Use as
// `material_overlay` and animate `flash` from 1 to 0. Visual only.
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.9, 0.85, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 1.5);
	ALBEDO = color.rgb * flash * (0.35 + fres * 1.5);
}

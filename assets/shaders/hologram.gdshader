shader_type spatial;
// Marking visual: holographic tracker indicator (scanlines, flicker, texture mask).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D mask : source_color, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.1, 1.0);
uniform float intensity = 2.5;
uniform float spin = 0.6;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float a = TIME * spin;
	uv = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * uv;
	float m = texture(mask, uv * 0.5 + 0.5).a;
	float scan = 0.7 + 0.3 * sin(FRAGCOORD.y * 1.3 - TIME * 20.0);
	float flick = 0.85 + 0.15 * sin(TIME * 37.0) * sin(TIME * 13.0);
	ALBEDO = color.rgb * intensity * m * scan * flick;
}

shader_type spatial;
// Marking visual: pulsing outline + inner rim glow. Put this material in a
// target's `material_overlay` (or as next_pass). Visual only.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, blend_add;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.08, 1.0);
uniform float width = 0.012;
uniform float pulse_speed = 2.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.6;

void vertex() {
	VERTEX += NORMAL * width * (1.0 + 0.35 * sin(TIME * pulse_speed * 6.2832));
}

void fragment() {
	float p = 0.6 + 0.4 * sin(TIME * pulse_speed * 6.2832);
	ALBEDO = color.rgb * intensity * p;
}

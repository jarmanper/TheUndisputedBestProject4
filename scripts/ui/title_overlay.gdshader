shader_type canvas_item;
// Title screen film treatment, drawn over the 3D backdrop but *under* the menu
// text, so the mechanism gets lens character while the type stays crisp.
// Cheap: one screen sample per channel, no loops.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.0;
uniform float aberration : hint_range(0.0, 4.0) = 0.65;
uniform float halation : hint_range(0.0, 1.0) = 0.12;
uniform float lift : hint_range(0.0, 0.1) = 0.014;
uniform vec4 shadow_tint : source_color = vec4(0.46, 0.56, 0.76, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d2 = dot(c, c);

	// Lateral chromatic aberration: zero in the centre, grows towards the edges.
	vec2 off = c * d2 * aberration * 0.012;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// Halation: warm bleed around the hot brass speculars.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col += vec3(1.0, 0.74, 0.48) * smoothstep(0.78, 1.7, luma) * halation;

	// Cold shadows, warm highlights -- the split that makes brass read as brass.
	col = mix(col * mix(shadow_tint.rgb * 1.5, vec3(1.0), smoothstep(0.0, 0.28, luma)), col, 0.70);

	vec2 vc = c;
	vc.x *= 1.12;
	col *= 1.0 - smoothstep(0.28, 0.92, length(vc)) * vignette_strength;

	// Film blacks are never zero.
	col += vec3(lift * 0.9, lift, lift * 1.25) * (1.0 - col);

	COLOR = vec4(col, 1.0);
}

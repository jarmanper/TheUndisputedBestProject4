shader_type canvas_item;
// Title screen post overlay: vignette, film grain, faint scanlines, red edge tint.

uniform float vignette_strength = 1.15;
uniform float grain_amount = 0.045;
uniform float scanline_amount = 0.015;
uniform vec4 tint : source_color = vec4(0.35, 0.02, 0.02, 1.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	c.x *= 1.25;
	float d = length(c);
	float vig = smoothstep(0.25, 0.85, d) * vignette_strength;
	float t = floor(TIME * 24.0);
	float g = hash(FRAGCOORD.xy + vec2(t * 37.0, t * 11.0)) - 0.5;
	float scan = sin(FRAGCOORD.y * 1.6 + TIME * 3.0) * 0.5 + 0.5;
	float dark = clamp(vig, 0.0, 1.0);
	vec3 col = mix(vec3(0.0), tint.rgb * 0.4, smoothstep(0.5, 1.0, d) * 0.5);
	float a = dark * 0.92 + scan * scanline_amount;
	// Grain: add light/dark speckle by blending toward white or black.
	col += vec3(max(g, 0.0)) * grain_amount * 4.0;
	a = clamp(a + abs(g) * grain_amount, 0.0, 1.0);
	COLOR = vec4(col, a);
}

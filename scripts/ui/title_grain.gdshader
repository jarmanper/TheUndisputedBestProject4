shader_type canvas_item;
// Fine animated film grain, drawn last so it sits over the type as well as the
// backdrop. Deliberately weak -- it should be felt, not seen.

uniform float amount : hint_range(0.0, 0.2) = 0.038;
uniform float rate = 20.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float t = floor(TIME * rate);
	float g = hash(FRAGCOORD.xy + vec2(t * 37.0, t * 11.0)) - 0.5;
	COLOR = vec4(vec3(step(0.0, g)), abs(g) * amount * 2.0);
}

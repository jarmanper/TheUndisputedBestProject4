shader_type spatial;
// Suspend visual: a bubble of slowed time. Refracts and desaturates what is
// behind it, adds chromatic fringing, ripples and a ticking clock-face glow.
// Visual only: drive `strength` (0..1) from gameplay code to fade it in/out.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D clock_tex : source_color, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float refraction = 0.035;
uniform float ripple_speed = 0.6;
uniform float clock_speed = 0.15;

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 2.5);
	float t = TIME * ripple_speed;
	float ripple = sin(fres * 24.0 - t * 6.2832) * 0.5 + 0.5;
	vec2 off = n.xy * refraction * (0.4 + fres) * strength * (0.7 + 0.3 * ripple);
	float ca = 0.006 * strength * (0.5 + fres);
	vec3 col;
	col.r = textureLod(screen_tex, SCREEN_UV + off * (1.0 + ca * 40.0), 1.5).r;
	col.g = textureLod(screen_tex, SCREEN_UV + off, 1.5).g;
	col.b = textureLod(screen_tex, SCREEN_UV + off * (1.0 - ca * 40.0), 1.5).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 slowed = mix(col, vec3(lum) * tint.rgb * 1.1, 0.55 * strength);
	// rotating clock dial projected on the bubble's front
	vec2 cuv = UV * 2.0 - 1.0;
	float a = clock_speed * TIME;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	vec4 clock = texture(clock_tex, rot * cuv * 0.5 + 0.5);
	vec3 glow = tint.rgb * (fres * 1.6 + clock.a * 0.8 * (1.0 - fres)) * strength;
	ALBEDO = slowed + glow;
	ALPHA = clamp((0.35 + fres * 0.65) * strength, 0.0, 1.0);
}

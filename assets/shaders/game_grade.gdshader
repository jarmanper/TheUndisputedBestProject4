shader_type canvas_item;
render_mode blend_mix, unshaded;

// Always-on cinematic pass over gameplay: fine animated film grain, a gentle
// constant vignette and a very slight chromatic aberration at the frame edge.
// Makes the image read as *filmed* rather than *rendered*. Deliberately subtle:
// if you can see the grain instead of just feeling it, turn `grain` down.
//
// Driven by scripts/game/hud.gd; intensities are scaled by the graphics
// quality setting (see scripts/game/ui_settings.gd).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

// Peak grain amplitude in the shadows/midtones (0 = off).
uniform float grain : hint_range(0.0, 0.2) = 0.030;
// Grain cell size in pixels. Slightly above 1 keeps it from shimmering.
uniform float grain_size : hint_range(1.0, 4.0) = 1.5;
// How many times a second the grain pattern is resampled. Film-like, not per-frame.
uniform float grain_rate : hint_range(1.0, 60.0) = 20.0;
// How dark the corners get.
uniform float vignette : hint_range(0.0, 1.0) = 0.26;
// Radial RGB split at the frame corners, in UV units. Keep this sub-pixel:
// at 1920 wide, 0.0008 is about a 0.8 px split in the corners, which is felt
// and not seen. Anything past ~0.002 shows as a rainbow on every vertical edge.
uniform float aberration : hint_range(0.0, 0.004) = 0.0008;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	float r2 = dot(c, c);

	// Chromatic aberration: zero in the middle, grows toward the corners so the
	// centre of the screen (where the player aims) stays perfectly sharp.
	vec3 col;
	if (aberration > 0.0) {
		// Fade the split out in the last ~2% of the frame. Without this the
		// clamped R and B samples disagree at the border and leave a hard
		// coloured seam right around the edge of the screen.
		vec2 edge2 = min(uv, vec2(1.0) - uv);
		float edge = smoothstep(0.0, 0.02, min(edge2.x, edge2.y));
		vec2 off = c * aberration * r2 * 4.0 * edge;
		col.r = texture(screen_tex, clamp(uv + off, vec2(0.0), vec2(1.0))).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, clamp(uv - off, vec2(0.0), vec2(1.0))).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}

	// Vignette: soft, constant, never fully black. The HUD keeps its own red
	// damage vignette on top of this one.
	col *= 1.0 - vignette * smoothstep(0.05, 0.62, r2 * 2.0);

	// Film grain. Quantised in time so it looks like film stock rather than
	// per-frame noise, and rolled off in the highlights the way real grain is.
	if (grain > 0.0) {
		vec2 cell = floor(uv / SCREEN_PIXEL_SIZE / max(grain_size, 1.0));
		float t = floor(TIME * grain_rate);
		float n = hash12(cell + vec2(t * 7.13, t * 3.71)) - 0.5;
		float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col += n * grain * (1.0 - smoothstep(0.30, 0.95, luma));
	}

	COLOR = vec4(col, 1.0);
}

shader_type spatial;
// (Alpha-blended copy of magic_circle.gdshader, for transparent viewports.)
// An arcane circle drawn on a flat quad (UV 0..1): an outer double ring
// with a band of rune marks turning one way, an eight-pointed star turning
// the other, an inner ring and a bright core. `grow` (0..1) draws it in from
// the centre out; `fade` takes it away. Additive, unshaded, never fogged.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.72, 0.45, 1.0, 1.0);
uniform float grow = 1.0;
uniform float fade = 1.0;
uniform float spin = 0.25;
uniform float strength = 1.3;

float ring(float r, float at, float w) {
	return 1.0 - smoothstep(0.0, w, abs(r - at));
}

// Distance to the edges of a regular star polygon with `n` points.
float star_line(vec2 p, float n, float r_out, float r_in, float w) {
	float a = atan(p.y, p.x);
	float seg = TAU / n;
	float k = mod(a + seg * 0.5, seg) - seg * 0.5;
	vec2 q = length(p) * vec2(cos(k), abs(sin(k)));
	vec2 a0 = vec2(r_out, 0.0);
	vec2 a1 = vec2(r_in * cos(seg * 0.5), r_in * sin(seg * 0.5));
	vec2 e = a1 - a0;
	float t = clamp(dot(q - a0, e) / dot(e, e), 0.0, 1.0);
	return 1.0 - smoothstep(0.0, w, length(q - a0 - e * t));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float t = TIME * spin;
	float lines = 0.0;
	// Outer double ring.
	lines += ring(r, 0.97, 0.012) + ring(r, 0.9, 0.008);
	// Rune band: short ticks and little glyph blocks, turning slowly.
	float ra = a + t;
	float cells = 48.0;
	float cell = fract(ra / TAU * cells);
	float id = floor(ra / TAU * cells);
	float glyph = step(0.5, fract(sin(id * 12.9898) * 43758.5453));
	float band = step(0.915, r) * step(r, 0.955);
	float mark = band * (step(0.15, cell) * step(cell, 0.35) + glyph * step(0.55, cell) * step(cell, 0.85) * step(0.925, r));
	lines += mark * 0.9;
	// The star, turning the other way.
	vec2 sp = vec2(cos(a - t * 1.6), sin(a - t * 1.6)) * r;
	lines += star_line(sp, 8.0, 0.86, 0.38, 0.012) * 0.9;
	// Inner rings and dots at the star's points.
	lines += ring(r, 0.42, 0.01) + ring(r, 0.36, 0.006) * 0.7;
	float pa = mod(a - t * 1.6 + TAU / 16.0, TAU / 8.0) - TAU / 16.0;
	lines += (1.0 - smoothstep(0.0, 0.03, length(vec2(r - 0.86, pa * 0.86)))) * 1.2;
	// Core glow and a soft disc.
	float core = exp(-r * 6.0) * 0.8 + (1.0 - smoothstep(0.0, 0.9, r)) * 0.08;
	// Drawn in from the centre outward.
	float drawn = 1.0 - smoothstep(grow * 1.05 - 0.05, grow * 1.05, r);
	float pulse = 0.85 + 0.15 * sin(TIME * 4.0);
	float v = (clamp(lines, 0.0, 1.5) + core) * drawn * fade * pulse;
	vec3 c = mix(tint.rgb, vec3(1.0, 0.95, 1.0), clamp(lines - 0.6, 0.0, 1.0) * 0.6);
	ALBEDO = c * strength;
	ALPHA = clamp(v, 0.0, 1.0);
}

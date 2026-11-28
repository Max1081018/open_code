shader_type spatial;
// A rune cut into a standing stone, glowing in its guardian's colour: a
// stave with one of four branch patterns (by `seed`), a bright core line and
// a soft glow round it, breathing slowly. Additive, so it reads on any rock.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.4, 0.7, 1.0);
uniform float energy = 1.4;
uniform float seed = 0.0;
uniform vec2 extent = vec2(0.34, 1.1);   // the quad's size in metres

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = (vec2(UV.x, 1.0 - UV.y) - 0.5) * extent;
	float d = seg(p, vec2(0.0, -0.42), vec2(0.0, 0.42));
	int k = int(mod(seed, 4.0));
	if (k == 0) {
		d = min(d, seg(p, vec2(0.0, 0.42), vec2(0.12, 0.26)));
		d = min(d, seg(p, vec2(0.0, 0.2), vec2(0.12, 0.04)));
	} else if (k == 1) {
		d = min(d, seg(p, vec2(0.0, 0.3), vec2(0.12, 0.17)));
		d = min(d, seg(p, vec2(0.12, 0.17), vec2(0.0, 0.04)));
	} else if (k == 2) {
		d = min(d, seg(p, vec2(-0.12, 0.22), vec2(0.12, -0.02)));
	} else {
		d = min(d, seg(p, vec2(0.0, 0.18), vec2(-0.12, 0.34)));
		d = min(d, seg(p, vec2(0.0, 0.18), vec2(0.12, 0.34)));
	}
	float core = 1.0 - smoothstep(0.011, 0.024, d);
	float glow = exp(-d * 26.0) * 0.45;
	float breathe = 0.82 + 0.18 * sin(TIME * 1.7 + seed * 2.3);
	ALBEDO = mix(tint, vec3(1.0), core * 0.35) * (core * 1.3 + glow) * energy * breathe;
}

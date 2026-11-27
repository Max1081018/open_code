shader_type spatial;
// A foe's coming blow, drawn on the ground: a wedge the size of its reach,
// pointing the way it faces (+Z), outlined in warm red, filling from the
// foe outward as the wind-up runs (`fill` 0..1). Flashes when it lands.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.18, 1.0);
uniform float fill = 0.0;
uniform float half_span = 0.9;   // radians either side of straight ahead
uniform float flash = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = abs(atan(p.x, p.y));
	if (r > 1.0 || a > half_span) {
		discard;
	}
	float rim = (1.0 - smoothstep(0.0, 0.035, 1.0 - r)) + (1.0 - smoothstep(0.0, 0.04 / max(r, 0.05), half_span - a));
	float inside = step(r, fill) * (0.35 + 0.25 * smoothstep(fill - 0.12, fill, r));
	float a_out = clamp(rim * 0.85 + inside + 0.08 + flash * 0.6, 0.0, 0.95);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.85, 0.6), flash);
	ALPHA = a_out * (0.6 + 0.4 * fill);
}

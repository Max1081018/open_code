shader_type spatial;
// A sword slash: a crescent of light swept round the heroine. `progress`
// runs 0 -> 1: the bright head races along the arc (UV.x), a fading wake
// trails behind it, the outer edge (UV.y = 1) burns white.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float progress = 0.0;
uniform float strength = 2.1;

void fragment() {
	float head = progress * 1.3;
	float behind = head - UV.x;
	if (behind < 0.0) {
		discard;
	}
	float wake = exp(-behind * 3.2) * (1.0 - smoothstep(0.85, 1.0, progress));
	// Thin toward the inner radius, thick at the edge, tapering at both ends.
	float edge = pow(UV.y, 1.6);
	float ends = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.85, UV.x);
	float a = wake * edge * ends;
	vec3 c = mix(core.rgb, vec3(1.0), smoothstep(0.85, 1.0, UV.y) * exp(-behind * 10.0) * 0.5);
	ALBEDO = c * a * strength;
}

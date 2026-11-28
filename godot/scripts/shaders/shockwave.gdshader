shader_type spatial;
// A shockwave on the ground: a thin band of coloured light racing out from
// the centre (`progress` 0 -> 1 over the quad's radius), soft on both edges,
// with a faint wash inside it, thinning and fading as it spreads.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.36, 1.0, 1.0);
uniform float progress = 0.0;
uniform float strength = 1.0;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	if (r > 1.0) {
		discard;
	}
	float p = progress;
	float w = mix(0.09, 0.025, p);
	float band = exp(-pow((r - p) / w, 2.0));
	float wash = smoothstep(0.0, p, r) * step(r, p) * 0.12;
	float life = 1.0 - smoothstep(0.55, 1.0, p);
	vec3 c = mix(tint.rgb, vec3(1.0, 0.96, 1.0), band * 0.2);
	ALBEDO = c * (band + wash) * life * strength;
}

shader_type spatial;
// A soft violet dusk laid under a rune circle, so its additive lines stay
// coloured on bright sunlit grass and stone. A round, feathered disc.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 shade : source_color = vec4(0.16, 0.08, 0.3, 1.0);
uniform float amount = 1.0;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = shade.rgb;
	ALPHA = (1.0 - smoothstep(0.3, 1.0, r)) * 0.55 * amount;
}

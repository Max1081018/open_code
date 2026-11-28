shader_type spatial;
// A warning lane on the ground (UV.x across, UV.y from the foe outward):
// bright edges, a fill racing from the foe to the tip as the blow winds up
// (`fill` 0 -> 1), chevrons flowing outward, then a flash when it lands.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.4, 0.2, 1.0);
uniform float fill = 0.0;
uniform float flash = 0.0;
uniform float fade = 1.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float along = 1.0 - UV.y;   // 0 at the foe, 1 at the tip
	float edge = smoothstep(0.78, 0.96, x) * (1.0 - smoothstep(0.96, 1.0, x));
	float inside = 1.0 - smoothstep(0.9, 1.0, x);
	float filled = step(along, fill) * inside;
	float chev = smoothstep(0.55, 0.8, fract(along * 6.0 - x * 0.6 - TIME * 2.2)) * inside * 0.35;
	float tip_fade = 1.0 - smoothstep(0.9, 1.0, along);
	float v = (edge * 0.9 + filled * 0.35 + chev + flash * inside * 1.4) * tip_fade * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.95, 0.85), flash * 0.4) * v;
}

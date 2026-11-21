shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, blend_add;
// A column of starlight rising into the sky: bright core, soft falloff to the
// sides of the cylinder, rippling bands drifting upward.
uniform vec4 color : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform float intensity = 1.6;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float core = pow(facing, 3.0);
	float bands = 0.75 + 0.25 * sin(UV.y * 60.0 - TIME * 3.0);
	float fade = smoothstep(1.0, 0.6, UV.y) * smoothstep(0.0, 0.03, UV.y);
	ALBEDO = color.rgb * intensity * core * bands * fade;
}

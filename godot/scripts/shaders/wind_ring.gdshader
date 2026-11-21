shader_type spatial;
// The glowing mark on the ground where an updraft rises: a soft ring with a
// slowly turning dashed inner circle, so it can be found from the air.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 tint : source_color = vec4(0.6, 0.92, 1.0, 1.0);
uniform float strength = 0.7;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float outer = smoothstep(0.08, 0.0, abs(r - 0.86)) ;
	float dashes = step(0.5, fract(ang * 3.0 / 3.14159 + TIME * 0.15)) * smoothstep(0.05, 0.0, abs(r - 0.62));
	float glow = (1.0 - smoothstep(0.0, 1.0, r)) * 0.18;
	float pulse = 0.8 + 0.2 * sin(TIME * 2.0);
	ALBEDO = tint.rgb * (outer + dashes * 0.7 + glow) * strength * pulse;
}

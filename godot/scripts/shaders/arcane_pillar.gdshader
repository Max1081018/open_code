shader_type spatial;
// A column of arcane light on an open cylinder: bright and narrow at the
// base, thinning and fading as it rises, streaked by bands drifting up, and
// soft at its silhouette (brightest where the view passes through the most
// light). `height` is the cylinder's height in metres.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.72, 0.45, 1.0, 1.0);
uniform float fade = 1.0;
uniform float strength = 0.32;
uniform float height = 10.0;
varying float hy;

void vertex() {
	hy = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}

void fragment() {
	float rise = fract(hy * 2.5 - TIME * 0.9);
	float streak = 0.55 + 0.45 * smoothstep(0.0, 0.25, rise) * (1.0 - smoothstep(0.25, 0.9, rise));
	float wisp = 0.7 + 0.3 * sin(UV.x * TAU * 5.0 + TIME * 2.5 + hy * 6.0);
	float facing = abs(dot(NORMAL, VIEW));
	float body = pow(facing, 2.0);
	float v = pow(1.0 - hy, 2.2) * streak * wisp * body * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.95, 1.0), pow(1.0 - hy, 8.0) * 0.25) * v * strength;
}

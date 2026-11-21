shader_type spatial;
// A column of rising wind: translucent ribbons twisting upward around an open
// cylinder, brightest at the silhouette, fading out at the base and the top.
// Additive, so it reads as light and air rather than a solid.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.92, 1.0, 1.0);
uniform float strength = 0.3;
uniform float rise = 0.35;      // ribbon speed up the column (UV per second)
uniform float twist = 1.6;      // turns of the ribbons over the column's height
uniform float fade_far = 380.0; // metres: gone beyond this

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float v = 1.0 - UV.y; // 0 at the base, 1 at the top
	float u = UV.x;
	// Ribbons: thin bands that wrap the column and slide upward.
	float band = u * 7.0 + v * twist * 7.0 - TIME * rise * 7.0;
	float wisps = noise(vec2(band * 0.9, v * 3.0 - TIME * rise * 2.0));
	float ribbon = smoothstep(0.8, 0.98, sin(band * 3.14159) * 0.5 + 0.5) * smoothstep(0.35, 0.8, wisps);
	// Fine streaks for speed.
	float streak = smoothstep(0.82, 1.0, noise(vec2(u * 40.0, v * 4.0 - TIME * rise * 6.0)));
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float shape = smoothstep(0.0, 0.12, v) * (1.0 - smoothstep(0.7, 1.0, v));
	float dist = length(VERTEX);
	float far = 1.0 - smoothstep(fade_far * 0.6, fade_far, dist);
	// Up close the column thins out so it does not wall off the view.
	float near = smoothstep(4.0, 30.0, dist);
	float a = (ribbon * 0.9 + streak * 0.45 + rim * 0.08) * shape * far * strength * mix(0.35, 1.0, near);
	ALBEDO = tint.rgb * a;
}

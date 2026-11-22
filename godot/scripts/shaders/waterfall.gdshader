shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, blend_mix;
// A ribbon of falling water: streaks scrolling down, brighter at the lip,
// thinning to mist at the bottom.
uniform vec4 tint : source_color = vec4(0.78, 0.92, 1.0, 0.85);
uniform float speed = 1.6;
uniform float night = 0.0;   // unshaded, so dimmed by hand after dark

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float streak = noise(vec2(uv.x * 26.0, uv.y * 3.0 - TIME * speed * 3.0));
	streak += 0.5 * noise(vec2(uv.x * 60.0, uv.y * 6.0 - TIME * speed * 5.0));
	float edge = smoothstep(0.0, 0.15, uv.x) * smoothstep(1.0, 0.85, uv.x);
	float fade = 1.0 - smoothstep(0.55, 1.0, uv.y);
	float a = (0.35 + 0.5 * streak) * edge * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0), streak * 0.6 + (1.0 - uv.y) * 0.2) * mix(1.0, 0.22, night);
	ALPHA = clamp(a * tint.a, 0.0, 1.0);
}

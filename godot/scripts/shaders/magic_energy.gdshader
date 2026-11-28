shader_type spatial;
// Violet arcane energy for the heroine's magic grip: soft at the rim, bright
// in streaming bands that flow along UV.y, flickering with a slow noise.
// Additive and unshaded, so it glows without ever hiding what is behind it.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.92, 0.78, 1.0);
uniform vec3 edge : source_color = vec3(0.55, 0.22, 1.0);
uniform float energy = 0.4;
uniform float flow = 1.6;
uniform float rim_only = 1.0;   // 1: fresnel rim (spheres); 0: strand across UV.x
uniform float seed = 0.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float shape;
	if (rim_only > 0.5) {
		float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
		shape = pow(f, 1.6) * 0.9 + 0.12;
	} else {
		float x = abs(UV.x - 0.5) * 2.0;
		shape = (1.0 - smoothstep(0.0, 1.0, x));
		shape *= shape;
	}
	float t = TIME * flow + seed * 7.0;
	float bands = n(vec2(UV.x * 3.0 + seed, UV.y * 6.0 - t)) * 0.65 + n(vec2(UV.x * 9.0, UV.y * 14.0 - t * 1.7)) * 0.35;
	float glow = shape * (0.45 + bands * 0.9);
	vec3 c = mix(edge, core, smoothstep(0.55, 1.0, glow));
	// Never a slab of colour across the lens: fade out close to the camera.
	float near_fade = smoothstep(0.6, 2.8, -VERTEX.z);
	ALBEDO = c * glow * energy * near_fade;
}

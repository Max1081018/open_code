shader_type spatial;
// Molten lava: plates of dark crust drifting over glowing orange, the hot
// seams pulsing; bright enough to bloom. Used for the crater pools.
render_mode unshaded, fog_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = wpos.xz * 0.12 + vec2(TIME * 0.04, TIME * 0.025);
	float n = vnoise(q) * 0.6 + vnoise(q * 2.7) * 0.3 + vnoise(q * 7.0) * 0.1;
	float crust = smoothstep(0.5, 0.64, n);
	vec3 hot = mix(vec3(1.0, 0.32, 0.04), vec3(1.0, 0.78, 0.25), vnoise(q * 4.0 + TIME * 0.2));
	float pulse = 0.85 + 0.15 * sin(TIME * 1.7 + n * 8.0);
	ALBEDO = mix(hot * 2.4 * pulse, vec3(0.1, 0.05, 0.04), crust);
}

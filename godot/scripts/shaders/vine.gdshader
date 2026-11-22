shader_type spatial;
// Vines and roots trailing from a floating isle's rim: leafy green at the
// top fading to dark root, swaying gently; leaf gaps cut by noise.
render_mode cull_disabled, specular_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec3 vbase;
varying float vside;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vbase = base;
	vside = (VERTEX.x + VERTEX.z) * 4.0;
	float sway = sin(TIME * 0.9 + base.x * 0.3 + base.z * 0.2) * 0.25 * UV.y * UV.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	float leaf = hash(floor(vec2(vside * 3.0, UV.y * 22.0)) + floor(vbase.xz * 3.0));
	if (leaf < 0.18 + UV.y * 0.45) {
		discard;
	}
	vec3 top = vec3(0.38, 0.62, 0.26);
	vec3 bottom = vec3(0.16, 0.24, 0.12);
	ALBEDO = mix(top, bottom, UV.y) * (0.85 + leaf * 0.3);
	ROUGHNESS = 0.85;
}

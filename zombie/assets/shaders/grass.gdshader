shader_type spatial;
// Grass tufts and flowers drawn through a MultiMesh. Colour comes from the
// vertex colour (ground-matching at the root, lighter at the tip) times the
// per-instance tint, and the blades sway in a gentle wind that rolls across the
// island. Height above the root is stored in UV.y (0 = root, 1 = tip).
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float wind_strength = 0.07;
uniform float wind_speed = 1.5;

varying vec3 tint;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = UV.y;
	float gust = sin(TIME * wind_speed + world.x * 0.35 + world.z * 0.22)
		+ 0.5 * sin(TIME * wind_speed * 2.3 + world.z * 0.8);
	VERTEX.x += gust * wind_strength * h * h;
	VERTEX.z += gust * wind_strength * 0.5 * h * h;
}

void fragment() {
	// Light every blade (both faces) like the ground it grows from, so tufts
	// read as part of the lawn instead of dark spikes.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 base = srgb_to_linear(COLOR.rgb * tint);
	ALBEDO = base;
	ROUGHNESS = 1.0;
	// a touch of fake translucency at the tips
	EMISSION = base * 0.10 * UV.y;
}

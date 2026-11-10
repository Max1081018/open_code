shader_type spatial;
// Procedural palm: vertex colour (sRGB) for albedo; UV.y = how much this vertex
// sways (0 at the root of the trunk, up to 1 at frond tips), UV.x = distance
// along a frond (droop). The whole crown nods in the wind and fronds flutter.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float wind = 1.0;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME;
	float sway = UV.y;
	float gust = sin(t * 0.9 + w.x * 0.21) * 0.6 + sin(t * 2.1 + w.z * 0.37) * 0.25;
	VERTEX.x += gust * 0.18 * sway * sway * wind;
	VERTEX.z += cos(t * 0.8 + w.z * 0.19) * 0.10 * sway * sway * wind;
	// fronds flutter more toward their tips
	float flutter = UV.x * UV.x;
	VERTEX.y += sin(t * 3.3 + VERTEX.x * 2.0 + VERTEX.z * 1.7) * 0.06 * flutter * wind;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.9;
	// a little light through the leaves
	EMISSION = ALBEDO * 0.08 * UV.x;
}

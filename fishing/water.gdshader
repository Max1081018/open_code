shader_type spatial;
// Stylized low-poly water for the GL Compatibility renderer: sine waves push the
// vertices, normals are recomputed from the same waves so the sun sparkles move,
// and a fresnel term brightens the grazing angle toward the sky.
//
// The wave formula here is mirrored in game.gd (wave_height()) so the bobber
// floats at exactly the same height as the surface under it.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.02, 0.13, 0.27);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.30, 0.44);
uniform vec3 sky_tint : source_color = vec3(0.32, 0.55, 0.74);
uniform float wave_speed = 0.9;
uniform float wave_height = 0.16;

float wave(vec2 p, float t) {
	return sin(p.x * 0.60 + t) * 0.5
		 + sin(p.y * 0.80 + t * 1.3) * 0.5
		 + sin((p.x + p.y) * 0.40 + t * 0.7) * 0.5;
}

void vertex() {
	float t = TIME * wave_speed;
	float h = wave(VERTEX.xz, t);
	VERTEX.y += h * wave_height;

	// Finite-difference normal from the same height field.
	float e = 0.35;
	float hx = wave(VERTEX.xz + vec2(e, 0.0), t);
	float hz = wave(VERTEX.xz + vec2(0.0, e), t);
	NORMAL = normalize(vec3((h - hx) * wave_height, e, (h - hz) * wave_height));
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
	vec3 col = mix(deep_color, shallow_color, clamp(NORMAL.y, 0.0, 1.0));
	col = mix(col, sky_tint, fres * 0.35);
	ALBEDO = col;
	ROUGHNESS = 0.28;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}

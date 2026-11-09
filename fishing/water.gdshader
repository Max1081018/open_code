shader_type spatial;
// Stylized lake water for the GL Compatibility renderer (mobile-friendly):
//  - 4 summed Gerstner waves give gentle rolling swells with analytic normals
//  - a second layer of fine ripples adds sparkle without extra geometry
//  - depth-tinted colour, fresnel sky reflection, a tight sun glint
//  - a touch of foam on the wave crests
//
// The vertical part of the Gerstner sum is mirrored in game.gd (wave_height())
// so the bobber floats on the surface. Keep WAVES in sync with WATER_WAVES there.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.015, 0.08, 0.19);
uniform vec3 shallow_color : source_color = vec3(0.04, 0.24, 0.38);
uniform vec3 sky_color : source_color = vec3(0.42, 0.60, 0.78);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 sun_dir = vec3(0.45, 0.7, 0.35);
uniform float time_scale = 1.0;

// Each wave: xy = direction, z = wavelength, w = amplitude (metres).
const vec4 WAVES[4] = {
	vec4( 0.8,  0.6, 16.0, 0.28),
	vec4(-0.7,  0.7, 10.0, 0.16),
	vec4( 0.2, -0.95, 6.0, 0.09),
	vec4(-0.95,-0.25, 3.5, 0.05)
};
const float STEEP = 0.5;   // horizontal pinch of the crests (0..1)
const float GRAV = 9.8;

vec3 gerstner(vec2 pos, float t, out vec3 tangent, out vec3 binormal) {
	vec3 disp = vec3(0.0);
	tangent = vec3(1.0, 0.0, 0.0);
	binormal = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 4; i++) {
		vec2 dir = normalize(WAVES[i].xy);
		float k = 6.28318 / WAVES[i].z;
		float amp = WAVES[i].w;
		float speed = sqrt(GRAV / k);
		float f = k * dot(dir, pos) + t * speed;
		float cf = cos(f);
		float sf = sin(f);
		disp.x += STEEP * amp * dir.x * cf;
		disp.z += STEEP * amp * dir.y * cf;
		disp.y += amp * sf;
		float ka = k * amp;
		tangent  += vec3(-STEEP * dir.x * dir.x * ka * sf, dir.x * ka * cf, -STEEP * dir.x * dir.y * ka * sf);
		binormal += vec3(-STEEP * dir.x * dir.y * ka * sf, dir.y * ka * cf, -STEEP * dir.y * dir.y * ka * sf);
	}
	return disp;
}

varying float v_height;
varying vec3 v_world;

void vertex() {
	float t = TIME * time_scale;
	vec3 tangent;
	vec3 binormal;
	vec3 d = gerstner(VERTEX.xz, t, tangent, binormal);
	VERTEX += d;
	NORMAL = normalize(cross(binormal, tangent));
	v_height = d.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fine ripple detail perturbs the normal for sparkle.
	vec2 rp = v_world.xz;
	float r = sin(rp.x * 1.8 + TIME * 1.7) * cos(rp.y * 2.1 - TIME * 1.3);
	vec3 n = normalize(NORMAL + vec3(r * 0.03, 0.0, r * 0.03));

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), n), 0.0, 1.0), 5.0);
	vec3 col = mix(deep_color, shallow_color, clamp(n.y * 0.5 + 0.5, 0.0, 1.0));
	col = mix(col, sky_color, fres * 0.35);

	// Foam only on the very highest crests.
	float foam = smoothstep(0.44, 0.58, v_height);
	col = mix(col, foam_color, foam * 0.5);

	ALBEDO = col;
	ROUGHNESS = mix(0.22, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	vec3 h = normalize(normalize(sun_dir) + normalize(VIEW));
	float glint = pow(max(dot(n, h), 0.0), 200.0);
	EMISSION = vec3(glint) * 0.35 * (1.0 - foam);
}

shader_type spatial;
// Dense meadow grass: clumps of tapered blades, swaying in travelling gusts,
// parting round the heroine, coloured from a dark root (the instance colour,
// matched to the biome) to a sunlit tip. Lit like the ground beneath it
// (normals point up) so a field reads as one soft surface, not a hedge of
// cards. Blades shrink to nothing toward the edge of the field so its
// moving border never pops.
render_mode cull_disabled, diffuse_lambert, specular_disabled, world_vertex_coords;

uniform vec3 player_pos = vec3(0.0);
uniform vec3 field_centre = vec3(0.0);
uniform float field_radius = 40.0;
uniform float wind_strength = 0.16;
uniform vec4 tip_color : source_color = vec4(0.6, 0.78, 0.36, 1.0);
uniform float tip_mix = 0.42;
// Wildflowers: the same sway, a green stem (UV.x 0) and a petal head
// (UV.x 1) in the instance's colour.
uniform bool flower_mode = false;

varying float tip;
varying vec3 root_col;
varying vec2 ground_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float vnoise(vec2 p) {
	return noise(p);
}

void vertex() {
	tip = UV.y;
	root_col = COLOR.rgb;
	ground_xz = MODEL_MATRIX[3].xz;
	// world_vertex_coords: VERTEX is already in world space.
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 world = VERTEX;
	// Fade the field's edge by shortening blades.
	float d = distance(base.xz, field_centre.xz);
	float grow = 1.0 - smoothstep(field_radius * 0.72, field_radius, d);
	// Keep blades out of the lens when the camera dips low.
	grow *= smoothstep(0.7, 2.4, distance(base, CAMERA_POSITION_WORLD));
	float h = UV.y * UV.y;
	// Gusts: a slow wave rolling across the meadow plus flutter.
	float gust = noise(base.xz * 0.06 + vec2(TIME * 0.35, TIME * 0.22));
	float flutter = sin(TIME * 3.1 + base.x * 1.7 + base.z * 1.3) * 0.25;
	vec2 wind = vec2(0.8, 0.45) * (gust * 1.4 + flutter) * wind_strength * h;
	// Part round the heroine.
	vec2 away = base.xz - player_pos.xz;
	float near = 1.0 - smoothstep(0.25, 1.3, length(away));
	near *= 1.0 - smoothstep(1.5, 2.5, abs(base.y - player_pos.y));
	vec2 push = normalize(away + vec2(0.0001)) * near * 0.45 * UV.y;
	world.xz += wind + push;
	world.y -= (near * 0.25 + length(wind) * 0.3) * UV.y;
	world = base + (world - base) * grow;
	VERTEX = world;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// Tips lighten toward sunlit yellow-green on green grass, and toward a
	// paler shade of their own colour elsewhere (violet blight, gloom).
	float greenness = clamp((root_col.g - max(root_col.r, root_col.b)) * 5.0, 0.0, 1.0);
	vec3 tip_target = mix(root_col * 1.7 + 0.04, tip_color.rgb, greenness * (root_col.g > 0.33 ? 1.0 : 0.45));
	vec3 col = mix(root_col * 0.8, mix(root_col, tip_target, tip_mix), smoothstep(0.0, 1.0, tip));
	if (flower_mode) {
		vec3 petal = mix(root_col * 0.72, vec3(1.0, 0.78, 0.2), smoothstep(0.955, 0.99, tip));
		col = UV.x > 0.5 ? petal : mix(vec3(0.2, 0.36, 0.14), vec3(0.4, 0.6, 0.26), tip);
	}
	// The same drifting cloud shadows as the ground beneath.
	float cs = vnoise(ground_xz * 0.004 + vec2(TIME * 0.006, TIME * 0.0035));
	cs = smoothstep(0.48, 0.62, cs * 0.75 + vnoise(ground_xz * 0.011 + vec2(TIME * 0.009, 0.0)) * 0.25);
	col *= 1.0 - cs * 0.32;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	// A little light through the blades.
	BACKLIGHT = vec3(0.25, 0.3, 0.12) * tip;
}

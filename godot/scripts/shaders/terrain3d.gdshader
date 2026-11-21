shader_type spatial;
// The ground: grass, soil, rock, snow and sand textures (ambientCG, CC0)
// blended by per-vertex weights (COLOR = grass, rock, snow, sand; soil takes
// the rest), sampled at two scales to hide tiling, steep rock projected from
// the side so cliffs do not stretch, a biome tint and ash from UV2.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.22;
// Town paving (TerrainGen.PLAZA_RADIUS / ROADS): cobbles drawn into the ground.
uniform sampler2D paving_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D paving_normal : filter_linear_mipmap, repeat_enable;
uniform vec4 roads[16];
uniform float road_hw[16];
uniform int road_count = 0;
uniform float plaza_radius = 0.0;
// Horizon mesh: drawn only beyond this distance (near chunks cover the rest).
uniform float cull_radius = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Signed distance to the paving (negative inside).
float paved_dist(vec2 p) {
	float d = length(p) - plaza_radius;
	for (int i = 0; i < road_count; i++) {
		vec2 a = roads[i].xy;
		vec2 b = roads[i].zw;
		vec2 ab = b - a;
		float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
		d = min(d, distance(p, a + ab * t) - road_hw[i]);
	}
	return d;
}

vec3 two_scale(sampler2D t, vec2 p) {
	return mix(texture(t, p * scale).rgb, texture(t, p * scale * 0.23).rgb, 0.35);
}

void fragment() {
	if (cull_radius > 0.0 && distance(world_pos.xz, CAMERA_POSITION_WORLD.xz) < cull_radius) {
		discard;
	}
	vec2 p = world_pos.xz;
	vec3 grass = two_scale(grass_tex, p) * vec3(0.68, 0.78, 0.55);
	vec3 soil = two_scale(soil_tex, p);
	vec3 snow = two_scale(snow_tex, p);
	vec3 sand = two_scale(sand_tex, p);
	// Rock: triplanar-ish, from the side on steep faces.
	vec3 n = abs(world_normal);
	vec3 rock_top = two_scale(rock_tex, p);
	vec3 rock_x = two_scale(rock_tex, world_pos.zy);
	vec3 rock_z = two_scale(rock_tex, world_pos.xy);
	vec3 rock = (rock_top * n.y + rock_x * n.x + rock_z * n.z) / (n.x + n.y + n.z);
	vec4 w = COLOR;
	float soil_w = max(0.0, 1.0 - w.r - w.g - w.b - w.a);
	vec3 c = (grass * w.r + rock * w.g + snow * w.b + sand * w.a + soil * soil_w)
		/ max(w.r + w.g + w.b + w.a + soil_w, 0.001);
	// Biome tint (UV2.x: overall brightness of the tint) and ash (UV2.y).
	c *= mix(1.0, UV2.x, 0.8);
	c = mix(c, c * vec3(0.32, 0.3, 0.3), UV2.y * 0.8);
	// Cobbles of the town, with a band of darker border stones at the edge
	// and a ragged rim where grass creeps over.
	float pave = 0.0;
	if (road_count > 0 && length(p) < 250.0) {
		float d = paved_dist(p) + (vnoise(p * 0.8) - 0.5) * 0.8;
		pave = 1.0 - smoothstep(-0.2, 0.2, d);
		if (pave > 0.0) {
			vec2 puv = p / 3.2;
			vec3 stones = texture(paving_tex, puv).rgb * vec3(0.9, 0.85, 0.78);
			float curb = smoothstep(-0.75, -0.3, d);
			stones = mix(stones, stones * vec3(0.7, 0.68, 0.66), curb);
			c = mix(c, stones, pave);
			vec3 nt = texture(paving_normal, puv).rgb * 2.0 - 1.0;
			vec3 wn = normalize(world_normal + vec3(nt.x, 0.0, nt.y) * 0.9);
			NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wn, 0.0)).xyz, pave));
		}
	}
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.92, 0.55, w.b), 0.78, pave);
	SPECULAR = 0.25;
}

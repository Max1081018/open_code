shader_type spatial;
// The ground: grass, soil, rock, snow and sand textures (ambientCG, CC0)
// blended by per-vertex weights (COLOR = grass, rock, snow, sand; soil takes
// the rest), sampled at two scales to hide tiling, steep rock projected from
// the side so cliffs do not stretch, a biome tint and ash from UV2.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.22;
// Town paving (TerrainGen.PLAZA_RADIUS / ROADS): cobbles drawn into the ground.
uniform sampler2D paving_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D paving_normal : filter_linear_mipmap, repeat_enable;
uniform vec4 roads[16];
uniform float road_hw[16];
uniform int road_count = 0;
uniform float plaza_radius = 0.0;
uniform float cloud_shade = 0.32;
// The Ashlands' great volcano and its lava flows (angles in radians).
uniform vec2 volcano_pos = vec2(860.0, -920.0);
uniform float volcano_r = 175.0;
uniform float flow_angles[5];
uniform float flow_reach[5];
// Horizon mesh: drawn only beyond this distance (near chunks cover the rest).
uniform float cull_radius = 0.0;
// The Sunscar Sea: its own sand, ripple normals, grains that glint.
uniform sampler2D desert_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D desert_fine : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D desert_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 desert_pos = vec2(-1500.0, -250.0);
uniform float desert_r = 800.0;
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform float sun_up = 1.0;

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
	vec3 grass = two_scale(grass_tex, p) * vec3(0.8, 0.76, 0.6);
	// Meadows are never one flat green: broad patches of lush deep grass and
	// sun-dried lighter grass, broken up again at a smaller scale.
	float meadow = vnoise(p * 0.011) * 0.6 + vnoise(p * 0.047 + 3.1) * 0.4;
	grass *= mix(vec3(0.8, 0.9, 0.76), vec3(1.12, 1.06, 0.86), smoothstep(0.2, 0.8, meadow));
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
	// Mountains: snow keeps to the gentler slopes (broken up by noise), the
	// steep faces show dark cool rock streaked downhill, and snow is a soft
	// blue-white so its shading reads instead of clipping to white.
	float up = world_normal.y;
	float high = smoothstep(18.0, 45.0, world_pos.y);
	float streak = vnoise(vec2((world_pos.x + world_pos.z) * 0.09, world_pos.y * 0.5));
	float steep = (1.0 - smoothstep(0.62 + streak * 0.12, 0.86, up)) * high;
	vec3 cliff = rock * vec3(0.56, 0.58, 0.68) * (0.78 + streak * 0.35);
	c = mix(c, cliff, clamp(steep * 1.2, 0.0, 1.0));
	c = mix(c, c * vec3(0.86, 0.9, 0.98), w.b * 0.6);
	// Biome tint: brightness in UV2.x, hue in UV (red and blue shares; green
	// takes the rest), ash in UV2.y.
	vec3 tint = vec3(UV.x, 3.0 - UV.x - UV.y, UV.y) * UV2.x;
	c *= mix(vec3(1.0), tint, 0.8);
	// The Ashlands: ash-grey ground with dark basalt fields, not a black plane.
	float ash = UV2.y;
	float basalt = smoothstep(0.45, 0.62, vnoise(world_pos.xz * 0.025) * 0.7 + vnoise(world_pos.xz * 0.09) * 0.3);
	vec3 ash_col = mix(vec3(0.5, 0.47, 0.45), vec3(0.17, 0.15, 0.16), basalt) * (0.85 + vnoise(world_pos.xz * 0.6) * 0.25);
	c = mix(c, mix(c * 0.4, ash_col, 0.9), ash);
	float lava = 0.0;
	float heat = 0.0;
	if (ash > 0.3) {
		// Lava flows: streams leaving the great crater, wandering down the
		// slopes in channels that widen across the plains.
		vec2 dv = world_pos.xz - volcano_pos;
		float rad = length(dv);
		float ang = atan(dv.y, dv.x);
		float flow = 0.0;
		for (int i = 0; i < 5; i++) {
			float a = flow_angles[i] + sin(rad * 0.022 + float(i) * 2.1) * 0.22 + (vnoise(vec2(rad * 0.02, float(i) * 7.0)) - 0.5) * 0.3;
			float da = abs(mod(ang - a + PI, TAU) - PI) * rad;
			float w = mix(3.0, 9.0, smoothstep(volcano_r * 0.3, volcano_r * 1.6, rad));
			float reach = volcano_r * (1.35 + flow_reach[i]) + (vnoise(vec2(ang * 3.0, 5.0)) - 0.5) * 50.0;
			float along = smoothstep(volcano_r * 0.2, volcano_r * 0.27, rad) * (1.0 - smoothstep(reach - 60.0, reach, rad));
			flow = max(flow, (1.0 - smoothstep(w * 0.55, w, da)) * along);
			heat = max(heat, (1.0 - smoothstep(w, w * 3.5, da)) * along);
		}
		// Thin fissures, dim, on the flatter ground only.
		vec2 q = world_pos.xz * 0.12;
		float n1 = vnoise(q) + 0.5 * vnoise(q * 2.3 + 7.0);
		float crack = 0.0;
		// Moving crust over the hot lava.
		vec2 fq = world_pos.xz * 0.18 + normalize(dv + vec2(0.001)) * TIME * 0.35;
		float crust = smoothstep(0.48, 0.66, vnoise(fq) * 0.65 + vnoise(fq * 2.6) * 0.35);
		float pulse = 0.8 + 0.2 * sin(TIME * 1.6 + vnoise(q * 0.5) * 6.0);
		lava = max(flow * (1.0 - crust * 0.85), crack) * pulse * smoothstep(0.3, 0.6, ash);
		c = mix(c, vec3(0.09, 0.05, 0.04), max(flow, crack) * smoothstep(0.3, 0.6, ash));
		// Ground just above the lava lakes is scorched and glows.
		float shore = (1.0 - smoothstep(0.05, 1.4, world_pos.y)) * smoothstep(0.5, 0.8, ash);
		heat = max(heat, shore);
		c = mix(c, vec3(0.11, 0.08, 0.075), heat * 0.7);
	}
	// Cobbles of the town, with a band of darker border stones at the edge
	// and a ragged rim where grass creeps over.
	float pave = 0.0;
	if (road_count > 0 && length(p) < 250.0) {
		float d = paved_dist(p) + (vnoise(p * 0.8) - 0.5) * 0.8;
		pave = 1.0 - smoothstep(-0.2, 0.2, d);
		if (pave > 0.0) {
			vec2 puv = p / 3.2;
			vec3 stones = texture(paving_tex, puv).rgb * vec3(0.82, 0.77, 0.7);
			// Mortar and gaps in shade, worn stone tops lighter.
			float lum = dot(stones, vec3(0.33));
			stones *= mix(0.55, 1.08, smoothstep(0.18, 0.5, lum));
			float curb = smoothstep(-0.75, -0.3, d);
			stones = mix(stones, stones * vec3(0.7, 0.68, 0.66), curb);
			c = mix(c, stones, pave);
			vec3 nt = texture(paving_normal, puv).rgb * 2.0 - 1.0;
			vec3 wn = normalize(world_normal + vec3(nt.x, 0.0, nt.y) * 0.9);
			NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wn, 0.0)).xyz, pave));
		}
	}
	// The Sunscar Sea: warm sand with wind ripples, crests catching the sun,
	// slip faces in warm shade, grains glinting toward the sun.
	float dd = distance(p, desert_pos);
	float des = w.a * (1.0 - smoothstep(desert_r - 160.0, desert_r + 40.0, dd));
	float glint = 0.0;
	if (des > 0.01) {
		vec2 duv = p * 0.11;
		vec3 dsand = mix(texture(desert_tex, duv).rgb, texture(desert_tex, p * 0.027 + 0.37).rgb, 0.4);
		dsand = mix(dsand, texture(desert_fine, p * 0.45).rgb, 0.22);
		dsand *= 0.88 + vnoise(p * 0.008) * 0.2 + vnoise(p * 0.05) * 0.06;
		vec2 wind = normalize(vec2(0.94, 0.34));
		float face = dot(world_normal.xz, wind) / max(length(world_normal.xz), 0.001) * smoothstep(0.02, 0.2, 1.0 - world_normal.y);
		dsand *= mix(vec3(1.0), vec3(1.06, 1.0, 0.92), smoothstep(0.0, 0.6, face));
		dsand = mix(dsand, dsand * vec3(0.8, 0.64, 0.52), smoothstep(0.0, 0.7, -face) * 0.55);
		// Crests a shade paler where the wind scours them.
		dsand = mix(dsand, dsand * vec3(1.08, 1.05, 1.0), smoothstep(0.96, 1.0, world_normal.y) * 0.3);
		c = mix(c, dsand, des);
		float far = smoothstep(35.0, 140.0, distance(world_pos, CAMERA_POSITION_WORLD));
		vec3 nt = texture(desert_n, duv).rgb * 2.0 - 1.0;
		vec3 big = vec3(sin(dot(p, wind) * 1.9 + vnoise(p * 0.2) * 4.0), 0.0, 0.0) * 0.12;
		vec3 wn = normalize(world_normal + (vec3(nt.x, 0.0, nt.y) * 0.75 + big) * (1.0 - far));
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wn, 0.0)).xyz, des));
		// Glints: a few grains per cell mirror the sun toward the eye.
		vec2 gp = p * 26.0;
		vec2 cell = floor(gp);
		float hsh = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		// A pinpoint grain somewhere in the cell, not the whole cell.
		vec2 spot = vec2(fract(hsh * 31.7), fract(hsh * 17.3)) * 0.6 + 0.2;
		float dot_ = 1.0 - smoothstep(0.03, 0.09, distance(fract(gp), spot));
		vec3 gn = normalize(wn + (vec3(fract(hsh * 13.1), 1.0, fract(hsh * 7.7)) - 0.5) * 0.6);
		vec3 eye = normalize(CAMERA_POSITION_WORLD - world_pos);
		float mirror = max(dot(reflect(-eye, gn), normalize(sun_dir)), 0.0);
		glint = step(0.9, hsh) * dot_ * pow(mirror, 32.0) * (1.0 - far) * des * sun_up * (0.7 + 0.3 * sin(TIME * 3.0 + hsh * 40.0));
	}
	// Relief from the ground texture itself (grass tufts, soil clods): a bump
	// normal from the texture's brightness, fading out with distance.
	float cam_d = distance(world_pos, CAMERA_POSITION_WORLD);
	if (cam_d < 60.0 && des < 0.01 && pave < 0.01) {
		vec2 tp = p * scale;
		float e = 0.004;
		float h0 = dot(texture(grass_tex, tp).rgb, vec3(0.33));
		float hx = dot(texture(grass_tex, tp + vec2(e, 0.0)).rgb, vec3(0.33));
		float hz = dot(texture(grass_tex, tp + vec2(0.0, e)).rgb, vec3(0.33));
		float bump = (1.0 - smoothstep(25.0, 60.0, cam_d)) * (w.r + soil_w) * 2.2;
		vec3 bn = normalize(world_normal + vec3(h0 - hx, 0.0, h0 - hz) * bump);
		NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
		// Crevices between tufts are darker.
		c *= mix(1.0, 0.78 + h0 * 0.5, min(bump, 1.0) * 0.6);
	}
	// Shadows of clouds drifting over the land.
	float cs = vnoise(world_pos.xz * 0.004 + vec2(TIME * 0.006, TIME * 0.0035));
	cs = smoothstep(0.48, 0.62, cs * 0.75 + vnoise(world_pos.xz * 0.011 + vec2(TIME * 0.009, 0.0)) * 0.25);
	c *= 1.0 - cs * cloud_shade;
	ALBEDO = c;
	EMISSION = vec3(1.0, 0.3, 0.05) * lava * 2.0 + vec3(0.9, 0.25, 0.05) * heat * 0.25 * smoothstep(0.3, 0.6, UV2.y)
		+ vec3(1.0, 0.95, 0.85) * glint * 2.2;
	ROUGHNESS = mix(mix(mix(0.92, 0.55, w.b), 0.78, pave), 0.96, des);
	SPECULAR = 0.25;
}

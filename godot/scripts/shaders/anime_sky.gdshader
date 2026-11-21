shader_type sky;
// Painted anime sky: deep cerulean overhead to a pale luminous horizon, a sun
// disk with a wide soft halo, and big cumulus clouds drawn the way anime
// backgrounds paint them — bright lit crowns, lilac shaded bellies, a crisp
// banded edge instead of a smooth fade — drifting slowly. Dawn and dusk tint
// everything gold and rose; night fades to indigo with stars.

uniform vec3 top_color : source_color = vec3(0.1, 0.3, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.85, 0.99);
uniform vec3 ground_color : source_color = vec3(0.42, 0.5, 0.58);
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.74, 0.92);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float cloud_cover = 0.42;
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float time_scale = 0.004;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	// Gradient: horizon glow hugging the ground line, deep blue above.
	float up = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(up, 0.55));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));

	// Sun.
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = max(dot(dir, sun_dir), 0.0);
	vec3 sun_col = LIGHT0_COLOR * sun_tint;
	col += sun_col * pow(sd, 8.0) * 0.35;           // wide halo
	col += sun_col * pow(sd, 64.0) * 0.6;           // inner glow
	col += sun_col * smoothstep(0.9993, 0.9997, sd) * 2.5;  // disk

	// Clouds on a dome above the horizon.
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.15) * 0.45;
		vec2 drift = vec2(TIME * time_scale, TIME * time_scale * 0.4);
		float n = fbm(uv * 1.1 + drift) + 0.3 * fbm(uv * 2.7 - drift * 1.7);
		float thresh = 1.18 - cloud_cover;
		float body = smoothstep(thresh, thresh + 0.05, n);
		// Thickness: dense cores have a shaded belly toward the horizon side,
		// light crowns toward the zenith and the sun.
		float dense = smoothstep(thresh + 0.05, thresh + 0.35, n);
		vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001)) * 0.06;
		float n2 = fbm((uv + to_sun) * 1.1 + drift) + 0.3 * fbm((uv + to_sun) * 2.7 - drift * 1.7);
		float sunward = smoothstep(-0.02, 0.06, n - n2);
		float shade_amt = dense * (1.0 - sunward) * 0.75;
		vec3 cc = mix(cloud_lit, cloud_shade, step(0.35, shade_amt) * 0.85 + step(0.6, shade_amt) * 0.15);
		cc = mix(cc, cc * sun_col * 1.05, 0.25 + dusk * 0.45);
		cc += vec3(0.12) * (1.0 - dense) * body;
		float fade = smoothstep(0.0, 0.18, h);  // clouds melt into the horizon haze
		col = mix(col, cc, body * fade * (1.0 - night * 0.6));
	}

	// Night: indigo and stars.
	if (night > 0.0) {
		vec3 night_col = mix(vec3(0.05, 0.07, 0.18), vec3(0.01, 0.015, 0.05), up);
		col = mix(col, night_col, night);
		vec2 sp = dir.xz / (abs(h) + 0.3) * 120.0;
		float s = step(0.9975, hash(floor(sp))) * smoothstep(0.0, 0.2, h);
		col += vec3(0.9, 0.92, 1.0) * s * night;
	}
	COLOR = col;
}

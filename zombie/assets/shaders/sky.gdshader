shader_type sky;
// Day and night sky.
//
// The palette, the way the four times of day blend into one another, and the
// sun/moon/star treatment follow the "Day and Night Sky" pack by Dimension
// Almios (MIT, licence kept beside this file). That one paints a 2D rect,
// which cannot work in a first-person game - look up and the horizon would
// stay nailed to the middle of the screen - so the same idea is rebuilt here
// as a real sky shader driven by the view direction and the sun's actual
// position, which also lets the engine's fog and ambient light pick it up.
//
// Everything is analytic: four colour stops, a disc for the sun, a disc and a
// phase for the moon, a hashed star field that twinkles, and two layers of
// drifting cloud. No textures, no cubemap, a few dozen instructions.

uniform float hour : hint_range(0.0, 24.0) = 10.0;
uniform float sunrise_hour = 6.0;
uniform float sunset_hour = 18.5;
uniform float twilight : hint_range(0.2, 3.0) = 1.0;

uniform vec4 night_top : source_color = vec4(0.015, 0.028, 0.075, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.10, 0.13, 0.26, 1.0);
uniform vec4 dawn_top : source_color = vec4(0.19, 0.27, 0.53, 1.0);
uniform vec4 dawn_horizon : source_color = vec4(1.0, 0.68, 0.48, 1.0);
uniform vec4 day_top : source_color = vec4(0.23, 0.46, 0.82, 1.0);
uniform vec4 day_horizon : source_color = vec4(0.76, 0.86, 0.93, 1.0);
uniform vec4 dusk_top : source_color = vec4(0.17, 0.16, 0.40, 1.0);
uniform vec4 dusk_horizon : source_color = vec4(0.96, 0.49, 0.33, 1.0);

uniform vec4 sun_color : source_color = vec4(1.0, 0.97, 0.86, 1.0);
uniform vec4 sun_low_color : source_color = vec4(1.0, 0.57, 0.28, 1.0);
uniform float sun_size : hint_range(0.0, 0.05) = 0.011;
uniform float sun_glow : hint_range(0.0, 4.0) = 1.3;

uniform vec4 moon_color : source_color = vec4(0.93, 0.95, 1.0, 1.0);
uniform float moon_size : hint_range(0.0, 0.05) = 0.013;
uniform float moon_phase : hint_range(-1.0, 1.0) = 0.35;

uniform float star_density : hint_range(0.0, 1.0) = 0.62;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.012;
uniform vec4 cloud_day : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_night : source_color = vec4(0.22, 0.25, 0.36, 1.0);
uniform vec4 ground_color : source_color = vec4(0.11, 0.12, 0.11, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise2(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, -1.0, 1.0);

	// Where we are in the day, as four weights that overlap through dawn and
	// dusk rather than switching over.
	float noon = (sunrise_hour + sunset_hour) * 0.5;
	float half_day = (sunset_hour - sunrise_hour) * 0.5;
	float since = (hour - noon) / max(half_day, 0.001);     // 0 noon, ±1 at sun up/down
	float band = 0.42 * twilight;
	float day_w = 1.0 - smoothstep(1.0 - band, 1.0 + band * 0.35, abs(since));
	float night_w = smoothstep(1.0 + band * 0.35, 1.0 + band * 1.6, abs(since));
	float twi = clamp(1.0 - day_w - night_w, 0.0, 1.0);
	float rising = step(since, 0.0);                        // morning side

	vec3 top = day_top.rgb * day_w + night_top.rgb * night_w
		+ mix(dusk_top.rgb, dawn_top.rgb, rising) * twi;
	vec3 hor = day_horizon.rgb * day_w + night_horizon.rgb * night_w
		+ mix(dusk_horizon.rgb, dawn_horizon.rgb, rising) * twi;
	vec3 col = mix(hor, top, pow(clamp(up, 0.0, 1.0), 0.42));

	// Stars, out once the sun is properly down and brightest overhead.
	float dark = clamp(night_w + twi * 0.35, 0.0, 1.0);
	if (dark > 0.01 && up > -0.05) {
		vec2 sc = dir.xz / (abs(dir.y) + 0.35) * 46.0;
		vec2 cell = floor(sc);
		float r = hash21(cell);
		if (r > 1.0 - star_density * 0.06) {
			vec2 off = fract(sc) - vec2(hash21(cell + 3.1), hash21(cell + 7.7));
			float d = length(off);
			float tw = 0.65 + 0.35 * sin(TIME * (1.5 + r * 4.0) + r * 30.0);
			col += vec3(0.9, 0.93, 1.0) * smoothstep(0.42, 0.0, d) * tw * dark
				* clamp(up * 2.2, 0.0, 1.0);
		}
	}

	// The sun, where the scene's own light actually comes from, so the glare
	// and the shadows agree with one another.
	vec3 sun_dir = -LIGHT0_DIRECTION;
	float sd = dot(dir, sun_dir);
	float low = 1.0 - clamp(sun_dir.y * 2.4, 0.0, 1.0);
	vec3 scol = mix(sun_color.rgb, sun_low_color.rgb, low);
	float disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.35, sd);
	float glow = pow(clamp(sd, 0.0, 1.0), 26.0) * sun_glow;
	float haze = pow(clamp(sd, 0.0, 1.0), 4.0) * 0.18 * (1.0 - clamp(up, 0.0, 1.0));
	col += scol * (disc * 6.0 + glow * 0.5 + haze) * clamp(sun_dir.y + 0.25, 0.0, 1.0);

	// The moon rides opposite the sun, with a shadowed limb for its phase.
	vec3 moon_dir = normalize(-sun_dir + vec3(0.12, 0.0, 0.08));
	float md = dot(dir, moon_dir);
	float mdisc = smoothstep(1.0 - moon_size, 1.0 - moon_size * 0.3, md);
	if (mdisc > 0.0) {
		vec3 right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
		float across = dot(dir - moon_dir * md, right) / max(moon_size, 0.0001);
		float lit = smoothstep(moon_phase - 0.25, moon_phase + 0.25, across);
		col += moon_color.rgb * mdisc * (0.25 + lit * 0.95) * dark;
		col += moon_color.rgb * pow(clamp(md, 0.0, 1.0), 300.0) * 0.35 * dark;
	}

	// Two layers of cloud, drifting at different speeds so the sky has depth.
	if (up > 0.0) {
		vec2 cuv = dir.xz / (dir.y + 0.18);
		float t = TIME * cloud_speed;
		float c1 = fbm(cuv * 0.55 + vec2(t, t * 0.5));
		float c2 = fbm(cuv * 1.3 + vec2(-t * 1.7, t * 0.9));
		float c = clamp(c1 * 0.68 + c2 * 0.42, 0.0, 1.0);
		float cover = smoothstep(0.78 - cloud_cover * 0.55, 0.95 - cloud_cover * 0.3, c);
		cover *= smoothstep(0.0, 0.22, up);
		vec3 ccol = mix(cloud_night.rgb, cloud_day.rgb, clamp(day_w + twi * 0.6, 0.0, 1.0));
		// lit from the sun's side, dark underneath
		ccol *= 0.75 + 0.45 * clamp(sd * 0.5 + 0.5, 0.0, 1.0);
		col = mix(col, ccol, cover * 0.92);
	}

	// Below the horizon the sky is not drawn so much as suggested: the ground
	// haze the terrain fades into.
	col = mix(ground_color.rgb * (0.4 + day_w * 0.8), col, smoothstep(-0.06, 0.02, up));
	COLOR = col;
}

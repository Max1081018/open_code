shader_type canvas_item;

// Day and Night Sky (free) by Dimension Almios, MIT licence.
// Put it on a ColorRect that covers the sky and drive `hour` (0 to 24): the
// gradient goes through night, dawn, day and dusk, the sun and the moon travel
// their arc and set behind the horizon line, stars and shooting stars come out at
// night and puffy clouds drift by. Every element has its own settings below; the
// node's modulate tints or fades the whole sky.
// DayNightSky (day_night_sky.gd) can drive `hour` and `day` for you.

group_uniforms Time;
uniform float hour : hint_range(0.0, 24.0) = 10.0;
// counts the days: moves the moon through its phases when `lunar_cycle_days` > 0
uniform float day = 0.0;
uniform float sunrise_hour : hint_range(0.0, 12.0) = 6.0;
uniform float sunset_hour : hint_range(12.0, 24.0) = 18.0;
uniform float horizon_y : hint_range(0.3, 1.0) = 0.72;     // where the horizon line is (fraction of the rect)
uniform float arc_height : hint_range(0.1, 1.0) = 0.8;     // how high the sun and moon climb (1 = the top)
uniform float arc_width : hint_range(0.1, 0.6) = 0.42;     // how far to the sides they rise and set
uniform bool rise_on_left = true;                          // false: they rise on the right
// clock of the moving parts (clouds, twinkle, aurora, shooting stars). DayNightSky
// sets it every frame; -1 uses the engine's TIME, which starts over every hour by
// default (a small jump of the clouds then)
uniform float sky_time = -1.0;
// how long dawn and dusk last: 0.5 short, 1 normal, 2 long golden hours
uniform float twilight_length : hint_range(0.3, 3.0) = 1.0;

group_uniforms Sky_Colors;
uniform vec4 night_top : source_color = vec4(0.03, 0.05, 0.13, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.17, 0.20, 0.36, 1.0);
uniform vec4 dawn_top : source_color = vec4(0.25, 0.30, 0.55, 1.0);
uniform vec4 dawn_horizon : source_color = vec4(1.0, 0.72, 0.55, 1.0);
uniform vec4 day_top : source_color = vec4(0.30, 0.53, 0.86, 1.0);
uniform vec4 day_horizon : source_color = vec4(0.84, 0.91, 0.94, 1.0);
uniform vec4 dusk_top : source_color = vec4(0.22, 0.20, 0.44, 1.0);
uniform vec4 dusk_horizon : source_color = vec4(0.98, 0.58, 0.40, 1.0);
// warm glow on the horizon on the sun's side at dawn and dusk
uniform float horizon_glow : hint_range(0.0, 2.0) = 1.0;

group_uniforms Sun;
uniform vec4 sun_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform vec4 sun_low_color : source_color = vec4(1.0, 0.63, 0.35, 1.0);   // near the horizon
uniform float sun_size : hint_range(0.0, 0.2) = 0.05;      // radius, as a fraction of the rect height
uniform float sun_glow : hint_range(0.0, 3.0) = 1.0;       // halo around the sun
uniform float sun_glow_size : hint_range(0.2, 3.0) = 1.0;

group_uniforms Moon;
uniform vec4 moon_color : source_color = vec4(0.92, 0.94, 1.0, 1.0);
uniform float moon_size : hint_range(0.0, 0.2) = 0.035;
uniform float moon_glow : hint_range(0.0, 3.0) = 1.0;
// 0 new moon, 0.25 first quarter, 0.5 full moon, 0.75 last quarter (used when
// lunar_cycle_days is 0)
uniform float lunar_phase : hint_range(0.0, 1.0) = 0.35;
// days for a whole cycle of phases, driven by `day` (0 = use lunar_phase)
uniform float lunar_cycle_days : hint_range(0.0, 60.0) = 0.0;
uniform float moon_earthshine : hint_range(0.0, 0.5) = 0.12;   // faint light on the dark side
uniform float moon_craters : hint_range(0.0, 1.0) = 0.5;
// hours the moon runs behind the sun's opposite point (0: it rises at sunset)
uniform float moon_offset : hint_range(-12.0, 12.0) = 0.0;   // hours the moon runs late on its place opposite the sun (negative: early); 12 puts it beside the sun, in the day sky
uniform float moon_by_day : hint_range(0.0, 1.0) = 0.3;        // how visible the moon stays in daylight

group_uniforms Stars;
uniform vec4 star_color : source_color = vec4(0.9, 0.93, 1.0, 1.0);
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_size : hint_range(0.3, 3.0) = 1.0;
uniform float twinkle : hint_range(0.0, 1.0) = 0.5;
uniform float star_rotation : hint_range(0.0, 1.0) = 0.15;     // the sky turns slowly through the night
uniform float shooting_stars : hint_range(0.0, 1.0) = 0.3;     // how often (0 = never)
uniform float milky_way : hint_range(0.0, 1.0) = 0.35;
uniform vec4 milky_way_color : source_color = vec4(0.75, 0.72, 1.0, 1.0);

group_uniforms Aurora;
uniform float aurora : hint_range(0.0, 1.0) = 0.0;           // northern lights at night (0 = none)
uniform vec4 aurora_color : source_color = vec4(0.3, 1.0, 0.6, 1.0);      // lower edge
uniform vec4 aurora_top_color : source_color = vec4(0.65, 0.35, 1.0, 1.0); // top of the rays
uniform float aurora_height : hint_range(0.1, 0.8) = 0.35;  // where the curtain hangs (share of the horizon height)
uniform float aurora_speed : hint_range(0.0, 3.0) = 1.0;

group_uniforms Clouds;
uniform float clouds : hint_range(0.0, 1.0) = 0.45;           // how many clouds (0 = clear sky)
uniform float cloud_speed : hint_range(-0.1, 0.1) = 0.015;    // drift, + to the right
uniform float cloud_scale : hint_range(0.3, 3.0) = 1.0;
uniform vec2 cloud_band = vec2(0.18, 0.62);                   // highest and lowest cloud, as a share of the horizon height
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);        // lit side by day
uniform vec4 cloud_night_color : source_color = vec4(0.30, 0.34, 0.50, 1.0);
uniform float cloud_shade : hint_range(0.0, 1.0) = 0.55;      // how dark their underside is
uniform float cloud_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_round : hint_range(0.0, 1.0) = 1.0;       // 0 flat bottoms, 1 bottoms rounded by small puffs

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// soft-edged disc, anti-aliased over one pixel
float disc(float r, float radius, float px) {
	return smoothstep(radius + px, radius - px, r);
}
// the sun's angle along its path for an hour: 0 at sunrise, PI at sunset, 2 PI at the next sunrise
float sun_angle(float h) {
	float rise = sunrise_hour;
	float set = max(sunset_hour, rise + 0.5);
	float day_len = set - rise;
	float t = mod(h - rise, 24.0);
	return t < day_len ? t / day_len * PI : PI + (t - day_len) / (24.0 - day_len) * PI;
}

void fragment() {
	vec4 node_tint = COLOR;
	float T = sky_time >= 0.0 ? sky_time : TIME;
	vec2 uv = UV;
	float asp = fwidth(UV.y) / max(fwidth(UV.x), 1e-6);   // width / height of the rect
	float px = fwidth(UV.y);                               // one pixel, in UV.y units
	float side = rise_on_left ? 1.0 : -1.0;

	// sun and moon: they rise on one side, climb the arc and set on the other
	float ang = sun_angle(hour);
	float sun_e = sin(ang);                                // elevation, -1 to 1
	float mang = sun_angle(hour - moon_offset) + PI;
	float moon_e = sin(mang);
	float arc = horizon_y * arc_height;
	vec2 sun_p = vec2(0.5 - side * arc_width * cos(ang), horizon_y - sun_e * arc);
	vec2 moon_p = vec2(0.5 - side * arc_width * cos(mang), horizon_y - moon_e * arc);

	// colours: dawn before noon, dusk after (the switch is hidden by the day colours)
	bool morning = mod(ang, 2.0 * PI) > 1.5 * PI || mod(ang, 2.0 * PI) < 0.5 * PI;
	vec3 tw_top = morning ? dawn_top.rgb : dusk_top.rgb;
	vec3 tw_hor = morning ? dawn_horizon.rgb : dusk_horizon.rgb;
	float tl = twilight_length;
	// the top end stays below the sun's highest point, so noon is full day at any length
	float to_day = smoothstep(0.02 * tl, min(0.4 * tl, 0.9), sun_e);
	float to_night = smoothstep(-0.02 * tl, -0.3 * tl, sun_e);
	vec3 top = mix(mix(tw_top, day_top.rgb, to_day), night_top.rgb, to_night);
	vec3 hor = mix(mix(tw_hor, day_horizon.rgb, to_day), night_horizon.rgb, to_night);

	float y = clamp(uv.y / horizon_y, 0.0, 1.0);          // 0 top, 1 horizon
	// flat at the horizon, so the gradient meets the colour below it without a crease
	vec3 c = mix(top, hor, smoothstep(0.0, 1.0, pow(y, 1.25)));
	float twilight = (1.0 - to_day) * (1.0 - to_night);
	// at sunrise and sunset the horizon glows warmer on the sun's side
	vec2 ds = (uv - sun_p) * vec2(asp, 1.0);
	float rs = length(ds);
	c = mix(c, tw_hor * 1.05, clamp(twilight * exp(-rs * 2.5) * smoothstep(0.4, 1.0, y) * 0.6 * horizon_glow, 0.0, 1.0));

	// night: how dark the sky is, for everything that only shows at night
	float night = smoothstep(0.1 * tl, -0.2 * tl, sun_e);
	// stars fade toward the horizon, and the whole moon disc (dark side too) hides them
	vec2 dm = (uv - moon_p) * vec2(asp, 1.0);
	float rm = length(dm);
	float md = disc(rm, moon_size, px);
	float moon_up = smoothstep(-0.12, 0.02, moon_e);
	float sky_fade = (1.0 - smoothstep(0.35, 0.95, y)) * (1.0 - md * moon_up);

	// Milky Way: a soft diagonal band of faint light and dust
	if (milky_way > 0.0 && night > 0.0) {
		vec2 q = vec2(uv.x * asp, uv.y);
		float band = dot(q - vec2(0.5 * asp, 0.3), normalize(vec2(0.45, 1.0)));
		float n = vnoise(q * 6.0 + 3.0) * 0.6 + vnoise(q * 15.0) * 0.4;
		float dust = smoothstep(0.35, 0.75, vnoise(q * 9.0 + 11.0));
		float mw = exp(-band * band * 40.0) * (0.5 + 0.8 * n) * (1.0 - dust * 0.6);
		c += milky_way_color.rgb * mw * milky_way * 0.18 * night * sky_fade;
	}

	// aurora: a curtain of vertical rays hanging from a slowly waving line, bright
	// at its lower edge and fading upward, drawn behind the stars
	if (aurora > 0.0 && night > 0.0) {
		float t = T * 0.12 * aurora_speed;
		float xa = uv.x * asp;
		float line = horizon_y * aurora_height + (vnoise(vec2(xa * 1.6 + t, 3.0)) - 0.5) * 0.16 + sin(xa * 2.3 + t * 2.0) * 0.03;
		float above = line - uv.y;                               // > 0 above the lower edge
		float rays = 0.55 + 0.45 * vnoise(vec2(xa * 38.0 + t * 6.0, t * 3.0));
		rays *= 0.6 + 0.4 * vnoise(vec2(xa * 7.0 - t * 2.0, 1.0));
		float curtain = smoothstep(-0.03, 0.006, above) * exp(-max(above, 0.0) / 0.16);
		float fold = 0.55 + 0.45 * vnoise(vec2(xa * 2.4 - t * 1.5, 7.0));  // brighter and dimmer folds
		vec3 ac = mix(aurora_color.rgb, aurora_top_color.rgb, smoothstep(0.0, 0.2, above));
		c += ac * curtain * rays * fold * aurora * night * 0.55 * (1.0 - smoothstep(0.85, 1.0, y));
	}

	// stars: one per cell at most, round, anti-aliased; the field turns slowly
	if (star_density > 0.0 && night > 0.0) {
		// (the turn starts over at noon, when no star is out)
		float turn = mod(ang - 0.5 * PI, 2.0 * PI) * star_rotation * 0.25;
		// in pixels of the rect (not of the screen): the stars move with the sky
		vec2 fw = fwidth(UV);
		vec2 pole = vec2(0.5, horizon_y * 0.2) / fw;
		vec2 fp = UV / fw - pole;
		fp = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * fp + pole;
		vec2 p = fp / 9.0;
		vec2 cell = floor(p);
		float h1 = hash(cell);
		if (h1 < star_density * 0.35) {
			vec2 at = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.7 + 0.15;
			float rr = length(fract(p) - at) * 9.0;             // screen pixels
			float big = hash(cell + 1.9);
			float size = mix(0.5, 1.3, big * big) * star_size;
			float star = smoothstep(size + 0.7, size - 0.3, rr) * mix(0.35, 1.0, big);
			star *= 1.0 - twinkle * 0.6 * (0.5 + 0.5 * sin(T * mix(1.5, 3.5, h1 * 3.0) + big * 40.0));
			// a few stars have a colour of their own
			vec3 tint = mix(star_color.rgb, mix(vec3(1.0, 0.8, 0.6), vec3(0.7, 0.8, 1.0), hash(cell + 5.5)), step(0.8, hash(cell + 4.4)) * 0.5);
			c += tint * star * night * sky_fade;
		}
	}

	// shooting stars: now and then a streak crosses the upper sky
	if (shooting_stars > 0.0 && night > 0.3) {
		float slot_len = mix(9.0, 2.0, shooting_stars);         // seconds between chances
		float slot = floor(T / slot_len);
		if (hash(vec2(slot, 3.3)) < 0.7) {
			float life = 0.7;
			float t = (T - slot * slot_len - hash(vec2(slot, 8.8)) * (slot_len - life)) / life;
			if (t > 0.0 && t < 1.0) {
				vec2 a = vec2(mix(0.1, 0.9, hash(vec2(slot, 1.1))) * asp, mix(0.05, 0.35, hash(vec2(slot, 2.2))) * horizon_y);
				vec2 dir = normalize(vec2(hash(vec2(slot, 4.4)) < 0.5 ? -1.0 : 1.0, mix(0.35, 0.8, hash(vec2(slot, 5.5)))));
				vec2 head = a + dir * t * 0.35;
				vec2 q = vec2(uv.x * asp, uv.y) - head;
				float along = dot(q, -dir);                     // behind the head
				float across = abs(dot(q, vec2(-dir.y, dir.x)));
				float tail = 0.12 * min(t * 3.0, 1.0);
				float streak = smoothstep(px * 1.2, 0.0, across) * step(0.0, along) * (1.0 - smoothstep(0.0, tail, along));
				streak += disc(length(q), px * 1.2, px) * 0.8;
				c += star_color.rgb * streak * sin(t * PI) * night * sky_fade * 1.4;
			}
		}
	}

	// sun colour: deeper near the horizon
	vec3 sun_c = mix(sun_low_color.rgb, sun_color.rgb, smoothstep(0.0, 0.35, sun_e));
	float sun_up = smoothstep(-0.12, 0.02, sun_e);
	float gs = 1.0 / sun_glow_size;
	c += sun_c * sun_glow * sun_up * (exp(-rs * 9.0 * gs) * 0.3 + exp(-rs * 2.6 * gs) * 0.1);

	// moon halo
	float moon_vis = mix(moon_by_day, 1.0, night);
	float phase = lunar_cycle_days > 0.0 ? fract(day / lunar_cycle_days + lunar_phase) : lunar_phase;
	float fullness = 0.5 - 0.5 * cos(phase * 2.0 * PI);    // 0 new, 1 full
	c += moon_color.rgb * moon_glow * moon_up * night * fullness * (exp(-rm * 12.0) * 0.22 + exp(-rm * 3.5) * 0.06);

	// sun and moon discs, hidden below the horizon line (the clouds pass in front)
	float hide = smoothstep(horizon_y + px, horizon_y - px, uv.y);
	float sd = disc(rs, sun_size, px);
	// always a little brighter than its own halo, or it would read as a ring
	vec3 lw = vec3(0.3, 0.59, 0.11);
	float boost = max(1.05, dot(c, lw) / max(dot(sun_c, lw), 1e-3) + 0.08);
	// a soft halo just outside the disc and a slightly darker limb inside it, so the sun
	// reads as a glowing ball rather than a flat sticker
	c += sun_c * smoothstep(sun_size * 1.7, sun_size, rs) * 0.1 * hide * (1.0 - sd);
	float limb = clamp(rs / max(sun_size, 1e-4), 0.0, 1.0);
	c = mix(c, sun_c * boost * mix(1.0, 0.9, limb * limb), sd * hide);

	// the moon as a lit sphere: the sun lights it from the side that follows its
	// phase, with a soft terminator, a faint earthshine and a few craters
	if (md > 0.0) {
		vec2 nq = dm / max(moon_size, 1e-4);
		float nz = sqrt(max(1.0 - dot(nq, nq), 0.0));
		float th = phase * 2.0 * PI;
		vec3 L = vec3(side * sin(th), 0.0, -cos(th));
		// (from 0: a new moon's rim, where the dot is 0, stays dark; it showed a faint ring)
		float lit = smoothstep(0.0, 0.14, dot(vec3(nq, nz), L));
		// the dark plains ("seas"), then round craters: a soft darker floor with
		// a faint lighter rim. Placed by hand so they spread over the whole disc.
		float crater = smoothstep(0.35, 0.0, length((nq - vec2(-0.28, -0.18)) * vec2(1.0, 1.3))) * 0.8
			+ smoothstep(0.3, 0.0, length(nq - vec2(0.22, 0.12))) * 0.6
			+ smoothstep(0.22, 0.0, length(nq - vec2(-0.05, 0.42))) * 0.5;
		vec3 cr[5] = {vec3(0.42, -0.36, 0.13), vec3(-0.5, 0.25, 0.11), vec3(0.1, -0.52, 0.09),
			vec3(0.55, 0.3, 0.08), vec3(-0.15, 0.05, 0.07)};
		for (int k = 0; k < 5; k++) {
			float dd = length(nq - cr[k].xy) / cr[k].z;
			crater += (1.0 - smoothstep(0.6, 1.0, dd)) * 0.7 - smoothstep(0.85, 1.05, dd) * (1.0 - smoothstep(1.05, 1.35, dd)) * 0.35;
		}
		vec3 surface = moon_color.rgb * (0.88 + 0.12 * nz) * (1.0 - clamp(crater, -0.3, 1.0) * 0.28 * moon_craters);
		float a = md * hide * moon_vis;
		// the lit part covers the sky; the dark part only adds a faint earthshine,
		// so it is never darker than the sky around it
		c = mix(c, surface, lit * a);
		c += surface * moon_earthshine * 0.35 * (1.0 - lit) * a * night;
	}

	// clouds: flat-bottomed (or rounded, cloud_round) puffy clouds drifting in a band of the sky, lit from
	// above and coloured by the hour. Each one is a few round puffs that swell and
	// shrink slowly, so the clouds change shape as they go.
	if (clouds > 0.0 && cloud_opacity > 0.0) {
		float cw = 0.34 * cloud_scale;                      // one cloud slot, in rect heights
		float x = uv.x * asp + T * cloud_speed * 2.0;
		float id = floor(x / cw);
		float dist = 10.0;
		float base = 0.0;
		float size = 1.0;
		for (int j = -1; j <= 1; j++) {
			float cid = id + float(j);
			// a curve, not a straight line, so every part of the 0 to 1 range adds clouds
			if (hash(vec2(cid, 1.7)) > 1.0 - pow(1.0 - clouds, 1.88)) continue;
			float far = hash(vec2(cid, 5.3));                   // 0 high and near .. 1 low and far
			float sz = cw * mix(0.2, 0.11, far);               // puff radius
			vec2 cc = vec2((cid + 0.5 + (hash(vec2(cid, 2.9)) - 0.5) * 0.4) * cw,
				horizon_y * mix(cloud_band.x, cloud_band.y, far));
			float len = mix(0.8, 1.5, hash(vec2(cid, 8.1)));    // longer or rounder clouds
			float bottom = cc.y + sz * 0.45;
			// a rounded body along the bottom joins the puffs
			vec2 bq = abs(vec2(x, uv.y) - vec2(cc.x, bottom - sz * 0.32)) - vec2(sz * 1.05 * len, 0.0);
			float d = length(max(bq, 0.0)) - sz * 0.32;
			for (int k = 0; k < 4; k++) {
				float fk = float(k);
				float ox = (fk - 1.5) * sz * 0.62 * len;
				float r = sz * mix(0.62, 1.05, hash(vec2(cid, fk + 11.0))) * (1.0 - 0.3 * abs(fk - 1.5) / 1.5);
				r *= 1.0 + 0.07 * sin(T * 0.35 + fk * 2.1 + cid * 5.0);
				vec2 q = vec2(x, uv.y) - vec2(cc.x + ox, bottom - r * 0.72);
				d = min(d, length(q) - r);
			}
			// small puffs along the bottom round it off (cloud_round), else a flat cut
			if (cloud_round > 0.0) {
				for (int m = 0; m < 4; m++) {
					float fm = float(m);
					float rr = sz * 0.3 * mix(0.85, 1.15, hash(vec2(cid, fm + 23.0)));
					vec2 q = vec2(x, uv.y) - vec2(cc.x + (fm - 1.5) * sz * 0.58 * len, bottom - rr * 0.35);
					d = min(d, length(q) - rr);
				}
			}
			d = max(d, uv.y - bottom - sz * 0.3 * cloud_round);
			if (d < dist) {
				dist = d;
				base = bottom;
				size = sz;
			}
		}
		float cov = smoothstep(px, -px, dist);
		if (cov > 0.0) {
			// light from above: the lower part of each cloud is in its own shade
			float lit = 1.0 - smoothstep(base - size * 0.9, base - size * 0.05, uv.y) * cloud_shade;
			vec3 day_light = mix(hor, cloud_color.rgb, 0.6);
			vec3 light = mix(day_light, cloud_night_color.rgb, to_night);
			light += sun_c * sun_up * exp(-rs * 3.0) * 0.35;
			vec3 shade = mix(mix(top, hor, 0.5), light, 0.35) * mix(0.95, 0.8, to_night);
			c = mix(c, mix(shade, light, lit), cov * cloud_opacity * smoothstep(0.0, 0.03, horizon_y - uv.y));
		}
	}

	c += (hash(FRAGCOORD.xy + fract(T * 7.0) * 61.0) - 0.5) / 255.0 * 1.5;   // dither: no banding
	COLOR = vec4(c, 1.0);
	COLOR *= node_tint;
}

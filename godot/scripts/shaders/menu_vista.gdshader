shader_type canvas_item;
// The title painting, alive. Everything is placed in the painting's own
// pixels (1920x1080) and moves by a few pixels at most, so it reads as a
// living scene, not a warped picture:
//   the floating isles bob, the World Tree's crown stirs in the wind, the
//   waterfalls run, mist drifts along the cliffs and the valley, the sea
//   ripples, the foreground flowers sway, stars twinkle and the sun breathes.

const vec2 RES = vec2(1920.0, 1080.0);

uniform sampler2D noise_tex : filter_linear, repeat_enable;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Value noise from a small tiling texture (one fetch, not four sine hashes).
float vnoise(vec2 p) {
	return texture(noise_tex, (p + 0.5) / 128.0).r;
}

float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.03 + 5.1) * 0.4;
}

// A soft ellipse: 1 inside, fading to 0 by `soft` times its radius.
float blob(vec2 p, vec2 c, vec2 r, float soft) {
	float d = length((p - c) / r);
	return 1.0 - smoothstep(1.0, soft, d);
}

// A soft rectangle in pixels.
float box(vec2 p, vec2 lo, vec2 hi, float feather) {
	vec2 a = smoothstep(lo - feather, lo + feather, p) * (1.0 - smoothstep(hi - feather, hi + feather, p));
	return a.x * a.y;
}

void fragment() {
	vec2 p = UV * RES;
	float t = TIME;
	vec2 off = vec2(0.0);

	// The floating isles bob, each at its own pace (the sky round them is
	// smooth, so moving it with them does not show).
	off.y += sin(t * 0.55) * 4.0 * blob(p, vec2(1700, 150), vec2(125, 90), 1.7);
	off.y += sin(t * 0.7 + 1.3) * 3.0 * blob(p, vec2(1445, 160), vec2(40, 35), 1.8);
	off.y += sin(t * 0.62 + 2.6) * 3.5 * blob(p, vec2(1535, 245), vec2(50, 40), 1.8);
	off.y += sin(t * 0.8 + 4.0) * 2.0 * blob(p, vec2(1460, 287), vec2(16, 14), 2.0);
	off.y += sin(t * 0.75 + 5.1) * 2.0 * blob(p, vec2(1732, 236), vec2(14, 12), 2.0);

	// The World Tree's crown stirs: the outer leaves more than the trunk.
	float crown = blob(p, vec2(1075, 170), vec2(345, 130), 1.25);
	float gust = 0.6 + 0.4 * sin(t * 0.23);
	off.x += crown * gust * (sin(t * 0.9 + p.y * 0.021) * 1.1 + sin(t * 1.7 + p.x * 0.013) * 0.5)
		* smoothstep(300.0, 120.0, p.y);

	// Clouds churn slowly in the open sky (not over the tree, the mesa with
	// its ruins, or the hills).
	float mesa = box(p, vec2(600, 270), vec2(1470, 720), 40.0);
	float sky = (1.0 - smoothstep(330.0, 400.0, p.y)) * (1.0 - crown) * (1.0 - mesa);
	// (Each effect only runs inside its own part of the painting.)
	if (sky > 0.001) {
		vec2 q = p * vec2(0.004, 0.012);
		off.x += sky * (fbm(q + vec2(t * 0.02, 0.0)) - 0.5) * 3.0;
		off.y += sky * (fbm(q + vec2(3.7, t * 0.015)) - 0.5) * 1.2;
	}

	// The sea: fine ripples, larger nearer the shore below.
	float sea = box(p, vec2(1250, 448), vec2(1940, 628), 10.0) * smoothstep(1180.0, 1320.0, p.x + (p.y - 440.0) * 1.2);
	if (sea > 0.001) {
		float near_k = smoothstep(440.0, 620.0, p.y);
		off.x += sea * sin(p.y * 0.85 + t * 1.6 + vnoise(p * 0.05 + t * 0.3) * 6.0) * mix(0.4, 1.6, near_k);
		off.y += sea * sin(p.x * 0.05 + p.y * 0.4 - t * 1.1) * 0.35 * near_k;
	}

	// Flowers and leaves in the near left corner sway (rooted at the bottom).
	float plants = box(p, vec2(-20, 680), vec2(400, 1100), 40.0) * smoothstep(1080.0, 720.0, p.y);
	off.x += plants * (sin(t * 1.3 + p.y * 0.015) * 2.0 + sin(t * 2.3 + p.x * 0.03) * 0.6);
	// The ivy over the parapet stirs a little.
	float ivy = blob(p, vec2(935, 760), vec2(120, 170), 1.3);
	off.x += ivy * sin(t * 1.1 + p.y * 0.03) * 0.7;

	vec4 col = texture(TEXTURE, (p - off) / RES);
	float lum = dot(col.rgb, vec3(0.3, 0.55, 0.15));

	// Waterfalls run: bright streaks falling through the pale water only.
	if (p.x > 840.0 && p.x < 1360.0 && p.y > 320.0 && p.y < 620.0) {
	float falls = blob(p, vec2(1068, 450), vec2(30, 75), 1.3)
		+ blob(p, vec2(881, 400), vec2(6, 32), 1.6)
		+ blob(p, vec2(1098, 368), vec2(10, 16), 1.6)
		+ blob(p, vec2(1325, 505), vec2(8, 38), 1.5)
		+ blob(p, vec2(970, 550), vec2(14, 40), 1.5)
		+ blob(p, vec2(873, 500), vec2(6, 30), 1.6);
	float water = smoothstep(0.38, 0.6, lum) * clamp(falls, 0.0, 1.0);
	float streak = vnoise(vec2(p.x * 0.45, p.y * 0.06 - t * 2.6));
	streak = smoothstep(0.45, 0.9, streak);
	col.rgb += vec3(0.85, 0.9, 1.0) * water * (streak * 0.28 - 0.06);
	// Spray where the main fall lands.
	float spray = blob(p, vec2(1070, 525), vec2(55, 18), 1.6);
	col.rgb += vec3(0.75, 0.78, 0.9) * spray * fbm(p * 0.05 + vec2(0.0, t * 0.6)) * 0.12;
	}

	// Mist drifts: along the foot of the cliffs and down the valley.
	float band1 = box(p, vec2(480, 460), vec2(1380, 590), 40.0);
	float band2 = box(p, vec2(60, 560), vec2(880, 820), 60.0);
	if (band1 + band2 > 0.001) {
		float m1 = smoothstep(0.45, 0.85, fbm(p * vec2(0.006, 0.02) + vec2(t * 0.035, 0.0)));
		float m2 = smoothstep(0.45, 0.85, fbm(p * vec2(0.005, 0.016) + vec2(-t * 0.025, 4.0)));
		vec3 mist = vec3(0.6, 0.6, 0.76);
		col.rgb = mix(col.rgb, mist, m1 * band1 * 0.16 + m2 * band2 * 0.12);
	}

	// Stars twinkle in the dark upper sky: points brighter than the sky
	// round them (not lit ruins or cloud edges).
	float dark_sky = box(p, vec2(-20, -20), vec2(760, 300), 30.0) * (1.0 - crown) * (1.0 - mesa);
	if (dark_sky > 0.01) {
		float ring = 0.0;
		for (int k = 0; k < 4; k++) {
			float a = float(k) * 1.5708;
			ring += dot(texture(TEXTURE, (p + vec2(cos(a), sin(a)) * 4.0) / RES).rgb, vec3(0.3, 0.55, 0.15));
		}
		float point_ = smoothstep(0.08, 0.2, lum - ring * 0.25);
		vec2 cell = floor(p / 6.0);
		col.rgb *= 1.0 + point_ * dark_sky * 0.8 * sin(t * (1.6 + hash(cell) * 2.4) + hash(cell + 7.0) * 6.28);
	}

	// The sun breathes, and its warmth on the clouds with it.
	float sun = blob(p, vec2(1757, 428), vec2(70, 50), 3.0);
	col.rgb += vec3(1.0, 0.62, 0.32) * sun * (0.06 + 0.04 * sin(t * 0.8));

	COLOR = col;
}

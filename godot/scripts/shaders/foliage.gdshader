shader_type canvas_item;
// Trees and bushes: layered wind motion and volume, in one shared material
// per species (never one per tree; the phase comes from each tree's own
// position).
//
// Motion, in three layers so nothing moves as one flat card:
//   trunk    bends from the root, more toward the top (quadratic)
//   clusters regions of the canopy, picked out by low-frequency noise,
//            sway on their own phases and lag behind the trunk, so a gust
//            runs through the crown and settles after it
//   leaves   a fine shimmer of displacement and brightness
//
// Volume: the art is a flat fill. A normal is worked out from the sprite's
// own silhouette (alpha gradient) plus how deep inside the shape a pixel
// is, then lit from the sun's direction, with a cool rim on the far edge
// and occlusion under the crown. Flat cutouts start to read as round.
//
//   quality 0  plain sprite, gentle sway only
//   quality 1  layered motion and leaf detail
//   quality 2+ plus volume lighting

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform int quality = 2;

// Species.
uniform float bend = 14.0;        // trunk sway at the top, in texture px
uniform float flutter = 6.0;      // canopy cluster sway, px
uniform float shimmer = 1.5;      // leaf jitter, px
uniform float speed = 1.0;        // how quickly this species moves
uniform float canopy_start = 0.35; // height fraction where foliage begins
uniform float cluster_scale = 2.2; // canopy clusters per sprite
uniform float leaf_detail = 0.14; // strength of drawn-in leaf clumps
uniform float pad = 24.0;         // room around the art for the motion, px

// Environment, set each frame for every species at once.
uniform float wind = 1.0;               // 0 still .. 2 storm
uniform vec2 sun_dir = vec2(-0.6, -0.8); // toward the light, screen space
uniform float sun_strength = 1.0;       // 0 at night, 1 at noon
uniform vec3 rim_color = vec3(0.72, 0.86, 1.0);

uniform float saturation = 0.78;
uniform vec3 tint = vec3(0.90, 0.95, 0.90);

varying float phase;

void vertex() {
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	phase = origin.x * 0.0071 + origin.y * 0.0013;
	// Grow the quad so swaying leaves are not clipped at the sprite's edge.
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	VERTEX += (UV * 2.0 - 1.0) * pad;
	UV = VERTEX / size;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float t = TIME * speed;
	float w = wind;

	// Trunk: two slow waves and a rarer gust, bending from the root.
	float gust = pow(max(sin(t * 0.31 + phase * 0.7), 0.0), 6.0);
	float sway = sin(t * 0.9 + phase) * 0.65 + sin(t * 2.1 + phase * 1.7) * 0.2 + gust * 0.9;
	vec2 offset = vec2(sway * bend * w * h * h, 0.0);

	if (quality >= 1) {
		float canopy = smoothstep(canopy_start - 0.1, canopy_start + 0.15, h);
		// Which cluster of the crown this pixel belongs to.
		float id = texture(noise_tex, UV * cluster_scale * 0.25 + vec2(phase * 0.13, 0.0)).r;
		float lag = id * 6.283;
		// Clusters follow the trunk a beat late, then bob on their own.
		float follow = sin(t * 0.9 + phase - 0.7 - id) * 0.5;
		vec2 cluster = vec2(sin(t * 1.7 + lag) + follow, cos(t * 1.3 + lag * 1.3) * 0.45);
		offset += cluster * flutter * w * canopy;
		// Leaves.
		float fine = texture(noise_tex, UV * 0.9 + vec2(t * 0.05, -t * 0.03)).g;
		offset += vec2(sin(t * 6.0 + fine * 12.0), cos(t * 5.3 + fine * 9.0)) * shimmer * w * canopy;
	}

	vec2 uv = UV - offset * px;
	vec4 c = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		c.a = 0.0;
	}

	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(grey), c.rgb, saturation) * tint;

	if (quality >= 1) {
		// Drawn-in leaf clumps: the flat vector fill gains texture that
		// moves slightly with the wind.
		float canopy = smoothstep(canopy_start - 0.05, canopy_start + 0.2, h);
		float clumps = texture(noise_tex, uv * 0.75 + vec2(phase, 0.0)).g;
		float small = texture(noise_tex, uv * 1.9 - vec2(t * 0.01, 0.0)).r;
		float leaves = smoothstep(0.35, 0.7, clumps * 0.6 + small * 0.4);
		col *= mix(1.0 - leaf_detail, 1.0 + leaf_detail * 0.8, leaves * canopy + (1.0 - canopy) * 0.5);
	}

	if (quality >= 2 && c.a > 0.01) {
		// Silhouette normal: alpha around this pixel at two radii.
		vec2 r1 = px * 9.0;
		vec2 r2 = px * 40.0;
		float al = texture(TEXTURE, uv - vec2(r1.x, 0.0)).a;
		float ar = texture(TEXTURE, uv + vec2(r1.x, 0.0)).a;
		float au = texture(TEXTURE, uv - vec2(0.0, r1.y)).a;
		float ad = texture(TEXTURE, uv + vec2(0.0, r1.y)).a;
		float thick = (texture(TEXTURE, uv + vec2(r2.x, r2.y)).a + texture(TEXTURE, uv + vec2(-r2.x, r2.y)).a
			+ texture(TEXTURE, uv + vec2(r2.x, -r2.y)).a + texture(TEXTURE, uv + vec2(-r2.x, -r2.y)).a) * 0.25;
		thick = (thick + (al + ar + au + ad) * 0.25) * 0.5;
		vec3 n = normalize(vec3(al - ar, au - ad, 0.35 + thick * 0.9));
		vec3 l = normalize(vec3(sun_dir, 0.75));
		float lit = clamp(dot(n, l), 0.0, 1.0);
		float shade = mix(0.52, 1.32, lit);
		// Deep inside the crown, light is lost among the leaves.
		shade *= mix(1.0, 0.84, smoothstep(0.75, 1.0, thick) * step(canopy_start, h));
		// Occlusion: the underside of the crown and the inner trunk.
		float under = smoothstep(canopy_start + 0.25, canopy_start - 0.05, h) * (1.0 - smoothstep(0.0, 0.08, h));
		float occlude = mix(1.0, 0.78, under) * mix(0.9, 1.0, smoothstep(0.0, 0.25, h));
		col *= mix(1.0, shade * occlude, 0.55 + 0.45 * sun_strength);
		// Rim: sky light catching the edge that faces away from the sun.
		float edge = 1.0 - smoothstep(0.35, 0.85, thick);
		float away = clamp(dot(n.xy, -sun_dir), 0.0, 1.0);
		col += rim_color * edge * away * 0.22 * sun_strength;
	}

	COLOR = vec4(col, c.a) * COLOR;
}

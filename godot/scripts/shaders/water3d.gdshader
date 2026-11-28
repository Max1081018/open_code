shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;
// Lakes, rivers and the sea, anime style: clear turquoise over the shallows
// with the bed showing through (the scene behind, refracted), deepening to
// blue with thickness (from the depth buffer); white foam lapping at the
// shore; rolling normals from three wave trains; a soft fresnel of sky and
// bright sun glints and sparkles.
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 shallow : source_color = vec4(0.34, 0.86, 0.82, 1.0);
uniform vec4 deep : source_color = vec4(0.06, 0.3, 0.55, 1.0);
uniform vec4 sky : source_color = vec4(0.74, 0.87, 0.98, 1.0);
uniform float clarity = 2.6;   // metres until the bed fades out
uniform float night = 0.0;
// The Ashlands' lakes and rivers are lava: a mask over the island.
uniform sampler2D lava_map : filter_linear;
uniform float island_span = 5120.0;
// Sky reflected at grazing angles: horizon to zenith, with the sun's glow.
uniform vec4 sky_top : source_color = vec4(0.36, 0.58, 0.92, 1.0);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform vec4 sun_tint : source_color = vec4(1.0, 0.92, 0.75, 1.0);
// Light focused by the ripples onto the shallow bed (0 = off).
uniform float caustics = 1.0;

float wave(vec2 p, vec2 dir, float freq, float speed) {
	return sin(dot(p, dir) * freq + TIME * speed);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Caustics: two drifting cell patterns whose bright ridges cross, as light
// bent by ripples gathers on a sandy bed. Cheap (no texture).
float caustic(vec2 p) {
	vec2 q = p * 0.9;
	float c = 0.0;
	for (int i = 0; i < 2; i++) {
		vec2 d = vec2(TIME * (0.11 + 0.05 * float(i)), TIME * (0.07 - 0.04 * float(i)));
		vec2 g = q * (1.0 + 0.7 * float(i)) + d;
		vec2 f = fract(g) - 0.5;
		vec2 j = vec2(hash(floor(g)), hash(floor(g) + 7.3)) - 0.5;
		float r = length(f - j * 0.6);
		c += pow(1.0 - smoothstep(0.0, 0.5, r), 6.0);
	}
	return c;
}

float waves(vec2 p) {
	return wave(p, normalize(vec2(1.0, 0.3)), 0.35, 1.2) + wave(p, normalize(vec2(-0.4, 1.0)), 0.6, 1.7) * 0.6
		+ wave(p, normalize(vec2(0.7, -0.8)), 1.4, 2.3) * 0.25;
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;
	float e = 0.5;
	float h0 = waves(p);
	vec3 n_world = normalize(vec3(-(waves(p + vec2(e, 0.0)) - h0) * 0.09, 1.0, -(waves(p + vec2(0.0, e)) - h0) * 0.09));
	// Fine chop that drifts: breaks up the regular wave trains up close.
	vec2 cq = p * 2.3 + vec2(TIME * 0.35, -TIME * 0.27);
	float c0 = vnoise(cq);
	n_world = normalize(n_world + vec3(vnoise(cq + vec2(0.4, 0.0)) - c0, 0.0, vnoise(cq + vec2(0.0, 0.4)) - c0) * 0.55);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// How much water lies behind this point, along the view ray.
	float raw = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(0.0, VERTEX.z - behind.z);
	float murk = 1.0 - exp(-thickness / clarity);
	// The bed, refracted by the ripples.
	vec2 bend = n_world.xz * 0.025 * clamp(thickness, 0.0, 1.0);
	vec3 bed = texture(screen_tex, SCREEN_UV + bend).rgb;
	// Light focused onto the bed, fading with depth and at night.
	float bed_light = caustic(p + n_world.xz * 0.6) * caustics * (1.0 - smoothstep(0.1, 2.2, thickness)) * smoothstep(0.02, 0.25, thickness) * (1.0 - night);
	bed += vec3(0.85, 0.95, 1.0) * bed_light * 0.35;
	// Water absorbs red first, then green: the bed tints as it deepens.
	vec3 absorb = exp(-thickness * vec3(0.55, 0.16, 0.09));
	vec3 body = mix(shallow.rgb, deep.rgb, smoothstep(0.0, 1.0, murk * 1.15));
	vec3 col = mix(bed * absorb * mix(vec3(1.0), shallow.rgb * 1.35, 0.55), body, smoothstep(0.05, 0.75, murk));
	// Foam lapping at the shore.
	float lap = 0.5 + 0.5 * sin(TIME * 1.4 + (p.x + p.y) * 0.35);
	float edge = 1.0 - smoothstep(0.0, 0.35 + lap * 0.35, thickness);
	float lace = smoothstep(0.35, 0.65, vnoise(p * 1.6 + vec2(TIME * 0.25, -TIME * 0.18)));
	float foam = clamp(edge * (0.55 + lace * 0.6), 0.0, 1.0);
	col = mix(col, vec3(0.97, 0.99, 1.0), foam * 0.9);
	// Sky at grazing angles, kept soft so the water stays water.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 5.0);
	// The sky as seen in the water: the reflected ray's height picks the
	// gradient, and the sun leaves a soft glow on the surface.
	vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v_world, n_world);
	vec3 refl = mix(sky.rgb, sky_top.rgb, smoothstep(0.0, 0.6, r.y));
	float sun_glow = pow(max(dot(r, normalize(sun_dir)), 0.0), 64.0);
	refl += sun_tint.rgb * sun_glow * 1.5 * (1.0 - night);
	col = mix(col, refl * mix(1.0, 0.3, night), clamp(fresnel * 0.65 + 0.04, 0.0, 1.0));
	// Sparkles riding the ripples.
	float sparkle = step(0.985, vnoise(p * 6.0 + vec2(TIME * 0.6, TIME * 0.4))) * (1.0 - murk * 0.3);
	col *= mix(1.0, 0.35, night);
	float lv = smoothstep(0.35, 0.6, texture(lava_map, p / island_span + 0.5).r);
	vec3 emit = vec3(sparkle) * 0.6 * (1.0 - night);
	if (lv > 0.0) {
		vec2 q = p * 0.12 + vec2(TIME * 0.04, TIME * 0.025);
		float n = vnoise(q) * 0.6 + vnoise(q * 2.7) * 0.3 + vnoise(q * 7.0) * 0.1;
		float crust = smoothstep(0.4, 0.52, n);
		vec3 hot = mix(vec3(0.95, 0.22, 0.03), vec3(1.0, 0.55, 0.12), vnoise(q * 4.0 + TIME * 0.2));
		// Glowing seams where the crust plates part.
		float seam = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.47));
		col = mix(col, vec3(0.06, 0.045, 0.04), lv);
		emit = mix(emit, hot * max(1.0 - crust, seam * 0.8) * 1.5 + vec3(0.3, 0.05, 0.02) * crust * 0.2, lv);
		NORMAL = mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, lv);
	}
	ALBEDO = col;
	EMISSION = emit;
	ROUGHNESS = mix(0.05, 0.9, lv);
	SPECULAR = mix(0.65, 0.1, lv);
	ALPHA = 1.0;
}

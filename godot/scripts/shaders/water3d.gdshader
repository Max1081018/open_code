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
	vec3 body = mix(shallow.rgb, deep.rgb, smoothstep(0.0, 1.0, murk * 1.15));
	vec3 col = mix(bed * shallow.rgb * 1.35, body, smoothstep(0.05, 0.75, murk));
	// Foam lapping at the shore.
	float lap = 0.5 + 0.5 * sin(TIME * 1.4 + (p.x + p.y) * 0.35);
	float edge = 1.0 - smoothstep(0.0, 0.35 + lap * 0.35, thickness);
	float lace = smoothstep(0.35, 0.65, vnoise(p * 1.6 + vec2(TIME * 0.25, -TIME * 0.18)));
	float foam = clamp(edge * (0.55 + lace * 0.6), 0.0, 1.0);
	col = mix(col, vec3(0.97, 0.99, 1.0), foam * 0.9);
	// Sky at grazing angles, kept soft so the water stays water.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 5.0);
	col = mix(col, sky.rgb, fresnel * 0.5);
	// Sparkles riding the ripples.
	float sparkle = step(0.985, vnoise(p * 6.0 + vec2(TIME * 0.6, TIME * 0.4))) * (1.0 - murk * 0.3);
	col *= mix(1.0, 0.35, night);
	ALBEDO = col;
	EMISSION = vec3(sparkle) * 0.6 * (1.0 - night);
	ROUGHNESS = 0.05;
	SPECULAR = 0.65;
	ALPHA = 1.0;
}

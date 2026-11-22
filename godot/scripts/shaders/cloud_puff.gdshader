shader_type spatial;
// A soft cloud puff as a camera-facing billboard: a few overlapping noisy
// lobes, sunlit and cream on top, cool blue-lilac underneath, edges
// feathered, fading as the camera nears (so you can fly through it) and
// tinted toward dusk and night with the sky.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 top_color : source_color = vec4(1.0, 0.99, 0.96, 1.0);
uniform vec4 base_color : source_color = vec4(0.68, 0.74, 0.9, 1.0);
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float opacity = 0.9;

varying float seed;
varying float cam_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	// Billboard keeping the node's scale (x wide, y tall).
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= scale;
	vec3 world = MODEL_MATRIX[3].xyz;
	cam_dist = distance(world, CAMERA_POSITION_WORLD);
}

void fragment() {
	vec2 uv = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);   // y up
	// Cumulus: a big central dome with smaller shoulders, a flattish base,
	// and edges broken by noise.
	float shape = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float x = mix(-0.62, 0.62, fi / 5.0) + (hash(vec2(seed, fi)) - 0.5) * 0.15;
		float tall = 1.0 - abs(x) * 0.95;
		vec2 c = vec2(x, -0.3 + tall * 0.45 * (0.6 + 0.4 * hash(vec2(fi, seed))));
		float r = (0.34 + 0.42 * max(tall, 0.0)) * (0.85 + hash(vec2(seed * 3.0, fi)) * 0.3);
		shape = max(shape, 1.0 - length((uv - c) / vec2(r * 0.85, r)));
	}
	shape *= smoothstep(-0.62, -0.4, uv.y);
	float n = fbm(uv * 2.6 + vec2(seed * 10.0, TIME * 0.015));
	float d = shape * 1.25 + (n - 0.5) * 0.6;
	float a = smoothstep(-0.04, 0.3, d);
	// Never reach the quad's edges (no square corners).
	a *= smoothstep(1.0, 0.72, abs(uv.x)) * smoothstep(1.0, 0.7, abs(uv.y));
	// Lit from above: cream top, blue-lilac underside.
	float h = clamp(uv.y * 0.6 + 0.5 + (n - 0.5) * 0.4, 0.0, 1.0);
	vec3 col = mix(base_color.rgb, top_color.rgb, smoothstep(0.2, 0.85, h));
	col = mix(col, col * vec3(1.0, 0.72, 0.62), dusk * 0.7);
	col = mix(col, vec3(0.16, 0.18, 0.3), night * 0.85);
	float near = smoothstep(6.0, 40.0, cam_dist);
	float far = 1.0 - smoothstep(1600.0, 2600.0, cam_dist);
	ALBEDO = col;
	ALPHA = a * opacity * near * far;
}

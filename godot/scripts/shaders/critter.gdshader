shader_type spatial;
// Butterflies and fireflies as particle billboards. Butterflies: two wings
// drawn from the quad's UV, flapping (the quad narrows and widens) and
// wandering on their own little loops. Fireflies: a soft glowing dot that
// blinks. One shader, `kind` 0 or 1. Particle colour tints the wings.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform int kind = 0;           // 0 butterfly, 1 firefly, 2 falling leaf
uniform float fade = 1.0;       // day/night visibility

varying float seed;
varying vec4 tint;
varying float cam_d;

void vertex() {
	seed = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	tint = COLOR;
	// Billboard, keeping the particle's scale.
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 v = VERTEX * s;
	if (kind == 0) {
		float flap = abs(sin(TIME * (14.0 + seed * 8.0) + seed * 6.28));
		v.x *= 0.25 + 0.75 * flap;
		// Wander: a small loop of its own.
		float t = TIME * (0.6 + seed * 0.5) + seed * 30.0;
		bb[3].xyz += vec3(sin(t) * 0.8, sin(t * 1.7) * 0.35, cos(t * 0.8) * 0.8);
	} else if (kind == 1) {
		float t = TIME * (0.4 + seed * 0.4) + seed * 20.0;
		bb[3].xyz += vec3(sin(t) * 0.5, sin(t * 1.3) * 0.3, cos(t * 0.9) * 0.5);
	} else {
		// Leaves tumble: the quad flips (narrows) and spins as it drifts.
		float t = TIME * (1.2 + seed * 1.5) + seed * 50.0;
		float c = cos(t);
		float sn = sin(t * 0.7);
		v.x *= abs(c) * 0.85 + 0.15;
		v.xy = mat2(vec2(cos(sn), sin(sn)), vec2(-sin(sn), cos(sn))) * v.xy;
		bb[3].xyz += vec3(sin(t * 0.5) * 0.6, 0.0, cos(t * 0.4) * 0.6);
	}
	cam_d = distance(bb[3].xyz, CAMERA_POSITION_WORLD);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * bb * vec4(v, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// Nothing flutters right in front of the lens.
	float lens = smoothstep(1.5, 3.5, cam_d);
	if (lens < 0.02) {
		discard;
	}
	if (kind == 0) {
		// Two rounded wings either side of a thin body.
		vec2 w = vec2(abs(uv.x), uv.y);
		float upper = length((w - vec2(0.45, -0.25)) / vec2(0.5, 0.55));
		float lower = length((w - vec2(0.35, 0.4)) / vec2(0.35, 0.42));
		float wing = min(upper, lower);
		float body = step(abs(uv.x), 0.06) * step(abs(uv.y), 0.6);
		if (wing > 1.0 && body < 0.5) {
			discard;
		}
		vec3 c = mix(tint.rgb, tint.rgb * 0.45, smoothstep(0.55, 1.0, wing));
		c = mix(c, vec3(1.0), smoothstep(0.3, 0.0, upper) * 0.35);
		ALBEDO = body > 0.5 ? vec3(0.15, 0.12, 0.1) : c;
		ALPHA = fade * lens;
	} else if (kind == 2) {
		// A leaf: pointed ellipse with a midrib.
		float leaf = length(vec2(uv.x * 1.7 / (1.0 - abs(uv.y) * 0.35), uv.y));
		if (leaf > 1.0) {
			discard;
		}
		vec3 c = tint.rgb * (0.8 + 0.2 * (1.0 - leaf));
		c *= 1.0 - step(abs(uv.x), 0.05) * 0.25;
		ALBEDO = c;
		ALPHA = fade * lens;
	} else {
		float d = length(uv);
		float blink = 0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * (1.5 + seed * 2.0) + seed * 40.0));
		float glow = (1.0 - smoothstep(0.0, 1.0, d)) * blink * fade;
		if (glow < 0.02) {
			discard;
		}
		ALBEDO = vec3(1.0, 0.92, 0.45) * glow * 4.0;
		ALPHA = glow * lens;
	}
}

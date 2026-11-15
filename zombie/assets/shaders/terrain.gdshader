shader_type spatial;
// Ground.
//
// The mesh carries one colour per vertex, worked out when the chunk is built
// (grass, jungle, dust, rock on the steep parts). That alone reads as flat
// poster paint from head height, so everything that makes it look like ground
// is added here, procedurally, with no textures to load or stream:
//
//   - two scales of blotching, so no two square metres are the same colour;
//   - a fine grain that only shows close up, which stops the ground going
//     smooth and plastic under your feet;
//   - dirt gathering in the hollows and bleaching on the crests, read from
//     the surface normal rather than from a painted mask;
//   - a cooler, hazier tint with distance, so the far hills sit back.
//
// All of it is a handful of hashes per pixel - the same cost whatever the
// terrain is doing.

render_mode specular_disabled;

uniform float blotch_scale = 0.045;      // big patches, metres
uniform float blotch_strength : hint_range(0.0, 1.0) = 0.30;
uniform float grain_scale = 2.6;         // fine grain, metres
uniform float grain_strength : hint_range(0.0, 1.0) = 0.18;
uniform float grain_fade = 26.0;         // metres: grain gone past this
uniform vec4 dirt_color : source_color = vec4(0.33, 0.27, 0.19, 1.0);
uniform float dirt_strength : hint_range(0.0, 1.0) = 0.42;
uniform vec4 rock_color : source_color = vec4(0.42, 0.41, 0.40, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.62;
uniform vec4 haze_color : source_color = vec4(0.58, 0.66, 0.72, 1.0);
uniform float haze_start = 130.0;
uniform float haze_end = 420.0;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.22;

// Cel lighting, to match the vegetation: the ground is banded too, or it
// reads as a different world to everything standing on it.
uniform int bands : hint_range(2, 6) = 4;
uniform float band_softness : hint_range(0.0, 0.3, 0.005) = 0.06;
// How much light the darkest band keeps. At zero the unlit side of
// everything goes to pure ambient and reads as a hole; this lifts it.
uniform float shade_floor : hint_range(0.0, 0.8) = 0.34;
uniform float shade_warmth : hint_range(0.0, 1.0) = 0.28;
uniform vec4 shade_tint : source_color = vec4(0.40, 0.48, 0.66, 1.0);

varying vec3 v_world;
varying vec3 v_normal;
varying float v_dist;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise2(p) * 0.6 + noise2(p * 2.1) * 0.3 + noise2(p * 4.3) * 0.1;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;

	// Rock wherever the ground gets steep. Taken from the real normal, so it
	// follows every fold of the terrain without anything being painted in.
	float slope = 1.0 - clamp(v_normal.y, 0.0, 1.0);
	float rock = smoothstep(1.0 - slope_start, 1.0 - slope_start + 0.22, slope);
	base = mix(base, rock_color.rgb, rock * 0.85);

	// Big patches of lighter and darker ground, and a second, slower drift
	// between two greens so a field is never one colour from edge to edge.
	float blotch = fbm(v_world.xz * blotch_scale);
	base *= 1.0 + (blotch - 0.5) * 2.0 * blotch_strength;
	float drift = fbm(v_world.xz * blotch_scale * 0.31 + vec2(37.0, 11.0));
	base = mix(base, base * vec3(0.84, 1.06, 0.74), smoothstep(0.42, 0.75, drift) * 0.55);

	// Dirt in the hollows: where the surface turns over, soil gathers and
	// grass thins out. Crests bleach instead.
	float curve = fbm(v_world.xz * 0.11);
	base = mix(base, dirt_color.rgb, smoothstep(0.55, 0.95, curve) * dirt_strength * (1.0 - rock));
	base *= 1.0 + smoothstep(0.45, 0.1, curve) * 0.10;

	// Fine grain, close up only: past a few dozen metres it would just alias.
	float near = 1.0 - smoothstep(grain_fade * 0.4, grain_fade, v_dist);
	if (near > 0.001) {
		float g = noise2(v_world.xz * grain_scale) + noise2(v_world.xz * grain_scale * 3.7) * 0.5;
		base *= 1.0 + (g / 1.5 - 0.5) * grain_strength * near;
	}

	// Distance haze, so the far ground recedes instead of shouting.
	float far = smoothstep(haze_start, haze_end, v_dist) * haze_strength;
	base = mix(base, haze_color.rgb, far);

	// A touch more colour than the flat vertex paint: ground that is all one
	// desaturated grey-green is what makes low-poly worlds look unfinished.
	float grey = dot(base, vec3(0.299, 0.587, 0.114));
	base = clamp(mix(vec3(grey), base, 1.25), vec3(0.0), vec3(1.0));
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

float band(float amount) {
	float slices = float(bands);
	float half_soft = max(band_softness, 0.0001) * 0.5;
	float level = 0.0;
	for (int i = 1; i < bands; i++) {
		float edge = float(i) / slices;
		level += smoothstep(edge - half_soft, edge + half_soft, amount);
	}
	return level / max(slices - 1.0, 1.0);
}

void light() {
	vec3 light_rgb = LIGHT_COLOR / PI;
	float strength = max(max(light_rgb.r, light_rgb.g), light_rgb.b);
	vec3 col = light_rgb / max(strength, 0.0001);
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// More bands than the foliage and a softer edge: hard steps across open
	// ground would march about as you walk.
	float level = band(n_dot_l * ATTENUATION * max(strength, 1.0)) * min(strength, 1.0);
	level = mix(shade_floor, 1.0, level);
	vec3 shaded = mix(col, shade_tint.rgb, shade_warmth * (1.0 - level));
	DIFFUSE_LIGHT += shaded * level;
}

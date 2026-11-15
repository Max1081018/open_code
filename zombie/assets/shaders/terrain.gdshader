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

render_mode diffuse_lambert, specular_disabled;

uniform float blotch_scale = 0.045;      // big patches, metres
uniform float blotch_strength : hint_range(0.0, 1.0) = 0.22;
uniform float grain_scale = 2.6;         // fine grain, metres
uniform float grain_strength : hint_range(0.0, 1.0) = 0.13;
uniform float grain_fade = 26.0;         // metres: grain gone past this
uniform vec4 dirt_color : source_color = vec4(0.33, 0.27, 0.19, 1.0);
uniform float dirt_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rock_color : source_color = vec4(0.42, 0.41, 0.40, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.62;
uniform vec4 haze_color : source_color = vec4(0.58, 0.66, 0.72, 1.0);
uniform float haze_start = 130.0;
uniform float haze_end = 420.0;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.22;

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

	// Big patches of lighter and darker ground.
	float blotch = fbm(v_world.xz * blotch_scale);
	base *= 1.0 + (blotch - 0.5) * 2.0 * blotch_strength;

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
}

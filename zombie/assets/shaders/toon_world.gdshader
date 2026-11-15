shader_type spatial;
// Cel-shaded vegetation and scenery, with wind.
//
// The lighting is the "Toon Shader" from godotlearning.com (CC0, supplied in
// the toon-shader pack): light is cut into flat bands in light(), with a rim
// along the lit silhouette and a hard-edged highlight. What is added here is
// the rest of what the world needs - colour from the mesh's own vertex
// colours or from an atlas, and the wind that moves everything green.
//
// One shader covers grass, bushes and trees: the only difference between them
// is how hard the wind pushes and how tall the plant is.

render_mode cull_disabled, specular_schlick_ggx;

group_uniforms Colour;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;
// How far to pull the colour toward grey. The environment's own saturation
// control does nothing in the compatibility renderer, which is what this game
// ships with, so the drabness has to be baked in here.
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;

group_uniforms Toon;
uniform int bands : hint_range(2, 6) = 3;
uniform float band_softness : hint_range(0.0, 0.2, 0.005) = 0.03;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim_width : hint_range(0.0, 1.0) = 0.28;
// How much light the darkest band keeps. At zero the unlit side of
// everything goes to pure ambient and reads as a hole; this lifts it.
uniform float shade_floor : hint_range(0.0, 0.8) = 0.34;
uniform float shade_warmth : hint_range(0.0, 1.0) = 0.25;   // colour in the dark bands
uniform vec4 shade_tint : source_color = vec4(0.42, 0.50, 0.68, 1.0);

group_uniforms Wind;
uniform float sway_strength : hint_range(0.0, 1.0) = 0.12;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.1;
uniform float gust_strength : hint_range(0.0, 1.0) = 0.35;
uniform float height_scale = 1.0;
uniform vec2 wind_dir = vec2(0.82, 0.57);

group_uniforms Depth;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 haze_color : source_color = vec4(0.60, 0.68, 0.74, 1.0);
uniform float haze_start = 120.0;
uniform float haze_end = 380.0;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.3;

varying float v_up;        // 0 at the base of the plant, 1 at the top
varying float v_dist;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.6);
	float bend = h * h;
	if (sway_strength > 0.0001) {
		float t = TIME * sway_speed;
		float phase = dot(w.xz, wind_dir) * 0.35;
		// A slow swell rolling across the landscape, so whole stands lean
		// together instead of each plant dancing on its own.
		float gust = sin(TIME * 0.21 + dot(w.xz, wind_dir) * 0.045) * 0.5 + 0.5;
		float amount = sway_strength * (0.35 + gust * gust_strength * 2.0);
		vec2 offset = wind_dir * (sin(t + phase) * 0.6 + sin(t * 1.7 + phase * 2.1) * 0.4);
		w.xz += offset * amount * bend;
		w.y -= abs(offset.x) * amount * bend * 0.25;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	}
	v_up = bend;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 c = tint;
	if (use_texture) {
		c *= texture(albedo_texture, UV);
	} else {
		c *= COLOR;
	}
	// Undergrowth loses light at its base; without this a bush is a flat
	// cut-out however good the lighting above it is.
	// Back faces take the front face's lighting. The models are open shells -
	// a canopy seen from below, a blade of grass from behind - and left alone
	// their back faces point away from every light and render as black fill.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	float ao = mix(1.0 - ao_strength, 1.0, clamp(v_up + 0.25, 0.0, 1.0));
	vec3 col = c.rgb;
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey * 0.96), desaturate) * (1.0 - darken);
	ALBEDO = col * ao;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	if (alpha_scissor > 0.0) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
}

// Light cut into `bands` flat levels, soft only at the very edge.
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
	float level = band(n_dot_l * ATTENUATION * max(strength, 1.0)) * min(strength, 1.0);
	level = mix(shade_floor, 1.0, level);

	// Rim along the lit edge, which is what gives cel shading its depth.
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width + max(band_softness, 0.0001), 1.0 - n_dot_v);

	// Shadowed bands take a cool cast rather than going flat grey - the thing
	// that most separates a stylised scene from an unlit one.
	vec3 shaded = mix(col, shade_tint.rgb, shade_warmth * (1.0 - level));
	DIFFUSE_LIGHT += shaded * level * (1.0 + rim * rim_strength);
}

shader_type spatial;
// The ground: grass, soil, rock, snow and sand textures (ambientCG, CC0)
// blended by per-vertex weights (COLOR = grass, rock, snow, sand; soil takes
// the rest), sampled at two scales to hide tiling, steep rock projected from
// the side so cliffs do not stretch, a biome tint and ash from UV2.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.22;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 two_scale(sampler2D t, vec2 p) {
	return mix(texture(t, p * scale).rgb, texture(t, p * scale * 0.23).rgb, 0.35);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 grass = two_scale(grass_tex, p) * vec3(0.68, 0.78, 0.55);
	vec3 soil = two_scale(soil_tex, p);
	vec3 snow = two_scale(snow_tex, p);
	vec3 sand = two_scale(sand_tex, p);
	// Rock: triplanar-ish, from the side on steep faces.
	vec3 n = abs(world_normal);
	vec3 rock_top = two_scale(rock_tex, p);
	vec3 rock_x = two_scale(rock_tex, world_pos.zy);
	vec3 rock_z = two_scale(rock_tex, world_pos.xy);
	vec3 rock = (rock_top * n.y + rock_x * n.x + rock_z * n.z) / (n.x + n.y + n.z);
	vec4 w = COLOR;
	float soil_w = max(0.0, 1.0 - w.r - w.g - w.b - w.a);
	vec3 c = (grass * w.r + rock * w.g + snow * w.b + sand * w.a + soil * soil_w)
		/ max(w.r + w.g + w.b + w.a + soil_w, 0.001);
	// Biome tint (UV2.x: overall brightness of the tint) and ash (UV2.y).
	c *= mix(1.0, UV2.x, 0.8);
	c = mix(c, c * vec3(0.32, 0.3, 0.3), UV2.y * 0.8);
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.55, w.b);
	SPECULAR = 0.25;
}

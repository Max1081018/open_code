shader_type spatial;
// Glazed roof tiles in the town's colours: the tile texture's light and
// shade carried onto a cobalt, teal or violet glaze, with a soft sheen.
uniform sampler2D tiles : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tiles_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.18, 0.34, 0.66, 1.0);

void fragment() {
	vec3 t = texture(tiles, UV).rgb;
	float l = dot(t, vec3(0.3, 0.59, 0.11));
	ALBEDO = tint.rgb * (0.45 + l * 1.25);
	NORMAL_MAP = texture(tiles_n, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = 0.45;
	SPECULAR = 0.45;
}

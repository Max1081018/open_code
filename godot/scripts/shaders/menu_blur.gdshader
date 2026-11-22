shader_type canvas_item;
// Frosted glass behind the game menu: the paused world blurred and tinted
// toward night blue, with a soft vignette.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 tint : source_color = vec4(0.03, 0.04, 0.13, 0.66);
uniform float radius = 3.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float k = exp(-float(x * x + y * y) / 8.0);
			c += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb * k;
			w += k;
		}
	}
	c /= w;
	vec2 d = SCREEN_UV - 0.5;
	float vig = 1.0 - dot(d, d) * 0.9;
	COLOR = vec4(mix(c, tint.rgb, tint.a) * vig, 1.0);
}

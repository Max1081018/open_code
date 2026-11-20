shader_type canvas_item;
// Water and lava. The liquid atlas is one row: water, water surface,
// lava, lava surface. Each tile works out which it is from its UV.
//
//   quality 0  static tiles, colour only
//   quality 1  moving surface waves, caustic highlights, flowing lava
//   quality 2+ plus refraction of whatever lies behind the water

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform int quality = 2;
uniform vec4 water_deep : source_color = vec4(0.10, 0.28, 0.44, 1.0);
uniform vec4 water_glint : source_color = vec4(0.80, 0.95, 1.0, 1.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	int column = clamp(int(floor(UV.x * 4.0)), 0, 3);
	bool lava = column >= 2;
	bool surface = column == 1 || column == 3;
	float t = TIME;

	vec2 uv = UV;
	if (quality >= 1 && surface) {
		// The surface line rolls: shift the art vertically by a wave that
		// travels along the world, so neighbouring tiles join up.
		float wave = sin(world.x * 0.030 + t * (lava ? 0.9 : 2.1)) * 0.040
			+ sin(world.x * 0.083 - t * (lava ? 1.3 : 3.0)) * 0.016;
		uv.y = clamp(uv.y + wave, 0.0, 1.0);
	}
	if (quality >= 1) {
		vec2 wobble = vec2(sin(world.y * 0.05 + t * 1.8), cos(world.x * 0.04 + t * 1.4));
		uv += wobble * TEXTURE_PIXEL_SIZE * (lava ? 1.0 : 2.0);
	}
	vec4 base = texture(TEXTURE, uv);
	vec3 c = base.rgb;

	if (lava) {
		if (quality >= 1) {
			float flow = texture(noise_tex, world / 420.0 + vec2(t * 0.015, -t * 0.03)).r;
			float crust = texture(noise_tex, world / 160.0 - vec2(t * 0.02, 0.0)).g;
			c = mix(c * vec3(0.75, 0.45, 0.3), vec3(1.35, 0.72, 0.22), smoothstep(0.35, 0.75, flow));
			c *= mix(0.65, 1.15, smoothstep(0.3, 0.6, crust));
		}
		COLOR = vec4(c, base.a);
	} else {
		// Deeper water darkens away from the surface.
		c = mix(c, water_deep.rgb, surface ? 0.15 : 0.45);
		if (quality >= 1) {
			float caustic = texture(noise_tex, world / 260.0 + vec2(t * 0.04, t * 0.025)).r;
			float caustic2 = texture(noise_tex, world / 190.0 - vec2(t * 0.03, -t * 0.02)).g;
			float light = smoothstep(0.58, 0.68, (caustic + caustic2) * 0.5);
			c += water_glint.rgb * light * 0.22;
		}
		if (quality >= 2) {
			vec2 bend = vec2(sin(world.y * 0.07 + t * 2.0), cos(world.x * 0.05 + t * 1.7)) * 0.004;
			vec3 behind = texture(screen_texture, SCREEN_UV + bend).rgb;
			c = mix(c, behind * vec3(0.55, 0.85, 1.0), 0.32);
		}
		if (surface) {
			// A bright line where light skims the surface.
			float line = smoothstep(0.06, 0.0, abs(uv.y - 0.30)) * base.a;
			float glint = 0.5 + 0.5 * sin(world.x * 0.11 + t * 2.6);
			c += water_glint.rgb * line * glint * 0.35;
		}
		COLOR = vec4(c, base.a * 0.86);
	}
}

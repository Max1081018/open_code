shader_type canvas_item;
// Final image for the 3D world, drawn over the rendered frame:
//   bloom (bright parts of blurred mip levels) for the soft anime glow;
//   contrast-adaptive sharpening so textures and outlines stay crisp;
//   a gentle filmic curve and split toning (warm light, cool shade);
//   saturation lift, light vignette, and dithering against banding.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float bloom = 0.22;
uniform float bloom_threshold = 0.92;
uniform float sharpen = 0.5;
uniform float saturation = 1.08;
uniform float contrast = 1.0;
uniform float curve = 0.3;   // a filmic S-curve: deeper shade, kept highlights
uniform float vignette = 0.28;
uniform vec3 warm : source_color = vec3(1.03, 0.99, 0.94);
uniform vec3 cool : source_color = vec3(0.92, 0.96, 1.06);

vec3 tap(vec2 uv, float lod) {
	return textureLod(screen_texture, uv, lod).rgb;
}

vec3 bright(vec2 uv, float lod) {
	vec3 c = tap(uv, lod);
	float m = max(c.r, max(c.g, c.b));
	return c * smoothstep(bloom_threshold, 1.0, m);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = tap(uv, 0.0);
	if (sharpen > 0.0) {
		vec3 n = tap(uv + vec2(0.0, -px.y), 0.0);
		vec3 s = tap(uv + vec2(0.0, px.y), 0.0);
		vec3 e = tap(uv + vec2(px.x, 0.0), 0.0);
		vec3 w = tap(uv + vec2(-px.x, 0.0), 0.0);
		vec3 lo = min(c, min(min(n, s), min(e, w)));
		vec3 hi = max(c, max(max(n, s), max(e, w)));
		vec3 amp = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, vec3(1e-3)), 0.0, 1.0));
		vec3 wgt = -amp * mix(0.125, 0.2, sharpen);
		c = clamp((c + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt), 0.0, 1.0);
	}
	if (bloom > 0.0) {
		vec3 g = bright(uv, 2.5) * 0.3 + bright(uv, 4.0) * 0.35 + bright(uv, 5.5) * 0.35;
		c += g * bloom;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c *= mix(cool, warm, smoothstep(0.2, 0.75, l));
	l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	vec3 cc = clamp(c, 0.0, 1.0);
	vec3 s_curve = cc * cc * (3.0 - 2.0 * cc);
	c = mix(c, s_curve, curve);
	vec2 d = uv - 0.5;
	c *= 1.0 - dot(d, d) * vignette * 1.4;
	c += (fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}

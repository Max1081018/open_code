shader_type canvas_item;
// Final image: the whole look in one pass, cheap enough for a phone.
//   1. contrast-adaptive sharpening (after AMD's CAS): crisp edges and
//      texture detail without halos, like a good upscaler's reconstruction;
//   2. bloom from the screen's own mip chain: lights and sunlit edges glow
//      softly into the air around them;
//   3. ACES filmic tone curve: rich contrast, highlights that roll off
//      instead of clipping;
//   4. split toning: warm gold in the light, cool blue in the shade;
//   5. a biome tint, vignette, lens fringe, and fine grain that also
//      dithers away banding in skies and fog.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float vignette = 0.42;
uniform float fringe = 0.0018;
uniform float saturation = 0.92;
uniform float contrast = 1.1;
// Lift the floor so dark caves stay readable on a phone outdoors.
uniform float shadow_lift = 0.035;
uniform float underwater = 0.0;  // 0..1 while the player's head is submerged
uniform float heat = 0.0;        // 0..1 near lava
uniform float rain = 0.0;        // 0..1 during rain
// Quality knobs (0 turns each off): set from the graphics settings.
uniform float sharpen = 0.55;
uniform float bloom = 0.3;
uniform float bloom_threshold = 0.8;
uniform float grain = 0.018;
uniform float exposure = 1.0;
uniform vec3 warm_light = vec3(1.04, 0.98, 0.88);
uniform vec3 cool_shade = vec3(0.88, 0.96, 1.08);

vec3 aces(vec3 x) {
	// Narkowicz's fit of the ACES filmic curve.
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

vec3 fetch(vec2 uv) {
	return textureLod(screen_texture, uv, 0.0).rgb;
}

vec3 bright(vec2 uv, float lod) {
	vec3 c = textureLod(screen_texture, uv, lod).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(bloom_threshold, 1.0, l);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	// Underwater the whole view sways; near lava the air shimmers upward.
	uv.x += sin(uv.y * 24.0 + TIME * 2.2) * 0.0035 * underwater;
	uv.y += cos(uv.x * 18.0 + TIME * 1.7) * 0.0025 * underwater;
	uv.x += sin(uv.y * 90.0 - TIME * 9.0) * 0.0012 * heat * smoothstep(0.2, 1.0, uv.y);
	vec2 from_centre = uv - vec2(0.5);
	float edge = dot(from_centre, from_centre);
	vec2 shift = from_centre * fringe * edge * 4.0;
	vec3 color;
	color.r = fetch(uv + shift).r;
	color.g = fetch(uv).g;
	color.b = fetch(uv - shift).b;

	// 1. Sharpen: weight the cross neighbours by how much contrast is
	//    already there, so flat areas sharpen and hard edges do not ring.
	if (sharpen > 0.0) {
		vec3 n = fetch(uv + vec2(0.0, -px.y));
		vec3 s = fetch(uv + vec2(0.0, px.y));
		vec3 e = fetch(uv + vec2(px.x, 0.0));
		vec3 w = fetch(uv + vec2(-px.x, 0.0));
		vec3 lo = min(color, min(min(n, s), min(e, w)));
		vec3 hi = max(color, max(max(n, s), max(e, w)));
		vec3 amp = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, vec3(1e-3)), 0.0, 1.0));
		vec3 weight = -amp * mix(0.125, 0.2, sharpen);
		color = clamp((color + (n + s + e + w) * weight) / (1.0 + 4.0 * weight), 0.0, 1.0);
	}

	// 2. Bloom: bright parts of ever-blurrier copies of the screen.
	if (bloom > 0.0) {
		vec3 glow = bright(uv, 2.0) * 0.30 + bright(uv, 3.5) * 0.35 + bright(uv, 5.0) * 0.35;
		color += glow * bloom;
	}

	// 3. Exposure and the filmic curve, then back toward the art's
	//    own brightness so nothing goes muddy.
	vec3 filmic = aces(color * exposure * 1.25);
	color = mix(color, filmic, 0.45);

	// 4. Split toning: shade cool, light warm (the art direction).
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color *= mix(cool_shade, warm_light, smoothstep(0.15, 0.75, luma));

	luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, saturation);
	color = (color - 0.5) * contrast + 0.5;
	color = max(color, vec3(0.0));
	color = color * (1.0 - shadow_lift) + vec3(0.6, 0.85, 1.0) * shadow_lift;
	color *= tint.rgb;
	color = mix(color, color * vec3(0.45, 0.78, 0.92) + vec3(0.0, 0.03, 0.06), underwater * 0.8);
	color = mix(color, color * vec3(1.08, 0.94, 0.86), heat * 0.25);
	// Rain flattens contrast and cools the light.
	color = mix(color, mix(vec3(dot(color, vec3(0.33))), color, 0.7) * vec3(0.86, 0.9, 0.98), rain * 0.45);
	color *= 1.0 - edge * vignette * 1.6;

	// 5. Grain: a little film, and no banding in gradients.
	float noise = hash(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5;
	color += noise * grain;
	COLOR = vec4(color, 1.0);
}

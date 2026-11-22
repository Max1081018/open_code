shader_type spatial;
// Floating islands: grassy crowns and cliff bodies of layered rock, chosen by
// slope; rock projected from the sides so cliffs do not stretch; warm toon
// light with cool shade, and the undersides fading into a soft sky haze.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 shade : source_color = vec3(0.5, 0.52, 0.74);
uniform vec3 haze : source_color = vec3(0.72, 0.82, 0.97);
uniform float top_y = 0.0;

varying vec3 wpos;
varying vec3 wnor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 n = abs(wnor);
	vec3 grass = texture(grass_tex, wpos.xz * 0.2).rgb * vec3(0.7, 0.86, 0.52);
	vec3 rx = texture(rock_tex, wpos.zy * 0.12).rgb;
	vec3 rz = texture(rock_tex, wpos.xy * 0.12).rgb;
	vec3 ry = texture(rock_tex, wpos.xz * 0.12).rgb;
	vec3 rock = (rx * n.x + rz * n.z + ry * n.y) / (n.x + n.y + n.z);
	float lum = dot(rock, vec3(0.33));
	// Broad crags and clefts at a large scale, so big cliffs are not smooth.
	float big = (dot(texture(rock_tex, wpos.zy * 0.022).rgb, vec3(0.33)) * n.x
		+ dot(texture(rock_tex, wpos.xy * 0.022).rgb, vec3(0.33)) * n.z
		+ dot(texture(rock_tex, wpos.xz * 0.022).rgb, vec3(0.33)) * n.y) / (n.x + n.y + n.z);
	lum = mix(lum, big, 0.5);
	// Strata: bands of warm sandstone, cool slate and deep umber, wavering.
	float below = top_y - wpos.y;
	float band = below * 0.075 + vnoise(wpos.xz * 0.04 + vec2(wpos.y * 0.015)) * 1.3
		+ vnoise(wpos.xz * 0.2) * 0.12;
	float layer = fract(band);
	vec3 sand = vec3(0.74, 0.62, 0.5);
	vec3 slate = vec3(0.5, 0.52, 0.6);
	vec3 umber = vec3(0.46, 0.37, 0.33);
	vec3 strata = mix(sand, slate, smoothstep(0.32, 0.46, layer));
	strata = mix(strata, umber, smoothstep(0.72, 0.86, layer));
	// Dark seams where the bands meet.
	strata *= 0.8 + 0.2 * smoothstep(0.0, 0.05, min(abs(layer - 0.39), abs(layer - 0.79)));
	rock = strata * (0.3 + lum * 1.2);
	// Deeper is darker (and cooler) toward the tip.
	float deep = smoothstep(2.0, 60.0, below);
	rock *= mix(vec3(1.0), vec3(0.62, 0.64, 0.78), deep);
	// The crown, and grass draping over the rim in a ragged fringe.
	float top = smoothstep(0.3, 0.55, wnor.y);
	float fringe = 0.8 + 2.2 * vnoise(wpos.xz * 0.45 + wpos.y * 0.1);
	float drape = smoothstep(fringe + 0.4, fringe - 0.3, below);
	float moss = smoothstep(-0.3, 0.4, wnor.y) * smoothstep(9.0, 0.0, below) * 0.5;
	vec3 c = mix(rock, grass * 0.85, clamp(moss + drape, 0.0, 1.0));
	c = mix(c, grass, top);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	// Undersides dissolve into the sky's haze.
	float under = smoothstep(0.0, -0.8, wnor.y);
	EMISSION = haze * under * 0.04;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = smoothstep(0.42, 0.52, ndl) * mix(0.6, 1.0, ATTENUATION);
	DIFFUSE_LIGHT += mix(shade, vec3(1.0), lit) * LIGHT_COLOR / PI * 0.95;
}

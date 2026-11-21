shader_type spatial;
// Floating islands: grassy crowns and cliff bodies of layered rock, chosen by
// slope; rock projected from the sides so cliffs do not stretch; warm toon
// light with cool shade, and the undersides fading into a soft sky haze.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 shade : source_color = vec3(0.66, 0.68, 0.9);
uniform vec3 haze : source_color = vec3(0.72, 0.82, 0.97);
uniform float top_y = 0.0;

varying vec3 wpos;
varying vec3 wnor;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnor);
	vec3 grass = texture(grass_tex, wpos.xz * 0.2).rgb * vec3(0.7, 0.84, 0.55);
	vec3 rx = texture(rock_tex, wpos.zy * 0.12).rgb;
	vec3 rz = texture(rock_tex, wpos.xy * 0.12).rgb;
	vec3 ry = texture(rock_tex, wpos.xz * 0.12).rgb;
	vec3 rock = (rx * n.x + rz * n.z + ry * n.y) / (n.x + n.y + n.z);
	rock = pow(rock, vec3(1.25)) * vec3(0.92, 0.84, 0.82);
	float top = smoothstep(0.3, 0.55, wnor.y);
	// Moss and hanging grass on the upper cliffs, warm earthy rock below.
	float moss = smoothstep(-0.2, 0.3, wnor.y) * smoothstep(-6.0, 0.0, wpos.y - top_y);
	rock = mix(rock * vec3(1.05, 0.95, 0.85), grass * 0.8, moss * 0.7);
	vec3 c = mix(rock, grass, top);
	// Rock strata: faint horizontal bands.
	c *= 0.92 + 0.08 * sin(wpos.y * 1.7);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	// Undersides dissolve into the sky's haze.
	float under = smoothstep(0.0, -0.8, wnor.y);
	EMISSION = haze * under * 0.12;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = smoothstep(0.42, 0.52, ndl) * mix(0.6, 1.0, ATTENUATION);
	DIFFUSE_LIGHT += mix(shade, vec3(1.0), lit) * LIGHT_COLOR / PI * 0.95;
}

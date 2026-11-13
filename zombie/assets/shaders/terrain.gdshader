shader_type spatial;
// Island ground: the height-banded vertex colours (wet sand, sand, grass)
// with cheap procedural detail on top - soft blotches and fine speckle - so
// it reads as a surface rather than flat paint.
render_mode diffuse_lambert, specular_disabled;

varying vec3 wpos;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	float big = vnoise(wpos.xz * 0.35);
	float fine = vnoise(wpos.xz * 4.0);
	float grassy = smoothstep(0.05, 0.25, COLOR.g - COLOR.r);   // green band
	vec3 c = base * (0.90 + 0.16 * big);
	c *= 1.0 - 0.07 * fine;
	// tiny pale speckle on sand, darker tufts on grass
	c = mix(c, c * mix(1.08, 0.86, grassy), step(0.86, fine));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}

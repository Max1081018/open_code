shader_type spatial;
// Town banners: a long pennant rippling in the wind (waves travel from the
// pole to the tail, growing toward the free end), deep blue with a gold
// border and the four-pointed star of the Starfall, swallow-tailed.
render_mode cull_disabled, specular_disabled;

uniform vec4 field : source_color = vec4(0.12, 0.2, 0.48, 1.0);
uniform vec4 trim : source_color = vec4(0.96, 0.8, 0.4, 1.0);

void vertex() {
	// UV.x: 0 at the pole, 1 at the tail; UV.y: 0 top, 1 bottom.
	float free = UV.x;
	float t = TIME * 4.2 + MODEL_MATRIX[3].x * 0.3;
	VERTEX.z += sin(UV.x * 7.0 - t) * 0.16 * free + sin(UV.x * 13.0 - t * 1.7) * 0.04 * free;
	VERTEX.y += sin(UV.x * 5.0 - t * 0.8) * 0.05 * free;
}

float star(vec2 p) {
	p = abs(p);
	return p.x * 0.35 + p.y + min(p.x, p.y) * 1.2;
}

void fragment() {
	vec2 uv = UV;
	// Swallow tail: a V cut into the free end.
	float notch = 0.85 + abs(uv.y - 0.5) * 0.3;
	if (uv.x > notch) {
		discard;
	}
	vec3 c = field.rgb;
	float border = step(uv.y, 0.07) + step(0.93, uv.y) + step(uv.x, 0.05);
	c = mix(c, trim.rgb, clamp(border, 0.0, 1.0));
	// The star, centred a third of the way along.
	vec2 sp = (uv - vec2(0.32, 0.5)) * vec2(2.6, 1.0);
	float s = star(sp);
	c = mix(c, trim.rgb, 1.0 - smoothstep(0.22, 0.25, s));
	// Fold shading from the ripple.
	c *= 0.86 + 0.14 * sin(uv.x * 7.0 - TIME * 4.2);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	BACKLIGHT = c * 0.4;
}

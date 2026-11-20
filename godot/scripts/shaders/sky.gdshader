shader_type canvas_item;
// Sky gradient that meets the horizon wherever the ground currently is,
// with a warm haze band just above it.
uniform vec4 top : source_color = vec4(0.30, 0.56, 0.78, 1.0);
uniform vec4 bottom : source_color = vec4(0.74, 0.90, 0.84, 1.0);
uniform float horizon = 0.66;

void fragment() {
	float t = clamp(UV.y / max(horizon, 0.05), 0.0, 1.0);
	vec3 color = mix(top.rgb, bottom.rgb, pow(t, 1.35));
	float haze = exp(-abs(UV.y - horizon) * 9.0) * 0.18;
	COLOR = vec4(color + bottom.rgb * haze, 1.0);
}

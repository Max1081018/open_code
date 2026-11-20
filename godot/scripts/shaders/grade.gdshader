shader_type canvas_item;
// Final grade: a gentle filmic contrast, a biome tint, a vignette, and a
// hint of colour fringing toward the corners like a real lens.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float vignette = 0.42;
uniform float fringe = 0.0018;
uniform float saturation = 0.86;
uniform float contrast = 1.05;
// Lift the floor so dark caves stay readable on a phone outdoors.
uniform float shadow_lift = 0.035;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_centre = uv - vec2(0.5);
	float edge = dot(from_centre, from_centre);
	vec2 shift = from_centre * fringe * edge * 4.0;
	vec3 color;
	color.r = texture(screen_texture, uv + shift).r;
	color.g = texture(screen_texture, uv).g;
	color.b = texture(screen_texture, uv - shift).b;
	// Lift the shadows toward cool teal, keep highlights warm.
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, color * vec3(0.92, 1.0, 1.04), 1.0 - luma);
	color = color * color * (3.0 - 2.0 * color) * 0.35 + color * 0.65;
	luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, saturation);
	color = (color - 0.5) * contrast + 0.5;
	color = max(color, vec3(0.0));
	color = color * (1.0 - shadow_lift) + vec3(0.6, 0.85, 1.0) * shadow_lift;
	color *= tint.rgb;
	color *= 1.0 - edge * vignette * 1.6;
	COLOR = vec4(color, 1.0);
}

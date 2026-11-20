shader_type canvas_item;
render_mode blend_add;
// A soft shaft of sunlight: feathered at both sides, fading with length,
// slowly breathing so it never looks pasted on.
uniform float phase = 0.0;

void fragment() {
	float across = smoothstep(0.0, 0.5, UV.x) * smoothstep(1.0, 0.5, UV.x);
	float along = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.35, 1.0, UV.y));
	float breathe = 0.55 + 0.45 * sin(TIME * 0.35 + phase);
	float strength = across * across * along * breathe * 0.16;
	COLOR = vec4(vec3(1.0, 0.96, 0.82) * strength, strength) * COLOR;
}

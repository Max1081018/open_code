shader_type canvas_item;
// Ground cover in the wind. One shared material for every tuft: the gust
// phase comes from world position, so neighbours ripple in sequence and
// thousands of sprites never need a material each.
uniform float strength = 7.0;
uniform float saturation = 0.72;
uniform vec3 tint = vec3(0.86, 0.92, 0.88);
varying float lift;
void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	lift = 1.0 - UV.y;
	float phase = world.x * 0.012;
	float gust = sin(TIME * 1.6 + phase) * 0.7 + sin(TIME * 3.3 + phase * 2.3) * 0.3;
	VERTEX.x += gust * strength * lift * lift;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), c.rgb, saturation) * tint, c.a) * COLOR;
}

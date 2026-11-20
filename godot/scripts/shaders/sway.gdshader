shader_type canvas_item;
// Ground cover in the wind. One shared material for every tuft: the gust
// phase comes from world position, so neighbours ripple in sequence and
// thousands of sprites never need a material each. Tufts also part around
// the player as they walk through.
uniform float strength = 7.0;
uniform float wind = 1.0;
uniform vec2 player_position = vec2(-99999.0);
uniform float saturation = 0.72;
uniform vec3 tint = vec3(0.86, 0.92, 0.88);
void vertex() {
	vec2 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float lift = 1.0 - UV.y;
	float phase = world.x * 0.012;
	// Each tuft has its own rhythm too, so a row never moves in lockstep.
	float own = fract(sin(root.x * 12.9898) * 43758.5453) * 6.283;
	float gust = sin(TIME * 1.6 + phase + own * 0.3) * 0.6 + sin(TIME * 3.3 + phase * 2.3 + own) * 0.3
		+ pow(max(sin(TIME * 0.4 + phase * 0.5), 0.0), 5.0) * 0.8;
	VERTEX.x += gust * strength * wind * lift * lift;
	// Pushed aside by the player's legs.
	vec2 away = root - player_position;
	if (abs(away.y) < 160.0) {
		float near = 1.0 - smoothstep(30.0, 150.0, abs(away.x));
		VERTEX.x += sign(away.x) * near * 26.0 * lift;
		VERTEX.y += near * 6.0 * lift;
	}
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), c.rgb, saturation) * tint, c.a) * COLOR;
}

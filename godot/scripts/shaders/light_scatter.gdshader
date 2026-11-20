shader_type canvas_item;
render_mode blend_add;
// The light map's second pass. The first multiplies the world by the light,
// which can only darken toward each surface's own colour: a torch could
// never make a dark cave wall glow. This pass adds the *coloured* part of
// the light on top (torches, lava, crystals, glowing mushrooms), so they
// wash nearby rock with their colour. White sunlight has no colour excess
// and adds nothing, so daylight scenes are untouched.
uniform float strength = 0.55;
void fragment() {
	vec3 light = texture(TEXTURE, UV).rgb;
	float hi = max(light.r, max(light.g, light.b));
	float lo = min(light.r, min(light.g, light.b));
	float colour = hi - lo;
	vec3 tint = light - vec3(lo);
	COLOR = vec4(tint * smoothstep(0.08, 0.5, colour) * hi * strength, 1.0);
}

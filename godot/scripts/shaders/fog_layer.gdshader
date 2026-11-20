shader_type canvas_item;
// Atmospheric perspective: blend toward the fog colour by distance.
// Modulate can only darken, which left every tree line equally green;
// distance needs colours to drift *toward* the air, lighter and cooler.
uniform vec4 fog : source_color = vec4(0.55, 0.80, 0.74, 1.0);
uniform float amount = 0.5;
uniform float light = 1.0;
// Kenney's backdrops are toy-bright; a forest seen through air is not.
uniform float saturation = 0.6;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float grey = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 lit = mix(vec3(grey), tex.rgb, saturation) * light;
	// Kenney paints distant hills pale *inside* a near layer's art: in
	// these backdrops paleness means distance, so pale pixels take the
	// fog of something further away than the layer they sit in.
	float chroma = max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b));
	float pale = smoothstep(0.68, 0.9, grey) * (1.0 - smoothstep(0.08, 0.3, chroma));
	float haze = mix(amount, 0.85, pale);
	COLOR = vec4(mix(lit, fog.rgb, haze), tex.a * COLOR.a);
}

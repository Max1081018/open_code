shader_type canvas_item;
// Atmospheric perspective: blend toward the fog colour by distance.
// Modulate can only darken, which left every tree line equally green;
// distance needs colours to drift *toward* the air, lighter and cooler.
uniform vec4 fog : source_color = vec4(0.55, 0.80, 0.74, 1.0);
uniform float amount = 0.5;
uniform float light = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 lit = tex.rgb * light;
	COLOR = vec4(mix(lit, fog.rgb, amount), tex.a * COLOR.a);
}

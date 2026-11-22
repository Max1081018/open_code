shader_type spatial;
render_mode diffuse_toon, specular_toon, ambient_light_disabled;
// Anime character shading (the look of modern anime action RPGs): light falls
// in two soft-edged tones instead of a smooth gradient, shadows are tinted
// cool and never black, a thin rim of light outlines the silhouette against
// the sky, and a gentle specular band glints on hair and metal.
// Outlines come from a second pass (toon_outline.gdshader).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade_color : source_color = vec4(0.72, 0.7, 0.92, 1.0);
uniform float shade_threshold = 0.42;
uniform float shade_softness = 0.06;
uniform float rim_strength = 0.35;
uniform float rim_width = 0.72;
uniform float spec_strength = 0.18;
uniform float alpha_cut = 0.0;   // > 0: alpha-tested (hair cards, lace)
uniform float emission_boost = 0.0;
uniform float light_scale = 0.62;
// Our own soft fill instead of the scene's sky ambient (which pushed pale
// skin past white): a fixed share of the albedo, slightly cool.
uniform vec4 fill_color : source_color = vec4(0.96, 0.9, 0.92, 1.0);
uniform float fill = 0.22;
// Hair: the glossy "angel ring" band of anime hair, broken into strands
// along the cards, catching the light from above the head.
uniform float hair_ring = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 0.96, 1.0, 1.0);

void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	if (alpha_cut > 0.0 && t.a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb;
	EMISSION = t.rgb * emission_boost + t.rgb * fill_color.rgb * fill;
	ROUGHNESS = 0.8;
	SPECULAR = 0.0;
	// Rim: brighter where the surface turns away from the camera.
	float rim = smoothstep(rim_width, 1.0, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	EMISSION += t.rgb * rim * rim_strength * 0.6;
	if (hair_ring > 0.0) {
		// The band sits where the hair's surface faces up-and-toward the
		// camera; strands break it along the texture's long axis.
		vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		float band = smoothstep(0.16, 0.0, abs(wn.y - 0.55)) * smoothstep(0.1, 0.5, dot(NORMAL, VIEW));
		float strands = 0.55 + 0.45 * sin(UV.x * 420.0 + sin(UV.y * 40.0) * 2.0);
		EMISSION += ring_color.rgb * band * strands * hair_ring;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl * 0.5 + 0.5);
	lit *= mix(0.55, 1.0, ATTENUATION);
	vec3 tone = mix(shade_color.rgb, vec3(1.0), lit);
	// (Godot multiplies by ALBEDO afterwards.) Scaled so full sun lands
	// near the texture's own colour instead of clipping pale skin to white.
	DIFFUSE_LIGHT += tone * LIGHT_COLOR / PI * light_scale;
	// Soft anime specular band.
	vec3 h = normalize(LIGHT + VIEW);
	float s = smoothstep(0.95, 0.985, dot(NORMAL, h)) * lit;
	SPECULAR_LIGHT += LIGHT_COLOR / PI * s * spec_strength;
}

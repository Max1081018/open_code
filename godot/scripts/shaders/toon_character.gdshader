shader_type spatial;
render_mode diffuse_toon, specular_toon;
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

void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	if (alpha_cut > 0.0 && t.a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb;
	EMISSION = t.rgb * emission_boost;
	ROUGHNESS = 0.8;
	SPECULAR = 0.0;
	// Rim: brighter where the surface turns away from the camera.
	float rim = smoothstep(rim_width, 1.0, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	EMISSION += t.rgb * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, ndl * 0.5 + 0.5);
	lit *= mix(0.55, 1.0, ATTENUATION);
	vec3 tone = mix(shade_color.rgb, vec3(1.0), lit);
	DIFFUSE_LIGHT += ALBEDO * tone * LIGHT_COLOR / PI * 1.15;
	// Soft anime specular band.
	vec3 h = normalize(LIGHT + VIEW);
	float s = smoothstep(0.92, 0.97, dot(NORMAL, h)) * lit;
	SPECULAR_LIGHT += LIGHT_COLOR * s * spec_strength;
}

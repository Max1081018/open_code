shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;
// Lakes, rivers and the sea: one plane at the water line following the
// player. Rolling normals from three wave trains, a fresnel blend from deep
// teal straight down to sky-coloured at grazing angles, sun glints, and
// soft foam where the ground comes near the surface (the terrain height is
// passed as a coarse texture around the player).
uniform vec4 deep : source_color = vec4(0.05, 0.2, 0.26, 1.0);
uniform vec4 shallow : source_color = vec4(0.18, 0.45, 0.46, 1.0);
uniform vec4 sky : source_color = vec4(0.62, 0.74, 0.86, 1.0);

float wave(vec2 p, vec2 dir, float freq, float speed) {
	return sin(dot(p, dir) * freq + TIME * speed);
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;
	float e = 0.5;
	float h0 = wave(p, normalize(vec2(1.0, 0.3)), 0.35, 1.2) + wave(p, normalize(vec2(-0.4, 1.0)), 0.6, 1.7) * 0.6
		+ wave(p, normalize(vec2(0.7, -0.8)), 1.4, 2.3) * 0.25;
	float hx = wave(p + vec2(e, 0.0), normalize(vec2(1.0, 0.3)), 0.35, 1.2) + wave(p + vec2(e, 0.0), normalize(vec2(-0.4, 1.0)), 0.6, 1.7) * 0.6
		+ wave(p + vec2(e, 0.0), normalize(vec2(0.7, -0.8)), 1.4, 2.3) * 0.25;
	float hz = wave(p + vec2(0.0, e), normalize(vec2(1.0, 0.3)), 0.35, 1.2) + wave(p + vec2(0.0, e), normalize(vec2(-0.4, 1.0)), 0.6, 1.7) * 0.6
		+ wave(p + vec2(0.0, e), normalize(vec2(0.7, -0.8)), 1.4, 2.3) * 0.25;
	vec3 n_world = normalize(vec3(-(hx - h0) * 0.12, 1.0, -(hz - h0) * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	vec3 body = mix(shallow.rgb, deep.rgb, clamp(facing * 1.2, 0.0, 1.0));
	ALBEDO = mix(body, sky.rgb, fresnel * 0.85);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = mix(0.78, 0.96, fresnel);
}

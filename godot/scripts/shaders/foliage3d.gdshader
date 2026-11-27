shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Leaves and grass: alpha-tested, swaying in the wind more the higher a
// vertex stands, each instance on its own phase so a forest never moves in
// lockstep. Back faces lit like front ones (thin leaves).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float sway = 0.08;
uniform float alpha_cut = 0.45;
uniform float saturation = 1.0;
// Trees thin out (ordered dither) when the camera pushes into them.
uniform float near_fade = 0.0;
global uniform float occlude_depth;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = world.x * 0.21 + world.z * 0.17;
	float h = max(VERTEX.y, 0.0);
	float bend = sway * h * h * 0.08;
	VERTEX.x += sin(TIME * 1.3 + phase) * bend + sin(TIME * 3.1 + phase * 2.0) * bend * 0.25;
	VERTEX.z += cos(TIME * 1.1 + phase) * bend * 0.6;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	if (t.a < alpha_cut) {
		discard;
	}
	if (near_fade > 0.0) {
		float seen = smoothstep(near_fade * 0.4, near_fade, -VERTEX.z);
		// And around the heroine, wherever a bough stands in front of her.
		vec2 c = SCREEN_UV - vec2(0.5, 0.56);
		c.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		float occl = (1.0 - smoothstep(0.14, 0.32, length(c))) * (1.0 - smoothstep(occlude_depth - 1.0, occlude_depth, -VERTEX.z));
		seen = min(seen, 1.0 - occl * 0.8);
		ivec2 px = ivec2(FRAGCOORD.xy) % 4;
		float bayer = float((px.x * 3 + px.y * 2 + (px.x ^ px.y) * 5) % 16) / 16.0;
		if (seen < bayer + 0.03) {
			discard;
		}
	}
	float l = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(l), t.rgb, saturation);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// Light through thin leaves: brighten back faces slightly.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

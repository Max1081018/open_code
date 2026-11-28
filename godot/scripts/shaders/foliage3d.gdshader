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
// Canopy shaping (radius 0 = off): leaf normals bend out from the crown's
// centre so a tree is lit as one soft rounded mass (light on the sun side,
// shade on the far side) instead of a confetti of flat cards; leaves deep
// inside the crown sit in its own shadow; light glows through the thin
// leaves on the side away from the sun.
uniform vec3 canopy_center = vec3(0.0);
uniform float canopy_radius = 0.0;
uniform float translucency = 0.0;
// Far canopies thin smoothly (FoliageLib.with_cards): CUSTOM0 holds each
// leaf card's centre and a random number. With distance a growing share of
// cards shrinks to nothing and the rest grow to keep the crown full, so a
// forest draws far fewer alpha-tested leaves with no pop. Shadows keep all.
uniform float card_thin = 0.0;
uniform float thin_near = 22.0;
uniform float thin_far = 55.0;
varying float v_ao;
varying float v_tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (card_thin > 0.0 && PROJECTION_MATRIX[3][3] < 0.5) {
		vec3 cen = CUSTOM0.xyz;
		float d = distance((MODEL_MATRIX * vec4(cen, 1.0)).xyz, CAMERA_POSITION_WORLD);
		float far_k = smoothstep(thin_near, thin_far, d);
		// Up close every card stays whole; only beyond thin_near do some go.
		float keep = clamp((CUSTOM0.w - 0.5 * far_k) / 0.08 + (1.0 - far_k), 0.0, 1.0);
		VERTEX = cen + (VERTEX - cen) * keep * (1.0 + 0.4 * far_k);
	}
	float phase = world.x * 0.21 + world.z * 0.17;
	float h = max(VERTEX.y, 0.0);
	float bend = sway * h * h * 0.08;
	VERTEX.x += sin(TIME * 1.3 + phase) * bend + sin(TIME * 3.1 + phase * 2.0) * bend * 0.25;
	VERTEX.z += cos(TIME * 1.1 + phase) * bend * 0.6;
	v_ao = 1.0;
	if (canopy_radius > 0.0) {
		vec3 d = VERTEX - canopy_center;
		float r = length(d) / canopy_radius;
		NORMAL = normalize(mix(NORMAL, d / max(length(d), 1e-4), 0.8));
		// Inner leaves and the underside of the crown are shaded.
		v_ao = smoothstep(0.05, 0.95, r) * 0.75 + 0.25;
		v_ao *= mix(0.62, 1.0, smoothstep(-0.7, 0.4, d.y / canopy_radius));
	}
	// Each plant a slightly different green.
	v_tint = fract(sin(dot(world.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	if (t.a < alpha_cut) {
		discard;
	}
	// The sun's shadow pass draws with an orthographic projection: never thin
	// leaves out there, or the shadows come out stippled.
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	if (near_fade > 0.0 && !shadow_pass) {
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
	vec3 c = mix(vec3(l), t.rgb, saturation);
	if (canopy_radius > 0.0) {
		c *= mix(vec3(0.9, 1.02, 0.86), vec3(1.06, 1.0, 0.9), v_tint);
	}
	ALBEDO = c * v_ao;
	BACKLIGHT = c * translucency * v_ao;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// Light through thin leaves: brighten back faces slightly.
	if (!FRONT_FACING && canopy_radius <= 0.0) {
		NORMAL = -NORMAL;
	}
}

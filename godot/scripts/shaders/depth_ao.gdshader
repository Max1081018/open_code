shader_type spatial;
// Screen-space ambient occlusion and contact shading from the depth buffer,
// drawn as a full-screen quad that darkens the frame only where geometry
// folds: a dark, cool tint blended in by the occlusion (alpha), so where
// nothing is occluded it adds nothing at all (and water and particles drawn
// before it are kept). A multiply blend is not used: the Compatibility
// renderer tone-maps its output, which dimmed the whole frame.
// Where geometry folds (tree bases, rocks sitting in grass, walls meeting the
// ground, under eaves) the light that reaches it falls off; a cool tint keeps
// the shade from going grey. Fades with distance so far land keeps its air.
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float strength = 0.9;
uniform float radius = 0.9;      // metres
uniform float far_fade = 90.0;   // metres
uniform vec3 shade_tint : source_color = vec3(0.86, 0.9, 1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Depth is read only inside fragment() (the Compatibility renderer cannot
// compile depth-texture reads made from helper functions).
vec3 to_view(vec2 uv, float raw, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 p = to_view(uv, textureLod(depth_tex, uv, 0.0).r, INV_PROJECTION_MATRIX);
	float dist = -p.z;
	float occl = 0.0;
	if (dist < far_fade && dist > 0.05) {
		// The surface normal from the depth's own slopes.
		vec2 px = 1.0 / VIEWPORT_SIZE;
		vec3 px_r = to_view(uv + vec2(px.x, 0.0), textureLod(depth_tex, uv + vec2(px.x, 0.0), 0.0).r, INV_PROJECTION_MATRIX);
		vec3 px_u = to_view(uv + vec2(0.0, px.y), textureLod(depth_tex, uv + vec2(0.0, px.y), 0.0).r, INV_PROJECTION_MATRIX);
		vec3 n = normalize(cross(px_r - p, px_u - p));
		// Projected radius on screen.
		float rs = radius * PROJECTION_MATRIX[1][1] * 0.5 / dist;
		rs = clamp(rs, 3.0 * px.y, 0.08);
		// Interleaved rotation per pixel (4x4), so 8 taps cover the disc.
		ivec2 ip = ivec2(FRAGCOORD.xy) % 4;
		float rot = float((ip.x * 4 + ip.y) * 7 % 16) / 16.0 * TAU;
		float sum = 0.0;
		for (int i = 0; i < 8; i++) {
			float a = rot + float(i) * 2.39996;
			float r = sqrt((float(i) + 0.5) / 8.0);
			vec2 o = vec2(cos(a), sin(a)) * r * rs;
			o.x *= VIEWPORT_SIZE.y / VIEWPORT_SIZE.x;
			vec3 s = to_view(uv + o, textureLod(depth_tex, uv + o, 0.0).r, INV_PROJECTION_MATRIX);
			vec3 d = s - p;
			float l = length(d);
			// Occluders above the surface, within reach, count.
			float facing = max(dot(n, d / max(l, 1e-4)) - 0.1, 0.0);
			float reach = 1.0 - smoothstep(radius * 0.6, radius * 2.2, l);
			sum += facing * reach;
		}
		occl = clamp(sum / 8.0 * 2.2, 0.0, 1.0);
		occl *= 1.0 - smoothstep(far_fade * 0.5, far_fade, dist);
	}
	float k = clamp(occl * strength, 0.0, 1.0);
	ALBEDO = vec3(0.012, 0.016, 0.035) * shade_tint;
	ALPHA = k * 0.6;
}

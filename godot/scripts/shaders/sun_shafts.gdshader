shader_type spatial;
// Crepuscular rays: light from the sun streaming past trees, cliffs and
// clouds. The open sky near the sun (where the depth buffer is empty) is
// smeared toward the sun's place on screen; whatever stands in the way cuts
// dark lanes through it. Added over the frame (blend_add).
render_mode unshaded, blend_add, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 sun_uv = vec2(0.5, 0.2);
uniform float intensity = 0.0;   // 0 when the sun is behind the camera
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float decay = 0.94;
uniform float length_ = 0.85;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float sky_at(vec2 uv) {
	float raw = textureLod(depth_tex, uv, 0.0).r;
	// Nothing drawn there: open sky (or clouds in the sky shader).
	float open = step(0.99999, raw);
	vec3 c = textureLod(screen_tex, uv, 1.5).rgb;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	return open * smoothstep(0.45, 1.0, lum);
}

void fragment() {
	if (intensity < 0.001) {
		ALBEDO = vec3(0.0);
	} else {
		vec2 uv = SCREEN_UV;
		vec2 delta = (sun_uv - uv) * length_ / 20.0;
		ivec2 ip = ivec2(FRAGCOORD.xy) % 4;
		float jitter = float((ip.x * 4 + ip.y) * 7 % 16) / 16.0;
		vec2 s = uv + delta * jitter;
		float w = 1.0;
		float sum = 0.0;
		for (int i = 0; i < 20; i++) {
			sum += sky_at(clamp(s, vec2(0.001), vec2(0.999))) * w;
			w *= decay;
			s += delta;
		}
		sum /= 9.0;
		// Strongest close to the sun, fading over the screen.
		vec2 d = uv - sun_uv;
		d.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		float near_sun = 1.0 / (1.0 + dot(d, d) * 6.0);
		ALBEDO = sun_color * sum * intensity * mix(0.35, 1.0, near_sun);
	}
}

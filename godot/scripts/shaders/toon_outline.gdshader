shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
// Ink outline (inverted hull): the mesh drawn again slightly inflated along its
// normals, back faces only, in a dark tint of the surface colour. Width is kept
// roughly constant on screen and fades out at a distance.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 line_tint : source_color = vec4(0.22, 0.16, 0.24, 1.0);
uniform float width = 0.0016;
uniform float alpha_cut = 0.0;

#include "res://scripts/shaders/leg_collide.gdshaderinc"

void vertex() {
	VERTEX = leg_collide(VERTEX);
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = max(-view_pos.z, 0.5);
	float w = width * clamp(dist, 0.5, 6.0) * (1.0 - smoothstep(18.0, 30.0, dist));
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	view_pos.xyz += n * w;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (alpha_cut > 0.0 && t.a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb * line_tint.rgb;
}

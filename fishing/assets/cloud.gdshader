shader_type spatial;
// Low-poly cumulus: puffs merged into one mesh; the base is flattened (no
// vertex below y = 0 locally), tops are bright white, undersides a soft
// blue-grey that darkens when the weather turns.
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 top_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 base_color : source_color = vec3(0.74, 0.80, 0.90);
uniform float height = 6.0;
varying float h;

void vertex() {
	VERTEX.y = max(VERTEX.y, 0.0);
	h = clamp(VERTEX.y / height, 0.0, 1.0);
}

void fragment() {
	// facets catch a little light so the low-poly shape reads
	float facet = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.4, 0.8, 0.3, 0.0)).xyz) * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = mix(base_color, top_color, smoothstep(0.0, 0.85, h));
	ALBEDO = c * (0.82 + 0.18 * facet);
}

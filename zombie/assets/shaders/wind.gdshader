shader_type spatial;
// Vegetation in a breeze.
//
// Everything green in the world runs this: grass, bushes and the canopies of
// the trees. The sway is worked out per vertex from the world position, so a
// whole forest moves as one weather system rather than every tree dancing to
// its own beat, and it costs nothing but a couple of sines in the vertex
// stage - no CPU work, no per-object state, and it batches with MultiMesh.
//
// Only the top of a plant moves: the displacement is weighted by height above
// the model's own base, squared, so trunks stay put and leaves travel.

render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float sway_strength : hint_range(0.0, 1.0) = 0.12;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.1;
uniform float gust_strength : hint_range(0.0, 1.0) = 0.35;
uniform float height_scale = 1.0;      // how tall this kind of plant is
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ao_strength : hint_range(0.0, 1.0) = 0.35;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;

varying float v_sway;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.6);
	float bend = h * h;
	// Two scales of motion: a steady sway, and slower gusts rolling across the
	// landscape so that whole stands of trees lean together.
	float t = TIME * sway_speed;
	float phase = dot(w.xz, wind_dir) * 0.35;
	float gust = sin(TIME * 0.21 + dot(w.xz, wind_dir) * 0.045) * 0.5 + 0.5;
	float amount = sway_strength * (0.35 + gust * gust_strength * 2.0);
	vec2 offset = wind_dir * (sin(t + phase) * 0.6 + sin(t * 1.7 + phase * 2.1) * 0.4);
	w.xz += offset * amount * bend;
	w.y -= abs(offset.x) * amount * bend * 0.25;   // the tip dips as it leans
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	v_sway = bend;
}

void fragment() {
	vec4 c = COLOR * tint;
	ALBEDO = c.rgb;
	// Fake the light that undergrowth loses at its base, which is most of what
	// makes a bush read as a solid thing rather than a flat cut-out.
	AO = mix(1.0 - ao_strength, 1.0, clamp(v_sway + 0.25, 0.0, 1.0));
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = 1.0;
	if (alpha_scissor > 0.0) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
}

shader_type spatial;
// First-person hand. The mesh is baked so the wrist sits at the origin, the
// fingers point down -Z and the palm faces -Y. `curl` (0 = open, 1 = fist)
// rolls every vertex past the knuckle line down toward the palm, a little more
// the further out it is, which reads as fingers closing. The thumb (on the
// `thumb_side` of the hand) closes less and sideways.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 skin : source_color = vec3(0.93, 0.72, 0.58);
uniform float curl : hint_range(0.0, 1.0) = 0.3;
uniform float knuckle = 0.085;      // distance from the wrist to the knuckles (m)
uniform float finger_len = 0.10;    // knuckles to fingertips (m)
uniform float thumb_side = 1.0;     // +1: thumb on +X, -1: thumb on -X
uniform float thumb_x = 0.035;      // where the thumb starts across the hand
uniform float palm_y = -0.012;      // height of the bend axis

void vertex() {
	float side = VERTEX.x * thumb_side;
	float thumb = smoothstep(thumb_x - 0.006, thumb_x + 0.012, side);
	float past = -VERTEX.z - knuckle;
	if (past > 0.0) {
		// Bend the finger into a circular arc that keeps its length: total bend
		// ~200 degrees at a full fist, so the tips tuck in under the palm.
		float k = max(curl * (1.0 - thumb * 0.35) * 3.5 / finger_len, 0.0001);
		float phi = past * k;
		float c = cos(phi);
		float sn = sin(phi);
		float h = VERTEX.y - palm_y;
		float cz = -knuckle - sn / k;
		float cy = palm_y - (1.0 - c) / k;
		VERTEX.y = cy + h * c;
		VERTEX.z = cz - h * sn;
		vec2 n = vec2(NORMAL.y * c + NORMAL.z * sn, -NORMAL.y * sn + NORMAL.z * c);
		NORMAL.y = n.x;
		NORMAL.z = n.y;
	}
	// thumb folds in across the palm a little as the hand closes
	VERTEX.x -= thumb * curl * 0.03 * thumb_side * clamp(-VERTEX.z / 0.12, 0.0, 1.0);
}

void fragment() {
	// soft warm rim so the hands don't go flat in shade
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = skin;
	ROUGHNESS = 0.72;
	SPECULAR = 0.25;
	EMISSION = skin * (0.12 + rim * 0.16);
}

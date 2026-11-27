// Clothing that collides with the legs: each thigh is a tapered capsule
// (hip joint a, knee b, radius r.x at the hip, r.y at the knee) in this
// mesh's own space, updated every frame from the posed skeleton
// (LegCollider). A clothing vertex inside a capsule is pushed out to its
// surface, so skirts drape over the thighs instead of being pierced.
uniform vec3 leg_a0 = vec3(0.0);
uniform vec3 leg_b0 = vec3(0.0);
uniform vec3 leg_a1 = vec3(0.0);
uniform vec3 leg_b1 = vec3(0.0);
uniform vec2 leg_r = vec2(0.0);   // 0 = off

vec3 leg_push(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = dot(p - a, ab) / max(dot(ab, ab), 1e-6);
	if (t <= 0.0) {
		return p;   // above the hip joint: the waist is left alone
	}
	t = min(t, 1.0);
	vec3 c = a + ab * t;
	vec3 d = p - c;
	float r = mix(leg_r.x, leg_r.y, t);
	float l = length(d);
	if (l < r && l > 1e-5) {
		return c + d / l * r;
	}
	return p;
}

vec3 leg_collide(vec3 p) {
	if (leg_r.x <= 0.0) {
		return p;
	}
	return leg_push(leg_push(p, leg_a0, leg_b0), leg_a1, leg_b1);
}

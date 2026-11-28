// Smooth cubic B-spline sampling of a low-resolution texture (4 bilinear taps).
vec4 cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

// Where to take the four bilinear taps and how to weigh them. The caller
// samples the texture itself (passing a sampler, above all a built-in one
// such as TEXTURE, into a function breaks the Compatibility compiler):
//   vec4 o; vec2 w; bicubic_taps(UV, TEXTURE_PIXEL_SIZE, o, w);
//   vec4 c = bicubic_mix(texture(TEXTURE, o.xz), texture(TEXTURE, o.yz),
//                        texture(TEXTURE, o.xw), texture(TEXTURE, o.yw), w);
void bicubic_taps(vec2 uv, vec2 texel, out vec4 offset, out vec2 weight) {
	vec2 size = 1.0 / texel;
	vec2 coord = uv * size - 0.5;
	vec2 f = fract(coord);
	coord -= f;
	vec4 xc = cubic(f.x);
	vec4 yc = cubic(f.y);
	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	offset = (c + vec4(xc.yw, yc.yw) / s) * texel.xxyy;
	weight = vec2(s.x / (s.x + s.y), s.z / (s.z + s.w));
}

vec4 bicubic_mix(vec4 s0, vec4 s1, vec4 s2, vec4 s3, vec2 weight) {
	return mix(mix(s3, s2, weight.x), mix(s1, s0, weight.x), weight.y);
}

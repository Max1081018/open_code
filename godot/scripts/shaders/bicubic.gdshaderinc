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

vec4 bicubic(sampler2D tex, vec2 uv, vec2 texel) {
	vec2 size = 1.0 / texel;
	vec2 coord = uv * size - 0.5;
	vec2 f = fract(coord);
	coord -= f;
	vec4 xc = cubic(f.x);
	vec4 yc = cubic(f.y);
	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 offset = (c + vec4(xc.yw, yc.yw) / s) * texel.xxyy;
	vec4 s0 = texture(tex, offset.xz);
	vec4 s1 = texture(tex, offset.yz);
	vec4 s2 = texture(tex, offset.xw);
	vec4 s3 = texture(tex, offset.yw);
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

shader_type canvas_item;
// Terrain surface: relief, mottling, and a natural palette per material.
//
// The Kenney tiles are flat vector fills with a few strata lines. Three
// things turn them into ground:
//   * relief — a normal derived from the art's own luminance edges, lit
//     from the upper left, so strata read as carved rather than painted;
//   * mottling — world-space noise, so a wall of identical tiles stops
//     repeating visibly;
//   * palette — each atlas row (one material) gets its own saturation and
//     tint, and everything cools and darkens with depth, so soil, rock and
//     the deep read as distinct layers.

uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;
uniform int quality = 2;            // 0 flat, 1 mottled, 2+ relief
uniform float relief = 0.55;
uniform float detail = 0.20;
uniform float brightness = 0.92;
uniform vec4 row_tint[9];
uniform float row_saturation[9];
uniform float rows = 9.0;
uniform float columns = 16.0;
uniform float surface_px = 12288.0;  // mean surface, in world pixels
uniform float deep_px = 32000.0;     // where the basalt begins
// The tile light map, so relief faces whichever way the light comes from:
// strata catch a torch on the torch's side, the sun from above.
uniform sampler2D light_tex : filter_linear;
uniform vec2 light_origin = vec2(0.0);
uniform vec2 light_size = vec2(1.0);
// Bevel: each exposed side of a block becomes a face. The atlas column is
// the neighbour mask (bit set = that side open to air: 1 up, 2 down,
// 4 left, 8 right), so the shader knows which edges to shape.
uniform float bevel = 0.0;
uniform vec4 deep_tint : source_color = vec4(0.66, 0.68, 0.86, 1.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 c = base.rgb;
	int row = clamp(int(floor(UV.y * rows)), 0, 8);

	if (quality >= 2) {
		vec2 cell = vec2(1.0 / columns, 1.0 / rows);
		vec2 lo = floor(UV / cell) * cell + TEXTURE_PIXEL_SIZE;
		vec2 hi = lo + cell - TEXTURE_PIXEL_SIZE * 2.0;
		vec2 step_px = TEXTURE_PIXEL_SIZE * 2.5;
		// Samples stay inside this tile's own atlas cell: a neighbouring cell
		// holds a different edge piece, and bleeding into it draws seams.
		// Inlined, because the Compatibility renderer (the one Android uses)
		// cannot pass TEXTURE into a helper function.
		float hl = luma(texture(TEXTURE, clamp(UV - vec2(step_px.x, 0.0), lo, hi)).rgb);
		float hr = luma(texture(TEXTURE, clamp(UV + vec2(step_px.x, 0.0), lo, hi)).rgb);
		float hu = luma(texture(TEXTURE, clamp(UV - vec2(0.0, step_px.y), lo, hi)).rgb);
		float hd = luma(texture(TEXTURE, clamp(UV + vec2(0.0, step_px.y), lo, hi)).rgb);
		vec3 normal = normalize(vec3((hl - hr) * 5.0, (hu - hd) * 5.0, 1.0));
		// Toward the light: the light map's slope around this point.
		vec2 luv = (world - light_origin) / light_size;
		vec2 step_l = 96.0 / light_size;
		float ll = dot(texture(light_tex, luv - vec2(step_l.x, 0.0)).rgb, vec3(0.333));
		float lr = dot(texture(light_tex, luv + vec2(step_l.x, 0.0)).rgb, vec3(0.333));
		float lu = dot(texture(light_tex, luv - vec2(0.0, step_l.y)).rgb, vec3(0.333));
		float ld = dot(texture(light_tex, luv + vec2(0.0, step_l.y)).rgb, vec3(0.333));
		vec2 slope = vec2(lr - ll, ld - lu);
		vec2 toward = mix(vec2(-0.55, -0.65), normalize(slope + vec2(1e-4)), clamp(length(slope) * 6.0, 0.0, 0.85));
		float lit = dot(normal, normalize(vec3(toward, 0.55)));
		c *= mix(1.0, 0.45 + lit * 0.85, relief);
	}

	if (quality >= 1 && bevel > 0.0) {
		int m = int(floor(UV.x * columns));
		vec2 local = fract(UV * vec2(columns, rows));
		float bw = 0.17;
		float top = ((m & 1) != 0) ? 1.0 - smoothstep(0.0, bw, local.y) : 0.0;
		float bottom = ((m & 2) != 0) ? 1.0 - smoothstep(0.0, bw * 1.4, 1.0 - local.y) : 0.0;
		float left = ((m & 4) != 0) ? 1.0 - smoothstep(0.0, bw, local.x) : 0.0;
		float right = ((m & 8) != 0) ? 1.0 - smoothstep(0.0, bw, 1.0 - local.x) : 0.0;
		// Faces lit from the upper left by default; the light map's slope
		// below (quality 2) refines it.
		float face = 1.0;
		face += top * 0.30;                 // the top catches the light
		face -= bottom * 0.42;              // the underside is in shadow
		face += left * 0.16 - right * 0.20; // sides, from the light's side
		// Away from every open edge the block is buried: a little darker.
		float exposed = max(max(top, bottom), max(left, right));
		float buried = (m == 0) ? 1.0 : 0.0;
		face *= mix(1.0, 0.88, buried);
		c *= mix(1.0, face, bevel);
		// A thin bright lip on the top edge, as on a worn stone corner.
		float lip = ((m & 1) != 0) ? smoothstep(0.035, 0.0, abs(local.y - 0.02)) : 0.0;
		c += vec3(0.10, 0.09, 0.08) * lip * bevel;
	}

	if (quality >= 1) {
		float broad = texture(detail_noise, world / 900.0).r;
		float fine = texture(detail_noise, world / 140.0).g;
		float mottle = broad * 0.65 + fine * 0.35;
		c *= mix(1.0 - detail, 1.0 + detail * 0.55, mottle);
	}

	float grey = luma(c);
	c = mix(vec3(grey), c, row_saturation[row]);
	c *= row_tint[row].rgb * brightness;

	float depth = smoothstep(surface_px + 2000.0, deep_px, world.y);
	c = mix(c, c * deep_tint.rgb, depth * 0.35);

	COLOR = vec4(c, base.a) * COLOR;
}

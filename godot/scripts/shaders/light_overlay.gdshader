shader_type canvas_item;
render_mode blend_mul;
// The light map multiplied over the world. It holds one texel per tile,
// so plain bilinear filtering shows the grid as soft squares and diamonds
// of light. A cubic B-spline (four bilinear taps) turns it into smooth
// round falloff, the way real light spreads.

#include "res://scripts/shaders/bicubic.gdshaderinc"

void fragment() {
	vec4 o;
	vec2 w;
	bicubic_taps(UV, TEXTURE_PIXEL_SIZE, o, w);
	COLOR = bicubic_mix(texture(TEXTURE, o.xz), texture(TEXTURE, o.yz), texture(TEXTURE, o.xw), texture(TEXTURE, o.yw), w);
}

shader_type canvas_item;
render_mode blend_mul;
// The light map multiplied over the world. It holds one texel per tile,
// so plain bilinear filtering shows the grid as soft squares and diamonds
// of light. A cubic B-spline (four bilinear taps) turns it into smooth
// round falloff, the way real light spreads.

#include "res://scripts/shaders/bicubic.gdshaderinc"

void fragment() {
	COLOR = bicubic(TEXTURE, UV, TEXTURE_PIXEL_SIZE);
}

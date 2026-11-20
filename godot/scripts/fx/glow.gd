class_name Glow
extends RefCounted
## Additive halos drawn above the light map, so lights bloom.
##
## The light map darkens everything beneath it by multiplication, which is
## correct for surfaces but leaves a torch looking like a lit object rather
## than a light. A soft additive halo over the top is what reads as glow.

static var _texture: Texture2D
static var _material: CanvasItemMaterial


static func make(color: Color, radius_tiles: float, pulse := true) -> Sprite2D:
	if _texture == null:
		_texture = load("res://assets/fx/light_01.png")  # a soft falloff, not a ring
		_material = CanvasItemMaterial.new()
		_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var halo := Sprite2D.new()
	halo.texture = _texture
	halo.material = _material
	halo.z_as_relative = false
	halo.z_index = 60
	var size := radius_tiles * 128.0 * 2.0
	halo.scale = Vector2.ONE * size / float(_texture.get_width())
	halo.modulate = Color(color.r, color.g, color.b, 0.30)
	halo.position = Vector2(0, -64)
	if pulse:
		halo.ready.connect(func():
			var tween := halo.create_tween().set_loops()
			var base := halo.modulate.a
			tween.tween_property(halo, "modulate:a", base * 0.75, randf_range(0.6, 1.1)) \
				.set_trans(Tween.TRANS_SINE)
			tween.tween_property(halo, "modulate:a", base, randf_range(0.6, 1.1)) \
				.set_trans(Tween.TRANS_SINE))
	return halo


## A halo centred on a parent node's own origin.
static func attach(parent: Node2D, color: Color, radius_tiles: float, offset := Vector2.ZERO) -> Sprite2D:
	var halo := make(color, radius_tiles)
	halo.position = offset
	parent.add_child(halo)
	return halo

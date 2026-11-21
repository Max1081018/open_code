class_name TreeBreak
extends Node2D
## A felled tree coming apart: its own drawing is cut into fragments, the
## crown bursting into leaves and the trunk splitting into chunks of wood
## that tumble, bounce on the ground, settle, and become the wood you pick
## up. One node runs every fragment; nothing here has a script of its own.

const TILE := 128.0
const GRAVITY := 2600.0

var level: Level
var _pieces: Array[Dictionary] = []
var _wood_left := 0
var _apple := false
var _age := 0.0
var _foot := Vector2.ZERO


## Shatter `tree` (an ObjectArt tree node) standing at `foot`, hit from `from_x`.
static func shatter(level: Level, tree: Node2D, from_x: float, wood: int, apple: bool) -> void:
	var sprite: Sprite2D = null
	for child in tree.get_children():
		if child is Sprite2D and child.texture != null and not (child is SoftShadow):
			if sprite == null or child.texture.get_height() > sprite.texture.get_height():
				sprite = child
	var node := TreeBreak.new()
	node.level = level
	node._wood_left = wood
	node._apple = apple
	level.fx_layer.add_child(node)
	if sprite:
		node._cut(sprite, tree, from_x)
	tree.queue_free()


func _cut(sprite: Sprite2D, tree: Node2D, from_x: float) -> void:
	var foot := tree.global_position
	_foot = foot
	var away := 1.0 if foot.x >= from_x else -1.0
	var height := sprite.texture.get_height() * sprite.global_scale.y

	# The crown dissolves: the tree's own leafy drawing swells a little and
	# fades inside a burst of tumbling leaves.
	var crown := Sprite2D.new()
	crown.texture = sprite.texture
	crown.material = sprite.material
	crown.centered = false
	crown.global_position = sprite.global_position
	crown.scale = sprite.global_scale
	crown.z_index = 11
	add_child(crown)
	var tween := crown.create_tween().set_parallel()
	tween.tween_property(crown, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tween.tween_property(crown, "scale", sprite.global_scale * Vector2(1.08, 1.04), 0.35)
	tween.tween_property(crown, "position:y", crown.position.y - 30.0, 0.35)
	tween.chain().tween_callback(crown.queue_free)
	for i in 7:
		var at := foot + Vector2(randf_range(-110, 110), -height * randf_range(0.45, 0.95))
		Effects.burst(level.fx_layer, at, "leaves", Color(0.5, 0.72, 0.34) if i % 3 else Color(0.78, 0.6, 0.25))

	# The trunk splits into chunks of wood, flung away from the axe.
	var log_texture: Texture2D = load("res://assets/rendered/resource-wood.png")
	var chunks := clampi(_wood_left, 3, 7)
	for i in chunks:
		var piece := Sprite2D.new()
		piece.texture = log_texture
		var k := randf_range(56.0, 78.0) / float(log_texture.get_width())
		piece.scale = Vector2(k, k)
		piece.position = foot + Vector2(randf_range(-20, 20), -40.0 - i * (height * 0.35 / chunks))
		piece.rotation = randf() * TAU
		piece.z_index = 12
		add_child(piece)
		var velocity := Vector2(away * randf_range(120, 420) + randf_range(-120, 120), -randf_range(380, 760))
		_pieces.append({"node": piece, "velocity": velocity, "spin": randf_range(-10.0, 10.0),
			"trunk": true, "rest": 0.0, "life": randf_range(1.8, 2.6)})
	# Splinters and dust where the trunk broke.
	Effects.burst(level.fx_layer, foot + Vector2(0, -50), "break", Color(0.66, 0.46, 0.28))
	Effects.burst(level.fx_layer, foot + Vector2(0, -50), "splinters", Color(0.86, 0.70, 0.48))
	Effects.burst(level.fx_layer, foot + Vector2(0, -10), "smoke", Color(0.8, 0.72, 0.6))


func _physics_process(delta: float) -> void:
	_age += delta
	var data := level.data
	for i in range(_pieces.size() - 1, -1, -1):
		var p: Dictionary = _pieces[i]
		var node: Sprite2D = p.node
		p.life -= delta
		var v: Vector2 = p.velocity
		v.y = minf(v.y + GRAVITY * delta, 1800.0)
		var next := node.position + v * delta
		var radius := 20.0 * node.scale.x
		var below := World.cell_of(next + Vector2(0, radius))
		if data.is_solid(below.x, below.y) and v.y > 0.0:
			# Bounce, losing energy, and roll to a stop.
			next.y = below.y * TILE - radius
			v.y = -v.y * 0.35 if absf(v.y) > 220.0 else 0.0
			v.x *= 0.62
			p.spin *= 0.6
			if v.y == 0.0:
				p.rest += delta
		var side := World.cell_of(next + Vector2(signf(v.x) * radius, 0))
		if data.is_solid(side.x, side.y):
			v.x = -v.x * 0.3
			next.x = node.position.x
		node.position = next
		node.rotation += p.spin * delta
		p.velocity = v
		# Settled trunk pieces turn into wood you can pick up.
		if p.trunk and (p.rest > 0.25 or p.life < 0.6) and _wood_left > 0:
			var share := maxi(1, _wood_left / maxi(1, _count_trunk()))
			_drop_wood(node.position + Vector2(0, -10), share)
			_wood_left -= share
			p.trunk = false
			p.life = minf(p.life, 0.25)
		if p.life <= 0.5:
			node.modulate.a = maxf(p.life / 0.5, 0.0)
		if p.life <= 0.0:
			node.queue_free()
			_pieces.remove_at(i)
	if _pieces.is_empty():
		if _wood_left > 0:
			_drop_wood(_foot + Vector2(0, -60), _wood_left)
		if _apple:
			level.spawn_drop("apple", 1, _foot + Vector2(0, -260))
		queue_free()


func _count_trunk() -> int:
	var n := 0
	for p in _pieces:
		if p.trunk:
			n += 1
	return n


func _drop_wood(at: Vector2, amount: int) -> void:
	level.spawn_drop("wood", amount, at)

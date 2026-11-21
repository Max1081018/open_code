class_name ItemDrop
extends Node2D
## A dropped item: pops out, falls, settles, then flies to the player.

const TILE := 128.0
const MAGNET := 3.2 * TILE
const COLLECT := 0.7 * TILE

var id := ""
var count := 1
var world: World
var player: Player
var velocity := Vector2.ZERO
var _age := 0.0
var _sprite: Sprite2D
var _base_scale := Vector2.ONE

## Pickups in quick succession climb in pitch, so a haul sounds like one.
static var _streak := 0
static var _streak_at := 0


func _ready() -> void:
	z_index = 20
	_sprite = Sprite2D.new()
	_sprite.texture = Items.icon(id)
	if _sprite.texture:
		var longest: float = max(_sprite.texture.get_width(), _sprite.texture.get_height())
		var s := 58.0 / longest
		_sprite.scale = Vector2(s, s)
	_base_scale = _sprite.scale
	add_child(_sprite)
	velocity = Vector2(randf_range(-160, 160), randf_range(-520, -320))


func _physics_process(delta: float) -> void:
	_age += delta
	var to_player := player.global_position + Vector2(0, -90) - global_position
	var distance := to_player.length()

	# After a beat — so the pop reads — anything nearby flies home.
	if _age > 0.35 and distance < MAGNET and player.inventory.can_fit(id, count) and not player.is_dead():
		velocity = velocity.lerp(to_player.normalized() * 1400.0, 8.0 * delta)
		global_position += velocity * delta
		# Drawn in: it shrinks into the player as it arrives.
		_sprite.scale = _base_scale * clampf(distance / (COLLECT * 2.2), 0.45, 1.0)
		if distance < COLLECT:
			_collect()
		return

	velocity.y = minf(velocity.y + 2200.0 * delta, 1400.0)
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	var next := global_position + velocity * delta
	var below := World.cell_of(next + Vector2(0, 22))
	if world.data.is_solid(below.x, below.y) and velocity.y > 0.0:
		next.y = below.y * TILE - 22.0
		velocity.y = -velocity.y * 0.25 if absf(velocity.y) > 200.0 else 0.0
		velocity.x *= 0.6
	var side := World.cell_of(next + Vector2(signf(velocity.x) * 22.0, 0))
	if world.data.is_solid(side.x, side.y):
		velocity.x = -velocity.x * 0.3
		next.x = global_position.x
	global_position = next
	_sprite.position.y = sin(_age * 3.0) * 6.0 - 8.0
	# A slow glint at rest, so things on the ground catch the eye.
	var glint := maxf(sin(_age * 2.2 + float(get_instance_id() % 7)), 0.0)
	var shine := Color(1.5, 1.4, 1.1) if Items.rarity(id) == 0 else _colour() * 1.8
	_sprite.self_modulate = Color(1, 1, 1).lerp(shine, pow(glint, 8.0))


func _collect() -> void:
	var left := player.inventory.add(id, count)
	if left < count:
		var now := Time.get_ticks_msec()
		_streak = mini(_streak + 1, 8) if now - _streak_at < 600 else 0
		_streak_at = now
		Sfx.play("pickup", -4.0, 0.02, 1.0 + _streak * 0.06)
		Effects.burst(get_parent(), global_position, "glow", _colour())
		Game.item_picked.emit(id, count - left)
	if left > 0:
		count = left
		return
	queue_free()


## Rarer finds sparkle in their rarity's colour; common ones in lantern gold.
func _colour() -> Color:
	var rarity := Items.rarity(id)
	return Items.RARITY_COLORS[rarity] if rarity > 0 else UITheme.GOLD

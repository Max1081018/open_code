class_name Spit
extends Node2D
## A glob of glowing acid lobbed by a spitter: flies on an arc, splashes on
## rock, burns whoever it lands on. A raised shield turns it aside (the
## player's own hurt() checks the facing), and a dodge roll's
## invulnerability lets it pass.

const GRAVITY := 1500.0
const RADIUS := 18.0

var level: Level
var velocity := Vector2.ZERO
var damage := 10.0
var colour := Color(0.62, 1.0, 0.38)
var _life := 3.0
var _trail: Array[Vector2] = []


## Fire from `from` so as to land on `target`, taking about `flight` seconds.
static func lob(the_level: Level, from: Vector2, target: Vector2, the_damage: float, flight := 0.8) -> Spit:
	var spit := Spit.new()
	spit.level = the_level
	spit.damage = the_damage
	spit.position = from
	var d := target - from
	spit.velocity = Vector2(d.x / flight, d.y / flight - 0.5 * GRAVITY * flight)
	the_level.fx_layer.add_child(spit)
	return spit


func _ready() -> void:
	z_index = 40


func _physics_process(delta: float) -> void:
	_life -= delta
	velocity.y = minf(velocity.y + GRAVITY * delta, 1600.0)
	position += velocity * delta
	_trail.push_front(position)
	if _trail.size() > 7:
		_trail.pop_back()
	queue_redraw()

	var player := level.player
	if player and not player.is_dead():
		var body_centre := player.global_position + Vector2(0, -95)
		if global_position.distance_to(body_centre) < 70.0 + RADIUS:
			player.hurt(damage, global_position - velocity.normalized() * 40.0)
			_splash()
			return
	var cell := World.cell_of(global_position)
	if level.data.is_solid(cell.x, cell.y) or _life <= 0.0:
		_splash()


func _splash() -> void:
	Effects.burst(level.fx_layer, global_position, "splash", colour)
	Effects.burst(level.fx_layer, global_position, "glow", colour)
	Sfx.play("dig", -10.0, 0.2, 1.4)
	queue_free()


func _draw() -> void:
	# A fading tail, then the glob itself with a bright core.
	for i in range(_trail.size() - 1, 0, -1):
		var k := 1.0 - float(i) / _trail.size()
		draw_circle(_trail[i] - position, RADIUS * (0.4 + 0.5 * k), Color(colour, 0.25 * k))
	draw_circle(Vector2.ZERO, RADIUS * 1.6, Color(colour, 0.22))
	draw_circle(Vector2.ZERO, RADIUS, colour)
	draw_circle(Vector2(-5, -5), RADIUS * 0.45, Color(1, 1, 0.9))

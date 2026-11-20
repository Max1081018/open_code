class_name CollisionDebug
extends Node2D
## The collision view (Settings > Debug: collision shapes): what the
## physics and the hit tests actually use, drawn over the world.
##
##   white      solid terrain edges near the player
##   green      the player's capsule
##   red        enemy boxes (orange while winding up an attack)
##   yellow     the sword's reach, in front of the shoulder
##   cyan       mining and building reach
##   magenta    the interaction zone
##   grey       object footprints; objects are passable, which is drawn
##              dashed so it is plain they are not obstacles
##   blue       water cells
##
## Visual depth (z_index, y-sorting) is a separate matter from all of this:
## nothing drawn here changes with draw order.

const TILE := 128.0

var level: Level


func setup(the_level: Level) -> void:
	level = the_level
	z_as_relative = false
	z_index = 95


func _process(_delta: float) -> void:
	visible = Settings.debug_collision
	if visible:
		queue_redraw()


func _draw() -> void:
	if level == null or level.player == null:
		return
	var player := level.player
	var data := level.data
	var centre := World.cell_of(player.global_position)
	var line := 3.0

	# Terrain: outline each solid cell's open faces, the true collision edge.
	for y in range(centre.y - 9, centre.y + 7):
		for x in range(centre.x - 14, centre.x + 15):
			if data.get_liquid(x, y) == WorldData.WATER:
				draw_rect(Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE)), Color(0.3, 0.6, 1.0, 0.18))
			if not data.is_solid(x, y):
				continue
			var p := Vector2(x, y) * TILE
			var c := Color(1, 1, 1, 0.75)
			if not data.is_solid(x, y - 1):
				draw_line(p, p + Vector2(TILE, 0), c, line)
			if not data.is_solid(x, y + 1):
				draw_line(p + Vector2(0, TILE), p + Vector2(TILE, TILE), c, line)
			if not data.is_solid(x - 1, y):
				draw_line(p, p + Vector2(0, TILE), c, line)
			if not data.is_solid(x + 1, y):
				draw_line(p + Vector2(TILE, 0), p + Vector2(TILE, TILE), c, line)

	# Objects: footprint of the cell they stand in. None of them block.
	for y in range(centre.y - 9, centre.y + 7):
		for x in range(centre.x - 14, centre.x + 15):
			var object := level.world.object_at(Vector2i(x, y))
			if object.is_empty():
				continue
			var rect := Rect2(Vector2(x, y) * TILE + Vector2(8, 8), Vector2(TILE - 16, TILE - 16))
			_dashed_rect(rect, Color(0.8, 0.8, 0.8, 0.8))
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 22), object.type,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.9))

	# The player's capsule.
	for child in player.get_children():
		if child is CollisionShape2D and child.shape is CapsuleShape2D:
			var cap: CapsuleShape2D = child.shape
			var at: Vector2 = player.global_position + child.position
			var half := cap.height * 0.5 - cap.radius
			draw_circle(at - Vector2(0, half), cap.radius, Color(0.3, 1, 0.4, 0.25))
			draw_circle(at + Vector2(0, half), cap.radius, Color(0.3, 1, 0.4, 0.25))
			draw_rect(Rect2(at - Vector2(cap.radius, half), Vector2(cap.radius * 2, half * 2)),
				Color(0.3, 1, 0.4, 0.25))
			draw_rect(Rect2(at - Vector2(cap.radius, cap.height * 0.5), Vector2(cap.radius * 2, cap.height)),
				Color(0.3, 1, 0.4, 0.9), false, line)

	# Sword reach: the half-disc in front of (and over) the shoulder.
	var shoulder := player.global_position + Vector2(0, -130)
	var facing := float(player.facing)
	var start := -PI * 0.5 - 0.13 if facing > 0 else PI * 0.5 + 0.13
	draw_arc(shoulder, Player.SWING_REACH, start, start + PI * facing + 0.26 * facing, 32,
		Color(1, 0.9, 0.2, 0.9), line)
	draw_line(shoulder + Vector2(-40 * facing, -Player.SWING_REACH),
		shoulder + Vector2(-40 * facing, Player.SWING_REACH), Color(1, 0.9, 0.2, 0.5), 2.0)

	# Mining and building reach.
	draw_arc(player.global_position - Vector2(0, 100), Player.REACH * TILE, 0, TAU, 64,
		Color(0.3, 0.9, 1.0, 0.6), 2.0)

	# Interaction zone (cells searched by _interact).
	var cell := World.cell_of(player.global_position - Vector2(0, 60))
	draw_rect(Rect2(Vector2(cell + Vector2i(-3, -2)) * TILE, Vector2(7, 4) * TILE),
		Color(1, 0.3, 1, 0.7), false, 2.0)

	# Enemies.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var rect: Rect2 = enemy.body_rect()
		var winding: bool = enemy.get("_windup") > 0.0
		draw_rect(rect, Color(1, 0.55, 0.1, 0.35) if winding else Color(1, 0.2, 0.2, 0.18))
		draw_rect(rect, Color(1, 0.25, 0.25, 0.95), false, line)


func _dashed_rect(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var steps := 8
		for k in steps:
			if k % 2 == 0:
				draw_line(a.lerp(b, float(k) / steps), a.lerp(b, float(k + 1) / steps), color, 2.0)

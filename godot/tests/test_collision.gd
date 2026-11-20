extends TestCase
## Collision against the art: shapes fit what is drawn, hits land where the
## swing goes.


func _make_level() -> Level:
	var level := Level.new()
	Engine.get_main_loop().root.add_child(level)
	level.start(991)
	return level


func test_every_creature_box_fits_its_art() -> void:
	var level := _make_level()
	var at := level.player.global_position + Vector2(2000, -600)
	for kind in Enemy.KINDS:
		var enemy := level.spawn_enemy(kind, at)
		var spec: Dictionary = Enemy.KINDS[kind]
		var rect: Rect2 = enemy.body_rect()
		var s: float = spec.scale
		check(rect.size.x > 20 * s and rect.size.y > 20 * s, "%s has a real body" % kind)
		if spec.has("toon"):
			check(rect.size.y > 150 * s, "%s (a person) is person-sized" % kind)
		else:
			# Never wider than the drawing (128 px a frame), never taller.
			check(rect.size.x <= 128 * s + 0.5 and rect.size.y <= 128 * s + 0.5,
				"%s box within its frame" % kind)
		if spec.mode in [Enemy.Mode.WALK, Enemy.Mode.HOP]:
			# Walkers stand on the box's bottom edge: no floating, no sinking.
			check_near(rect.end.y, enemy.global_position.y, 2.0, "%s stands on its box" % kind)
		enemy.free()
	level.free()


func test_boxes_differ_with_the_art() -> void:
	var level := _make_level()
	var at := level.player.global_position + Vector2(2000, -600)
	var worm := level.spawn_enemy("worm", at) if Enemy.KINDS.has("worm") else null
	var snail := level.spawn_enemy("snail", at) if Enemy.KINDS.has("snail") else null
	if worm and snail:
		check(worm.body_rect().size.y < snail.body_rect().size.y, "a worm is lower than a snail")
	level.free()


func test_the_sword_reaches_in_front_not_behind() -> void:
	var level := _make_level()
	var player := level.player
	player.facing = 1
	var body := Vector2(80, 80)
	var front := Rect2(player.global_position + Vector2(150, -100), body)
	var behind := Rect2(player.global_position + Vector2(-260, -100), body)
	var far := Rect2(player.global_position + Vector2(520, -100), body)
	var overhead := Rect2(player.global_position + Vector2(-20, -360), body)
	check(player.in_swing_reach(front), "an enemy in front is struck")
	check(not player.in_swing_reach(behind), "an enemy behind is not")
	check(not player.in_swing_reach(far), "an enemy out of reach is not")
	check(player.in_swing_reach(overhead), "the arc passes overhead")
	player.facing = -1
	check(player.in_swing_reach(behind), "turning round turns the reach")
	level.free()


func test_enemies_telegraph_before_they_hit() -> void:
	var level := _make_level()
	var player := level.player
	var enemy := level.spawn_enemy("slime", player.global_position + Vector2(60, 0))
	player.health = player.max_health
	enemy._touch_damage()
	check(enemy._windup > 0.0, "the attack starts with a wind-up")
	check_eq(player.health, player.max_health, "nothing lands during the tell")
	level.free()


func test_placement_rules_match_what_the_ghost_shows() -> void:
	var level := _make_level()
	var player := level.player
	var data := level.data
	var feet := World.cell_of(player.global_position + Vector2(0, -4))
	var ground := feet + Vector2i(2, 0)
	# Find an open cell on the ground two to the right.
	while data.is_solid(ground.x, ground.y):
		ground.y -= 1
	while not data.is_solid(ground.x, ground.y + 1):
		ground.y += 1
	check_eq(player.placement_problem("planks", ground), "", "a block beside solid ground is fine")
	check_eq(player.placement_problem("workbench", ground), "", "a bench on the ground is fine")
	check_eq(player.placement_problem("planks", feet), "You're standing there", "not inside yourself")
	var high := ground + Vector2i(0, -4)
	if data.get_wall(high.x, high.y) == WorldData.AIR:
		check_eq(player.placement_problem("planks", high), "Needs support", "not floating in the air")
	check_eq(player.placement_problem("workbench", ground + Vector2i(0, -2)), "Needs ground", "benches stand on something")
	check_eq(player.placement_problem("planks", feet + Vector2i(40, 0)), "Too far", "out of reach")
	player.inventory.slots[0] = {"id": "planks", "count": 5}
	player.hotbar_index = 0
	player._use_cooldown = 0.0
	player._place("planks", ground)
	check(data.is_solid(ground.x, ground.y), "placing where the ghost was green builds")
	check_eq(player.placement_problem("planks", ground), "Occupied", "and then the cell is taken")
	check_eq(player.inventory.count("planks"), 4, "one plank used")
	level.free()

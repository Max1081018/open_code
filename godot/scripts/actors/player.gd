class_name Player
extends CharacterBody2D
## The adventurer: movement, animation, digging, building, fighting, and
## the lantern they carry.

signal health_changed(health: float, max_health: float)
signal glow_changed(glow: float, max_glow: float)
signal held_changed(index: int)
signal died

const TILE := 128.0

# --- Movement feel --------------------------------------------------------------
const RUN_SPEED := 590.0
const ACCEL := 4200.0
const AIR_ACCEL := 2600.0
const FRICTION := 5200.0
const GRAVITY := 2700.0
const FALL_LIMIT := 1900.0
const JUMP_SPEED := 1480.0  ## apex ~3.2 tiles: clears the 3-tile ledges common in the terrain
## Releasing jump early cuts the rise, so taps hop and holds leap.
const JUMP_CUT := 0.45
## Grace after walking off a ledge during which a jump still counts.
const COYOTE := 0.10
## A jump pressed this long before landing still fires on landing.
const BUFFER := 0.13
const REACH := 5.2  ## tiles
const FALL_DAMAGE_FROM := 2300.0

# --- Lantern --------------------------------------------------------------------
## Glow drained per second underground, before the depth multiplier.
const GLOW_DRAIN := 0.42
## Seconds of total darkness before the dark starts to bite.
const DARK_GRACE := 4.0

var world: World
var level: Node
var input := PlayerInput.new()
var inventory := Inventory.new(40)
var hotbar_index := 0

var max_health := 100.0
var health := 100.0
var lantern_tier := 0
## Relics worn (item ids), at most RELIC_SLOTS.
var relics: Array[String] = []
const RELIC_SLOTS := 3
const FLARE_COST := 25.0
const FLARE_REACH := 6.5 * 128.0
var _flare_cooldown := 0.0
var _air_jumps := 0
signal relics_changed
var glow := 100.0
var dark_time := 0.0
var spawn_point := Vector2.ZERO

var facing := 1
var _coyote := 0.0
var _buffer := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _invulnerable := 0.0
var _use_cooldown := 0.0
var _anim_lock := 0.0
var _dead := false
var _mining_cell := Vector2i(-1, -1)
var _mining_progress := 0.0
var _breath := 0.0
var _step_timer := 0.0

## The character: a rigged 3D model (Body3D), or the older cut-out rig
## (CutoutBody) when 3D characters are switched off. Both speak the same
## small interface.
var body: Node2D
var rig: EquipmentRig
var _was_in_water := false
var _swing_override := ""  ## a weapon drawn just for this swing
var crack: Sprite2D
var aim_marker: Sprite2D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 18.0
	floor_max_angle = deg_to_rad(50)

	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 34.0
	capsule.height = 196.0
	shape.shape = capsule
	shape.position = Vector2(0, -98)
	add_child(shape)

	body = Body3D.new("player") if Settings.characters_3d else CutoutBody.new("player")
	body.run_speed = RUN_SPEED
	body.z_index = 10
	add_child(body)
	body.footstep.connect(_footstep)

	rig = EquipmentRig.new()
	rig.z_index = 10
	add_child(rig)
	rig.setup(self)

	crack = Sprite2D.new()
	crack.texture = AtlasTexture.new()
	crack.texture.atlas = load("res://assets/tiles/overlay.png")
	crack.z_as_relative = false
	crack.z_index = 2
	crack.visible = false

	aim_marker = Sprite2D.new()
	aim_marker.texture = load("res://assets/ui/icons/icon_crosshair.png")
	aim_marker.modulate = Color(1, 1, 1, 0.55)
	aim_marker.scale = Vector2(0.55, 0.55)
	aim_marker.z_as_relative = false
	aim_marker.z_index = 70
	aim_marker.visible = false

	world.add_child(crack)
	world.add_child(aim_marker)
	if Settings.shadows:
		add_child(SoftShadow.under(self, world, 0.85))
	world.dynamic_lights.append(_lantern_light)
	world.dynamic_lights.append(rig.torch_light)
	inventory.changed.connect(_refresh_held)
	_refresh_held()


# =============================================================================
# Frame
# =============================================================================

func _physics_process(delta: float) -> void:
	if _dead:
		velocity.y = minf(velocity.y + GRAVITY * delta, FALL_LIMIT)
		move_and_slide()
		return

	_invulnerable = maxf(_invulnerable - delta, 0.0)
	_use_cooldown = maxf(_use_cooldown - delta, 0.0)
	_anim_lock = maxf(_anim_lock - delta, 0.0)
	_flare_cooldown = maxf(_flare_cooldown - delta, 0.0)
	if input.flare_pressed:
		flare()

	if input.hotbar_select >= 0:
		select_hotbar(input.hotbar_select)

	_move(delta)
	rig.blocking = input.block_held and rig.has_shield() and not rig.swinging()
	_dodge(delta)
	_use_items(delta)
	_work_craft(delta)
	if input.interact_pressed:
		_interact()
	_update_lantern(delta)
	_animate(delta)
	input.end_frame()


func _move(delta: float) -> void:
	var cell := World.cell_of(global_position - Vector2(0, 40))
	var in_water := world.data.get_liquid(cell.x, cell.y) == WorldData.WATER
	var in_lava := world.data.get_liquid(cell.x, cell.y) == WorldData.LAVA
	var gravity := GRAVITY * (0.32 if in_water else 1.0)
	var top_speed := RUN_SPEED * (0.55 if in_water else 1.0) * (0.45 if rig.blocking else 1.0) \
		* (1.18 if has_relic("relic_swiftroot") else 1.0)

	var target := input.move * top_speed
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	if absf(input.move) < 0.05:
		accel = FRICTION if is_on_floor() else AIR_ACCEL * 0.5
	if _dodge_time <= 0.0:
		velocity.x = move_toward(velocity.x, target, accel * delta)
	if absf(input.move) > 0.1:
		facing = 1 if input.move > 0 else -1

	if is_on_floor():
		_coyote = COYOTE
		_air_jumps = 1 if has_relic("relic_featherbone") else 0
	else:
		_coyote -= delta
	if input.jump_pressed:
		_buffer = BUFFER
	else:
		_buffer -= delta

	if _buffer > 0.0 and (_coyote > 0.0 or in_water):
		velocity.y = -JUMP_SPEED * (0.62 if in_water else 1.0)
		_buffer = 0.0
		_coyote = 0.0
		Sfx.play("jump", -6.0)
		_squash(Vector2(0.86, 1.14))
	elif input.jump_pressed and _air_jumps > 0 and not in_water and _coyote <= 0.0:
		# The Featherbone Charm: a second leap from thin air.
		_air_jumps -= 1
		_buffer = 0.0
		velocity.y = -JUMP_SPEED * 0.88
		Sfx.play("jump", -4.0, 0.05, 1.25)
		Effects.burst(level.fx_layer, global_position + Vector2(0, -20), "smoke", Color(0.85, 0.92, 1.0))
		_squash(Vector2(0.8, 1.2))
	if not input.jump_held and velocity.y < 0.0 and not in_water:
		velocity.y *= JUMP_CUT if velocity.y < -JUMP_SPEED * 0.35 else 1.0

	velocity.y = minf(velocity.y + gravity * delta, FALL_LIMIT * (0.3 if in_water else 1.0))
	if not is_on_floor():
		_fall_speed = maxf(_fall_speed, velocity.y)

	var blocked_before := is_on_wall()
	move_and_slide()
	if absf(input.move) > 0.1 and is_on_floor() and (is_on_wall() or blocked_before):
		_try_step_up()

	if is_on_floor() and not _was_on_floor:
		_land()
	_was_on_floor = is_on_floor()

	if in_lava:
		hurt(40.0 * delta, global_position + Vector2(0, 40), false)

	# Into the water: a splash sized by how fast.
	if in_water and not _was_in_water and absf(velocity.y) + absf(velocity.x) * 0.3 > 200.0:
		var surface_y := float(cell.y) * TILE
		for i in 3:
			Effects.burst(level.fx_layer, Vector2(global_position.x + randf_range(-50, 50), surface_y), "splash")
		Sfx.play("land", -8.0, 0.2)
	_was_in_water = in_water


## Walk up one-tile ledges without jumping, as Terraria does. On a phone
## this matters more than anywhere: constant jump-tapping to cross bumpy
## ground is the fastest way to make a game feel like a chore.
## A quick roll: a burst of speed in the direction you are going, with a
## moment where blows pass through you. Short cooldown so it is a choice,
## not a way to travel.
var _dodge_time := 0.0
var _dodge_cooldown := 0.0
var _air_dodged := false
const DODGE_SPEED := 1350.0
const DODGE_TIME := 0.36


func _dodge(delta: float) -> void:
	_dodge_cooldown = maxf(_dodge_cooldown - delta, 0.0)
	if _dodge_time > 0.0:
		_dodge_time -= delta
		velocity.x = facing * DODGE_SPEED * (0.55 + 0.45 * _dodge_time / DODGE_TIME)
		return
	if is_on_floor():
		_air_dodged = false
	if not input.dodge_pressed or _dodge_cooldown > 0.0 or rig.blocking:
		return
	# On the ground any time; in the air, once until you land.
	if not is_on_floor():
		if _air_dodged:
			return
		_air_dodged = true
	if absf(input.move) > 0.1:
		facing = 1 if input.move > 0 else -1
	_dodge_time = DODGE_TIME
	velocity.x = facing * DODGE_SPEED
	velocity.y = minf(velocity.y, 0.0)
	_dodge_cooldown = 0.75
	_invulnerable = maxf(_invulnerable, DODGE_TIME)
	_anim_lock = DODGE_TIME
	body.play("dodge")
	body.speed_scale = 1.0
	Sfx.play("swing", -8.0, 0.15)
	Effects.burst(level.fx_layer, global_position, "smoke", Color(0.85, 0.78, 0.66))


func dodging() -> bool:
	return _dodge_time > 0.0


func _try_step_up() -> void:
	var feet := World.cell_of(global_position + Vector2(0, -8))
	var ahead := feet + Vector2i(facing, 0)
	var data := world.data
	if not data.is_solid(ahead.x, ahead.y):
		return
	for rise in [1, 2]:
		if data.is_solid(ahead.x, ahead.y - rise):
			return
	if data.is_solid(feet.x, feet.y - 2):
		return
	global_position.y = ahead.y * TILE - 1.0
	global_position.x += facing * 10.0
	velocity.y = 0.0


## A foot comes down: the sound of whatever is underfoot, louder when
## running, with a little dust kicked up from dry ground.
func _footstep(running: bool) -> void:
	var under := World.cell_of(global_position + Vector2(0, 20))
	var tile := world.data.get_tile(under.x, under.y)
	var volume := -12.0 if running else -16.0
	match tile:
		WorldData.ROCK, WorldData.BASALT, WorldData.BRICK, WorldData.CRYSTAL:
			Sfx.play("step_stone" if randf() < 0.5 else "step_stone2", volume, 0.12)
		WorldData.PLANKS:
			Sfx.play("step_wood", volume - 2.0, 0.12)
		WorldData.SNOW, WorldData.SAND:
			Sfx.play("step_snow", volume - 1.0, 0.15)
		_:
			Sfx.play("step_grass", volume, 0.15)
	if running and tile in [WorldData.SAND, WorldData.SOIL, WorldData.SNOW]:
		Effects.burst(level.fx_layer, global_position + Vector2(-facing * 20, -6), "smoke",
			_dust_color(under))


func _land() -> void:
	if _fall_speed > FALL_DAMAGE_FROM:
		hurt((_fall_speed - FALL_DAMAGE_FROM) * 0.05, global_position + Vector2(0, 50))
	# Compression scaled by the fall: a hop barely dips, a long drop sits
	# down hard and pushes up again.
	var weight := clampf((_fall_speed - 250.0) / 1300.0, 0.0, 1.0)
	if weight > 0.0:
		_squash(Vector2(1.0 + 0.22 * weight, 1.0 - 0.2 * weight))
	if _fall_speed > 600.0:
		Sfx.play("land", -4.0)
		Effects.burst(level.fx_layer, global_position, "smoke", Color(0.85, 0.78, 0.66))
		if _fall_speed > 1300.0:
			level.shake(4.0 * weight)
	_fall_speed = 0.0


func _squash(amount: Vector2) -> void:
	var tween := create_tween()
	body.scale = amount
	tween.tween_property(body, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)


# =============================================================================
# Items
# =============================================================================

func held_id() -> String:
	var slot = inventory.get_slot(hotbar_index)
	return "" if slot == null else slot.id


func select_hotbar(index: int) -> void:
	if index == hotbar_index or index < 0 or index >= Inventory.HOTBAR_SIZE:
		return
	hotbar_index = index
	Sfx.play("click", -10.0)
	_refresh_held()
	held_changed.emit(index)


func _refresh_held() -> void:
	if rig.swinging() and rig.main.visible and _swing_override != "":
		return  # a sword drawn for a swing stays until the swing is done
	rig.hold(held_id())
	rig.carry_shield(inventory.best_of_kind(Items.Kind.SHIELD))
	held_changed.emit(hotbar_index)


func _use_items(delta: float) -> void:
	aim_marker.visible = false
	_update_ghost()
	if input.attack_pressed:
		attack()

	if not input.use_held:
		_cancel_mining()
		return

	var target := World.cell_of(input.aim)
	var centre := global_position - Vector2(0, 100)
	var in_reach := Vector2(centre / TILE).distance_to(Vector2(target) + Vector2(0.5, 0.5)) <= REACH
	aim_marker.visible = true
	aim_marker.position = World.centre_of(target)
	aim_marker.modulate = Color(1, 1, 1, 0.65) if in_reach else Color(1, 0.4, 0.4, 0.5)
	if input.aim.x != global_position.x:
		facing = 1 if input.aim.x > global_position.x else -1
	if not in_reach:
		_cancel_mining()
		return

	var id := held_id()
	var kind := Items.kind(id) if id != "" else -1
	match kind:
		Items.Kind.SWORD:
			attack()
		Items.Kind.BLOCK, Items.Kind.PLACEABLE:
			_place(id, target)
		Items.Kind.HAMMER:
			_hammer(target, Items.def(id))
		Items.Kind.CONSUMABLE:
			if _use_cooldown <= 0.0:
				consume(hotbar_index)
				_use_cooldown = 0.5
		Items.Kind.RELIC:
			if _use_cooldown <= 0.0:
				wear_relic(hotbar_index)
				_use_cooldown = 0.5
		_:
			# Pickaxes, axes and bare hands all dig.
			_dig(target, delta)


func _tool_stats() -> Dictionary:
	var id := held_id()
	var d := Items.def(id) if id != "" else {}
	if d.get("kind", -1) in [Items.Kind.PICKAXE, Items.Kind.AXE]:
		return d
	# Not holding a tool: use the best pickaxe carried, or bare hands.
	var best := inventory.best_of_kind(Items.Kind.PICKAXE)
	if best != "":
		return Items.def(best)
	return {"power": 1, "speed": 0.45, "kind": Items.Kind.PICKAXE}


func _dig(target: Vector2i, delta: float) -> void:
	var data := world.data
	var object := world.object_at(target)
	var tool := _tool_stats()

	if not object.is_empty() and object.type == "tree":
		_chop(target, object, tool)
		return
	if not object.is_empty() and ObjectArt.item_for(object) != "" and not data.is_solid(target.x, target.y):
		if _use_cooldown <= 0.0:
			_use_cooldown = 0.3
			_swing("mine", 0.3, func():
				world.remove_object(target, true)
				Sfx.play("break"))
		return
	if not data.is_solid(target.x, target.y):
		_cancel_mining()
		return

	var hardness := data.hardness(target.x, target.y)
	if hardness > tool.get("power", 1):
		if _use_cooldown <= 0.0:
			_use_cooldown = 0.5
			_swing("mine", 0.5, func():
				Sfx.play("dig", -8.0, 0.02)
				Effects.burst(level.fx_layer, World.centre_of(target), "hit")
				Effects.float_text(level.fx_layer, World.centre_of(target), "Too hard", UITheme.DANGER, 34))
		return

	if target != _mining_cell:
		_mining_cell = target
		_mining_progress = 0.0

	# Time to break grows with hardness and shrinks with tool power.
	var seconds := 0.18 + hardness * 0.55 / float(tool.get("power", 1))
	_mining_progress += delta / seconds
	if _use_cooldown <= 0.0:
		_use_cooldown = tool.get("speed", 0.4)
		var dust := _dust_color(target)
		var material := data.get_tile(target.x, target.y)
		_swing("mine", _use_cooldown, func():
			_mine_sound(material)
			_mine_debris(material, World.centre_of(target), dust)
			_squash(Vector2(1.04, 0.97)))

	var stage := clampi(int(_mining_progress * 3.0), 0, 2)
	crack.visible = true
	crack.position = World.centre_of(target)
	(crack.texture as AtlasTexture).region = Rect2(Vector2(8 + stage, 0) * TILE, Vector2(TILE, TILE))

	if _mining_progress >= 1.0:
		_break(target)


func _break(target: Vector2i) -> void:
	var data := world.data
	var material := data.get_tile(target.x, target.y)
	var ore := data.get_ore(target.x, target.y)
	var color := _dust_color(target)
	world.set_block(target, WorldData.AIR)
	_cancel_mining()
	Sfx.play("break")
	Effects.burst(level.fx_layer, World.centre_of(target), "break", color)
	level.shake(4.0)
	var drop := Items.drop_for_ore(ore) if ore != WorldData.ORE_NONE else Items.drop_for_tile(material)
	if drop != "":
		level.spawn_drop(drop, 1, World.centre_of(target))
	level.on_tile_broken(target, material, ore)


func _chop(target: Vector2i, object: Dictionary, tool: Dictionary) -> void:
	if _use_cooldown > 0.0:
		return
	_use_cooldown = tool.get("speed", 0.4)
	# Chopping is its own motion: a flatter, heavier blow that lands a beat
	# later than a pick's, and the wood is hurt when the blade bites.
	_swing("chop", _use_cooldown * 1.15, func():
		if world.object_at(target) == object:
			_chop_hit(target, object, tool))


func _chop_hit(target: Vector2i, object: Dictionary, tool: Dictionary) -> void:
	var axe_bonus := 2 if tool.get("kind", -1) == Items.Kind.AXE else 1
	if not object.has("max_health"):
		object["max_health"] = int(object.get("health", 5))
	object.health = int(object.get("health", 5)) - tool.get("power", 1) * axe_bonus
	_tree_damage(target, object)
	Sfx.play("chop", 0.0, 0.12)
	var node := world.object_node_at(target)
	if node:
		pass
	level.shake(2.5)
	Effects.burst(level.fx_layer, World.centre_of(target) + Vector2(0, -60), "dig", Color(0.5, 0.75, 0.35))
	if object.health <= 0:
		var falling := world.detach_object_node(target)
		world.remove_object(target)
		if level.quests:
			level.quests.event("fell")
		var apple := String(object.get("art", "")).begins_with("tree") and randf() < 0.35
		if falling:
			# The tree comes apart: crown into leaves, trunk into chunks of
			# wood that tumble and settle where you can pick them up.
			TreeBreak.shatter(level, falling, global_position.x, 4 + randi() % 4, apple)
		else:
			level.spawn_drop("wood", 4 + randi() % 4, World.centre_of(target) + Vector2(0, -80))
		Sfx.play("break", 0.0, 0.05)
		Sfx.play("tree_fall", -4.0, 0.05)
		level.shake(7.0)


## Things you built come down to a hammer in one blow and come back whole:
## planks, brick, and placed objects (an emptied chest only). Natural rock
## and soil are for the pick.
const HAMMERABLE := [WorldData.PLANKS, WorldData.BRICK]


func _hammer(target: Vector2i, tool: Dictionary) -> void:
	if _use_cooldown > 0.0:
		return
	_use_cooldown = tool.get("speed", 0.3)
	var object := world.object_at(target)
	var tile := world.data.get_tile(target.x, target.y)
	var item := ObjectArt.item_for(object) if not object.is_empty() else ""
	var can: bool = (item != "" and not (object.get("type", "") == "chest" and not (object.get("loot", []) as Array).is_empty())) \
		or (object.is_empty() and tile in HAMMERABLE)
	_swing("mine", _use_cooldown, func():
		if not can:
			Sfx.play("hit", -10.0, 0.1)
			if object.get("type", "") == "chest":
				Effects.float_text(level.fx_layer, World.centre_of(target), "Empty it first", UITheme.DANGER, 30)
			return
		var at := World.centre_of(target)
		if item != "":
			world.remove_object(target, true)
		else:
			world.set_block(target, WorldData.AIR)
			level.spawn_drop(Items.drop_for_tile(tile), 1, at)
		Sfx.play("chop" if tile == WorldData.PLANKS or item != "" else "hit", -2.0, 0.1)
		Effects.burst(level.fx_layer, at, "splinters", Color(0.8, 0.66, 0.46) if tile != WorldData.BRICK else Color(0.7, 0.66, 0.66))
		Effects.burst(level.fx_layer, at, "smoke", Color(0.85, 0.8, 0.7))
		level.shake(2.0)
		if level.quests:
			level.quests.event("hammer"))


## Each material answers the pick in its own voice: dirt thuds, stone
## clinks, crystal rings, wood knocks.
func _mine_sound(material: int) -> void:
	match material:
		WorldData.ROCK, WorldData.BASALT, WorldData.BRICK:
			Sfx.play("hit", -7.0, 0.12)
			Sfx.play("dig", -10.0, 0.1)
		WorldData.CRYSTAL:
			Sfx.play("pickup", -9.0, 0.2)
			Sfx.play("hit", -12.0, 0.15)
		WorldData.PLANKS:
			Sfx.play("chop", -6.0, 0.15)
		WorldData.SNOW, WorldData.SAND:
			Sfx.play("dig", -6.0, 0.25)
		_:
			Sfx.play("dig", -3.0, 0.12)


## Each blow shows on the tree: a notch cut deeper into the trunk where the
## axe bites, bark chips and splinters flying from it, leaves shaken loose,
## and a lean that grows as the tree weakens.
func _tree_damage(cell: Vector2i, object: Dictionary) -> void:
	var node := world.object_node_at(cell)
	var foot := World.centre_of(cell) + Vector2(0, TILE * 0.5)
	var side := -1.0 if foot.x > global_position.x else 1.0
	var bite := foot + Vector2(side * 22.0, -54.0)
	var damage := 1.0 - clampf(float(object.health) / float(object.max_health), 0.0, 1.0)
	Effects.burst(level.fx_layer, bite, "dig", Color(0.55, 0.36, 0.22))
	Effects.burst(level.fx_layer, bite + Vector2(side * 8, 0), "hit")
	Effects.burst(level.fx_layer, foot + Vector2(randf_range(-80, 80), -randf_range(260, 420)), "dig",
		Color(0.45, 0.68, 0.33))
	if node == null:
		return
	var notch: Polygon2D = node.get_node_or_null("Notch")
	if notch == null:
		notch = Polygon2D.new()
		notch.name = "Notch"
		notch.color = Color(0.22, 0.13, 0.07)
		notch.z_index = 1
		node.add_child(notch)
	# A wedge cut in from the axe's side, deeper with every blow.
	var depth := 6.0 + 22.0 * damage
	var half := 7.0 + 6.0 * damage
	notch.polygon = PackedVector2Array([Vector2(side * 16, -54 - half), Vector2(side * (16 - depth), -54),
		Vector2(side * 16, -54 + half)])
	var pale: Polygon2D = node.get_node_or_null("NotchFace")
	if pale == null:
		pale = Polygon2D.new()
		pale.name = "NotchFace"
		pale.color = Color(0.86, 0.72, 0.5)
		pale.z_index = 1
		node.add_child(pale)
	pale.polygon = PackedVector2Array([Vector2(side * 16, -54 - half * 0.5), Vector2(side * (17 - depth * 0.6), -54),
		Vector2(side * 16, -54 + half * 0.2)])
	# Lean away from the axe as it weakens; the shudder plays around that.
	var lean := -side * 0.06 * damage
	var tween := node.create_tween()
	tween.tween_property(node, "rotation", lean - side * 0.05, 0.05).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(node, "rotation", lean + side * 0.025, 0.10).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "rotation", lean - side * 0.01, 0.10).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "rotation", lean, 0.12).set_trans(Tween.TRANS_SINE)
	if damage > 0.5:
		Sfx.play("chop", -10.0, 0.3)  # a creak in the wood


## What flies off the pick depends on what it hits: clumps from soil,
## grey chips and sparks from stone, violet shards from crystal.
func _mine_debris(material: int, at: Vector2, dust: Color) -> void:
	match material:
		WorldData.ROCK, WorldData.BASALT, WorldData.BRICK:
			Effects.burst(level.fx_layer, at, "splinters", dust.darkened(0.1))
			Effects.burst(level.fx_layer, at, "hit")
		WorldData.CRYSTAL:
			Effects.burst(level.fx_layer, at, "splinters", Color(0.8, 0.6, 1.0))
			Effects.burst(level.fx_layer, at, "glow", Color(0.7, 0.5, 1.0))
		_:
			Effects.burst(level.fx_layer, at, "dig", dust)


func _dust_color(cell: Vector2i) -> Color:
	match world.data.get_tile(cell.x, cell.y):
		WorldData.GRASS, WorldData.SOIL:
			return Color(0.80, 0.52, 0.34)
		WorldData.SAND:
			return Color(0.95, 0.78, 0.55)
		WorldData.SNOW:
			return Color(0.92, 0.95, 1.0)
		WorldData.CRYSTAL:
			return Color(0.72, 0.52, 0.95)
		WorldData.BASALT:
			return Color(0.45, 0.38, 0.45)
	return Color(0.72, 0.72, 0.78)


func _cancel_mining() -> void:
	_mining_cell = Vector2i(-1, -1)
	_mining_progress = 0.0
	crack.visible = false


var ghost: PlacementGhost


## While holding something buildable, preview it where it would go: under
## the finger while it is down, under the mouse on a desktop.
func _update_ghost() -> void:
	if ghost == null:
		ghost = PlacementGhost.new()
		world.add_child(ghost)
	var id := held_id()
	var kind := Items.kind(id) if id != "" else -1
	var point: Vector2 = input.aim if input.use_held else input.hover
	if not (kind in [Items.Kind.BLOCK, Items.Kind.PLACEABLE]) or point == Vector2.INF:
		ghost.hide_ghost()
		return
	var cell := World.cell_of(point)
	ghost.show_at(cell, Items.icon(id), placement_problem(id, cell))


## The player's collision box in world space (the capsule's bounds).
func body_box() -> Rect2:
	return Rect2(global_position - Vector2(34, 196), Vector2(68, 196))


## Why an item cannot go in a cell, or "" if it can. The placement ghost
## shows the same verdict the game will apply.
func placement_problem(id: String, target: Vector2i) -> String:
	var data := world.data
	var centre := global_position - Vector2(0, 100)
	if Vector2(centre / TILE).distance_to(Vector2(target) + Vector2(0.5, 0.5)) > REACH:
		return "Too far"
	if data.is_solid(target.x, target.y) or not world.object_at(target).is_empty():
		return "Occupied"
	if data.get_liquid(target.x, target.y) == WorldData.LAVA:
		return "Lava"
	var d := Items.def(id)
	# Never build a block into a body: the player's own collision box (which
	# can straddle two columns), or anyone else's.
	if d.get("kind", -1) == Items.Kind.BLOCK:
		var cell_rect := Rect2(Vector2(target) * TILE, Vector2(TILE, TILE)).grow(-3)
		if cell_rect.intersects(body_box()):
			return "You're standing there"
		for other in get_tree().get_nodes_in_group("enemies"):
			if cell_rect.intersects(other.body_rect()):
				return "Something's there"
		for npc in get_tree().get_nodes_in_group("npcs"):
			if cell_rect.intersects(Rect2(npc.global_position - Vector2(40, 200), Vector2(80, 200))):
				return "Someone's there"
	if d.get("kind", -1) == Items.Kind.BLOCK:
		if data.get_wall(target.x, target.y) != WorldData.AIR:
			return ""
		for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if data.is_solid(target.x + offset.x, target.y + offset.y):
				return ""
		return "Needs support"
	if not data.is_solid(target.x, target.y + 1):
		return "Needs ground"
	return ""


func _place(id: String, target: Vector2i) -> void:
	if _use_cooldown > 0.0:
		return
	if placement_problem(id, target) != "":
		return
	var d := Items.def(id)
	if d.kind == Items.Kind.BLOCK:
		world.set_block(target, d.block)
		_build_effect(target, false)
	else:
		var object := {"type": d.object}
		if d.object == "chest":
			object["loot"] = []
		world.add_object(target, object)
		_build_effect(target, true)
	inventory.remove_at(hotbar_index, 1)
	_use_cooldown = 0.16
	_swing("place", 0.22)
	# The sound of the material going down: timber knocks, earth and stone thud.
	if d.kind == Items.Kind.BLOCK and d.block == WorldData.PLANKS:
		Sfx.play("place_wood", -3.0, 0.1)
	elif d.kind == Items.Kind.BLOCK:
		Sfx.play("place_stone", -2.0, 0.12)
	else:
		Sfx.play("place_wood", -1.0, 0.06)
	level.on_placed(target, id)


## Something built: a flash of the new cell and a puff of dust; an object
## pops up out of the ground rather than appearing.
func _build_effect(cell: Vector2i, object: bool) -> void:
	var at := World.centre_of(cell)
	Effects.burst(level.fx_layer, at + Vector2(0, 50), "smoke", Color(0.85, 0.8, 0.7))
	if object:
		var node := world.object_node_at(cell)
		if node:
			node.scale = Vector2(1.15, 0.2)
			node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.32) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sfx.play("craft", -6.0, 0.05)
		return
	var flash := ColorRect.new()
	flash.color = Color(1, 0.95, 0.8, 0.55)
	flash.size = Vector2(TILE, TILE)
	flash.position = Vector2(cell) * TILE
	flash.z_index = 30
	level.fx_layer.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.25)
	tween.tween_callback(flash.queue_free)


# =============================================================================
# Crafting: a job that takes a moment of work, not a button that conjures
# =============================================================================

signal craft_finished(id: String)

var _craft := {}  ## recipe, t, duration, beat


## Seconds a recipe takes: more for better gear and heavier stations.
static func craft_time(recipe: Array) -> float:
	var tier: int = Items.def(recipe[0]).get("tier", 1)
	var base := {Items.Station.HAND: 0.7, Items.Station.WORKBENCH: 1.0,
		Items.Station.ANVIL: 1.4, Items.Station.CAMPFIRE: 1.1}
	return float(base.get(recipe[2], 1.0)) + 0.18 * tier


func start_craft(recipe: Array) -> bool:
	if not _craft.is_empty() or _dead:
		return false
	if not inventory.has_all(recipe[3]) or not (recipe[2] in nearby_stations()):
		return false
	_craft = {"recipe": recipe, "t": 0.0, "duration": craft_time(recipe), "beat": 0.0}
	return true


func crafting() -> Array:
	return _craft.get("recipe", [])


func craft_progress() -> float:
	return 0.0 if _craft.is_empty() else clampf(_craft.t / _craft.duration, 0.0, 1.0)


func _work_craft(delta: float) -> void:
	if _craft.is_empty():
		return
	var recipe: Array = _craft.recipe
	_craft.t += delta
	_craft.beat -= delta
	if _craft.beat <= 0.0:
		# A blow of the hammer (or a stir of the pot) every beat.
		_craft.beat = 0.32
		_anim_lock = 0.28
		body.play("use")
		body.speed_scale = 1.0
		var at := global_position + Vector2(facing * 90, -90)
		match recipe[2]:
			Items.Station.ANVIL:
				Sfx.play("anvil", -8.0, 0.05)
				Effects.burst(level.fx_layer, at, "hit")
			Items.Station.WORKBENCH:
				Sfx.play("chop", -8.0, 0.15)
				Effects.burst(level.fx_layer, at, "dig", Color(0.75, 0.55, 0.35))
			Items.Station.CAMPFIRE:
				Sfx.play("dig", -14.0, 0.2)
				Effects.burst(level.fx_layer, at + Vector2(0, -30), "smoke", Color(0.9, 0.9, 0.9))
			_:
				Sfx.play("dig", -12.0, 0.2)
	if _craft.t < _craft.duration:
		return
	_craft = {}
	if inventory.craft(recipe):
		Sfx.play("craft")
		Game.crafted.emit(recipe[0], recipe[1])
		Game.toast("Crafted %s" % Items.item_name(recipe[0]), Items.icon(recipe[0]))
		# The new thing pops out, so the eye sees where it came from.
		Effects.burst(level.fx_layer, global_position + Vector2(0, -160), "glow", UITheme.GOLD)
		var pop := Sprite2D.new()
		pop.texture = Items.icon(recipe[0])
		pop.position = global_position + Vector2(0, -170)
		pop.z_index = 80
		pop.scale = Vector2(0.3, 0.3)
		level.fx_layer.add_child(pop)
		var tween := pop.create_tween()
		tween.tween_property(pop, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(pop, "position:y", pop.position.y - 90, 0.5).set_ease(Tween.EASE_OUT)
		tween.tween_property(pop, "modulate:a", 0.0, 0.3)
		tween.tween_callback(pop.queue_free)
	craft_finished.emit(recipe[0])


func consume(index: int) -> void:
	var slot = inventory.get_slot(index)
	if slot == null:
		return
	var d := Items.def(slot.id)
	if d.kind != Items.Kind.CONSUMABLE:
		return
	var used := false
	if d.has("heal") and health < max_health:
		heal(d.heal)
		used = true
	if d.has("glow"):
		add_glow(d.glow)
		used = true
	if d.has("max_health"):
		max_health += d.max_health
		heal(d.max_health)
		Game.toast("Max health raised to %d" % max_health, Items.icon(slot.id))
		used = true
	if d.has("lantern_tier"):
		lantern_tier += d.lantern_tier
		glow = max_glow()
		glow_changed.emit(glow, max_glow())
		Game.toast("Your lantern burns brighter", Items.icon(slot.id))
		used = true
	if used:
		inventory.remove_at(index, 1)
		Sfx.play("pickup")


## Swing the held item; `on_impact` runs when it connects.
func _swing(kind := "mine", duration := 0.3, on_impact := Callable()) -> void:
	duration = maxf(duration, 0.16)
	_anim_lock = duration
	var clip := EquipmentRig.body_clip(kind)
	body.play(clip)
	body.speed_scale = body.clip_length(clip) / duration
	rig.swing(kind, duration, on_impact)


# =============================================================================
# Combat
# =============================================================================

func attack_damage() -> float:
	var id := held_id()
	if id != "" and Items.kind(id) == Items.Kind.SWORD:
		return Items.def(id).damage
	var best := inventory.best_of_kind(Items.Kind.SWORD)
	if best != "":
		return Items.def(best).damage
	return 5.0


func attack() -> void:
	if _use_cooldown > 0.0:
		return
	var sword := held_id() if held_id() != "" and Items.kind(held_id()) == Items.Kind.SWORD \
		else inventory.best_of_kind(Items.Kind.SWORD)
	_use_cooldown = Items.def(sword).get("speed", 0.4) if sword != "" else 0.45

	# Face the nearest enemy in range: on a touchscreen there is no fine
	# aim, so the swing finds its target the way a player meant it to.
	var nearest: Node2D = null
	var best := 3.2 * TILE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_alive():
			continue
		var d: float = enemy.global_position.distance_to(global_position)
		if d < best:
			best = d
			nearest = enemy
	if nearest != null:
		facing = 1 if nearest.global_position.x > global_position.x else -1

	# Draw the sword for the swing if it is not already in hand.
	if sword != "" and sword != held_id():
		_swing_override = sword
		rig.hold(sword)
	var duration := clampf(_use_cooldown, 0.2, 0.42)
	Sfx.play("swing", -2.0)
	_swing("slash", duration, _slash_hit)
	get_tree().create_timer(duration).timeout.connect(func():
		_swing_override = ""
		_refresh_held())


## The sword's reach: from the shoulder out to blade's length plus the arm,
## across the arc the swing sweeps (over the head and down in front, not
## behind). Tested against the nearest point of the target's box.
const SWING_REACH := 300.0


func in_swing_reach(target: Rect2) -> bool:
	var shoulder := global_position + Vector2(0, -130)
	var nearest := Vector2(clampf(shoulder.x, target.position.x, target.end.x),
		clampf(shoulder.y, target.position.y, target.end.y))
	var local := nearest - shoulder
	local.x *= facing
	return local.length() <= SWING_REACH and local.x >= -40.0


## The sword connects: everything in the arc in front is struck.
func _slash_hit() -> void:
	var arc_centre := global_position + Vector2(facing * 110, -100)
	Effects.burst(level.fx_layer, arc_centre, "slash")
	var damage := attack_damage()
	var landed := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_alive():
			continue
		if in_swing_reach(enemy.body_rect()):
			var crit := randf() < 0.1
			enemy.take_hit(damage * (1.8 if crit else 1.0), global_position, crit)
			if has_relic("relic_ember_heart"):
				enemy.ignite(3.0)
			landed = true
			if crit:
				level.hit_stop(0.09)
	if landed:
		level.shake(3.0)
		level.hit_stop(0.045)


func hurt(amount: float, from: Vector2, knock := true) -> void:
	if _dead or (_invulnerable > 0.0 and knock):
		return
	if has_relic("relic_bulwark"):
		amount *= 0.75
	# A raised shield takes a blow from the front.
	if rig.blocking and knock and signf(from.x - global_position.x) == float(facing):
		var shield_id := inventory.best_of_kind(Items.Kind.SHIELD)
		var guard: float = Items.def(shield_id).get("block", 0.5)
		amount *= 1.0 - guard
		Sfx.play("hit", -4.0, 0.1)
		Effects.burst(level.fx_layer, rig.shield.global_position, "hit")
		velocity.x = signf(global_position.x - from.x) * 620.0 * (1.0 - guard)
		_invulnerable = 0.5
		level.shake(3.0)
		if amount < 0.5:
			return
		health = maxf(health - amount, 0.0)
		health_changed.emit(health, max_health)
		Effects.float_text(level.fx_layer, global_position + Vector2(0, -230), "-%d" % int(amount),
			UITheme.DANGER, 40)
		if health <= 0.0:
			_die()
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if knock:
		_invulnerable = 1.0
		velocity = Vector2(signf(global_position.x - from.x) * 620.0, -520.0)
		_anim_lock = 0.3
		body.play("hurt")
		Sfx.play("hurt")
		level.shake(9.0)
		Effects.float_text(level.fx_layer, global_position + Vector2(0, -230), "-%d" % int(amount),
			UITheme.DANGER)
		var tween := create_tween()
		body.modulate = Color(1, 0.45, 0.45)
		tween.tween_property(body, "modulate", Color.WHITE, 0.35)
	if health <= 0.0:
		_die()


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)
	Effects.burst(level.fx_layer, global_position + Vector2(0, -100), "heal", Color(0.5, 1, 0.5))
	Effects.float_text(level.fx_layer, global_position + Vector2(0, -240), "+%d" % int(amount),
		Color(0.55, 1.0, 0.55))


func _die() -> void:
	_dead = true
	body.play("death")
	Sfx.play("hurt")
	died.emit()


func revive(at: Vector2) -> void:
	_dead = false
	global_position = at
	velocity = Vector2.ZERO
	health = max_health
	glow = maxf(glow, max_glow() * 0.5)
	_invulnerable = 2.0
	health_changed.emit(health, max_health)
	glow_changed.emit(glow, max_glow())
	body.play("idle")


func is_dead() -> bool:
	return _dead


# =============================================================================
# The lantern
# =============================================================================

func max_glow() -> float:
	return 100.0 + lantern_tier * 50.0


func add_glow(amount: float) -> void:
	glow = minf(glow + amount, max_glow())
	glow_changed.emit(glow, max_glow())
	Effects.burst(level.fx_layer, global_position + Vector2(0, -110), "glow", UITheme.GLOW)


## Light radius in tiles. Shrinks as the oil runs down, so running low is
## something the player sees before the meter tells them.
func lantern_radius() -> float:
	var base := 6.0 + lantern_tier * 1.6
	return base * (0.30 + 0.70 * clampf(glow / max_glow(), 0.0, 1.0))


func _lantern_light() -> Array:
	if not is_inside_tree():
		return []
	var position := rig.lantern_position() / TILE
	var warmth := Color(1.0, 0.84, 0.58) * (0.55 + 0.45 * clampf(glow / max_glow(), 0.0, 1.0))
	return [[position, lantern_radius(), warmth]]


func _update_lantern(delta: float) -> void:
	var cell := World.cell_of(global_position - Vector2(0, 100))
	var data := world.data
	var underground := cell.y > data.surface[clampi(cell.x, 0, data.width - 1)] + 6
	var deep := cell.y > WorldData.DEEP_Y

	var change := 0.0
	if world.near_placed_light(cell, 3.5):
		var object_glow := 0.0
		for offset_x in range(-4, 5):
			for offset_y in range(-3, 3):
				var o := world.object_at(cell + Vector2i(offset_x, offset_y))
				if o.get("type", "") == "wardstone":
					object_glow = maxf(object_glow, 18.0)
				elif o.get("type", "") == "campfire":
					object_glow = maxf(object_glow, 4.0)
		change += object_glow
	if not underground and not world.is_night():
		change += 6.0
	if underground:
		# The deep dark presses harder on a weak lantern. Every Lumen Core
		# eases it, which is what makes the depths reachable at all.
		var pressure := 1.0
		if deep:
			pressure = maxf(3.2 - lantern_tier * 0.9, 1.0)
		change -= GLOW_DRAIN * pressure

	if has_relic("relic_moth_lantern") and underground and world.brightness_at(global_position - Vector2(0, 100)) < 0.3:
		change += GLOW_DRAIN * 1.6  # moths feed the flame in the black
	var before := glow
	glow = clampf(glow + change * delta, 0.0, max_glow())
	if int(glow) != int(before):
		glow_changed.emit(glow, max_glow())

	if glow <= 0.0 and underground and world.brightness_at(global_position - Vector2(0, 100)) < 0.25:
		dark_time += delta
		if dark_time > DARK_GRACE:
			hurt(4.0 * delta, global_position, false)
			if fmod(dark_time, 1.0) < delta:
				Effects.float_text(level.fx_layer, global_position + Vector2(0, -250),
					"The dark bites", Color(0.7, 0.55, 1.0), 34)
	else:
		dark_time = 0.0


# =============================================================================
# Interaction
# =============================================================================

func _interact() -> void:
	# People first: talking to someone beside you beats opening a chest.
	var npc: Npc = level.npc_near()
	if npc:
		facing = 1 if npc.global_position.x > global_position.x else -1
		_anim_lock = 0.35
		body.play("interact")
		level.talk_to(npc)
		return
	var cell := World.cell_of(global_position - Vector2(0, 60))
	var best_cell := Vector2i(-1, -1)
	var best := 99.0
	for dy in range(-2, 2):
		for dx in range(-3, 4):
			var c := cell + Vector2i(dx, dy)
			var o := world.object_at(c)
			if o.is_empty() or not (o.type in ["chest", "workbench", "anvil", "campfire", "sign",
					"altar", "wardstone", "torch", "geode", "brazier", "relic_chest"]):
				continue
			var d := Vector2(dx, dy).length()
			if d < best:
				best = d
				best_cell = c
	if best_cell.x >= 0:
		_anim_lock = 0.35
		body.play("interact")
		level.interact_with(best_cell, world.object_at(best_cell))


func nearby_stations() -> Array:
	var stations := [Items.Station.HAND]
	var cell := World.cell_of(global_position - Vector2(0, 60))
	for dy in range(-3, 3):
		for dx in range(-4, 5):
			var o := world.object_at(cell + Vector2i(dx, dy))
			match o.get("type", ""):
				"workbench":
					stations.append(Items.Station.WORKBENCH)
				"anvil":
					stations.append(Items.Station.ANVIL)
				"campfire":
					stations.append(Items.Station.CAMPFIRE)
	return stations


# =============================================================================
# Relics and the lantern's flare
# =============================================================================

func has_relic(id: String) -> bool:
	return id in relics


## Put on the relic in this inventory slot, if a relic slot is free.
func wear_relic(index: int) -> bool:
	var stack = inventory.get_slot(index)
	if stack == null or Items.kind(stack.id) != Items.Kind.RELIC:
		return false
	if relics.size() >= RELIC_SLOTS:
		Game.toast("Your relic slots are full: take one off first")
		return false
	if has_relic(stack.id):
		return false
	relics.append(stack.id)
	inventory.remove_at(index, 1)
	if level.quests:
		level.quests.event("wear")
	Sfx.play("craft", -4.0, 0.05, 1.3)
	Effects.burst(level.fx_layer, global_position + Vector2(0, -120), "glow", Items.RARITY_COLORS[3])
	Game.toast("%s — worn" % Items.item_name(stack.id), Items.icon(stack.id))
	relics_changed.emit()
	return true


## Take a relic off, back into the pack.
func remove_relic(id: String) -> bool:
	if not has_relic(id) or not inventory.can_fit(id, 1):
		return false
	relics.erase(id)
	inventory.add(id, 1)
	relics_changed.emit()
	return true


## The Flare: the lantern blazes for a moment. The dead burn and reel, the
## living flinch away, cold braziers close by catch, and light-runes in
## the rock answer. Costs glow, so it is a choice, not a reflex.
func flare() -> bool:
	if _flare_cooldown > 0.0 or _dead:
		return false
	if glow < FLARE_COST:
		Game.toast("Not enough light to flare")
		return false
	glow -= FLARE_COST
	glow_changed.emit(glow, max_glow())
	_flare_cooldown = 1.2
	_anim_lock = 0.35
	body.play("cast")
	body.speed_scale = body.clip_length("cast") / 0.5
	var centre := global_position + Vector2(0, -110)
	Effects.burst(level.fx_layer, centre, "glow", Color(1.0, 0.9, 0.6))
	Effects.burst(level.fx_layer, centre, "heal", Color(1.0, 0.85, 0.5))
	level.flare_ring(centre, FLARE_REACH)
	Sfx.play("thunder_far", -10.0, 0.05, 1.8)
	Sfx.play("craft", -2.0, 0.05, 1.6)
	level.shake(4.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_alive():
			continue
		var d: float = enemy.global_position.distance_to(global_position)
		if d > FLARE_REACH:
			continue
		if enemy.is_undead():
			enemy.take_hit(28.0 + (30.0 if enemy.kind == "shade" else 0.0), global_position)
		enemy.velocity = Vector2(signf(enemy.global_position.x - global_position.x) * 900.0, -420.0)
	level.on_flare(centre)
	return true


# =============================================================================
# Animation
# =============================================================================

func _animate(delta: float) -> void:
	# The skeleton animates itself from how the player is moving: strides
	# matched to the ground covered, jumps, falls. Actions are one-shots.
	body.flip_h = facing < 0
	body.motion = velocity
	body.grounded = is_on_floor()
	if _anim_lock > 0.0:
		return
	body.speed_scale = 1.0



# =============================================================================
# Saving
# =============================================================================

func to_dict() -> Dictionary:
	return {
		"position": global_position,
		"health": health,
		"max_health": max_health,
		"glow": glow,
		"lantern_tier": lantern_tier,
		"inventory": inventory.to_array(),
		"hotbar": hotbar_index,
		"spawn": spawn_point,
		"facing": facing,
		"relics": relics.duplicate(),
	}


func from_dict(state: Dictionary) -> void:
	global_position = state.get("position", global_position)
	max_health = state.get("max_health", max_health)
	health = state.get("health", max_health)
	lantern_tier = state.get("lantern_tier", 0)
	glow = state.get("glow", max_glow())
	inventory.from_array(state.get("inventory", []))
	relics.clear()
	for id in state.get("relics", []):
		relics.append(String(id))
	hotbar_index = state.get("hotbar", 0)
	spawn_point = state.get("spawn", global_position)
	facing = state.get("facing", 1)
	_refresh_held()
	health_changed.emit(health, max_health)
	glow_changed.emit(glow, max_glow())

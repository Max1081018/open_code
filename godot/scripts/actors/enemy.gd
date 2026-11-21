class_name Enemy
extends CharacterBody2D
## Every creature, from slimes to the Warden. Behaviour comes from the
## kind's table entry: how it moves, what it is drawn with, what it drops.

signal died_at(position: Vector2)

const TILE := 128.0
const GRAVITY := 2600.0

enum Mode { WALK, HOP, FLY, PHASE, ROOTED, SWIM }

## kind -> definition
const KINDS := {
	"slime": {"frames": "slime_normal", "mode": Mode.HOP, "health": 28, "damage": 7,
		"speed": 300, "scale": 0.95, "loot": [["glowshard", 0.15, 1]]},
	"spike_slime": {"frames": "slime_spike", "mode": Mode.HOP, "health": 60, "damage": 18,
		"speed": 340, "scale": 1.0, "loot": [["iron_ore", 0.4, 2], ["glowshard", 0.2, 1]]},
	"fire_slime": {"frames": "slime_fire", "mode": Mode.HOP, "health": 90, "damage": 26,
		"speed": 380, "scale": 1.05, "loot": [["coal", 0.7, 3], ["ruby", 0.08, 1]], "light": Color(1.0, 0.5, 0.2)},
	"snail": {"frames": "snail", "mode": Mode.WALK, "health": 40, "damage": 8, "speed": 90,
		"scale": 0.95, "loot": [["raw_meat", 0.5, 1]]},
	"mouse": {"frames": "mouse", "mode": Mode.WALK, "health": 22, "damage": 9, "speed": 420,
		"scale": 0.85, "loot": [["raw_meat", 0.6, 1]]},
	"worm": {"frames": "worm_normal", "mode": Mode.WALK, "health": 45, "damage": 14,
		"speed": 160, "scale": 1.0, "loot": [["raw_meat", 0.5, 1], ["copper_ore", 0.3, 3]]},
	"frog": {"frames": "frog", "mode": Mode.HOP, "health": 38, "damage": 12, "speed": 360,
		"scale": 0.95, "loot": [["raw_meat", 0.6, 1]]},
	"bee": {"frames": "bee", "mode": Mode.FLY, "health": 24, "damage": 7, "speed": 260,
		"scale": 0.8, "loot": [["apple", 0.25, 1]]},
	"fly": {"frames": "fly", "mode": Mode.FLY, "health": 34, "damage": 14, "speed": 300,
		"scale": 0.85, "loot": [["glowshard", 0.35, 2]]},
	"ladybug": {"frames": "ladybug", "mode": Mode.WALK, "health": 30, "damage": 9, "speed": 190,
		"scale": 0.85, "loot": [["apple", 0.3, 1]]},
	# Rooted to the cave floor; lobs acid at anything in its line of sight.
	"spitter": {"frames": "barnacle_attack", "mode": Mode.ROOTED, "health": 50, "damage": 12,
		"speed": 0, "scale": 0.95, "loot": [["glowshard", 0.3, 1], ["coal", 0.4, 2]],
		"light": Color(0.5, 1.0, 0.35), "range": 9.0},
	# The Drowned Halls' hunters: they keep to the water and rush swimmers.
	"biter": {"frames": "fish_blue", "mode": Mode.SWIM, "health": 32, "damage": 11, "speed": 420,
		"scale": 0.9, "loot": [["fish", 0.6, 1], ["pearl", 0.12, 1]]},
	"zombie": {"toon": "zombie", "mode": Mode.WALK, "health": 70, "damage": 14, "speed": 210,
		"scale": 0.95, "loot": [["raw_meat", 0.55, 1], ["torch", 0.2, 2]]},
	"robot": {"toon": "robot", "mode": Mode.WALK, "health": 130, "damage": 24, "speed": 250,
		"scale": 1.0, "loot": [["iron_ore", 0.7, 4], ["silver_ore", 0.3, 3]],
		"light": Color(0.5, 0.8, 1.0)},
	"shade": {"toon": "zombie", "mode": Mode.PHASE, "health": 55, "damage": 14, "speed": 230,
		"scale": 0.9, "loot": [["glowshard", 0.8, 2]], "tint": Color(0.22, 0.12, 0.38, 0.82),
		"light_hurts": true},

	"warden": {"toon": "robot", "mode": Mode.WALK, "health": 1400, "damage": 34, "speed": 300,
		"scale": 2.6, "boss": "The Rusted Warden", "tint": Color(1.0, 0.72, 0.62),
		"loot": [["lumen_core", 1.0, 1], ["gold_ore", 1.0, 18], ["heart_crystal", 1.0, 1]],
		"light": Color(1.0, 0.4, 0.3)},
	"gloam": {"toon": "zombie", "mode": Mode.PHASE, "health": 1000, "damage": 28, "speed": 270,
		"scale": 2.3, "boss": "The Gloam", "tint": Color(0.28, 0.16, 0.52, 0.9),
		"loot": [["lumen_core", 1.0, 1], ["glowshard", 1.0, 30], ["emerald", 1.0, 3]],
		"light": Color(0.6, 0.35, 1.0)},
}

var kind := "slime"
var spec: Dictionary
var world: World
var level: Level
var player: Player
var health := 1.0
var max_health := 1.0
var hit_radius := 50.0
var facing := -1
var is_boss := false
var home := Vector2.ZERO

var _sprite  ## AnimatedSprite2D for creatures, CutoutBody for people
var _toon := false
var _hop_timer := 0.0
var _attack_timer := 0.0
var _spit_timer := 1.5   ## spitters: until the next glob
var _spit_tell := 0.0    ## spitters: the gape before it fires
var _hurt_timer := 0.0
var _phase := 0.0
var _dead := false
var _boss_state := 0
var _boss_timer := 2.0


func setup(kind_name: String) -> void:
	kind = kind_name
	spec = KINDS[kind]
	max_health = spec.health
	health = max_health
	is_boss = spec.has("boss")


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 if spec.mode != Mode.PHASE else 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING if spec.mode in [Mode.FLY, Mode.PHASE] \
		else CharacterBody2D.MOTION_MODE_GROUNDED
	_phase = randf() * TAU
	home = global_position

	var s: float = spec.scale
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	if spec.has("toon"):
		_toon = true
		box.size = Vector2(70, 190) * Vector2(s, s)
		shape.position = Vector2(0, -box.size.y * 0.5)
	else:
		# Fitted to the creature's own art, not one box for every kind: a
		# worm is long and low, a snail tall, a bee hangs mid-frame.
		var fit := _art_box()
		box.size = fit.size * s
		shape.position = fit.get_center() * s
	shape.shape = box
	add_child(shape)
	_box = box
	hit_radius = box.size.x * 0.6

	if _toon:
		# People (zombies, robots, shades, the bosses) are jointed rigs.
		if Settings.characters_3d and Body3D.CAST.has(kind):
			_sprite = Body3D.new(kind)
			# Crowds render cheaply; a boss, drawn large, renders sharp.
			_sprite.supersample = Body3D.SUPERSAMPLE * clampf(s, 1.0, 2.2) if is_boss else 1.0
			_sprite.smooth = is_boss
			_sprite.ready.connect(_arm_skeleton)
		else:
			_sprite = CutoutBody.new(spec.toon)
		_sprite.run_speed = float(spec.speed)
	else:
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = _frames()
		_sprite.offset = Vector2(0, -64)
	_sprite.scale = Vector2(s, s)
	_sprite.z_index = 9
	if spec.has("tint"):
		_sprite.modulate = spec.tint
	add_child(_sprite)
	_sprite.play("idle" if _toon else "move")
	if Settings.shadows and spec.mode != Mode.PHASE:
		add_child(SoftShadow.under(self, world, 0.9 * s))

	if spec.has("light"):
		add_child(Glow.make(spec.light, 1.4 * s, true))
		get_child(get_child_count() - 1).position = Vector2(0, -90 * s)
		world.dynamic_lights.append(_own_light)


static var _frame_cache := {}
static var _box_cache := {}
var _box: RectangleShape2D
var _windup := 0.0  ## seconds left before a telegraphed attack lands


## The visible body of the creature's first frame, in sprite-local pixels
## (unscaled): 80% of the drawn width (fins and wings are not body), 90% of
## the height, standing on the same bottom edge.
func _art_box() -> Rect2:
	var key: String = spec.frames
	if _box_cache.has(key):
		return _box_cache[key]
	var frames := _frames()
	var texture := frames.get_frame_texture("move", 0)
	var used := Rect2(32, 58, 64, 70)
	if texture:
		var image := texture.get_image()
		if image:
			if image.is_compressed():
				image.decompress()
			used = Rect2(image.get_used_rect())
	var size := used.size * Vector2(0.8, 0.9)
	var bottom := used.end.y - 128.0  # the art's bottom edge, feet at 0
	var centre_x := used.get_center().x - 64.0
	var box := Rect2(Vector2(centre_x - size.x * 0.5, bottom - size.y), size)
	_box_cache[key] = box
	return box


## The collision box in world space, for hit tests and the debug view.
func body_rect() -> Rect2:
	if _box == null:
		return Rect2(global_position - Vector2(40, 80), Vector2(80, 80))
	var shape: CollisionShape2D = null
	for child in get_children():
		if child is CollisionShape2D:
			shape = child
	var centre := global_position + (shape.position if shape else Vector2.ZERO)
	return Rect2(centre - _box.size * 0.5, _box.size)


## What flashes when struck: a 3D body's rendered picture (a plain
## Node2D's self_modulate would not reach it), else the sprite itself.
func _flash_target() -> CanvasItem:
	return _sprite.picture if _sprite is Body3D else _sprite


## Weapons for the risen dead, and the way they come: out of the ground.
const SKELETON_ARMS := {
	"zombie": ["Skeleton_Axe", ""], "robot": ["Skeleton_Blade", "Skeleton_Shield_Small_A"],
	"shade": ["Skeleton_Blade", ""], "warden": ["Skeleton_Blade", "Skeleton_Shield_Large_A"],
	"gloam": ["Skeleton_Staff", ""],
}


func _arm_skeleton() -> void:
	var arms: Array = SKELETON_ARMS.get(kind, ["", ""])
	_sprite.hold_model(arms[0], arms[1])
	if not is_boss and spec.mode != Mode.PHASE:
		_sprite.play("rise")
		_hurt_timer = 1.1  # still clawing out of the earth: no stride yet


func _frames() -> SpriteFrames:
	if spec.has("toon"):
		return CharacterFrames.build(spec.toon)
	var key: String = spec.frames
	if _frame_cache.has(key):
		return _frame_cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var dir := "res://assets/enemies/"
	var pairs := {
		"move": ["walk_a", "walk_b", "move_a", "move_b", "a", "b", "swim_a", "swim_b", "jump", "idle"],
		"rest": ["rest", "idle", "flat"],
		"dead": ["flat", "rest", "shell"],
	}
	for anim in pairs:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 6.0)
		for suffix in pairs[anim]:
			var path := "%s%s_%s.png" % [dir, key, suffix]
			if ResourceLoader.exists(path):
				frames.add_frame(anim, load(path))
				if anim != "move":
					break
	if frames.get_frame_count("move") == 0:
		frames.add_frame("move", load("%s%s_rest.png" % [dir, key]))
	_frame_cache[key] = frames
	return frames


func _own_light() -> Array:
	if not is_inside_tree() or _dead:
		return []
	var s: float = spec.scale
	return [[(global_position - Vector2(0, 80 * s)) / TILE, 3.0 * s, spec.light * 0.8]]


## The risen dead: what light hurts and the Flare burns.
func is_undead() -> bool:
	return kind in ["zombie", "robot", "shade", "warden", "gloam"]


var _burning := 0.0
var _burn_tick := 0.0


## Set alight (the Ember Heart): a few seconds of fire.
func ignite(seconds := 3.0) -> void:
	if _dead:
		return
	if _burning <= 0.0:
		var fire := Effects.fire(Vector2(0, -80 * float(spec.scale)))
		fire.name = "Burning"
		add_child(fire)
	_burning = maxf(_burning, seconds)


func _update_burning(delta: float) -> void:
	if _burning <= 0.0:
		return
	_burning -= delta
	_burn_tick -= delta
	if _burn_tick <= 0.0:
		_burn_tick = 0.5
		take_hit(4.0, global_position + Vector2(0, -10), false, true)
		Effects.float_text(level.fx_layer, global_position + Vector2(0, -160 * float(spec.scale)), "4", Color(1.0, 0.6, 0.25), 36)
	if _burning <= 0.0 and has_node("Burning"):
		get_node("Burning").queue_free()


func is_alive() -> bool:
	return not _dead


# =============================================================================
# Behaviour
# =============================================================================

func _physics_process(delta: float) -> void:
	if _dead or player == null:
		return
	_attack_timer -= delta
	_hurt_timer -= delta
	_update_burning(delta)
	var to_player := player.global_position - global_position
	var near := to_player.length() < 14.0 * TILE and not player.is_dead()
	if absf(to_player.x) > 20:
		facing = 1 if to_player.x > 0 else -1

	if is_boss:
		_boss_think(delta, to_player)

	match spec.mode:
		Mode.WALK:
			_walk(delta, to_player, near)
		Mode.HOP:
			_hop(delta, to_player, near)
		Mode.FLY, Mode.PHASE:
			_fly(delta, to_player, near)
		Mode.ROOTED:
			_rooted(delta, to_player)
		Mode.SWIM:
			_swim(delta, to_player, near)

	_sprite.flip_h = facing > 0 if not _toon else facing < 0
	if _toon:
		_sprite.motion = velocity / maxf(spec.scale, 0.1)
		_sprite.grounded = is_on_floor() or spec.mode == Mode.PHASE
	_touch_damage()

	# Shades burn in strong light: a torch line is a wall to them.
	if spec.get("light_hurts", false) and world.brightness_at(global_position - Vector2(0, 80)) > 0.55 \
			and not is_boss:
		take_hit(40.0 * delta, global_position + Vector2(0, -10), false, true)


func _walk(delta: float, to_player: Vector2, near: bool) -> void:
	var speed: float = spec.speed * (1.0 if near else 0.35)
	var direction := float(facing) if near else sin(Time.get_ticks_msec() / 2000.0 + _phase)
	if _hurt_timer > 0.0:
		direction = 0.0
	velocity.x = move_toward(velocity.x, direction * speed, 1800.0 * delta)
	velocity.y = minf(velocity.y + GRAVITY * delta, 1800.0)
	if is_on_floor() and is_on_wall() and near:
		velocity.y = -980.0 * (1.2 if is_boss else 1.0)
	move_and_slide()
	if _toon:
		var clip := "walk" if absf(velocity.x) > 30 else "idle"
		if not is_on_floor():
			clip = "jump" if velocity.y < 0 else "fall"
		if _attack_timer > 0.4:
			clip = "attack"
		_play(clip)


func _hop(delta: float, to_player: Vector2, near: bool) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, 1800.0)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 3000.0 * delta)
		_hop_timer -= delta
		_play("rest")
		if _hop_timer <= 0.0 and _hurt_timer <= 0.0:
			_hop_timer = randf_range(0.7, 1.4) if near else randf_range(1.6, 3.0)
			var direction := float(facing) if near else (1.0 if randf() < 0.5 else -1.0)
			velocity = Vector2(direction * spec.speed, -randf_range(780, 1050))
			_squash(Vector2(1.2, 0.8))
	else:
		_play("move")
	move_and_slide()


func _fly(delta: float, to_player: Vector2, near: bool) -> void:
	var target := to_player + Vector2(0, -60) if near else Vector2(sin(_phase) * 300, cos(_phase * 0.7) * 120)
	_phase += delta
	var desired := target.normalized() * float(spec.speed)
	desired.y += sin(Time.get_ticks_msec() / 260.0 + _phase) * 90.0
	if _hurt_timer > 0.0:
		desired *= 0.2
	velocity = velocity.lerp(desired, 3.0 * delta)
	if spec.mode == Mode.PHASE:
		global_position += velocity * delta
	else:
		move_and_slide()
	_play("walk" if _toon else "move")


## A spitter stays put. It gapes (a tell, with a gurgle), then lobs a
## glob of acid on an arc to where the player stands, if it can see them.
func _rooted(delta: float, to_player: Vector2) -> void:
	velocity.x = 0.0
	velocity.y = minf(velocity.y + GRAVITY * delta, 1800.0)
	move_and_slide()
	var mouth := global_position + Vector2(0, -70 * float(spec.scale))
	if _spit_tell > 0.0:
		_spit_tell -= delta
		if _spit_tell <= 0.0:
			_play("rest")
			_squash(Vector2(0.8, 1.25))
			Sfx.play("swing", -6.0, 0.1, 0.7)
			var target := player.global_position + Vector2(0, -90)
			var flight := clampf(mouth.distance_to(target) / 950.0, 0.45, 1.1)
			Spit.lob(level, mouth, target, spec.damage, flight)
		return
	_spit_timer -= delta
	if _spit_timer > 0.0 or player.is_dead() or _hurt_timer > 0.0:
		_play("rest")
		return
	if to_player.length() < float(spec.get("range", 9.0)) * TILE and can_see(player.global_position + Vector2(0, -90)):
		_spit_timer = randf_range(1.8, 2.6)
		_spit_tell = 0.45
		_play("move")  # the jaws work
		_squash(Vector2(1.2, 0.85))
		Sfx.play("growl", -12.0, 0.1, 1.5)
	else:
		_spit_timer = 0.4


## A biter swims only in water. A swimmer close by is rushed; otherwise it
## drifts and turns. Stranded on dry ground it flops, helpless.
func _swim(delta: float, to_player: Vector2, near: bool) -> void:
	var here := World.cell_of(global_position + Vector2(0, -40))
	var wet := level.data.get_liquid(here.x, here.y) == WorldData.WATER
	if not wet:
		velocity.y = minf(velocity.y + GRAVITY * delta, 1600.0)
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		move_and_slide()
		_play("rest")
		return
	var player_cell := World.cell_of(player.global_position + Vector2(0, -90))
	var hunting := near and to_player.length() < 9.0 * TILE \
		and level.data.get_liquid(player_cell.x, player_cell.y) == WorldData.WATER
	var desired: Vector2
	if hunting:
		desired = (to_player + Vector2(0, -80)).normalized() * float(spec.speed)
	else:
		_phase += delta
		desired = Vector2(cos(_phase * 0.6) * 160.0, sin(_phase * 1.3) * 60.0)
	if _hurt_timer > 0.0:
		desired *= 0.2
	velocity = velocity.lerp(desired, 2.5 * delta)
	# Never swim up out of the water.
	# (Looking more than half a tile up, so it turns before breaking the surface.)
	var above := World.cell_of(global_position + Vector2(0, -40 - 80))
	if velocity.y < 0.0 and level.data.get_liquid(above.x, above.y) != WorldData.WATER:
		velocity.y = 60.0
	move_and_slide()
	if absf(velocity.x) > 20.0:
		facing = 1 if velocity.x > 0 else -1
	_play("move")


## Nothing solid between this creature's mouth and `point`.
func can_see(point: Vector2) -> bool:
	var from := global_position + Vector2(0, -70 * float(spec.scale))
	var steps := int(from.distance_to(point) / 40.0)
	for i in range(1, steps):
		var cell := World.cell_of(from.lerp(point, float(i) / steps))
		if level.data.is_solid(cell.x, cell.y):
			return false
	return true


func _play(clip: String) -> void:
	if _toon:
		# The rig picks walking, jumping and falling from motion itself.
		if clip in ["attack", "death", "hurt"] and _sprite.animation != clip:
			_sprite.play(clip)
		return
	if _sprite.animation != clip and _sprite.sprite_frames.has_animation(clip):
		_sprite.play(clip)


func _squash(amount: Vector2) -> void:
	var s: float = spec.scale
	_sprite.scale = amount * s
	create_tween().tween_property(_sprite, "scale", Vector2(s, s), 0.25).set_trans(Tween.TRANS_BACK)


func _touch_damage() -> void:
	var s: float = spec.scale
	var reach := hit_radius + 50.0
	var centre := global_position + Vector2(0, -40 * s)
	var close := player.global_position.distance_to(centre) < reach + 30 * s or \
			(player.global_position + Vector2(0, -100)).distance_to(centre) < reach
	if _windup > 0.0:
		# The blow lands at the end of the wind-up, and only if the player
		# is still there: the tell is a real chance to get out of the way.
		_windup -= get_physics_process_delta_time()
		if _windup <= 0.0:
			_lunge()
			if close or player.global_position.distance_to(centre) < reach + 70 * s:
				player.hurt(spec.damage, global_position)
			_attack_timer = 0.9
		return
	if _attack_timer > 0.0 or not close:
		return
	_begin_windup()


## The tell: a crouch, a flash, a lean back. Bosses have their own.
func _begin_windup() -> void:
	_windup = 0.12 if is_boss else 0.32
	if _toon:
		_play("attack")
		# The tell is heard as well as seen: a snarl before the blow.
		if randf() < 0.6:
			Sfx.play("growl2" if randf() < 0.5 else "growl", -7.0, 0.12)
	var s: float = spec.scale
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(s * 1.12, s * 0.86), _windup * 0.8) \
		.set_trans(Tween.TRANS_SINE)
	_flash_target().self_modulate = Color(1.6, 1.25, 1.25)
	tween.parallel().tween_property(_flash_target(), "self_modulate", Color.WHITE, _windup)


## The strike after the tell: a short lunge toward the player.
func _lunge() -> void:
	var s: float = spec.scale
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(s * 0.9, s * 1.12), 0.06)
	tween.tween_property(_sprite, "scale", Vector2(s, s), 0.18).set_trans(Tween.TRANS_BACK)
	if spec.mode != Mode.PHASE:
		velocity.x += facing * 420.0


# =============================================================================
# Bosses
# =============================================================================

## Bosses fight in three phases (above two thirds of their health, above
## one third, and the last stand), and every move has a tell: a taunt, a
## crouch, a glow. The player learns them, and the fight gets harder as
## it goes on rather than only longer.
var boss_phase := 1
var _move := 0
var _charging := 0.0
var _spinning := 0.0
var _rocks := 0.0


func _boss_think(delta: float, to_player: Vector2) -> void:
	_boss_timer -= delta
	var phase := 1 if health > max_health * 0.66 else (2 if health > max_health * 0.33 else 3)
	if phase > boss_phase:
		boss_phase = phase
		level.boss_phase(self)
		_play("taunt")
		_boss_timer = 1.4
		var minion := "robot" if kind == "warden" else "shade"
		for i in 2 + phase - 2:
			level.spawn_enemy(minion, global_position + Vector2(randf_range(-500, 500), -120))
	_update_boss_hazards(delta, to_player)
	if _boss_timer > 0.0 or _charging > 0.0 or _spinning > 0.0:
		return
	var quick := 0.8 if boss_phase == 3 else 1.0
	match kind:
		"warden":
			_move = (_move + 1) % 3
			match _move:
				0:
					_boss_timer = 3.2 * quick
					_warden_slam(to_player)
				1:
					_boss_timer = 3.0 * quick
					_warden_charge(to_player)
				2:
					_boss_timer = 3.0 * quick
					_warden_spin()
		"gloam":
			_move = (_move + 1) % 3
			match _move:
				0:
					# Swoop: a fast dive through the player, then away.
					_boss_timer = 2.4 * quick
					velocity = to_player.normalized() * 1500.0
					Sfx.play("roar", -4.0)
				1:
					_boss_timer = 2.6 * quick
					_gloam_volley()
				2:
					_boss_timer = 2.2 * quick
					_gloam_blink()


## Leap and slam: the shockwave rolls along the ground, outward, and only a
## jump clears it. In the last stand it rolls both ways and the roof falls.
func _warden_slam(to_player: Vector2) -> void:
	if not is_on_floor():
		return
	_play("taunt")
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree() or _dead:
		return
	velocity = Vector2(signf(to_player.x) * 700.0, -1500.0)
	await get_tree().create_timer(0.25).timeout
	while is_inside_tree() and not is_on_floor():
		await get_tree().physics_frame
	if not is_inside_tree() or _dead:
		return
	level.shake(22.0)
	Sfx.play("break", 2.0)
	Sfx.play("bodyfall", 0.0, 0.05, 0.6)
	for direction in ([-1.0, 1.0] if boss_phase >= 2 else [signf(to_player.x)]):
		_shockwave(global_position, direction)
	if boss_phase == 3:
		_rocks = 2.5


## A wave of dust rolling along the ground; it hurts whoever is standing
## in its way when it passes.
func _shockwave(origin: Vector2, direction: float) -> void:
	var travelled := 0.0
	var hit := false
	while travelled < 9.0 * TILE and is_inside_tree():
		travelled += 26.0
		var at := origin + Vector2(direction * travelled, -10)
		if int(travelled) % 104 < 26:
			Effects.burst(level.fx_layer, at, "smoke", Color(0.8, 0.7, 0.6))
		if not hit and absf(player.global_position.x - at.x) < 60.0 and player.is_on_floor() \
				and absf(player.global_position.y - origin.y) < TILE * 1.5:
			hit = true
			player.hurt(spec.damage * 0.7, at)
		await get_tree().physics_frame


## Shield up, then a rush across the hall. While charging it cannot be hurt
## from the front: get behind it.
func _warden_charge(to_player: Vector2) -> void:
	if _sprite is Body3D:
		_sprite.play("block")
	_flash_target().self_modulate = Color(1.6, 1.1, 1.1)
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree() or _dead:
		return
	_flash_target().self_modulate = Color.WHITE
	facing = 1 if to_player.x > 0 else -1
	_charging = 1.1
	Sfx.play("roar", -2.0, 0.05, 0.8)


func _warden_spin() -> void:
	_play("taunt")
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree() or _dead:
		return
	_spinning = 1.3
	if _sprite is Body3D:
		_sprite.play("spin")
	Sfx.play("swing", 0.0, 0.05, 0.7)


## The Gloam raises its staff and hurls three bolts of violet fire.
func _gloam_volley() -> void:
	if _sprite is Body3D:
		_sprite.play("cast")
	for i in 3 if boss_phase < 3 else 5:
		await get_tree().create_timer(0.28).timeout
		if not is_inside_tree() or _dead or player == null:
			return
		var mouth := global_position + Vector2(0, -170 * float(spec.scale))
		var aim := player.global_position + Vector2(randf_range(-120, 120), -90)
		var bolt := Spit.lob(level, mouth, aim, spec.damage * 0.5, 0.55)
		bolt.colour = Color(0.72, 0.42, 1.0)
		Sfx.play("swing", -4.0, 0.05, 1.4)


## Gone in a puff of dark, and back behind you.
func _gloam_blink() -> void:
	Effects.burst(level.fx_layer, global_position + Vector2(0, -120), "smoke", Color(0.3, 0.15, 0.45))
	var behind := player.global_position + Vector2(-player.facing * 380.0, -260.0)
	global_position = behind
	velocity = Vector2.ZERO
	Effects.burst(level.fx_layer, global_position + Vector2(0, -120), "smoke", Color(0.3, 0.15, 0.45))
	Sfx.play("growl2", -2.0, 0.05, 0.7)
	if boss_phase == 3 and player.glow > 0.0 and level.world.brightness_at(player.global_position - Vector2(0, 100)) < 0.5:
		# The last stand: a pulse of dark that drinks the lantern unless you stand in light.
		player.glow = maxf(player.glow - 15.0, 0.0)
		player.glow_changed.emit(player.glow, player.max_glow())
		Effects.float_text(level.fx_layer, player.global_position + Vector2(0, -250), "The dark drinks your light", Color(0.7, 0.5, 1.0), 34)


func _update_boss_hazards(delta: float, to_player: Vector2) -> void:
	if _charging > 0.0:
		_charging -= delta
		velocity.x = facing * 1150.0
		if absf(to_player.x) < 120.0 * float(spec.scale) and absf(to_player.y) < 200.0 * float(spec.scale):
			player.hurt(spec.damage, global_position)
			_charging = 0.0
		if is_on_wall():
			_charging = 0.0
			level.shake(10.0)
	if _spinning > 0.0:
		_spinning -= delta
		velocity.x = signf(to_player.x) * 260.0
		if to_player.length() < 2.6 * TILE:
			player.hurt(spec.damage * 0.6, global_position)
	if _rocks > 0.0:
		_rocks -= delta
		if randf() < delta * 5.0:
			var above := player.global_position + Vector2(randf_range(-600, 600), -900)
			var rock := Spit.lob(level, above, above + Vector2(randf_range(-40, 40), 900), spec.damage * 0.4, 0.75)
			rock.colour = Color(0.55, 0.46, 0.4)


## Charging, the Warden's raised shield takes blows from the front.
func shielded_from(from: Vector2) -> bool:
	return kind == "warden" and _charging > 0.0 and signf(from.x - global_position.x) == float(facing)


# =============================================================================
# Damage
# =============================================================================

func take_hit(amount: float, from: Vector2, crit := false, quiet := false) -> void:
	if _dead:
		return
	if is_boss and shielded_from(from):
		Sfx.play("anvil", -6.0, 0.05, 1.3)
		Effects.burst(level.fx_layer, global_position + Vector2(facing * 90, -200), "hit")
		Effects.float_text(level.fx_layer, global_position + Vector2(0, -330), "Blocked!", Color(0.8, 0.85, 1.0), 40)
		return
	health -= amount
	if not quiet:
		_hurt_timer = 0.25
		var push := 1.0 if not is_boss else 0.15
		velocity = Vector2(signf(global_position.x - from.x) * 520.0 * push, -360.0 * push)
		Sfx.play("hit")
		if _toon and randf() < 0.45:
			Sfx.play("growl", -9.0, 0.15)  # a grunt of pain, not every blow
		var s: float = spec.scale
		Effects.burst(level.fx_layer, global_position + Vector2(0, -60 * s), "hit")
		Effects.float_text(level.fx_layer, global_position + Vector2(0, -150 * s),
			("%d!" if crit else "%d") % int(amount), UITheme.GOLD if crit else Color.WHITE,
			64 if crit else 50)
		level.shake(5.0 if crit else 3.0)
		var tween := create_tween()
		_flash_target().self_modulate = Color(3, 3, 3)
		tween.tween_property(_flash_target(), "self_modulate", Color.WHITE, 0.15)
		# The blow lands on the body: squashed against it, then springing back.
		_squash(Vector2(1.25, 0.78) if not is_boss else Vector2(1.08, 0.94))
	if health <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	collision_layer = 0
	remove_from_group("enemies")
	Sfx.play("break" if not _toon else "growl2", -2.0, 0.1)
	if _toon:
		Sfx.play("bodyfall", -3.0, 0.1)
	var s: float = spec.scale
	Effects.burst(level.fx_layer, global_position + Vector2(0, -60 * s), "smoke",
		spec.get("tint", Color(0.9, 0.9, 0.9)))
	if get_meta("tide", false):
		level.spawn_drop("glowshard", randi_range(1, 2), global_position + Vector2(0, -80))
	for drop in spec.loot:
		var chance: float = drop[1] * (2.0 if player and player.has_relic("relic_luckstone") else 1.0)
		if randf() < chance:
			level.spawn_drop(drop[0], max(1, randi_range(1, drop[2])), global_position + Vector2(0, -80))
	died_at.emit(global_position)
	if _toon:
		_play("death")
	elif _sprite.sprite_frames.has_animation("dead"):
		_play("dead")
	# The finish: a white flash, a pop of sparks, a short tumble away from
	# the blow, then gone.
	Effects.burst(level.fx_layer, global_position + Vector2(0, -60 * s), "hit")
	Effects.burst(level.fx_layer, global_position + Vector2(0, -60 * s), "glow", Color(1.0, 0.9, 0.7))
	_flash_target().self_modulate = Color(4, 4, 4)
	level.shake(4.0 if not is_boss else 20.0)
	var tween := create_tween()
	tween.tween_property(_flash_target(), "self_modulate", Color.WHITE, 0.15)
	if not _toon:
		var away := signf(global_position.x - player.global_position.x)
		tween.parallel().tween_property(_sprite, "rotation", away * 1.4, 0.5).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "position:y", position.y - 40, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.35)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)

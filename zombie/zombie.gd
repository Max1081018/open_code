extends CharacterBody3D
## One zombie: senses, states, steering and the hooks that tie them to the
## animation machine underneath.
##
## The brain is deliberately small. A zombie stands or shuffles about until it
## sees or hears you, closes on you, swings when it is in reach, flinches when
## it is hit, and goes down for good when it runs out. The interesting part is
## that every one of those is also an animation state, so what you see is what
## the AI is actually doing - there is no separate "animation layer" that can
## drift out of step with it.
##
## Navigation is steering rather than a baked navmesh: the world is generated
## and endless, and baking navigation for it on a phone would cost more than
## the zombies do. They walk at you, feel their way round trees and walls with
## three short rays, and climb the kind of slopes the ground actually has.

const ZChar := preload("res://zchar.gd")

const SIGHT := 30.0               # how far it can see you in the open
const SIGHT_NIGHT := 17.0
const FOV := 2.2                  # radians, total
const HEAR := 55.0                # a gunshot carries
const REACH := 1.75
const ATTACK_DAMAGE := 11.0
const ATTACK_TIME := 0.42         # when in the swing the blow lands
const GRAVITY := 22.0
const STEP := 0.45

var game: Node                    # who to tell about damage and death
var state := "idle"
var health := 100.0
var max_health := 100.0
var speed_walk := 1.0
var speed_chase := 3.0
var is_crawler := false
var alive := true

var body: ZChar
var _target: Vector3              # where it is heading
var _has_target := false
var _t := 0.0                     # time in the current state
var _think := 0.0                 # countdown to the next decision
var _swing := -1.0                # time until the current swing lands
var _yaw := 0.0
var _lost := 0.0                  # how long since it last saw you
var _col: CollisionShape3D
var _shape: CapsuleShape3D
var _dead_t := 0.0
var _far := 0                     # frames to skip while it is far away
var _skip := 0
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
var _moan := 0.0


func setup(g: Node, at: Vector3, seed_v: int, crawler := false) -> void:
	game = g
	_rng.seed = seed_v
	is_crawler = crawler
	_home = at
	global_position = at
	_yaw = _rng.randf() * TAU
	rotation.y = _yaw

	collision_layer = 2          # zombies have a layer of their own, so shots
	collision_mask = 1 | 2       # and the crosshair can pick them out
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.36
	_shape.height = 1.65
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_col.position = Vector3(0, 0.82, 0)
	add_child(_col)

	body = ZChar.new()
	add_child(body)
	body.randomize_look(_rng)

	# A mixed crowd: most shamble, some are quick, a few only crawl.
	var fast := _rng.randf() < 0.22
	speed_walk = _rng.randf_range(0.75, 1.25)
	speed_chase = _rng.randf_range(3.6, 4.6) if fast else _rng.randf_range(2.0, 2.9)
	max_health = 85.0 + _rng.randf() * 45.0
	health = max_health
	if crawler:
		_go_crawler()
	_think = _rng.randf() * 2.0


func _go_crawler() -> void:
	is_crawler = true
	speed_walk *= 0.55
	speed_chase = minf(speed_chase, 1.9)
	_shape.height = 0.7
	_col.position = Vector3(0, 0.35, 0)
	if body:
		body.go_down()


func _physics_process(delta: float) -> void:
	if not alive:
		_rot_dead(delta)
		return
	# Far away: think and animate less often. A hundred zombies in a forest
	# cost about as much as ten nearby ones this way.
	var player: Node3D = game.player if game else null
	var dist := 999.0
	if player:
		dist = global_position.distance_to(player.global_position)
	_far = 0 if dist < 28.0 else (2 if dist < 55.0 else 5)
	if _far > 0:
		_skip += 1
		if _skip <= _far:
			# still fall, so nothing hangs in the air
			if not is_on_floor():
				velocity.y -= GRAVITY * delta
				move_and_slide()
			return
		delta *= float(_skip)
		_skip = 0
	if body:
		body.tick(delta)
		body._tree.active = dist < 70.0

	_t += delta
	_think -= delta
	_decide(delta, player, dist)
	_move(delta)


## The state machine proper: what it wants to be doing right now.
func _decide(delta: float, player: Node3D, dist: float) -> void:
	var sees := _can_see(player, dist)
	if sees:
		_lost = 0.0
	else:
		_lost += delta

	match state:
		"idle", "wander":
			if sees:
				_enter("alert")
			elif _think <= 0.0:
				_think = _rng.randf_range(2.5, 6.0)
				if state == "idle" and _rng.randf() < 0.55:
					_enter("wander")
					var a := _rng.randf() * TAU
					_target = _home + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 11.0)
					_has_target = true
				else:
					_enter("idle")
					_has_target = false
		"alert":
			# A moment of noticing you before it comes.
			_has_target = false
			if _t > 0.45:
				_enter("chase")
			if player:
				_face(player.global_position, delta * 4.0)
		"chase":
			if player == null:
				_enter("idle")
			else:
				_target = player.global_position
				_has_target = true
				if dist < REACH:
					_enter("attack")
				elif _lost > 6.0:
					_home = global_position
					_enter("wander")
		"attack":
			_has_target = false
			if player:
				_face(player.global_position, delta * 6.0)
			if _swing > 0.0:
				_swing -= delta
				if _swing <= 0.0 and player and global_position.distance_to(player.global_position) < REACH + 0.5:
					if game and game.has_method("zombie_hit_player"):
						game.zombie_hit_player(ATTACK_DAMAGE * (0.7 if is_crawler else 1.0), self)
			if not body.busy():
				if player and global_position.distance_to(player.global_position) < REACH + 0.3:
					_swing_now()
				else:
					_enter("chase")
		"stagger":
			_has_target = false
			if not body.busy():
				_enter("chase" if _lost < 4.0 else "wander")
		"getup":
			_has_target = false
			if not body.busy():
				_enter("chase")

	# A groan now and then, more often once it has seen you.
	_moan -= delta
	if _moan <= 0.0:
		_moan = _rng.randf_range(4.0, 11.0) * (0.5 if state in ["chase", "attack"] else 1.0)
		if game and game.has_method("zombie_moan") and dist < 34.0:
			game.zombie_moan(global_position, state in ["chase", "attack"])


func _enter(s: String) -> void:
	if state == s:
		return
	state = s
	_t = 0.0
	if s == "attack":
		_swing_now()


func _swing_now() -> void:
	if body.act("bite" if is_crawler else "attack"):
		_swing = ATTACK_TIME


## Sight: close enough, roughly in front, and nothing solid in the way.
func _can_see(player: Node3D, dist: float) -> bool:
	if player == null or not alive:
		return false
	var range_now: float = SIGHT
	if game and game.has_method("is_night") and game.is_night():
		range_now = SIGHT_NIGHT
	if state in ["chase", "attack", "alert"]:
		range_now *= 1.6               # once roused it keeps track of you
	if dist > range_now:
		return false
	var to := player.global_position - global_position
	if dist > 2.0 and state not in ["chase", "attack"]:
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		if fwd.dot(Vector3(to.x, 0, to.z).normalized()) < cos(FOV * 0.5):
			return false
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.3, 0), player.global_position + Vector3(0, 1.0, 0))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == player


## A gunshot, a smashed window, a shout: come and look.
func hear(at: Vector3, loud: float) -> void:
	if not alive:
		return
	if global_position.distance_to(at) > HEAR * loud:
		return
	if state in ["idle", "wander"]:
		_target = at
		_has_target = true
		_enter("chase")
		_lost = 3.0           # it is coming to the noise, not to you


func _move(delta: float) -> void:
	var want := Vector3.ZERO
	if _has_target:
		var to := _target - global_position
		to.y = 0.0
		if to.length() > (0.8 if state == "chase" else 1.2):
			var dir := _steer(to.normalized())
			var sp: float = speed_chase if state == "chase" else speed_walk
			want = dir * sp
			_face(global_position + dir, delta * (7.0 if state == "chase" else 3.0))
		elif state == "wander":
			_enter("idle")
	velocity.x = move_toward(velocity.x, want.x, 9.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 9.0 * delta)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -2.0
	else:
		velocity.y -= GRAVITY * delta
	body.speed = Vector2(velocity.x, velocity.z).length()
	move_and_slide()
	# Shuffle up kerbs and roots rather than sticking on them.
	if is_on_wall() and want.length() > 0.2:
		var ahead := want.normalized() * 0.3
		var up := Vector3(0, STEP, 0)
		var t := global_transform
		if test_move(t, ahead) and not test_move(t, up) and not test_move(t.translated(up), ahead):
			global_position += up + ahead * 0.5


## Three short rays: straight ahead and a little to each side. If the way is
## blocked it slides along whichever side is open, which is enough to get a
## shambling thing round a tree or along a wall.
func _steer(dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.9, 0)
	var probe := func(d: Vector3) -> bool:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * 1.5)
		q.exclude = [get_rid()]
		q.collision_mask = 1
		return not space.intersect_ray(q).is_empty()
	if not probe.call(dir):
		return dir
	var left := dir.rotated(Vector3.UP, 0.9)
	var right := dir.rotated(Vector3.UP, -0.9)
	var l: bool = probe.call(left)
	var r: bool = probe.call(right)
	if not l and r:
		return left
	if not r and l:
		return right
	if not l and not r:
		return left if (int(get_instance_id()) % 2 == 0) else right
	return dir.rotated(Vector3.UP, PI * 0.5)


func _face(at: Vector3, amount: float) -> void:
	var to := at - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), clampf(amount, 0.0, 1.0))
	rotation.y = _yaw


## Taking a hit. A shot to the head is worth three to the body; enough damage
## to the legs puts it on its belly instead of killing it outright.
func take_damage(amount: float, where: String, from: Vector3) -> void:
	if not alive:
		return
	var mult := 1.0
	match where:
		"head": mult = 3.2
		"leg": mult = 0.65
	health -= amount * mult
	body.flash()
	if game and game.has_method("zombie_hurt"):
		game.zombie_hurt(self, where, amount * mult)
	if health <= 0.0:
		_die()
		return
	if where == "leg" and not is_crawler and health < max_health * 0.55 and randf() < 0.5:
		_go_crawler()
		_enter("chase")
		return
	# Heavy hits break the swing and rock it back.
	if amount * mult > 16.0 or randf() < 0.3:
		body.act("stagger" if amount * mult > 26.0 else "hit", true)
		_enter("stagger")
		var push := (global_position - from)
		push.y = 0.0
		if push.length() > 0.01:
			velocity += push.normalized() * minf(amount * 0.06, 2.2)
	if state in ["idle", "wander"]:
		_enter("chase")
		_target = from
		_has_target = true


func _die() -> void:
	alive = false
	state = "dead"
	_has_target = false
	velocity = Vector3.ZERO
	body.die()
	_col.disabled = true
	collision_layer = 0
	collision_mask = 0
	if game and game.has_method("zombie_died"):
		game.zombie_died(self)


## Bodies lie where they fall for a while, then sink quietly into the ground
## so a long fight doesn't leave a hundred corpses to draw.
func _rot_dead(delta: float) -> void:
	_dead_t += delta
	if body:
		body.tick(delta)
		if body._tree:
			body._tree.active = _dead_t < 3.0
	if _dead_t > 28.0:
		position.y -= delta * 0.25
		if _dead_t > 34.0:
			queue_free()

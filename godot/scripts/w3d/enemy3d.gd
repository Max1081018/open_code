class_name Enemy3D
extends CharacterBody3D
## A foe in the open world, on the shared humanoid rig. Wanders until it
## notices the player, then chases, circles in and strikes with a visible
## wind-up; the blow only lands if the player is still in front and in reach
## when it falls (so dodging and blocking work). Flinches, staggers and is
## knocked back when hit; dies with its animation and drops loot.
## The Warden is a boss: three phases (sword combos, then charges, then
## slams that call the dead).

signal died(enemy: Enemy3D)

const SPECS := {
	"zombie": {"model": "zombie", "health": 45.0, "speed": 2.4, "damage": 9.0, "reach": 1.7, "windup": 0.55,
		"idle": "Zombie_Idle", "walk": "Zombie_Walk_Fwd", "run": "Zombie_Walk_Fwd", "attack": ["Zombie_Scratch"],
		"loot": [["coal", 0.5, 2], ["glowshard", 0.25, 1], ["gold_coin", 0.3, 2]], "sight": 18.0},
	"robot": {"model": "robot", "health": 80.0, "speed": 3.6, "damage": 14.0, "reach": 2.1, "windup": 0.45,
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Regular_A", "Sword_Regular_B", "Sword_Attack"],
		"weapon": "iron_sword", "shield": "wood_shield",
		"loot": [["iron_ore", 0.6, 3], ["gold_coin", 0.6, 4]], "sight": 22.0},
	"shade": {"model": "shade", "health": 38.0, "speed": 4.6, "damage": 11.0, "reach": 1.9, "windup": 0.35,
		"idle": "Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Regular_A", "Sword_Regular_C"],
		"weapon": "silver_sword", "loot": [["glowshard", 0.7, 2]], "sight": 24.0},
	"warden": {"model": "warden", "health": 900.0, "speed": 3.2, "damage": 24.0, "reach": 3.0, "windup": 0.6,
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C"],
		"heavy": "Sword_Heavy_Combo", "weapon": "gold_sword", "shield": "iron_shield", "scale": 1.55, "boss": "The Rusted Warden",
		"loot": [["heart_crystal", 1.0, 1], ["lumen_core", 1.0, 1], ["gold_coin", 1.0, 25]], "sight": 30.0},
}

## Region foes. "style": melee (the default), ranged (keeps its distance and
## throws bolts), slam (a full-circle blow round itself), charge (dashes in).
## "element": the colour of its magic, sparks and telegraphs.
const ZONE_SPECS := {
	"thornling": {"model": "thornling", "health": 55.0, "speed": 4.4, "damage": 10.0, "reach": 1.8, "windup": 0.4,
		"style": "charge", "element": Color(0.5, 0.9, 0.4), "name": "Thornling",
		"idle": "Zombie_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Zombie_Scratch", "Punch_Jab"],
		"loot": [["wood", 0.6, 3], ["glowshard", 0.3, 1]], "sight": 20.0},
	"wisp_caller": {"model": "wisp_caller", "health": 50.0, "speed": 3.0, "damage": 12.0, "reach": 11.0, "windup": 0.8,
		"style": "ranged", "element": Color(0.35, 1.0, 0.9), "name": "Wisp Caller",
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"loot": [["glowshard", 0.7, 2], ["gold_coin", 0.4, 3]], "sight": 24.0},
	"frost_knight": {"model": "frost_knight", "health": 160.0, "speed": 2.6, "damage": 22.0, "reach": 3.4, "windup": 0.9,
		"style": "slam", "element": Color(0.6, 0.85, 1.0), "name": "Frost Knight",
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Heavy_Combo"],
		"weapon": "iron_hammer", "loot": [["iron_ore", 0.8, 4], ["silver_ore", 0.5, 3], ["gold_coin", 0.7, 5]], "sight": 22.0},
	"rime_shade": {"model": "rime_shade", "health": 60.0, "speed": 3.4, "damage": 13.0, "reach": 12.0, "windup": 0.7,
		"style": "ranged", "element": Color(0.7, 0.9, 1.0), "name": "Rime Shade",
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"loot": [["glowshard", 0.6, 2], ["silver_ore", 0.4, 2]], "sight": 26.0},
	"dune_raider": {"model": "dune_raider", "health": 110.0, "speed": 3.8, "damage": 16.0, "reach": 2.2, "windup": 0.45,
		"style": "charge", "element": Color(1.0, 0.82, 0.45), "name": "Dune Raider",
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Regular_A", "Sword_Regular_B"],
		"weapon": "copper_sword", "loot": [["copper_ore", 0.7, 4], ["gold_coin", 0.7, 5]], "sight": 24.0},
	"sand_thrower": {"model": "sand_thrower", "health": 48.0, "speed": 3.2, "damage": 11.0, "reach": 12.0, "windup": 0.65,
		"style": "ranged", "element": Color(1.0, 0.75, 0.4), "name": "Sand Thrower",
		"idle": "Zombie_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["OverhandThrow"],
		"loot": [["stone", 0.8, 4], ["gold_coin", 0.5, 3]], "sight": 24.0},
	"cinder_knight": {"model": "cinder_knight", "health": 190.0, "speed": 2.5, "damage": 26.0, "reach": 3.6, "windup": 0.95,
		"style": "slam", "element": Color(1.0, 0.45, 0.12), "name": "Cinder Knight",
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Heavy_Combo"],
		"weapon": "gold_sword", "loot": [["gold_ore", 0.7, 4], ["ruby", 0.3, 1], ["gold_coin", 0.8, 6]], "sight": 22.0},
	"ember_caller": {"model": "ember_caller", "health": 58.0, "speed": 3.0, "damage": 15.0, "reach": 12.0, "windup": 0.75,
		"style": "ranged", "element": Color(1.0, 0.5, 0.15), "name": "Ember Caller",
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"loot": [["coal", 0.8, 3], ["ruby", 0.2, 1]], "sight": 26.0},
	"void_shade": {"model": "void_shade", "health": 70.0, "speed": 4.8, "damage": 14.0, "reach": 2.0, "windup": 0.35,
		"style": "charge", "element": Color(0.7, 0.4, 1.0), "name": "Void Shade",
		"idle": "Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Regular_A", "Sword_Regular_C"],
		"weapon": "silver_sword", "loot": [["glowshard", 0.8, 2], ["emerald", 0.15, 1]], "sight": 26.0},
	"void_caller": {"model": "void_caller", "health": 62.0, "speed": 3.0, "damage": 16.0, "reach": 12.0, "windup": 0.7,
		"style": "ranged", "element": Color(0.75, 0.4, 1.0), "name": "Void Caller",
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"loot": [["glowshard", 0.8, 3], ["gold_coin", 0.5, 4]], "sight": 26.0},
}

var kind := "zombie"
var spec: Dictionary
var game: Node
var health := 1.0
var max_health := 1.0
var model: Node3D
var anim: AnimationPlayer
var phase := 1
var is_boss := false
var dead := false

var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _nav := {}            ## path cache for NavField.path_dir
var _aggro := false
var _attack_timer := 0.0     ## time to the blow landing (wind-up)
var _cooldown := 0.0
var _stagger := 0.0
var _clip := ""
var _flash: StandardMaterial3D
var _flash_time := 0.0
var _strafe := 1.0
var _charge := 0.0
var _style := "melee"
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_time := 0.0


func setup(the_kind: String, the_game: Node) -> void:
	kind = the_kind
	game = the_game
	spec = SPECS[kind] if SPECS.has(kind) else ZONE_SPECS[kind]
	_style = spec.get("style", "melee")
	max_health = spec.health
	health = max_health
	is_boss = spec.has("boss")


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 2
	var s: float = spec.get("scale", 1.0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35 * s
	capsule.height = 1.75 * s
	shape.shape = capsule
	shape.position = Vector3(0, 0.875 * s, 0)
	add_child(shape)
	model = CharacterKit.build(spec.model)
	model.scale = Vector3.ONE * s
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	for clip in [spec.idle, spec.walk, spec.run]:
		if anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	if spec.has("weapon"):
		var hand := HumanoidGrip.grip(skeleton, model, "RightHand", "RightIndexProximal", "RightLittleProximal", "RightMiddleProximal")
		var w := Body3D.item_model(spec.weapon)
		if w:
			hand.add_child(w)
	if spec.has("shield"):
		var off := HumanoidGrip.grip(skeleton, model, "LeftHand", "LeftIndexProximal", "LeftLittleProximal", "LeftMiddleProximal")
		var sh := Body3D.item_model(spec.shield)
		if sh:
			off.add_child(sh)
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.albedo_color = Color(1.0, 0.25, 0.2, 0.0)
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = _flash
		(m as MeshInstance3D).extra_cull_margin = 2.0
	_home = global_position
	_wander_target = _home
	_play(spec.idle)
	if not is_boss:
		_build_bar()
	if spec.has("element"):
		# A faint glow of its element on it.
		var l := OmniLight3D.new()
		l.light_color = spec.element
		l.light_energy = 0.6
		l.omni_range = 3.0
		l.shadow_enabled = false
		l.position = Vector3(0, 1.2, 0)
		add_child(l)


## A slim health bar over its head, shown for a while after it is struck.
func _build_bar() -> void:
	_bar = Node3D.new()
	add_child(_bar)
	_bar.position = Vector3(0, 2.15 * float(spec.get("scale", 1.0)) * float(model.get_meta("style", {}).get("height", 1.8)) / 1.8, 0)
	for k in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 0.08) if k == 0 else Vector2(0.86, 0.05)
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.04, 0.03, 0.08, 0.7) if k == 0 else Color(0.92, 0.32, 0.36)
		m.render_priority = k
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bar.add_child(q)
		if k == 1:
			_bar_fill = q
	_bar.visible = false


func _physics_process(delta: float) -> void:
	_flash_time -= delta
	if _bar:
		_bar_time -= delta
		_bar.visible = _bar_time > 0.0 and not dead
		if _bar.visible:
			var f := clampf(health / max_health, 0.0, 1.0)
			_bar_fill.scale.x = maxf(f, 0.001)
			_bar_fill.position.x = 0.0
	_flash.albedo_color.a = clampf(_flash_time * 4.0, 0.0, 0.55)
	if dead:
		velocity.y -= 22.0 * delta
		velocity.x *= 0.9
		velocity.z *= 0.9
		move_and_slide()
		return
	var player: Player3D = game.player
	var to_player := player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()
	var sight: float = spec.sight
	if not _aggro and dist < sight and player.health > 0.0:
		_aggro = true
		if is_boss:
			game.boss_started(self)
	if _aggro and dist > sight * 2.2:
		_aggro = false
	_cooldown -= delta
	_stagger -= delta
	var wish := Vector3.ZERO
	var speed: float = spec.speed

	if _stagger > 0.0:
		pass
	elif _attack_timer > 0.0:
		# Winding up: face the player, then the blow lands.
		_attack_timer -= delta
		_face(to_player, delta, 6.0)
		if _tele:
			(_tele.material_override as ShaderMaterial).set_shader_parameter("fill", 1.0 - _attack_timer / float(spec.windup))
		if _attack_timer <= 0.0:
			_land_blow(player)
			_end_telegraph(true)
	elif _charge > 0.0:
		# Lunging along the way it faces (the model looks down +Z), turning
		# a little toward her; the blow lands when it reaches her.
		_charge -= delta
		_face(to_player, delta, 2.5)
		wish = model.global_transform.basis.z
		wish.y = 0.0
		wish = wish.normalized()
		speed = spec.speed * 3.2
		if dist < float(spec.reach) * 1.2:
			_charge = 0.0
			_end_telegraph(true)
			_land_blow(player)
		elif _charge <= 0.0:
			_end_telegraph(false)
	elif _aggro and _style == "ranged":
		# Keep a casting distance: back off when crowded, close when far.
		var want := float(spec.reach) * 0.65
		if dist < float(spec.reach) and dist > 3.0 and _cooldown <= 0.0:
			_begin_attack()
		elif dist < want * 0.6:
			wish = -to_player.normalized()
			speed *= 0.8
		elif dist > want:
			wish = _toward(player.global_position, to_player)
		else:
			wish = to_player.normalized().cross(Vector3.UP) * _strafe
			speed *= 0.45
			if randf() < 0.01:
				_strafe = -_strafe
	elif _aggro and _style == "charge" and dist > 5.0 and dist < 14.0 and _cooldown <= 0.0 and randf() < 0.03:
		# A lunge: a brief crouch (its telegraph), then a dash at her.
		_charge = 0.75
		_cooldown = 2.4
		_play(spec.run, 1.8, true)
		_show_telegraph(true)
	elif _aggro:
		var reach: float = spec.reach
		if dist < reach * 0.95 and _cooldown <= 0.0:
			_begin_attack()
		elif is_boss and phase >= 2 and dist > 7.0 and dist < 18.0 and _cooldown <= 0.0 and randf() < 0.02:
			_charge = 1.1
			_cooldown = 3.0
			_play(spec.run, 1.6, true)
		else:
			wish = _toward(player.global_position, to_player)
			if dist < reach * 1.6:
				# Close: circle a little rather than walking into the blade.
				wish = (wish * 0.3 + wish.cross(Vector3.UP) * _strafe).normalized()
				speed *= 0.5
				if randf() < 0.01:
					_strafe = -_strafe
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(3.0, 7.0)
			_wander_target = _home + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		var to := _wander_target - global_position
		to.y = 0
		if to.length() > 1.0:
			wish = _toward(_wander_target, to)
			speed *= 0.45

	if wish.length() > 0.1 and _charge <= 0.0:
		wish = (wish + _separation()).normalized()
	var horizontal := Vector3(velocity.x, 0, velocity.z).lerp(wish * speed, 1.0 - exp(-8.0 * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y -= 22.0 * delta
	move_and_slide()
	if wish.length() > 0.1 and _attack_timer <= 0.0:
		_face(wish, delta, 8.0)
	if _attack_timer <= 0.0 and _stagger <= 0.0:
		var v := horizontal.length()
		_play(spec.idle if v < 0.3 else (spec.walk if v < 2.6 else spec.run), clampf(v / 3.0, 0.7, 1.5) if v > 0.3 else 1.0)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, want, 1.0 - exp(-rate * delta))


func _begin_attack() -> void:
	var clips: Array = spec.attack
	var clip: String = clips[randi() % clips.size()]
	if is_boss and phase >= 3 and spec.has("heavy") and randf() < 0.4:
		clip = spec.heavy
	_attack_timer = spec.windup
	_cooldown = spec.windup + randf_range(0.9, 1.6) / (1.0 + (phase - 1) * 0.35)
	_play(clip, 1.0, true)
	_show_telegraph()


func _land_blow(player: Player3D) -> void:
	var to := player.global_position - global_position
	to.y = 0
	var facing := model.global_transform.basis.z
	var reach: float = spec.reach * 1.15
	var colour: Color = spec.get("element", Color(1, 0.8, 0.6))
	match _style:
		"ranged":
			_cast_bolt(player, colour)
			return
		"slam":
			# The ground shakes all round it.
			game.ring_burst(global_position, reach, colour)
			if to.length() < reach:
				player.hurt(spec.damage, global_position)
				game.on_player_hit(spec.damage)
			return
	if to.length() < reach and facing.dot(to.normalized()) > 0.35:
		player.hurt(spec.damage, global_position)
		game.on_player_hit(spec.damage)
		if spec.has("element"):
			Arcana.sparks(game, player.global_position + Vector3(0, 1.0, 0), colour, 14, 4.0, 0.08)
	if is_boss and phase >= 3:
		game.boss_slam(self)


## A bolt of its element, aimed where she will be; she can dodge it.
func _cast_bolt(player: Player3D, colour: Color) -> void:
	var from := global_position + Vector3(0, 1.35 * float(spec.get("scale", 1.0)), 0) + model.global_transform.basis.z * 0.6
	var lead := player.velocity * 0.35
	var aim := (player.global_position + Vector3(0, 1.0, 0) + lead - from).normalized()
	var bolt := Arcana.Orb.new()
	bolt.tint = colour
	bolt.speed = 15.0
	bolt.life = 1.6
	bolt.heading = aim
	bolt.ground = game.world.height_at
	var dmg: float = spec.damage
	var src := global_position
	bolt.burst = func(at: Vector3):
		Arcana.sparks(game, at, colour, 22, 5.0, 0.1)
		Arcana.flash(game, at, colour, 2.0, 5.0, 0.25)
		if not game.player.dead and at.distance_to(game.player.global_position + Vector3(0, 1.0, 0)) < 1.4:
			game.player.hurt(dmg, src)
			game.on_player_hit(dmg)
	bolt.hit_target = player
	game.add_child(bolt)
	bolt.global_position = from
	Sfx.play("magic_cast", -12.0, 0.2, 1.15)


## The wedge on the ground that shows a coming blow (reach and arc).
var _tele: MeshInstance3D
static var _tele_shader: Shader


func _show_telegraph(lunge := false) -> void:
	_end_telegraph(false)
	if _tele_shader == null:
		_tele_shader = load("res://scripts/shaders/telegraph.gdshader")
	if _style == "ranged":
		# A caster's tell: light gathering in its hand.
		Arcana.circle(game, global_position, 1.1, spec.get("element", Color.WHITE), float(spec.windup), 1.5)
		return
	var reach: float = float(spec.reach) * 1.15
	if lunge:
		reach = 9.0
	_tele = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(reach * 2.0, reach * 2.0)
	_tele.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = _tele_shader
	m.set_shader_parameter("half_span", PI if _style == "slam" else (0.22 if lunge else acos(0.35)))
	if spec.has("element"):
		m.set_shader_parameter("tint", (spec.element as Color).lerp(Color(1.0, 0.3, 0.15), 0.35))
	_tele.material_override = m
	_tele.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(_tele)
	_tele.scale = Vector3.ONE / maxf(model.scale.x, 0.01)   # the reach is in metres
	_tele.position = Vector3(0, 0.06, 0) / maxf(model.scale.x, 0.01)


func _end_telegraph(landed: bool) -> void:
	if _tele == null:
		return
	var t := _tele
	_tele = null
	if landed:
		var m := t.material_override as ShaderMaterial
		var tw := t.create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("flash", v), 1.0, 0.0, 0.2)
		tw.tween_callback(t.queue_free)
	else:
		t.queue_free()


## Hit by the player. Returns true if it died.
func take_hit(amount: float, from: Vector3, heavy: bool) -> bool:
	if dead:
		return false
	health -= amount
	_flash_time = 0.25
	_bar_time = 4.0
	if spec.has("element") and not is_boss:
		Arcana.sparks(game, global_position + Vector3(0, 1.1, 0), Color(0.85, 0.6, 1.0), 10, 4.0, 0.08)
	var push := global_position - from
	push.y = 0
	velocity += push.normalized() * (7.0 if heavy else 3.5) * (0.35 if is_boss else 1.0)
	_aggro = true
	if not is_boss or heavy:
		_stagger = 0.45 if heavy else 0.25
		_attack_timer = 0.0
		_end_telegraph(false)
		_play("Hit_Chest", 1.2, true)
	if is_boss:
		var ratio := health / max_health
		var new_phase := 1 if ratio > 0.6 else (2 if ratio > 0.3 else 3)
		if new_phase != phase:
			phase = new_phase
			game.boss_phase(self, phase)
	if health <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	_end_telegraph(false)
	dead = true
	collision_layer = 0
	_play("Death01", 1.0, true)
	died.emit(self)
	var t := create_tween()
	t.tween_interval(4.0)
	t.tween_property(self, "position:y", position.y - 1.6, 1.5)
	t.tween_callback(queue_free)


func _play(clip: String, speed := 1.0, restart := false) -> void:
	speed *= float(model.get_meta("style", {}).get("speed", 1.0))
	if not anim.has_animation(clip):
		return
	if clip == _clip and not restart:
		anim.speed_scale = speed
		return
	_clip = clip
	anim.play(clip, 0.15)
	anim.speed_scale = speed
	if restart:
		anim.seek(0.0, true)


## Walk toward `target` along the navmesh when one is baked here (round
## trees and boulders, not into lakes); straight otherwise.
func _toward(target: Vector3, straight: Vector3) -> Vector3:
	var nav: NavField = game.get("nav")
	if nav == null:
		return straight.normalized()
	return nav.path_dir(global_position, target, _nav)


## A gentle push away from other foes so a band spreads around her
## instead of stacking in one spot.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.dead:
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.01 and l < 1.8:
			push += d / l * (1.8 - l) * 0.8
	return push

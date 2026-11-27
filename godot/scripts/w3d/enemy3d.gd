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
var _aggro := false
var _attack_timer := 0.0     ## time to the blow landing (wind-up)
var _cooldown := 0.0
var _stagger := 0.0
var _clip := ""
var _flash: StandardMaterial3D
var _flash_time := 0.0
var _strafe := 1.0
var _charge := 0.0


func setup(the_kind: String, the_game: Node) -> void:
	kind = the_kind
	game = the_game
	spec = SPECS[kind]
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


func _physics_process(delta: float) -> void:
	_flash_time -= delta
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
		_charge -= delta
		wish = -model.global_transform.basis.z
		speed = spec.speed * 3.2
		if dist < float(spec.reach) * 1.2 and _cooldown <= 0.0:
			_land_blow(player)
			_charge = 0.0
	elif _aggro:
		var reach: float = spec.reach
		if dist < reach * 0.95 and _cooldown <= 0.0:
			_begin_attack()
		elif is_boss and phase >= 2 and dist > 7.0 and dist < 18.0 and _cooldown <= 0.0 and randf() < 0.02:
			_charge = 1.1
			_cooldown = 3.0
			_play(spec.run, 1.6, true)
		else:
			wish = to_player.normalized()
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
			wish = to.normalized()
			speed *= 0.45

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
	if to.length() < reach and facing.dot(to.normalized()) > 0.35:
		player.hurt(spec.damage, global_position)
		game.on_player_hit(spec.damage)
	if is_boss and phase >= 3:
		game.boss_slam(self)


## The wedge on the ground that shows a coming blow (reach and arc).
var _tele: MeshInstance3D
static var _tele_shader: Shader


func _show_telegraph() -> void:
	_end_telegraph(false)
	if _tele_shader == null:
		_tele_shader = load("res://scripts/shaders/telegraph.gdshader")
	var reach: float = float(spec.reach) * 1.15
	_tele = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(reach * 2.0, reach * 2.0)
	_tele.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = _tele_shader
	m.set_shader_parameter("half_span", acos(0.35))
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

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
		"style": "charge", "element": Color(0.5, 0.9, 0.4), "name": "Thornling", "resist": {"arcane": -0.2},
		"idle": "Zombie_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Zombie_Scratch", "Punch_Jab"],
		"loot": [["wood", 0.6, 3], ["glowshard", 0.3, 1]], "sight": 20.0},
	"wisp_caller": {"model": "wisp_caller", "health": 50.0, "speed": 3.0, "damage": 12.0, "reach": 11.0, "windup": 0.8,
		"style": "ranged", "element": Color(0.35, 1.0, 0.9), "name": "Wisp Caller",
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"loot": [["glowshard", 0.7, 2], ["gold_coin", 0.4, 3]], "sight": 24.0},
	"frost_knight": {"model": "frost_knight", "health": 160.0, "speed": 2.6, "damage": 22.0, "reach": 3.4, "windup": 0.9,
		"style": "slam", "element": Color(0.6, 0.85, 1.0), "name": "Frost Knight", "resist": {"arcane": 0.15},
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Heavy_Combo"],
		"weapon": "iron_hammer", "loot": [["iron_ore", 0.8, 4], ["silver_ore", 0.5, 3], ["gold_coin", 0.7, 5]], "sight": 22.0},
	"rime_shade": {"model": "rime_shade", "health": 60.0, "speed": 3.4, "damage": 13.0, "reach": 12.0, "windup": 0.7,
		"style": "ranged", "element": Color(0.7, 0.9, 1.0), "name": "Rime Shade", "resist": {"arcane": 0.3},
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

## The starting islands' own creatures (beyond the shared region foes):
##   ambush — lies hidden in the ground until she is close, then springs
##   guard  — a shield: light blows from the front are mostly turned aside
##            (strike from behind, or with a heavy blow)
##   fly    — keeps to the air at that height
const ISLAND_SPECS := {
	"vine_stalker": {"model": "vine_stalker", "health": 70.0, "speed": 5.0, "damage": 13.0, "reach": 1.9, "windup": 0.35,
		"style": "charge", "ambush": true, "element": Color(0.45, 0.9, 0.35), "name": "Vine Stalker",
		"idle": "Zombie_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Zombie_Scratch", "Punch_Jab"],
		"loot": [["wood", 0.6, 3], ["emerald", 0.15, 1]], "sight": 18.0},
	"root_guardian": {"model": "root_guardian", "health": 180.0, "speed": 2.4, "damage": 20.0, "reach": 2.6, "windup": 0.75,
		"guard": 0.7, "defense": 25.0, "element": Color(0.6, 0.85, 0.4), "name": "Root Guardian",
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Regular_A", "Sword_Heavy_Combo"],
		"weapon": "iron_hammer", "shield": "wood_shield",
		"loot": [["wood", 0.8, 5], ["gold_coin", 0.7, 5], ["lumen_core", 0.1, 1]], "sight": 20.0},
	"gale_sprite": {"model": "gale_sprite", "health": 45.0, "speed": 4.6, "damage": 10.0, "reach": 12.0, "windup": 0.6,
		"style": "ranged", "fly": 2.4, "element": Color(0.75, 0.95, 1.0), "name": "Gale Sprite",
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"loot": [["glowshard", 0.6, 2], ["gold_coin", 0.4, 3]], "sight": 26.0},
	"aerie_sentinel": {"model": "aerie_sentinel", "health": 170.0, "speed": 2.6, "damage": 19.0, "reach": 2.8, "windup": 0.8,
		"style": "slam", "guard": 0.7, "defense": 30.0, "element": Color(0.8, 0.9, 1.0), "name": "Aerie Sentinel",
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Heavy_Combo"],
		"weapon": "silver_sword", "shield": "iron_shield",
		"loot": [["silver_ore", 0.7, 3], ["gold_coin", 0.7, 5]], "sight": 22.0},
	"crystal_husk": {"model": "crystal_husk", "health": 80.0, "speed": 4.2, "damage": 14.0, "reach": 1.9, "windup": 0.4,
		"style": "charge", "ambush": true, "element": Color(0.5, 0.95, 1.0), "name": "Crystal Husk",
		"idle": "Zombie_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Zombie_Scratch"],
		"loot": [["glowshard", 0.8, 3], ["starsilver", 0.08, 1]], "sight": 18.0},
	"tide_caller": {"model": "tide_caller", "health": 55.0, "speed": 3.0, "damage": 12.0, "reach": 12.0, "windup": 0.7,
		"style": "ranged", "element": Color(0.35, 0.8, 1.0), "name": "Tide Caller",
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"loot": [["glowshard", 0.6, 2], ["gold_coin", 0.5, 3]], "sight": 24.0},
	"coral_knight": {"model": "coral_knight", "health": 190.0, "speed": 2.5, "damage": 21.0, "reach": 2.8, "windup": 0.8,
		"guard": 0.7, "defense": 30.0, "element": Color(0.4, 0.9, 1.0), "name": "Coral Knight",
		"idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Sword_Regular_A", "Sword_Regular_B"],
		"weapon": "gold_sword", "shield": "iron_shield",
		"loot": [["gold_coin", 0.8, 6], ["emerald", 0.2, 1]], "sight": 20.0},
}

## The three starting islands' guardians. Each fights in phases (health
## 60% and 30%) drawing on its own moves (see _boss_move):
##   lines  — roots erupt along three telegraphed lines toward her
##   ring   — a shockwave all round it (jump it!)
##   rain   — crystal shards fall on glowing circles around her
##   volley — a fan of bolts; dive — it swoops onto a marked spot
##   summon — calls its island's creatures; charge — a lunge
##   melee  — its weapon at close range
const BOSS_SPECS := {
	"thornmother": {"model": "thornmother", "health": 1400.0, "speed": 3.0, "damage": 22.0, "reach": 3.2, "windup": 0.7,
		"scale": 1.7, "boss": "The Thornmother", "title": "Guardian of the First Root", "element": Color(0.5, 0.95, 0.4),
		"defense": 30.0, "resist": {"arcane": -0.1}, "idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd",
		"attack": ["Sword_Regular_A", "Sword_Regular_B"], "heavy": "Sword_Heavy_Combo", "weapon": "iron_hammer",
		"patterns": [["melee", "lines"], ["melee", "lines", "ring"], ["lines", "ring", "summon", "charge"]], "adds": "thornling",
		"phase_lines": ["", "", "The roots wake beneath you!", "The First Root calls her children!"],
		"loot": [["heart_crystal", 1.0, 1], ["lumen_core", 1.0, 1], ["gold_coin", 1.0, 40]], "sight": 34.0},
	"stormwing": {"model": "stormwing", "health": 1100.0, "speed": 4.0, "damage": 16.0, "reach": 16.0, "windup": 0.8,
		"scale": 1.6, "boss": "The Stormwing", "title": "Last Sentinel of the Aerie", "element": Color(0.6, 0.9, 1.0),
		"defense": 15.0, "resist": {"arcane": 0.1}, "style": "ranged", "fly": 2.8,
		"idle": "Spell_Simple_Idle", "walk": "Walk", "run": "Jog_Fwd", "attack": ["Spell_Simple_Shoot"],
		"patterns": [["volley"], ["volley", "dive"], ["volley", "dive", "ring", "summon"]], "adds": "wisp_caller",
		"phase_lines": ["", "", "The Stormwing dives!", "The winds answer the Sentinel!"],
		"loot": [["heart_crystal", 1.0, 1], ["relic_featherbone", 1.0, 1], ["gold_coin", 1.0, 40]], "sight": 36.0},
	"tidewarden": {"model": "tidewarden", "health": 1600.0, "speed": 2.8, "damage": 24.0, "reach": 3.4, "windup": 0.75,
		"scale": 1.75, "boss": "The Tidewarden", "title": "Keeper of the Crystal Deep", "element": Color(0.45, 0.95, 1.0),
		"defense": 40.0, "resist": {"arcane": 0.2}, "idle": "Sword_Idle", "walk": "Walk", "run": "Jog_Fwd",
		"attack": ["Sword_Regular_A", "Sword_Regular_C"], "heavy": "Sword_Heavy_Combo", "weapon": "gold_sword", "shield": "iron_shield",
		"patterns": [["melee", "rain"], ["melee", "rain", "ring"], ["rain", "ring", "charge", "summon"]], "adds": "rime_shade",
		"phase_lines": ["", "", "Crystal rains from the deep!", "The tide brings its guard!"],
		"loot": [["heart_crystal", 1.0, 1], ["relic_tidecaller", 1.0, 1], ["gold_coin", 1.0, 40]], "sight": 34.0},
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
## What it is doing (for the HUD, tests and debugging): patrol, chase,
## windup, charge, retreat, search, return, stagger, move (a boss move), dead.
var state := "patrol"
var _sense := 0.0
var _sees := false
var _last_seen := Vector3.ZERO
var _lost := 0.0
var _search := 0.0
var _returning := false
var _retreat := 0.0
var _retreated := false
var _move_left := 0.0       ## a boss move's own wind-up: it holds still
var _emerged := false
var elite := false
var _adds: Array = []
## Seconds left of an Arcane Mark (Phase Step): takes 20% more harm.
var mark := 0.0
const MARK_VULN := 0.2
## Armour by fighting style (heavier styles shrug off more of each blow).
const STYLE_DEFENSE := {"melee": 8.0, "charge": 10.0, "ranged": 0.0, "slam": 35.0}


func setup(the_kind: String, the_game: Node) -> void:
	kind = the_kind
	game = the_game
	if SPECS.has(kind):
		spec = SPECS[kind]
	elif ZONE_SPECS.has(kind):
		spec = ZONE_SPECS[kind]
	elif ISLAND_SPECS.has(kind):
		spec = ISLAND_SPECS[kind]
	else:
		spec = BOSS_SPECS[kind]
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
	_flash.albedo_color = Color(1.0, 0.95, 0.92, 0.0)   # a crisp white hit flash
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = _flash
		(m as MeshInstance3D).extra_cull_margin = 2.0
	_home = global_position
	_wander_target = _home
	_play(spec.idle)
	if not is_boss:
		_build_bar()
	if elite:
		# A golden aura marks an elite.
		var aura := OmniLight3D.new()
		aura.light_color = Color(1.0, 0.82, 0.35)
		aura.light_energy = 1.2
		aura.omni_range = 3.5
		aura.shadow_enabled = false
		aura.position = Vector3(0, 1.4, 0)
		add_child(aura)
		Arcana.circle(game, global_position, 1.2, Color(1.0, 0.82, 0.35), 2.0, 1.0)
	if spec.has("ambush"):
		_hide()
	_glowing_eyes()
	if spec.has("boss") and BOSS_SPECS.has(kind):
		_dress_guardian()
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
	mark = maxf(0.0, mark - delta)
	if _bar:
		_bar_time -= delta
		_bar.visible = _bar_time > 0.0 and not dead
		if _bar.visible:
			var f := clampf(health / max_health, 0.0, 1.0)
			_bar_fill.scale.x = maxf(f, 0.001)
			_bar_fill.position.x = 0.0
	if not dead:
		_flash.albedo_color.a = clampf(_flash_time * 6.0, 0.0, 0.6)
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
	if spec.has("ambush") and not _emerged:
		# Hidden in the ground until she is close.
		if dist < 6.5 and player.health > 0.0:
			_emerge()
		else:
			velocity = Vector3.ZERO
			return
	var sight: float = spec.sight
	# Senses: sight needs a clear line (four times a second); she is heard
	# when close, and a boss always knows its arena.
	_sense -= delta
	if _sense <= 0.0:
		_sense = 0.25
		_sees = dist < sight and (is_boss or _line_of_sight(player))
	elif dist >= sight:
		_sees = false   # out of range is known at once; only the ray waits
	var heard := dist < 3.5
	if (_sees or heard) and player.health > 0.0:
		_last_seen = player.global_position
		_lost = 0.0
		if not _aggro:
			_aggro = true
			_search = 0.0
			_returning = false
			if is_boss:
				game.boss_started(self)
	elif _aggro:
		_lost += delta
		if _lost > 3.0 or dist > sight * 2.2 or player.health <= 0.0:
			# Lost her: go to where she was last seen and look around.
			_aggro = false
			_search = 6.0
	_cooldown -= delta
	_stagger -= delta
	_move_left -= delta
	_retreat -= delta
	var wish := Vector3.ZERO
	var speed: float = spec.speed
	if not is_boss and not _retreated and health < max_health * 0.3 and _style in ["ranged", "charge"]:
		# Badly hurt: break away for a moment, then fight on.
		_retreated = true
		_retreat = 2.2
	state = "chase" if _aggro else ("search" if _search > 0.0 else ("return" if _returning else "patrol"))

	if _stagger > 0.0:
		state = "stagger"
	elif _move_left > 0.0:
		state = "move"
		_face(to_player, delta, 4.0)
	elif _retreat > 0.0 and _aggro:
		state = "retreat"
		wish = -to_player.normalized()
		speed *= 1.25
	elif _aggro and spec.has("patterns") and _cooldown <= 0.0 and _attack_timer <= 0.0 and _charge <= 0.0 and _boss_move(player, dist):
		state = "move"
	elif _attack_timer > 0.0:
		# Winding up: face the player, then the blow lands.
		_attack_timer -= delta
		_face(to_player, delta, 6.0)
		if _tele:
			(_tele.material_override as ShaderMaterial).set_shader_parameter("fill", 1.0 - _attack_timer / float(spec.windup))
		state = "windup"
		if _attack_timer <= 0.0:
			_land_blow(player)
			_end_telegraph(true)
	elif _charge > 0.0:
		# Lunging along the way it faces (the model looks down +Z), turning
		# a little toward her; the blow lands when it reaches her.
		_charge -= delta
		state = "charge"
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
	elif _search > 0.0:
		# Searching: walk to where she was last seen, then cast about.
		_search -= delta
		var to_seen := _last_seen - global_position
		to_seen.y = 0.0
		if to_seen.length() > 1.5:
			wish = _toward(_last_seen, to_seen)
			speed *= 0.7
		elif randf() < 0.02:
			_last_seen += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		if _search <= 0.0:
			_returning = true
	elif _returning:
		var to_home := _home - global_position
		to_home.y = 0.0
		if to_home.length() > 2.0:
			wish = _toward(_home, to_home)
			speed *= 0.6
		else:
			_returning = false
			health = minf(max_health, health + max_health * 0.25)   # it rests at its post
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
	if spec.has("fly") and _dive <= 0.0:
		# Aloft: it holds a height over the ground, bobbing.
		var want_y: float = _home.y + float(spec.fly) + sin(Time.get_ticks_msec() * 0.002) * 0.3
		velocity.y = (want_y - global_position.y) * 3.0
	elif _dive <= 0.0:
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
func _cast_bolt(player: Player3D, colour: Color, yaw_offset := 0.0) -> void:
	var from := global_position + Vector3(0, 1.35 * float(spec.get("scale", 1.0)), 0) + model.global_transform.basis.z * 0.6
	var lead := player.velocity * 0.35
	var aim := (player.global_position + Vector3(0, 1.0, 0) + lead - from).normalized().rotated(Vector3.UP, yaw_offset)
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
## What DamageCalc needs from this foe: armour, resistances, debuffs.
func combat_stats(from := Vector3.INF, heavy := false) -> Dictionary:
	var defense: float = float(spec.get("defense", STYLE_DEFENSE.get(_style, 8.0)))
	if is_boss:
		defense = maxf(defense, 30.0)
	# A shield turns aside light blows from the front.
	var reduction := 0.0
	if spec.has("guard") and not heavy and from != Vector3.INF and model:
		var to := from - global_position
		to.y = 0.0
		if to.length() > 0.01 and model.global_transform.basis.z.dot(to.normalized()) > 0.3:
			reduction = float(spec.guard)
	return {"defense": defense, "resist": spec.get("resist", {}), "vulnerable": MARK_VULN if mark > 0.0 else 0.0,
		"reduction": reduction}


## Was a blow from `from` taken on its shield? (for the clang and sparks)
func guards_against(from: Vector3, heavy: bool) -> bool:
	return float(combat_stats(from, heavy).reduction) > 0.0


func take_hit(amount: float, from: Vector3, heavy: bool) -> bool:
	if dead:
		return false
	if is_nan(amount) or is_inf(amount) or amount < 0.0:
		amount = 0.0
	if spec.has("ambush") and not _emerged:
		_emerge()   # struck while hidden: it springs out
	health = maxf(0.0, health - amount)
	_flash_time = 0.14
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
	# It falls, lies a moment, then comes apart into motes of its light
	# (no sinking through the ground).
	var colour: Color = spec.get("element", Color(0.72, 0.5, 1.0))
	var t := create_tween()
	t.tween_interval(1.7 if not is_boss else 3.0)
	t.tween_callback(func():
		var at := global_position + Vector3(0, 0.8 * float(spec.get("scale", 1.0)), 0)
		Arcana.sparks(game, at, colour, 40 if not is_boss else 120, 3.5, 0.12, 1.5)
		Arcana.flash(game, at, colour, 1.5, 4.0, 0.4))
	t.tween_method(func(v: float): _flash.albedo_color = Color(colour.lerp(Color.WHITE, 0.5), v), 0.0, 0.85, 0.25)
	t.parallel().tween_property(model, "scale", model.scale * 0.04, 0.4).set_delay(0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
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


# ------------------------------------------------------------- senses ---

## Can it see her? A ray from its eyes to her chest, blocked by the world.
func _line_of_sight(player: Player3D) -> bool:
	if not is_inside_tree():
		return false
	var eye := global_position + Vector3(0, 1.5 * float(spec.get("scale", 1.0)), 0)
	var q := PhysicsRayQueryParameters3D.create(eye, player.global_position + Vector3(0, 1.1, 0), 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --------------------------------------------------------- boss moves ---

var _dive := 0.0


## The arena floor under a point: a flier's arena may be a sky isle, far
## above the land the terrain reports.
func _ground_at(x: float, z: float) -> float:
	if spec.has("fly"):
		return _home.y
	return game.world.height_at(x, z)


## Pick and start one of this phase's moves. False if none fits right now.
func _boss_move(player: Player3D, dist: float) -> bool:
	var options: Array = spec.patterns[clampi(phase - 1, 0, (spec.patterns as Array).size() - 1)]
	var pick: String = options[randi() % options.size()]
	var colour: Color = spec.get("element", Color(1, 0.8, 0.6))
	match pick:
		"melee":
			if dist > float(spec.reach) * 0.95:
				return false
			_begin_attack()
			return true
		"charge":
			if dist < 6.0 or dist > 18.0:
				return false
			_charge = 1.1
			_play(spec.run, 1.6, true)
			_show_telegraph(true)
		"lines":
			_move_lines(player, colour)
		"ring":
			_move_ring(colour)
		"rain":
			_move_rain(player, colour)
		"volley":
			_move_left = float(spec.windup)
			_play(spec.attack[0], 1.0, true)
			Arcana.circle(game, global_position, 1.6, colour, float(spec.windup), 1.5)
			get_tree().create_timer(float(spec.windup)).timeout.connect(func():
				if dead or not is_instance_valid(player):
					return
				for k in 5:
					_cast_bolt(player, colour, (k - 2) * 0.22))
		"dive":
			_move_dive(player, colour)
		"summon":
			_adds = _adds.filter(func(a): return is_instance_valid(a) and not a.dead)
			if _adds.size() >= 3 or not spec.has("adds"):
				return false
			_move_left = 1.0
			_play("Spell_Simple_Shoot", 0.8, true)
			Arcana.pillar(game, global_position, 1.2, 10.0, colour, 1.0)
			for k in 2:
				var a := randf() * TAU
				var at := global_position + Vector3(cos(a), 0, sin(a)) * 5.0
				at.y = _ground_at(at.x, at.z)
				Arcana.circle(game, at, 1.4, colour, 0.9, 2.0)
				_adds.append(game.spawn_enemy(spec.adds, at))
	_cooldown = randf_range(1.5, 2.5) / (1.0 + (phase - 1) * 0.25)
	return true


## Three lines of roots (or light) racing out toward her; she has the
## wind-up to step out of them.
func _move_lines(player: Player3D, colour: Color) -> void:
	var windup := 0.95 - (phase - 1) * 0.1
	_move_left = windup + 0.2
	_play(spec.get("heavy", spec.attack[0]), 0.9, true)
	var to := player.global_position - global_position
	to.y = 0.0
	var base := to.normalized() if to.length() > 0.1 else model.global_transform.basis.z
	var origin := global_position
	var marks: Array = []
	for k in 3:
		var dir := base.rotated(Vector3.UP, (k - 1) * 0.38)
		marks.append([dir, _line_mark(origin, dir, 15.0, colour, windup)])
	get_tree().create_timer(windup).timeout.connect(func():
		if dead:
			return
		for m in marks:
			var dir: Vector3 = m[0]
			for i in 6:
				var at: Vector3 = origin + dir * (2.0 + i * 2.5)
				at.y = _ground_at(at.x, at.z)
				Arcana.sparks(game, at + Vector3(0, 0.3, 0), colour, 8, 5.0, 0.1)
			var rel: Vector3 = game.player.global_position - origin
			rel.y = 0.0
			var along := clampf(rel.dot(dir), 0.0, 15.0)
			if (rel - dir * along).length() < 1.1 and along > 0.5 and not game.player.dead:
				game.player.hurt(float(spec.damage) * 0.9, origin)
				game.on_player_hit(float(spec.damage) * 0.9))


func _line_mark(origin: Vector3, dir: Vector3, length: float, colour: Color, life: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, length)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/shaders/telegraph_line.gdshader")
	m.set_shader_parameter("tint", colour.lerp(Color(1.0, 0.32, 0.18), 0.6) * 0.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.game.add_child(mi)
	var mid := origin + dir * (length * 0.5 + 0.5)
	mid.y = _ground_at(mid.x, mid.z) + 0.08
	mi.global_position = mid
	mi.global_basis = Basis(Vector3.UP, atan2(dir.x, dir.z))
	var t := mi.create_tween()
	t.tween_method(func(v: float): m.set_shader_parameter("fill", v), 0.0, 1.0, life)
	t.tween_method(func(v: float): m.set_shader_parameter("flash", v), 1.0, 0.0, 0.3)
	t.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 0.2)
	t.tween_callback(mi.queue_free)
	return mi


## A shockwave all round it. Airborne, she is safe.
func _move_ring(colour: Color) -> void:
	var windup := 0.9
	var radius := 6.5
	_move_left = windup + 0.2
	_play(spec.get("heavy", spec.attack[0]), 0.9, true)
	Arcana.circle(game, global_position, radius, colour, windup, 0.6)
	get_tree().create_timer(windup).timeout.connect(func():
		if dead:
			return
		game.ring_burst(global_position, radius, colour)
		var p: Player3D = game.player
		var ground: float = _ground_at(p.global_position.x, p.global_position.z)
		if p.global_position.distance_to(global_position) < radius and p.global_position.y - ground < 0.6 and not p.dead:
			p.hurt(float(spec.damage), global_position)
			game.on_player_hit(float(spec.damage)))


## Crystal shards on glowing circles: one on her, four around.
func _move_rain(player: Player3D, colour: Color) -> void:
	var windup := 1.1 - (phase - 1) * 0.1
	_move_left = 0.6
	_play("Spell_Simple_Shoot", 0.8, true)
	var spots: Array = [player.global_position]
	for k in 4 + phase:
		var a := randf() * TAU
		spots.append(player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 6.0))
	for at in spots:
		var g: Vector3 = at
		g.y = _ground_at(g.x, g.z)
		Arcana.circle(game, g, 1.7, colour, windup, 1.8)
		get_tree().create_timer(windup).timeout.connect(func():
			if dead:
				return
			Arcana.pillar(game, g, 0.6, 7.0, colour, 0.5)
			Arcana.sparks(game, g + Vector3(0, 0.4, 0), colour, 16, 6.0, 0.1)
			var p: Player3D = game.player
			if Vector2(p.global_position.x - g.x, p.global_position.z - g.z).length() < 1.7 and not p.dead:
				p.hurt(float(spec.damage) * 0.8, g)
				game.on_player_hit(float(spec.damage) * 0.8))


## It marks where she stands, then swoops onto it.
func _move_dive(player: Player3D, colour: Color) -> void:
	var windup := 0.9
	var target := player.global_position
	target.y = _ground_at(target.x, target.z)
	_move_left = windup + 0.6
	Arcana.circle(game, target, 2.6, colour, windup, 2.5)
	get_tree().create_timer(windup).timeout.connect(func():
		if dead:
			return
		_dive = 0.6
		var t := create_tween()
		t.tween_property(self, "global_position", target + Vector3(0, 0.2, 0), 0.32).set_ease(Tween.EASE_IN)
		t.tween_callback(func():
			game.ring_burst(target, 2.6, colour)
			var p: Player3D = game.player
			if p.global_position.distance_to(target) < 2.6 and not p.dead:
				p.hurt(float(spec.damage) * 1.2, target)
				game.on_player_hit(float(spec.damage) * 1.2))
		t.tween_interval(0.3)
		t.tween_callback(func(): _dive = 0.0))


# ------------------------------------------------------- ambush, elite ---

## Sinks out of sight (an ambusher before it springs).
func _hide() -> void:
	model.visible = false
	model.position.y -= 1.6
	collision_layer = 0
	if _bar:
		_bar.visible = false


func _emerge() -> void:
	_emerged = true
	model.visible = true
	collision_layer = 4
	var t := create_tween()
	t.tween_property(model, "position:y", model.position.y + 1.6, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var colour: Color = spec.get("element", Color(0.6, 0.9, 0.4))
	Arcana.sparks(game, global_position + Vector3(0, 0.4, 0), colour, 30, 6.0, 0.12)
	game.debris(global_position + Vector3(0, 0.3, 0), Color(0.35, 0.3, 0.22), 14)
	_aggro = true
	_attack_timer = 0.0
	_cooldown = 0.2
	Sfx.play("growl", -4.0, 0.15)


## A stronger, golden-aura'd one of its kind: tougher, harder-hitting,
## richer spoils. Called before it enters the tree.
func make_elite() -> void:
	elite = true
	spec = spec.duplicate(true)
	spec.health = float(spec.health) * 2.5
	spec.damage = float(spec.damage) * 1.3
	spec.scale = float(spec.get("scale", 1.0)) * 1.2
	spec.name = "Elite " + String(spec.get("name", kind.capitalize()))
	var loot: Array = []
	for d in spec.get("loot", []):
		loot.append([d[0], minf(1.0, float(d[1]) * 2.0), int(d[2]) * 2])
	loot.append(["heart_crystal", 0.15, 1])
	spec.loot = loot
	max_health = spec.health
	health = max_health


# ----------------------------------------------- guardians' silhouettes ---

## Each guardian wears its island: thorns and spores, wings and wind, a
## crest of crystal; attached to its bones so they move with it.
func _dress_guardian() -> void:
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var colour: Color = spec.element
	var glow := StandardMaterial3D.new()
	glow.albedo_color = colour.darkened(0.2)
	glow.emission_enabled = true
	glow.emission = colour
	glow.emission_energy_multiplier = 1.4
	glow.roughness = 0.4
	var head := _bone_mount(sk, "Head")
	var chest := _bone_mount(sk, "Chest")
	match kind:
		"thornmother":
			var bark := StandardMaterial3D.new()
			bark.albedo_color = Color(0.25, 0.32, 0.16)
			bark.roughness = 0.9
			# A crown of thorns.
			for k in 9:
				var a := TAU * k / 9.0
				_spike(head, Vector3(cos(a) * 0.13, 0.17, sin(a) * 0.13), Vector3(cos(a) * 0.5, 1.0, sin(a) * 0.5), 0.22 + 0.08 * (k % 2), 0.035, glow if k % 3 == 0 else bark)
			# Thorns on the shoulders and back.
			for side in [-1.0, 1.0]:
				for k in 3:
					_spike(chest, Vector3(side * (0.22 + k * 0.05), 0.12 + k * 0.03, -0.08), Vector3(side * 0.8, 0.7, -0.4), 0.3 - k * 0.05, 0.05, bark)
			_motes(chest, colour, 24, 0.6)
		"stormwing":
			var feather := StandardMaterial3D.new()
			feather.albedo_color = Color(0.92, 0.95, 1.0, 0.92)
			feather.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			feather.cull_mode = BaseMaterial3D.CULL_DISABLED
			feather.emission_enabled = true
			feather.emission = colour * 0.4
			for side in [-1.0, 1.0]:
				var wing := Node3D.new()
				chest.add_child(wing)
				wing.position = Vector3(side * 0.12, 0.1, -0.14)
				wing.rotation = Vector3(0.1, side * -0.35, side * 0.25)
				for k in 6:
					var f := MeshInstance3D.new()
					var q := PrismMesh.new()
					q.size = Vector3(0.18, 0.9 - k * 0.08, 0.02)
					f.mesh = q
					f.material_override = feather
					wing.add_child(f)
					f.position = Vector3(side * (0.15 + k * 0.17), 0.25 - k * 0.07, 0)
					f.rotation.z = side * (0.5 + k * 0.18)
				var t := wing.create_tween().set_loops()
				t.tween_property(wing, "rotation:z", side * 0.55, 0.6).set_trans(Tween.TRANS_SINE)
				t.tween_property(wing, "rotation:z", side * 0.15, 0.6).set_trans(Tween.TRANS_SINE)
			_motes(chest, colour, 30, 1.0)
		"tidewarden":
			for k in 5:
				for part in FoliageLib.parts("P:crystal"):
					var mi := MeshInstance3D.new()
					mi.mesh = part[0]
					mi.material_override = glow
					chest.add_child(mi)
					var a := (k - 2) * 0.35
					mi.transform = Transform3D(Basis.from_euler(Vector3(-0.5, 0, a)).scaled(Vector3.ONE * (0.18 - absf(k - 2) * 0.03)), Vector3(sin(a) * 0.15, 0.25, -0.18)) * (part[1] as Transform3D)
			_motes(chest, colour, 20, 0.7)
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 1.0
	light.omni_range = 5.0
	light.shadow_enabled = false
	chest.add_child(light)


func _bone_mount(sk: Skeleton3D, bone: String) -> Node3D:
	var at := BoneAttachment3D.new()
	at.bone_name = bone
	sk.add_child(at)
	# Undo the rig's own scale so ornaments are sized in metres.
	var holder := Node3D.new()
	at.add_child(holder)
	var b := sk.find_bone(bone)
	if b >= 0:
		var rig: Vector3 = (sk.global_transform * sk.get_bone_global_rest(b)).basis.get_scale()
		var want: Vector3 = model.global_transform.basis.get_scale()
		holder.scale = Vector3(want.x / maxf(rig.x, 1e-4), want.y / maxf(rig.y, 1e-4), want.z / maxf(rig.z, 1e-4))
	return holder


func _spike(parent: Node3D, at: Vector3, dir: Vector3, length: float, radius: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 5
	mi.mesh = c
	mi.material_override = mat
	parent.add_child(mi)
	var up := dir.normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, up, x.cross(up)), at + up * length * 0.5)


func _motes(parent: Node3D, colour: Color, amount: int, spread: float) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Play3D._spark_texture()
	m.albedo_color = colour
	p.material_override = m
	p.amount = amount
	p.lifetime = 1.8
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread
	p.gravity = Vector3(0, 0.4, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	parent.add_child(p)


## Two points of light in its eye sockets, in its element's colour (the
## Risen a cold violet): a creature, not a prop. Placed from the rig's own
## head and neck so it fits any size.
func _glowing_eyes() -> void:
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var head := sk.find_bone("Head")
	var neck := sk.find_bone("Neck")
	if head < 0 or neck < 0:
		return
	var hr := sk.get_bone_global_rest(head)
	var h := (hr.origin - sk.get_bone_global_rest(neck).origin).length()
	if h <= 0.0:
		return
	var to_sk := sk.global_transform.basis.inverse()
	var fwd := (to_sk * model.global_transform.basis.z).normalized()
	var up := (to_sk * Vector3.UP).normalized()
	var right := up.cross(fwd).normalized()
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	sk.add_child(att)
	var colour: Color = spec.get("element", Color(0.7, 0.4, 1.0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Play3D._spark_texture()
	m.albedo_color = colour.lerp(Color.WHITE, 0.25)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(h, h) * 0.32
		eye.mesh = q
		eye.material_override = m
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		att.add_child(eye)
		var at_sk: Vector3 = hr.origin + up * h * 0.42 + fwd * h * 0.62 + right * side * h * 0.2
		eye.transform = Transform3D(Basis(), hr.affine_inverse() * at_sk)

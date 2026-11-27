class_name Progression
extends RefCounted
## The heroine's level and experience. XP comes from the risen dead (a
## third of their health), felled trees, broken rock and finished requests;
## each level raises her health, stamina and the force of her blade, and
## some open a new art of the Moonblade:
##   Lv 1  Violet slashes; the blade gathers wood and stone
##   Lv 2  Crescent Wave: a heavy stroke flings a travelling crescent
##   Lv 3  Arcane Comet (E): a homing orb that bursts among foes
##   Lv 4  Phase Step (R): a blink through foes; the afterimage cuts and Marks
##   Lv 5  Violet Starfall (Q): a rune circle and a rain of star lances
##   Lv 7  Blade Orbit (F): her floating blade circles her, cutting all near
## Each level from 2 on also gives a skill point; points raise an art's rank
## (1 -> 2 costs 1, 2 -> 3 costs 2): more damage and a shorter cooldown.

signal xp_gained(amount: int)
signal leveled(level: int, unlocked: String)

const MAX_LEVEL := 20
## Arts and the level that opens each.
const UNLOCKS := {"crescent": 2, "comet": 3, "phase": 4, "starfall": 5, "orbit": 7}
const ART_NAMES := {"crescent": "Crescent Wave", "comet": "Arcane Comet", "phase": "Phase Step",
	"starfall": "Violet Starfall", "orbit": "Blade Orbit"}
## Per art: the control it lives on, damage multiplier (x weapon power) and
## cooldown (s) at ranks 1..3, and what it does.
const ARTS := {
	"crescent": {"slot": "heavy", "mult": [1.6, 1.9, 2.3], "cooldown": [0.0, 0.0, 0.0],
		"desc": "A heavy stroke flings a travelling crescent that cuts every foe in its path."},
	"comet": {"slot": "skill", "mult": [2.2, 2.6, 3.1], "cooldown": [6.0, 5.0, 4.0],
		"desc": "A homing orb of arcana that bursts in a ring of runes among her foes."},
	"phase": {"slot": "skill2", "mult": [1.3, 1.6, 1.9], "cooldown": [5.0, 4.2, 3.4],
		"desc": "She blinks forward through foes, untouchable; her violet afterimage cuts all she passed and Marks them (they take 20% more harm for 5 s)."},
	"orbit": {"slot": "skill3", "mult": [0.55, 0.7, 0.85], "cooldown": [14.0, 12.0, 10.0],
		"desc": "Her floating blade leaves her hand and circles her for 4 s, cutting every foe it sweeps (several times)."},
	"starfall": {"slot": "burst", "mult": [3.0, 3.6, 4.3], "cooldown": [0.0, 0.0, 0.0],
		"desc": "When charged by battle: a great rune circle opens and star lances rain on every foe near her."},
}
const MAX_RANK := 3
## XP for each source.
const XP_TREE := 6
const XP_ROCK := 5
const XP_QUEST := 60

var level := 1
var xp := 0
## art -> rank bought beyond 1 (0..2).
var ranks := {}


## XP needed to go from `lv` to the next level.
static func need(lv: int) -> int:
	return 60 + lv * 40 + lv * lv * 6


func unlocked(art: String) -> bool:
	return level >= int(UNLOCKS.get(art, 1))


## An art's rank: 0 while sealed, then 1..MAX_RANK.
func rank(art: String) -> int:
	if not unlocked(art):
		return 0
	return 1 + clampi(int(ranks.get(art, 0)), 0, MAX_RANK - 1)


func art_mult(art: String) -> float:
	var r := maxi(1, rank(art))
	return float((ARTS[art].mult as Array)[r - 1])


func art_cooldown(art: String) -> float:
	var r := maxi(1, rank(art))
	return float((ARTS[art].cooldown as Array)[r - 1])


## Points earned (one per level from 2) less those spent.
func points() -> int:
	var spent := 0
	for a in ranks:
		var r := int(ranks[a])
		spent += r * (r + 1) / 2   # rank 2 cost 1, rank 3 cost 2 more
	return maxi(0, (level - 1) - spent)


func upgrade_cost(art: String) -> int:
	return rank(art)   # 1 to reach rank 2, 2 to reach rank 3


## Spend points on an art's next rank. True if it rose.
func upgrade(art: String) -> bool:
	if not ARTS.has(art) or not unlocked(art) or rank(art) >= MAX_RANK:
		return false
	var cost := upgrade_cost(art)
	if points() < cost:
		return false
	ranks[art] = int(ranks.get(art, 0)) + 1
	return true


## Bonus multiplier on her blade's damage.
func damage_bonus() -> float:
	return 1.0 + 0.07 * (level - 1)


func gain(amount: int) -> void:
	if amount <= 0 or level >= MAX_LEVEL:
		return
	xp += amount
	xp_gained.emit(amount)
	while level < MAX_LEVEL and xp >= need(level):
		xp -= need(level)
		level += 1
		var art := ""
		for a in UNLOCKS:
			if int(UNLOCKS[a]) == level:
				art = a
		leveled.emit(level, art)
	if level >= MAX_LEVEL:
		xp = 0


## Stat totals at a level (the base the player starts with is level 1).
static func max_health_at(lv: int) -> float:
	return 100.0 + (lv - 1) * 12.0


static func max_stamina_at(lv: int) -> float:
	return 100.0 + (lv - 1) * 4.0


func to_dict() -> Dictionary:
	return {"level": level, "xp": xp, "ranks": ranks.duplicate()}


func from_dict(d: Dictionary) -> void:
	level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	xp = maxi(0, int(d.get("xp", 0)))
	ranks = {}
	var r: Dictionary = d.get("ranks", {})
	for a in r:
		if ARTS.has(a):
			ranks[a] = clampi(int(r[a]), 0, MAX_RANK - 1)
	# Never more spent than earned (an edited or older save).
	while points() <= 0 and _overspent():
		for a in ranks.keys():
			ranks[a] = maxi(0, int(ranks[a]) - 1)


func _overspent() -> bool:
	var spent := 0
	for a in ranks:
		var k := int(ranks[a])
		spent += k * (k + 1) / 2
	return spent > level - 1

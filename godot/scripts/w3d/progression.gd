class_name Progression
extends RefCounted
## The heroine's level and experience. XP comes from the risen dead (a
## third of their health), felled trees, broken rock and finished requests;
## each level raises her health, stamina and the force of her blade, and
## some open a new art of the Moonblade:
##   Lv 1  Violet slashes; the blade gathers wood and stone
##   Lv 2  Crescent Wave: a heavy stroke flings a travelling crescent
##   Lv 3  Arcane Comet (E): a homing orb that bursts among foes
##   Lv 5  Violet Starfall (Q): a rune circle and a rain of star lances

signal xp_gained(amount: int)
signal leveled(level: int, unlocked: String)

const MAX_LEVEL := 20
## Arts and the level that opens each.
const UNLOCKS := {"crescent": 2, "comet": 3, "starfall": 5}
const ART_NAMES := {"crescent": "Crescent Wave", "comet": "Arcane Comet", "starfall": "Violet Starfall"}
## XP for each source.
const XP_TREE := 6
const XP_ROCK := 5
const XP_QUEST := 60

var level := 1
var xp := 0


## XP needed to go from `lv` to the next level.
static func need(lv: int) -> int:
	return 60 + lv * 40 + lv * lv * 6


func unlocked(art: String) -> bool:
	return level >= int(UNLOCKS.get(art, 1))


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
	return {"level": level, "xp": xp}


func from_dict(d: Dictionary) -> void:
	level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	xp = maxi(0, int(d.get("xp", 0)))

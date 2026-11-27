class_name DamageCalc
extends RefCounted
## THE damage formula. Every blow in the game — her strikes and arts, and
## every foe's attacks on her — goes through compute(), so the number shown
## is always exactly the health taken away.
##
##   power   = (weapon + 2 * (level - 1)) * (1 + 0.04 * (level - 1)) * buff
##   raw     = power * skill_mult
##   armour  = 100 / (100 + defense * (1 - pierce))       diminishing, never 0
##   element = 1 - resist[element]   (resist clamped -0.5 .. 0.8; < 0 = weak)
##   crit    = crit_damage if roll < crit_chance else 1
##   vuln    = 1 + vulnerable                          (debuffs such as Mark)
##   guard   = 1 - reduction                        (blocking, shields; <=0.9)
##   final   = round(raw * armour * element * crit * vuln * guard * variance)
##             variance 0.95 .. 1.05; at least 1 for any landed hit; NaN, INF
##             and negatives are impossible (clamped to 1 .. MAX_HIT).
##
## Attacker: {weapon, level, buff, crit_chance, crit_damage, pierce}
## Target:   {defense, resist: {element: float}, vulnerable, reduction}

const MAX_HIT := 99999
const CRIT_CHANCE := 0.1
const CRIT_DAMAGE := 1.6


static func power(attacker: Dictionary) -> float:
	var level: int = maxi(1, int(attacker.get("level", 1)))
	var weapon: float = maxf(0.0, _num(attacker.get("weapon", 4.0)))
	var buff: float = maxf(0.0, _num(attacker.get("buff", 1.0), 1.0))
	return (weapon + 2.0 * (level - 1)) * (1.0 + 0.04 * (level - 1)) * buff


## One hit. `roll` and `spread` (0..1) default to random; tests pass them.
## Returns {"amount": int, "crit": bool}.
static func compute(attacker: Dictionary, target: Dictionary, skill_mult := 1.0, element := "", roll := -1.0, spread := -1.0) -> Dictionary:
	if roll < 0.0:
		roll = randf()
	if spread < 0.0:
		spread = randf()
	var raw := power(attacker) * maxf(0.0, _num(skill_mult, 1.0))
	var defense := maxf(0.0, _num(target.get("defense", 0.0)))
	var pierce := clampf(_num(attacker.get("pierce", 0.0)), 0.0, 1.0)
	var armour := 100.0 / (100.0 + defense * (1.0 - pierce))
	var resist := 0.0
	if element != "":
		resist = clampf(_num((target.get("resist", {}) as Dictionary).get(element, 0.0)), -0.5, 0.8)
	var crit := roll < clampf(_num(attacker.get("crit_chance", CRIT_CHANCE)), 0.0, 1.0)
	var crit_mult := maxf(1.0, _num(attacker.get("crit_damage", CRIT_DAMAGE), CRIT_DAMAGE)) if crit else 1.0
	var vuln := 1.0 + clampf(_num(target.get("vulnerable", 0.0)), 0.0, 2.0)
	var guard := 1.0 - clampf(_num(target.get("reduction", 0.0)), 0.0, 0.9)
	var variance := lerpf(0.95, 1.05, clampf(spread, 0.0, 1.0))
	var total := raw * armour * (1.0 - resist) * crit_mult * vuln * guard * variance
	# Clamp as a float first: rounding a huge float would overflow the int.
	var amount := roundi(clampf(total, 1.0, float(MAX_HIT))) if raw > 0.0 and not is_nan(total) else 0
	return {"amount": amount, "crit": crit}


## A foe's blow on her: its base damage against her armour and guard.
static func incoming(base: float, defense: float, reduction := 0.0, spread := -1.0) -> int:
	var r := compute({"weapon": base, "level": 1, "crit_chance": 0.0}, {"defense": defense, "reduction": reduction}, 1.0, "", 1.0, spread)
	return int(r.amount)


static func _num(v, fallback := 0.0) -> float:
	var f := float(v) if (v is float or v is int) else fallback
	if is_nan(f) or is_inf(f):
		return fallback
	return f

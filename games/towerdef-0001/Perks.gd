extends RefCounted
## Run perks (SPEC B7): pure static rules. `taken` is an Array of perk ids
## (a stacking perk appears once per take).

const PerkDB := preload("res://data/PerkDB.gd")
const TuneRef := preload("res://Tune.gd")


static func count(taken: Array, id: String) -> int:
	var n: int = 0
	for x in taken:
		if String(x) == id:
			n += 1
	return n


static func available(taken: Array) -> Array:
	var out: Array = []
	for id in PerkDB.IDS:
		var d: Dictionary = PerkDB.DEFS[id]
		if count(taken, String(id)) < int(d["stack"]):
			out.append(String(id))
	return out


## Up to 3 distinct available ids: one per family where one exists, then
## filled from the rest. Seeded Fisher-Yates (never Array.shuffle).
static func offer(rng: RandomNumberGenerator, taken: Array) -> Array:
	var pool: Array = available(taken)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var picks: Array = []
	for fam in PerkDB.FAMILIES:
		for id in pool:
			var d: Dictionary = PerkDB.DEFS[id]
			if String(d["fam"]) == String(fam) and not picks.has(id):
				picks.append(id)
				break
	for id in pool:
		if picks.size() >= 3:
			break
		if not picks.has(id):
			picks.append(id)
	return picks


## Multipliers implied by `taken`. Pure numbers so tests can assert exact values.
static func mults(taken: Array) -> Dictionary:
	var glass: bool = taken.has("p_glass")
	var fort: bool = taken.has("p_fort")
	var hp: float = 1.0
	if taken.has("p_hp"):
		hp *= 1.25
	if glass:
		hp *= 0.75
	if fort:
		hp *= 1.6
	return {
		"dmg": 1.0 + 0.2 * float(count(taken, "p_dmg")) + (0.4 if glass else 0.0) - (0.2 if fort else 0.0),
		"rate": 1.0 + 0.15 * float(count(taken, "p_rate")) + (0.3 if taken.has("p_frenzy") else 0.0),
		"range": 1.2 if taken.has("p_range") else 1.0,
		"hp": maxf(0.5, hp),
		"regen": 0.0 if taken.has("p_frenzy") else (2.0 if fort else 1.0),
		"mine": 1.0 + 0.25 * float(count(taken, "p_cash")),
		"xp": (1.3 if taken.has("p_xp") else 1.0) * (0.7 if taken.has("p_miser") else 1.0),
		"cash": 1.5 if taken.has("p_greed") else 1.0,
		"coin": (1.5 if taken.has("p_greed") else 1.0) * (1.75 if taken.has("p_bloodmoon") else 1.0),
		"enemy_spd": 1.15 if taken.has("p_greed") else 1.0,
		"enemy_hp": TuneRef.num("greed_enemy_hp", 1.25) if taken.has("p_greed") else 1.0,
		"upgrade_cost": 0.7 if taken.has("p_miser") else 1.0,
		"spawn": 0.8 if taken.has("p_bloodmoon") else 1.0,
	}


## Apply perks to a compute_stats() dict in place and return it. Clamps (AC-24):
## max HP never below 50% of its pre-perk value, regen never negative.
static func apply(st: Dictionary, taken: Array) -> Dictionary:
	var m: Dictionary = mults(taken)
	var base_hp: float = float(st["max_hp"])
	st["max_hp"] = maxf(base_hp * 0.5, base_hp * float(m["hp"]))
	st["regen"] = maxf(0.0, float(st["regen"]) * float(m["regen"]))
	st["cash_ps"] = float(st["cash_ps"]) * float(m["mine"])
	st["xp_mult"] = float(st["xp_mult"]) * float(m["xp"])
	for w in st["weapons"]:
		var wd: Dictionary = w
		wd["dmg"] = float(wd["dmg"]) * float(m["dmg"])
		wd["rate"] = float(wd["rate"]) * float(m["rate"])
		wd["range"] = float(wd["range"]) * float(m["range"])
	for k in ["cash", "coin", "enemy_spd", "enemy_hp", "upgrade_cost", "spawn"]:
		st["perk_" + String(k)] = float(m[k])
	return st

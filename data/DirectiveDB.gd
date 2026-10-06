extends RefCounted
## Directives (V2 P7c): rule-changers offered when a boss wave is cleared
## (pick 1 of 3, Vampire Survivors' Arcana). Each is a gain with a cost:
##   fx    keys added to the run's fx (TowerState.dfx, read through pf)
##   enemy {hp, count} enemy multipliers (+x)
##   choices  +draft choices
## A Directive is taken once per run.

const DEFS: Dictionary = {
	"dr_bullet": {"name": "Bullet Hell", "fx": {"multishot": 2.0, "dmg": -0.25}, "desc": "+2 Weapon targets per volley", "cost": "-25% all damage"},
	"dr_glass": {"name": "Glass Fortress", "fx": {"bld_dmg": 0.40, "core_hp": -0.30}, "desc": "+40% building damage", "cost": "-30% Core max HP"},
	"dr_gold": {"name": "Gold Rush", "fx": {"kill_cash": 1.0}, "enemy": {"hp": 0.20}, "desc": "Kill cash x2", "cost": "Enemies +20% HP"},
	"dr_scholar": {"name": "Scholar's Oath", "fx": {"xp": 0.50, "cash": -0.20}, "desc": "+50% XP (more drafts)", "cost": "-20% cash per second"},
	"dr_siege": {"name": "Siege Mode", "fx": {"range": 2.0, "rate": -0.20}, "desc": "+2 cells Weapon range", "cost": "-20% Weapon attack rate"},
	"dr_iron": {"name": "Iron Will", "fx": {"armor": 4.0, "regen": 0.50, "dr": 0.05}, "desc": "+4 armor, +50% regen, -5% damage taken", "cost": "-15% all damage", "fx2": {"dmg": -0.15}},
	"dr_luck": {"name": "Lucky Streak", "fx": {"draft_luck": 3.0, "loot_luck": 2.0}, "enemy": {"count": 0.10}, "desc": "+3 draft luck, +2 loot luck", "cost": "+10% more enemies"},
	"dr_exec": {"name": "Executioner", "fx": {"execute": 0.08, "crit": 0.05}, "desc": "Weapon hits finish bodies under 8% HP, +5% crit", "cost": "-10% building attack rate", "fx2": {"bld_rate": -0.10}},
	"dr_frost": {"name": "Permafrost", "fx": {"slow_hit": 0.15, "regen": 0.25}, "desc": "Weapon hits slow 15%, +25% regen", "cost": "-10% Weapon damage", "fx2": {"core_dmg": -0.10}},
	"dr_high": {"name": "High Roller", "fx": {"coin_run": 0.25}, "choices": 1, "enemy": {"count": 0.15}, "desc": "+1 draft choice, +25% coins", "cost": "+15% more enemies"},
	"dr_overdrive": {"name": "Overdrive Protocol", "fx": {"rate": 0.35, "bld_rate": 0.35}, "desc": "+35% Weapon and building attack rate", "cost": "-20% Core max HP", "fx2": {"core_hp": -0.20}},
	"dr_titan": {"name": "Titan Slayer", "fx": {"boss": 0.75}, "desc": "+75% damage to bosses", "cost": "-20% kill cash", "fx2": {"kill_cash": -0.20}},
}
const IDS: Array = ["dr_bullet", "dr_glass", "dr_gold", "dr_scholar", "dr_siege", "dr_iron", "dr_luck", "dr_exec", "dr_frost", "dr_high", "dr_overdrive", "dr_titan"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## fx of the taken directives (fx + the cost's fx2).
static func fx_of(taken: Array) -> Dictionary:
	var out: Dictionary = {}
	for id in taken:
		var d: Dictionary = DEFS.get(String(id), {})
		for part in ["fx", "fx2"]:
			for k in (d.get(part, {}) as Dictionary).keys():
				out[k] = float(out.get(k, 0.0)) + float(d[part][k])
	return out


## Enemy multiplier `key` (hp / count) of the taken directives.
static func enemy_mult(taken: Array, key: String) -> float:
	var m: float = 1.0
	for id in taken:
		m *= 1.0 + float((DEFS.get(String(id), {}).get("enemy", {}) as Dictionary).get(key, 0.0))
	return m


## 3 distinct untaken ids (seeded).
static func offer(rng: RandomNumberGenerator, taken: Array, n: int = 3) -> Array:
	var pool: Array = IDS.filter(func(i: Variant) -> bool: return not taken.has(i))
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var k: int = rng.randi_range(0, pool.size() - 1)
		out.append(pool[k])
		pool.remove_at(k)
	return out

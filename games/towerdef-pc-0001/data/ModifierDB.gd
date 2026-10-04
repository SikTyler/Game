extends RefCounted
## Challenge modifiers (PC_SPEC §3.2) and endless mutation cards (§3.1). Pure
## data; TowerState.setup(opts.modifiers / opts.mode) applies them. Coin
## rewards stack additively and the total multiplier caps at COIN_CAP.

const COIN_CAP: float = 3.0

const DEFS: Dictionary = {
	"glass":    {"name": "Glass Core",  "coin": 0.15, "desc": "Core max HP -50%"},
	"swarm":    {"name": "Swarm",       "coin": 0.10, "desc": "+60% enemies, -30% HP each"},
	"ironclad": {"name": "Ironclad",    "coin": 0.30, "desc": "Enemies take -20% damage from non-crit hits"},
	"poverty":  {"name": "Austerity",   "coin": 0.10, "desc": "Start with $0, kill cash -30%"},
	"allsides": {"name": "Encircled",   "coin": 0.10, "desc": "All 4 lanes attack from wave 1"},
	"noperks":  {"name": "Purist",      "coin": 0.55, "desc": "No perk drafts"},
	"haste":    {"name": "Haste",       "coin": 0.10, "desc": "Enemy speed +25%"},
	"elitist":  {"name": "Elite Guard", "coin": 0.40, "desc": "Elite weight x3, elites from Tier 1"},
	"nolabs":   {"name": "Fresh Start", "coin": 0.60, "desc": "Lab bonuses disabled for the run"},
}

const IDS: Array = ["glass", "swarm", "ironclad", "poverty", "allsides", "noperks", "haste", "elitist", "nolabs"]

## Endless mutations: one pick of 3 every MUTATION_EVERY waves; each enemy buff
## pays +MUTATION_COIN coins (multiplicative with the modifier multiplier).
const MUTATION_EVERY: int = 25
const MUTATION_COIN: float = 0.15
const MUTATION_STACK: int = 3
const MUTATIONS: Dictionary = {
	"m_vigor":   {"name": "Vigor",   "desc": "Enemy HP +20%"},
	"m_rush":    {"name": "Rush",    "desc": "Enemy speed +10%"},
	"m_horde":   {"name": "Horde",   "desc": "Enemy count +20%"},
	"m_fangs":   {"name": "Fangs",   "desc": "Enemy damage +25%"},
	"m_plating": {"name": "Plating", "desc": "Elite shields +2"},
}
const MUTATION_IDS: Array = ["m_vigor", "m_rush", "m_horde", "m_fangs", "m_plating"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## Known, de-duplicated modifier ids in canonical order.
static func clean(ids: Array) -> Array:
	var out: Array = []
	for id in IDS:
		if ids.has(id):
			out.append(id)
	return out


## min(3.0, 1 + sum of the picked modifiers' coin rewards).
static func coin_mult(ids: Array) -> float:
	var sum: float = 0.0
	for id in clean(ids):
		sum += float((DEFS[id] as Dictionary)["coin"])
	return minf(COIN_CAP, 1.0 + sum)

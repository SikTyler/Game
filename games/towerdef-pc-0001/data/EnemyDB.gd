extends RefCounted
## Enemy archetypes at wave 1 (SYSTEMS §8). Spawn gates live in Tiers.allows;
## weights in WEIGHTS (roll order: hauler, splitter, elite, ranged, skitter, drone). TowerState scales hp/dmg by hp_growth^(wave-1).

const DEFS: Dictionary = {
	"drone":   {"hp": 6.0,   "spd": 45.0, "dmg": 4.0,  "cash": 1.0,  "xp": 1.0,  "coin": 0.2,  "size": 16.0},
	"skitter": {"hp": 3.0,   "spd": 85.0, "dmg": 2.0,  "cash": 1.0,  "xp": 1.0,  "coin": 0.15, "size": 13.0},
	"hauler":  {"hp": 24.0,  "spd": 28.0, "dmg": 10.0, "cash": 3.0,  "xp": 3.0,  "coin": 0.6,  "size": 26.0},
	"ranged":  {"hp": 8.0,   "spd": 40.0, "dmg": 3.0,  "cash": 2.0,  "xp": 2.0,  "coin": 0.3,  "size": 15.0},
	"elite":   {"hp": 30.0,  "spd": 32.0, "dmg": 12.0, "cash": 5.0,  "xp": 5.0,  "coin": 1.0,  "size": 24.0},
	"splitter": {"hp": 18.0, "spd": 38.0, "dmg": 6.0,  "cash": 2.0,  "xp": 2.0,  "coin": 0.4,  "size": 22.0},
	"mite":    {"hp": 3.0,   "spd": 95.0, "dmg": 1.5,  "cash": 0.5,  "xp": 0.5,  "coin": 0.05, "size": 10.0},
	"boss":    {"hp": 200.0, "spd": 22.0, "dmg": 18.0, "cash": 25.0, "xp": 15.0, "coin": 10.0, "size": 44.0},
}

## Spawn weights per roll slot; elite comes from Tiers.elite_weight(tier).
const WEIGHTS: Dictionary = {"hauler": 0.15, "splitter": 0.10, "ranged": 0.12, "skitter": 0.25}
const ROLL_ORDER: Array = ["hauler", "splitter", "elite", "ranged", "skitter"]


static func get_def(kind: String) -> Dictionary:
	return DEFS.get(kind, {})

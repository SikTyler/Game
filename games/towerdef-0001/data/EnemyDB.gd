extends RefCounted
## Enemy archetypes at wave 1. TowerState scales hp/dmg by hp_growth^(wave-1).

const DEFS: Dictionary = {
	"drone":   {"hp": 6.0,   "spd": 45.0, "dmg": 4.0,  "cash": 1.0,  "xp": 1.0,  "coin": 0.2,  "size": 16.0},
	"skitter": {"hp": 3.0,   "spd": 85.0, "dmg": 2.0,  "cash": 1.0,  "xp": 1.0,  "coin": 0.15, "size": 13.0},
	"hauler":  {"hp": 24.0,  "spd": 28.0, "dmg": 10.0, "cash": 3.0,  "xp": 3.0,  "coin": 0.6,  "size": 26.0},
	"boss":    {"hp": 200.0, "spd": 22.0, "dmg": 18.0, "cash": 25.0, "xp": 15.0, "coin": 10.0, "size": 44.0},
}


static func get_def(kind: String) -> Dictionary:
	return DEFS.get(kind, {})

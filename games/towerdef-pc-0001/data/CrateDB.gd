extends RefCounted
## Part crates (REDESIGN_SYSTEMS §3.4, REDESIGN_SPEC §3.1). Odds are disclosed
## in-game (hard rule): `odds` are the per-part rarity weights in percent,
## `pity` is the guaranteed rarity after N opens without one. The Set Crate is
## cut (REDESIGN_SPEC §9). Field Crate coin cost = 2,500 x (1 + 0.25(T-1)).

const DEFS: Dictionary = {
	"field": {"name": "Field Crate", "parts": 1, "coins": 2500, "keys": 0,
		"odds": {"common": 70.0, "rare": 25.0, "epic": 4.5, "legendary": 0.5}, "pity": {"epic": 20}, "rare_plus": 0},
	"supply": {"name": "Supply Crate", "parts": 2, "coins": 0, "keys": 1,
		"odds": {"common": 45.0, "rare": 40.0, "epic": 12.0, "legendary": 3.0}, "pity": {"epic": 10, "legendary": 50}, "rare_plus": 0},
	"vault": {"name": "Vault Crate", "parts": 4, "coins": 0, "keys": 4,
		"odds": {"common": 25.0, "rare": 45.0, "epic": 22.0, "legendary": 8.0}, "pity": {"legendary": 15}, "rare_plus": 1},
}
const IDS: Array = ["field", "supply", "vault"]
const RARITIES: Array = ["common", "rare", "epic", "legendary"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

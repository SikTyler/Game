extends RefCounted
## Building content. Every building is a stat modifier / special effect; the
## numbers themselves live in TowerState.compute_stats() so one pure function
## owns all the math. Reached via preload + static (no autoloads).

const DEFS: Dictionary = {
	"gun":     {"name": "Gun Turret",    "cat": "weapon",  "coin": 15, "desc": "Rapid single-target fire"},
	"mortar":  {"name": "Mortar",        "cat": "weapon",  "coin": 20, "desc": "Slow, heavy splash shells"},
	"tesla":   {"name": "Tesla Coil",    "cat": "weapon",  "coin": 20, "desc": "Chains zaps + slows"},
	"armory":  {"name": "Armory",        "cat": "support", "coin": 18, "desc": "+25%/lv dmg to adjacent weapons & core"},
	"bulwark": {"name": "Bulwark",       "cat": "support", "coin": 15, "desc": "+40 max HP & +0.5 regen /lv"},
	"mine":    {"name": "Mine",          "cat": "eco",     "coin": 15, "desc": "+$1.2/sec per lv"},
	"oilmill": {"name": "Oil Mill",      "cat": "eco",     "coin": 15, "desc": "+25% XP/lv (+15%/adj Mine); adj Mortar/Tesla +5% dmg/lv"},
	"bounty":  {"name": "Bounty Office", "cat": "eco",     "coin": 18, "desc": "+40% kill cash /lv; adj weapons +5% dmg /lv"},
	"vault":   {"name": "Vault",         "cat": "eco",     "coin": 20, "desc": "Wave end: +4%/lv interest on held cash (cap $40/lv)"},
	"aegis":   {"name": "Aegis Pylon",   "cat": "support", "coin": 22, "desc": "-4%/lv core dmg; adj weapons +10%/lv rate; adj eco -15%"},
}

const IDS: Array = ["gun", "mortar", "tesla", "armory", "bulwark", "mine", "oilmill", "bounty"]

## Run-3+ buildings (SYSTEMS §11): drafted only when run_mods.allow_new_bldg.
const NEW_IDS: Array = ["vault", "aegis"]


static func all_ids() -> Array:
	return IDS + NEW_IDS


static func ids() -> Array:
	return IDS


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func cat_of(id: String) -> String:
	var d: Dictionary = DEFS.get(id, {})
	return String(d.get("cat", ""))


static func cat_color(cat: String) -> Color:
	match cat:
		"weapon":
			return Color("3fd8e8")
		"eco":
			return Color("f2a93b")
		"support":
			return Color("6bd46b")
	return Color.WHITE

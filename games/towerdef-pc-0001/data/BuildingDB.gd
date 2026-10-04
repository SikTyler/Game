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
	# PC roster (PC_SPEC §2.2).
	"railgun":   {"name": "Railgun",       "cat": "weapon",  "coin": 28, "desc": "Piercing line shot every 2.5 s; outer rings only (ring 2+). Adj Tesla: +20% dmg per 5 Tesla lv (max +60%)"},
	"flak":      {"name": "Flak Battery",  "cat": "weapon",  "coin": 22, "desc": "Fast splash, x1.5 vs skitter/mite/drone. Adj Gun: both +10% crit"},
	"beacon":    {"name": "Lane Beacon",   "cat": "support", "coin": 20, "desc": "+15%/lv weapon dmg vs the focused lane. Adj Mortar: +25% range"},
	"refinery":  {"name": "Refinery",      "cat": "eco",     "coin": 24, "desc": "Wave end: 10% of the wave's cash income -> coins (cap 2.5/lv). Adj Mine: +20% output"},
	"barricade": {"name": "Barricade",     "cat": "support", "coin": 16, "desc": "Wall on its lane: -30% enemy speed, 60 HP/lv, rebuilt each wave"},
}

const IDS: Array = ["gun", "mortar", "tesla", "armory", "bulwark", "mine", "oilmill", "bounty"]

## Run-3+ buildings (SYSTEMS §11): drafted only when run_mods.allow_new_bldg.
const NEW_IDS: Array = ["vault", "aegis"]

## PC-only buildings; drafted with the run-3+ set.
const PC_IDS: Array = ["railgun", "flak", "beacon", "refinery", "barricade"]


static func all_ids() -> Array:
	return IDS + NEW_IDS + PC_IDS


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

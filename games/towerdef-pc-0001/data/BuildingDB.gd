extends RefCounted
## Building content. Every building is a stat modifier / special effect; the
## numbers themselves live in TowerState.compute_stats() so one pure function
## owns all the math. Reached via preload + static (no autoloads).

const PickDB := preload("res://data/PickDB.gd")

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
	"flak":      {"name": "Flamer",  "cat": "weapon",  "coin": 22, "desc": "40 deg cone of fire; burn spreads through the pile"},
	"beacon":    {"name": "Signal Beacon", "cat": "support", "coin": 20, "desc": "+10%/lv rate & +0.3/lv range to buildings within 2 cells, every direction"},
	"refinery":  {"name": "Refinery",      "cat": "eco",     "coin": 24, "desc": "Wave end: 10% of the wave's cash income -> coins (cap 2.5/lv). Adj Mine: +20% output"},
	"barricade": {"name": "Wall",          "cat": "support", "coin": 16, "desc": "Blocker: flowed around or squeezed through at a crawl; enemies within 1.5 cells on any side -30% speed"},
	# Redesign run-only picks (PickDB holds draft text; these give the view a name + colour).
	"frost":        {"name": "Cryo Spire",     "cat": "weapon",  "coin": 0, "desc": "Slows 30% within 2.5 cells, 3 dmg/s"},
	"obelisk":      {"name": "Siphon Obelisk", "cat": "support", "coin": 0, "desc": "1% of all damage dealt heals the Core"},
	"hut_infantry": {"name": "Rifle Barracks", "cat": "support", "coin": 0, "desc": "3 Riflemen guard the whole perimeter and taunt"},
	"hut_sapper":   {"name": "Sapper Den",     "cat": "support", "coin": 0, "desc": "2 Sappers charge elites and bosses and explode"},
	# V2 P7d weapons (PickDB holds the draft text).
	"pulse":     {"name": "Pulse Emitter",   "cat": "weapon", "coin": 0, "desc": "Radial pulse around it"},
	"missile":   {"name": "Missile Battery", "cat": "weapon", "coin": 0, "desc": "Homing missiles with small blasts"},
	"spike":     {"name": "Spike Pylon",     "cat": "weapon", "coin": 0, "desc": "Stabs every body next to it"},
	"mines":     {"name": "Minelayer",       "cat": "weapon", "coin": 0, "desc": "Seeds mines under the horde"},
	"scatter":   {"name": "Scatter Gun",     "cat": "weapon", "coin": 0, "desc": "Fixed cone of pellets"},
	"laser":     {"name": "Laser Lance",     "cat": "weapon", "coin": 0, "desc": "Fixed lane beam that ramps up"},
	"saw":       {"name": "Saw Launcher",    "cat": "weapon", "coin": 0, "desc": "Ricocheting saw blades"},
	"arcproj":   {"name": "Arc Projector",   "cat": "weapon", "coin": 0, "desc": "Forked lightning in an arc"},
	"sonic":     {"name": "Sonic Cannon",    "cat": "weapon", "coin": 0, "desc": "Shock wave cone that hurls the pile back"},
	"harpoon":   {"name": "Harpoon",         "cat": "weapon", "coin": 0, "desc": "Heavy bolt, deadly on elites"},
	"plasma":    {"name": "Plasma Fence",    "cat": "weapon", "coin": 0, "desc": "Sets its lane burning"},
	"flakburst": {"name": "Flak Burst",      "cat": "weapon", "coin": 0, "desc": "Airbursts over the crowd"},
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


## Buildings first; any other roguelite pick (pack / special / Insight) gets a
## view-compatible def from PickDB so the current draft UI can name it.
static func get_def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	var pd: Dictionary = PickDB.get_def(id)
	if pd.is_empty():
		return {}
	var tags: Array = pd.get("tags", [])
	var cat: String = "eco" if tags.has("eco") else ("weapon" if (tags.has("dps") or tags.has("aoe")) else "support")
	return {"name": String(pd["name"]), "cat": cat, "coin": 0, "desc": String(pd["desc"])}


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

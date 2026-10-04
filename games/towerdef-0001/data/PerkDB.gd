extends RefCounted
## Run perks (SYSTEMS §7, SPEC B7). Offered every perk_every waves, one per
## family when possible. `stack` = how many times the perk may be taken.
## `cost` is the red COST line for tradeoff perks (empty for pure perks).

const DEFS: Dictionary = {
	"p_dmg":       {"name": "Overcharge",      "fam": "offense", "stack": 3, "tradeoff": false, "desc": "+20% weapon damage", "cost": ""},
	"p_rate":      {"name": "Hair Trigger",    "fam": "offense", "stack": 2, "tradeoff": false, "desc": "+15% fire rate", "cost": ""},
	"p_range":     {"name": "Long Barrels",    "fam": "offense", "stack": 1, "tradeoff": false, "desc": "+20% range", "cost": ""},
	"p_glass":     {"name": "Glass Cannon",    "fam": "offense", "stack": 1, "tradeoff": true,  "desc": "+40% damage", "cost": "-25% max HP"},
	"p_frenzy":    {"name": "Frenzy",          "fam": "offense", "stack": 1, "tradeoff": true,  "desc": "+30% fire rate", "cost": "Regen disabled"},
	"p_hp":        {"name": "Reinforced Core", "fam": "defense", "stack": 1, "tradeoff": false, "desc": "+25% max HP, heal to full", "cost": ""},
	"p_fort":      {"name": "Fortress",        "fam": "defense", "stack": 1, "tradeoff": true,  "desc": "+60% max HP, +100% regen", "cost": "-20% damage"},
	"p_cash":      {"name": "Prospector",      "fam": "economy", "stack": 2, "tradeoff": false, "desc": "+20% Mine cash/s", "cost": ""},
	"p_xp":        {"name": "Scholar",         "fam": "economy", "stack": 1, "tradeoff": false, "desc": "+30% XP", "cost": ""},
	"p_greed":     {"name": "Greed",           "fam": "economy", "stack": 1, "tradeoff": true,  "desc": "+50% cash & coins", "cost": "Enemies +15% speed, +70% HP"},
	"p_miser":     {"name": "Miser",           "fam": "economy", "stack": 1, "tradeoff": true,  "desc": "Cash upgrades -30% cost", "cost": "-30% XP"},
	"p_bloodmoon": {"name": "Blood Moon",      "fam": "economy", "stack": 1, "tradeoff": true,  "desc": "Coins x1.75", "cost": "+25% more enemies"},
}

const IDS: Array = ["p_dmg", "p_rate", "p_range", "p_glass", "p_frenzy", "p_hp", "p_fort", "p_cash", "p_xp", "p_greed", "p_miser", "p_bloodmoon"]
const FAMILIES: Array = ["offense", "defense", "economy"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func is_tradeoff(id: String) -> bool:
	var d: Dictionary = DEFS.get(id, {})
	return bool(d.get("tradeoff", false))

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
	"p_bloodmoon": {"name": "Blood Moon",      "fam": "economy", "stack": 1, "tradeoff": true,  "desc": "Coins x1.25", "cost": "+25% more enemies"},
	# ---- V2 P7d: 24 more (fx perks, TowerState.rfx), three new families ------
	"p_sharp":     {"name": "Sharpshooter",    "fam": "offense", "stack": 2, "tradeoff": false, "desc": "+10% crit chance", "cost": "", "fx": {"crit": 0.10}},
	"p_heavy":     {"name": "Heavy Rounds",    "fam": "offense", "stack": 2, "tradeoff": false, "desc": "+12% damage, +20% knockback", "cost": "", "fx": {"dmg": 0.12, "knock": 0.20}},
	"p_volley":    {"name": "Volley",          "fam": "offense", "stack": 1, "tradeoff": true,  "desc": "+1 Weapon target per volley", "cost": "-10% damage", "fx": {"multishot": 1.0, "dmg": -0.10}},
	"p_giant":     {"name": "Giant Killer",    "fam": "offense", "stack": 1, "tradeoff": false, "desc": "+35% damage to bosses", "cost": "", "fx": {"boss": 0.35}},
	"p_plated":    {"name": "Plated Hull",     "fam": "defense", "stack": 2, "tradeoff": false, "desc": "+3 armor", "cost": "", "fx": {"armor": 3.0}},
	"p_aegis":     {"name": "Aegis Core",      "fam": "defense", "stack": 1, "tradeoff": false, "desc": "+60 Core shield", "cost": "", "fx": {"shield": 60.0}},
	"p_spiked":    {"name": "Spiked Hull",     "fam": "defense", "stack": 1, "tradeoff": false, "desc": "Reflect 20% of Core hits", "cost": "", "fx": {"reflect": 0.20}},
	"p_laststand": {"name": "Last Stand",      "fam": "defense", "stack": 1, "tradeoff": false, "desc": "Below 30% HP: 2 s immunity, once per wave", "cost": "", "fx": {"last_stand": 1.0}},
	"p_compound":  {"name": "Compound",        "fam": "economy", "stack": 1, "tradeoff": false, "desc": "+2% interest", "cost": "", "fx": {"interest": 0.02}},
	"p_bounty":    {"name": "Bounty Hunter",   "fam": "economy", "stack": 2, "tradeoff": false, "desc": "+25% kill cash", "cost": "", "fx": {"kill_cash": 0.25}},
	"p_scrapper":  {"name": "Scrapper",        "fam": "economy", "stack": 1, "tradeoff": false, "desc": "+40% Scrap", "cost": "", "fx": {"scrap_find": 0.40}},
	"p_tycoon":    {"name": "Tycoon",          "fam": "economy", "stack": 1, "tradeoff": true,  "desc": "+25% cash per second", "cost": "-10% damage", "fx": {"cash": 0.25, "dmg": -0.10}},
	"p_frostbite": {"name": "Frostbite",       "fam": "control", "stack": 2, "tradeoff": false, "desc": "Weapon hits slow 12%", "cost": "", "fx": {"slow_hit": 0.12}},
	"p_quake":     {"name": "Quake",           "fam": "control", "stack": 1, "tradeoff": false, "desc": "+50% knockback", "cost": "", "fx": {"knock": 0.50}},
	"p_reaper":    {"name": "Reaper",          "fam": "control", "stack": 1, "tradeoff": false, "desc": "Weapon hits finish bodies under 5% HP", "cost": "", "fx": {"execute": 0.05}},
	"p_conductor": {"name": "Conductor",       "fam": "control", "stack": 1, "tradeoff": false, "desc": "+2 chain jumps, +1 ricochet", "cost": "", "fx": {"chain": 2.0, "bounce": 1.0}},
	"p_adrenaline": {"name": "Adrenaline",     "fam": "tempo", "stack": 2, "tradeoff": false, "desc": "+12% Weapon and building attack rate", "cost": "", "fx": {"rate": 0.12, "bld_rate": 0.12}},
	"p_overclock": {"name": "Overclocked",     "fam": "tempo", "stack": 1, "tradeoff": true,  "desc": "+25% building attack rate", "cost": "-15% Core max HP", "fx": {"bld_rate": 0.25, "core_hp": -0.15}},
	"p_focus":     {"name": "Focus",           "fam": "tempo", "stack": 1, "tradeoff": false, "desc": "+40% crit damage", "cost": "", "fx": {"crit_dmg": 0.40}},
	"p_longshot":  {"name": "Longshot",        "fam": "tempo", "stack": 1, "tradeoff": false, "desc": "+0.6 Weapon range", "cost": "", "fx": {"range": 0.60}},
	"p_charm":     {"name": "Lucky Charm",     "fam": "fortune", "stack": 1, "tradeoff": false, "desc": "+2 draft luck", "cost": "", "fx": {"draft_luck": 2.0}},
	"p_treasure":  {"name": "Treasure Hunter", "fam": "fortune", "stack": 1, "tradeoff": false, "desc": "+2 loot luck", "cost": "", "fx": {"loot_luck": 2.0}},
	"p_midas":     {"name": "Midas",           "fam": "fortune", "stack": 1, "tradeoff": false, "desc": "+20% coins this run", "cost": "", "fx": {"coin_run": 0.20}},
	"p_stakes":    {"name": "High Stakes",     "fam": "fortune", "stack": 1, "tradeoff": true,  "desc": "+3 loot luck", "cost": "-20% Core max HP", "fx": {"loot_luck": 3.0, "core_hp": -0.20}},
}

const IDS: Array = ["p_dmg", "p_rate", "p_range", "p_glass", "p_frenzy", "p_hp", "p_fort", "p_cash", "p_xp", "p_greed", "p_miser", "p_bloodmoon",
	"p_sharp", "p_heavy", "p_volley", "p_giant", "p_plated", "p_aegis", "p_spiked", "p_laststand", "p_compound", "p_bounty", "p_scrapper", "p_tycoon",
	"p_frostbite", "p_quake", "p_reaper", "p_conductor", "p_adrenaline", "p_overclock", "p_focus", "p_longshot", "p_charm", "p_treasure", "p_midas", "p_stakes"]
const FAMILIES: Array = ["offense", "defense", "economy", "control", "tempo", "fortune"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func is_tradeoff(id: String) -> bool:
	var d: Dictionary = DEFS.get(id, {})
	return bool(d.get("tradeoff", false))

extends RefCounted
## Core Modules (V2 P4): the ring of sockets around the Core's centre Weapon.
## A module carries a built-in effect (`fx`, Common L1 values; numeric ones
## scale with rarity base x level, `int` ones stay whole and only grow at
## masterworks) plus rolled perks. Sockets open with the Core level
## (Gear.SOCKETS). Every fx key is a pfx key TowerState.pf() reads.
##   fx       {pfx key: value}       ints: keys whose value is a count
##   trade    true for a module whose fx carries a cost (Overclock)
##   look     GearVis pod shape / glyph index

const INT_KEYS: Array = ["multishot", "bounce", "chain", "pierce", "luck"]
const IDS: Array = ["twin_feed", "echo", "splash", "penetrator", "ricochet", "arc_coupler", "crit_matrix", "crit_lens",
	"accelerator", "rangefinder", "igniter", "cryo_core", "kinetic_ram", "shield_gen", "regen_cell", "thorn_plate",
	"siphon", "executioner", "giant_slayer", "bounty_chip", "learning_chip", "fortune_chip", "overclock"]
const DEFS: Dictionary = {
	"twin_feed":    {"name": "Twin Feed",       "fx": {"multishot": 1.0}, "desc": "The Weapon fires one extra shot at another target", "look": 0},
	"echo":         {"name": "Echo Chamber",    "fx": {"echo": 0.15}, "desc": "15% chance each attack fires twice", "look": 1},
	"splash":       {"name": "Splash Chamber",  "fx": {"splash": 0.3}, "desc": "+0.3 cell splash on Weapon hits", "look": 2},
	"penetrator":   {"name": "Penetrator",      "fx": {"pierce": 2.0}, "desc": "Weapon shots pierce 2 more bodies", "look": 3},
	"ricochet":     {"name": "Ricochet Rig",    "fx": {"bounce": 2.0}, "desc": "Weapon hits bounce to 2 more bodies (x0.7)", "look": 4},
	"arc_coupler":  {"name": "Arc Coupler",     "fx": {"chain": 1.0, "chain_dmg": 0.10}, "desc": "+1 chain jump / pulse ring, +10% chain damage", "look": 5},
	"crit_matrix":  {"name": "Crit Matrix",     "fx": {"crit": 0.06}, "desc": "+6% crit chance", "look": 6},
	"crit_lens":    {"name": "Crit Lens",       "fx": {"crit_dmg": 0.30}, "desc": "+30% crit damage", "look": 7},
	"accelerator":  {"name": "Accelerator",     "fx": {"rate": 0.10}, "desc": "+10% Weapon attack rate", "look": 8},
	"rangefinder":  {"name": "Rangefinder",     "fx": {"range": 0.4}, "desc": "+0.4 cell Weapon range", "look": 9},
	"igniter":      {"name": "Igniter",         "fx": {"burn": 0.15}, "desc": "Weapon hits burn for 15% of their damage per second", "look": 10},
	"cryo_core":    {"name": "Cryo Core",       "fx": {"slow_hit": 0.15}, "desc": "Weapon hits slow 15%", "look": 11},
	"kinetic_ram":  {"name": "Kinetic Ram",     "fx": {"knock": 0.4}, "desc": "+40% Weapon knockback", "look": 12},
	"shield_gen":   {"name": "Shield Generator", "fx": {"shield": 30.0}, "desc": "+30 Core shield", "look": 13},
	"regen_cell":   {"name": "Regen Cell",      "fx": {"regen": 0.20}, "desc": "+20% Core regen", "look": 14},
	"thorn_plate":  {"name": "Thorn Plate",     "fx": {"reflect": 0.10}, "desc": "Reflects 10% of contact damage", "look": 15},
	"siphon":       {"name": "Siphon",          "fx": {"lifesteal": 0.01}, "desc": "Heals 1% of damage dealt", "look": 16},
	"executioner":  {"name": "Executioner",     "fx": {"execute": 0.05}, "desc": "Weapon hits execute non-bosses below 5% HP", "look": 17},
	"giant_slayer": {"name": "Giant Slayer",    "fx": {"boss": 0.20}, "desc": "+20% damage to elites and bosses", "look": 18},
	"bounty_chip":  {"name": "Bounty Chip",     "fx": {"kill_cash": 0.10}, "desc": "+10% kill cash", "look": 19},
	"learning_chip": {"name": "Learning Chip",  "fx": {"xp": 0.10}, "desc": "+10% run XP", "look": 20},
	"fortune_chip": {"name": "Fortune Chip",    "fx": {"luck": 1.0}, "desc": "+1 luck (drafts and loot)", "look": 21},
	"overclock":    {"name": "Overclock",       "fx": {"rate": 0.25, "core_hp": -0.15}, "trade": true, "desc": "+25% Weapon rate, -15% Core HP", "look": 22},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

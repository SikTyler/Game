extends RefCounted
## Data-driven run support / eco buildings (V2 P7d). The V1 support set
## (Armory, Beacon, Bulwark, ...) keeps its bespoke math in compute_stats;
## these 22 are generic, scaled by the building's tier x (1 + its "power"
## mods):
##   aura  {r, fx}   buildings (and the Core) whose footprint lies within r
##                   cells get fx: dmg / rate (+x), range (+cells), crit
##   core  {fx}      added to the run's fx (pf: the same keys gear, Core
##                   buildings, enhancements and Directives use)
##   cash            +cash/s (wave-1 units, x the cash index)
##   wall  {slow, dmg}  a Wall-like slow aura (1.5 cells) that also stabs
##   spin            cash a slot spin pays at every wave start (x cash index)
## Rarity / tags / text live in PickDB like every other draft card.

const DEFS: Dictionary = {
	"amp":         {"aura": {"r": 1, "fx": {"dmg": 0.20}}},
	"ocrelay":     {"aura": {"r": 2, "fx": {"rate": 0.12}}},
	"uplink":      {"aura": {"r": 3, "fx": {"range": 0.4}}},
	"critlens":    {"aura": {"r": 2, "fx": {"crit": 0.06}}},
	"coolant":     {"aura": {"r": 1, "fx": {"rate": 0.25, "dmg": -0.05}}},
	"ammodepot":   {"aura": {"r": 2, "fx": {"dmg": 0.08, "rate": 0.05}}},
	"watchtower":  {"aura": {"r": 3, "fx": {"range": 0.25, "crit": 0.03}}},
	"forge":       {"aura": {"r": 1, "fx": {"dmg": 0.12, "crit": 0.03}}},
	"lure":        {"core": {"slow_hit": 0.05, "knock": 0.15}},
	"shieldpylon": {"core": {"shield": 40.0}},
	"bank":        {"core": {"interest": 0.01, "icap": 0.25}},
	"capacitor":   {"core": {"rate": 0.06, "crit_dmg": 0.10}},
	"market":      {"cash": 1.2, "core": {"kill_cash": 0.05}},
	"xpsiphon":    {"core": {"xp": 0.12}},
	"magnet":      {"core": {"loot_luck": 1.0, "scrap_find": 0.10}},
	"salvager":    {"core": {"scrap_find": 0.25, "coin_run": 0.03}},
	"totem":       {"core": {"draft_luck": 1.0}},
	"medbay":      {"core": {"regen": 0.30, "core_hp": 0.05}},
	"taxoffice":   {"core": {"interest": 0.005, "cash": 0.08}},
	"insurance":   {"core": {"dr": 0.04, "armor": 1.0}},
	"slots":       {"spin": 60.0},
	"gate":        {"wall": {"slow": 0.20, "dmg": 6.0}},
}
const IDS: Array = ["amp", "ocrelay", "uplink", "critlens", "coolant", "ammodepot", "watchtower", "forge", "lure", "shieldpylon",
	"bank", "capacitor", "market", "xpsiphon", "magnet", "salvager", "totem", "medbay", "taxoffice", "insurance", "slots", "gate"]
## Keys whose stacked total is an integer luck (rounded down when read).
const LUCK_KEYS: Array = ["loot_luck", "draft_luck"]


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

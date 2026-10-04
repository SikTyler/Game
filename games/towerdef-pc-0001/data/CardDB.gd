extends RefCounted
## Cards (SPEC A7 / SYSTEMS §10). `key` is the run-mod field the card feeds;
## vals[L-1] is the value at level L.

const DEFS: Dictionary = {
	"c_dmg":    {"name": "Damage",      "key": "dmg",         "vals": [0.10, 0.16, 0.22, 0.30, 0.40], "fmt": "+%d%% damage"},
	"c_hp":     {"name": "Health",      "key": "hp",          "vals": [0.15, 0.22, 0.30, 0.40, 0.50], "fmt": "+%d%% max HP"},
	"c_cash":   {"name": "Cash",        "key": "cash",        "vals": [0.10, 0.15, 0.20, 0.27, 0.35], "fmt": "+%d%% cash"},
	"c_coin":   {"name": "Coins",       "key": "coin",        "vals": [0.08, 0.12, 0.16, 0.22, 0.30], "fmt": "+%d%% coins"},
	"c_xp":     {"name": "XP",          "key": "xp",          "vals": [0.10, 0.15, 0.20, 0.27, 0.35], "fmt": "+%d%% XP"},
	"c_reroll": {"name": "Free Reroll", "key": "reroll",      "vals": [1, 1, 2, 2, 3],                "fmt": "+%d draft rerolls"},
	"c_wind":   {"name": "Second Wind", "key": "wind_hp",     "vals": [0.20, 0.25, 0.30, 0.40, 0.50], "fmt": "Revive once at %d%% HP"},
	"c_skip":   {"name": "Wave Skip",   "key": "skip_chance", "vals": [0.03, 0.05, 0.07, 0.09, 0.12], "fmt": "%d%% chance to skip a wave"},
}

const IDS: Array = ["c_dmg", "c_hp", "c_cash", "c_coin", "c_xp", "c_reroll", "c_wind", "c_skip"]
const MAX_LVL: int = 5


static func value(id: String, lvl: int) -> float:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return 0.0
	var vals: Array = d["vals"]
	return float(vals[clampi(lvl, 1, MAX_LVL) - 1])


## Human-readable effect line at a level.
static func describe(id: String, lvl: int) -> String:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return ""
	var v: float = value(id, lvl)
	var n: int = int(v) if id == "c_reroll" else int(round(v * 100.0))
	return String(d["fmt"]) % n

extends RefCounted
## Daily mission templates (SYSTEMS §9). Targets scale with best wave B.

const DEFS: Dictionary = {
	"kill":    {"text": "Kill %d enemies",            "gems": 3},
	"wave":    {"text": "Reach wave %d",              "gems": 4},
	"boss":    {"text": "Defeat %d bosses",           "gems": 4},
	"eco":     {"text": "Place %d eco buildings",     "gems": 2},
	"cash":    {"text": "Earn $%d cash in one run",   "gems": 3},
	"perk":    {"text": "Take %d tradeoff perks",     "gems": 2},
	"lab":     {"text": "Start %d lab researches",    "gems": 2},
	"upgrade": {"text": "Buy %d permanent upgrades",  "gems": 2},
}

const IDS: Array = ["kill", "wave", "boss", "eco", "cash", "perk", "lab", "upgrade"]

## Streak ladder: day 1..7.
const STREAK: Array = [
	{"coins": 50, "gems": 0}, {"coins": 0, "gems": 2}, {"coins": 100, "gems": 0},
	{"coins": 0, "gems": 3}, {"coins": 200, "gems": 0}, {"coins": 0, "gems": 4},
	{"coins": 0, "gems": 10, "chest": true},
]

const TRADEOFF_PERKS: Array = ["p_glass", "p_greed", "p_fort", "p_frenzy", "p_miser", "p_bloodmoon"]


static func target(tpl: String, best_wave: int) -> int:
	var b: int = maxi(0, best_wave)
	match tpl:
		"kill":
			return 150 + 10 * b
		"wave":
			return maxi(10, int(floor(float(b) * 0.8)))
		"boss":
			return 1 + b / 30
		"eco":
			return 4
		"cash":
			return 300 + 25 * b
		"perk":
			return 2
		"lab":
			return 2
		"upgrade":
			return 3
	return 1


static func text(tpl: String, tgt: int) -> String:
	var d: Dictionary = DEFS.get(tpl, {})
	return String(d.get("text", "%d")) % tgt


static func reward(tpl: String) -> int:
	var d: Dictionary = DEFS.get(tpl, {})
	return int(d.get("gems", 0))

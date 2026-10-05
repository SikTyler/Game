extends RefCounted
## Daily mission templates (SYSTEMS §9). Targets scale with best wave B.
## Rewards are coins (owner feedback #1: gems removed).

const DEFS: Dictionary = {
	"kill":    {"text": "Kill %d enemies",            "coins": 120},
	"wave_kills": {"text": "Kill %d enemies in one wave", "coins": 120},
	"wave":    {"text": "Reach wave %d",              "coins": 160},
	"boss":    {"text": "Defeat %d bosses",           "coins": 160},
	"eco":     {"text": "Place %d eco buildings",     "coins": 80},
	"cash":    {"text": "Earn $%d cash in one run",   "coins": 120},
	"perk":    {"text": "Take %d tradeoff perks",     "coins": 80},
	"lab":     {"text": "Start %d lab researches",    "coins": 80},
	"upgrade": {"text": "Buy %d permanent upgrades",  "coins": 80},
}

const IDS: Array = ["kill", "wave", "boss", "eco", "cash", "perk", "lab", "upgrade", "wave_kills"]

## Streak ladder: day 1..7.
const STREAK: Array = [
	{"coins": 50}, {"coins": 80}, {"coins": 100},
	{"coins": 120}, {"coins": 200}, {"coins": 160},
	{"coins": 400, "chest": true},
]

const TRADEOFF_PERKS: Array = ["p_glass", "p_greed", "p_fort", "p_frenzy", "p_miser", "p_bloodmoon"]


static func target(tpl: String, best_wave: int) -> int:
	var b: int = maxi(0, best_wave)
	match tpl:
		"kill":
			# MASS_HORDE §D6: designed mass waves kill 100s-10,000s per wave
			# (a wave-20 run is ~7k bodies, a wave-35 run ~37k).
			if b >= 35:
				return 40000
			return 15000 if b >= 25 else 5000
		"wave_kills":
			return 5000 if b >= 35 else 1000
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
	return int(d.get("coins", 0))

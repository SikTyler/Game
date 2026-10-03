extends RefCounted
## Lab research tracks (SPEC A3). cost(L) = base*growth^L coins;
## duration(L) = dur_base*dur_growth^L seconds (× Lab Speed).

const DEFS: Dictionary = {
	"speed":     {"name": "Game Speed",    "max": 3,  "base": 400.0, "growth": 4.0,  "dur_base": 1800.0, "dur_growth": 3.0,  "effect": "Unlocks the next game speed step"},
	"dmg":       {"name": "Damage",        "max": 30, "base": 80.0,  "growth": 1.8,  "dur_base": 300.0,  "dur_growth": 1.6,  "effect": "+5% damage (core & weapons)"},
	"hp":        {"name": "Health",        "max": 30, "base": 80.0,  "growth": 1.8,  "dur_base": 300.0,  "dur_growth": 1.6,  "effect": "+5% core max HP"},
	"coin":      {"name": "Coin Bonus",    "max": 20, "base": 60.0,  "growth": 1.35, "dur_base": 300.0,  "dur_growth": 1.30, "effect": "+5% coins"},
	"xp":        {"name": "XP Bonus",      "max": 20, "base": 50.0,  "growth": 1.35, "dur_base": 240.0,  "dur_growth": 1.30, "effect": "+4% run XP"},
	"startcash": {"name": "Starting Cash", "max": 15, "base": 40.0,  "growth": 1.40, "dur_base": 180.0,  "dur_growth": 1.30, "effect": "+$15 cash at run start"},
	"offcap":    {"name": "Offline Cap",   "max": 8,  "base": 150.0, "growth": 1.60, "dur_base": 1200.0, "dur_growth": 1.45, "effect": "+1 h offline cap"},
	"offrate":   {"name": "Offline Rate",  "max": 5,  "base": 120.0, "growth": 1.50, "dur_base": 900.0,  "dur_growth": 1.40, "effect": "+5% offline rate"},
	"reroll":    {"name": "Draft Reroll",  "max": 3,  "base": 250.0, "growth": 3.0,  "dur_base": 2700.0, "dur_growth": 2.5,  "effect": "+1 free draft reroll per run"},
	"labspeed":  {"name": "Lab Speed",     "max": 10, "base": 200.0, "growth": 1.55, "dur_base": 1800.0, "dur_growth": 1.45, "effect": "-6% research time"},
}

const IDS: Array = ["speed", "dmg", "hp", "coin", "xp", "startcash", "offcap", "offrate", "reroll", "labspeed"]

const SPEED_STEPS: Array = [1.0, 1.5, 2.0, 2.5]


static func max_of(id: String) -> int:
	var d: Dictionary = DEFS.get(id, {})
	return int(d.get("max", 0))

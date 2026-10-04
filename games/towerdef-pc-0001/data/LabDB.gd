extends RefCounted
## Research Hall projects (SPEC A3, REDESIGN_SPEC §3.3). cost(L) =
## base*growth^L coins; duration(L) = dur_base*dur_growth^L seconds (x Lab
## Speed). offcap = Storage Tech, offrate = Logistics Tech (ids kept for saves);
## Part Analysis and Crate Theory are new.

const DEFS: Dictionary = {
	"speed":     {"name": "Game Speed",    "max": 3,  "base": 400.0, "growth": 4.0,  "dur_base": 1800.0, "dur_growth": 3.0,  "effect": "Unlocks a faster game speed"},
	"dmg":       {"name": "Damage",        "max": 30, "base": 80.0,  "growth": 1.8,  "dur_base": 300.0,  "dur_growth": 1.45, "effect": "+5% damage (core & weapons)"},
	"hp":        {"name": "Health",        "max": 30, "base": 80.0,  "growth": 1.8,  "dur_base": 300.0,  "dur_growth": 1.45, "effect": "+5% core max HP"},
	"coin":      {"name": "Coin Bonus",    "max": 20, "base": 60.0,  "growth": 1.35, "dur_base": 300.0,  "dur_growth": 1.30, "effect": "+5% coins"},
	"xp":        {"name": "XP Bonus",      "max": 20, "base": 50.0,  "growth": 1.35, "dur_base": 240.0,  "dur_growth": 1.30, "effect": "+4% run XP"},
	"startcash": {"name": "Starting Cash", "max": 15, "base": 40.0,  "growth": 1.40, "dur_base": 180.0,  "dur_growth": 1.30, "effect": "+$15 cash at run start"},
	"offcap":    {"name": "Storage Tech",  "max": 8,  "base": 150.0, "growth": 1.60, "dur_base": 1200.0, "dur_growth": 1.45, "effect": "+10% Outpost storage"},
	"offrate":   {"name": "Logistics Tech", "max": 5, "base": 120.0, "growth": 1.50, "dur_base": 900.0,  "dur_growth": 1.40, "effect": "+5% Outpost production"},
	"reroll":    {"name": "Draft Reroll",  "max": 3,  "base": 250.0, "growth": 3.0,  "dur_base": 2700.0, "dur_growth": 2.5,  "effect": "+1 free draft reroll per run"},
	"labspeed":  {"name": "Lab Speed",     "max": 10, "base": 200.0, "growth": 1.55, "dur_base": 1800.0, "dur_growth": 1.45, "effect": "-6% research time"},
	"part_analysis": {"name": "Part Analysis", "max": 10, "base": 500.0, "growth": 1.50, "dur_base": 1800.0, "dur_growth": 1.40, "effect": "+2% Scrap from salvage"},
	"crate_theory":  {"name": "Crate Theory",  "max": 10, "base": 600.0, "growth": 1.50, "dur_base": 1800.0, "dur_growth": 1.40, "effect": "-2% Field Crate cost"},
}

const IDS: Array = ["speed", "dmg", "hp", "coin", "xp", "startcash", "offcap", "offrate", "reroll", "labspeed", "part_analysis", "crate_theory"]

const SPEED_STEPS: Array = [1.0, 1.5, 2.0, 2.5]


static func max_of(id: String) -> int:
	var d: Dictionary = DEFS.get(id, {})
	return int(d.get("max", 0))

extends RefCounted
## Research Hall projects (SPEC A3, REDESIGN_SPEC §3.3). cost(L) =
## base*growth^L coins. Research is INSTANT (owner feedback #1: no research
## timers; the old dur_* fields and Lab Speed are gone). offcap = Storage Tech,
## offrate = Logistics Tech (ids kept for saves). "grid" grows the run grid
## 3x3 -> 5x5 -> 7x7 -> 8x8 -> 10x10 (TowerState.GRID_SIZES).

const DEFS: Dictionary = {
	"grid":      {"name": "Grid Expansion", "max": 4, "base": 60.0, "growth": 3.0, "effect": "Bigger run grid: 3x3 -> 5x5 -> 7x7 -> 8x8 -> 10x10"},
	"speed":     {"name": "Game Speed",    "max": 3,  "base": 400.0, "growth": 4.0,  "effect": "Unlocks a faster game speed"},
	"dmg":       {"name": "Damage",        "max": 30, "base": 80.0,  "growth": 1.8, "effect": "+5% damage (core & weapons)"},
	"hp":        {"name": "Health",        "max": 30, "base": 80.0,  "growth": 1.8, "effect": "+5% core max HP"},
	"coin":      {"name": "Coin Bonus",    "max": 20, "base": 60.0,  "growth": 1.35, "effect": "+5% coins"},
	"xp":        {"name": "XP Bonus",      "max": 20, "base": 50.0,  "growth": 1.35, "effect": "+4% run XP"},
	"startcash": {"name": "Starting Cash", "max": 15, "base": 40.0,  "growth": 1.40, "effect": "+$15 cash at run start"},
	"offcap":    {"name": "Storage Tech",  "max": 8,  "base": 150.0, "growth": 1.60, "effect": "+4% factory away time"},
	"offrate":   {"name": "Logistics Tech", "max": 5, "base": 120.0, "growth": 1.50, "effect": "+5% factory output value"},
	"reroll":    {"name": "Draft Reroll",  "max": 3,  "base": 250.0, "growth": 3.0,  "effect": "+1 free draft reroll per run"},
	"part_analysis": {"name": "Part Analysis", "max": 10, "base": 500.0, "growth": 1.50, "effect": "+2% Scrap from salvage"},
	"crate_theory":  {"name": "Crate Theory",  "max": 10, "base": 600.0, "growth": 1.50, "effect": "-2% Field Crate cost"},
}

const IDS: Array = ["grid", "speed", "dmg", "hp", "coin", "xp", "startcash", "offcap", "offrate", "reroll", "part_analysis", "crate_theory"]

const SPEED_STEPS: Array = [1.0, 1.5, 2.0, 2.5]


static func max_of(id: String) -> int:
	var d: Dictionary = DEFS.get(id, {})
	return int(d.get("max", 0))

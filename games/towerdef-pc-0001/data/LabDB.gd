extends RefCounted
## Research Hall projects (SPEC A3, REDESIGN_SPEC §3.3). cost(L) =
## base*growth^L coins. Research is INSTANT (owner feedback #1: no research
## timers; the old dur_* fields and Lab Speed are gone). offcap = Storage Tech,
## offrate = Logistics Tech (ids kept for saves). "grid" grows the V2 run grid
## 7x7 -> 9x9 -> ... -> 21x21 (TowerState.GRID_SIZES) at the V2 steep costs.
## A def with "costs" prices each step explicitly (the steep key researches);
## otherwise cost(L) = base * growth^L.

const DEFS: Dictionary = {
	"grid":      {"name": "Grid Expansion", "max": 7, "costs": [2000, 10000, 50000, 200000, 750000, 2500000, 8000000], "effect": "Bigger run grid: 7x7 -> 9x9 -> 11x11 ... -> 21x21"},
	"speed":     {"name": "Game Speed",    "max": 3,  "base": 400.0, "growth": 4.0,  "effect": "Unlocks a faster game speed"},
	"dmg":       {"name": "Damage",        "max": 30, "base": 80.0,  "growth": 1.8, "effect": "+5% damage (core & weapons)"},
	"hp":        {"name": "Health",        "max": 30, "base": 80.0,  "growth": 1.8, "effect": "+5% core max HP"},
	"coin":      {"name": "Coin Bonus",    "max": 20, "base": 60.0,  "growth": 1.35, "effect": "+5% coins"},
	"xp":        {"name": "XP Bonus",      "max": 20, "base": 50.0,  "growth": 1.35, "effect": "+4% run XP"},
	"startcash": {"name": "Starting Cash", "max": 15, "base": 40.0,  "growth": 1.40, "effect": "+$15 cash at run start"},
	"offcap":    {"name": "Storage Tech",  "max": 8,  "base": 150.0, "growth": 1.60, "effect": "+4% Outpost storage"},
	"offrate":   {"name": "Logistics Tech", "max": 5, "base": 120.0, "growth": 1.50, "effect": "+5% Outpost production"},
	"reroll":    {"name": "Draft Reroll",  "max": 3,  "base": 250.0, "growth": 3.0,  "effect": "+1 free draft reroll per run"},
	"core_theory": {"name": "Core Theory", "max": 5, "costs": [5000, 40000, 250000, 1500000, 8000000], "effect": "Unlocks Core levels 10 / 20 / 30 / 40 / 50"},
}

const IDS: Array = ["grid", "speed", "dmg", "hp", "coin", "xp", "startcash", "offcap", "offrate", "reroll", "core_theory"]

const SPEED_STEPS: Array = [1.0, 1.5, 2.0, 2.5]


static func max_of(id: String) -> int:
	var d: Dictionary = DEFS.get(id, {})
	return int(d.get("max", 0))

extends RefCounted
## Cores (REDESIGN_SYSTEMS §1.1, REDESIGN_SPEC §2.1 / R8). The Core is the only
## permanent object on the run grid: it sits on the centre cell, fires its own
## attack and produces cash/s. Ranges are in grid "cells" (TowerState converts
## with pc_cell_px). Hive is deferred (R8) and never ships in IDS.
##   attack: cannon | slag | beam | pulse  (TowerState._core_fire)
##   interest: fraction of banked cash paid per wave, capped at `icap` (wave-1
##   cash units; scaled by the run cash index like every cash amount).

const DEFS: Dictionary = {
	"bastion": {"name": "Bastion", "arch": "balanced", "dmg": 10.0, "rate": 1.25, "range": 4.0, "hp": 120.0, "regen": 1.0, "armor": 2.0, "cash": 2.0, "irate": 0.02, "icap": 50.0,
		"attack": "cannon", "splash": 0.5, "splash_frac": 0.4,
		"attack_name": "Auto Cannon", "attack_desc": "Shell at the nearest enemy; 0.5-cell splash at 40%",
		"trait": "steadfast", "trait_name": "Steadfast", "trait_desc": "+1% dmg and +1% cash/s per building on the grid (max 20)",
		"l20": "Double barrel: fires two shells"},
	"foundry": {"name": "Foundry", "arch": "eco", "dmg": 5.0, "rate": 1.0, "range": 3.5, "hp": 100.0, "regen": 0.8, "armor": 1.0, "cash": 4.0, "irate": 0.05, "icap": 150.0,
		"attack": "slag", "splash": 1.0, "slow": 0.2, "slow_t": 2.0,
		"attack_name": "Slag Spitter", "attack_desc": "Lobbed blob; 1-cell splash, 2 s slow (-20%)",
		"trait": "compound", "trait_name": "Compound", "trait_desc": "Interest cap +10 per Eco track level; eco picks 1.5x as likely",
		"l20": "Splash x1.5"},
	"lance": {"name": "Lance", "arch": "single", "dmg": 28.0, "rate": 0.5, "range": 5.5, "hp": 90.0, "regen": 0.6, "armor": 1.0, "cash": 1.5, "irate": 0.01, "icap": 30.0,
		"attack": "beam", "ramp": 0.15, "ramp_max": 1.5,
		"attack_name": "Charging Beam", "attack_desc": "Locks the highest-HP enemy in range; +15%/s while held (max +150%)",
		"trait": "focus", "trait_name": "Focus", "trait_desc": "+25% dmg vs bosses and elites; buildings in Core range -10% rate",
		"l20": "Max ramp +200%"},
	"tempest": {"name": "Tempest", "arch": "area", "dmg": 6.0, "rate": 0.8, "range": 3.0, "hp": 140.0, "regen": 1.2, "armor": 3.0, "cash": 1.8, "irate": 0.02, "icap": 40.0,
		"attack": "pulse", "knock": 0.3, "chain_every": 5, "chain_frac": 0.4, "chain_n": 3,
		"attack_name": "Pulse Ring", "attack_desc": "Ring to full range hits every enemy once; 0.3 s knockback",
		"trait": "static", "trait_name": "Static", "trait_desc": "Every 5th pulse chains 40% dmg to 3 targets beyond range",
		"l20": "Two rings per pulse"},
}

const IDS: Array = ["bastion", "foundry", "lance", "tempest"]
const MAX_LVL: int = 40
const MAX_LVL_CEILING: int = 50     # with the Reforge node core_ceiling
## Per-level multipliers (REDESIGN_SPEC §2.1).
const PER_LVL: Dictionary = {"dmg": 1.06, "hp": 1.05, "regen": 1.04, "cash": 1.04}
const UNLOCK_TEXT: Dictionary = {
	"bastion": "Starting Core",
	"foundry": "Clear Tier 2 (wave 30 on T2)",
	"lance": "Complete your first Core Reforge",
	"tempest": "Equip a 2-piece set and reach best wave 60",
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["bastion"])


static func has(id: String) -> bool:
	return DEFS.has(id)


## Stat multiplier of a Core at level L for one of PER_LVL's stats.
static func lvl_mult(stat: String, lvl: int) -> float:
	return pow(float(PER_LVL.get(stat, 1.0)), float(clampi(lvl, 1, MAX_LVL_CEILING) - 1))


## Breakpoint trait strength: x1.25 at L10, x1.5 at L30.
static func trait_mult(lvl: int) -> float:
	if lvl >= 30:
		return 1.5
	if lvl >= 10:
		return 1.25
	return 1.0

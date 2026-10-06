extends RefCounted
## The Core (V2_DESIGN: one Core). The Core is the only permanent object on the
## run grid: it sits on the centre, fires the equipped Weapon (P4: the Weapon
## frame decides the attack; until then the base attack below) and produces
## cash/s. Its look, Modules and colours are the player's build (CoreView).
## Ranges are in grid "cells" (TowerState converts with pc_cell_px).
##   attack: cannon | slag | beam | pulse  (TowerState._core_fire)
##   interest: fraction of banked cash paid per wave, capped at `icap` (wave-1
##   cash units; scaled by the run cash index like every cash amount).

const TuneRef := preload("res://Tune.gd")

const ID: String = "core"
const CORE: Dictionary = {"name": "Core", "dmg": 10.0, "rate": 1.25, "range": 4.0, "hp": 120.0, "regen": 1.0, "armor": 2.0, "cash": 2.0, "irate": 0.02, "icap": 50.0,
	"attack": "cannon", "splash": 0.5, "splash_frac": 0.4,
	"attack_name": "Auto Cannon", "attack_desc": "Shell at the nearest enemy; 0.5-cell splash at 40%"}

const MAX_LVL: int = 60
const MAX_LVL_CEILING: int = 75     # with the Reforge node core_ceiling
## Per-level multipliers.
const PER_LVL: Dictionary = {"dmg": 1.06, "hp": 1.05, "regen": 1.04, "cash": 1.04}


static func get_def(_id: String = ID) -> Dictionary:
	return CORE


static func has(id: String) -> bool:
	return id == ID


## Stat multiplier of the Core at level L for one of PER_LVL's stats.
static func lvl_mult(stat: String, lvl: int) -> float:
	return pow(float(PER_LVL.get(stat, 1.0)), float(clampi(lvl, 1, max_lvl_ceiling()) - 1))


## Level caps (Tune seams pc_core_max / pc_core_max_ceiling; defaults = the consts).
static func max_lvl() -> int:
	return TuneRef.int_of("pc_core_max", MAX_LVL)


static func max_lvl_ceiling() -> int:
	return TuneRef.int_of("pc_core_max_ceiling", MAX_LVL_CEILING)
